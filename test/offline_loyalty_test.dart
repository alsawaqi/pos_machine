import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';

/// Gap #3 — offline loyalty: the config bundle now caches per-customer balances
/// (loyaltyJson on CachedCustomers). This verifies the decode into CustomerRef
/// and the conversion to the CustomerSearchResult shape the redeem flow uses.
void main() {
  group('offline loyalty cache', () {
    test('toCatalog decodes cached loyalty JSON into CustomerRef', () {
      const row = CustomerRow(
        id: 1,
        name: 'Ali',
        phone: '+96890000000',
        walletBalanceBaisas: 3000,
        loyaltyJson: '[{"rule_id":1,"points":50,"stamps":3}]',
      );

      final catalog = ConfigMapper.toCatalog(
        null,
        const [], // categories
        const [], // products
        const [], // floors
        const [], // tables
        const [], // taxes
        const [], // addon groups
        const [], // addons
        const [], // delivery providers
        const [], // expense categories
        const [], // branch stock
        const [], // discounts
        const [], // loyalty rules
        [row], // customers
      );

      expect(catalog.customers.length, 1);
      final c = catalog.customers.first;
      expect(c.loyalty.length, 1);
      expect(c.loyalty.first.ruleId, 1);
      expect(c.loyalty.first.points, 50);
      expect(c.loyalty.first.stamps, 3);
    });

    test('an empty loyalty cache decodes to no balances', () {
      const row = CustomerRow(
        id: 2,
        name: 'Sara',
        phone: null,
        walletBalanceBaisas: 0,
        loyaltyJson: '[]',
      );
      final catalog = ConfigMapper.toCatalog(
        null, const [], const [], const [], const [], const [],
        const [], const [], const [], const [], const [], const [], const [],
        [row],
      );
      expect(catalog.customers.first.loyalty, isEmpty);
    });

    test('CustomerRef.toSearchResult carries loyalty for the redeem path', () {
      const ref = CustomerRef(
        id: 1,
        name: 'Ali',
        walletBalance: 3.0,
        loyalty: [LoyaltyBalance(ruleId: 7, points: 120, stamps: 0)],
      );

      final r = ref.toSearchResult();
      expect(r.id, 1);
      expect(r.name, 'Ali');
      expect(r.pointsForRule(7), 120);
      expect(r.pointsForRule(8), 0); // unknown rule → 0
    });
  });
}
