import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/state/pos_controller.dart';

const _latte = Product(id: '1', name: 'Latte', category: 'X', price: 2.0);
const _cake = Product(id: '2', name: 'Cake', category: 'X', price: 3.0);
const _bundle = Offer(id: 9, name: 'Pair', type: 'bundle');
const _floor = DiningFloor(id: 'f1', label: 'Main Hall');
const _table = DiningTableDefinition(
  id: 't1',
  floorId: 'f1',
  name: 'T1',
  sizeLabel: 'square',
  seats: 4,
  sortOrder: 1,
);

class _FakeStorage implements OrderStorageService {
  @override
  Future<void> assertNoPendingCombine() async {}
  @override
  Future<int> fetchNextOrderNumber() async => 1;
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
  Future<void> saveDiningTableSession(DiningTableSession session) async {}
  @override
  Future<List<DiningTableSession>> loadDiningTableSessions() async => const [];
  @override
  Future<void> clearDiningTable(String tableId) async {}
  @override
  Future<void> deleteHeldOrder(String id) async {}
  @override
  Future<void> clearHeldOrders() async {}
  @override
  Future<void> clearAllData() async {}
}

/// [_FakeStorage] plus a draft-recovery guard the test can switch on: while
/// it is blocked, every cart edit is refused (_cartMutationAllowed).
class _GuardedStorage extends _FakeStorage implements DraftRecoveryGuard {
  @override
  final ValueNotifier<bool> recoveryBlocked = ValueNotifier(false);
  @override
  Future<void> refreshRecoveryGuard() async {}
  @override
  Future<void> assertDraftNotRetired({
    String? uuid,
    String? tableId,
    String? reference,
    String? occupiedAt,
    String? seatingKey,
  }) async {}
}

PosController _buildController({
  List<Product> products = const [_latte, _cake],
  List<DiningFloor> floors = const <DiningFloor>[],
  List<DiningTableDefinition> tables = const <DiningTableDefinition>[],
}) {
  final controller = PosController(orderStorage: _FakeStorage());
  controller.applyCatalog(
    categories: const ['X'],
    products: products,
    floors: floors,
    tables: tables,
    taxes: const <CompanyTax>[],
  );
  return controller;
}

OrderSessionDraft _draft({
  required List<CartItem> items,
  OrderType orderType = OrderType.quickOrder,
  String reference = 'DRAFT-1',
  String tableId = '',
}) {
  return OrderSessionDraft(
    orderReference: reference,
    orderType: orderType,
    selectedCategory: 'X',
    customerReferenceNumber: '',
    diningFloorId: tableId.isEmpty ? '' : 'f1',
    diningFloorLabel: tableId.isEmpty ? '' : 'Main Hall',
    diningTableId: tableId,
    diningTableName: tableId.isEmpty ? '' : 'T1',
    items: items,
    discount: const DiscountConfiguration(),
    splitCount: 1,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('machine comp quantity source rules', () {
    test('line target starts at N, re-initializes, and whole-order nulls qty', () {
      final cart = <CartItem>[
        CartItem(product: _latte, qty: 3),
        CartItem(product: _cake, qty: 2),
      ];
      final draft = MachineCompSelectionDraft();

      draft.selectTarget(0, cart);
      expect(draft.lineIndex, 0);
      expect(draft.qty, 3);
      expect(draft.normalizedQty(cart), isNull);

      draft.changeQty(-1, cart);
      expect(draft.qty, 2);
      expect(draft.normalizedQty(cart), 2);
      draft.changeQty(1, cart);
      expect(draft.qty, 3);
      expect(draft.normalizedQty(cart), isNull);

      draft.selectTarget(1, cart);
      expect(draft.lineIndex, 1);
      expect(draft.qty, 2);
      expect(draft.normalizedQty(cart), isNull);

      draft.selectTarget(null, cart);
      expect(draft.lineIndex, isNull);
      expect(draft.qty, isNull);
      expect(draft.normalizedQty(cart), isNull);
    });

    test('dialog preview uses D-B1 integer rounding and guard order', () {
      final partialUnderCap = machineLineCompPreviewBaisas(
        lineTotalBaisas: 1200,
        lineDiscountBaisas: 200,
        lineQty: 3,
        compQty: 1,
      );
      expect(partialUnderCap, 333);
      expect(partialUnderCap, lessThanOrEqualTo(500));
      expect(
        machineLineCompPreviewBaisas(
          lineTotalBaisas: 1200,
          lineDiscountBaisas: 200,
          lineQty: 3,
          compQty: 3,
        ),
        greaterThan(500),
      );
      expect(
        machineLineCompPreviewBaisas(
          lineTotalBaisas: 1200,
          lineDiscountBaisas: 200,
          lineQty: 3,
          compQty: 2,
        ),
        667,
      );
      expect(
        machineLineCompPreviewBaisas(
          lineTotalBaisas: 1100,
          lineDiscountBaisas: 99,
          lineQty: 2,
          compQty: 1,
        ),
        501,
      );
      expect(
        machineLineCompPreviewBaisas(
          lineTotalBaisas: 100,
          lineDiscountBaisas: 200,
          lineQty: 0,
          compQty: 1,
        ),
        0,
      );
    });

    test('AppliedComp enforces whole-order qty null and maps partial qty', () {
      const whole = AppliedComp(
        reasonId: 1,
        reasonName: 'Whole',
        qty: 1,
      );
      expect(whole.qty, isNull);

      const partial = AppliedComp(
        reasonId: 2,
        reasonName: 'Partial',
        lineIndex: 0,
        qty: 1,
      );
      final restored = AppliedComp.fromMap(partial.toMap());
      expect(restored.lineIndex, 0);
      expect(restored.qty, 1);
    });

    test('controller normalizes n == N to null before snapshot and pricing', () {
      final controller = _buildController();
      addTearDown(controller.dispose);
      controller.addProduct(_latte);
      controller.addProduct(_latte);

      controller.applyComp(const AppliedComp(
        reasonId: 1,
        reasonName: 'Full line',
        lineIndex: 0,
        qty: 2,
      ));

      expect(controller.appliedComp!.qty, isNull);
      expect(controller.snapshot().compQty, isNull);
      expect(controller.managerCompAmount, 4.0);
    });
  });

  group('machine stale comp invalidation', () {
    void expectSuccessfulEditDrops({
      required void Function(PosController) arrange,
      required void Function(PosController) edit,
    }) {
      final controller = _buildController();
      arrange(controller);
      var notices = 0;
      controller.onCompClearedAfterCartEdit = () => notices++;
      controller.applyComp(
        const AppliedComp(reasonId: 7, reasonName: 'Service recovery'),
      );

      edit(controller);

      expect(controller.appliedComp, isNull);
      expect(notices, 1);
      controller.dispose();
    }

    test('add, move, requantify, remove, and addBundle drop the comp once', () {
      expectSuccessfulEditDrops(
        arrange: (c) => c.addProduct(_latte),
        edit: (c) => c.addProduct(_cake),
      );
      expectSuccessfulEditDrops(
        arrange: (c) {
          c.addProduct(_latte);
          c.addProduct(_cake);
        },
        edit: (c) => c.addProduct(_latte),
      );
      expectSuccessfulEditDrops(
        arrange: (c) => c.addProduct(_latte),
        edit: (c) => c.incrementCartItem(c.cart.single),
      );
      expectSuccessfulEditDrops(
        arrange: (c) {
          c.addProduct(_latte);
          c.addProduct(_latte);
        },
        edit: (c) => c.decreaseCartItem(c.cart.single),
      );
      expectSuccessfulEditDrops(
        arrange: (c) => c.addProduct(_latte),
        edit: (c) => c.removeCartItem(c.cart.single),
      );
      expectSuccessfulEditDrops(
        arrange: (c) => c.addProduct(_latte),
        edit: (c) => c.addBundle(_bundle, const [_cake, _latte]),
      );
    });

    test('blocked and no-op mutations retain the comp and emit no notice', () {
      // LAUNCH-P2: the shelf cap no longer blocks a cart edit, so a pending
      // draft recovery is the blocker here.
      final storage = _GuardedStorage();
      final controller = PosController(orderStorage: storage);
      controller.applyCatalog(
        categories: const ['X'],
        products: const [_latte],
        floors: const <DiningFloor>[],
        tables: const <DiningTableDefinition>[],
        taxes: const <CompanyTax>[],
      );
      addTearDown(controller.dispose);
      controller.addProduct(_latte);
      var notices = 0;
      controller.onCompClearedAfterCartEdit = () => notices++;
      controller.applyComp(
        const AppliedComp(reasonId: 7, reasonName: 'Service recovery'),
      );

      storage.recoveryBlocked.value = true;
      controller.addProduct(_latte);
      controller.incrementCartItem(controller.cart.single);
      storage.recoveryBlocked.value = false;
      expect(controller.cart.single.qty, 1);
      controller.addBundle(_bundle, const []);
      controller.removeCartItem(CartItem(product: _latte));
      controller.decreaseCartItem(CartItem(product: _latte));

      expect(controller.appliedComp, isNotNull);
      expect(notices, 0);
    });

    test('line comp does not survive into a loaded dining-table draft', () async {
      final controller = _buildController(
        floors: const [_floor],
        tables: const [_table],
      );
      addTearDown(controller.dispose);
      controller.addProduct(_latte);
      controller.applyComp(const AppliedComp(
        reasonId: 7,
        reasonName: 'Service recovery',
        lineIndex: 0,
      ));
      var notices = 0;
      controller.onCompClearedAfterCartEdit = () => notices++;
      final draft = _draft(
        items: [CartItem(product: _cake, qty: 2)],
        orderType: OrderType.dineIn,
        tableId: 't1',
      );
      controller.diningTableSessions = [
        DiningTableSession(
          tableId: 't1',
          floorId: 'f1',
          status: DiningTableStatus.occupied,
          updatedAt: DateTime(2026, 8, 24, 12),
          orderReference: draft.orderReference,
          occupiedAt: DateTime(2026, 8, 24, 12),
          draft: draft,
        ),
      ];

      await controller.openDiningTable('t1');

      expect(controller.appliedComp, isNull);
      expect(notices, 1);
      expect(controller.cart.map((item) => item.product.id), ['2']);
      expect(controller.cart.single.qty, 2);
    });

    test('whole-order comp does not survive onto a fresh table cart', () async {
      final controller = _buildController(
        floors: const [_floor],
        tables: const [_table],
      );
      addTearDown(controller.dispose);
      controller.addProduct(_latte);
      controller.applyComp(const AppliedComp(
        reasonId: 7,
        reasonName: 'Service recovery',
      ));
      var notices = 0;
      controller.onCompClearedAfterCartEdit = () => notices++;

      await controller.openDiningTable('t1');

      expect(controller.appliedComp, isNull);
      expect(notices, 1);
      expect(controller.cart, isEmpty);
    });

    test('resumeHeldOrder drops the outgoing carts comp', () async {
      final controller = _buildController();
      addTearDown(controller.dispose);
      controller.addProduct(_latte);
      controller.applyComp(const AppliedComp(
        reasonId: 7,
        reasonName: 'Service recovery',
        lineIndex: 0,
      ));
      var notices = 0;
      controller.onCompClearedAfterCartEdit = () => notices++;
      final draft = _draft(
        items: [CartItem(product: _cake, qty: 2)],
        reference: 'HELD-1',
      );
      final held = HeldOrderRecord(
        id: 'held-1',
        orderReference: 'HELD-1',
        orderType: OrderType.quickOrder,
        heldAt: DateTime(2026, 8, 24, 12),
        draft: draft,
      );

      await controller.resumeHeldOrder(held);

      expect(controller.appliedComp, isNull);
      expect(notices, 1);
      expect(controller.cart.map((item) => item.product.id), ['2']);
      expect(controller.cart.single.qty, 2);
    });

    test('the free-table reuse branch preserves the cart and comp', () async {
      final controller = _buildController(
        floors: const [_floor],
        tables: const [_table],
      );
      addTearDown(controller.dispose);
      controller.addProduct(_latte);
      controller.applyComp(const AppliedComp(
        reasonId: 7,
        reasonName: 'Service recovery',
        lineIndex: 0,
      ));
      var notices = 0;
      controller.onCompClearedAfterCartEdit = () => notices++;
      await controller.selectOrderType(OrderType.dineIn);
      final originalLine = controller.cart.single;
      final originalComp = controller.appliedComp;

      await controller.openDiningTable('t1');

      expect(controller.appliedComp, same(originalComp));
      expect(notices, 0);
      expect(controller.cart, hasLength(1));
      expect(controller.cart.single, same(originalLine));
    });

    test('modifier customization drops the line comp after changing the cart', () {
      final controller = _buildController();
      addTearDown(controller.dispose);
      controller.addProduct(_latte);
      controller.applyComp(const AppliedComp(
        reasonId: 7,
        reasonName: 'Service recovery',
        lineIndex: 0,
      ));
      var notices = 0;
      controller.onCompClearedAfterCartEdit = () => notices++;

      controller.updateCartItemCustomization(
        controller.cart.single,
        modifiers: const [
          CartItemModifier(
            id: '9',
            group: 'Milk',
            label: 'Oat',
            price: 0.5,
          ),
        ],
        notes: ' extra hot ',
      );

      expect(controller.appliedComp, isNull);
      expect(notices, 1);
      expect(controller.cart.single.modifiers.single.label, 'Oat');
      expect(controller.cart.single.notes, 'extra hot');
    });

    test('gift toggle retains the comp as the deliberate exception', () {
      final controller = _buildController();
      addTearDown(controller.dispose);
      controller.addProduct(_latte);
      var notices = 0;
      controller.onCompClearedAfterCartEdit = () => notices++;
      controller.applyComp(const AppliedComp(
        reasonId: 7,
        reasonName: 'Service recovery',
        lineIndex: 0,
      ));

      expect(controller.toggleGiftItem(controller.cart.single), isTrue);

      expect(controller.appliedComp, isNotNull);
      expect(notices, 0);
    });
  });
}
