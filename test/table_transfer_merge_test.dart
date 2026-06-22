import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/state/pos_controller.dart';

/// Dine-in table transfer (move an occupied session to a free table) and JOIN
/// (pull a FREE neighbouring table into an occupied party so they share the
/// party's ONE bill — never combining two separate running orders).
class _FakeStorage implements OrderStorageService {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const latte = Product(id: '10', name: 'Latte', category: 'Coffee', price: 2.0);
  const cake = Product(id: '11', name: 'Cake', category: 'Dessert', price: 3.0);

  OrderSessionDraft draft({
    required String tableId,
    required String tableName,
    required List<CartItem> items,
    String reference = 'REF-1',
    String serverOrderUuid = '',
  }) {
    return OrderSessionDraft(
      orderReference: reference,
      orderType: OrderType.dineIn,
      selectedCategory: 'Coffee',
      customerReferenceNumber: '',
      diningFloorId: 'f1',
      diningFloorLabel: 'Main Hall',
      diningTableId: tableId,
      diningTableName: tableName,
      items: items,
      discount: const DiscountConfiguration(),
      splitCount: 1,
      serverOrderUuid: serverOrderUuid,
    );
  }

  DiningTableSession occupied(String tableId, OrderSessionDraft d,
          {DateTime? at}) =>
      DiningTableSession(
        tableId: tableId,
        floorId: 'f1',
        status: DiningTableStatus.occupied,
        updatedAt: DateTime(2026, 6, 10, 12),
        orderReference: d.orderReference,
        occupiedAt: at ?? DateTime(2026, 6, 10, 12),
        draft: d,
      );

  (PosController, _FakeStorage) build() {
    final storage = _FakeStorage();
    final controller = PosController(orderStorage: storage);
    controller.applyCatalog(
      categories: const ['Coffee', 'Dessert'],
      products: const [latte, cake],
      floors: const [DiningFloor(id: 'f1', label: 'Main Hall')],
      tables: const [
        DiningTableDefinition(
            id: 't1', floorId: 'f1', name: 'T1', sizeLabel: 'square', seats: 4, sortOrder: 1),
        DiningTableDefinition(
            id: 't2', floorId: 'f1', name: 'T2', sizeLabel: 'square', seats: 4, sortOrder: 2),
        DiningTableDefinition(
            id: 't3', floorId: 'f1', name: 'T3', sizeLabel: 'square', seats: 4, sortOrder: 3),
      ],
    );
    return (controller, storage);
  }

  test('transfer moves an occupied session to a free table', () async {
    final (controller, storage) = build();
    final d = draft(
      tableId: 't1',
      tableName: 'T1',
      items: [CartItem(product: latte, qty: 2)],
    );
    storage.tables['t1'] = occupied('t1', d);
    controller.diningTableSessions = [occupied('t1', d)];

    final message = await controller.transferDiningTable('t1', 't2');

    expect(message, isNotNull);
    expect(storage.tables.containsKey('t1'), isFalse);
    final moved = storage.tables['t2']!;
    expect(moved.status, DiningTableStatus.occupied);
    expect(moved.orderReference, 'REF-1');
    expect(moved.draft!.diningTableId, 't2');
    expect(moved.draft!.diningTableName, 'T2');
    expect(moved.draft!.items.single.qty, 2);
    expect(controller.diningSessionFor('t1'), isNull);
    expect(controller.diningSessionFor('t2'), isNotNull);
  });

  test('transfer refuses an occupied target or a missing source', () async {
    final (controller, storage) = build();
    final d1 = draft(tableId: 't1', tableName: 'T1', items: [CartItem(product: latte)]);
    final d2 = draft(tableId: 't2', tableName: 'T2', items: [CartItem(product: cake)], reference: 'REF-2');
    storage.tables['t1'] = occupied('t1', d1);
    storage.tables['t2'] = occupied('t2', d2);
    controller.diningTableSessions = [occupied('t1', d1), occupied('t2', d2)];

    expect(await controller.transferDiningTable('t1', 't2'), isNull);
    expect(await controller.transferDiningTable('t3', 't1'), isNull);
    expect(storage.tables.length, 2); // untouched
  });

  test('join links a free table to the party — one shared bill, both seated', () async {
    final (controller, storage) = build();
    final d1 = draft(
      tableId: 't1',
      tableName: 'T1',
      items: [CartItem(product: latte, qty: 2)],
      reference: 'REF-1',
    );
    final at = DateTime(2026, 6, 10, 11);
    storage.tables['t1'] = occupied('t1', d1, at: at);
    controller.diningTableSessions = [occupied('t1', d1, at: at)];
    // t2 is FREE (no session) — the neighbouring table pulled into the party.

    final message = await controller.joinDiningTables('t1', 't2');

    expect(message, isNotNull);
    final head = storage.tables['t1']!;
    final seat = storage.tables['t2']!;
    // The head keeps its single bill; the free table becomes a linked seat.
    expect(head.status, DiningTableStatus.occupied);
    expect(head.linkedTableIds, ['t2']);
    expect(head.hasJoinedTables, isTrue);
    expect(head.draft!.items, hasLength(1)); // unchanged — NO cart merge
    expect(head.draft!.items.single.qty, 2);
    expect(head.occupiedAt, at);
    expect(seat.status, DiningTableStatus.occupied);
    expect(seat.isLinkedSecondary, isTrue);
    expect(seat.primaryTableId, 't1');
    expect(seat.draft, isNull); // no bill of its own
    expect(seat.occupiedAt, at); // shares the party's clock
  });

  test('join refuses a table that already has its own running order', () async {
    final (controller, storage) = build();
    final d1 = draft(tableId: 't1', tableName: 'T1', items: [CartItem(product: latte)]);
    final d2 = draft(tableId: 't2', tableName: 'T2', items: [CartItem(product: cake)], reference: 'REF-2');
    storage.tables['t1'] = occupied('t1', d1);
    storage.tables['t2'] = occupied('t2', d2);
    controller.diningTableSessions = [occupied('t1', d1), occupied('t2', d2)];

    // Both occupied — joining must NEVER combine two separate orders.
    expect(await controller.joinDiningTables('t1', 't2'), isNull);
    expect(storage.tables['t1']!.draft!.items, hasLength(1));
    expect(storage.tables['t2']!.draft!.items, hasLength(1));
    expect(storage.tables['t1']!.linkedTableIds, isEmpty);
  });

  test('multiple free tables can join the same party', () async {
    final (controller, storage) = build();
    final d1 = draft(tableId: 't1', tableName: 'T1', items: [CartItem(product: latte)]);
    storage.tables['t1'] = occupied('t1', d1);
    controller.diningTableSessions = [occupied('t1', d1)];

    await controller.joinDiningTables('t1', 't2'); // add free t2
    await controller.joinDiningTables('t1', 't3'); // add free t3

    final head = storage.tables['t1']!;
    expect(head.linkedTableIds, containsAll(<String>['t2', 't3']));
    expect(storage.tables['t2']!.primaryTableId, 't1');
    expect(storage.tables['t3']!.primaryTableId, 't1');
  });

  test('opening a linked seat opens the head shared bill', () async {
    final (controller, storage) = build();
    final d1 = draft(tableId: 't1', tableName: 'T1', items: [CartItem(product: latte)]);
    storage.tables['t1'] = occupied('t1', d1);
    controller.diningTableSessions = [occupied('t1', d1)];
    await controller.joinDiningTables('t1', 't2'); // t1 head, t2 linked seat

    await controller.openDiningTable('t2'); // tap the linked seat

    // Redirected to the head, where the shared bill lives.
    expect(controller.activeDiningTableId, 't1');
  });

  test('discarding any joined table frees the whole party', () async {
    final (controller, storage) = build();
    final d1 = draft(tableId: 't1', tableName: 'T1', items: [CartItem(product: latte)]);
    storage.tables['t1'] = occupied('t1', d1);
    controller.diningTableSessions = [occupied('t1', d1)];
    await controller.joinDiningTables('t1', 't2');

    await controller.clearDiningTableById('t2'); // discard via the linked seat

    expect(storage.tables.containsKey('t1'), isFalse);
    expect(storage.tables.containsKey('t2'), isFalse);
    expect(controller.diningSessionFor('t1'), isNull);
    expect(controller.diningSessionFor('t2'), isNull);
  });

  test('transfer refuses a table that is part of a joined party', () async {
    final (controller, storage) = build();
    final d1 = draft(tableId: 't1', tableName: 'T1', items: [CartItem(product: latte)]);
    storage.tables['t1'] = occupied('t1', d1);
    controller.diningTableSessions = [occupied('t1', d1)];
    await controller.joinDiningTables('t1', 't2'); // t1 head, t2 linked seat

    // Neither the head nor the linked seat can be moved to a free table.
    expect(await controller.transferDiningTable('t1', 't3'), isNull);
    expect(await controller.transferDiningTable('t2', 't3'), isNull);
  });

  test('emptying a joined head cart frees the whole party (no orphaned seats)', () async {
    final (controller, storage) = build();
    final d1 = draft(tableId: 't1', tableName: 'T1', items: [CartItem(product: latte)]);
    storage.tables['t1'] = occupied('t1', d1);
    controller.diningTableSessions = [occupied('t1', d1)];
    await controller.joinDiningTables('t1', 't2'); // t1 head, t2 linked seat
    expect(storage.tables.containsKey('t2'), isTrue);

    await controller.openDiningTable('t1'); // load the head's bill
    // Remove every line — the head's cart goes empty while it has a linked seat.
    for (final item in [...controller.cart]) {
      controller.removeCartItem(item);
    }
    await controller.returnToDiningFloorPlan(); // flushes the debounced persist

    // The whole party freed in BOTH memory and storage — the linked seat is
    // NOT orphaned (occupied with a vanished head).
    expect(controller.diningSessionFor('t1'), isNull);
    expect(controller.diningSessionFor('t2'), isNull);
    expect(storage.tables.containsKey('t1'), isFalse);
    expect(storage.tables.containsKey('t2'), isFalse);
  });
}
