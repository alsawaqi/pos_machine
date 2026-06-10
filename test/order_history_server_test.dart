import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/models/pos_models.dart';

/// The device hydrates its order-history view from the pos_api
/// /device/orders/history endpoint (branch-wide, cross-device). This verifies
/// the server JSON -> OrderHistoryRecord mapping (money is integer baisas -> OMR).
void main() {
  group('OrderHistoryRecord.fromServerJson', () {
    test('maps the /device/orders/history shape (baisas -> OMR)', () {
      final json = <String, dynamic>{
        'id': 42,
        'uuid': 'order-uuid-1',
        'order_type': 'dine_in',
        'status': 'paid',
        'opened_at': '2026-06-08T09:00:00.000Z',
        'subtotal_baisas': 3000,
        'discount_total_baisas': 500,
        'tax_total_baisas': 0,
        'grand_total_baisas': 2500,
        'note': 'extra hot',
        'items': [
          {
            'product_name': 'Latte',
            'qty': 2,
            'line_total_baisas': 3000,
            'notes': 'oat',
            'addons': [
              {
                'add_on_id': 9,
                'add_on_name': 'Extra Shot',
                'price_delta_baisas': 300,
              },
            ],
          },
        ],
      };

      final r = OrderHistoryRecord.fromServerJson(json);

      expect(r.fromServer, isTrue);
      expect(r.id, 'order-uuid-1');
      expect(r.orderNumber, 42);
      expect(r.orderType, OrderType.dineIn);
      expect(r.createdAt.toUtc().toIso8601String(), '2026-06-08T09:00:00.000Z');

      final s = r.snapshot;
      expect(s.subtotal, 3.0);
      expect(s.discountAmount, 0.5);
      expect(s.tax, 0.0);
      expect(s.total, 2.5);
      expect(s.payableTotal, 2.5);
      expect(s.paymentStatus, 'Paid');
      expect(s.paymentMethod, ''); // server doesn't expose method -> badge hidden
      expect(s.note, 'extra hot');
      expect(s.items.length, 1);
      expect(s.items.first['name'], 'Latte');
      expect(s.items.first['qty'], 2.0);
      expect(s.items.first['lineTotal'], 3.0);

      // Phase C1 — server add-ons map to the CartItem modifier shape so
      // kitchen-ticket reprints of cross-device orders include them.
      final modifiers = s.items.first['modifiers'] as List;
      expect(modifiers.length, 1);
      expect(modifiers.first['label'], 'Extra Shot');
      expect(modifiers.first['group'], '');
      expect(modifiers.first['price'], 0.3);
    });

    test('defaults gracefully on a sparse payload', () {
      final r = OrderHistoryRecord.fromServerJson(
        <String, dynamic>{'id': 7, 'status': 'void'},
      );

      expect(r.fromServer, isTrue);
      expect(r.id, 'srv_7'); // no uuid -> synthesized
      expect(r.orderNumber, 7);
      expect(r.snapshot.paymentStatus, 'Void');
      expect(r.snapshot.items, isEmpty);
      expect(r.snapshot.total, 0);
    });
  });
}
