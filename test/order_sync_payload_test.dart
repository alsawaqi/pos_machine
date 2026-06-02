import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/order_sync_payload.dart';

/// Deterministic uuid generator: uuid-0 (order), uuid-1 (create), uuid-2 (pay),
/// uuid-3 (donation).
String Function() _seqUuid() {
  var n = 0;
  return () => 'uuid-${n++}';
}

OrderSnapshot _snapshot({
  String orderType = 'quick_order',
  required List<Map<String, dynamic>> items,
  double rawSubtotal = 0,
  double discountAmount = 0,
  String discountLabel = '',
  double tax = 0,
  double total = 0,
  String paymentMethod = 'Cash',
  bool charityRoundUpAccepted = false,
  double charityRoundUpAmount = 0,
  List<SplitPaymentRecord> splitPayments = const [],
  String note = '',
  String diningTableId = '',
}) {
  return OrderSnapshot.initial().copyWith(
    orderType: orderType,
    items: items,
    rawSubtotal: rawSubtotal,
    discountAmount: discountAmount,
    discountLabel: discountLabel,
    tax: tax,
    total: total,
    paymentMethod: paymentMethod,
    charityRoundUpAccepted: charityRoundUpAccepted,
    charityRoundUpAmount: charityRoundUpAmount,
    splitPayments: splitPayments,
    note: note,
    diningTableId: diningTableId,
  );
}

void main() {
  group('buildOrderSyncPayload', () {
    test('card order with add-on + round-up → create + pay + donation', () {
      final snap = _snapshot(
        orderType: 'quick_order',
        items: [
          {
            'id': '10',
            'name': 'Latte',
            'qty': 2,
            'unitPrice': 2.5, // 2.0 base + 0.5 add-on
            'lineTotal': 5.0,
            'modifiers': [
              {'id': '100', 'group': 'Size', 'label': 'Large', 'price': 0.5},
            ],
            'notes': 'extra hot',
          },
        ],
        rawSubtotal: 5.0,
        tax: 0.25,
        total: 5.25,
        paymentMethod: 'Credit Card',
        charityRoundUpAccepted: true,
        charityRoundUpAmount: 0.75,
        note: 'table by window',
      );

      final payload = buildOrderSyncPayload(
        snap,
        lat: 23.588,
        lng: 58.3829,
        staffId: 7,
        newUuid: _seqUuid(),
      );

      expect(payload.orderUuid, 'uuid-0');
      expect(payload.events.length, 3);

      // order.create
      final create = payload.events[0];
      expect(create['event_type'], 'order.create');
      expect(create['client_event_id'], 'uuid-1');
      final order = (create['payload'] as Map)['order'] as Map<String, dynamic>;
      expect(order['uuid'], 'uuid-0');
      expect(order['order_type'], 'quick');
      expect(order['source'], 'main_pos');
      expect(order['subtotal_baisas'], 5000);
      expect(order['tax_total_baisas'], 250);
      expect(order['discount_total_baisas'], 0);
      expect(order['grand_total_baisas'], 5250);
      expect(order['staff_id'], 7);
      expect(order['note'], 'table by window');
      expect(order['gps'], {'lat': 23.588, 'lng': 58.3829});

      // money invariant the server enforces
      expect(
        (order['subtotal_baisas'] as int) -
            (order['discount_total_baisas'] as int) +
            (order['tax_total_baisas'] as int),
        order['grand_total_baisas'],
      );

      final lines = order['lines'] as List;
      expect(lines.length, 1);
      final line = lines.first as Map<String, dynamic>;
      expect(line['product_id'], 10);
      expect(line['qty'], 2);
      expect(line['unit_price_baisas'], 2500);
      expect(line['line_total_baisas'], 5000);
      expect(line['notes'], 'extra hot');
      final addons = line['addons'] as List;
      expect(addons.length, 1);
      expect((addons.first as Map)['add_on_id'], 100);
      expect((addons.first as Map)['price_delta_baisas'], 500);

      // order.pay
      final pay = payload.events[1];
      expect(pay['event_type'], 'order.pay');
      final payP = pay['payload'] as Map<String, dynamic>;
      expect(payP['order_uuid'], 'uuid-0');
      final payments = payP['payments'] as List;
      expect(payments.length, 1);
      expect((payments.first as Map)['method'], 'card');
      expect((payments.first as Map)['amount_baisas'], 5250); // == grand

      // donation.record (rode the card payment)
      final donation = payload.events[2];
      expect(donation['event_type'], 'donation.record');
      final donP = donation['payload'] as Map<String, dynamic>;
      expect(donP['order_uuid'], 'uuid-0');
      expect(donP['amount_baisas'], 750);
    });

    test('cash order has no donation event even if round-up flagged', () {
      final snap = _snapshot(
        items: [
          {'id': '5', 'qty': 1, 'unitPrice': 1.0, 'lineTotal': 1.0},
        ],
        rawSubtotal: 1.0,
        total: 1.0,
        paymentMethod: 'Cash',
        charityRoundUpAccepted: true,
        charityRoundUpAmount: 0.5,
      );

      final payload = buildOrderSyncPayload(snap, newUuid: _seqUuid());

      expect(payload.events.map((e) => e['event_type']),
          ['order.create', 'order.pay']);
      final payments =
          (payload.events[1]['payload'] as Map)['payments'] as List;
      expect((payments.first as Map)['method'], 'cash');
    });

    test('split tenders sum exactly to grand_total (rounding absorbed)', () {
      final snap = _snapshot(
        items: [
          {'id': '5', 'qty': 1, 'unitPrice': 10.0, 'lineTotal': 10.0},
        ],
        rawSubtotal: 10.0,
        total: 10.0,
        paymentMethod: 'Split Payment',
        splitPayments: [
          _split(1, 'Cash', 3.333),
          _split(2, 'Cash', 3.333),
          _split(3, 'Credit Card', 3.334),
        ],
      );

      final payload = buildOrderSyncPayload(snap, newUuid: _seqUuid());
      final payments =
          (payload.events[1]['payload'] as Map)['payments'] as List;
      expect(payments.length, 3);
      final sum = payments.fold<int>(
          0, (s, p) => s + ((p as Map)['amount_baisas'] as int));
      expect(sum, 10000); // exactly grand_total, no ±drift
      expect((payments[2] as Map)['method'], 'card');
    });

    test('non-catalog (non-numeric) product ids are dropped from lines', () {
      final snap = _snapshot(
        items: [
          {'id': 'demo-espresso', 'qty': 1, 'unitPrice': 1.0, 'lineTotal': 1.0},
          {'id': '42', 'qty': 1, 'unitPrice': 2.0, 'lineTotal': 2.0},
        ],
        rawSubtotal: 3.0,
        total: 3.0,
      );

      final payload = buildOrderSyncPayload(snap, newUuid: _seqUuid());
      final lines =
          ((payload.events[0]['payload'] as Map)['order'] as Map)['lines']
              as List;
      expect(lines.length, 1);
      expect((lines.first as Map)['product_id'], 42);
    });

    test('helpers map enums + money correctly', () {
      expect(mapOrderType('dine_in'), 'dine_in');
      expect(mapOrderType('to_go'), 'to_go');
      expect(mapOrderType('delivery'), 'delivery');
      expect(mapOrderType('quick_order'), 'quick');
      expect(mapPaymentMethod('Credit Card'), 'card');
      expect(mapPaymentMethod('Cash'), 'cash');
      expect(omrToBaisas(1.234), 1234);
      expect(omrToBaisas(0.1), 100);
    });
  });
}

SplitPaymentRecord _split(int index, String method, double base) =>
    SplitPaymentRecord(
      splitIndex: index,
      splitCount: 3,
      paymentMethod: method,
      baseAmount: base,
      charityRoundUpAccepted: false,
      charityRoundUpAmount: 0,
      paidAmount: base,
      paidAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
