import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';

import 'qr_checkout_fakes.dart';

/// LAUNCH-P5 C3 — a QR order paid as a gift: its `gift` block rides on the
/// order.pay that carries the payments, as `tender:<index>` with the tender
/// amount (Part A §6), and the saved pending event still decodes.
void main() {
  test('a gift tender carries its block on order.pay', () async {
    final f = CheckoutFixture();
    final calls = <(String, int, int)>[];
    final c = QrCheckoutController(
      gateway: f.api,
      store: f.store,
      now: () => f.now,
      newId: () => 'payment-attempt-1',
      authorizeGift: () async => true,
      captureCard: (amount) async =>
          const CheckoutCapture(CheckoutCaptureState.approved),
      captureBank: (amount) async =>
          const CheckoutCapture(CheckoutCaptureState.approved),
      staffId: () => 7,
      giftAuthorization: (uuid, index, amount) {
        calls.add((uuid, index, amount));
        return {
          'action': 'gift',
          'ref': 'tender:$index',
          'mode': 'position',
          'actor_staff_id': 7,
        };
      },
    );
    addTearDown(c.dispose);
    await c.open('qr-bill');
    await c.pay([const CheckoutTender('gift', 4750)]);
    expect(c.phase, CheckoutPhase.paid);
    final payload = f.api.pushes.single['payload'] as Map;
    expect(calls, [('qr-bill', 0, 4750)]);
    expect(payload['authorizations'], [
      {
        'action': 'gift',
        'ref': 'tender:0',
        'mode': 'position',
        'actor_staff_id': 7,
      },
    ]);
    expect(payload['staff_id'], 7);
    expect(payload['auth_v'], 1);
    // The saved attempt (with the block) still decodes.
    expect(
      CheckoutAttempt.decode(jsonEncode(f.store.value!.json)).event,
      isNotNull,
    );
  });
}
