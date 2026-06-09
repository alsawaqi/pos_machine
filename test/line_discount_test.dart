import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/order_sync_payload.dart';

String Function() _seqUuid() {
  var n = 0;
  return () => 'uuid-${n++}';
}

OrderSnapshot _snap({
  required List<Map<String, dynamic>> items,
  double rawSubtotal = 0,
  double discountAmount = 0,
  String discountLabel = '',
  int? discountId,
  String? discountAmountType,
  double tax = 0,
  double total = 0,
}) {
  return OrderSnapshot.initial().copyWith(
    items: items,
    rawSubtotal: rawSubtotal,
    discountAmount: discountAmount,
    discountLabel: discountLabel,
    discountId: discountId,
    discountAmountType: discountAmountType,
    tax: tax,
    total: total,
  );
}

void main() {
  group('MerchantDiscount line-level applicability', () {
    test('appliesToProduct matches product + category scope, not order scope', () {
      const productRule = MerchantDiscount(
        id: 1,
        name: 'Latte 20%',
        scope: 'product',
        amountType: 'percent',
        percent: 20,
        targets: [DiscountTarget(targetType: 'product', targetId: 10)],
      );
      expect(productRule.appliesToProduct(10, 3), isTrue);
      expect(productRule.appliesToProduct(11, 3), isFalse);

      const categoryRule = MerchantDiscount(
        id: 2,
        name: 'Coffee 0.5 off',
        scope: 'category',
        amountType: 'fixed',
        fixedAmount: 0.5,
        targets: [DiscountTarget(targetType: 'category', targetId: 3)],
      );
      expect(categoryRule.appliesToProduct(10, 3), isTrue);
      expect(categoryRule.appliesToProduct(10, 4), isFalse);

      const orderRule = MerchantDiscount(
        id: 3, name: 'Order 10%', scope: 'order', amountType: 'percent', percent: 10,
      );
      expect(orderRule.appliesToProduct(10, 3), isFalse);
    });

    test('amountFor computes percent/fixed, clamped to the line', () {
      const pct = MerchantDiscount(
          id: 1, name: '', scope: 'product', amountType: 'percent', percent: 20);
      expect(pct.amountFor(5.0), 1.0);

      const fix = MerchantDiscount(
          id: 2, name: '', scope: 'product', amountType: 'fixed', fixedAmount: 0.5);
      expect(fix.amountFor(5.0), 0.5);
      expect(fix.amountFor(0.3), 0.3); // can't exceed the line
    });
  });

  group('order.create per-line discounts', () {
    test('a line discount rides as a discounts[] entry with line_index', () {
      final snap = _snap(
        items: [
          {
            'id': '10', 'name': 'Latte', 'qty': 2, 'unitPrice': 2.5, 'lineTotal': 5.0,
            'lineDiscount': 1.0, 'lineDiscountId': 7,
            'lineDiscountAmountType': 'percent', 'lineDiscountLabel': 'Latte 20%',
          },
          {'id': '11', 'name': 'Cake', 'qty': 1, 'unitPrice': 3.0, 'lineTotal': 3.0},
        ],
        rawSubtotal: 8.0,
        discountAmount: 1.0, // only the line discount
        total: 7.0,
      );

      final payload = buildOrderSyncPayload(snap, staffId: 1, newUuid: _seqUuid());
      final order =
          (payload.events[0]['payload'] as Map)['order'] as Map<String, dynamic>;
      final discounts = (order['discounts'] as List).cast<Map<String, dynamic>>();

      expect(discounts.length, 1); // no order-level portion left
      final d = discounts.single;
      expect(d['amount_baisas'], 1000);
      expect(d['discount_id'], 7);
      expect(d['amount_type'], 'percent');
      expect(d['line_index'], 0); // Latte is the first emitted line

      // money invariant the server enforces
      expect(order['subtotal_baisas'], 8000);
      expect(order['discount_total_baisas'], 1000);
      expect(
        (order['subtotal_baisas'] as int) -
            (order['discount_total_baisas'] as int) +
            (order['tax_total_baisas'] as int),
        order['grand_total_baisas'],
      );
    });

    test('order-level + line discounts both emitted, order-level split out', () {
      final snap = _snap(
        items: [
          {
            'id': '10', 'name': 'Latte', 'qty': 1, 'unitPrice': 5.0, 'lineTotal': 5.0,
            'lineDiscount': 1.0, 'lineDiscountId': 7,
            'lineDiscountAmountType': 'percent', 'lineDiscountLabel': 'Latte 20%',
          },
        ],
        rawSubtotal: 5.0,
        discountAmount: 1.5, // 1.0 line + 0.5 order-level
        discountLabel: 'Order 0.5',
        discountId: 99,
        discountAmountType: 'fixed',
        total: 3.5,
      );

      final payload = buildOrderSyncPayload(snap, staffId: 1, newUuid: _seqUuid());
      final order =
          (payload.events[0]['payload'] as Map)['order'] as Map<String, dynamic>;
      final discounts = (order['discounts'] as List).cast<Map<String, dynamic>>();

      expect(discounts.length, 2);
      final orderLevel =
          discounts.firstWhere((d) => !d.containsKey('line_index'));
      expect(orderLevel['amount_baisas'], 500); // 1.5 - 1.0
      expect(orderLevel['discount_id'], 99);
      final lineLevel = discounts.firstWhere((d) => d.containsKey('line_index'));
      expect(lineLevel['amount_baisas'], 1000);
      expect(lineLevel['line_index'], 0);
    });
  });
}
