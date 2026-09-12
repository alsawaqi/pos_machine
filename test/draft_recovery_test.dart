import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/bill_combine/combine_store.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_models.dart';
import 'package:pos_machine/draft_recovery/recovery_controller.dart';
import 'package:pos_machine/draft_recovery/recovery_local.dart';
import 'package:pos_machine/draft_recovery/recovery_models.dart';
import 'package:pos_machine/draft_recovery/recovery_store.dart';

const billId = '11111111-1111-4111-8111-111111111111';
const seatId = '22222222-2222-4222-8222-222222222222';
const requestId = '33333333-3333-4333-8333-333333333333';
const recoveryId = '44444444-4444-4444-8444-444444444444';
const seatKey = '55555555-5555-4555-8555-555555555555';
final at = DateTime.utc(2026, 9, 12);

Map<String, dynamic> originalItem([int qty = 3]) => {
  'id': '7',
  'name': 'Coffee',
  'qty': qty,
  'basePrice': 1.0,
  'unitPrice': 1.0,
  'lineTotal': qty.toDouble(),
  'notes': 'Keep Exactly',
  'modifiers': [],
  'category': 'Drinks',
  'imageAsset': 'original.png',
  'detailLines': ['Keep Exactly'],
};
Map<String, dynamic> frozenLine([int qty = 2]) => {
  'product_id': 7,
  'qty': qty,
  'name': 'Coffee',
  'notes': 'Keep Exactly',
  'unit_price_baisas': 1000,
  'line_total_baisas': qty * 1000,
  'addons': [],
};
Map<String, dynamic> previewValue({bool legacy = false}) => {
  'recovery_policy': 'same_bill_recovery_v1',
  'preview_token': '1790000000.${'a' * 64}',
  'expires_at': '2026-09-12T10:00:00Z',
  'proof': {
    'proof_policy': 'same_bill_draft_v1',
    'read_only': true,
    'archive_authorized': false,
    'table_id': 1,
    'table_label': 'T1',
    'device_id': 1,
    'order_uuid': billId,
    'table_session_uuid': seatId,
    'kind': legacy ? 'legacy_hold' : 'staff_rounds',
    'delta_policy': 'proven_local_rounds_only',
    'bill': {
      'uuid': billId,
      'status': 'open',
      'source': 'qr_web',
      'receipt_number': null,
      'temp_reference': 'T-1',
      'subtotal_baisas': 3000,
      'tax_total_baisas': 0,
      'grand_total_baisas': 3000,
      'discount_total_baisas': 0,
      'comp_total_baisas': 0,
      'items': [
        {
          'id': 10,
          'status': 'open',
          'line_discount_baisas': 0,
          ...frozenLine(),
        },
        {
          'id': 11,
          'status': 'open',
          'line_discount_baisas': 0,
          ...frozenLine(1),
          'product_id': 9,
          'name': 'Customer water',
        },
      ],
    },
    'acknowledged': [
      {
        'client_event_id': requestId,
        if (!legacy) ...{
          'client_request_id': requestId,
          'seating_key': seatKey,
          'round_id': 20,
          'round_no': 1,
        },
        'lines': [
          {'order_item_id': 10, ...frozenLine()},
        ],
      },
    ],
  },
};

class RecoveryFake implements DraftRecoveryGateway, DineInGateway {
  Map<String, dynamic> previewJson = previewValue();
  final confirmations = <Map<String, dynamic>>[];
  final sent = <DineInRequest>[];
  int previews = 0;
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? reply;
  Future<Map<String, dynamic>> Function(DineInRequest)? roundReply;
  bool closed = false, wrongRound = false;
  String roundStatus = 'accepted';
  Map<String, dynamic> ack(Map<String, dynamic> input) => {
    'data': {
      'status': 'processed',
      'result': {
        'outcome': 'draft_recovered',
        'recovery_policy': 'same_bill_recovery_v1',
        'client_request_id': input['client_request_id'],
        'local_snapshot_hash': input['local_snapshot_hash'],
        'order_uuid': billId,
        'table_id': 1,
        'table_session_uuid': seatId,
        'preview_token': input['preview_token'],
        'event_id': 90,
        'archive_authorized': true,
      },
    },
    'errors': <dynamic>[],
  };
  @override
  Future<Map<String, dynamic>> preview(
    int tableId,
    Map<String, dynamic> query,
  ) async {
    previews++;
    return previewJson;
  }

  @override
  Future<Map<String, dynamic>> confirm(
    int tableId,
    Map<String, dynamic> payload,
  ) async {
    confirmations.add(recoveryMap(jsonDecode(jsonEncode(payload))));
    return reply?.call(payload) ?? ack(payload);
  }

  @override
  Future<DineInDetail> detail(int tableId) async => DineInDetail({
    'table': {'id': 1, 'label': 'T1'},
    'occupied': true,
    'orphaned': false,
    'seating': {
      'uuid': seatId,
      'table_id': 1,
      'status': 'open',
      'joined_table_ids': <int>[],
    },
    'bill': {
      'uuid': billId,
      'status': closed ? 'paid' : 'open',
      'source': 'qr_web',
      'charge': 'none',
      'grand_total_baisas': 4000,
      'items': <dynamic>[],
    },
    'rounds': sent.isEmpty
        ? <dynamic>[]
        : [
            {
              'id': 21,
              'round_no': 3,
              'entered_by': 'staff',
              'status': roundStatus,
              'client_request_id': wrongRound ? requestId : sent.last.id,
              'priced_lines': <dynamic>[],
            },
          ],
  });
  @override
  Future<Map<String, dynamic>> append(DineInRequest request) async {
    sent.add(request);
    return roundReply?.call(request) ??
        {
          'outcome': roundStatus == 'pending_confirmation'
              ? 'held'
              : 'replayed',
          'round_status': roundStatus,
          'order_uuid': billId,
          'table_session_uuid': seatId,
          'table_id': 1,
          'seating_key': request.payload['seating_key'],
          'round_id': 21,
          'round_no': 3,
          'total_baisas': 1000,
        };
  }

  @override
  Future<void> clear(int tableId) async =>
      fail('Recovery never clears a table');
  @override
  Future<void> reopen(String uuid) async =>
      fail('Recovery never reopens a bill');
  @override
  Future<void> review(
    DineInDetail detail,
    Map<String, dynamic> round,
    bool accept,
  ) async => fail('Recovery never reviews another round');
}

class RecoveryHarness {
  late Database db;
  late RecoveryStore store;
  final api = RecoveryFake();
  final outbox = <String, OrderOutboxRow>{};
  late RecoveryController controller;
  int retired = 0;
  bool blocked = false;
  Future<void> init({int qty = 3, bool legacy = false}) async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE held_orders (id TEXT PRIMARY KEY, order_type TEXT, draft_json TEXT)',
    );
    await db.execute(
      '''CREATE TABLE dining_tables (table_id TEXT PRIMARY KEY, status TEXT,
      draft_json TEXT, paid_at TEXT, paid_snapshot_json TEXT, primary_table_id TEXT,
      linked_table_ids_json TEXT, server_order_uuid TEXT, seating_uuid TEXT, seating_key TEXT,
      seating_state TEXT, winner_seating_uuid TEXT, occupied_at TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE local_table_rounds (client_request_id TEXT PRIMARY KEY,
      table_id TEXT, seating_key TEXT, local_round_no INTEGER, lines_json TEXT,
      submitted_at TEXT, printed_at TEXT, outbox_key TEXT, status TEXT,
      server_round_id INTEGER, server_round_no INTEGER, order_uuid TEXT,
      total_baisas INTEGER, review_reasons_json TEXT, held_lines_json TEXT, acked_at TEXT)''',
    );
    await db.execute(
      'CREATE TABLE local_line_cancellations (client_request_id TEXT PRIMARY KEY, table_id TEXT, cancelled_at TEXT)',
    );
    await db.execute('CREATE TABLE order_history (snapshot_json TEXT)');
    await CombineStore.createSchema(db);
    await RecoveryStore.createSchema(db);
    final draft = {
      'serverOrderUuid': billId,
      'orderReference': 'REF-1',
      'diningTableId': '1',
      'orderType': 'dine_in',
      'splitCount': 1,
      'discount': {'value': 0},
      'items': [originalItem(qty)],
    };
    await db.insert('held_orders', {
      'id': 'held-1',
      'order_type': 'dine_in',
      'draft_json': jsonEncode(draft),
    });
    await db.insert('dining_tables', {
      'table_id': '1',
      'status': 'occupied',
      'draft_json': jsonEncode(draft),
      'server_order_uuid': billId,
      'occupied_at': at.toIso8601String(),
      if (!legacy) ...{
        'seating_uuid': seatId,
        'seating_key': seatKey,
        'seating_state': 'open',
      },
    });
    if (!legacy) {
      final lines = [
        {'product_id': 7, 'qty': 2, 'notes': 'Keep Exactly'},
      ];
      const key = 'tbl:$seatKey:round:$requestId';
      await db.insert('local_table_rounds', {
        'client_request_id': requestId,
        'table_id': '1',
        'seating_key': seatKey,
        'local_round_no': 1,
        'lines_json': jsonEncode(lines),
        'submitted_at': at.toIso8601String(),
        'outbox_key': key,
        'status': 'appended',
        'server_round_id': 20,
        'server_round_no': 1,
        'order_uuid': billId,
        'total_baisas': 2000,
        'acked_at': at.toIso8601String(),
        'held_lines_json': '[]',
        'review_reasons_json': '[]',
      });
      outbox[key] = OrderOutboxRow(
        orderUuid: key,
        eventsJson: jsonEncode([
          {
            'client_event_id': requestId,
            'event_type': 'table.session.round',
            'payload': {
              'client_request_id': requestId,
              'table_id': 1,
              'seating_key': seatKey,
              'order_uuid': billId,
              'lines': lines,
            },
          },
        ]),
        createdAt: at,
        attempts: 0,
        serverRejections: 0,
        syncedAt: at,
      );
    }
    api.previewJson = previewValue(legacy: legacy);
    store = RecoveryStore(db, 'scope');
    controller = create();
  }

  Future<RecoveryLocal> local(int id) =>
      loadRecoveryLocal(db, id, outboxRow: (key) async => outbox[key]);
  RecoveryController create() => RecoveryController(
    store: store,
    gateway: api,
    dineIn: api,
    tableId: 1,
    loadLocal: local,
    checkIdle: () async {
      if (blocked) throw StateError('pending payment');
    },
    admit: (operation) => operation(),
    onRetired: (_) async {
      retired++;
    },
  );
  Future<void> close() async {
    controller.dispose();
    await db.close();
  }
}

void main() {
  sqfliteFfiInit();
  late RecoveryHarness h;
  setUp(() async {
    h = RecoveryHarness();
    await h.init();
  });
  tearDown(() => h.close());

  test(
    'proof removes only own acknowledged subset; customer items do not become a delta',
    () async {
      final local = await h.local(1), before = await h.db.query('held_orders');
      final delta = local.delta(RecoveryPreview(h.api.previewJson));
      expect(delta.single['qty'], 1);
      expect(delta.single['original'], originalItem());
      expect(local.items.single, originalItem());
      expect(await h.db.query('held_orders'), before);
      expect(local.hash, matches(RegExp(r'^[0-9a-f]{64}$')));
    },
  );
  test('preview is read-only and does not create a durable recovery', () async {
    await h.controller.start();
    expect(h.controller.error, isNull);
    expect(h.controller.canLeave, isTrue);
    expect(await h.store.active(), isNull);
    expect(h.api.confirmations, isEmpty);
    expect(await h.db.query('held_orders'), hasLength(1));
  });
  test(
    'acknowledgement atomically archives raw copies and preserves saved additions',
    () async {
      await h.controller.start();
      final local = h.controller.local!;
      h.api.reply = (payload) async {
        expect((await h.store.active())!.payload, payload);
        expect(await h.db.query('held_orders'), hasLength(1));
        return h.api.ack(payload);
      };
      await h.controller.confirm();
      final saved = (await h.store.active())!;
      expect(saved.state, 'delta_ready');
      expect(saved.local.encoded, local.encoded);
      expect(saved.delta.single['original'], originalItem());
      expect(await h.db.query('held_orders'), isEmpty);
      expect(await h.db.query('dining_tables'), isEmpty);
      expect(await h.db.query('local_table_rounds'), hasLength(1));
      expect(h.outbox, hasLength(1));
      expect(h.api.sent, isEmpty);
      await expectLater(
        RecoveryStore.assertNonePending(h.db),
        throwsStateError,
      );
      await expectLater(
        RecoveryStore.assertNotRetired(h.db, uuid: billId),
        throwsStateError,
      );
      await expectLater(
        RecoveryStore.assertNotRetired(h.db, tableId: '1', reference: 'REF-1'),
        throwsStateError,
      );
      await expectLater(
        RecoveryStore.assertNotRetired(
          h.db,
          tableId: '1',
          occupiedAt: at.toIso8601String(),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'lost recovery reply retries identical durable identity after restart',
    () async {
      h.api.reply = (_) async => throw StateError('lost reply');
      await h.controller.start();
      await h.controller.confirm();
      final first = h.api.confirmations.single;
      h.controller.dispose();
      h.controller = h.create();
      await h.controller.start();
      h.api.reply = (payload) async => h.api.ack(payload);
      await h.controller.confirm();
      expect(h.api.confirmations, [first, first]);
      expect(h.api.previews, 1);
      expect(h.controller.attempt!.state, 'delta_ready');
    },
  );
  test('double confirmation tap sends one request', () async {
    final gate = Completer<Map<String, dynamic>>();
    h.api.reply = (_) => gate.future;
    await h.controller.start();
    final run = h.controller.confirm();
    while (h.api.confirmations.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await h.controller.confirm();
    expect(h.api.confirmations, hasLength(1));
    gate.complete(h.api.ack(h.api.confirmations.single));
    await run;
  });
  test(
    'changed local copy after acknowledgement retains confirmed journal',
    () async {
      h.api.reply = (payload) async {
        await h.db.update('held_orders', {
          'draft_json': jsonEncode({'changed': true}),
        });
        return h.api.ack(payload);
      };
      await h.controller.start();
      await h.controller.confirm();
      expect((await h.store.active())!.state, 'confirmed');
      expect(await h.db.query('held_orders'), hasLength(1));
      expect((await h.store.active())!.local.items.single, originalItem());
    },
  );
  test(
    'a newly appeared duplicate blocks retirement without touching either copy',
    () async {
      await h.controller.start();
      h.api.reply = (payload) async {
        final row = (await h.db.query('held_orders')).single;
        await h.db.insert('held_orders', {...row, 'id': 'new-copy'});
        return h.api.ack(payload);
      };
      await h.controller.confirm();
      expect(await h.db.query('held_orders'), hasLength(2));
      expect((await h.store.active())!.state, 'confirmed');
    },
  );
  test(
    'archive transaction rolls back all copies, fence and completion on storage failure',
    () async {
      await h.db.execute(
        "CREATE TRIGGER stop_archive BEFORE DELETE ON held_orders BEGIN SELECT RAISE(ABORT, 'storage fault'); END",
      );
      await h.controller.start();
      await h.controller.confirm();
      expect((await h.store.active())!.state, 'confirmed');
      expect(await h.db.query('held_orders'), hasLength(1));
      expect(await h.db.query('dining_tables'), hasLength(1));
      expect(await h.db.query('draft_recovery_retired'), isEmpty);
      await h.db.execute('DROP TRIGGER stop_archive');
      h.controller.dispose();
      h.controller = h.create();
      await h.controller.start();
      await h.controller.confirm();
      expect(h.api.confirmations, hasLength(1));
      expect((await h.store.active())!.state, 'delta_ready');
    },
  );
  test(
    'explicit saved additions are journaled before network and retain ids after lost reply',
    () async {
      await h.controller.start();
      await h.controller.confirm();
      h.api.roundReply = (request) async {
        final saved = (await h.store.active())!;
        expect(saved.state, 'delta_pending');
        expect(saved.request.encoded, request.encoded);
        throw StateError('reply lost');
      };
      await h.controller.sendSavedAdditions();
      final first = h.api.sent.single;
      expect(first.payload['lines'], [
        {'product_id': 7, 'qty': 1, 'addon_ids': [], 'notes': 'Keep Exactly'},
      ]);
      expect(jsonEncode(first.payload), isNot(contains('price')));
      h.controller.dispose();
      h.controller = h.create();
      await h.controller.start();
      h.api.roundReply = null;
      await h.controller.sendSavedAdditions();
      expect(h.api.sent.map((r) => r.encoded), [first.encoded, first.encoded]);
      expect(h.controller.attempt!.state, 'done');
      expect(await h.store.active(), isNull);
      expect(
        (await h.store.read(h.controller.attempt!.id))!.local.items.single,
        originalItem(),
      );
    },
  );
  test(
    'wrong detail request identity cannot unlock after a plausible append acknowledgement',
    () async {
      await h.controller.start();
      await h.controller.confirm();
      h.api.wrongRound = true;
      await h.controller.sendSavedAdditions();
      expect((await h.store.active())!.state, 'delta_pending');
    },
  );
  test('closed same bill preserves unsent additions without posting', () async {
    await h.controller.start();
    await h.controller.confirm();
    h.api.closed = true;
    await h.controller.sendSavedAdditions();
    expect(h.api.sent, isEmpty);
    expect((await h.store.active())!.state, 'delta_ready');
  });
  test(
    'unidentified nonaccepted round result preserves immutable delta request',
    () async {
      await h.controller.start();
      await h.controller.confirm();
      h.api.roundReply = (_) async => {
        'outcome': 'held',
        'round_status': 'pending_confirmation',
      };
      await h.controller.sendSavedAdditions();
      expect((await h.store.active())!.state, 'delta_pending');
    },
  );
  for (final status in ['pending_confirmation', 'rejected']) {
    test(
      'exact recorded $status round is retained and returned to canonical review',
      () async {
        await h.controller.start();
        await h.controller.confirm();
        h.api.roundStatus = status;
        await h.controller.sendSavedAdditions();
        expect(h.controller.error, isNull);
        expect(h.controller.attempt!.state, 'done');
        expect(h.api.sent, hasLength(1));
        expect(h.controller.attempt!.json['delta_ack']['round_status'], status);
        expect(
          h.controller.attempt!.json['delta_round']['client_request_id'],
          h.api.sent.single.id,
        );
        expect(h.controller.attempt!.delta.single['original'], originalItem());
      },
    );
  }
  test(
    'only exact final no-write release unlocks the unchanged original',
    () async {
      h.api.reply = (payload) async => {
        'errors': [
          {'code': 'draft_recovery_preview_stale'},
        ],
        'draft_recovery_final_no_write': {...payload, 'table_id': 1},
      };
      await h.controller.start();
      await h.controller.confirm();
      expect(h.controller.attempt!.state, 'not_applied');
      expect(await h.db.query('held_orders'), hasLength(1));
      expect(await h.db.query('draft_recovery_retired'), isEmpty);
    },
  );
  test('wrong no-write release remains pending', () async {
    h.api.reply = (payload) async => {
      'errors': [
        {'code': 'draft_recovery_preview_stale'},
      ],
      'draft_recovery_final_no_write': {...payload, 'table_id': 2},
    };
    await h.controller.start();
    await h.controller.confirm();
    expect((await h.store.active())!.state, 'pending');
  });
  for (final field in [
    'order_uuid',
    'client_request_id',
    'local_snapshot_hash',
    'table_id',
    'table_session_uuid',
    'preview_token',
    'archive_authorized',
    'event_id',
    'outcome',
  ]) {
    test('mismatched $field acknowledgement never archives', () async {
      h.api.reply = (payload) async {
        final response = h.api.ack(payload);
        (response['data'] as Map)['result'][field] = null;
        return response;
      };
      await h.controller.start();
      await h.controller.confirm();
      expect((await h.store.active())!.state, 'pending');
      expect(await h.db.query('held_orders'), hasLength(1));
    });
  }
  for (final status in [
    'queued',
    'held',
    'merged',
    'replayed',
    'bill_terminal',
    'failed',
  ]) {
    test('local $status round is not acknowledged baseline evidence', () async {
      await h.db.update('local_table_rounds', {'status': status});
      await expectLater(h.local(1), throwsStateError);
    });
  }
  test('cancelled history never becomes a guessed delta', () async {
    await h.db.insert('local_line_cancellations', {
      'client_request_id': recoveryId,
      'table_id': '1',
    });
    await expectLater(h.local(1), throwsStateError);
  });
  test('unknown durable state and wrong scope block admission', () async {
    await h.db.insert('draft_recovery_journal', {
      'id': recoveryId,
      'scope': 'different',
      'state': 'unexpected',
      'payload': '{}',
    });
    await expectLater(
      RecoveryStore.assertNonePending(h.db),
      throwsFormatException,
    );
    await expectLater(h.store.assertOwn(null), throwsA(anything));
    await h.controller.start();
    expect(h.controller.error, isNotNull);
    expect(h.api.previews, 0);
  });
  test('missing recovery schema fails closed', () async {
    await h.db.execute('DROP TABLE draft_recovery_journal');
    await expectLater(RecoveryStore.assertNonePending(h.db), throwsA(anything));
  });
  test('payment work and background cannot approve a recovery', () async {
    h.blocked = true;
    await h.controller.start();
    expect(h.api.previews, 0);
    h.blocked = false;
    await h.controller.start();
    h.controller.setForeground(false);
    await h.controller.confirm();
    expect(h.api.confirmations, isEmpty);
  });
  test('staff-only bill keeps its only local payment draft', () async {
    recoveryMap(h.api.previewJson['proof']);
    (h.api.previewJson['proof'] as Map)['bill']['source'] = 'main_pos';
    await h.controller.start();
    expect(h.controller.error, contains('staff-only checkout'));
    expect(h.api.confirmations, isEmpty);
    expect(await h.db.query('held_orders'), hasLength(1));
  });
  for (final mutate in <String, void Function(Map<String, dynamic>)>{
    'wrong notes': (p) =>
        p['acknowledged'][0]['lines'][0]['notes'] = 'keep exactly',
    'unknown owned item': (p) =>
        p['acknowledged'][0]['lines'][0]['order_item_id'] = 999,
    'bad subtotal': (p) => p['bill']['subtotal_baisas'] = 9000,
    'bad quantity': (p) => p['acknowledged'][0]['lines'][0]['qty'] = 1.5,
    'duplicate owner': (p) => (p['acknowledged'][0]['lines'] as List).add(
      Map<String, dynamic>.from(p['acknowledged'][0]['lines'][0] as Map),
    ),
    'wrong source event': (p) =>
        p['acknowledged'][0]['client_event_id'] = recoveryId,
  }.entries) {
    test('proof ${mutate.key} cannot retire local copies', () async {
      mutate.value(h.api.previewJson['proof'] as Map<String, dynamic>);
      await h.controller.start();
      expect(h.controller.error, isNotNull);
      expect(await h.db.query('held_orders'), hasLength(1));
      expect(await h.store.active(), isNull);
    });
  }
  test(
    'legacy exact zero-delta recovery archives without sending a round',
    () async {
      await h.close();
      h = RecoveryHarness();
      await h.init(qty: 2, legacy: true);
      await h.controller.start();
      expect(h.controller.error, isNull);
      await h.controller.confirm();
      expect(h.controller.attempt!.state, 'done');
      expect(h.api.sent, isEmpty);
      expect(h.api.confirmations.single.keys, isNot(contains('event_ids')));
    },
  );
  test('legacy extra local quantity remains preserved and blocked', () async {
    await h.close();
    h = RecoveryHarness();
    await h.init(legacy: true);
    await h.controller.start();
    expect(h.controller.error, isNotNull);
    expect(await h.db.query('held_orders'), hasLength(1));
    expect(h.api.confirmations, isEmpty);
  });
  test(
    'legacy equal quantity cannot hide a changed original line multiset',
    () async {
      await h.close();
      h = RecoveryHarness();
      await h.init(qty: 2, legacy: true);
      for (final table in ['held_orders', 'dining_tables']) {
        final row = (await h.db.query(table)).single;
        final draft = recoveryMap(jsonDecode(row['draft_json'] as String));
        draft['items'] = [originalItem(1), originalItem(1)];
        await h.db.update(table, {'draft_json': jsonEncode(draft)});
      }
      await h.controller.start();
      expect(h.controller.error, contains('multiset'));
      expect(h.api.confirmations, isEmpty);
      expect(await h.db.query('held_orders'), hasLength(1));
    },
  );
  test('terminal state cannot be inserted as a new recovery', () async {
    await h.controller.start();
    await h.controller.confirm();
    await expectLater(h.store.create(h.controller.attempt!), throwsStateError);
  });
  test(
    'release proof survives restart and cannot be removed from a released journal',
    () async {
      h.api.reply = (payload) async => {
        'errors': [
          {'code': 'draft_recovery_preview_stale'},
        ],
        'draft_recovery_final_no_write': {...payload, 'table_id': 1},
      };
      await h.controller.start();
      await h.controller.confirm();
      final saved = (await h.store.read(h.controller.attempt!.id))!;
      expect(saved.json['release'], {...saved.payload, 'table_id': 1});
      expect(
        () => RecoveryAttempt({...saved.json}..remove('release')),
        throwsFormatException,
      );
    },
  );
  test(
    'unsupported saved addition quantity is refused before archiving',
    () async {
      await h.close();
      h = RecoveryHarness();
      await h.init(qty: 102);
      await h.controller.start();
      expect(h.controller.error, isNotNull);
      expect(h.api.confirmations, isEmpty);
      expect(await h.db.query('held_orders'), hasLength(1));
    },
  );
  test('missing auxiliary fence cannot resurrect an archived bill', () async {
    await h.close();
    h = RecoveryHarness();
    await h.init(qty: 2, legacy: true);
    await h.controller.start();
    await h.controller.confirm();
    expect(h.controller.attempt!.state, 'done');
    await h.db.delete('draft_recovery_retired');
    await expectLater(
      RecoveryStore.assertNotRetired(h.db, uuid: billId),
      throwsStateError,
    );
    await expectLater(
      RecoveryStore.assertNotRetired(h.db, tableId: '1', reference: 'REF-1'),
      throwsStateError,
    );
  });
  test(
    'corrupt completed payload fails closed for mutation and retirement guards',
    () async {
      await h.db.insert('draft_recovery_journal', {
        'id': recoveryId,
        'scope': 'scope',
        'state': 'done',
        'payload': '{broken',
      });
      await expectLater(
        RecoveryStore.assertNonePending(h.db),
        throwsFormatException,
      );
      await expectLater(
        RecoveryStore.assertNotRetired(h.db, uuid: billId),
        throwsFormatException,
      );
    },
  );
}
