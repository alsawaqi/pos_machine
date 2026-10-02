import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'support/fake_order_storage.dart';

/// Phase 7 stock fields: stock_mode + recipe + per-branch ingredient balances
/// survive parse → catalog. LAUNCH-P2 "sell, but warn": cached stock never
/// makes a product unorderable — only its daily window does (the full P2-7
/// coverage lives in launch_p2_sell_but_warn_test.dart).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('config_mapper — stock fields', () {
    test('toCatalog maps stock_mode + recipe + branchStockQty + balances', () {
      final catalog = ConfigMapper.toCatalog(
        null,
        const <CategoryRow>[],
        [
          const ProductRow(
            id: 10,
            name: 'Latte',
            basePriceBaisas: 1500,
            addonGroupIds: '',
            deliveryPricesJson: '{}',
            recipeJson: '[{"ingredient_id":1,"quantity":0.25}]',
            stockMode: 'ingredient',
          ),
          const ProductRow(
            id: 11,
            name: 'Cake',
            basePriceBaisas: 2000,
            addonGroupIds: '',
            deliveryPricesJson: '{}',
            recipeJson: '[]',
            stockMode: 'unit',
            branchStockQty: 0,
          ),
        ],
        const <FloorRow>[],
        const <TableRow>[],
        const <TaxRow>[],
        const <AddonGroupRow>[],
        const <AddonRow>[],
        const <DeliveryProviderRow>[],
        const <ExpenseCategoryRow>[],
        [const BranchIngredientStockRow(ingredientId: 1, quantity: 0.5)],
      );

      final latte = catalog.products.firstWhere((p) => p.id == '10');
      expect(latte.stockMode, 'ingredient');
      expect(latte.recipe.single.ingredientId, 1);
      expect(latte.recipe.single.quantity, closeTo(0.25, 1e-9));

      final cake = catalog.products.firstWhere((p) => p.id == '11');
      expect(cake.stockMode, 'unit');
      expect(cake.branchStockQty, 0);

      expect(catalog.ingredientBalances[1], closeTo(0.5, 1e-9));
    });
  });

  // Gap sweep G1 — per-product daily availability windows.
  group('config_mapper — availability window passthrough', () {
    test('toCatalog carries available_from/available_until', () {
      final catalog = ConfigMapper.toCatalog(
        null,
        const <CategoryRow>[],
        [
          const ProductRow(
            id: 12,
            name: 'Breakfast Wrap',
            basePriceBaisas: 1200,
            addonGroupIds: '',
            deliveryPricesJson: '{}',
            recipeJson: '[]',
            availableFrom: '06:00:00',
            availableUntil: '11:00:00',
          ),
          const ProductRow(
            id: 13,
            name: 'All-Day Cake',
            basePriceBaisas: 2000,
            addonGroupIds: '',
            deliveryPricesJson: '{}',
            recipeJson: '[]',
          ),
        ],
        const <FloorRow>[],
        const <TableRow>[],
        const <TaxRow>[],
        const <AddonGroupRow>[],
        const <AddonRow>[],
        const <DeliveryProviderRow>[],
        const <ExpenseCategoryRow>[],
        const <BranchIngredientStockRow>[],
      );

      final wrap = catalog.products.firstWhere((p) => p.id == '12');
      expect(wrap.availableFrom, '06:00:00');
      expect(wrap.availableUntil, '11:00:00');
      expect(wrap.hasAvailabilityWindow, isTrue);

      final cake = catalog.products.firstWhere((p) => p.id == '13');
      expect(cake.availableFrom, isNull);
      expect(cake.availableUntil, isNull);
      expect(cake.hasAvailabilityWindow, isFalse);
    });
  });

  group('Product.isAvailableAt', () {
    DateTime at(int hour, [int minute = 0, int second = 0]) =>
        DateTime(2026, 6, 10, hour, minute, second);

    const breakfast = Product(
      id: '1',
      name: 'A',
      category: 'X',
      price: 1,
      availableFrom: '06:00:00',
      availableUntil: '11:00:00',
    );

    test('no window = always available', () {
      const p = Product(id: '1', name: 'A', category: 'X', price: 1);
      expect(p.isAvailableAt(at(0)), isTrue);
      expect(p.isAvailableAt(at(23, 59, 59)), isTrue);
    });

    test('simple window, boundaries inclusive', () {
      expect(breakfast.isAvailableAt(at(5, 59, 59)), isFalse);
      expect(breakfast.isAvailableAt(at(6)), isTrue);
      expect(breakfast.isAvailableAt(at(9, 30)), isTrue);
      expect(breakfast.isAvailableAt(at(11)), isTrue);
      expect(breakfast.isAvailableAt(at(11, 0, 1)), isFalse);
      expect(breakfast.isAvailableAt(at(18)), isFalse);
    });

    test('overnight window wraps midnight (22:00 → 02:00)', () {
      const lateMenu = Product(
        id: '1',
        name: 'A',
        category: 'X',
        price: 1,
        availableFrom: '22:00:00',
        availableUntil: '02:00:00',
      );
      expect(lateMenu.isAvailableAt(at(23)), isTrue);
      expect(lateMenu.isAvailableAt(at(1)), isTrue);
      expect(lateMenu.isAvailableAt(at(22)), isTrue);
      expect(lateMenu.isAvailableAt(at(2)), isTrue);
      expect(lateMenu.isAvailableAt(at(12)), isFalse);
      expect(lateMenu.isAvailableAt(at(21, 59, 59)), isFalse);
      expect(lateMenu.isAvailableAt(at(2, 0, 1)), isFalse);
    });

    test('one-sided windows default the missing edge', () {
      const fromOnly = Product(
        id: '1', name: 'A', category: 'X', price: 1, availableFrom: '17:00:00');
      expect(fromOnly.isAvailableAt(at(12)), isFalse);
      expect(fromOnly.isAvailableAt(at(17)), isTrue);
      expect(fromOnly.isAvailableAt(at(23, 59, 59)), isTrue);

      const untilOnly = Product(
        id: '1', name: 'A', category: 'X', price: 1, availableUntil: '11:00:00');
      expect(untilOnly.isAvailableAt(at(0)), isTrue);
      expect(untilOnly.isAvailableAt(at(11)), isTrue);
      expect(untilOnly.isAvailableAt(at(11, 0, 1)), isFalse);
    });

    test("tolerates 'HH:MM' without seconds from raw API callers", () {
      const p = Product(
        id: '1',
        name: 'A',
        category: 'X',
        price: 1,
        availableFrom: '06:00',
        availableUntil: '11:00',
      );
      expect(p.isAvailableAt(at(6)), isTrue);
      expect(p.isAvailableAt(at(11)), isTrue);
      expect(p.isAvailableAt(at(11, 0, 1)), isFalse);
      expect(p.isAvailableAt(at(5, 59, 59)), isFalse);
    });

    test('copyWith (delivery re-price) keeps the window', () {
      final repriced = breakfast.copyWith(price: 9.9);
      expect(repriced.availableFrom, '06:00:00');
      expect(repriced.availableUntil, '11:00:00');
      expect(repriced.price, 9.9);
    });
  });

  group('PosController.isUnorderable', () {
    test('only the window blocks, under the injected clock — never stock', () {
      final c = PosController(orderStorage: FakeOrderStorage());
      addTearDown(c.dispose);
      c.applyCatalog(
        categories: const ['X'],
        products: const [],
        floors: const <DiningFloor>[],
        tables: const <DiningTableDefinition>[],
      );

      const windowed = Product(
        id: '1',
        name: 'A',
        category: 'X',
        price: 1,
        availableFrom: '06:00:00',
        availableUntil: '11:00:00',
      );
      const emptyShelf = Product(
        id: '2',
        name: 'B',
        category: 'X',
        price: 1,
        stockMode: 'unit',
        branchStockQty: 0,
      );

      c.clock = () => DateTime(2026, 6, 10, 9); // inside the window
      expect(c.isOutsideHours(windowed), isFalse);
      expect(c.isUnorderable(windowed), isFalse);
      // LAUNCH-P2 "sell, but warn": an empty shelf never blocks.
      expect(c.isUnorderable(emptyShelf), isFalse);

      c.clock = () => DateTime(2026, 6, 10, 15); // outside the window
      expect(c.isOutsideHours(windowed), isTrue);
      expect(c.isUnorderable(windowed), isTrue);

      // No window → time never blocks it.
      const plain = Product(id: '3', name: 'C', category: 'X', price: 1);
      expect(c.isUnorderable(plain), isFalse);
    });

    test('hasTimeWindowedProducts gates the minute tick', () {
      final c = PosController(orderStorage: FakeOrderStorage());
      addTearDown(c.dispose);
      c.applyCatalog(
        categories: const ['X'],
        products: const [
          Product(id: '1', name: 'A', category: 'X', price: 1),
        ],
        floors: const <DiningFloor>[],
        tables: const <DiningTableDefinition>[],
      );
      expect(c.hasTimeWindowedProducts, isFalse);

      var ticks = 0;
      c.addListener(() => ticks++);
      c.onMinuteTick();
      expect(ticks, 0); // no windows → no rebuild

      c.applyCatalog(
        categories: const ['X'],
        products: const [
          Product(
            id: '1',
            name: 'A',
            category: 'X',
            price: 1,
            availableFrom: '06:00:00',
            availableUntil: '11:00:00',
          ),
        ],
        floors: const <DiningFloor>[],
        tables: const <DiningTableDefinition>[],
      );
      expect(c.hasTimeWindowedProducts, isTrue);
      ticks = 0;
      c.onMinuteTick();
      expect(ticks, 1);
    });
  });

  // #3 — a sale decrements a cooked/unit product's cached shelf count.
  // LAUNCH-P2 "sell, but warn": that count is informational — the cart may
  // exceed it and the product stays orderable at zero.
  group('#3 shelf count (informational) + sale decrement', () {
    PosController withProducts(List<Product> products) {
      final c = PosController(orderStorage: FakeOrderStorage());
      c.applyCatalog(
        categories: const ['X'],
        products: products,
        floors: const <DiningFloor>[],
        tables: const <DiningTableDefinition>[],
      );
      return c;
    }

    const unit3 = Product(
      id: '1', name: 'Cake', category: 'X', price: 1,
      stockMode: 'unit', branchStockQty: 3,
    );
    const cooked2 = Product(
      id: '2', name: 'Soup', category: 'X', price: 1,
      stockMode: 'cooked', branchStockQty: 2,
    );

    test('cart may exceed the produced shelf count (unit + cooked)', () {
      final c = withProducts(const [unit3, cooked2]);
      addTearDown(c.dispose);

      for (var i = 0; i < 4; i++) {
        c.addProduct(unit3); // 4 sold, only 3 made — still allowed
      }
      expect(c.cartQuantityForProduct('1'), 4);

      for (var i = 0; i < 3; i++) {
        c.addProduct(cooked2);
      }
      expect(c.cartQuantityForProduct('2'), 3);
    });

    test('untracked / unbounded products add freely', () {
      const untracked =
          Product(id: '5', name: 'U', category: 'X', price: 1, stockMode: 'untracked');
      // unit mode but no branch count = not shelf-tracked here.
      const unitNoShelf =
          Product(id: '6', name: 'N', category: 'X', price: 1, stockMode: 'unit');
      final c = withProducts(const [untracked, unitNoShelf]);
      addTearDown(c.dispose);
      for (var i = 0; i < 5; i++) {
        c.addProduct(untracked);
        c.addProduct(unitNoShelf);
      }
      expect(c.cartQuantityForProduct('5'), 5);
      expect(c.cartQuantityForProduct('6'), 5);
    });

    test('a sale decrements the shelf count + fires the persist callback', () {
      final c = withProducts(const [unit3]);
      addTearDown(c.dispose);
      Map<int, double>? persisted;
      c.onShelfStockConsumed = (m) => persisted = m;

      c.applyShelfStockConsumption({'1': 2.0});

      final p = c.allProducts.firstWhere((x) => x.id == '1');
      expect(p.branchStockQty, 1); // made 3, sold 2 → 1 left
      expect(persisted, {1: 2.0});
      expect(c.isUnorderable(p), isFalse);
    });

    test('selling past the shelf clamps the cached count at 0 and the '
        'product stays orderable', () {
      final c = withProducts(const [unit3]);
      addTearDown(c.dispose);
      c.applyShelfStockConsumption({'1': 5.0}); // oversold → clamp 0
      final p = c.allProducts.firstWhere((x) => x.id == '1');
      expect(p.branchStockQty, 0);
      expect(c.isUnorderable(p), isFalse);
    });

    test('a bundle may take a finite-shelf pick past its count', () {
      const offer = Offer(id: 1, name: 'Combo', type: 'bundle');
      final c = withProducts(const [unit3]);
      addTearDown(c.dispose);

      c.addBundle(offer, const [unit3, unit3]);
      expect(c.cartQuantityForProduct('1'), 2);

      // 4 > 3 on the shelf — the bundle is still added (sell, but warn).
      c.addBundle(offer, const [unit3, unit3]);
      expect(c.cartQuantityForProduct('1'), 4);
    });
  });
}
