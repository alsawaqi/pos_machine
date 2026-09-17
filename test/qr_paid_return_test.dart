import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/order_workspace/current_order_workspace.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_widgets.dart';
import 'package:pos_machine/qr_quick/qr_quick_controller.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'package:pos_machine/qr_quick/qr_quick_screen.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'qr_checkout_fakes.dart';
import 'qr_quick_controller_test.dart';
import 'qr_quick_evidence.dart';
import 'support/fake_order_storage.dart';
import 'workspace_machine_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    debugOrderStorageOverride = FakeOrderStorage();
    for (final name in [
      'plugins.it_nomads.com/flutter_secure_storage',
      'pos_machine/rear_display_host',
      'sunmi_printer_plus',
    ]) {
      final channel = MethodChannel(name);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'read'
            ? 'test-token'
            : call.method == 'getPresentationDisplays'
            ? <Map<String, dynamic>>[]
            : null,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }
  });
  tearDown(() => debugOrderStorageOverride = null);

  for (final scenario in [
    'paid',
    'paid-back-ar',
    'cancel',
    'pending',
    'other-bill',
  ]) {
    testWidgets('QR checkout returns safely: $scenario', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await loadQuickEvidenceFonts(tester);
      const water = Product(
        id: '7',
        name: 'Water',
        category: 'Drinks',
        price: 1,
      );
      await pumpWorkspaceMachine(
        tester,
        mode: 'live',
        toggle: false,
        arabic: scenario == 'paid-back-ar',
        catalog: const CatalogSnapshot(
          categories: ['Drinks'],
          products: [water],
          floors: [],
          tables: [],
          taxes: [],
        ),
      );
      final dynamic staff = tester.state(find.byType(StaffPosScreen));
      await staff.controller.selectOrderType(OrderType.toGo);
      staff.controller.addProduct(water);
      await tester.pumpAndSettle();
      final localItems = jsonEncode(
        staff.controller.snapshot().toMap()['items'],
      );
      final gateway = FakeQuickGateway()
        ..orders = [
          QrQuickOrder(
            quickJson(
              uuid: scenario == 'other-bill' ? 'other-bill' : 'qr-bill',
            ),
          ),
        ];
      late CurrentOrderWorkspace workspace;
      staff.openServerWorkspace((CurrentOrderWorkspace w) {
        workspace = w;
        return QrQuickScreen(
          workspace: w,
          workspaceUuid: gateway.orders.single.uuid,
          createController: () async =>
              QrQuickController(gateway, MemoryQuickStore()),
          catalogue: () => [],
          onPay: (_, order) async {},
        );
      }, quick: true);
      await tester.pumpAndSettle();
      final fixture = CheckoutFixture();
      final payment = fixture.controller();
      await payment.open('qr-bill');
      final Future<void> route = staff.showQrCheckout(payment);
      await tester.pumpAndSettle();
      if (scenario == 'cancel') {
        await payment.cancel();
      } else {
        fixture.api.loseAck = scenario == 'pending';
        await payment.pay([const CheckoutTender('cash', 4750)]);
      }
      await tester.pumpAndSettle();
      if (scenario == 'pending') {
        expect(payment.phase, CheckoutPhase.pending);
        expect(payment.canLeave, false);
        expect(find.byType(QrCheckoutBoundary), findsOneWidget);
        expect(workspace.bill!.uuid, 'qr-bill');
        expect(fixture.store.value!.event, isNotNull);
        fixture.api.loseAck = false;
        await payment.retryAcknowledgement();
        await tester.pumpAndSettle();
      }
      if (scenario == 'paid-back-ar') {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.byKey(const ValueKey('qr-checkout-exit')));
      }
      await tester.pumpAndSettle();
      await route;
      expect(find.byType(QrCheckoutBoundary), findsNothing);
      if (scenario == 'cancel' || scenario == 'other-bill') {
        expect(find.byType(QrQuickScreen), findsOneWidget);
        expect(workspace.canAdd, true);
        expect(staff.controller.selectedOrderType, OrderType.toGo);
      } else {
        expect(find.byType(QrQuickScreen), findsNothing);
        expect(staff.controller.selectedOrderType, OrderType.quickOrder);
        expect(
          jsonEncode(staff.controller.snapshot().toMap()['items']),
          localItems,
        );
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_ProductTile',
          ),
        );
        await tester.pumpAndSettle();
        expect(staff.controller.cart.single.qty, 2);
        expect(gateway.requests, isEmpty);
      }
      expect(fixture.api.commits, scenario == 'cancel' ? 0 : 1);
      expect(tester.takeException(), isNull);
      await disposeWorkspaceMachine(tester);
      payment.dispose();
    });
  }
}
