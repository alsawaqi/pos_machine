import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/kitchen_production.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/state/pos_controller.dart';

/// P-G1 — kitchen production: the kitchen_positions policy flow
/// (config → meta → catalog → controller gate), cooked sold-out
/// semantics, and the /device/kitchen payload parsing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('kitchen_positions policy', () {
    test('flows config → meta → catalog → controller gate', () {
      final parsed = ConfigMapper.parse(<String, dynamic>{
        'settings': {
          'order_cancel_positions': ['manager'],
          'reports_positions': ['manager'],
          'kitchen_positions': ['kitchen', 'manager'],
        },
      });
      expect(parsed.meta.kitchenPositions.value, '["kitchen","manager"]');

      final controller = PosController();
      addTearDown(controller.dispose);
      controller.applyCatalog(
        categories: const ['X'],
        products: const [],
        floors: const <DiningFloor>[],
        tables: const <DiningTableDefinition>[],
        kitchenPositions: const ['kitchen', 'manager'],
      );
      expect(controller.positionCanUseKitchen('Kitchen'), isTrue);
      expect(controller.positionCanUseKitchen('manager'), isTrue);
      expect(controller.positionCanUseKitchen('cashier'), isFalse);
      expect(controller.positionCanUseKitchen(null), isFalse);
    });

    test('defaults to managers-only when the setting never synced', () {
      final controller = PosController();
      addTearDown(controller.dispose);
      expect(controller.positionCanUseKitchen('manager'), isTrue);
      expect(controller.positionCanUseKitchen('kitchen'), isFalse);
    });
  });

  group('cooked sold-out semantics', () {
    PosController controller() {
      final c = PosController();
      addTearDown(c.dispose);
      return c;
    }

    test('a cooked product with NO shelf count yet is sold out', () {
      const cake = Product(
        id: '1',
        name: 'Cake',
        category: 'Dessert',
        price: 5.0,
        stockMode: 'cooked',
      );
      expect(controller().isOutOfStock(cake), isTrue);
    });

    test('a cooked product with shelf stock is available, 0 is sold out', () {
      const onShelf = Product(
        id: '1',
        name: 'Cake',
        category: 'Dessert',
        price: 5.0,
        stockMode: 'cooked',
        branchStockQty: 4,
      );
      const soldDown = Product(
        id: '1',
        name: 'Cake',
        category: 'Dessert',
        price: 5.0,
        stockMode: 'cooked',
        branchStockQty: 0,
      );
      final c = controller();
      expect(c.isOutOfStock(onShelf), isFalse);
      expect(c.isOutOfStock(soldDown), isTrue);
    });

    test('unit semantics are unchanged: NO count means untracked-available',
        () {
      const unitNoCount = Product(
        id: '2',
        name: 'Chips',
        category: 'Snacks',
        price: 0.5,
        stockMode: 'unit',
      );
      expect(controller().isOutOfStock(unitNoCount), isFalse);
    });
  });

  group('KitchenData parsing', () {
    test('parses the /device/kitchen payload', () {
      final data = KitchenData.fromJson(<String, dynamic>{
        'products': [
          {
            'id': 1,
            'uuid': 'u-1',
            'name': 'Cake',
            'name_ar': 'كيكة',
            'category_id': 7,
            'branch_stock_qty': 2.0,
            'max_producible': 10,
            'recipe': [
              {
                'ingredient_id': 5,
                'name': 'Flour',
                'name_ar': null,
                'quantity': 0.5,
                'unit': 'kg',
                'branch_balance': 5.0,
              },
            ],
          },
        ],
        'ingredients': [
          {'id': 5, 'name': 'Flour', 'unit': 'kg', 'branch_balance': 5.0},
        ],
        'active': [
          {
            'uuid': 'p-1',
            'status': 'in_progress',
            'product_id': 1,
            'product_name': 'Cake',
            'quantity': 4.0,
            'started_at': '2026-06-12T10:00:00+04:00',
            'started_by': 'Sami',
            'lines': [
              {
                'ingredient_id': 5,
                'name': 'Flour',
                'quantity': 2.0,
                'unit': 'kg',
                'is_extra': false,
              },
              {
                'ingredient_id': 6,
                'name': 'Sugar',
                'quantity': 0.1,
                'unit': 'kg',
                'is_extra': true,
              },
            ],
          },
        ],
      });

      expect(data.products.single.name, 'Cake');
      expect(data.products.single.maxProducible, 10);
      expect(data.products.single.branchStockQty, 2.0);
      expect(data.products.single.recipe.single.branchBalance, 5.0);
      expect(data.ingredients.single.unit, 'kg');
      final batch = data.active.single;
      expect(batch.uuid, 'p-1');
      expect(batch.quantity, 4.0);
      expect(batch.startedBy, 'Sami');
      expect(batch.lines.where((l) => l.isExtra).single.quantity, 0.1);
    });

    test('an empty body decodes to empty lists', () {
      final data = KitchenData.fromJson(const <String, dynamic>{});
      expect(data.products, isEmpty);
      expect(data.ingredients, isEmpty);
      expect(data.active, isEmpty);
    });
  });
}
