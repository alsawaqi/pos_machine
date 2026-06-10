import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/state/pos_controller.dart';

/// Phase 7 device sold-out: stock_mode + recipe + per-branch ingredient balances
/// survive parse → catalog, and isOutOfStock blocks unit products at 0 and
/// ingredient products whose recipe ingredient ran low.
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

  group('PosController.isOutOfStock', () {
    PosController make(Map<int, double> balances) {
      final c = PosController();
      c.applyCatalog(
        categories: const ['X'],
        products: const [],
        floors: const <DiningFloor>[],
        tables: const <DiningTableDefinition>[],
        ingredientBalances: balances,
      );
      return c;
    }

    test('unit: out when branch count <= 0, available otherwise', () {
      final c = make(const {});
      addTearDown(c.dispose);
      expect(
        c.isOutOfStock(const Product(
            id: '1', name: 'A', category: 'X', price: 1, stockMode: 'unit', branchStockQty: 0)),
        isTrue,
      );
      expect(
        c.isOutOfStock(const Product(
            id: '1', name: 'A', category: 'X', price: 1, stockMode: 'unit', branchStockQty: 5)),
        isFalse,
      );
      // null branch stock = not unit-tracked here → available.
      expect(
        c.isOutOfStock(const Product(
            id: '1', name: 'A', category: 'X', price: 1, stockMode: 'unit')),
        isFalse,
      );
    });

    test('ingredient: out when any recipe ingredient balance < needed', () {
      final c = make(const {1: 0.5, 2: 0.0});
      addTearDown(c.dispose);
      expect(
        c.isOutOfStock(const Product(
            id: '1', name: 'A', category: 'X', price: 1, stockMode: 'ingredient',
            recipe: [RecipeLine(ingredientId: 1, quantity: 0.25)])),
        isFalse,
      );
      expect(
        c.isOutOfStock(const Product(
            id: '2', name: 'B', category: 'X', price: 1, stockMode: 'ingredient',
            recipe: [RecipeLine(ingredientId: 1, quantity: 0.9)])),
        isTrue,
      );
      // Missing ingredient = balance 0.
      expect(
        c.isOutOfStock(const Product(
            id: '3', name: 'C', category: 'X', price: 1, stockMode: 'ingredient',
            recipe: [RecipeLine(ingredientId: 9, quantity: 0.1)])),
        isTrue,
      );
      // One line ok, the other depleted.
      expect(
        c.isOutOfStock(const Product(
            id: '4', name: 'D', category: 'X', price: 1, stockMode: 'ingredient',
            recipe: [RecipeLine(ingredientId: 1, quantity: 0.1), RecipeLine(ingredientId: 2, quantity: 0.1)])),
        isTrue,
      );
    });

    test('untracked / null mode is always available', () {
      final c = make(const {});
      addTearDown(c.dispose);
      expect(
        c.isOutOfStock(const Product(
            id: '1', name: 'A', category: 'X', price: 1, stockMode: 'untracked')),
        isFalse,
      );
      expect(
        c.isOutOfStock(const Product(id: '1', name: 'A', category: 'X', price: 1)),
        isFalse,
      );
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
    test('composes sold-out OR outside-hours under the injected clock', () {
      final c = PosController();
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
      const soldOut = Product(
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
      expect(c.isUnorderable(soldOut), isTrue); // sold out regardless of time

      c.clock = () => DateTime(2026, 6, 10, 15); // outside the window
      expect(c.isOutsideHours(windowed), isTrue);
      expect(c.isUnorderable(windowed), isTrue);

      // No window → time never blocks it.
      const plain = Product(id: '3', name: 'C', category: 'X', price: 1);
      expect(c.isUnorderable(plain), isFalse);
    });

    test('hasTimeWindowedProducts gates the minute tick', () {
      final c = PosController();
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
}
