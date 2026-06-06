import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/services/config_mapper.dart';

/// Covers delivery: providers + per-product overrides survive parse → Drift →
/// catalog, and Product.deliveryPriceFor follows override → delivery_price →
/// base, mirroring the merchant's resolution chain.
void main() {
  group('Delivery pricing', () {
    test('parse() captures delivery_price + per-provider overrides', () {
      final parsed = ConfigMapper.parse(<String, dynamic>{
        'products': [
          {
            'id': 10,
            'name': 'Latte',
            'base_price_baisas': 1500,
            'delivery_price_baisas': 1800,
            'delivery_prices': [
              {'provider_id': 1, 'price_baisas': 2000},
              {'provider_id': 2, 'price_baisas': 1900},
            ],
          },
        ],
        'delivery_providers': [
          {'id': 2, 'name': 'Otlob', 'sort_order': 2},
          {'id': 1, 'name': 'Talabat', 'color': '#FF5A00', 'sort_order': 1},
        ],
      });

      expect(parsed.products.first.deliveryPriceBaisas.value, 1800);
      expect(parsed.products.first.deliveryPricesJson.value, contains('"1":2000'));
      expect(parsed.products.first.deliveryPricesJson.value, contains('"2":1900'));
      expect(parsed.deliveryProviders.length, 2);
    });

    test('toCatalog sorts providers + resolves delivery prices per chain', () {
      final catalog = ConfigMapper.toCatalog(
        null,
        const <CategoryRow>[],
        [
          const ProductRow(
            id: 10,
            name: 'Latte',
            basePriceBaisas: 1500,
            deliveryPriceBaisas: 1800,
            addonGroupIds: '',
            deliveryPricesJson: '{"1":2000}',
            recipeJson: '[]',
          ),
          const ProductRow(
            id: 11,
            name: 'Tea',
            basePriceBaisas: 800,
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
        [
          const DeliveryProviderRow(id: 2, name: 'Otlob', sortOrder: 2),
          const DeliveryProviderRow(
              id: 1, name: 'Talabat', color: '#FF5A00', sortOrder: 1),
        ],
      );

      // Providers come back in sort order.
      expect(catalog.deliveryProviders.map((p) => p.id).toList(), [1, 2]);
      expect(catalog.deliveryProviders.first.name, 'Talabat');
      expect(catalog.deliveryProviders.first.color, '#FF5A00');

      final latte = catalog.products.firstWhere((p) => p.id == '10');
      // provider 1 has an override (2.000); provider 2 has none → delivery 1.800;
      // base stays 1.500.
      expect(latte.deliveryPriceFor(1), closeTo(2.0, 1e-9));
      expect(latte.deliveryPriceFor(2), closeTo(1.8, 1e-9));
      expect(latte.price, closeTo(1.5, 1e-9));

      // Tea has neither an override nor a delivery price → base for any provider.
      final tea = catalog.products.firstWhere((p) => p.id == '11');
      expect(tea.deliveryPriceFor(1), closeTo(0.8, 1e-9));
      expect(tea.deliveryPriceFor(99), closeTo(0.8, 1e-9));
    });
  });
}
