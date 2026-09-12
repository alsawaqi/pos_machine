import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/state/pos_controller.dart';

class _FakeStorage implements OrderStorageService {
  @override
  Future<void> assertNoPendingCombine() async {}
  final Map<String, DiningTableSession> tables = {};
  final List<String> voided = [];

  @override
  Future<int> fetchNextOrderNumber() async => 1451;
  @override
  Future<void> saveCompletedOrder(OrderSnapshot snapshot) async {}
  @override
  Future<void> updateCompletedOrder(OrderHistoryRecord record) async {}
  @override
  Future<List<OrderHistoryRecord>> loadOrderHistory() async => const [];
  @override
  Future<void> saveHeldOrder(OrderSessionDraft draft) async {}
  @override
  Future<List<HeldOrderRecord>> loadHeldOrders() async => const [];
  @override
  Future<void> saveDiningTableSession(DiningTableSession session) async {
    tables[session.tableId] = session;
  }

  @override
  Future<List<DiningTableSession>> loadDiningTableSessions() async =>
      tables.values.toList();
  @override
  Future<void> clearDiningTable(String tableId) async {
    tables.remove(tableId);
  }

  @override
  Future<void> deleteHeldOrder(String id) async {}
  @override
  Future<void> clearHeldOrders() async {}
  @override
  Future<void> clearAllData() async {}
}

class _Hooks implements DiningTableSyncHooks {
  final calls = <String>[];
  DiningTableSession? session;
  Set<String>? cleared;
  @override
  void onTableOccupied(DiningTableSession s) {
    calls.add('occupied');
    session = s;
  }

  @override
  void onTableDraftPersisted(DiningTableSession s) {
    calls.add('draft');
    session = s;
  }

  @override
  void onTableLeft(String tableId) {
    calls.add('left:$tableId');
  }

  @override
  void onTableTransferred(String fromId, DiningTableSession moved) {
    calls.add('move:$fromId');
    session = moved;
  }

  @override
  void onTablesJoined(DiningTableSession head, DiningTableSession seat) {
    calls.add('join');
    session = head;
  }

  @override
  void onTablesCleared(Set<String> groupIds, DiningTableSession? head) {
    calls.add('clear');
    session = head;
    cleared = groupIds;
  }

  @override
  void onTablePaid(DiningTableSession paid, OrderSnapshot snapshot) {
    calls.add('paid');
    session = paid;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const proposed = '11111111-1111-4111-8111-111111111111';
  const winner = '22222222-2222-4222-8222-222222222222';
  const product = Product(
    id: '10',
    name: 'Latte',
    category: 'Coffee',
    price: 2,
  );

  (PosController, _FakeStorage) setup(String billUuid) {
    final storage = _FakeStorage();
    final controller = PosController(orderStorage: storage);
    controller.applyCatalog(
      categories: const ['Coffee'],
      products: const [product],
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
        DiningTableDefinition(
          id: '6',
          floorId: '1',
          name: 'Table 6',
          sizeLabel: 'square',
          seats: 4,
          sortOrder: 2,
        ),
        DiningTableDefinition(
          id: '7',
          floorId: '1',
          name: 'Table 7',
          sizeLabel: 'square',
          seats: 4,
          sortOrder: 3,
        ),
      ],
    );
    final draft = OrderSessionDraft(
      orderReference: 'LOCAL-5',
      orderType: OrderType.dineIn,
      selectedCategory: 'Coffee',
      customerReferenceNumber: '',
      diningFloorId: '1',
      diningFloorLabel: 'Main',
      diningTableId: '5',
      diningTableName: 'Table 5',
      items: [CartItem(product: product, qty: 2)],
      discount: const DiscountConfiguration(),
      splitCount: 1,
      serverOrderUuid: billUuid,
    );
    final session = DiningTableSession(
      tableId: '5',
      floorId: '1',
      status: DiningTableStatus.occupied,
      updatedAt: DateTime.utc(2026, 9, 6),
      draft: draft,
      serverOrderUuid: billUuid,
      seatingKey: proposed,
    );
    storage.tables['5'] = session;
    controller.diningTableSessions = [session];
    addTearDown(controller.dispose);
    return (controller, storage);
  }

  test(
    'occupied/draft/leave hooks fire once at their persistence write points',
    () async {
      final (controller, storage) = setup(proposed);
      final hooks = _Hooks();
      controller.diningTableSyncHooks = hooks;
      await controller.openDiningTable('5');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(hooks.calls, ['occupied']);
      expect(hooks.session!.tableId, '5');
      expect(storage.tables['5']!.draft!.items.single.qty, 2);
      hooks.calls.clear();
      controller.addProduct(product);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(hooks.calls, ['draft']);
      expect(hooks.session!.draft!.items.single.qty, 3);
      hooks.calls.clear();
      await controller.returnToDiningFloorPlan();
      expect(hooks.calls, ['draft', 'left:5']);
      expect(controller.activeDiningTableId, isNull);
    },
  );

  test('move/join/clear hooks report the cashier write exactly once', () async {
    final (controller, storage) = setup(proposed);
    final hooks = _Hooks();
    controller.diningTableSyncHooks = hooks;
    await controller.transferDiningTable('5', '6');
    expect(hooks.calls, ['move:5']);
    expect(hooks.session!.tableId, '6');
    expect(storage.tables.keys, ['6']);
    hooks.calls.clear();
    await controller.joinDiningTables('6', '7');
    expect(hooks.calls, ['join']);
    expect(hooks.session!.linkedTableIds, ['7']);
    hooks.calls.clear();
    await controller.clearDiningTableById('7');
    expect(hooks.calls, ['clear']);
    expect(hooks.cleared, {'6', '7'});
    expect(hooks.session!.tableId, '6');
    expect(storage.tables, isEmpty);
  });

  test('active clear hook fires once with the saved head', () async {
    final (controller, _) = setup(proposed);
    final hooks = _Hooks();
    controller.diningTableSyncHooks = hooks;
    await controller.openDiningTable('5');
    await controller.clearActiveDiningTable();
    expect(hooks.calls, ['clear']);
    expect(hooks.session!.tableId, '5');
    expect(hooks.cleared, {'5'});
  });

  test(
    'mock cash completion calls final-round gate and paid hook once',
    () async {
      final (controller, _) = setup(proposed);
      final hooks = _Hooks();
      controller.diningTableSyncHooks = hooks;
      controller.printReceipts = false;
      controller.printKitchenTickets = false;
      var finalRounds = 0;
      controller.onDiningTableFinalRound = (snapshot) async {
        finalRounds++;
        expect(snapshot.serverOrderUuid, proposed);
        return true;
      };
      await controller.openDiningTable('5');
      controller.selectedPaymentMethod = 'Cash';
      await controller.payAndPrint();
      expect(finalRounds, 1);
      expect(hooks.calls.where((call) => call == 'paid'), hasLength(1));
      expect(hooks.session!.status, DiningTableStatus.paid);
    },
  );

  for (final type in [OrderType.toGo, OrderType.delivery]) {
    test('$type never emits dining hooks', () async {
      final (controller, _) = setup(proposed);
      final hooks = _Hooks();
      controller.diningTableSyncHooks = hooks;
      controller.selectedOrderType = type;
      controller.addProduct(product);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await controller.returnToDiningFloorPlan();
      expect(hooks.calls, isEmpty);
    });
  }

  test('openDiningTable restores the stored shared bill UUID', () async {
    final (controller, _) = setup(winner);
    await controller.openDiningTable('5');
    expect(controller.prepareTransferDraft()!.serverOrderUuid, winner);
    expect(controller.cart.single.qty, 2);
  });

  test(
    'own ACK rebinds the still-open cart without re-opening the table',
    () async {
      final (controller, storage) = setup(proposed);
      await controller.openDiningTable('5');

      // The permitted ACK effect: update seating metadata and draft UUID.
      // There is no board/feed read, transport, tender or device in this test.
      final current = storage.tables['5']!;
      storage.tables['5'] = current.copyWith(
        serverOrderUuid: winner,
        draft: current.draft!.copyWith(serverOrderUuid: winner),
      );
      await controller.refreshDiningTables();
      // The approved identity-only own-ACK hook. Existing expectations below
      // remain unchanged; no reopen or cart reload is used to satisfy them.
      expect(
        controller.bindDiningTableBillIdentity(
          live: true,
          tableId: '5',
          orderReference: 'LOCAL-5',
          seatingKey: proposed,
          expectedOrderUuid: proposed,
          orderUuid: winner,
        ),
        isTrue,
      );
      expect(controller.diningSessionFor('5')!.draft!.serverOrderUuid, winner);
      expect(controller.cart.single.qty, 2);
      expect(
        controller.diningSessionFor('5')!.status,
        DiningTableStatus.occupied,
      );

      // This existing pure helper exposes the same private active UUID read
      // by _finishCompletedOrder, without running a payment or printer.
      final activeUuid = controller.prepareTransferDraft()!.serverOrderUuid;
      debugPrint('stored winner=$winner; still-open active bill=$activeUuid');
      expect(activeUuid, winner);
    },
  );

  test(
    'identity hook is Live-only and rejects a different active occupancy',
    () async {
      final (controller, _) = setup(proposed);
      await controller.openDiningTable('5');
      controller.paymentStatus = 'Processing payment';
      final before = controller.snapshot().toMap();
      for (final (live, table, reference, seating, expected) in [
        (false, '5', 'LOCAL-5', proposed, proposed),
        (true, '6', 'LOCAL-5', proposed, proposed),
        (true, '5', 'another-party', proposed, proposed),
        (true, '5', 'LOCAL-5', winner, proposed),
        (true, '5', 'LOCAL-5', proposed, 'stale-uuid'),
      ]) {
        expect(
          controller.bindDiningTableBillIdentity(
            live: live,
            tableId: table,
            orderReference: reference,
            seatingKey: seating,
            expectedOrderUuid: expected,
            orderUuid: winner,
          ),
          isFalse,
        );
        expect(controller.activeDiningTableBillUuid, proposed);
        expect(controller.snapshot().toMap(), before);
      }
      expect(
        controller.bindDiningTableBillIdentity(
          live: true,
          tableId: '5',
          orderReference: 'LOCAL-5',
          seatingKey: proposed,
          expectedOrderUuid: proposed,
          orderUuid: winner,
        ),
        isTrue,
      );
      expect(controller.activeDiningTableBillUuid, winner);
      expect(
        controller.snapshot().toMap(),
        before,
        reason: 'An identity ACK changes no cart, amount or tender field.',
      );
    },
  );
}
