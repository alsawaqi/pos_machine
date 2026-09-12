import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_widgets.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'qr_checkout_fakes.dart';
import 'staff_table_checkout_test.dart'
    show StaffCheckoutGateway, staffController;
import 'qr_checkout_machine_harness.dart';
import 'qr_quick_evidence.dart';
import 'support/fake_order_storage.dart';

void main() {
  const channels = [
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    MethodChannel('pos_machine/rear_display_host'),
    MethodChannel('sunmi_printer_plus'),
  ];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugOrderStorageOverride = FakeOrderStorage();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channels[0],
      (call) async => call.method == 'read' ? 'test-token' : null,
    );
    messenger.setMockMethodCallHandler(
      channels[1],
      (call) async => call.method == 'getPresentationDisplays'
          ? <Map<String, dynamic>>[]
          : true,
    );
    messenger.setMockMethodCallHandler(channels[2], (_) async => null);
  });
  tearDown(() {
    debugOrderStorageOverride = null;
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
  for (final source in ['main_pos', 'handheld']) {
    testWidgets(
      '$source uses the normal till payment page without cart mutation',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpCheckoutMachine(
          tester,
          mode: 'off',
          toggle: false,
          arabic: false,
        );
        final dynamic state = tester.state(find.byType(StaffPosScreen));
        final before = jsonEncode(state.controller.snapshot().toMap());
        final api = StaffCheckoutGateway(source);
        final c = staffController(api, MemoryCheckoutStore());
        await c.open('qr-bill');
        final context = tester.element(find.byType(StaffPosScreen));
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => QrCheckoutBoundary(
              controller: c,
              authorizeManager: () async => false,
              paymentPage: (_, exit) =>
                  state.buildQrPaymentPage(c, exit) as Widget,
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final label in ['Cash', 'Card', 'Bank POS', 'Gift']) {
          expect(find.text(label), findsOneWidget);
        }
        expect(c.snapshot!.order['source'], source);
        expect(find.text('Test Customer · 00000000'), findsOneWidget);
        await tester.tap(find.text('Bank POS'));
        await tester.pumpAndSettle();
        expect(c.phase, CheckoutPhase.paid);
        expect(api.pushes, hasLength(1));
        expect(api.pushes.single['event_type'], 'order.pay');
        expect(jsonEncode(state.controller.snapshot().toMap()), before);
        expect(tester.takeException(), null);
        await disposeCheckoutMachine(tester);
        c.dispose();
      },
    );
  }
  for (final arabic in [false, true]) {
    for (final method in ['cash', 'card', 'bank_pos', 'gift']) {
      testWidgets(
        'normal till payment $method ${arabic ? 'AR' : 'EN'} keeps cart snapshot byte-identical',
        (tester) async {
          tester.view.physicalSize = const Size(1600, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await loadQuickEvidenceFonts(tester);
          await pumpCheckoutMachine(
            tester,
            mode: 'off',
            toggle: false,
            arabic: arabic,
          );
          final dynamic state = tester.state(find.byType(StaffPosScreen));
          final before = jsonEncode(state.controller.snapshot().toMap());
          final f = CheckoutFixture();
          final c = f.controller();
          await c.open('qr-bill');
          c.cashAmount(5000);
          final context = tester.element(find.byType(StaffPosScreen));
          Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => RepaintBoundary(
                key: quickEvidenceKey,
                child: QrCheckoutBoundary(
                  controller: c,
                  authorizeManager: () async => false,
                  paymentPage: (_, exit) =>
                      state.buildQrPaymentPage(c, exit) as Widget,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('qr-checkout-customer')),
            findsOneWidget,
          );
          expect(find.text('Test Customer · 00000000'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('qr-checkout-total')),
            findsOneWidget,
          );
          expect(find.textContaining('Test Coffee'), findsOneWidget);
          if (method == 'cash') {
            await captureQuickEvidence(
              tester,
              'qr-checkout-machine-${arabic ? 'ar' : 'en'}',
            );
          }
          final label = {
            'cash': arabic ? 'نقدًا' : 'Cash',
            'card': arabic ? 'بطاقة' : 'Card',
            'bank_pos': arabic ? 'جهاز البنك' : 'Bank POS',
            'gift': arabic ? 'هدية' : 'Gift',
          }[method]!;
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(c.phase, CheckoutPhase.paid);
          expect(f.api.pushes, hasLength(1));
          expect(jsonEncode(state.controller.snapshot().toMap()), before);
          expect(tester.takeException(), isNull);
          await disposeCheckoutMachine(tester);
          c.dispose();
        },
      );
    }
  }
}
