import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/state/pos_controller.dart';

/// P-F4 — order-scope auto_apply discounts + the custom-discount reason.
/// An order-scope rule flagged auto_apply self-applies to every qualifying
/// order (best rule wins, manager-approval rules never auto-apply, a cashier
/// clear suppresses re-application for that order); the reason on a manual
/// configuration rides the snapshot to the order.create discounts[] entry.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const latte = Product(id: '10', name: 'Latte', category: 'Coffee', price: 10.0);

  MerchantDiscount rule({
    int id = 1,
    String name = 'Happy Hour',
    bool autoApply = true,
    bool requiresManagerApproval = false,
    double? percent = 10,
    String amountType = 'percent',
    double? fixedAmount,
  }) =>
      MerchantDiscount(
        id: id,
        name: name,
        scope: 'order',
        amountType: amountType,
        percent: percent,
        fixedAmount: fixedAmount,
        autoApply: autoApply,
        requiresManagerApproval: requiresManagerApproval,
      );

  PosController build(List<MerchantDiscount> discounts) {
    final c = PosController();
    c.applyCatalog(
      categories: const ['Coffee'],
      products: const [latte],
      floors: const <DiningFloor>[],
      tables: const <DiningTableDefinition>[],
      discounts: discounts,
      branchId: 4,
    );
    return c;
  }

  test('the best qualifying auto rule self-applies when items land', () {
    final c = build([
      rule(id: 1, name: 'Small Promo', percent: 5),
      rule(id: 2, name: 'Big Promo', percent: 15),
      rule(id: 3, name: 'Manual Rule', autoApply: false, percent: 50),
      rule(id: 4, name: 'Needs Manager', requiresManagerApproval: true, percent: 80),
    ]);
    addTearDown(c.dispose);

    c.addProduct(latte);

    expect(c.discount.isActive, isTrue);
    expect(c.discount.discountId, 2); // best auto rule, not manual/manager ones
    expect(c.discount.label, 'Big Promo');
    expect(c.discountAmount, closeTo(1.5, 1e-9)); // 15% of 10.000
  });

  test('no auto rules → nothing applies', () {
    final c = build([rule(autoApply: false)]);
    addTearDown(c.dispose);
    c.addProduct(latte);
    expect(c.discount.isActive, isFalse);
  });

  test('a cashier clear suppresses re-application for the order; the next '
      'order auto-applies again', () async {
    final c = build([rule()]);
    addTearDown(c.dispose);

    c.addProduct(latte);
    expect(c.discount.isActive, isTrue);

    c.clearDiscount();
    expect(c.discount.isActive, isFalse);

    // More items / explicit re-check: stays cleared.
    c.addProduct(latte);
    c.maybeAutoApplyOrderDiscount();
    expect(c.discount.isActive, isFalse);
  });

  test('an existing manual discount is never overwritten', () {
    final c = build([rule()]);
    addTearDown(c.dispose);
    c.applyDiscount(const DiscountConfiguration(
      kind: DiscountKind.fixedAmount,
      value: 2,
      label: 'Manual',
      reason: 'VIP guest',
    ));
    c.addProduct(latte);
    expect(c.discount.label, 'Manual');
    expect(c.discount.reason, 'VIP guest');
  });

  test('the reason rides the snapshot map round-trip', () {
    const config = DiscountConfiguration(
      kind: DiscountKind.percentage,
      value: 7.5,
      label: '7.5% Discount',
      reason: 'Spilled drink apology',
    );
    final restored = DiscountConfiguration.fromMap(config.toMap());
    expect(restored.reason, 'Spilled drink apology');
    expect(restored.value, 7.5);
  });

  test('parse() + toCatalog carry auto_apply', () {
    final parsed = ConfigMapper.parse(<String, dynamic>{
      'discounts': [
        {
          'id': 9,
          'name': 'Auto Promo',
          'scope': 'order',
          'amount_type': 'percent',
          'percent': 10,
          'auto_apply': true,
          'status': 'active',
        },
      ],
    });
    expect(parsed.discounts.single.autoApply.value, isTrue);

    final catalog = ConfigMapper.toCatalog(
      null,
      const [],
      const [],
      const [],
      const [],
      const [],
      const [],
      const [],
      const [],
      const [],
      const [],
      [
        const DiscountRow(
          id: 9,
          name: 'Auto Promo',
          scope: 'order',
          amountType: 'percent',
          percent: 10,
          stackable: false,
          requiresManagerApproval: false,
          autoApply: true,
          targetsJson: '[]',
        ),
      ],
    );
    expect(catalog.discounts.single.autoApply, isTrue);
  });
}
