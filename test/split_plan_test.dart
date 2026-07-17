import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/state/pos_controller.dart';

/// Custom split plan (Phase 3): each guest may pay an ARBITRARY share instead
/// of an equal one, ported from the handheld's split-plan sheet. The plan
/// drives [PosController.activePaymentBaseTotal] leg by leg; the LAST share is
/// always the exact remainder so the recorded legs close to the order total.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PosController seeded() {
    final c = PosController();
    c.applyCatalog(
      categories: const ['Coffee'],
      products: const [
        Product(id: '10', name: 'Latte', nameAr: '', category: 'Coffee', price: 1.5),
      ],
      floors: const [],
      tables: const [],
      discounts: const [],
      offers: const [],
      branchId: 6,
    );
    c.addProduct(c.allProducts.first);
    return c;
  }

  Future<void> settleCashLeg(PosController c) async {
    c.selectPaymentMethod('Cash');
    await c.payAndPrint();
  }

  group('setSplitPlan — custom per-guest amounts', () {
    test('applies the plan: guest 1 pays their planned share', () {
      final c = seeded(); // total 1.500
      expect(c.setSplitPlan([1.0, 0.5]), isTrue);
      expect(c.splitCount, 2);
      expect(c.splitPlanAmounts, [1.0, 0.5]);
      expect(c.activePaymentBaseTotal, 1.0);
    });

    test('legs settle at the planned amounts in order', () async {
      final c = seeded(); // total 1.500
      c.setSplitPlan([1.0, 0.3, 0.2]);

      expect(c.activePaymentBaseTotal, 1.0);
      await settleCashLeg(c);
      expect(c.paidSplitCount, 1);
      expect(c.splitPayments.last.baseAmount, 1.0);

      expect(c.activePaymentBaseTotal, 0.3);
      await settleCashLeg(c);
      expect(c.paidSplitCount, 2);
      expect(c.splitPayments.last.baseAmount, 0.3);

      // Final leg: the remainder rule and the plan agree.
      expect(c.activePaymentBaseTotal, 0.2);
    });

    test('the last share is rewritten to the exact remainder', () {
      final c = seeded(); // total 1.500
      c.setSplitPlan([0.4, 0.4, 0.999]);
      expect(c.splitPlanAmounts, [0.4, 0.4, 0.7]);
    });

    test('rejected when the non-final shares already cover the total', () {
      final c = seeded(); // total 1.500
      // 1.0 + 0.6 leaves nothing for guest 3
      expect(c.setSplitPlan([1.0, 0.6, 0.2]), isFalse);
      expect(c.splitCount, 1);
      expect(c.splitPlanAmounts, isNull);
    });

    test('rejected when a non-final share is zero or negative', () {
      final c = seeded();
      expect(c.setSplitPlan([0.0, 1.5]), isFalse);
      expect(c.splitPlanAmounts, isNull);
      expect(c.setSplitPlan([-0.5, 2.0]), isFalse);
      expect(c.splitPlanAmounts, isNull);
    });

    test('rejected when a share rounds below one baisa (0.0004 -> 0.000)', () {
      final c = seeded(); // total 1.500
      expect(c.setSplitPlan([0.0004, 1.4996]), isFalse);
      expect(c.splitPlanAmounts, isNull);
      // ...and when the REMAINDER would round below a baisa.
      expect(c.setSplitPlan([1.4996, 0.0004]), isFalse);
      expect(c.splitPlanAmounts, isNull);
    });

    test('setSplitCount drops the plan (back to equal shares)', () {
      final c = seeded(); // total 1.500
      c.setSplitPlan([1.0, 0.5]);
      c.setSplitCount(3);
      expect(c.splitPlanAmounts, isNull);
      expect(c.activePaymentBaseTotal, 0.5); // 1.5 / 3
    });

    test('clearSplit drops the plan', () {
      final c = seeded();
      c.setSplitPlan([1.0, 0.5]);
      c.clearSplit();
      expect(c.splitCount, 1);
      expect(c.splitPlanAmounts, isNull);
    });

    test('a cart change before the first leg falls back to equal shares', () {
      final c = seeded(); // total 1.500
      c.setSplitPlan([1.0, 0.5]);
      c.addProduct(c.allProducts.first); // total now 3.000 — plan is stale
      expect(c.activePaymentBaseTotal, 1.5); // 3.0 / 2, NOT the stale 1.0
    });

    test('a swapped cart with a COINCIDING total still drops the plan', () {
      final c = seeded(); // one latte, total 1.500
      c.addProduct(c.allProducts.first); // total 3.000
      expect(c.setSplitPlan([2.0, 1.0]), isTrue);
      // Swap the cart: remove a latte, add a latte back. The total returns to
      // 3.000 — but the nonce moved, so the old amounts must not resurrect.
      c.decreaseCartItem(c.cart.first);
      c.addProduct(c.allProducts.first);
      expect(c.total, 3.0);
      expect(c.activePaymentBaseTotal, 1.5); // equal fallback, NOT 2.0
    });

    test('blocked once a leg has been recorded', () async {
      final c = seeded(); // total 1.500
      c.setSplitPlan([1.0, 0.5]);
      await settleCashLeg(c);
      // must not re-plan mid-collection
      expect(c.setSplitPlan([0.7, 0.8]), isFalse);
      expect(c.splitPlanAmounts, [1.0, 0.5]);
      expect(c.activePaymentBaseTotal, 0.5); // remainder of the original plan
    });

    test('round-up still offered only on a CARD leg of a custom split', () {
      final c = seeded(); // total 1.500
      c.setSplitPlan([0.9, 0.6]); // guest 1's 0.9 rounds up to 1.0
      c.selectPaymentMethod('Cash');
      expect(c.canOfferCharityRoundUp, isFalse);
      c.selectPaymentMethod('Credit Card');
      expect(c.canOfferCharityRoundUp, isTrue);
    });

    test('no round-up offer on a whole-OMR custom leg (nothing to round)', () {
      final c = seeded(); // total 1.500
      c.setSplitPlan([1.0, 0.5]); // guest 1 pays exactly 1.000
      c.selectPaymentMethod('Credit Card');
      expect(c.canOfferCharityRoundUp, isFalse);
    });
  });
}
