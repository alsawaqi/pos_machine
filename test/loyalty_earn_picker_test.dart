import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/state/pos_controller.dart';

/// P-F3 — the earn-program choice: when the merchant runs several active
/// loyalty rules, the cashier/customer may pick which one(s) THIS order earns
/// under. No pick = the longstanding earn-under-all default; the choice
/// belongs to one customer and one order.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const points = LoyaltyRule(
    id: 1,
    name: 'Points',
    type: 'spend_based',
    config: {'points_per_omr': 10},
  );
  const stamps = LoyaltyRule(
    id: 2,
    name: 'Coffee Card',
    type: 'visit_based',
    config: {'stamps_required': 8},
  );
  const paused = LoyaltyRule(
    id: 3,
    name: 'Old Promo',
    type: 'spend_based',
    isActive: false,
  );

  PosController build() {
    final c = PosController();
    c.applyCatalog(
      categories: const ['X'],
      products: const [],
      floors: const <DiningFloor>[],
      tables: const <DiningTableDefinition>[],
      loyaltyRules: const [points, stamps, paused],
    );
    return c;
  }

  const ali = CustomerSearchResult(id: 7, name: 'Ali', phone: '96915872');
  const sara = CustomerSearchResult(id: 8, name: 'Sara', phone: '96900000');

  test('no explicit choice = every active rule (paused excluded)', () {
    final c = build();
    addTearDown(c.dispose);
    expect(c.selectedEarnRuleIds, isNull);
    expect(c.effectiveEarnRuleIds, [1, 2]);
  });

  test('a choice narrows the pay set and is clipped to active rules', () {
    final c = build();
    addTearDown(c.dispose);
    c.attachCustomer(ali);
    c.setSelectedEarnRules([2, 3]); // 3 is paused → clipped out
    expect(c.effectiveEarnRuleIds, [2]);

    // Choosing none = earn nothing (the customer declined).
    c.setSelectedEarnRules(const []);
    expect(c.effectiveEarnRuleIds, isEmpty);
  });

  test('the choice survives a same-customer re-attach but not a new customer',
      () {
    final c = build();
    addTearDown(c.dispose);
    c.attachCustomer(ali);
    c.setSelectedEarnRules([1]);

    c.attachCustomer(ali); // reopening details re-attaches
    expect(c.selectedEarnRuleIds, [1]);

    c.attachCustomer(sara); // a different customer → re-ask
    expect(c.selectedEarnRuleIds, isNull);
    expect(c.effectiveEarnRuleIds, [1, 2]);
  });

  test('typing a raw number (detach) clears the choice', () {
    final c = build();
    addTearDown(c.dispose);
    c.attachCustomer(ali);
    c.setSelectedEarnRules([1]);

    c.setCustomerReferenceNumber('99999999');
    expect(c.selectedCustomer, isNull);
    expect(c.selectedEarnRuleIds, isNull);
  });
}
