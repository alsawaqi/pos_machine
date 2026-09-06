import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/order_sync_payload.dart';

String Function() _ids() {
  var next = 0;
  return () => 'event-${next++}';
}

void main() {
  final at = DateTime.utc(2026, 9, 6, 12);
  const charge = CardCharge(
    softposReference: 'bank-ref',
    softposAuthCode: 'approved',
    bankResponse: {'receipt': 'evidence'},
    status: 'pending_reconciliation',
  );
  for (final bill in ['', 'proposed-bill']) {
    for (final method in ['Cash', 'Card', 'Bank POS', 'Gift']) {
      test('pay-only equals legacy second event: $bill / $method', () {
        final snapshot = OrderSnapshot.initial().copyWith(
          serverOrderUuid: bill,
          orderType: 'dine_in',
          rawSubtotal: 4.5,
          subtotal: 4.5,
          total: 4.725,
          tax: .225,
          paymentMethod: method,
          loyaltyRedeemRuleId: 3,
          loyaltyRedeemPoints: 5,
        );
        final full = buildOrderSyncPayload(
          snapshot,
          now: at,
          newUuid: _ids(),
          lat: 23,
          lng: 58,
          cardCharge: charge,
          loyaltyRuleIds: [7],
        );
        final pay = buildOrderPayEvent(
          snapshot,
          now: at,
          newUuid: _ids(),
          lat: 23,
          lng: 58,
          cardCharge: charge,
          loyaltyRuleIds: [7],
        );
        expect(pay, full.events[1]);
        expect(jsonEncode(pay), jsonEncode(full.events[1]));
        expect(pay['event_type'], 'order.pay');
        expect(jsonEncode([pay]), isNot(contains('order.create')));
        expect((pay['payload'] as Map)['gps'], {'lat': 23.0, 'lng': 58.0});
      });
    }
  }
  test(
    'split tenders retain rounding and each card evidence byte-for-byte',
    () {
      final snapshot = OrderSnapshot.initial().copyWith(
        serverOrderUuid: 'bill',
        total: 4.501,
        subtotal: 4.501,
        rawSubtotal: 4.501,
        splitPayments: [
          SplitPaymentRecord(
            splitIndex: 1,
            splitCount: 2,
            paymentMethod: 'Cash',
            baseAmount: 2.25,
            paidAmount: 2.25,
            paidAt: at,
            charityRoundUpAccepted: false,
            charityRoundUpAmount: 0,
          ),
          SplitPaymentRecord(
            splitIndex: 2,
            splitCount: 2,
            paymentMethod: 'Card',
            baseAmount: 2.25,
            paidAmount: 2.25,
            paidAt: at,
            charityRoundUpAccepted: false,
            charityRoundUpAmount: 0,
            cardCharge: charge,
          ),
        ],
      );
      final pay = buildOrderPayEvent(snapshot, now: at, newUuid: _ids());
      final full = buildOrderSyncPayload(snapshot, now: at, newUuid: _ids());
      expect(pay, full.events[1]);
      expect(jsonEncode(pay), jsonEncode(full.events[1]));
      expect((pay['payload'] as Map)['payments'], [
        {'method': 'cash', 'amount_baisas': 2250, 'status': 'success'},
        {
          'method': 'card',
          'amount_baisas': 2251,
          'status': 'pending_reconciliation',
          'softpos_reference': 'bank-ref',
          'softpos_auth_code': 'approved',
          'bank_response': {'receipt': 'evidence'},
        },
      ]);
    },
  );
}
