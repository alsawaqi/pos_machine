import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/state/pos_controller.dart';

/// P-F1 — delivery-provider orders carry NO tax at all (merchant policy: the
/// provider's listed price is final). Other order types tax normally. The
/// server never recomputes tax (it only checks the additive invariant), so
/// the device's zero is authoritative end-to-end.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const latte = Product(id: '1', name: 'Latte', category: 'Coffee', price: 2.0);

  PosController build() {
    final c = PosController();
    c.applyCatalog(
      categories: const ['Coffee'],
      products: const [latte],
      floors: const <DiningFloor>[],
      tables: const <DiningTableDefinition>[],
      taxes: const [
        CompanyTax(name: 'VAT', ratePercent: 5),
        CompanyTax(name: 'Municipality', ratePercent: 2.5),
      ],
    );
    return c;
  }

  test('delivery orders have zero tax; the total is the bare subtotal', () {
    final c = build();
    addTearDown(c.dispose);
    addTearDown(() => activeCompanyTaxes = const <CompanyTax>[]);
    c.addProduct(latte);

    // Quick order: taxed normally (5% + 2.5% of 2.000).
    expect(c.tax, closeTo(0.150, 1e-9));
    expect(c.taxLines, hasLength(2));
    expect(c.total, closeTo(2.150, 1e-9));

    // Delivery: tax-exempt.
    c.selectedOrderType = OrderType.delivery;
    expect(c.tax, 0);
    expect(c.taxLines, isEmpty);
    expect(c.total, closeTo(2.0, 1e-9));

    // And back: switching away restores taxation.
    c.selectedOrderType = OrderType.dineIn;
    expect(c.tax, closeTo(0.150, 1e-9));
  });

  test('held delivery drafts are tax-exempt too', () {
    addTearDown(() => activeCompanyTaxes = const <CompanyTax>[]);
    activeCompanyTaxes = const [CompanyTax(name: 'VAT', ratePercent: 5)];

    OrderSessionDraft draft(OrderType type) => OrderSessionDraft(
          orderReference: 'REF-1',
          orderType: type,
          selectedCategory: 'Coffee',
          customerReferenceNumber: '',
          diningFloorId: '',
          diningFloorLabel: '',
          diningTableId: '',
          diningTableName: '',
          items: [CartItem(product: latte, qty: 1)],
          discount: const DiscountConfiguration(),
          splitCount: 1,
        );

    expect(draft(OrderType.quickOrder).tax, closeTo(0.100, 1e-9));
    expect(draft(OrderType.delivery).tax, 0);
    expect(draft(OrderType.delivery).taxLines, isEmpty);
    expect(draft(OrderType.delivery).total, closeTo(2.0, 1e-9));
  });
}
