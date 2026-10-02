import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/order_workspace/current_order_workspace.dart';
import 'package:pos_machine/qr_quick/qr_quick_controller.dart';
import 'package:pos_machine/qr_quick/qr_quick_screen.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'qr_quick_controller_test.dart' show FakeQuickGateway, MemoryQuickStore;
import 'unified_dine_in_test.dart' show TableFake, TableMemory;
import 'workspace_machine_harness.dart';
import 'qr_quick_evidence.dart';
import 'support/fake_order_storage.dart';

void main() {
  const channels = [
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    MethodChannel('pos_machine/rear_display_host'),
    MethodChannel('sunmi_printer_plus'),
  ];
  setUp(() {
    debugOrderStorageOverride = FakeOrderStorage();
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(
      channels[0],
      (call) async => call.method == 'read' ? 'test-token' : null,
    );
    m.setMockMethodCallHandler(
      channels[1],
      (call) async => call.method == 'getPresentationDisplays'
          ? <Map<String, dynamic>>[]
          : true,
    );
    m.setMockMethodCallHandler(channels[2], (_) async => null);
  });
  tearDown(() {
    debugOrderStorageOverride = null;
    for (final c in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, null);
    }
  });
  for (final table in [false, true]) {
    for (final arabic in [false, true]) {
      testWidgets(
        'actual main Current Order ${table ? "table" : "quick"} ${arabic ? "AR" : "EN"} keeps staff cart byte-identical',
        (tester) async {
          tester.view.physicalSize = const Size(1600, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await loadQuickEvidenceFonts(tester);
          const product = Product(
            id: '7',
            name: 'Water',
            nameAr: 'ماء',
            category: 'Drinks',
            price: .2,
            stockMode: 'unit',
            branchStockQty: 1,
          );
          const catalog = CatalogSnapshot(
            categories: ['Drinks'],
            products: [product],
            floors: [],
            tables: [],
            taxes: [],
          );
          await pumpWorkspaceMachine(
            tester,
            mode: 'live',
            toggle: false,
            arabic: arabic,
            catalog: catalog,
          );
          final dynamic state = tester.state(find.byType(StaffPosScreen));
          state.controller.addProduct(product);
          await tester.pumpAndSettle();
          final before = jsonEncode(state.controller.snapshot().toMap());
          final quickApi = FakeQuickGateway();
          final tableApi = TableFake();
          final payments = <String>[];
          late CurrentOrderWorkspace workspace;
          state.openServerWorkspace((CurrentOrderWorkspace w) {
            workspace = w;
            return table
                ? DineInScreen(
                    workspace: w,
                    label: 'T2',
                    arabic: arabic,
                    createController: () async => DineInController(
                      tableApi,
                      TableMemory(),
                      2,
                      staffId: 5,
                    ),
                    catalogue: () => [const QuickProduct(7, 'Water')],
                    onPay: (id) async {
                      payments.add(id);
                    },
                  )
                : QrQuickScreen(
                    workspace: w,
                    workspaceUuid: 'bill-1',
                    arabic: arabic,
                    createController: () async =>
                        QrQuickController(quickApi, MemoryQuickStore()),
                    catalogue: () => [const QuickProduct(7, 'Water')],
                    onPay: (_, order) async {
                      payments.add(order.uuid);
                    },
                  );
          });
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('workspace-current-order')),
            findsOneWidget,
          );
          expect(find.text(arabic ? 'ماء' : 'Water'), findsWidgets);
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('workspace-pay')),
              matching: find.textContaining(
                arabic ? 'المتابعة للدفع' : 'Proceed to pay',
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.text('Void'),
            findsNothing,
          ); // Never target the unrelated staff cart.
          final tileFinder = find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_ProductTile',
          );
          final dynamic tile = tester.widget(tileFinder.first);
          // LAUNCH-P2: no shelf cap at all — the staff cart holding the whole
          // shelf never greys this server bill's tile.
          expect(find.text(arabic ? 'نفدت الكمية' : 'SOLD OUT'), findsNothing);
          tile.onAdd();
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('quick-option-add')));
          await tester.pumpAndSettle();
          expect(workspace.canPay, false);
          final send = find.byKey(
            ValueKey(table ? 'dine-send' : 'quick-submit'),
          );
          await tester.ensureVisible(send);
          await tester.tap(send);
          await tester.pumpAndSettle();
          expect(
            table
                ? tableApi.requests.single.billUuid
                : quickApi.requests.single.orderUuid,
            'bill-1',
          );
          expect(jsonEncode(state.controller.snapshot().toMap()), before);
          await captureQuickEvidence(
            tester,
            'main-${table ? "table" : "quick"}-${arabic ? "ar" : "en"}',
          );
          await tester.tap(find.byKey(const ValueKey('workspace-pay')));
          await tester.pumpAndSettle();
          expect(payments, ['bill-1']);
          await tester.tap(find.byKey(const ValueKey('workspace-return')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('workspace-current-order')),
            findsNothing,
          );
          expect(jsonEncode(state.controller.snapshot().toMap()), before);
          expect(tester.takeException(), null);
          await disposeWorkspaceMachine(tester);
        },
      );
    }
  }
}
