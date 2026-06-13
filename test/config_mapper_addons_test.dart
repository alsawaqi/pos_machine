import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/state/pos_controller.dart';

/// Covers the product add-on wiring: the API `addon_group_ids` + `addon_groups`
/// survive parse → Drift companions, become AddonGroups (baisas → OMR) in
/// toCatalog, and the controller resolves a product's groups in its id order.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConfigMapper add-ons', () {
    test('parse() captures addon_group_ids and builds groups + addons', () {
      final parsed = ConfigMapper.parse(<String, dynamic>{
        'products': [
          {
            'id': 10,
            'name': 'Latte',
            'category_id': 1,
            'base_price_baisas': 1500,
            'addon_group_ids': [5, 6],
          },
          {
            'id': 11,
            'name': 'Water',
            'category_id': 1,
            'base_price_baisas': 500,
          },
        ],
        'addon_groups': [
          {
            'id': 5,
            'name': 'Size',
            'selection_mode': 'single',
            'addons': [
              {
                'id': 100,
                'add_on_group_id': 5,
                'name': 'Large',
                'price_delta_baisas': 500,
              },
            ],
          },
          {
            'id': 6,
            'name': 'Extras',
            'selection_mode': 'multiple',
            'addons': [
              {
                'id': 101,
                'add_on_group_id': 6,
                'name': 'Extra shot',
                'price_delta_baisas': 300,
              },
            ],
          },
        ],
      });

      expect(parsed.products.first.addonGroupIds.value, '5,6');
      expect(parsed.products[1].addonGroupIds.value, '');
      expect(parsed.addonGroups.length, 2);
      expect(parsed.addons.length, 2);
    });

    test('toCatalog() builds AddonGroups (OMR deltas) and attaches ids', () {
      final catalog = ConfigMapper.toCatalog(
        null,
        [const CategoryRow(id: 1, name: 'Coffee', displayOrder: 0, addonGroupIdsJson: '[]')],
        [
          const ProductRow(
            id: 10,
            name: 'Latte',
            categoryId: 1,
            basePriceBaisas: 1500,
            addonGroupIds: '5,6',
            deliveryPricesJson: '{}',
            recipeJson: '[]',
          ),
          const ProductRow(
            id: 11,
            name: 'Water',
            categoryId: 1,
            basePriceBaisas: 500,
            addonGroupIds: '',
            deliveryPricesJson: '{}',
            recipeJson: '[]',
          ),
        ],
        const <FloorRow>[],
        const <TableRow>[],
        const <TaxRow>[],
        [
          const AddonGroupRow(id: 5, name: 'Size', selectionMode: 'single'),
          const AddonGroupRow(id: 6, name: 'Extras', selectionMode: 'multiple'),
        ],
        [
          const AddonRow(
            id: 100,
            addOnGroupId: 5,
            name: 'Large',
            priceDeltaBaisas: 500,
            isDefault: false,
            consumptionJson: '[]',
          ),
          const AddonRow(
            id: 101,
            addOnGroupId: 6,
            name: 'Extra shot',
            priceDeltaBaisas: 300,
            isDefault: false,
            consumptionJson: '[]',
          ),
        ],
      );

      expect(catalog.addonGroups.length, 2);

      final size = catalog.addonGroups.firstWhere((g) => g.id == 5);
      expect(size.multiSelect, isFalse);
      expect(size.options.single.label, 'Large');
      expect(size.options.single.priceDelta, closeTo(0.5, 1e-9));

      final extras = catalog.addonGroups.firstWhere((g) => g.id == 6);
      expect(extras.multiSelect, isTrue);
      expect(extras.options.single.priceDelta, closeTo(0.3, 1e-9));

      final latte = catalog.products.firstWhere((p) => p.id == '10');
      expect(latte.addonGroupIds, [5, 6]);
      final water = catalog.products.firstWhere((p) => p.id == '11');
      expect(water.addonGroupIds, isEmpty);
    });

    test('inactive groups/addons are dropped from the catalog', () {
      final catalog = ConfigMapper.toCatalog(
        null,
        const <CategoryRow>[],
        const <ProductRow>[],
        const <FloorRow>[],
        const <TableRow>[],
        const <TaxRow>[],
        [
          const AddonGroupRow(id: 5, name: 'Size', selectionMode: 'single'),
          const AddonGroupRow(
            id: 9,
            name: 'Archived',
            selectionMode: 'single',
            status: 'inactive',
          ),
        ],
        [
          const AddonRow(
            id: 100,
            addOnGroupId: 5,
            name: 'Large',
            priceDeltaBaisas: 500,
            isDefault: false,
            consumptionJson: '[]',
          ),
          const AddonRow(
            id: 101,
            addOnGroupId: 5,
            name: 'Retired',
            priceDeltaBaisas: 300,
            status: 'inactive',
            isDefault: false,
            consumptionJson: '[]',
          ),
        ],
      );

      expect(catalog.addonGroups.map((g) => g.id), [5]);
      expect(catalog.addonGroups.single.options.single.label, 'Large');
    });
  });

  group('PosController.addonGroupsForProduct', () {
    test('resolves a product\'s groups in its assigned id order', () {
      final controller = PosController();
      addTearDown(controller.dispose);

      const latte = Product(
        id: '10',
        name: 'Latte',
        category: 'Coffee',
        price: 1.5,
        addonGroupIds: [6, 5], // intentionally not ascending
      );
      const water =
          Product(id: '11', name: 'Water', category: 'Coffee', price: 0.5);

      controller.applyCatalog(
        categories: const ['Coffee'],
        products: const [latte, water],
        floors: const <DiningFloor>[],
        tables: const <DiningTableDefinition>[],
        addonGroups: const [
          AddonGroup(
            id: 5,
            name: 'Size',
            multiSelect: false,
            options: [AddonOption(id: 100, label: 'Large', priceDelta: 0.5)],
          ),
          AddonGroup(
            id: 6,
            name: 'Extras',
            multiSelect: true,
            options: [AddonOption(id: 101, label: 'Extra shot', priceDelta: 0.3)],
          ),
        ],
      );

      expect(controller.addonGroupsForProduct(latte).map((g) => g.id).toList(),
          [6, 5]);
      expect(controller.addonGroupsForProduct(water), isEmpty);
    });
  });

  group('AddonGroup constraint clamping', () {
    AddonOption opt(int id) => AddonOption(id: id, label: 'O$id', priceDelta: 0);

    test('min above the satisfiable ceiling clamps instead of bricking Apply', () {
      // min 2 on a SINGLE-choice group can never be satisfied (selection
      // replaces, never accumulates) — the effective requirement becomes 1.
      final single = AddonGroup(
        id: 1,
        name: 'Size',
        multiSelect: false,
        minSelections: 2,
        options: [opt(1), opt(2)],
      );
      expect(single.effectiveMin, 1);
      expect(single.isRequired, isTrue);

      // min above an explicit max clamps to the max.
      final overMax = AddonGroup(
        id: 2,
        name: 'Extras',
        multiSelect: true,
        minSelections: 5,
        maxSelections: 2,
        options: [opt(1), opt(2), opt(3)],
      );
      expect(overMax.effectiveMin, 2);

      // min above the option count on an unbounded multi group clamps to
      // the option count (you cannot pick more options than exist).
      final overOptions = AddonGroup(
        id: 3,
        name: 'Sauces',
        multiSelect: true,
        minSelections: 9,
        options: [opt(1), opt(2)],
      );
      expect(overOptions.effectiveMin, 2);
    });

    test('satisfiable configs pass through unchanged', () {
      final normal = AddonGroup(
        id: 4,
        name: 'Size',
        multiSelect: false,
        minSelections: 1,
        options: [opt(1), opt(2)],
      );
      expect(normal.effectiveMin, 1);

      final optional = AddonGroup(
        id: 5,
        name: 'Extras',
        multiSelect: true,
        options: [opt(1)],
      );
      expect(optional.effectiveMin, 0);
      expect(optional.isRequired, isFalse);
    });
  });

  // P-G3 — product-as-add-on: linked_product_id rides the parse → Drift →
  // catalog pipeline, and the controller greys an option whose linked
  // product is sold out at the branch (same pool as its standalone tile).
  group('P-G3 product-as-add-on', () {
    test('parse() captures linked_product_id on the addon companion', () {
      final parsed = ConfigMapper.parse(<String, dynamic>{
        'addon_groups': [
          {
            'id': 5,
            'name': 'Extras',
            'selection_mode': 'multiple',
            'addons': [
              {
                'id': 100,
                'add_on_group_id': 5,
                'name': 'Cake slice',
                'price_delta_baisas': 1500,
                'linked_product_id': 77,
              },
              {
                'id': 101,
                'add_on_group_id': 5,
                'name': 'Extra shot',
                'price_delta_baisas': 300,
              },
            ],
          },
        ],
      });

      expect(parsed.addons.first.linkedProductId.value, 77);
      expect(parsed.addons[1].linkedProductId.value, isNull);
    });

    test('toCatalog() emits linkedProductId on the AddonOption', () {
      final catalog = ConfigMapper.toCatalog(
        null,
        const <CategoryRow>[],
        const <ProductRow>[],
        const <FloorRow>[],
        const <TableRow>[],
        const <TaxRow>[],
        [const AddonGroupRow(id: 5, name: 'Extras', selectionMode: 'multiple')],
        [
          const AddonRow(
            id: 100,
            addOnGroupId: 5,
            name: 'Cake slice',
            priceDeltaBaisas: 1500,
            isDefault: false,
            linkedProductId: 77,
            consumptionJson: '[]',
          ),
          const AddonRow(
            id: 101,
            addOnGroupId: 5,
            name: 'Extra shot',
            priceDeltaBaisas: 300,
            isDefault: false,
            consumptionJson: '[]',
          ),
        ],
      );

      final options = catalog.addonGroups.single.options;
      expect(options.first.linkedProductId, 77);
      expect(options[1].linkedProductId, isNull);
    });

    test('isAddonOptionUnavailable mirrors the linked product sold-out state', () {
      final controller = PosController();
      addTearDown(controller.dispose);

      const cakeInStock = Product(
        id: '77',
        name: 'Cake',
        category: 'Dessert',
        price: 5,
        stockMode: 'cooked',
        branchStockQty: 3,
      );
      const juice = Product(
        id: '78',
        name: 'Juice',
        category: 'Drinks',
        price: 2,
        stockMode: 'ingredient',
        recipe: [RecipeLine(ingredientId: 1, quantity: 0.3)],
      );

      controller.applyCatalog(
        categories: const ['Dessert', 'Drinks'],
        products: const [cakeInStock, juice],
        floors: const <DiningFloor>[],
        tables: const <DiningTableDefinition>[],
        // Orange (1): 0.2 L on the shelf — below the 0.3 L one juice needs.
        ingredientBalances: const {1: 0.2},
      );

      const cakeOption =
          AddonOption(id: 1, label: 'Cake slice', priceDelta: 1.5, linkedProductId: 77);
      const juiceOption =
          AddonOption(id: 2, label: 'Fresh juice', priceDelta: 1.0, linkedProductId: 78);
      const classicOption = AddonOption(id: 3, label: 'Extra shot', priceDelta: 0.3);
      const orphanOption =
          AddonOption(id: 4, label: 'Ghost', priceDelta: 1.0, linkedProductId: 999);

      // Cake has shelf stock -> sellable; juice is ingredient-short -> grey.
      expect(controller.isAddonOptionUnavailable(cakeOption), isFalse);
      expect(controller.isAddonOptionUnavailable(juiceOption), isTrue);
      // Classic options never grey; a link to a product missing from the
      // branch catalog greys (can't fulfil it here).
      expect(controller.isAddonOptionUnavailable(classicOption), isFalse);
      expect(controller.isAddonOptionUnavailable(orphanOption), isTrue);

      // The cake sells out (shelf hits zero) -> its option greys too.
      controller.applyCatalog(
        categories: const ['Dessert'],
        products: const [
          Product(
            id: '77',
            name: 'Cake',
            category: 'Dessert',
            price: 5,
            stockMode: 'cooked',
            branchStockQty: 0,
          ),
        ],
        floors: const <DiningFloor>[],
        tables: const <DiningTableDefinition>[],
      );
      expect(controller.isAddonOptionUnavailable(cakeOption), isTrue);
    });
  });

  // PD3b — per-option stock-usage lines: parse → Drift → catalog, and the
  // controller gates 'add' lines on what the device can see (ingredient
  // balances + cached product stock); removal lines never gate; a product
  // id missing from the config (internal packaging) is skipped.
  group('PD3b per-option consumption', () {
    test('parse() caches the consumption lines as JSON', () {
      final parsed = ConfigMapper.parse(<String, dynamic>{
        'addon_groups': [
          {
            'id': 5,
            'name': 'Extras',
            'selection_mode': 'multiple',
            'addons': [
              {
                'id': 100,
                'add_on_group_id': 5,
                'name': 'Extra patty',
                'price_delta_baisas': 500,
                'consumption': [
                  {'type': 'product', 'product_id': 3, 'direction': 'add', 'qty': 1, 'unit': null},
                ],
              },
              {
                'id': 101,
                'add_on_group_id': 5,
                'name': 'Plain',
                'price_delta_baisas': 0,
              },
            ],
          },
        ],
      });

      expect(parsed.addons.first.consumptionJson.value, contains('"product_id":3'));
      expect(parsed.addons[1].consumptionJson.value, '[]');
    });

    test('toCatalog() decodes the lines onto the AddonOption', () {
      final catalog = ConfigMapper.toCatalog(
        null,
        const <CategoryRow>[],
        const <ProductRow>[],
        const <FloorRow>[],
        const <TableRow>[],
        const <TaxRow>[],
        [const AddonGroupRow(id: 5, name: 'Extras', selectionMode: 'multiple')],
        [
          const AddonRow(
            id: 100,
            addOnGroupId: 5,
            name: 'No salad',
            priceDeltaBaisas: 0,
            isDefault: false,
            consumptionJson:
                '[{"type":"ingredient","ingredient_id":11,"product_id":null,"direction":"remove","qty":0.05,"unit":"kg"}]',
          ),
        ],
      );

      final lines = catalog.addonGroups.single.options.single.consumption;
      expect(lines, hasLength(1));
      expect(lines.single.ingredientId, 11);
      expect(lines.single.isRemove, isTrue);
      expect(lines.single.qty, closeTo(0.05, 0.0001));
    });

    test('add lines gate on visible stock; removals and unknown ids never do', () {
      final controller = PosController();
      addTearDown(controller.dispose);

      controller.applyCatalog(
        categories: const ['Food'],
        products: const [
          Product(
            id: '3',
            name: 'Patty',
            category: 'Food',
            price: 0.5,
            stockMode: 'cooked',
            branchStockQty: 0, // the kitchen has not produced yet
          ),
        ],
        floors: const <DiningFloor>[],
        tables: const <DiningTableDefinition>[],
        // Salad (11): 0.02 kg left.
        ingredientBalances: const {11: 0.02},
      );

      // An 'add' product line on a sold-out cooked product greys out.
      const extraPatty = AddonOption(
        id: 1,
        label: 'Extra patty',
        priceDelta: 0.5,
        consumption: [AddonConsumptionLine(productId: 3, qty: 1)],
      );
      expect(controller.isAddonOptionUnavailable(extraPatty), isTrue);

      // An 'add' ingredient line below the branch balance greys out.
      const extraSalad = AddonOption(
        id: 2,
        label: 'Extra salad',
        priceDelta: 0.1,
        consumption: [AddonConsumptionLine(ingredientId: 11, qty: 0.05)],
      );
      expect(controller.isAddonOptionUnavailable(extraSalad), isTrue);

      // ...but a smaller add fits the remaining 0.02 kg.
      const lightSalad = AddonOption(
        id: 3,
        label: 'Light salad',
        priceDelta: 0.05,
        consumption: [AddonConsumptionLine(ingredientId: 11, qty: 0.01)],
      );
      expect(controller.isAddonOptionUnavailable(lightSalad), isFalse);

      // A REMOVAL never gates, even of a depleted ingredient.
      const noSalad = AddonOption(
        id: 4,
        label: 'No salad',
        priceDelta: 0,
        consumption: [
          AddonConsumptionLine(ingredientId: 11, isRemove: true, qty: 0.05),
        ],
      );
      expect(controller.isAddonOptionUnavailable(noSalad), isFalse);

      // A product id missing from the config (internal packaging never
      // ships to the device) is SKIPPED — the option stays sellable.
      const largeCup = AddonOption(
        id: 5,
        label: 'Large',
        priceDelta: 0.1,
        consumption: [AddonConsumptionLine(productId: 999, qty: 1)],
      );
      expect(controller.isAddonOptionUnavailable(largeCup), isFalse);
    });

    test('product add lines gate against the line QTY, not just zero stock', () {
      final controller = PosController();
      addTearDown(controller.dispose);

      controller.applyCatalog(
        categories: const ['Food'],
        products: const [
          Product(
            id: '3',
            name: 'Patty',
            category: 'Food',
            price: 0.5,
            stockMode: 'cooked',
            branchStockQty: 1, // one left on the shelf
          ),
        ],
        floors: const <DiningFloor>[],
        tables: const <DiningTableDefinition>[],
      );

      // Needs 2 with 1 on the shelf — visible shortfall, greyed.
      const doublePatty = AddonOption(
        id: 1,
        label: 'Double patty',
        priceDelta: 1.0,
        consumption: [AddonConsumptionLine(productId: 3, qty: 2)],
      );
      expect(controller.isAddonOptionUnavailable(doublePatty), isTrue);

      // Needs 1 with 1 on the shelf — fits.
      const singlePatty = AddonOption(
        id: 2,
        label: 'Extra patty',
        priceDelta: 0.5,
        consumption: [AddonConsumptionLine(productId: 3, qty: 1)],
      );
      expect(controller.isAddonOptionUnavailable(singlePatty), isFalse);
    });
  });
}
