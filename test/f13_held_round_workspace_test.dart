import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'package:pos_machine/order_workspace/current_order_workspace.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'workspace_machine_harness.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'unified_dine_in_test.dart' show TableFake, TableMemory, tableFixture;
import 'support/fake_order_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final mixed in [false, true]) {
    testWidgets(
      'F13 adopted bill renders held staff line${mixed ? " with customer round" : ""}',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        debugOrderStorageOverride = FakeOrderStorage();
        addTearDown(() => debugOrderStorageOverride = null);
        const channel = MethodChannel(
          'plugins.it_nomads.com/flutter_secure_storage',
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              channel,
              (c) async => c.method == 'read' ? 'fixture' : null,
            );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
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
          wrapStaff: (child) => MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(0.8)),
            child: child,
          ),
        );
        final api = TableFake()
          ..value = tableFixture(selected: 3, pending: mixed);
        (api.value['rounds'] as List).add({
          'id': 108,
          'round_no': 3,
          'status': 'pending_confirmation',
          'entered_by': 'staff',
          'needs_review': true,
          'total_baisas': 0,
          'tax_baisas': 0,
          'priced_lines': [
            {
              'product_id': 2,
              'product_name': 'Held sweety',
              'qty': 1,
              'held_reason': 'out_of_stock',
              'addon_id': null,
              'unit_price_baisas': null,
              'line_total_baisas': null,
            },
          ],
        });
        late CurrentOrderWorkspace workspace;
        final dynamic host = tester.state(find.byType(StaffPosScreen));
        host.openServerWorkspace((CurrentOrderWorkspace w) {
          workspace = w;
          return DineInScreen(
            workspace: w,
            label: 'Table 3',
            createController: () async =>
                DineInController(api, TableMemory(), 3, staffId: 1),
            catalogue: () => [],
            onPay: (_) async => fail('Held rounds cannot pay'),
          );
        }, tableLabel: 'Table 3');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Held sweety'), findsOneWidget);
        expect(find.textContaining('Held — no price yet'), findsOneWidget);
        expect(find.textContaining('Out of stock'), findsOneWidget);
        expect(
          workspace.cartBill!.items.any(
            (r) => r['product_name'] == 'Held sweety',
          ),
          isFalse,
        );
        expect(workspace.cartBill!.total, mixed ? 5250 : 4750);
        expect(workspace.canPay, isFalse);
        expect(
          workspace.cartControls!.actions
              .where((a) => a.label == 'Confirm round 3')
              .single
              .run,
          isNotNull,
        );
        expect(
          workspace.cartControls!.actions
              .where((a) => a.label == 'Reject round 3')
              .single
              .run,
          isNotNull,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
