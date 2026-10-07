import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';

/// LAUNCH-P4 — the device config's product and menu fields survive
/// parse -> Drift -> catalog: H5 inactive rows hidden, L1 display order,
/// M1 category branch list, M2 global add-on groups, H11 photo URL (no coffee
/// picture), C5 channels + per-provider listing, C6 sold out, C7 combo slots.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProductRow product(
    int id, {
    int? categoryId = 1,
    String? status = 'active',
    int? displayOrder,
    String addonGroupIds = '',
    String? imageUrl,
  }) => ProductRow(
    id: id,
    name: 'P$id',
    categoryId: categoryId,
    basePriceBaisas: 1000,
    status: status,
    addonGroupIds: addonGroupIds,
    deliveryPricesJson: '{}',
    recipeJson: '[]',
    displayOrder: displayOrder,
    imageUrl: imageUrl,
  );

  CatalogSnapshot catalog({
    List<CategoryRow> cats = const [],
    List<ProductRow> prods = const [],
    List<AddonGroupRow> groups = const [],
    int branchId = 3,
  }) => ConfigMapper.toCatalog(
    BranchRow(id: branchId, name: 'Main'),
    cats,
    prods,
    const [],
    const [],
    const [],
    groups,
  );

  test('H5 — inactive products and categories are hidden', () {
    final c = catalog(
      cats: const [
        CategoryRow(
          id: 1,
          name: 'Coffee',
          displayOrder: 0,
          addonGroupIdsJson: '[]',
          status: 'active',
        ),
        CategoryRow(
          id: 2,
          name: 'Old',
          displayOrder: 1,
          addonGroupIdsJson: '[]',
          status: 'inactive',
        ),
      ],
      prods: [
        product(10),
        product(11, status: 'inactive'),
        product(12, categoryId: 2),
      ],
    );
    expect(c.categories, ['Coffee']);
    expect(c.products.map((p) => p.id), ['10']);
  });

  test('M1 — a category limited to other branches is hidden here', () {
    final c = catalog(
      cats: const [
        CategoryRow(
          id: 1,
          name: 'Coffee',
          displayOrder: 0,
          addonGroupIdsJson: '[]',
          branchIdsJson: '[3, 4]',
        ),
        CategoryRow(
          id: 2,
          name: 'Brunch',
          displayOrder: 1,
          addonGroupIdsJson: '[]',
          branchIdsJson: '[9]',
        ),
        CategoryRow(
          id: 3,
          name: 'Tea',
          displayOrder: 2,
          addonGroupIdsJson: '[]',
        ),
      ],
      prods: [
        product(10),
        product(11, categoryId: 2),
        product(12, categoryId: 3),
      ],
    );
    expect(c.categories, ['Coffee', 'Tea']);
    expect(c.products.map((p) => p.id), ['10', '12']);
  });

  test('L1 — products follow the merchant display order', () {
    final c = catalog(
      prods: [
        product(10, displayOrder: 3),
        product(11, displayOrder: 1),
        product(12, displayOrder: 2),
      ],
    );
    expect(c.products.map((p) => p.id), ['11', '12', '10']);
  });

  test('M2 — global add-on groups join every product', () {
    final c = catalog(
      prods: [
        product(10, addonGroupIds: '5'),
        product(11),
      ],
      groups: const [
        AddonGroupRow(id: 5, name: 'Size'),
        AddonGroupRow(id: 6, name: 'Cutlery', isGlobal: true),
      ],
    );
    expect(c.products.first.addonGroupIds, [5, 6]);
    expect(c.products.last.addonGroupIds, [6]);
  });

  test('H11 — the photo URL is kept and no coffee picture is assigned', () {
    final c = catalog(
      prods: [
        product(10, imageUrl: 'https://cdn.example/latte.jpg'),
        product(11),
      ],
    );
    expect(c.products.first.imageUrl, 'https://cdn.example/latte.jpg');
    expect(c.products.first.imageAsset, isNull);
    expect(c.products.last.imageUrl, isNull);
    expect(c.products.last.imageAsset, isNull);
    expect(c.products.last.initials(false), 'P');
  });

  test('channels, sold out and combo lines parse from the config', () {
    final parsed = ConfigMapper.parse(<String, dynamic>{
      'products': [
        {
          'id': 20,
          'name': 'Burger meal',
          'base_price_baisas': 3500,
          'product_type': 'combo',
          'sold_in_store': true,
          'sold_on_delivery': false,
          'sold_out': true,
          'description_ar': 'وجبة برجر',
          'display_order': 4,
          'delivery_prices': [
            {'provider_id': 1, 'price_baisas': null, 'listed': false},
            {'provider_id': 2, 'price_baisas': 3900, 'listed': true},
          ],
          // LAUNCH combo add-on — §7.1 lines (the slot model is gone).
          'combo': {
            'lines': [
              {
                'id': 7,
                'kind': 'choice',
                'sort_order': 2,
                'product_id': null,
                'quantity': null,
                'upgrades': [],
                'name': 'Drink',
                'name_ar': 'مشروب',
                'category_id': 3,
                'pick_count': 2,
                'items': [
                  {'product_id': 31, 'extra_price_baisas': 0},
                  {'product_id': 32, 'extra_price_baisas': 300},
                ],
              },
              {
                'id': 6,
                'kind': 'fixed',
                'sort_order': 1,
                'product_id': 30,
                'quantity': 2,
                'upgrades': [
                  {
                    'product_id': 33,
                    'upgrade_price_baisas': 800,
                    'sort_order': 0,
                  },
                ],
                'name': null,
                'name_ar': null,
                'category_id': null,
                'pick_count': null,
                'items': [],
              },
            ],
          },
        },
      ],
    });
    final row = parsed.products.single;
    final p = ConfigMapper.toCatalog(
      null,
      const [],
      [
        ProductRow(
          id: 20,
          name: 'Burger meal',
          basePriceBaisas: 3500,
          addonGroupIds: '',
          deliveryPricesJson: row.deliveryPricesJson.value,
          recipeJson: '[]',
          productType: row.productType.value,
          soldInStore: row.soldInStore.value,
          soldOnDelivery: row.soldOnDelivery.value,
          soldOut: row.soldOut.value,
          descriptionAr: row.descriptionAr.value,
          deliveryUnlistedJson: row.deliveryUnlistedJson.value,
          comboJson: row.comboJson.value,
          displayOrder: row.displayOrder.value,
        ),
      ],
      const [],
      const [],
      const [],
    ).products.single;
    expect(p.isCombo, isTrue);
    expect(p.soldInStore, isTrue);
    expect(p.soldOnDelivery, isFalse);
    expect(p.soldOut, isTrue);
    expect(p.descriptionAr, 'وجبة برجر');
    expect(p.displayOrder, 4);
    expect(p.deliveryUnlistedProviderIds, {1});
    expect(p.deliveryPriceByProvider, {2: 3.9});
    expect(p.isListedOn(2), isFalse); // not sold on delivery at all
    expect(p.comboLines.map((l) => l.id), [6, 7]); // by sort order
    final burger = p.comboLines.first;
    expect(burger.isFixed, isTrue);
    expect(burger.quantity, 2);
    expect(burger.upgrades.single.upgradePriceBaisas, 800);
    final drink = p.comboLines.last;
    expect(drink.nameAr, 'مشروب');
    expect(drink.pickCount, 2);
    expect(drink.items.map((i) => i.productId), [31, 32]);
    expect(drink.items.last.extraPriceBaisas, 300);
  });

  test('isListedOn honours the per-provider listed flag', () {
    const p = Product(
      id: '1',
      name: 'Latte',
      category: 'Coffee',
      price: 1,
      deliveryUnlistedProviderIds: {4},
    );
    expect(p.isListedOn(4), isFalse);
    expect(p.isListedOn(5), isTrue);
  });
}
