import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/services/qr_till_messages.dart';

void main() {
  test(
    'source-enumerated QR refusal codes all have English and Arabic copy',
    () {
      const expectedFromServerSource = {
        'device_not_table_board_reader',
        'device_unassigned',
        'device_not_attended',
        'order_not_found',
        'qr_order_not_settleable',
        'order_not_bound_to_device_session',
        'qr_session_expired',
        'qr_session_not_settleable',
        'charge_already_claimed',
        'qr_charge_recovery_required',
        'geofence_fix_required',
        'geofence_outside',
        'validation_failed',
        'rate_limited',
        'qr_session_not_ordered',
        'qr_order_not_reopenable',
        'order_already_held',
        'order_not_awaiting_payment',
        'numbering_disabled',
        'device_not_payment_station',
        'session_not_ordered',
        'qr_table_not_found',
        'qr_table_charge_live',
        'qr_table_payment_pending',
        'qr_table_unpaid_order',
        'charge_not_claimed_by_device',
        'charge_outcome_uncertain',
        'qr_round_not_found',
        'qr_round_not_pending',
      };

      expect(qrTillServerRefusalCodes, expectedFromServerSource);
      for (final code in expectedFromServerSource) {
        final message = qrTillRefusalMessages[code];
        expect(message, isNotNull, reason: 'Missing refusal copy for $code');
        expect(
          message!.en.trim(),
          isNotEmpty,
          reason: 'Missing English for $code',
        );
        expect(
          message.ar.trim(),
          isNotEmpty,
          reason: 'Missing Arabic for $code',
        );
        expect(qrTillMessageForCode(code), message.en);
        expect(qrTillMessageForCode(code, arabic: true), message.ar);
      }
    },
  );

  test('new round refusals select Arabic copy when requested', () {
    for (final code in const {'qr_round_not_found', 'qr_round_not_pending'}) {
      final copy = qrTillRefusalMessages[code]!;
      expect(qrTillMessageForCode(code), copy.en);
      expect(qrTillMessageForCode(code, arabic: true), copy.ar);
      expect(copy.ar, isNot(copy.en));
    }
  });

  test('local claim-safety codes have bilingual staff instructions', () {
    const localCodes = {
      'qr_payment_attempt_unresolved',
      'qr_settlement_claim_not_held',
      'qr_settlement_claim_expired',
      'qr_settlement_claim_changed',
      'qr_settlement_revalidation_failed',
    };

    for (final code in localCodes) {
      expect(qrTillRefusalMessages[code], isNotNull);
      expect(qrTillMessageForCode(code), isNotEmpty);
      expect(qrTillMessageForCode(code, arabic: true), isNotEmpty);
    }
  });
}
