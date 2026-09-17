import 'dart:convert';
import 'empty_table_session_test.dart' show EmptyGateway;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'package:pos_machine/order_workspace/current_order_workspace.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'support/fake_order_storage.dart';
import 'workspace_machine_harness.dart';
import 'qr_quick_evidence.dart';
import 'unified_dine_in_test.dart' show TableFake, TableMemory, tableFixture;

void main() {
  const channels = [
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    MethodChannel('pos_machine/rear_display_host'),
    MethodChannel('sunmi_printer_plus'),
  ];
  setUp(() {
    debugOrderStorageOverride = FakeOrderStorage();
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'read') return 'test-token';
            if (call.method == 'getPresentationDisplays') {
              return <Map<String, dynamic>>[];
            }
            return null;
          });
    }
  });
  tearDown(() {
    debugOrderStorageOverride = null;
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  testWidgets('normal machine cart exposes clear empty session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpWorkspaceMachine(
      tester,
      mode: 'live',
      toggle: false,
      catalog: const CatalogSnapshot(
        categories: [],
        products: [],
        floors: [],
        tables: [],
        taxes: [],
      ),
    );
    final dynamic state = tester.state(find.byType(StaffPosScreen));
    final gateway = EmptyGateway();
    late CurrentOrderWorkspace workspace;
    state.openServerWorkspace((CurrentOrderWorkspace w) {
      workspace = w;
      return DineInScreen(
        workspace: w,
        label: 'T1',
        createController: () async =>
            DineInController(gateway, TableMemory(), 1),
        catalogue: () => [],
        onPay: (_) async {},
      );
    }, tableLabel: 'T1');
    await tester.pumpAndSettle();
    expect(
      workspace.cartControls!.actions.map((a) => a.label),
      contains('Clear empty session'),
    );
    expect(find.text('Clear empty session'), findsOneWidget);
    await tester.tap(find.text('Clear empty session'));
    await tester.pumpAndSettle();
    expect(gateway.clearedUuid, isNull);
    await tester.tap(find.byKey(const ValueKey('dine-clear-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.clearedUuid, isNotNull);
    expect(find.byKey(const ValueKey('dine-in-cart-controller')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'pending customer round appears in normal cart without becoming payable',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpWorkspaceMachine(
        tester,
        mode: 'live',
        toggle: false,
        catalog: const CatalogSnapshot(
          categories: [],
          products: [],
          floors: [],
          tables: [],
          taxes: [],
        ),
      );
      final dynamic state = tester.state(find.byType(StaffPosScreen));
      final gateway = TableFake()..value = tableFixture(pending: true);
      gateway.value['bill']['items'] = [];
      gateway.value['bill']['grand_total_baisas'] = 0;
      gateway.value['rounds'][1]['tax_baisas'] = 25;
      late CurrentOrderWorkspace workspace;
      state.openServerWorkspace((CurrentOrderWorkspace w) {
        workspace = w;
        return DineInScreen(
          workspace: w,
          label: 'T2',
          createController: () async =>
              DineInController(gateway, TableMemory(), 2),
          catalogue: () => [],
          onPay: (_) async {},
        );
      }, tableLabel: 'T2');
      await tester.pumpAndSettle();
      expect(find.text('WATER'), findsOneWidget);
      expect(find.textContaining('Awaiting confirmation'), findsWidgets);
      expect(workspace.bill!.items, isEmpty);
      expect(workspace.bill!.total, 0);
      expect(workspace.cartBill!.total, 525);
      expect(workspace.cartBill!.items.single['pending_round_id'], 8);
      expect(workspace.canPay, isFalse);
      expect(gateway.calls.where((c) => c.startsWith('review:')), isEmpty);
      await workspace.cartControls!.quantity!(
        workspace.cartBill!.items.single,
        0,
      );
      expect(gateway.requests, isEmpty);
      // A later confirmation refresh replaces the preview with real bill lines.
      gateway.value['rounds'][1]['status'] = 'accepted';
      gateway.value['bill']['items'] = [
        {
          'id': 100,
          'product_name': 'Water',
          'qty': 1,
          'line_total_baisas': 500,
        },
      ];
      gateway.value['bill']['grand_total_baisas'] = 525;
      await workspace.cartControls!.refresh!();
      await tester.pumpAndSettle();
      expect(
        workspace.cartBill!.items.where(
          (row) => row['pending_round_id'] != null,
        ),
        isEmpty,
      );
      expect(workspace.cartBill!.items, hasLength(1));
      expect(workspace.cartBill!.total, 525);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final arabic in [false, true]) {
    testWidgets(
      'QR dine-in uses the normal cart and kitchen button ${arabic ? "AR" : "EN"}',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await loadQuickEvidenceFonts(tester);
        const product = Product(
          id: '8',
          name: 'Coffee',
          nameAr: 'قهوة',
          category: 'Drinks',
          price: 1,
        );
        await pumpWorkspaceMachine(
          tester,
          mode: 'live',
          toggle: false,
          arabic: arabic,
          catalog: const CatalogSnapshot(
            categories: ['Drinks'],
            products: [product],
            floors: [],
            tables: [],
            taxes: [],
          ),
        );
        final dynamic state = tester.state(find.byType(StaffPosScreen));
        final original = jsonEncode(state.controller.snapshot().toMap());
        final gateway = TableFake();
        late CurrentOrderWorkspace workspace;
        state.openServerWorkspace((CurrentOrderWorkspace w) {
          workspace = w;
          return DineInScreen(
            workspace: w,
            label: 'T2',
            arabic: arabic,
            createController: () async =>
                DineInController(gateway, TableMemory(), 2),
            catalogue: () => [
              const QuickProduct(8, 'Coffee', priceBaisas: 1000),
            ],
            onPay: (_) async {},
          );
        }, tableLabel: 'T2');
        await tester.pumpAndSettle();
        final cards = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_OrderItemCard',
        );
        final pay = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_PayButton',
        );
        expect(cards, findsOneWidget);
        expect(pay, findsOneWidget);
        final l10n = L10n.of(tester.element(pay));
        expect(find.text(l10n.tableSendToKitchen), findsOneWidget);
        expect(find.byKey(const ValueKey('unified-dine-in')), findsNothing);
        await workspace.pick(
          const QuickProduct(8, 'Coffee', priceBaisas: 1000),
        );
        await workspace.pick(
          const QuickProduct(8, 'Coffee', priceBaisas: 1000),
        );
        await tester.pumpAndSettle();
        expect(workspace.cartControls!.draftRows.single['qty'], 2);
        expect(cards, findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await captureQuickEvidence(
          tester,
          'dine-in-normal-cart-${arabic ? 'ar' : 'en'}',
        );
        await tester.tap(find.text(l10n.tableSendToKitchen));
        await tester.pumpAndSettle();
        expect(gateway.requests, hasLength(1));
        expect(jsonEncode(state.controller.snapshot().toMap()), original);
        workspace.onExit();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('dine-in-cart-controller')),
          findsNothing,
        );
        expect(jsonEncode(state.controller.snapshot().toMap()), original);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
