import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/order_workspace/current_order_workspace.dart';

void main() {
  test(
    'offline table placeholder uses the table label, never an internal UUID',
    () {
      final w = CurrentOrderWorkspace(
        onExit: () {},
        mainCart: true,
        tableLabel: 'Table 1',
      );
      addTearDown(w.dispose);
      expect(w.stale, true);
      expect(w.bill, isNull);
      expect(w.cartBill!.reference, 'Table 1');
      expect(w.cartBill!.cartDisplay(stale: true)['receiptNumber'], 'Table 1');
      expect(w.canPay, false);
      expect(w.cartBill!.items, isEmpty);
    },
  );
}
