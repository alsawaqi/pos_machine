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
}
