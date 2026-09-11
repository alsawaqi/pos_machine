import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/qr_quick/qr_quick_controller.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'package:pos_machine/qr_quick/qr_quick_store.dart';

Map<String, dynamic> quickJson({
  String uuid = 'bill-1',
  String charge = 'none',
  String status = 'held',
  int total = 1000,
}) => {
  'uuid': uuid,
  'source': 'qr_web',
  'order_type': 'quick',
  'table_id': null,
  'temp_reference': 'Q-007',
  'grand_total_baisas': total,
  'status': status,
  'charge': charge,
  'session': 'live',
  'phone_tail': '1234',
  'age_seconds': 60,
  'items': [
    {'id': 1, 'product_name': 'Coffee', 'qty': 1.0, 'line_total_baisas': 1000},
  ],
  'actions': {
    'settle': status == 'held' && charge == 'none',
    'to_counter': status == 'awaiting_payment' && charge == 'none',
  },
};

class MemoryQuickStore implements QrQuickStore {
  final data = <String, QrQuickRequest>{};
  bool failSave = false, failRemove = false;
  @override
  Future<List<QrQuickRequest>> load() async => data.values.toList();
  @override
  Future<void> save(QrQuickRequest r) async {
    if (failSave || data.containsKey(r.orderUuid)) throw StateError('disk');
    data[r.orderUuid] = r;
  }

  @override
  Future<void> remove(QrQuickRequest r) async {
    if (failRemove) throw StateError('disk');
    data.remove(r.orderUuid);
  }
}

class FakeQuickGateway implements QrQuickGateway {
  List<QrQuickOrder> orders = [QrQuickOrder(quickJson())];
  final requests = <QrQuickRequest>[];
  final accepted = <String>{};
  bool lostResponse = false, failFetch = false, malformed = false;
  QrQuickFailure? refusal;
  Completer<void>? wait;
  int mutations = 0, fetches = 0, moves = 0;
  @override
  Future<List<QrQuickOrder>> fetch() async {
    fetches++;
    if (failFetch) throw StateError('offline');
    return orders;
  }

  @override
  Future<void> move(String uuid) async {
    moves++;
    orders = [QrQuickOrder(quickJson(uuid: uuid))];
  }

  @override
  Future<Map<String, dynamic>> append(QrQuickRequest request) async {
    requests.add(request);
    if (wait != null) await wait!.future;
    if (refusal != null) throw refusal!;
    final replayed = !accepted.add(request.id);
    if (!replayed) mutations++;
    orders = [QrQuickOrder(quickJson(uuid: request.orderUuid, total: 1200))];
    if (lostResponse) throw TimeoutException('Response lost AFTER commit');
    if (malformed) return {'order': quickJson(uuid: 'another-bill')};
    return {
      'order': orders.first.json,
      'addition': {
        'id': 3,
        'round_no': 1,
        'subtotal_baisas': 200,
        'tax_baisas': 0,
        'total_baisas': 200,
        'priced_lines': [
          for (var i = 0; i < request.lines.length; i++)
            {...request.lines[i].toJson(), 'order_item_id': i + 2},
        ],
      },
      'replayed': replayed,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryQuickStore store;
  late FakeQuickGateway api;
  late QrQuickController c;
  setUp(() async {
    store = MemoryQuickStore();
    api = FakeQuickGateway();
    c = QrQuickController(api, store);
    await c.start();
  });
  tearDown(() => c.dispose());
  test(
    'unpriced payload has ONLY product/qty/addons/notes and request id',
    () async {
      expect(
        await c.add('bill-1', [
          QrQuickLine(7, 2, [9], notes: 'Warm'),
        ]),
        true,
      );
      expect(api.requests.single.payload.keys.toSet(), {
        'client_request_id',
        'lines',
      });
      expect(api.requests.single.payload['lines'], [
        {
          'product_id': 7,
          'qty': 2,
          'addon_ids': [9],
          'notes': 'Warm',
        },
      ]);
      expect(api.requests.single.orderUuid, 'bill-1');
      expect(c.find('bill-1')!.reference, 'Q-007');
      expect(c.find('bill-1')!.total, 1200);
      expect(store.data, isEmpty);
      expect(api.mutations, 1);
    },
  );
  test(
    'lost acknowledgement then restart keeps exact UUID and payload; one addition',
    () async {
      api.lostResponse = true;
      expect(
        await c.add('bill-1', [
          QrQuickLine(7, 2, [9]),
        ]),
        false,
      );
      final original = jsonEncode(store.data.values.single.payload);
      expect(c.canAdd('bill-1'), false);
      expect(c.canPay('bill-1'), false);
      expect(await c.add('bill-1', [QrQuickLine(8, 1, [])]), false);
      c.dispose();
      c = QrQuickController(api, store);
      await c.start();
      api.lostResponse = false;
      expect(await c.retry('bill-1'), true);
      expect(api.requests.map((r) => jsonEncode(r.payload)).toList(), [
        original,
        original,
      ]);
      expect(api.mutations, 1);
      expect(store.data, isEmpty);
    },
  );
  test(
    'retry remains available after paid bill disappears from pending list',
    () async {
      api.lostResponse = true;
      await c.add('bill-1', [QrQuickLine(7, 1, [])]);
      api.orders = [];
      await c.refresh();
      expect(c.find('bill-1'), null);
      expect(c.pending, contains('bill-1'));
      api.lostResponse = false;
      expect(await c.retry('bill-1'), true);
      expect(api.mutations, 1);
    },
  );
  test('durable write failure prevents any send and further actions', () async {
    store.failSave = true;
    expect(await c.add('bill-1', [QrQuickLine(7, 1, [])]), false);
    expect(api.requests, isEmpty);
    expect(c.ready, false);
    expect(c.canPay('bill-1'), false);
  });
  test(
    'delete failure after acceptance retains request for safe replay',
    () async {
      store.failRemove = true;
      await c.add('bill-1', [QrQuickLine(7, 1, [])]);
      expect(c.pending, contains('bill-1'));
      store.failRemove = false;
      expect(await c.retry('bill-1'), true);
      expect(api.mutations, 1);
    },
  );
  test('double tap while post is running sends once', () async {
    api.wait = Completer<void>();
    final first = c.add('bill-1', [QrQuickLine(7, 1, [])]);
    await Future<void>.delayed(Duration.zero);
    expect(await c.add('bill-1', [QrQuickLine(7, 1, [])]), false);
    expect(c.canPay('bill-1'), false);
    expect(api.requests.length, 1);
    api.wait!.complete();
    expect(await first, true);
  });
  for (final code in [
    'product_unavailable',
    'addon_unavailable',
    'addon_selection_invalid',
    'invalid_catalogue_line',
    'validation_failed',
    'charge_already_claimed',
    'qr_charge_recovery_required',
    'order_not_editable',
  ]) {
    test(
      'fresh no-write $code preserves bill and allows review, never queues',
      () async {
        final before = jsonEncode(api.orders.single.json);
        api.refusal = QrQuickFailure(code, 'Refused', refused: true);
        expect(await c.add('bill-1', [QrQuickLine(7, 1, [])]), false);
        expect(store.data, isEmpty);
        expect(api.mutations, 0);
        expect(jsonEncode(c.orders.single.json), before);
        expect(c.notice, code);
      },
    );
  }
  test('later refusal cannot erase an earlier uncertain addition', () async {
    api.lostResponse = true;
    await c.add('bill-1', [QrQuickLine(7, 1, [])]);
    api.refusal = const QrQuickFailure(
      'order_not_found',
      'Refused',
      refused: true,
    );
    expect(await c.retry('bill-1'), false);
    expect(store.data, contains('bill-1'));
    expect(c.canPay('bill-1'), false);
    expect(api.mutations, 1);
  });
  test('wrong-bill or malformed success is not acknowledgement', () async {
    api.malformed = true;
    await c.add('bill-1', [QrQuickLine(7, 1, [])]);
    expect(store.data, contains('bill-1'));
    expect(c.notice, 'uncertain');
  });
  for (final charge in ['live_claim', 'uncertain', 'declined', 'cancelled']) {
    test('$charge blocks new additions and payment', () async {
      api.orders = [QrQuickOrder(quickJson(charge: charge))];
      await c.refresh();
      expect(c.canAdd('bill-1'), false);
      expect(c.canPay('bill-1'), false);
      expect(await c.add('bill-1', [QrQuickLine(7, 1, [])]), false);
      expect(api.requests, isEmpty);
    });
  }
  test('station route requires explicit safe to-counter first', () async {
    api.orders = [QrQuickOrder(quickJson(status: 'awaiting_payment'))];
    await c.refresh();
    expect(c.canAdd('bill-1'), false);
    expect(api.moves, 0);
    await c.move('bill-1');
    expect(api.moves, 1);
    expect(c.canAdd('bill-1'), true);
  });
  test(
    'failed refresh disables actions and never automatically resends',
    () async {
      api.failFetch = true;
      await c.refresh();
      expect(c.stale, true);
      expect(await c.add('bill-1', [QrQuickLine(7, 1, [])]), false);
      expect(api.requests, isEmpty);
    },
  );
  test('non-quick, non-QR and table rows fail closed', () {
    for (final change in [
      {'source': 'staff'},
      {'order_type': 'dine_in'},
      {'table_id': 1},
      {'grand_total_baisas': '1'},
    ]) {
      expect(
        () => QrQuickOrder({...quickJson(), ...change}),
        throwsFormatException,
      );
    }
  });
  test('line limits, uniqueness and monetary-key rejection', () {
    for (final qty in [0, 100]) {
      expect(() => QrQuickLine(7, qty, []), throwsFormatException);
    }
    expect(() => QrQuickLine(7, 1, [2, 2]), throwsFormatException);
    expect(
      () => QrQuickLine.fromJson({
        'product_id': 7,
        'qty': 1,
        'addon_ids': [],
        'price': 1,
      }),
      throwsFormatException,
    );
    expect(
      () => QrQuickRequest('bill-1', 'request', []),
      throwsFormatException,
    );
    expect(
      QrQuickRequest.newId(),
      matches(
        RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ),
      ),
    );
  });
  test(
    'SQLite journal persists, is scope-isolated and never overwrites pending',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await SqliteQrQuickStore.createSchema(db);
      final first = SqliteQrQuickStore(db, 'server/company/branch/device');
      final request = QrQuickRequest('bill-1', 'req-1', [
        QrQuickLine(7, 1, []),
      ]);
      await first.save(request);
      final restarted = SqliteQrQuickStore(db, 'server/company/branch/device');
      expect((await restarted.load()).single.payload, request.payload);
      expect(await SqliteQrQuickStore(db, 'other-device').load(), isEmpty);
      await expectLater(
        first.save(QrQuickRequest('bill-1', 'req-2', [QrQuickLine(8, 1, [])])),
        throwsA(isA<DatabaseException>()),
      );
      await first.remove(
        QrQuickRequest('bill-1', 'wrong-id', [QrQuickLine(7, 1, [])]),
      );
      expect(await first.load(), hasLength(1));
      await restarted.remove(request);
      expect(await first.load(), isEmpty);
    },
  );
}
