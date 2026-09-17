import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/order_workspace/current_order_workspace.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';

void main() {
  test(
    'QR review and current/payment cart exclude removed rows but retain free items',
    () {
      final value = <String, dynamic>{
        'uuid': 'edited-transferred-order',
        'source': 'qr_web',
        'order_type': 'quick',
        'table_id': null,
        'grand_total_baisas': 3990,
        'subtotal_baisas': 3800,
        'tax_total_baisas': 190,
        'items': [
          for (final row in [
            ('Sweety', 1, 300, 'open'),
            ('Removed coffee', 0, 1000, 'void'),
            ('Coffee', 1, 2000, 'open'),
            ('Removed cake', 0, 1500, 'void'),
            ('Cake', 1, 1500, 'open'),
            ('Voided item', 1, 500, 'void'),
            ('Empty item', 0, 500, 'open'),
            ('Free item', 1, 0, 'open'),
          ])
            {
              'product_name': row.$1,
              'qty': row.$2,
              'unit_price_baisas': row.$3,
              'line_total_baisas': row.$2 * row.$3,
              'status': row.$4,
              'addons': <Object>[],
            },
        ],
      };
      final order = QrQuickOrder(value);
      final workspace = WorkspaceBill(value);
      expect(order.items.map((i) => i['product_name']), [
        'Sweety',
        'Coffee',
        'Cake',
        'Free item',
      ]);
      expect(workspace.items.map((i) => i['product_name']), [
        'Sweety',
        'Coffee',
        'Cake',
        'Free item',
      ]);
      expect(workspace.display(stale: false)['items'], hasLength(4));
      expect(order.total, 3990);
      expect(workspace.total, 3990);
      expect(order.json['items'], hasLength(8));
      expect(workspace.json['items'], hasLength(8));
    },
  );
}
