import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/models/pos_models.dart';

void main() {
  group('LoyaltyRule config parsing', () {
    test('spend_based getters (values may be ints or strings)', () {
      const rule = LoyaltyRule(
        id: 2,
        name: 'Points',
        type: 'spend_based',
        config: {
          'points_per_omr': 10,
          'redemption_points': 100,
          'min_redemption_points': 100,
          'redemption_value': '5.000',
        },
      );
      expect(rule.isSpendBased, isTrue);
      expect(rule.isVisitBased, isFalse);
      expect(rule.pointsPerOmr, 10);
      expect(rule.redemptionPoints, 100);
      expect(rule.minRedemptionPoints, 100);
      expect(rule.redemptionValue, 5.0);
    });

    test('visit_based getters', () {
      const rule = LoyaltyRule(
        id: 1,
        name: 'Stamp card',
        type: 'visit_based',
        config: {'min_order_value': '2.000', 'stamps_required': 5},
      );
      expect(rule.isVisitBased, isTrue);
      expect(rule.stampsRequired, 5);
      expect(rule.minOrderValue, 2.0);
    });

    test('visit_based reward getters (percent_off + free_product)', () {
      const percent = LoyaltyRule(
        id: 1,
        name: 'Percent card',
        type: 'visit_based',
        config: {'stamps_required': 10, 'reward_type': 'percent_off', 'reward_value': '50'},
      );
      expect(percent.rewardType, 'percent_off');
      expect(percent.rewardValue, 50.0);
      expect(percent.rewardProductId, isNull);

      const freeProduct = LoyaltyRule(
        id: 2,
        name: 'Free coffee',
        type: 'visit_based',
        config: {'stamps_required': 8, 'reward_type': 'free_product', 'reward_product_id': 42},
      );
      expect(freeProduct.rewardType, 'free_product');
      expect(freeProduct.rewardProductId, 42);
    });

    test('missing config keys default to zero', () {
      const rule = LoyaltyRule(id: 3, name: 'Empty', type: 'spend_based');
      expect(rule.pointsPerOmr, 0);
      expect(rule.redemptionValue, 0);
      expect(rule.stampsRequired, 0);
    });
  });
}
