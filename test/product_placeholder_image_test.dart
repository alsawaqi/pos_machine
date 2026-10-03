import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/services/config_mapper.dart';

ProductRow _product(int id, {String? imageUrl}) => ProductRow(
  id: id,
  name: 'Product $id',
  categoryId: 1,
  basePriceBaisas: 1000,
  imageUrl: imageUrl,
  addonGroupIds: '',
  deliveryPricesJson: '{}',
  recipeJson: '[]',
);

/// LAUNCH-P4 H11 — catalog products never get a stock coffee picture: they
/// show the merchant's photo (cached) or an initials placeholder. (This
/// replaces the earlier "stable bundled photo per product" rule.)
void main() {
  test('catalog products carry the photo URL and never a coffee picture', () {
    final products = ConfigMapper.toCatalog(
      null,
      [
        const CategoryRow(
          id: 1,
          name: 'Coffee',
          displayOrder: 0,
          addonGroupIdsJson: '[]',
        ),
      ],
      [
        _product(1, imageUrl: 'https://order.mithqal.net/storage/products/1.jpg'),
        _product(2, imageUrl: '   '),
        _product(3),
      ],
      const <FloorRow>[],
      const <TableRow>[],
      const <TaxRow>[],
    ).products;

    expect(products.map((p) => p.imageAsset), everyElement(isNull));
    expect(
      products.first.imageUrl,
      'https://order.mithqal.net/storage/products/1.jpg',
    );
    expect(products[1].imageUrl, isNull); // blank = no photo
    expect(products[2].imageUrl, isNull);
    expect(products[2].initials(false), 'P3');
  });
}
