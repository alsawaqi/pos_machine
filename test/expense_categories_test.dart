import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/services/config_mapper.dart';

/// v2 #7 — custom expense categories survive parse → Drift → catalog, and
/// reach the snapshot as {key, name} entries in sort order (the expense screen
/// shows `name`, submits `key`).
void main() {
  group('Expense categories', () {
    test('parse() captures the expense_categories config section', () {
      final parsed = ConfigMapper.parse(<String, dynamic>{
        'expense_categories': [
          {'id': 1, 'key': 'utilities', 'name': 'Utilities', 'name_ar': 'المرافق', 'sort_order': 1},
          {'id': 2, 'key': 'marketing', 'name': 'Marketing', 'sort_order': 2},
        ],
      });

      expect(parsed.expenseCategories.length, 2);
      expect(parsed.expenseCategories.first.id.value, 1);
      expect(parsed.expenseCategories.first.key.value, 'utilities');
      expect(parsed.expenseCategories.first.name.value, 'Utilities');
      expect(parsed.expenseCategories.first.nameAr.value, 'المرافق');
    });

    test('parseDelta() captures deleted expense_categories ids', () {
      final delta = ConfigMapper.parseDelta(<String, dynamic>{
        'deleted': {
          'expense_categories': [3, 4],
        },
      });

      expect(delta.deleted.expenseCategories, [3, 4]);
    });

    test('toCatalog returns categories as {key,name} in sort order', () {
      final catalog = ConfigMapper.toCatalog(
        null,
        const <CategoryRow>[],
        const <ProductRow>[],
        const <FloorRow>[],
        const <TableRow>[],
        const <TaxRow>[],
        const <AddonGroupRow>[],
        const <AddonRow>[],
        const <DeliveryProviderRow>[],
        [
          const ExpenseCategoryRow(id: 2, key: 'marketing', name: 'Marketing', sortOrder: 2),
          const ExpenseCategoryRow(id: 1, key: 'utilities', name: 'Utilities', sortOrder: 1),
        ],
      );

      expect(catalog.expenseCategories.map((c) => c.key).toList(), ['utilities', 'marketing']);
      expect(catalog.expenseCategories.first.name, 'Utilities');
    });
  });
}
