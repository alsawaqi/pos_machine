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
  int? discountId,
  String? discountAmountType,
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
    discountId: discountId,
    discountAmountType: discountAmountType,
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

    test('customer id + vehicle plate ride on the order', () {
      final snap = _snapshot(
        items: [
          {'id': '5', 'qty': 1, 'unitPrice': 1.0, 'lineTotal': 1.0},
        ],
        rawSubtotal: 1.0,
        total: 1.0,
      );

      final payload = buildOrderSyncPayload(
        snap,
        customerId: 88,
        plateNumber: '  A12345  ',
        newUuid: _seqUuid(),
      );
      final order =
          (payload.events[0]['payload'] as Map)['order'] as Map<String, dynamic>;
      expect(order['customer_id'], 88);
      expect(order['plate_number'], 'A12345'); // trimmed
    });

    test('null customer / blank plate are omitted from the order', () {
      final snap = _snapshot(
        items: [
          {'id': '5', 'qty': 1, 'unitPrice': 1.0, 'lineTotal': 1.0},
        ],
        rawSubtotal: 1.0,
        total: 1.0,
      );

      final payload =
          buildOrderSyncPayload(snap, plateNumber: '   ', newUuid: _seqUuid());
      final order =
          (payload.events[0]['payload'] as Map)['order'] as Map<String, dynamic>;
      expect(order.containsKey('customer_id'), isFalse);
      expect(order.containsKey('plate_number'), isFalse);
    });

    test('single card tender carries the Soft POS evidence + success status', () {
      final snap = _snapshot(
        items: [
          {'id': '5', 'qty': 1, 'unitPrice': 3.0, 'lineTotal': 3.0},
        ],
        rawSubtotal: 3.0,
        total: 3.0,
        paymentMethod: 'Credit Card',
      );

      final payload = buildOrderSyncPayload(
        snap,
        cardCharge: const CardCharge(
          softposReference: 'RRN123',
          softposAuthCode: 'AUTH9',
          bankResponse: {'result': 'SUCCESS', 'rrn': 'RRN123'},
        ),
        newUuid: _seqUuid(),
      );

      final tender =
          ((payload.events[1]['payload'] as Map)['payments'] as List).first
              as Map<String, dynamic>;
      expect(tender['method'], 'card');
      expect(tender['softpos_reference'], 'RRN123');
      expect(tender['softpos_auth_code'], 'AUTH9');
      expect((tender['bank_response'] as Map)['result'], 'SUCCESS');
      expect(tender['status'], 'success');
    });

    test('a force-recorded card charge rides as pending_reconciliation', () {
      final snap = _snapshot(
        items: [
          {'id': '5', 'qty': 1, 'unitPrice': 3.0, 'lineTotal': 3.0},
        ],
        rawSubtotal: 3.0,
        total: 3.0,
        paymentMethod: 'Credit Card',
      );

      final payload = buildOrderSyncPayload(
        snap,
        cardCharge: const CardCharge(
          softposReference: 'NFC-TIMEOUT',
          status: 'pending_reconciliation',
        ),
        newUuid: _seqUuid(),
      );

      final tender =
          ((payload.events[1]['payload'] as Map)['payments'] as List).first
              as Map<String, dynamic>;
      expect(tender['status'], 'pending_reconciliation');
      expect(tender['softpos_reference'], 'NFC-TIMEOUT');
    });

    test('a cash single tender never gets card fields from cardCharge', () {
      final snap = _snapshot(
        items: [
          {'id': '5', 'qty': 1, 'unitPrice': 1.0, 'lineTotal': 1.0},
        ],
        rawSubtotal: 1.0,
        total: 1.0,
        paymentMethod: 'Cash',
      );

      final payload = buildOrderSyncPayload(
        snap,
        cardCharge: const CardCharge(softposReference: 'X'),
        newUuid: _seqUuid(),
      );
      final tender =
          ((payload.events[1]['payload'] as Map)['payments'] as List).first
              as Map<String, dynamic>;
      expect(tender['method'], 'cash');
      expect(tender.containsKey('softpos_reference'), isFalse);
      expect(tender['status'], 'success');
    });

    test('a card tender within a split carries its own evidence', () {
      final snap = _snapshot(
        items: [
          {'id': '5', 'qty': 1, 'unitPrice': 10.0, 'lineTotal': 10.0},
        ],
        rawSubtotal: 10.0,
        total: 10.0,
        paymentMethod: 'Split Payment',
        splitPayments: [
          _split(1, 'Cash', 6.0),
          _split(2, 'Credit Card', 4.0,
              cardCharge: const CardCharge(
                  softposReference: 'SPLITRRN', softposAuthCode: 'SA1')),
        ],
      );

      final payload = buildOrderSyncPayload(snap, newUuid: _seqUuid());
      final payments =
          (payload.events[1]['payload'] as Map)['payments'] as List;
      final cash = payments[0] as Map<String, dynamic>;
      final card = payments[1] as Map<String, dynamic>;
      expect(cash['method'], 'cash');
      expect(cash.containsKey('softpos_reference'), isFalse);
      expect(card['method'], 'card');
      expect(card['softpos_reference'], 'SPLITRRN');
      expect(card['softpos_auth_code'], 'SA1');
    });

    test('a merchant-rule discount carries discount_id + amount_type', () {
      final snap = _snapshot(
        items: [
          {'id': '5', 'qty': 1, 'unitPrice': 10.0, 'lineTotal': 10.0},
        ],
        rawSubtotal: 10.0,
        discountAmount: 1.0,
        discountLabel: 'Ramadan 10%',
        discountId: 3,
        discountAmountType: 'percent',
        total: 9.0,
      );

      final payload = buildOrderSyncPayload(snap, newUuid: _seqUuid());
      final order =
          (payload.events[0]['payload'] as Map)['order'] as Map<String, dynamic>;
      final discounts = order['discounts'] as List;
      expect(discounts.length, 1);
      final d = discounts.first as Map<String, dynamic>;
      expect(d['name'], 'Ramadan 10%');
      expect(d['amount_baisas'], 1000);
      expect(d['discount_id'], 3);
      expect(d['amount_type'], 'percent');
    });

    test('a manual discount omits discount_id + amount_type', () {
      final snap = _snapshot(
        items: [
          {'id': '5', 'qty': 1, 'unitPrice': 10.0, 'lineTotal': 10.0},
        ],
        rawSubtotal: 10.0,
        discountAmount: 2.0,
        discountLabel: 'Manual',
        total: 8.0,
      );

      final payload = buildOrderSyncPayload(snap, newUuid: _seqUuid());
      final order =
          (payload.events[0]['payload'] as Map)['order'] as Map<String, dynamic>;
      final d = (order['discounts'] as List).first as Map<String, dynamic>;
      expect(d.containsKey('discount_id'), isFalse);
      expect(d.containsKey('amount_type'), isFalse);
    });

    test('loyalty_rule_id rides on the pay event when set', () {
      final snap = _snapshot(
        items: [
          {'id': '5', 'qty': 1, 'unitPrice': 3.0, 'lineTotal': 3.0},
        ],
        rawSubtotal: 3.0,
        total: 3.0,
      );

      final payload =
          buildOrderSyncPayload(snap, loyaltyRuleId: 2, newUuid: _seqUuid());
      final pay = (payload.events[1]['payload'] as Map<String, dynamic>);
      expect(pay['loyalty_rule_id'], 2);
    });

    test('no loyalty_rule_id key when unset (walk-in / no rule)', () {
      final snap = _snapshot(
        items: [
          {'id': '5', 'qty': 1, 'unitPrice': 3.0, 'lineTotal': 3.0},
        ],
        rawSubtotal: 3.0,
        total: 3.0,
      );

      final payload = buildOrderSyncPayload(snap, newUuid: _seqUuid());
      final pay = (payload.events[1]['payload'] as Map<String, dynamic>);
      expect(pay.containsKey('loyalty_rule_id'), isFalse);
    });

    test('loyalty_redeem rides on the pay event when points are redeemed', () {
      final snap = OrderSnapshot.initial().copyWith(
        items: [
          {'id': '5', 'qty': 1, 'unitPrice': 10.0, 'lineTotal': 10.0},
        ],
        rawSubtotal: 10.0,
        discountAmount: 5.0,
        discountLabel: 'Loyalty redemption',
        loyaltyRedeemRuleId: 2,
        loyaltyRedeemPoints: 100,
        total: 5.0,
      );

      final payload = buildOrderSyncPayload(snap, newUuid: _seqUuid());
      final pay = payload.events[1]['payload'] as Map<String, dynamic>;
      expect(pay['loyalty_redeem'], {'rule_id': 2, 'points': 100, 'stamps': 0});
    });

    test('loyalty_redeem carries stamps on a visit_based redemption', () {
      final snap = OrderSnapshot.initial().copyWith(
        items: [
          {'id': '5', 'qty': 1, 'unitPrice': 10.0, 'lineTotal': 10.0},
        ],
        rawSubtotal: 10.0,
        discountAmount: 4.0,
        discountLabel: 'Stamp reward',
        loyaltyRedeemRuleId: 3,
        loyaltyRedeemPoints: 0,
        loyaltyRedeemStamps: 5,
        total: 6.0,
      );

      final payload = buildOrderSyncPayload(snap, newUuid: _seqUuid());
      final pay = payload.events[1]['payload'] as Map<String, dynamic>;
      expect(pay['loyalty_redeem'], {'rule_id': 3, 'points': 0, 'stamps': 5});
    });

    test('no loyalty_redeem key when nothing is redeemed', () {
      final snap = _snapshot(
        items: [
          {'id': '5', 'qty': 1, 'unitPrice': 3.0, 'lineTotal': 3.0},
        ],
        rawSubtotal: 3.0,
        total: 3.0,
      );
      final payload = buildOrderSyncPayload(snap, newUuid: _seqUuid());
      final pay = payload.events[1]['payload'] as Map<String, dynamic>;
      expect(pay.containsKey('loyalty_redeem'), isFalse);
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

    test('reuses the snapshot serverOrderUuid as the order.create uuid', () {
      final snap = _snapshot(
        items: [
          {'id': '5', 'qty': 1, 'unitPrice': 1.0, 'lineTotal': 1.0},
        ],
        rawSubtotal: 1.0,
        total: 1.0,
      ).copyWith(serverOrderUuid: 'fixed-order-uuid');

      final payload = buildOrderSyncPayload(snap, newUuid: _seqUuid());

      // The generated uuid-0 is NOT used; the stamped uuid is, on both events.
      expect(payload.orderUuid, 'fixed-order-uuid');
      final order =
          (payload.events[0]['payload'] as Map)['order'] as Map<String, dynamic>;
      expect(order['uuid'], 'fixed-order-uuid');
      expect((payload.events[1]['payload'] as Map)['order_uuid'],
          'fixed-order-uuid');
    });
  });

  group('buildOrderVoidEvent', () {
    test('builds an order.void with the order_uuid + reason + audit fields', () {
      final event = buildOrderVoidEvent(
        orderUuid: 'order-123',
        reason: '  Canceled by manager  ',
        staffId: 7,
        authorizedBy: ' Manager ',
        voidedAt: DateTime.utc(2026, 6, 9, 10, 30),
        newUuid: _seqUuid(),
      );

      expect(event['event_type'], 'order.void');
      expect(event['client_event_id'], 'uuid-0');
      expect(event['client_timestamp'], '2026-06-09T10:30:00.000Z');

      final payload = event['payload'] as Map<String, dynamic>;
      expect(payload['order_uuid'], 'order-123');
      expect(payload['voided_at'], '2026-06-09T10:30:00.000Z');
      expect(payload['reason'], 'Canceled by manager'); // trimmed
      expect(payload['staff_id'], 7);
      expect(payload['authorized_by'], 'Manager'); // trimmed
    });

    test('omits blank reason / authorized_by / null staff_id', () {
      final event = buildOrderVoidEvent(
        orderUuid: 'order-9',
        reason: '   ',
        authorizedBy: '',
        newUuid: _seqUuid(),
      );

      final payload = event['payload'] as Map<String, dynamic>;
      expect(payload['order_uuid'], 'order-9');
      expect(payload.containsKey('reason'), isFalse);
      expect(payload.containsKey('authorized_by'), isFalse);
      expect(payload.containsKey('staff_id'), isFalse);
    });
  });
}

SplitPaymentRecord _split(int index, String method, double base,
        {CardCharge? cardCharge}) =>
    SplitPaymentRecord(
      splitIndex: index,
      splitCount: 3,
      paymentMethod: method,
      baseAmount: base,
      charityRoundUpAccepted: false,
      charityRoundUpAmount: 0,
      paidAmount: base,
      paidAt: DateTime.fromMillisecondsSinceEpoch(0),
      cardCharge: cardCharge,
    );
