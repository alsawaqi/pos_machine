import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'qr_checkout_fakes.dart';

void main() {
  test(
    'BUSY refuses this QR tender without recording or uncertainty',
    () async {
      final gateway = CheckoutFakeGateway();
      final store = MemoryCheckoutStore();
      var calls = 0;
      final controller = QrCheckoutController(
        gateway: gateway,
        store: store,
        now: () => checkoutTime,
        newId: () => 'busy-attempt',
        authorizeGift: () async => false,
        captureBank: (_) async => throw StateError('Unexpected bank tender'),
        captureCard: (_) async {
          calls++;
          return const CheckoutCapture(
            CheckoutCaptureState.cancelled,
            evidence: {
              'bank_response': {'code': 'BUSY', 'status': 'failed'},
            },
          );
        },
      );
      addTearDown(controller.dispose);
      await controller.open('qr-bill');
      await controller.pay([const CheckoutTender('card', 4750)]);
      expect(calls, 1);
      expect(controller.phase, CheckoutPhase.released);
      expect(controller.notice, 'terminal_busy');
      expect(gateway.pushes, isEmpty);
      expect(gateway.releases.single['outcome'], 'cancelled');
      expect(gateway.releases.single['captures'], isEmpty);
      expect(store.value!.state, 'released');
      expect(store.value!.event, isNull);
      expect(store.history.any((row) => row.state == 'uncertain'), isFalse);
    },
  );
}
