import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_widgets.dart';
import 'qr_checkout_fakes.dart';

void main() {
  testWidgets(
    'lost cash ACK is explicitly provisional until server receipt arrives',
    (tester) async {
      final f = CheckoutFixture();
      final c = f.controller();
      await c.open('qr-bill');
      f.api.loseAck = true;
      await c.pay([const CheckoutTender('cash', 4750)]);
      await tester.pumpWidget(
        MaterialApp(
          home: QrCheckoutBoundary(
            controller: c,
            authorizeManager: () async => false,
            paymentPage: (_, _) => const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('PAYMENT PENDING — NOT A FINAL RECEIPT'),
        findsOneWidget,
      );
      expect(find.textContaining('R-009'), findsNothing);
      f.api.loseAck = false;
      await c.retryAcknowledgement();
      await tester.pumpAndSettle();
      expect(find.text('PAYMENT PENDING — NOT A FINAL RECEIPT'), findsNothing);
      expect(find.textContaining('R-009'), findsOneWidget);
      expect(f.api.commits, 1);
      expect(f.api.pushes[0], f.api.pushes[1]);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
