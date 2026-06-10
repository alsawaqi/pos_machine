import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/state/pos_controller.dart';

/// Gap sweep G2 — table transfer (move an occupied session to a free table)
/// and merge (combine two occupied tables' carts on mergeSignature).
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

  test('merge combines carts on mergeSignature and frees the source', () async {
    final (controller, storage) = build();
    final d1 = draft(
      tableId: 't1',
      tableName: 'T1',
      items: [CartItem(product: latte, qty: 1), CartItem(product: cake, qty: 1)],
      reference: 'REF-SRC',
    );
    final d2 = draft(
      tableId: 't2',
      tableName: 'T2',
      items: [CartItem(product: latte, qty: 2)],
      reference: 'REF-DST',
    );
    final earlier = DateTime(2026, 6, 10, 11);
    storage.tables['t1'] = occupied('t1', d1, at: earlier);
    storage.tables['t2'] = occupied('t2', d2);
    controller.diningTableSessions = [
      occupied('t1', d1, at: earlier),
      occupied('t2', d2),
    ];

    final message = await controller.mergeDiningTables('t1', 't2');

    expect(message, isNotNull);
    expect(storage.tables.containsKey('t1'), isFalse);
    final merged = storage.tables['t2']!;
    // Target keeps its reference; latte qty merged 2+1, cake appended.
    expect(merged.orderReference, 'REF-DST');
    expect(merged.draft!.items, hasLength(2));
    expect(
      merged.draft!.items.firstWhere((i) => i.product.id == '10').qty,
      3,
    );
    expect(
      merged.draft!.items.firstWhere((i) => i.product.id == '11').qty,
      1,
    );
    // Earliest party's clock wins for the occupancy badge.
    expect(merged.occupiedAt, earlier);
  });

  test('customized lines only merge when modifiers + notes match', () async {
    final (controller, storage) = build();
    final largeLatte = CartItem(
      product: latte,
      modifiers: const [
        CartItemModifier(id: '100', group: 'Size', label: 'Large', price: 0.5),
      ],
    );
    final plainLatte = CartItem(product: latte);
    final d1 = draft(tableId: 't1', tableName: 'T1', items: [largeLatte]);
    final d2 = draft(tableId: 't2', tableName: 'T2', items: [plainLatte], reference: 'REF-2');
    storage.tables['t1'] = occupied('t1', d1);
    storage.tables['t2'] = occupied('t2', d2);
    controller.diningTableSessions = [occupied('t1', d1), occupied('t2', d2)];

    await controller.mergeDiningTables('t1', 't2');

    // Different mergeSignature → two separate lines.
    expect(storage.tables['t2']!.draft!.items, hasLength(2));
  });

  test('merging a server-mirrored source voids its held mirror', () async {
    final (controller, storage) = build();
    final voided = <String>[];
    controller.onOrderVoided = (uuid, {orderNumber, reason, voidReasonId}) {
      voided.add(uuid);
    };
    final d1 = draft(
      tableId: 't1',
      tableName: 'T1',
      items: [CartItem(product: latte)],
      serverOrderUuid: 'mirror-uuid-1',
    );
    final d2 = draft(tableId: 't2', tableName: 'T2', items: [CartItem(product: cake)], reference: 'REF-2');
    storage.tables['t1'] = occupied('t1', d1);
    storage.tables['t2'] = occupied('t2', d2);
    controller.diningTableSessions = [occupied('t1', d1), occupied('t2', d2)];

    await controller.mergeDiningTables('t1', 't2');

    expect(voided, ['mirror-uuid-1']);
  });
}
