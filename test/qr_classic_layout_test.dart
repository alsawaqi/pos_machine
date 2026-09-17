import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_widgets.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'qr_checkout_fakes.dart';
import 'workspace_machine_harness.dart';
import 'qr_quick_evidence.dart';
import 'support/fake_order_storage.dart';

Finder named(String name) =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == name);

void main() {
  const channels = [
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    MethodChannel('pos_machine/rear_display_host'),
    MethodChannel('sunmi_printer_plus'),
  ];
  setUp(() {
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
  for (final arabic in [false, true]) {
    for (final size in [const Size(1600, 1000), const Size(1280, 800)]) {
      testWidgets(
        'QR retains original payment layout and disables unsupported actions $arabic $size',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await loadQuickEvidenceFonts(tester);
          await pumpWorkspaceMachine(
            tester,
            mode: 'off',
            toggle: false,
            arabic: arabic,
            catalog: const CatalogSnapshot(
              categories: [],
              products: [],
              floors: [],
              tables: [],
              taxes: [],
            ),
          );
          final dynamic state = tester.state(find.byType(StaffPosScreen));
          state.controller.addProduct(
            const Product(
              id: '8',
              name: 'Test Coffee',
              category: 'Drinks',
              price: 2.5,
            ),
          );
          state.controller.setCustomerReferenceNumber(
            'Test Customer · 00000000',
          );
          await tester.pumpAndSettle();
          await tester.tap(named('_PayButton'));
          await tester.pumpAndSettle();
          final l10n = L10n.of(tester.element(find.byType(StaffPosScreen)));
          final actionTitles = [
            l10n.posPaymentTransfer,
            l10n.posPaymentAddDiscount,
            l10n.posPaymentSplitBill,
          ];
          final cardRects = [
            for (final title in actionTitles)
              tester.getRect(
                find.ancestor(
                  of: find.text(title),
                  matching: named('_PaymentTopActionCard'),
                ),
              ),
          ];
          final keypad = tester.getRect(named('_PaymentKeyButton').first);
          final customerSize = tester.getSize(
            find.byKey(const ValueKey('payment-customer-number')),
          );
          final plateSize = tester.getSize(
            find.byKey(const ValueKey('payment-vehicle-plate')),
          );
          final headerRect = tester.getRect(find.text(l10n.posPaymentTitle));
          final profileRect = tester.getRect(
            find.textContaining('Test Cashier', findRichText: true),
          );
          expect(named('_BackgroundScene'), findsOneWidget);
          for (final title in actionTitles) {
            final ink = find.descendant(
              of: find.ancestor(
                of: find.text(title),
                matching: named('_PaymentTopActionCard'),
              ),
              matching: find.byType(InkWell),
            );
            expect(tester.widget<InkWell>(ink).onTap, isNotNull);
          }
          await captureQuickEvidence(
            tester,
            'classic-local-payment-${arabic ? 'ar' : 'en'}-${size.width.toInt()}',
          );
          final original = jsonEncode(state.controller.snapshot().toMap());
          final f = CheckoutFixture();
          final c = f.controller();
          await c.open('qr-bill');
          // Use the production boundary and production payment builder. Its
          // layout must match the actual local page just measured above.
          Navigator.of(tester.element(find.byType(StaffPosScreen))).push<void>(
            MaterialPageRoute(
              builder: (_) => QrCheckoutBoundary(
                controller: c,
                authorizeManager: () async => false,
                paymentPage: (_, exit) =>
                    state.buildQrPaymentPage(c, exit) as Widget,
                statusPage: (_, exit, status) =>
                    state.buildQrPaymentStatus(c, exit, status) as Widget,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(named('_BackgroundScene'), findsOneWidget);
          expect(tester.getRect(find.text(l10n.posPaymentTitle)), headerRect);
          expect(
            tester.getRect(
              find.textContaining('Test Cashier', findRichText: true),
            ),
            profileRect,
          );
          for (var i = 0; i < actionTitles.length; i++) {
            final card = find.ancestor(
              of: find.text(actionTitles[i]),
              matching: named('_PaymentTopActionCard'),
            );
            expect(tester.getRect(card), cardRects[i]);
            expect(
              tester
                  .widget<InkWell>(
                    find.descendant(of: card, matching: find.byType(InkWell)),
                  )
                  .onTap,
              isNull,
            );
            await tester.tap(card);
            await tester.pumpAndSettle();
            expect(find.byType(Dialog), findsNothing);
          }
          expect(tester.getRect(named('_PaymentKeyButton').first), keypad);
          expect(
            tester.getSize(
              find.byKey(const ValueKey('payment-customer-number')),
            ),
            customerSize,
          );
          expect(
            tester.getSize(find.byKey(const ValueKey('payment-vehicle-plate'))),
            plateSize,
          );
          for (final key in [
            'payment-customer-number',
            'payment-vehicle-plate',
            'payment-customer-details',
            'payment-plate-search',
          ]) {
            expect(
              tester.widget<InkWell>(find.byKey(ValueKey(key))).onTap,
              isNull,
            );
          }
          expect(find.text('Test Customer · 00000000'), findsOneWidget);
          expect(
            find.text(
              checkoutText(
                tester.element(find.byType(QrCheckoutBoundary)),
                'frozen',
              ),
            ),
            findsNothing,
          );
          expect(jsonEncode(state.controller.snapshot().toMap()), original);
          expect(f.api.pushes, isEmpty);
          expect(f.cards, 0);
          expect(f.banks, 0);
          f.api.loseAck = true;
          await tester.tap(find.text(l10n.posPaymentBankPos));
          await tester.pumpAndSettle();
          expect(named('_BackgroundScene'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('qr-checkout-retry')),
            findsOneWidget,
          );
          expect(f.banks, 1);
          expect(f.api.pushes, hasLength(1));
          final pendingEvent = jsonEncode(f.api.pushes.single);
          f.api.loseAck = false;
          await tester.tap(find.byKey(const ValueKey('qr-checkout-retry')));
          await tester.pumpAndSettle();
          expect(f.api.pushes.map(jsonEncode), [pendingEvent, pendingEvent]);
          expect(f.api.commits, 1);
          expect(f.banks, 1);
          expect(jsonEncode(state.controller.snapshot().toMap()), original);
          expect(tester.takeException(), null);
          await disposeWorkspaceMachine(tester);
          c.dispose();
        },
      );
    }
  }
}
