import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/data/table_sync_coordinator.dart';
import 'package:pos_machine/l10n/l10n_en.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/table_sync_models.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/kitchen_ticket.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/state/pos_controller.dart';

const b3Product = Product(
  id: '10',
  name: 'Coffee',
  category: 'Drinks',
  price: 2.7,
);

class B3Memory implements TableLedgerStore, OrderStorageService {
  @override
  Future<void> assertNoPendingCombine() async {}
  final tables = <String, DiningTableSession>{};
  final rounds = <String, LocalTableRound>{};
  final cancellations = <String, LocalLineCancellation>{};
  final verdicts = <TableSyncVerdict>[];
  @override
  Future<int> fetchNextOrderNumber() async => 1451;
  @override
  Future<List<OrderHistoryRecord>> loadOrderHistory() async => [];
  @override
  Future<List<HeldOrderRecord>> loadHeldOrders() async => [];
  @override
  Future<void> saveCompletedOrder(OrderSnapshot s) async {}
  @override
  Future<void> updateCompletedOrder(OrderHistoryRecord r) async {}
  @override
  Future<void> saveHeldOrder(OrderSessionDraft d) async {}
  @override
  Future<void> deleteHeldOrder(String id) async {}
  @override
  Future<void> clearHeldOrders() async {}
  @override
  Future<void> clearAllData() async {}
  @override
  Future<void> saveDiningTableSession(DiningTableSession s) async {
    tables[s.tableId] = s;
  }

  @override
  Future<List<DiningTableSession>> loadDiningTableSessions() async =>
      tables.values.toList();
  @override
  Future<void> clearDiningTable(String id) async {
    tables.remove(id);
  }

  @override
  Future<void> saveLocalTableRound(LocalTableRound r) async {
    rounds[r.clientRequestId] = r;
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
  Future<int> addTableSyncVerdict(TableSyncVerdict v) async {
    verdicts.add(v);
    return verdicts.length;
  }

  @override
  Future<List<TableSyncVerdict>> readTableSyncVerdicts({
    bool unseenOnly = false,
    int limit = 200,
  }) async =>
      verdicts.where((v) => !unseenOnly || !v.seen).take(limit).toList();
  @override
  Future<void> markTableSyncVerdictsSeen(List<int> ids) async {}
  @override
  Future<void> updateTableSyncFields(String id, Map<String, Object?> f) async {
    expect(f.keys, isNot(contains('status')));
    final s = tables[id];
    if (s == null) return;
    tables[id] = s.copyWith(
      seatingKey: f['seating_key'] as String?,
      seatingUuid: f['seating_uuid'] as String?,
      seatingState: f['seating_state'] as String?,
      serverOrderUuid: f['server_order_uuid'] as String?,
      draft: s.draft?.copyWith(
        serverOrderUuid: f['server_order_uuid'] as String?,
      ),
      tempReference: f['temp_reference'] as String?,
    );
  }
}

/// Mock HTTP acknowledgements only. The independent B6 rule fake is separate.
class B3Harness {
  final memory = B3Memory();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  late final PosController controller;
  late final OrderSyncRepository outbox;
  late final TableSyncCoordinator coordinator;
  late final TableKitchenBridge bridge;
  late final SharedPreferences preferences;
  final events = <Map<String, dynamic>>[];
  final tickets = <KitchenTicketData>[];
  final printedIds = <String>[];
  String mode = 'live';
  bool online = true, printSuccess = true;
  int failures = 0, nextRound = 0;
  int? cancelledQty;

  Future<void> init({List<CartItem>? items}) async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          if (!online) {
            h.reject(
              DioException(
                requestOptions: o,
                type: DioExceptionType.connectionError,
              ),
            );
            return;
          }
          final batch = ((o.data as Map)['events'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          events.addAll(batch);
          h.resolve(
            Response(
              requestOptions: o,
              statusCode: 200,
              data: {
                'data': {
                  'results': [
                    for (final e in batch)
                      {
                        'client_event_id': e['client_event_id'],
                        'status': 'processed',
                        'result': {
                          'outcome': switch (e['event_type']) {
                            'table.session.open' => 'opened',
                            'table.session.round' => 'appended',
                            'table.session.cancel_line' => 'cancelled',
                            _ => 'closed',
                          },
                          'table_session_uuid':
                              'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                          'order_uuid': (e['payload'] as Map)['order_uuid'],
                          'temp_reference': 'T-0906-001',
                          if (e['event_type'] == 'table.session.round') ...{
                            'round_id': ++nextRound,
                            'round_no': nextRound,
                          },
                          if (e['event_type'] == 'table.session.cancel_line')
                            'cancelled_qty':
                                cancelledQty ?? (e['payload'] as Map)['qty'],
                        },
                      },
                  ],
                },
              },
            ),
          );
        },
      ),
    );
    outbox = OrderSyncRepository(
      PosApiService(tokenGetter: () => 'mock', dio: dio),
      db,
    );
    coordinator = TableSyncCoordinator(
      outbox: outbox,
      store: memory,
      loadSessions: memory.loadDiningTableSessions,
      mode: () => mode,
      degraded: () => !online,
      staffId: () => 4,
      markPrinted: (id) async {
        printedIds.add(id);
        await preferences.setStringList(
          'qr_round_printed_set_mock',
          printedIds,
        );
      },
    );
    controller = PosController(orderStorage: memory)
      ..printReceipts = false
      ..printKitchenTickets = true
      ..isLiveSharedTable = () => mode == 'live';
    controller.applyCatalog(
      categories: const ['Drinks'],
      products: const [b3Product],
      floors: const [DiningFloor(id: '1', label: 'Main')],
      tables: const [
        DiningTableDefinition(
          id: '5',
          floorId: '1',
          name: 'Table 5',
          sizeLabel: 'square',
          seats: 4,
          sortOrder: 1,
        ),
      ],
    );
    final at = DateTime.now();
    final session = DiningTableSession(
      tableId: '5',
      floorId: '1',
      status: DiningTableStatus.occupied,
      orderReference: 'LOCAL-5',
      occupiedAt: at,
      updatedAt: at,
      draft: OrderSessionDraft(
        orderReference: 'LOCAL-5',
        orderType: OrderType.dineIn,
        selectedCategory: 'Drinks',
        customerReferenceNumber: '',
        diningFloorId: '1',
        diningFloorLabel: 'Main',
        diningTableId: '5',
        diningTableName: 'Table 5',
        items: items ?? [CartItem(product: b3Product, qty: 2)],
        discount: const DiscountConfiguration(),
        splitCount: 1,
      ),
    );
    memory.tables['5'] = session;
    controller.diningTableSessions = [session];
    await coordinator.hydrate();
    bridge = TableKitchenBridge(
      controller: controller,
      coordinator: coordinator,
      preferences: preferences,
      l10n: L10nEn.new,
      printer: (ticket) async {
        tickets.add(ticket);
        return printSuccess;
      },
      onPrintFailure: () => failures++,
    )..attach();
    await controller.openDiningTable('5');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await coordinator.settled;
    addTearDown(() async {
      bridge.detach();
      controller.dispose();
      await coordinator.dispose();
      await outbox.dispose();
      await db.close();
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'paid table cleanup never queues void, including an offline pay',
    () async {
      final h = B3Harness();
      await h.init();
      await h.bridge.send(h.bridge.activeSession()!);
      h.online = false;
      final paid = h.bridge.activeSession()!.copyWith(
        status: DiningTableStatus.paid,
      );
      final snapshot = OrderSnapshot.initial().copyWith(
        orderType: 'dine_in',
        diningTableId: '5',
        serverOrderUuid: h.controller.activeDiningTableBillUuid,
        total: 5.4,
        rawSubtotal: 5.4,
        subtotal: 5.4,
      );
      h.bridge.onTablePaid(paid, snapshot);
      await h.coordinator.settled;
      final before = (await h.outbox.pendingRows())
          .map((r) => r.eventsJson)
          .toList();
      h.bridge.onTablesCleared({'5'}, paid);
      await h.coordinator.settled;
      expect(
        (await h.outbox.pendingRows()).map((r) => r.eventsJson).toList(),
        before,
      );
      expect(
        (jsonDecode(before.single) as List).single['event_type'],
        'order.pay',
      );
      expect(h.events.any((e) => e['event_type'] == 'order.void'), false);
    },
  );

  test(
    'final-round gate still sends when local kitchen printing is disabled',
    () async {
      final h = B3Harness();
      await h.init();
      h.controller.printKitchenTickets = false;
      expect(
        await h.controller.onDiningTableFinalRound!(OrderSnapshot.initial()),
        true,
      );
      expect(h.memory.rounds.values.single.lines.single['qty'], 2);
      expect(h.memory.rounds.values.single.printedAt, isNull);
      expect(h.tickets, isEmpty);
      expect(h.printedIds, isEmpty);
    },
  );

  test('local-only cart prints without fabricating a server round', () async {
    final h = B3Harness();
    await h.init(
      items: [
        CartItem(
          product: const Product(
            id: 'local-special',
            name: 'Special',
            category: 'Drinks',
            price: 1,
          ),
        ),
      ],
    );
    await h.bridge.send(h.bridge.activeSession()!);
    expect(h.tickets.single.items.single['name'], 'Special (local-only)');
    expect(h.memory.rounds, isEmpty);
    expect(
      h.events.any((e) => e['event_type'] == 'table.session.round'),
      false,
    );
    await h.bridge.send(h.bridge.activeSession()!);
    expect(h.tickets, hasLength(1));
  });

  test(
    'Send then leave prints each delta once and stamps numeric ACK IDs',
    () async {
      final h = B3Harness();
      await h.init();
      await h.bridge.send(h.bridge.activeSession()!);
      expect(h.tickets.single.items.single['qty'], 2);
      expect(h.tickets.single.orderLabel, 'T-0906-001');
      expect(h.tickets.single.tableLabel, 'Table 5');
      expect(h.tickets.single.isHold, false);
      expect(h.memory.rounds.values.single.printedAt, isNotNull);
      expect(h.printedIds, ['1']);
      expect(h.preferences.getStringList('qr_round_printed_set_mock'), ['1']);
      h.controller.addProduct(b3Product);
      await h.controller.returnToDiningFloorPlan();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await h.coordinator.settled;
      expect(h.tickets.map((t) => t.items.single['qty']), [2, 1]);
      expect(h.printedIds, ['1', '2']);
      expect(h.events.any((e) => e['event_type'] == 'order.create'), false);
    },
  );

  for (final enabled in [true, false]) {
    test(
      'print failure/disabled enabled=$enabled never stamps evidence',
      () async {
        final h = B3Harness()..printSuccess = false;
        await h.init();
        h.controller.printKitchenTickets = enabled;
        await h.bridge.send(h.bridge.activeSession()!);
        expect(h.memory.rounds.values.single.printedAt, isNull);
        expect(h.printedIds, isEmpty);
        expect(h.failures, enabled ? 1 : 0);
        expect(h.tickets.length, enabled ? 1 : 0);
        final e = h.events.last['payload'] as Map;
        expect(e['printed_at'], isNull);
      },
    );
  }

  test(
    'final-round gate sends only unsent and does not duplicate kitchen copy',
    () async {
      final h = B3Harness();
      await h.init();
      await h.bridge.send(h.bridge.activeSession()!);
      h.controller.addProduct(b3Product);
      final handled = await h.controller.onDiningTableFinalRound!(
        OrderSnapshot.initial(),
      );
      expect(handled, true);
      expect(h.tickets.map((t) => t.items.single['qty']), [2, 1]);
      expect(
        await h.controller.onDiningTableFinalRound!(OrderSnapshot.initial()),
        true,
      );
      expect(h.tickets, hasLength(2));
    },
  );

  test(
    'local-only lines print labelled once but never become wire lines',
    () async {
      final h = B3Harness();
      await h.init(
        items: [
          CartItem(product: b3Product),
          CartItem(
            product: const Product(
              id: 'local-drink',
              name: 'Special',
              category: 'Drinks',
              price: 1,
            ),
          ),
        ],
      );
      await h.bridge.send(h.bridge.activeSession()!);
      expect(h.tickets.single.items.last['name'], 'Special (local-only)');
      final lines = (h.events.last['payload'] as Map)['lines'] as List;
      expect(lines, hasLength(1));
      expect((lines.single as Map)['product_id'], 10);
      await h.bridge.send(h.bridge.activeSession()!);
      expect(h.tickets, hasLength(1));
    },
  );

  for (final mode in ['off', 'shadow', 'live']) {
    test(
      'round-up guard mode=$mode affects only a Live dine-in table',
      () async {
        final h = B3Harness()..mode = mode;
        await h.init();
        h.controller.selectPaymentMethod('Credit Card');
        final total = h.controller.total;
        expect(h.controller.canOfferCharityRoundUp, mode != 'live');
        expect(h.controller.showCharityRoundUpPrompt, false);
        expect(h.controller.total, total);
        h.controller.selectedOrderType = OrderType.toGo;
        expect(h.controller.canOfferCharityRoundUp, true);
        h.controller.selectedOrderType = OrderType.delivery;
        expect(h.controller.canOfferCharityRoundUp, false);
      },
    );
  }
}
