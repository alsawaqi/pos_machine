import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/order_workspace/current_order_workspace.dart';

void main() {
  test(
    'shared bill includes unsent line tax estimate without repricing saved lines',
    () {
      final previous = activeCompanyTaxes;
      addTearDown(() => activeCompanyTaxes = previous);
      activeCompanyTaxes = [const CompanyTax(name: 'VAT', ratePercent: 5)];
      final w = CurrentOrderWorkspace(
        onExit: () {},
        mainCart: true,
        tableLabel: 'Table 1',
      );
      addTearDown(w.dispose);
      final owner = Object();
      w.attach(owner, pick: (_) async {}, leave: () async {}, pay: () async {});
      w.publish(
        owner,
        order: {
          'uuid': 'bill',
          'temp_reference': 'T-001',
          'grand_total_baisas': 315,
          'subtotal_baisas': 300,
          'tax_total_baisas': 15,
          'items': [
            {'product_name': 'Coffee', 'qty': 1, 'line_total_baisas': 300},
          ],
        },
        stale: false,
        canAdd: true,
        canPay: false,
        cartControls: WorkspaceCartControls(
          draftRows: [
            {'product_name': 'Sweet', 'qty': 1, 'line_total_baisas': 300},
          ],
          pendingRows: [],
        ),
      );
      expect(w.cartBill!.total, 630);
      expect(w.cartBill!.tax, 30);
      expect(w.cartBill!.subtotal, 600);
      expect(w.bill!.total, 315);
      expect(w.bill!.items, hasLength(1));
      expect(w.cartBill!.json['preview_pending'], true);
      activeCompanyTaxes = [];
      expect(w.cartBill!.total, 615);
      expect(w.bill!.tax, 15);
    },
  );
}
