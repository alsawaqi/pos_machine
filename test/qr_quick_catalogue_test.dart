import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/screens/qr_quick_orders_screen.dart';

CatalogSnapshot catalogue(
  List<Product> products, {
  List<AddonGroup> groups = const [],
  Map<int, List<int>> bindings = const {},
}) => CatalogSnapshot(
  categories: [],
  products: products,
  floors: [],
  tables: [],
  taxes: [],
  addonGroups: groups,
  categoryAddonGroupIds: bindings,
);
void main() {
  test(
    'QR editor includes category and product modifiers once with exact required constraints',
    () {
      final result = machineQuickCatalogue(
        catalogue(
          [
            const Product(
              id: '7',
              name: 'Water',
              category: 'Drinks',
              categoryId: 2,
              price: 0.2,
              addonGroupIds: [3],
            ),
          ],
          groups: [
            const AddonGroup(
              id: 3,
              name: 'Size',
              multiSelect: false,
              minSelections: 1,
              options: [
                AddonOption(
                  id: 9,
                  label: 'Small',
                  priceDelta: 0.0,
                  isDefault: true,
                ),
              ],
            ),
            const AddonGroup(
              id: 4,
              name: 'Extras',
              multiSelect: true,
              minSelections: 2,
              maxSelections: 3,
              options: [],
            ),
          ],
          bindings: {
            2: [3, 4],
          },
        ),
      );
      expect(result.single.groups.map((g) => g.name).toList(), [
        'Size',
        'Extras',
      ]);
      expect(result.single.groups.first.choices.single.selected, true);
      expect(result.single.groups.last.min, 2);
      expect(result.single.groups.last.max, 3);
    },
  );
  test('missing modifier group disables selection; stock never does', () {
    final result = machineQuickCatalogue(
      catalogue([
        const Product(
          id: '7',
          name: 'Missing group',
          category: '',
          price: 1,
          addonGroupIds: [99],
        ),
        const Product(
          id: '8',
          name: 'Empty shelf',
          category: '',
          price: 1,
          stockMode: 'unit',
          branchStockQty: 0,
        ),
        const Product(
          id: '9',
          name: 'Not cooked',
          category: '',
          price: 1,
          stockMode: 'cooked',
        ),
        const Product(id: '10', name: 'Available', category: '', price: 1),
      ]),
    );
    // LAUNCH-P2 "sell, but warn": an empty or never-produced shelf stays
    // selectable.
    expect(result.map((p) => p.available).toList(), [false, true, true, true]);
  });
  test(
    'new navigation separates local Held Orders; QR host never imports a cart',
    () {
      final home = File('lib/screens/staff_pos_screen.dart').readAsStringSync();
      final route = File(
        'lib/screens/qr_quick_orders_screen.dart',
      ).readAsStringSync();
      expect(home, contains("_NavItemData('QR Quick Orders'"));
      expect(home, isNot(contains('QrPendingStorageLayout(')));
      expect(home, contains('records: controller.heldOrders'));
      expect(
        route,
        contains('QrPendingSheet(order: QrPendingOrder.fromJson(order.json))'),
      );
      for (final unsafe in [
        'PosController',
        'resumeHeldOrder',
        'CartItem.fromMap',
        'order.create',
        'order.pay',
      ]) {
        expect(route, isNot(contains(unsafe)));
      }
    },
  );
}
