import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/state/pos_controller.dart';

const _latte = Product(id: '1', name: 'Latte', category: 'X', price: 2.0);
const _cake = Product(id: '2', name: 'Cake', category: 'X', price: 3.0);
const _bundle = Offer(id: 9, name: 'Pair', type: 'bundle');

PosController _buildController({List<Product> products = const [_latte, _cake]}) {
  final controller = PosController();
  controller.applyCatalog(
    categories: const ['X'],
    products: products,
    floors: const <DiningFloor>[],
    tables: const <DiningTableDefinition>[],
    taxes: const <CompanyTax>[],
  );
  return controller;
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
      const capped = Product(
        id: '3',
        name: 'Capped',
        category: 'X',
        price: 1,
        stockMode: 'unit',
        branchStockQty: 1,
      );
      final controller = _buildController(products: const [capped]);
      addTearDown(controller.dispose);
      controller.addProduct(capped);
      var notices = 0;
      controller.onCompClearedAfterCartEdit = () => notices++;
      controller.applyComp(
        const AppliedComp(reasonId: 7, reasonName: 'Service recovery'),
      );

      controller.addProduct(capped);
      controller.incrementCartItem(controller.cart.single);
      controller.addBundle(_bundle, const []);
      controller.removeCartItem(CartItem(product: capped));
      controller.decreaseCartItem(CartItem(product: capped));

      expect(controller.appliedComp, isNotNull);
      expect(notices, 0);
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
