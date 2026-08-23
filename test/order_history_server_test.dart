import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/models/pos_models.dart';

Map<String, dynamic> _serverOrder({
  Map<String, dynamic> extra = const <String, dynamic>{},
}) {
  return <String, dynamic>{
    'id': 42,
    'uuid': 'server-order-42',
    'order_type': 'dine_in',
    'status': 'paid',
    'opened_at': '2026-06-08T09:00:00.000Z',
    'subtotal_baisas': 3000,
    'discount_total_baisas': 500,
    'tax_total_baisas': 0,
    'grand_total_baisas': 2500,
    'items': <Map<String, dynamic>>[],
    ...extra,
  };
}

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
      expect(s.rawSubtotal, 3.0);
      // raw − discount (D-6)
      expect(s.subtotal, 2.5);
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

    test('maps the first reasoned comp and skips a preceding gift row', () {
      final s = OrderHistoryRecord.fromServerJson(
        _serverOrder(
          extra: <String, dynamic>{
            'comp_total_baisas': 2500,
            'comps': <Map<String, dynamic>>[
              <String, dynamic>{
                'is_gift': true,
                'line_index': 0,
                'amount_baisas': 1000,
                'comp_reason_id': null,
                'qty': null,
                'reason_name': 'Gift',
              },
              <String, dynamic>{
                'is_gift': false,
                'line_index': 1,
                'amount_baisas': 1500,
                'comp_reason_id': 2,
                'qty': 1,
                'reason_name': 'Staff Meal',
                'note': 'regular',
              },
            ],
          },
        ),
      ).snapshot;

      expect(s.compAmount, 2.5);
      expect(s.compReasonId, 2);
      expect(s.compReasonName, 'Staff Meal');
      expect(s.compLineIndex, 1);
      expect(s.compQty, 1);
    });

    test('gift-only comps keep the reason fields sparse', () {
      final s = OrderHistoryRecord.fromServerJson(
        _serverOrder(
          extra: <String, dynamic>{
            'comp_total_baisas': 1000,
            'comps': <Map<String, dynamic>>[
              <String, dynamic>{
                'is_gift': true,
                'line_index': 0,
                'amount_baisas': 1000,
                'comp_reason_id': null,
                'qty': null,
                'reason_name': 'Gift',
              },
            ],
          },
        ),
      ).snapshot;

      expect(s.compAmount, 1.0);
      expect(s.compReasonId, isNull);
      expect(s.compReasonName, '');
      expect(s.compLineIndex, isNull);
      expect(s.compQty, isNull);
    });

    test('falls back to the comp note when the reason name is absent', () {
      final s = OrderHistoryRecord.fromServerJson(
        _serverOrder(
          extra: <String, dynamic>{
            'comp_total_baisas': 1000,
            'comps': <Map<String, dynamic>>[
              <String, dynamic>{
                'is_gift': false,
                'comp_reason_id': 3,
                'line_index': null,
                'qty': null,
                'amount_baisas': 1000,
                'note': 'Service recovery',
              },
            ],
          },
        ),
      ).snapshot;

      expect(s.compReasonName, 'Service recovery');
      expect(s.compReasonId, 3);
      expect(s.compLineIndex, isNull);
    });

    test('absent comp keys preserve defaults and the discounted money pins', () {
      final s = OrderHistoryRecord.fromServerJson(_serverOrder()).snapshot;

      expect(s.compAmount, 0);
      expect(s.compReasonId, isNull);
      expect(s.compReasonName, '');
      expect(s.compLineIndex, isNull);
      expect(s.compQty, isNull);
      expect(s.rawSubtotal, 3.0);
      expect(s.subtotal, 2.5);
      expect(s.discountAmount, 0.5);
      expect(s.total, 2.5);
      expect(s.payableTotal, 2.5);
    });

    test('server subtotal is raw subtotal less discount', () {
      final s = OrderHistoryRecord.fromServerJson(
        _serverOrder(
          extra: <String, dynamic>{
            'subtotal_baisas': 3000,
            'discount_total_baisas': 500,
          },
        ),
      ).snapshot;

      expect(s.rawSubtotal, 3.0);
      expect(s.subtotal, 2.5);
    });
  });
}
