import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/data/table_sync_coordinator.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/table_sync_models.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/services/pos_api_service.dart';

const _winner = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
const _serverSeat = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _product = Product(id: '10', name: 'Latte', category: 'Coffee', price: 2);

DiningTableSession _session({String tableId = '5', int qty = 2}) {
  final at = DateTime.now().toUtc();
  return DiningTableSession(
    tableId: tableId,
    floorId: '1',
    status: DiningTableStatus.occupied,
    updatedAt: at,
    occupiedAt: at,
    orderReference: 'LOCAL-$tableId',
    draft: OrderSessionDraft(
      orderReference: 'LOCAL-$tableId',
      orderType: OrderType.dineIn,
      selectedCategory: 'Coffee',
      customerReferenceNumber: '',
      diningFloorId: '1',
      diningFloorLabel: 'Main',
      diningTableId: tableId,
      diningTableName: 'Table $tableId',
      items: [CartItem(product: _product, qty: qty)],
      discount: const DiscountConfiguration(),
      splitCount: 1,
    ),
  );
}

class _Ledger implements TableLedgerStore {
  final tables = <String, DiningTableSession>{};
  final rounds = <String, LocalTableRound>{};
  final cancellations = <String, LocalLineCancellation>{};
  final verdicts = <TableSyncVerdict>[];
  final writes = <Map<String, Object?>>[];
  @override
  Future<void> saveLocalTableRound(LocalTableRound round) async {
    rounds[round.clientRequestId] = round;
  }

  @override
  Future<List<LocalTableRound>> readLocalTableRounds({
    String? tableId,
    String? seatingKey,
  }) async => rounds.values
      .where(
        (r) =>
            (tableId == null || r.tableId == tableId) &&
            (seatingKey == null || r.seatingKey == seatingKey),
      )
      .toList();
  @override
  Future<void> saveLocalLineCancellation(LocalLineCancellation c) async {
    cancellations[c.clientRequestId] = c;
  }

  @override
  Future<List<LocalLineCancellation>> readLocalLineCancellations({
    String? tableId,
    String? seatingKey,
  }) async => cancellations.values
      .where(
        (c) =>
            (tableId == null || c.tableId == tableId) &&
            (seatingKey == null || c.seatingKey == seatingKey),
      )
      .toList();
  @override
  Future<int> addTableSyncVerdict(TableSyncVerdict verdict) async {
    final id = verdicts.length + 1;
    verdicts.add(TableSyncVerdict.fromRow({...verdict.toRow(), 'id': id}));
    return id;
  }

  @override
  Future<List<TableSyncVerdict>> readTableSyncVerdicts({
    bool unseenOnly = false,
    int limit = 200,
  }) async => verdicts.reversed
      .where((v) => !unseenOnly || !v.seen)
      .take(limit)
      .toList();
  @override
  Future<void> markTableSyncVerdictsSeen(List<int> ids) async {
    for (var i = 0; i < verdicts.length; i++) {
      if (ids.contains(verdicts[i].id)) {
        verdicts[i] = TableSyncVerdict.fromRow({
          ...verdicts[i].toRow(),
          'seen': 1,
        });
      }
    }
  }

  @override
  Future<void> updateTableSyncFields(
    String id,
    Map<String, Object?> fields,
  ) async {
    expect(fields.keys, isNot(contains('status')));
    writes.add(Map.of(fields));
    final s = tables[id];
    if (s == null) return;
    final bill = fields['server_order_uuid'] as String?;
    tables[id] = s.copyWith(
      seatingKey: fields['seating_key'] as String?,
      seatingUuid: fields['seating_uuid'] as String?,
      seatingState: fields['seating_state'] as String?,
      serverOrderUuid: bill,
      draft: s.draft?.copyWith(serverOrderUuid: bill),
      tempReference: fields['temp_reference'] as String?,
      winnerSeatingUuid: fields['winner_seating_uuid'] as String?,
      lastVerdict: fields['last_verdict'] as String?,
      lastVerdictAt: DateTime.tryParse(
        fields['last_verdict_at']?.toString() ?? '',
      ),
    );
  }
}

class _AckAdapter implements HttpClientAdapter {
  bool online = true;
  bool failed = false;
  final batches = <List<Map<String, dynamic>>>[];
  Map<String, dynamic> Function(Map<String, dynamic>)? answer;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!online) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'offline',
      );
    }
    final events = ((options.data as Map)['events'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    batches.add(events);
    return ResponseBody.fromString(
      jsonEncode({
        'data': {
          'results': [
            for (final event in events)
              {
                'client_event_id': event['client_event_id'],
                'status': failed ? 'failed' : 'processed',
                'result': failed
                    ? {'error': 'payment total mismatch'}
                    : (answer?.call(event) ?? _answer(event)),
              },
          ],
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  Map<String, dynamic> _answer(Map<String, dynamic> event) {
    final p = event['payload'] as Map;
    final kind = (event['event_type'] as String).split('.').last;
    final outcome = switch (kind) {
      'open' => 'opened',
      'round' => 'appended',
      'move' => 'moved',
      'join' => 'joined',
      'close' => 'closed',
      'cancel_line' => 'cancelled',
      _ => 'processed',
    };
    return {
      'outcome': outcome,
      'status': kind == 'pay' ? 'paid' : 'processed',
      'table_session_uuid': _serverSeat,
      'temp_reference': 'T-0906-001',
      'order_uuid': p['order_uuid'],
      if (kind == 'round') ...{
        'round_id': 10,
        'round_no': 1,
        'total_baisas': 4000,
        'review_reasons': [],
        'held_lines': [],
      },
      if (kind == 'cancel_line') 'cancelled_qty': p['qty'],
    };
  }

  @override
  void close({bool force = false}) {}
}

class _Harness {
  _Harness() {
    dio = Dio(BaseOptions(baseUrl: 'https://pos.test'))
      ..httpClientAdapter = adapter;
    outbox = OrderSyncRepository(
      PosApiService(tokenGetter: () => 'device-token', dio: dio),
      db,
    );
    coordinator = TableSyncCoordinator(
      outbox: outbox,
      store: ledger,
      loadSessions: () async => ledger.tables.values.toList(),
      mode: () => mode,
      degraded: () => !adapter.online,
      staffId: () => 7,
      stockModeForProduct: (id) => stockModes[id],
      clock: () => now,
      newUuid: () =>
          '00000000-0000-4000-8000-${(++next).toString().padLeft(12, '0')}',
      markPrinted: (id) async {
        printed.add(id);
      },
      bindBillIdentity: (s, old, bill) {
        bindings.add([s.tableId, old, bill]);
      },
    );
    ledger.tables['5'] = _session();
    addTearDown(() async {
      await coordinator.settled;
      await coordinator.dispose();
      await outbox.dispose();
      dio.close(force: true);
      await db.close();
    });
  }
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final adapter = _AckAdapter();
  final ledger = _Ledger();
  late final Dio dio;
  late final OrderSyncRepository outbox;
  late final TableSyncCoordinator coordinator;
  final printed = <String>{};
  final bindings = <List<String>>[];
  final stockModes = <int, String?>{10: 'unit'};
  var mode = 'live';
  var now = DateTime.now().toUtc();
  var next = 0;
  DiningTableSession get table => ledger.tables['5']!;
  List<Map<String, dynamic>> get events =>
      adapter.batches.expand((b) => b).toList();

  Future<void> open() async {
    coordinator.onTableOccupied(table);
    await coordinator.settled;
    if (coordinator.lastError case final Object error) throw error;
  }

  Future<void> queuePay(String key, String bill, {bool synced = false}) async {
    await db.enqueueOutbox(
      OrderOutboxCompanion(
        orderUuid: Value(key),
        createdAt: Value(now),
        syncedAt: Value(synced ? now : null),
        eventsJson: Value(
          jsonEncode([
            buildOrderPayEvent(
              OrderSnapshot.initial().copyWith(serverOrderUuid: bill, total: 4),
              now: now,
              newUuid: () => 'pay-$key',
            ),
          ]),
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in ['off', 'shadow']) {
    test(
      '$mode: every hook produces zero rows and no identity writes',
      () async {
        final h = _Harness()..mode = mode;
        final c = h.coordinator;
        c.onTableOccupied(h.table);
        c.onTableDraftPersisted(h.table);
        c.onTableLeft('5');
        c.onTableTransferred('5', _session(tableId: '6'));
        c.onTablesJoined(h.table, _session(tableId: '6'));
        c.onTablesCleared({'5'}, h.table);
        c.onTablePaid(h.table, OrderSnapshot.initial());
        await c.settled;
        expect(await h.db.pendingOutbox(), isEmpty);
        expect(h.events, isEmpty);
        expect(h.ledger.writes, isEmpty);
        expect(h.ledger.rounds, isEmpty);
      },
    );
  }

  test(
    'live emission: durable open/round keys, proposal, no prices or GPS',
    () async {
      final h = _Harness();
      await h.open();
      final open = h.events.single;
      final opening = open['payload'] as Map;
      expect(open['event_type'], 'table.session.open');
      expect(opening['queued_offline'], false);
      expect(opening['table_id'], 5);
      expect(opening['staff_id'], 7);
      expect(opening['joined_table_ids'], []);
      final round = await h.coordinator.sendRound(h.table);
      expect(round!.status, 'appended');
      expect(round.serverRoundId, 10);
      final event = h.events.last;
      final payload = event['payload'] as Map;
      expect(payload['order_uuid'], opening['order_uuid']);
      expect(payload['lines'], [
        {'product_id': 10, 'qty': 2},
      ]);
      expect(payload['printed_at'], isNull);
      expect(
        await h.outbox.rowForKey(
          'tbl:${h.table.seatingKey}:round:${round.clientRequestId}',
        ),
        isNotNull,
      );
      expect(payload.keys, isNot(contains('gps')));
      expect(jsonEncode(payload), isNot(contains('price')));
      expect(jsonEncode(payload), isNot(contains('discount')));
      expect(jsonEncode(payload), isNot(contains('loyalty')));
      expect(h.table.status, DiningTableStatus.occupied);
      expect(h.table.seatingState, 'open');
    },
  );

  test(
    'offline flag is computed at creation and retained after recovery',
    () async {
      final h = _Harness();
      h.adapter.online = false;
      await h.open();
      await h.coordinator.sendRound(h.table);
      final pending = await h.db.pendingOutbox();
      expect(pending, hasLength(2));
      for (final row in pending) {
        final event = (jsonDecode(row.eventsJson) as List).single as Map;
        expect((event['payload'] as Map)['queued_offline'], true);
      }
      h.adapter.online = true;
      await h.outbox.flush();
      expect(
        h.events.every((e) => (e['payload'] as Map)['queued_offline'] == true),
        isTrue,
      );
    },
  );

  test(
    'over-300-second row becomes offline at flush, without changing its ID',
    () async {
      final h = _Harness();
      h.now = DateTime.now().toUtc().subtract(const Duration(seconds: 301));
      await h.open();
      final event = h.events.single;
      expect((event['payload'] as Map)['queued_offline'], true);
      expect(event['client_event_id'], h.table.seatingKey);
    },
  );

  test(
    'same-pass rebind updates pending pay/void, never synced or QR pay rows',
    () async {
      final h = _Harness();
      h.adapter.online = false;
      await h.open();
      await h.coordinator.sendRound(h.table);
      final original = h.table.serverOrderUuid!;
      await h.queuePay(original, original);
      await h.outbox.enqueueEvent(
        '$original:void',
        buildOrderVoidEvent(orderUuid: original, newUuid: () => 'void-id'),
      );
      await h.queuePay('already-synced', original, synced: true);
      await h.queuePay('$original:pay', original);
      final syncedBefore = (await h.outbox.rowForKey('already-synced'))!
          .eventsJson;
      h.adapter.answer = (event) => {
        ...h.adapter._answer(event),
        'order_uuid': _winner,
        if (event['event_type'] == 'table.session.open') ...{
          'outcome': 'attached',
          'winner_table_session_uuid': _serverSeat,
        },
      };
      h.adapter.online = true;
      await h.outbox.flush();
      final pay = h.events.firstWhere(
        (e) =>
            e['event_type'] == 'order.pay' &&
            e['client_event_id'] == 'pay-$original',
      );
      final voidEvent = h.events.firstWhere(
        (e) => e['event_type'] == 'order.void',
      );
      expect((pay['payload'] as Map)['order_uuid'], _winner);
      expect((voidEvent['payload'] as Map)['order_uuid'], _winner);
      expect(voidEvent['client_event_id'], 'void-id');
      expect(
        (await h.outbox.rowForKey('already-synced'))!.eventsJson,
        syncedBefore,
      );
      final qr =
          (jsonDecode(
                (await h.outbox.rowForKey('$original:pay'))!.eventsJson,
              ) as List).single
              as Map;
      expect((qr['payload'] as Map)['order_uuid'], original);
      expect(h.table.serverOrderUuid, _winner);
      expect(h.table.status, DiningTableStatus.occupied);
      expect(await h.outbox.resolveTableBillUuid(original), _winner);
    },
  );

  for (final outcome in [
    'opened',
    'replayed',
    'attached',
    'merged',
    'already_closed',
  ]) {
    test(
      'open $outcome applies only specified identity and sheet effect',
      () async {
        final h = _Harness();
        h.adapter.answer = (e) => {
          ...h.adapter._answer(e),
          'outcome': outcome,
          if (outcome == 'attached' || outcome == 'merged')
            'winner_table_session_uuid': _winner,
        };
        await h.open();
        expect(h.table.status, DiningTableStatus.occupied);
        expect(
          h.table.seatingState,
          outcome == 'merged'
              ? 'merged'
              : outcome == 'already_closed'
              ? 'closed'
              : 'open',
        );
        expect(h.table.seatingUuid, _serverSeat);
        expect(
          h.ledger.verdicts.length,
          ['attached', 'merged', 'already_closed'].contains(outcome) ? 1 : 0,
        );
      },
    );
  }

  for (final outcome in [
    'appended',
    'seating_created',
    'held',
    'merged',
    'replayed',
    'bill_terminal',
    'bill_unpaid',
  ]) {
    test(
      'round $outcome preserves cart/status and applies exact ledger effect',
      () async {
        final h = _Harness();
        await h.open();
        h.adapter.online = false;
        await h.coordinator.sendRound(h.table);
        final before = h.ledger.rounds.values.single.toRow();
        h.adapter.answer = (e) => {
          ...h.adapter._answer(e),
          'outcome': outcome,
          'review_reasons': outcome == 'held' ? ['catalogue'] : [],
          'held_lines': outcome == 'held'
              ? [
                  {'line_index': 0, 'product_id': 10, 'reason': 'inactive'},
                ]
              : [],
        };
        h.adapter.online = true;
        await h.outbox.flush();
        final after = h.ledger.rounds.values.single;
        if (outcome == 'replayed') {
          expect(after.toRow(), before);
        } else {
          expect(
            after.status,
            outcome == 'seating_created' ? 'appended' : outcome,
          );
          expect(after.serverRoundId, 10);
        }
        expect(h.table.status, DiningTableStatus.occupied);
        expect(h.table.draft!.items.single.qty, 2);
        expect(
          h.ledger.verdicts.length,
          ['held', 'merged', 'bill_terminal', 'bill_unpaid'].contains(outcome)
              ? 1
              : 0,
        );
      },
    );
  }

  test(
    'printed evidence and numeric local ID are durable; retry cannot reprint',
    () async {
      final h = _Harness();
      await h.open();
      var prints = 0;
      h.coordinator.printRound = (s, items) async {
        prints++;
        expect(items.single['qty'], 2);
        expect(
          await h.outbox.pendingRows(),
          isNotEmpty,
          reason: 'Durability precedes the physical print.',
        );
        return true;
      };
      final round = await h.coordinator.sendRound(h.table);
      expect(round!.printedAt, isNotNull);
      expect((h.events.last['payload'] as Map)['printed_at'], isNotNull);
      expect(h.printed, {'10'});
      expect(h.printed.any((id) => id.startsWith('round:')), false);
      await h.outbox.flush();
      expect(await h.coordinator.sendRound(h.table), isNull);
      expect(prints, 1);
    },
  );

  test(
    'failed business ack retains existing five-rejection parking behavior',
    () async {
      final h = _Harness();
      h.adapter.failed = true;
      await h.open();
      for (var i = 1; i < 5; i++) {
        await h.outbox.flush();
      }
      final row = (await h.db.pendingOutbox()).single;
      expect(row.serverRejections, 5);
      expect(OrderSyncRepository.isStuck(row), true);
      final count = h.adapter.batches.length;
      await h.outbox.flush();
      expect(h.adapter.batches.length, count);
      expect(h.ledger.verdicts, isEmpty);
      expect(h.table.status, DiningTableStatus.occupied);
    },
  );

  for (final outcome in [
    'moved',
    'replayed',
    'target_occupied',
    'stale_generation',
    'unknown_seating',
  ]) {
    test(
      'move $outcome leaves the cashier move intact and reports conflicts',
      () async {
        final h = _Harness();
        await h.open();
        final source = h.table;
        final moved = _session(tableId: '6').copyWith(
          orderReference: source.orderReference,
          occupiedAt: source.occupiedAt,
          draft: source.draft!.copyWith(diningTableId: '6'),
        );
        h.ledger.tables.remove('5');
        h.ledger.tables['6'] = moved;
        h.adapter.answer = (e) => {...h.adapter._answer(e), 'outcome': outcome};
        h.coordinator.onTableTransferred('5', moved);
        await h.coordinator.settled;
        expect(h.coordinator.lastError, isNull);
        final event = h.events.last;
        expect(event['event_type'], 'table.session.move');
        expect((event['payload'] as Map)['from_table_id'], 5);
        expect((event['payload'] as Map)['to_table_id'], 6);
        expect(h.ledger.tables.keys, ['6']);
        expect(h.ledger.tables['6']!.status, DiningTableStatus.occupied);
        expect(
          h.ledger.verdicts.length,
          ['moved', 'replayed'].contains(outcome) ? 0 : 1,
        );
      },
    );
  }

  for (final refused in [false, true]) {
    test(
      'join refused=$refused retains local seats; sheet lists refusal',
      () async {
        final h = _Harness();
        await h.open();
        final seat = _session(tableId: '6');
        h.ledger.tables['6'] = seat;
        h.adapter.answer = (e) => {
          ...h.adapter._answer(e),
          'refused': refused
              ? [
                  {'table_id': 6, 'reason': 'occupied'},
                ]
              : [],
        };
        h.coordinator.onTablesJoined(h.table, seat);
        await h.coordinator.settled;
        expect(h.events.last['event_type'], 'table.session.join');
        expect((h.events.last['payload'] as Map)['join_table_ids'], [6]);
        expect(h.ledger.tables.keys, ['5', '6']);
        expect(h.ledger.verdicts.length, refused ? 1 : 0);
      },
    );
  }

  for (final outcome in [
    'closed',
    'already_closed',
    'tombstoned',
    'stale_generation',
    'replayed',
    'bill_unpaid',
  ]) {
    test('close $outcome never resurrects a locally cleared table', () async {
      final h = _Harness();
      await h.open();
      final source = h.table;
      h.ledger.tables.clear();
      h.adapter.answer = (e) => {...h.adapter._answer(e), 'outcome': outcome};
      h.coordinator.onTablesCleared({'5'}, source);
      await h.coordinator.settled;
      expect(h.events.last['event_type'], 'table.session.close');
      expect((h.events.last['payload'] as Map)['reason'], 'staff_close');
      expect(h.ledger.tables, isEmpty);
      expect(
        h.coordinator.cachedSession('5')!.seatingState,
        outcome == 'bill_unpaid' ? 'open' : 'closed',
      );
      expect(h.ledger.verdicts.length, outcome == 'bill_unpaid' ? 1 : 0);
      expect(
        h.events,
        hasLength(2),
        reason: 'bill_unpaid must not enqueue anything automatically.',
      );
    });
  }

  for (final outcome in [
    'cancelled',
    'nothing_to_cancel',
    'replayed',
    'bill_terminal',
    'unknown_seating',
  ]) {
    test(
      'cancel $outcome records result and exact short-fulfilment effect',
      () async {
        final h = _Harness();
        await h.open();
        await h.coordinator.sendRound(h.table);
        h.adapter.answer = (e) => {
          ...h.adapter._answer(e),
          'outcome': outcome,
          'cancelled_qty': ['cancelled', 'replayed'].contains(outcome) ? 1 : 0,
          'unlinked_line_count': 1,
        };
        await h.coordinator.cancelLine(
          h.table,
          line: {'product_id': 10, 'addon_ids': <int>[], 'notes': ''},
          qty: 2,
          prepared: false,
          authorizedBy: 'Manager',
        );
        final cancellation = h.ledger.cancellations.values.single;
        expect(cancellation.status, outcome);
        expect(
          cancellation.cancelledQty,
          ['cancelled', 'replayed'].contains(outcome) ? 1 : 0,
        );
        expect(h.ledger.verdicts.length, outcome == 'unknown_seating' ? 0 : 1);
        expect(h.table.status, DiningTableStatus.occupied);
        expect(h.table.draft!.items.single.qty, 2);
      },
    );
  }

  test(
    'prepared cancellation queues cancel then waste; manager is mandatory',
    () async {
      final h = _Harness();
      await h.open();
      await h.coordinator.sendRound(h.table);
      await expectLater(
        h.coordinator.cancelLine(
          h.table,
          line: {'product_id': 10},
          qty: 1,
          prepared: true,
          authorizedBy: '',
        ),
        throwsArgumentError,
      );
      expect(h.events, hasLength(2));
      h.adapter.online = false;
      await h.coordinator.cancelLine(
        h.table,
        line: {'product_id': 10},
        qty: 1,
        prepared: true,
        authorizedBy: 'Manager',
        reason: 'Customer changed mind',
      );
      final rows = await h.outbox.pendingRows();
      expect(rows, hasLength(2));
      final events = rows
          .map((r) => (jsonDecode(r.eventsJson) as List).single as Map)
          .toList();
      expect(events.map((e) => e['event_type']), [
        'table.session.cancel_line',
        'product.waste',
      ]);
      expect((events.first['payload'] as Map)['queued_offline'], true);
      expect((events.last['payload'] as Map)['lines'], [
        {'product_id': 10, 'qty': 1, 'reason': 'other'},
      ]);
      expect((events.last['payload'] as Map).containsKey('gps'), false);
    },
  );

  test(
    'clear after accepted rounds requires manager and emits order.void',
    () async {
      final h = _Harness();
      await h.open();
      await h.coordinator.sendRound(h.table);
      h.coordinator.clearApproval = const TableVoidApproval(
        authorizedBy: 'Manager',
        reasonId: 3,
      );
      h.coordinator.onTablesCleared({'5'}, h.table);
      await h.coordinator.settled;
      expect(h.events.last['event_type'], 'order.void');
      expect((h.events.last['payload'] as Map)['void_reason_id'], 3);
      expect((h.events.last['payload'] as Map)['authorized_by'], 'Manager');
      expect(h.table.seatingState, 'closed');
      expect(h.table.status, DiningTableStatus.occupied);
    },
  );

  for (final stockMode in ['unit', 'cooked', 'untracked', 'ingredient', null]) {
    for (final prepared in [false, true]) {
      test(
        'cancel prepared=$prepared stock=$stockMode gates waste locally',
        () async {
          final h = _Harness();
          h.stockModes[10] = stockMode;
          await h.open();
          h.adapter.online = false;
          await h.coordinator.cancelLine(
            h.table,
            line: {'product_id': 10},
            qty: 1,
            prepared: prepared,
            authorizedBy: 'Manager',
          );
          final rows = await h.outbox.pendingRows();
          final events = rows
              .map((r) => (jsonDecode(r.eventsJson) as List).single as Map)
              .toList();
          final waste = prepared && ['unit', 'cooked'].contains(stockMode);
          expect(events.map((e) => e['event_type']), [
            'table.session.cancel_line',
            if (waste) 'product.waste',
          ]);
          expect((events.first['payload'] as Map)['prepared'], prepared);
          expect((events.first['payload'] as Map)['queued_offline'], true);
          expect(
            (events.first['payload'] as Map).containsKey('stock_mode'),
            false,
          );
          expect(h.ledger.cancellations.values.single.prepared, prepared);
          expect(h.table.status, DiningTableStatus.occupied);
          expect(h.table.draft!.items.single.qty, 2);
          h.adapter.online = true;
          await h.outbox.flush();
          expect(await h.outbox.pendingRows(), isEmpty);
          expect(h.ledger.cancellations.values.single.status, 'cancelled');
        },
      );
    }
  }

  test(
    'prepared cancellation without catalogue lookup emits no waste',
    () async {
      final h = _Harness();
      h.coordinator.stockModeForProduct = null;
      await h.open();
      h.adapter.online = false;
      await h.coordinator.cancelLine(
        h.table,
        line: {'product_id': 10},
        qty: 1,
        prepared: true,
        authorizedBy: 'Manager',
      );
      final row = (await h.outbox.pendingRows()).single;
      final event = (jsonDecode(row.eventsJson) as List).single as Map;
      expect(event['event_type'], 'table.session.cancel_line');
      expect((event['payload'] as Map)['prepared'], true);
      expect(h.ledger.cancellations.values.single.prepared, true);
    },
  );

  test(
    'an ACK after snapshot freeze still routes pay and later void to winner',
    () async {
      final h = _Harness();
      h.adapter.online = false;
      await h.open();
      await h.coordinator.sendRound(h.table);
      final original = h.table.serverOrderUuid!;
      final snapshot = OrderSnapshot.initial().copyWith(
        serverOrderUuid: original,
        orderType: 'dine_in',
        diningTableId: '5',
        total: 4,
        subtotal: 4,
        rawSubtotal: 4,
      );
      h.adapter.answer = (e) => {
        ...h.adapter._answer(e),
        'order_uuid': _winner,
      };
      h.adapter.online = true;
      await h.outbox.flush();
      h.coordinator.onTablePaid(h.table, snapshot);
      await h.coordinator.settled;
      final row = await h.outbox.rowForKey(original);
      final event = (jsonDecode(row!.eventsJson) as List).single as Map;
      expect((event['payload'] as Map)['order_uuid'], _winner);
      expect(event['event_type'], 'order.pay');
      expect(snapshot.serverOrderUuid, original);
      expect(await h.outbox.resolveTableBillUuid(original), _winner);
    },
  );

  test(
    'restart reconstructs a missing ledger from durable rows, never prints',
    () async {
      final h = _Harness();
      h.adapter.online = false;
      await h.open();
      await h.coordinator.sendRound(h.table);
      await h.coordinator.cancelLine(
        h.table,
        line: {'product_id': 10},
        qty: 1,
        prepared: true,
        authorizedBy: 'Manager',
      );
      final before = (await h.outbox.pendingRows())
          .map((row) => row.eventsJson)
          .toList();
      h.ledger.rounds.clear();
      h.ledger.cancellations.clear();
      var prints = 0;
      h.coordinator.printRound = (_, _) async {
        prints++;
        return true;
      };
      await h.coordinator.hydrate();
      expect(h.ledger.rounds, hasLength(1));
      expect(h.ledger.cancellations, hasLength(1));
      expect(h.ledger.cancellations.values.single.prepared, true);
      expect(prints, 0);
      expect(
        (await h.outbox.pendingRows()).map((row) => row.eventsJson).toList(),
        before,
      );
    },
  );

  test(
    'live pay hook emits pay-only with frozen tender and card evidence',
    () async {
      final h = _Harness();
      await h.open();
      await h.coordinator.sendRound(h.table);
      h.coordinator.paymentContext = (_) async => const TablePaymentContext(
        lat: 23,
        lng: 58,
        cardCharge: CardCharge(softposReference: 'bank-evidence'),
      );
      final snapshot = OrderSnapshot.initial().copyWith(
        orderType: 'dine_in',
        diningTableId: '5',
        serverOrderUuid: h.table.serverOrderUuid,
        total: 4,
        subtotal: 4,
        rawSubtotal: 4,
        paymentMethod: 'Card',
      );
      h.coordinator.onTablePaid(h.table, snapshot);
      await h.coordinator.settled;
      expect(h.events.map((e) => e['event_type']), [
        'table.session.open',
        'table.session.round',
        'order.pay',
      ]);
      final payload = h.events.last['payload'] as Map;
      expect(payload['payments'], [
        {
          'method': 'card',
          'amount_baisas': 4000,
          'status': 'success',
          'softpos_reference': 'bank-evidence',
        },
      ]);
      expect(payload['gps'], {'lat': 23.0, 'lng': 58.0});
      expect(h.table.seatingState, 'closed');
      expect(h.table.status, DiningTableStatus.occupied);
    },
  );
}
