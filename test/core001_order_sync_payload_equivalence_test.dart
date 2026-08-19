import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/order_sync_payload.dart';

typedef _LegacyPayload = ({
  String orderUuid,
  List<Map<String, dynamic>> events,
});

/// Deterministic UUID stream used independently by each side of a comparison.
String Function() _uuidSequence() {
  var next = 0;
  return () => 'uuid-${next++}';
}

int _legacyOmrToBaisas(double amount) => (amount * 1000).round();

String _legacyOrderType(String value) => switch (value) {
  'dine_in' => 'dine_in',
  'to_go' => 'to_go',
  'delivery' => 'delivery',
  _ => 'quick',
};

String _legacyPaymentMethod(String value) {
  final label = value.toLowerCase();
  if (label.contains('bank')) return 'bank_pos';
  if (label.contains('card')) return 'card';
  if (label.contains('gift')) return 'gift';
  if (label.contains('loyalty')) return 'loyalty';
  return 'cash';
}

/// Test-local oracle copied from the pricing-sensitive part of the machine's
/// pre-CORE-001 order-sync builder. It intentionally reads only frozen
/// OrderSnapshot money and does not call the adopted pricing package or the
/// production payload helpers. The three fixtures below stay inside this
/// oracle's historical order.create + order.pay surface.
_LegacyPayload _legacyBuildOrderSyncPayload(
  OrderSnapshot snapshot, {
  required DateTime now,
  required String Function() newUuid,
  int? staffId,
}) {
  final timestamp = now.toUtc().toIso8601String();
  final orderUuid = snapshot.serverOrderUuid.isNotEmpty
      ? snapshot.serverOrderUuid
      : newUuid();

  final lines = <Map<String, dynamic>>[];
  final lineDiscounts = <Map<String, dynamic>>[];
  var lineDiscountSum = 0.0;
  for (final raw in snapshot.items) {
    final productId = int.tryParse('${raw['id']}');
    if (productId == null) continue;
    final quantity = (raw['qty'] as num?)?.toInt() ?? 1;
    final unitPrice = (raw['unitPrice'] as num?)?.toDouble() ?? 0;
    final lineTotal = (raw['lineTotal'] as num?)?.toDouble() ?? 0;
    final addons = <Map<String, dynamic>>[];
    for (final modifier in (raw['modifiers'] as List? ?? const [])) {
      if (modifier is! Map) continue;
      final addOnId = int.tryParse('${modifier['id']}');
      if (addOnId == null) continue;
      addons.add({
        'add_on_id': addOnId,
        'price_delta_baisas': _legacyOmrToBaisas(
          (modifier['price'] as num?)?.toDouble() ?? 0,
        ),
      });
    }

    final notes = (raw['notes'] as String?)?.trim();
    final lineIndex = lines.length;
    lines.add({
      'product_id': productId,
      'qty': quantity,
      'unit_price_baisas': _legacyOmrToBaisas(unitPrice),
      'line_total_baisas': _legacyOmrToBaisas(lineTotal),
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (addons.isNotEmpty) 'addons': addons,
    });

    final lineDiscount = (raw['lineDiscount'] as num?)?.toDouble() ?? 0;
    if (lineDiscount > 0) {
      lineDiscountSum += lineDiscount;
      final label = (raw['lineDiscountLabel'] as String?) ?? '';
      lineDiscounts.add({
        'name': label.isEmpty ? 'Discount' : label,
        'amount_baisas': _legacyOmrToBaisas(lineDiscount),
        if (raw['lineDiscountId'] != null) 'discount_id': raw['lineDiscountId'],
        if (raw['lineDiscountAmountType'] != null)
          'amount_type': raw['lineDiscountAmountType'],
        'line_index': lineIndex,
      });
    }
  }

  final discounts = <Map<String, dynamic>>[];
  final offerEntries = <Map<String, dynamic>>[];
  var offerSum = 0.0;
  for (final offer in snapshot.offers) {
    final amount = (offer['amount'] as num?)?.toDouble() ?? 0;
    if (amount <= 0) continue;
    offerSum += amount;
    offerEntries.add({
      'name': offer['name']?.toString() ?? 'Offer',
      'amount_baisas': _legacyOmrToBaisas(amount),
      if (offer['offer_id'] != null) 'offer_id': offer['offer_id'],
      if (offer['line_index'] != null) 'line_index': offer['line_index'],
    });
  }
  final orderLevelDiscount =
      (snapshot.discountAmount - lineDiscountSum - offerSum)
          .clamp(0.0, double.infinity)
          .toDouble();
  if (orderLevelDiscount > 0) {
    discounts.add({
      'name': snapshot.discountLabel.isEmpty
          ? 'Discount'
          : snapshot.discountLabel,
      'amount_baisas': _legacyOmrToBaisas(orderLevelDiscount),
      if (snapshot.discountId != null) 'discount_id': snapshot.discountId,
      if (snapshot.discountAmountType != null)
        'amount_type': snapshot.discountAmountType,
      if (snapshot.discountReason.isNotEmpty) 'reason': snapshot.discountReason,
    });
  }
  discounts.addAll(lineDiscounts);
  discounts.addAll(offerEntries);

  final compBaisas = _legacyOmrToBaisas(snapshot.compAmount);
  final comps = <Map<String, dynamic>>[];
  if (compBaisas > 0) {
    var remaining = compBaisas;
    final giftRows = <Map<String, dynamic>>[];
    for (var i = 0; i < snapshot.items.length; i++) {
      final giftAmount =
          (snapshot.items[i]['giftAmount'] as num?)?.toDouble() ?? 0;
      if (giftAmount <= 0) continue;
      final amount = _legacyOmrToBaisas(giftAmount).clamp(0, remaining);
      if (amount <= 0) continue;
      remaining -= amount;
      giftRows.add({
        'is_gift': true,
        'amount_baisas': amount,
        'line_index': i,
        'staff_id': ?staffId,
      });
    }
    if (remaining > 0 && snapshot.compReasonId != null) {
      comps.add({
        'comp_reason_id': snapshot.compReasonId,
        'amount_baisas': remaining,
        'line_index': ?snapshot.compLineIndex,
        if (snapshot.compLineIndex != null && snapshot.compQty != null)
          'qty': snapshot.compQty,
        'staff_id': ?staffId,
        if (snapshot.compReasonName.isNotEmpty) 'note': snapshot.compReasonName,
      });
    }
    // Historical wire order is the reasoned row first, then gift rows.
    comps.addAll(giftRows);
  }

  final order = <String, dynamic>{
    'uuid': orderUuid,
    'order_type': _legacyOrderType(snapshot.orderType),
    'source': 'main_pos',
    // CORE-001 Step 4: licensed additive marker for core-priced payloads.
    'pricing_engine': 1,
    if (snapshot.receiptNumber.isNotEmpty)
      'receipt_number': snapshot.receiptNumber,
    'subtotal_baisas': _legacyOmrToBaisas(snapshot.rawSubtotal),
    'discount_total_baisas': _legacyOmrToBaisas(snapshot.discountAmount),
    if (comps.isNotEmpty) 'comp_total_baisas': compBaisas,
    'tax_total_baisas': _legacyOmrToBaisas(snapshot.tax),
    'grand_total_baisas': _legacyOmrToBaisas(snapshot.total),
    'opened_at': timestamp,
    'lines': lines,
    if (discounts.isNotEmpty) 'discounts': discounts,
    if (comps.isNotEmpty) 'comps': comps,
    'staff_id': ?staffId,
    if (snapshot.note.trim().isNotEmpty) 'note': snapshot.note.trim(),
  };

  final grandBaisas = _legacyOmrToBaisas(snapshot.total);
  final payments = <Map<String, dynamic>>[];
  if (snapshot.splitPayments.isNotEmpty) {
    var accumulated = 0;
    for (var i = 0; i < snapshot.splitPayments.length; i++) {
      final payment = snapshot.splitPayments[i];
      final isLast = i == snapshot.splitPayments.length - 1;
      final amount = isLast
          ? grandBaisas - accumulated
          : _legacyOmrToBaisas(payment.baseAmount);
      accumulated += amount;
      payments.add({
        'method': _legacyPaymentMethod(payment.paymentMethod),
        'amount_baisas': amount,
        'status': 'success',
      });
    }
  } else {
    payments.add({
      'method': _legacyPaymentMethod(snapshot.paymentMethod),
      'amount_baisas': grandBaisas,
      'status': 'success',
    });
  }

  final pay = <String, dynamic>{
    'order_uuid': orderUuid,
    'paid_at': timestamp,
    'payments': payments,
  };
  return (
    orderUuid: orderUuid,
    events: <Map<String, dynamic>>[
      {
        'client_event_id': newUuid(),
        'event_type': 'order.create',
        'client_timestamp': timestamp,
        'payload': {'order': order},
      },
      {
        'client_event_id': newUuid(),
        'event_type': 'order.pay',
        'client_timestamp': timestamp,
        'payload': pay,
      },
    ],
  );
}

String _productionJson(OrderSyncPayload payload) =>
    jsonEncode({'orderUuid': payload.orderUuid, 'events': payload.events});

String _legacyJson(_LegacyPayload payload) =>
    jsonEncode({'orderUuid': payload.orderUuid, 'events': payload.events});

OrderSnapshot _plainCart() => OrderSnapshot.initial().copyWith(
  receiptNumber: 'KLD-0042',
  items: <Map<String, dynamic>>[
    {
      'id': '10',
      'name': 'Latte',
      'qty': 2,
      'unitPrice': 2.500,
      'lineTotal': 5.000,
      'notes': ' extra hot ',
      'modifiers': <Map<String, dynamic>>[
        {'id': '100', 'label': 'Large', 'price': 0.500},
      ],
    },
  ],
  rawSubtotal: 5.000,
  subtotal: 5.000,
  tax: 0.250,
  total: 5.250,
  activePaymentBaseTotal: 5.250,
  payableTotal: 5.250,
  paymentMethod: 'Cash',
  note: 'Window table',
);

OrderSnapshot _discountAndOfferCart() => OrderSnapshot.initial().copyWith(
  items: <Map<String, dynamic>>[
    {
      'id': '20',
      'name': 'Breakfast',
      'qty': 2,
      'unitPrice': 3.000,
      'lineTotal': 6.000,
      'lineDiscount': 0.600,
      'lineDiscountLabel': 'Category 10%',
      'lineDiscountId': 41,
      'lineDiscountAmountType': 'percent',
    },
    {
      'id': '21',
      'name': 'Juice',
      'qty': 1,
      'unitPrice': 4.000,
      'lineTotal': 4.000,
    },
  ],
  rawSubtotal: 10.000,
  discountAmount: 2.500,
  discountLabel: 'VIP adjustment',
  discountId: 44,
  discountAmountType: 'fixed',
  discountReason: 'Service recovery',
  offers: <Map<String, dynamic>>[
    {'offer_id': 9, 'name': 'Lunch pair', 'amount': 0.400, 'line_index': 1},
    {'offer_id': 10, 'name': 'Spend reward', 'amount': 0.500},
  ],
  subtotal: 7.500,
  tax: 0.375,
  total: 7.875,
  activePaymentBaseTotal: 7.875,
  payableTotal: 7.875,
  paymentMethod: 'Credit Card',
);

OrderSnapshot _giftCompSplitCart() => OrderSnapshot.initial().copyWith(
  items: <Map<String, dynamic>>[
    {
      'id': '30',
      'name': 'Gifted dessert',
      'qty': 1,
      'unitPrice': 3.000,
      'lineTotal': 3.000,
      'gifted': true,
      'giftAmount': 3.000,
    },
    {
      'id': '31',
      'name': 'Main course',
      'qty': 2,
      'unitPrice': 3.500,
      'lineTotal': 7.000,
    },
  ],
  rawSubtotal: 10.000,
  subtotal: 10.000,
  compAmount: 5.000,
  compReasonId: 42,
  compReasonName: 'Service recovery',
  compLineIndex: 1,
  compQty: 1,
  tax: 0.250,
  total: 5.250,
  activePaymentBaseTotal: 2.625,
  splitCount: 2,
  payableTotal: 2.625,
  paymentMethod: 'Split Payment',
  splitPayments: <SplitPaymentRecord>[
    SplitPaymentRecord(
      splitIndex: 1,
      splitCount: 2,
      paymentMethod: 'Cash',
      baseAmount: 2.625,
      charityRoundUpAccepted: false,
      charityRoundUpAmount: 0,
      paidAmount: 2.625,
      paidAt: DateTime.utc(2026, 8, 17, 8, 1),
    ),
    SplitPaymentRecord(
      splitIndex: 2,
      splitCount: 2,
      paymentMethod: 'Credit Card',
      baseAmount: 2.625,
      charityRoundUpAccepted: false,
      charityRoundUpAmount: 0,
      paidAmount: 2.625,
      paidAt: DateTime.utc(2026, 8, 17, 8, 2),
    ),
  ],
);

void main() {
  final fixedNow = DateTime.utc(2026, 8, 17, 8, 30);

  group('CORE-001 Step 2 payload byte equivalence', () {
    for (final fixture in <({String name, OrderSnapshot snapshot})>[
      (name: 'plain cart', snapshot: _plainCart()),
      (
        name: 'discount plus line and order offers',
        snapshot: _discountAndOfferCart(),
      ),
      (
        name: 'gift plus reasoned comp and split tender',
        snapshot: _giftCompSplitCart(),
      ),
    ]) {
      test('${fixture.name} stays JSON-identical to the legacy builder', () {
        final production = buildOrderSyncPayload(
          fixture.snapshot,
          staffId: 7,
          now: fixedNow,
          newUuid: _uuidSequence(),
        );
        final legacy = _legacyBuildOrderSyncPayload(
          fixture.snapshot,
          staffId: 7,
          now: fixedNow,
          newUuid: _uuidSequence(),
        );

        expect(_productionJson(production), _legacyJson(legacy));
      });
    }

    test('compatibility order remains reasoned comp row before gift row', () {
      final payload = buildOrderSyncPayload(
        _giftCompSplitCart(),
        staffId: 7,
        now: fixedNow,
        newUuid: _uuidSequence(),
      );
      final order =
          (payload.events.first['payload'] as Map<String, dynamic>)['order']
              as Map<String, dynamic>;
      final comps = (order['comps'] as List).cast<Map<String, dynamic>>();

      expect(comps, hasLength(2));
      expect(comps.first['comp_reason_id'], 42);
      expect(comps.first.containsKey('is_gift'), isFalse);
      expect(comps.first['note'], 'Service recovery');
      expect(comps.first['qty'], 1);
      expect(comps.last['is_gift'], isTrue);
      expect(comps.map((row) => row['amount_baisas']), <int>[2000, 3000]);
    });
  });
}
