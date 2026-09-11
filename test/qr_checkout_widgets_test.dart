import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_widgets.dart';
import 'package:pos_machine/qr_quick/qr_quick_controller.dart';
import 'package:pos_machine/qr_quick/qr_quick_screen.dart';
import 'qr_checkout_fakes.dart';
import 'qr_quick_controller_test.dart' show FakeQuickGateway, MemoryQuickStore;

void main() {
  testWidgets('empty inbox still offers durable payment recovery', (
    tester,
  ) async {
    var opened = 0;
    final api = FakeQuickGateway()..orders = [];
    await tester.pumpWidget(
      MaterialApp(
        home: QrQuickScreen(
          createController: () async =>
              QrQuickController(api, MemoryQuickStore()),
          catalogue: () => [],
          onRecoverPayment: () async {
            opened++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-payment-recovery')));
    await tester.pumpAndSettle();
    expect(opened, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'boundary hosts normal page, cancelled exit releases before popping',
    (tester) async {
      final f = CheckoutFixture();
      final c = f.controller();
      await c.open('qr-bill');
      late BuildContext root;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              root = context;
              return const Text('inbox');
            },
          ),
        ),
      );
      Navigator.of(root).push<void>(
        MaterialPageRoute(
          builder: (_) => QrCheckoutBoundary(
            controller: c,
            authorizeManager: () async => false,
            paymentPage: (_, exit) => Scaffold(
              body: TextButton(
                onPressed: exit,
                child: const Text('NORMAL PAYMENT'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('NORMAL PAYMENT'), findsOneWidget);
      await tester.tap(find.text('NORMAL PAYMENT'));
      await tester.pumpAndSettle();
      expect(f.api.releases.single['outcome'], 'cancelled');
      expect(find.text('inbox'), findsOneWidget);
      c.dispose();
    },
  );
  testWidgets('pending boundary blocks back and only retries immutable pay', (
    tester,
  ) async {
    final f = CheckoutFixture();
    final c = f.controller();
    await c.open('qr-bill');
    f.api.loseAck = true;
    await c.pay([const CheckoutTender('card', 4750)]);
    late BuildContext root;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            root = context;
            return const Text('inbox');
          },
        ),
      ),
    );
    Navigator.of(root).push<void>(
      MaterialPageRoute(
        builder: (_) => QrCheckoutBoundary(
          controller: c,
          authorizeManager: () async => false,
          paymentPage: (_, _) => const Text('must not render'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await Navigator.of(root).maybePop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qr-checkout-retry')), findsOneWidget);
    f.api.loseAck = false;
    await tester.tap(find.byKey(const ValueKey('qr-checkout-retry')));
    await tester.pumpAndSettle();
    expect(c.phase, CheckoutPhase.paid);
    expect(f.cards, 1);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets(
    'Bank POS confirmation offers explicit unknown, never silently approves',
    (tester) async {
      CheckoutCapture? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await confirmCheckoutBank(context, 4750);
                },
                child: const Text('bank'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('bank'));
      await tester.pumpAndSettle();
      expect(find.textContaining('4.750'), findsOneWidget);
      expect(result, isNull);
      await tester.tap(find.text('Result unknown'));
      await tester.pumpAndSettle();
      expect(result!.state, CheckoutCaptureState.uncertain);
    },
  );
  testWidgets(
    'split validates precision and exact remainder with no tender before confirm',
    (tester) async {
      List<CheckoutTender>? plan;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  plan = await checkoutMixedPlan(context, 4750);
                },
                child: const Text('split'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('split'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('qr-split-cash')),
        '2.0001',
      );
      await tester.tap(find.text('Proceed'));
      await tester.pumpAndSettle();
      expect(plan, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('qr-split-cash')),
        '2.000',
      );
      await tester.tap(find.text('Proceed'));
      await tester.pumpAndSettle();
      expect(plan!.map((v) => v.amount), [2000, 2750]);
      expect(tester.takeException(), isNull);
    },
  );
}
