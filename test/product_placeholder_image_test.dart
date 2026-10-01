import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/services/config_mapper.dart';

ProductRow _product(int id) => ProductRow(
  id: id,
  name: 'Product $id',
  categoryId: 1,
  basePriceBaisas: 1000,
  addonGroupIds: '',
  deliveryPricesJson: '{}',
  recipeJson: '[]',
);

void main() {
  test('catalog products show a stable bundled photo per product', () {
    List<String?> images() => ConfigMapper.toCatalog(
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
        for (final id in [1, 2, 3, 4, 5, 6]) _product(id),
      ],
      const <FloorRow>[],
      const <TableRow>[],
      const <TaxRow>[],
    ).products.map((p) => p.imageAsset).toList();

    final first = images();
    expect(first, everyElement(isNotNull));
    expect(first, images()); // same product -> same photo, every time
    expect(first.toSet().length, greaterThan(1)); // not all identical
    expect(productPlaceholderAsset(6), productPlaceholderAsset(1));
  });

  test('every placeholder photo is a bundled asset', () {
    for (final asset in kProductPlaceholderAssets) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
  });
}
