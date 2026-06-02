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
        [const CategoryRow(id: 1, name: 'Coffee', displayOrder: 0)],
        [
          const ProductRow(
            id: 10,
            name: 'Latte',
            categoryId: 1,
            basePriceBaisas: 1500,
            addonGroupIds: '5,6',
            deliveryPricesJson: '{}',
          ),
          const ProductRow(
            id: 11,
            name: 'Water',
            categoryId: 1,
            basePriceBaisas: 500,
            addonGroupIds: '',
            deliveryPricesJson: '{}',
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
          ),
          const AddonRow(
            id: 101,
            addOnGroupId: 6,
            name: 'Extra shot',
            priceDeltaBaisas: 300,
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
          ),
          const AddonRow(
            id: 101,
            addOnGroupId: 5,
            name: 'Retired',
            priceDeltaBaisas: 300,
            status: 'inactive',
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
}
