import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/services/config_mapper.dart';

/// Phase 7 — the device delta parser. Verifies the /device/config/delta envelope
/// (changed rows reuse parse(); data.deleted{} → trashed-id lists; branch
/// object-or-null → hasBranch; meta.generated_at threaded in as the cursor).
void main() {
  group('config delta', () {
    test('maps changed rows, deleted ids, and the cursor', () {
      final data = <String, dynamic>{
        'branch': null, // unchanged this delta
        'categories': [
          {'id': 3, 'name': 'Drinks', 'display_order': 1, 'status': 'active'},
        ],
        'products': [
          {
            'id': 7,
            'name': 'Latte',
            'category_id': 3,
            'base_price_baisas': 1500,
            'status': 'active',
          },
        ],
        'deleted': {
          'products': [8, 9],
          'categories': [4],
          'customers': [11],
        },
      };

      final delta = ConfigMapper.parseDelta(data, cursor: 'CURSOR-123');

      // Branch absent → don't touch branchCache.
      expect(delta.hasBranch, isFalse);

      // Changed rows reuse parse() → real companions.
      expect(delta.changed.categories.length, 1);
      expect(delta.changed.categories.first.id.value, 3);
      expect(delta.changed.products.length, 1);
      expect(delta.changed.products.first.id.value, 7);
      expect(delta.changed.products.first.name.value, 'Latte');
      expect(delta.changed.products.first.basePriceBaisas.value, 1500);

      // Cursor (envelope meta.generated_at) threaded into SyncMeta.
      expect(delta.changed.meta.configSchemaVersion.value, 'CURSOR-123');

      // Deletions.
      expect(delta.deleted.products, [8, 9]);
      expect(delta.deleted.categories, [4]);
      expect(delta.deleted.customers, [11]);
      // Entities not present in the deleted map default to empty.
      expect(delta.deleted.ingredients, isEmpty);
      expect(delta.deleted.deliveryProviders, isEmpty);
      expect(delta.deleted.addons, isEmpty);
    });

    test('sets hasBranch true when the branch row is present', () {
      final data = <String, dynamic>{
        'branch': {'id': 6, 'name': 'Main', 'company_id': 9},
      };

      final delta = ConfigMapper.parseDelta(data, cursor: 'C');

      expect(delta.hasBranch, isTrue);
      expect(delta.changed.branch.id.value, 6);
    });

    test('with no deleted map yields all-empty deletions', () {
      final delta = ConfigMapper.parseDelta(
        <String, dynamic>{'products': <dynamic>[]},
        cursor: 'C',
      );

      expect(delta.deleted.products, isEmpty);
      expect(delta.deleted.categories, isEmpty);
      expect(delta.hasBranch, isFalse);
      expect(delta.changed.meta.configSchemaVersion.value, 'C');
    });
  });
}
