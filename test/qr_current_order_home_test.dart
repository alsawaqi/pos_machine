import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/screens/customer_display_screen.dart';
import 'package:pos_machine/order_workspace/server_workspace_display.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_widgets.dart';
import 'qr_checkout_fakes.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/order_workspace/current_order_workspace.dart';
import 'package:pos_machine/qr_quick/qr_quick_controller.dart';
import 'package:pos_machine/qr_quick/qr_quick_screen.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'qr_quick_controller_test.dart' show FakeQuickGateway, MemoryQuickStore;
import 'workspace_machine_harness.dart';
import 'qr_quick_evidence.dart';
import 'support/fake_order_storage.dart';

void main() {
  const channels = [
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    MethodChannel('pos_machine/rear_display_host'),
    MethodChannel('sunmi_printer_plus'),
  ];
  final displayed = <Map>[];
  setUp(() {
    displayed.clear();
    debugOrderStorageOverride = FakeOrderStorage();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channels[0],
      (call) async => call.method == 'read' ? 'test-token' : null,
    );
    messenger.setMockMethodCallHandler(channels[1], (call) async {
      if (call.method == 'transferDataToRear') {
        displayed.add(call.arguments as Map);
      }
      return call.method == 'getPresentationDisplays'
          ? <Map<String, dynamic>>[]
          : true;
    });
    messenger.setMockMethodCallHandler(channels[2], (_) async => null);
  });
  tearDown(() {
    debugOrderStorageOverride = null;
    for (final c in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, null);
    }
  });
  for (final arabic in [false, true]) {
    testWidgets(
      'QR quick opens the normal cart, pay button and customer display ${arabic ? "AR" : "EN"}',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await loadQuickEvidenceFonts(tester);
        const water = Product(
          id: '7',
          name: 'Water',
          nameAr: 'ماء',
          category: 'Drinks',
          price: 99,
        );
        await pumpWorkspaceMachine(
          tester,
          mode: 'live',
          toggle: false,
          arabic: arabic,
          catalog: const CatalogSnapshot(
            categories: ['Drinks'],
            products: [water],
            floors: [],
            tables: [],
            taxes: [],
          ),
        );
        final dynamic state = tester.state(find.byType(StaffPosScreen));
        state.controller.addProduct(water);
        await tester.pumpAndSettle();
        final original = jsonEncode(state.controller.snapshot().toMap());
        final originalItemRect = tester.getRect(
          find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_OrderItemCard',
          ),
        );
        final originalPayRect = tester.getRect(
          find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_PayButton',
          ),
        );
        await captureQuickEvidence(
          tester,
          'classic-local-cart-${arabic ? 'ar' : 'en'}',
        );
        final gateway = FakeQuickGateway();
        final store = MemoryQuickStore();
        final paid = <String>[];
        late CurrentOrderWorkspace workspace;
        state.openServerWorkspace((CurrentOrderWorkspace w) {
          workspace = w;
          return QrQuickScreen(
            workspace: w,
            workspaceUuid: 'bill-1',
            arabic: arabic,
            createController: () async => QrQuickController(gateway, store),
            catalogue: () => [const QuickProduct(7, 'Water')],
            onPay: (_, order) async {
              paid.add(order.uuid);
            },
          );
        }, quick: true);
        await tester.pumpAndSettle();
        final itemCard = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_OrderItemCard',
        );
        final payButton = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_PayButton',
        );
        expect(itemCard, findsOneWidget);
        expect(payButton, findsOneWidget);
        expect(tester.getRect(itemCard), originalItemRect);
        expect(tester.getRect(payButton), originalPayRect);
        final l10n = L10n.of(tester.element(itemCard));
        expect(find.text(l10n.posOrderPanelClear), findsOneWidget);
        expect(find.text(l10n.posCartAddOn), findsOneWidget);
        expect(find.text(l10n.posCartGift), findsOneWidget);
        expect(find.byKey(const ValueKey('workspace-refresh')), findsNothing);
        for (final icon in [
          Icons.delete_outline_rounded,
          Icons.add_circle_outline_rounded,
        ]) {
          final target = find.descendant(
            of: itemCard,
            matching: find.byIcon(icon),
          );
          final action = find
              .ancestor(of: target, matching: find.byType(InkWell))
              .first;
          expect(tester.widget<InkWell>(action).onTap, isNull);
        }
        expect(find.byKey(const ValueKey('quick-pay')), findsNothing);
        expect(find.byKey(const ValueKey('quick-add-items')), findsNothing);
        expect(find.textContaining('Q-007'), findsWidgets);
        await captureQuickEvidence(
          tester,
          'normal-qr-cart-${arabic ? 'ar' : 'en'}',
        );
        expect(workspace.bill!.total, 1000);
        expect(displayed.last['type'], 'order_snapshot');
        expect(displayed.last['total'], 1.0);
        expect((displayed.last['items'] as List).single['name'], 'Coffee');
        expect(jsonEncode(displayed.last), isNot(contains('bill-1')));
        expect(jsonEncode(state.controller.snapshot().toMap()), original);
        await tester.tap(payButton);
        await tester.pumpAndSettle();
        expect(paid, ['bill-1']);
        expect(gateway.requests, isEmpty);
        // Stale data cannot reach the checkout through the normal pay button.
        gateway.failFetch = true;
        // Simulate the controller's next server refresh. Healthy carts have no
        // extra toolbar; a failed refresh exposes the existing recovery action.
        await workspace.cartControls!.refresh!();
        await tester.pumpAndSettle();
        expect(workspace.canPay, false);
        await tester.tap(payButton);
        await tester.pumpAndSettle();
        expect(paid, ['bill-1']);
        gateway.failFetch = false;
        await tester.tap(find.byKey(const ValueKey('workspace-refresh')));
        await tester.pumpAndSettle();
        expect(workspace.canPay, true);

        // A catalogue addition goes to the original bill; a lost acknowledgement
        // exposes retry on the home cart and never creates another request.
        gateway.lostResponse = true;
        final product = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_ProductTile',
        );
        await tester.tap(product);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('quick-option-add')), findsNothing);
        await tester.pumpAndSettle();
        expect(gateway.requests, hasLength(1));
        expect(gateway.requests.single.orderUuid, 'bill-1');
        expect(gateway.requests.single.lines.single.productId, 7);
        final pendingPayload = jsonEncode(gateway.requests.single.payload);
        expect(store.data, hasLength(1));
        expect(workspace.canPay, false);
        await tester.tap(payButton);
        await tester.pumpAndSettle();
        expect(paid, ['bill-1']);
        gateway.lostResponse = false;
        await tester.tap(find.byKey(const ValueKey('workspace-retry')));
        await tester.pumpAndSettle();
        expect(gateway.requests.map((r) => jsonEncode(r.payload)), [
          pendingPayload,
          pendingPayload,
        ]);
        expect(gateway.mutations, 1);
        expect(store.data, isEmpty);
        expect(workspace.bill!.total, 1200);
        expect(workspace.canPay, true);
        expect(displayed.last['total'], 1.2);
        expect(jsonEncode(state.controller.snapshot().toMap()), original);
        expect(tester.takeException(), null);
        final rearPayload = Map<String, dynamic>.from(displayed.last);
        await disposeWorkspaceMachine(tester);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'QuickEvidence'),
            locale: Locale(arabic ? 'ar' : 'en'),
            supportedLocales: L10n.supportedLocales,
            localizationsDelegates: L10n.localizationsDelegates,
            home: RepaintBoundary(
              key: quickEvidenceKey,
              child: const CustomerDisplayScreen(),
            ),
          ),
        );
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'pos_machine/rear_display_channel',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('updateOrder', rearPayload),
          ),
          (_) {},
        );
        await tester.pumpAndSettle();
        expect(find.byType(ServerWorkspaceDisplay), findsNothing);
        expect(
          find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_DisplayItemCard',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Coffee'), findsWidgets);
        await captureQuickEvidence(
          tester,
          'normal-qr-customer-${arabic ? 'ar' : 'en'}',
        );
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'QR checkout reuses the normal payment item cards and server totals',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpWorkspaceMachine(
        tester,
        mode: 'off',
        toggle: false,
        arabic: false,
        catalog: const CatalogSnapshot(
          categories: [],
          products: [],
          floors: [],
          tables: [],
          taxes: [],
        ),
      );
      final dynamic state = tester.state(find.byType(StaffPosScreen));
      final original = jsonEncode(state.controller.snapshot().toMap());
      final fixture = CheckoutFixture();
      final payment = fixture.controller();
      await payment.open('qr-bill');
      Navigator.of(tester.element(find.byType(StaffPosScreen))).push<void>(
        MaterialPageRoute(
          builder: (_) => QrCheckoutBoundary(
            controller: payment,
            authorizeManager: () async => false,
            paymentPage: (_, exit) =>
                state.buildQrPaymentPage(payment, exit) as Widget,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_PaymentOrderItemCard',
        ),
        findsOneWidget,
      );
      final total = tester.widget<Text>(
        find.byKey(const ValueKey('qr-checkout-total')),
      );
      expect(total.data, contains('4.750'));
      expect(find.textContaining('No sugar'), findsWidgets);
      expect(jsonEncode(state.controller.snapshot().toMap()), original);
      expect(fixture.api.pushes, isEmpty);
      expect(tester.takeException(), null);
      await disposeWorkspaceMachine(tester);
      payment.dispose();
    },
  );
}
