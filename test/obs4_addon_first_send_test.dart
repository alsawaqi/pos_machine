import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/table_sync_models.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'send_to_kitchen_test.dart' show B3Memory;
import 'workspace_machine_harness.dart';

class _Coordinator extends WorkspaceTableCoordinator {
  _Coordinator(this.memory);
  final B3Memory memory;
  int sends = 0;
  List<Map<String, dynamic>> sent = [];
  @override
  bool get live => true;
  Completer<void>? approval;
  @override
  Future<void> get settled => approval?.future ?? Future<void>.value();
  @override
  TableLedgerStore get store => memory;
  @override
  Future<List<Map<String, dynamic>>> delta(DiningTableSession s) async =>
      buildTableRoundLines(s.draft!.items);
  @override
  void onTableOccupied(DiningTableSession s) {}
  @override
  void onTableDraftPersisted(DiningTableSession s) {}
  @override
  void onTableLeft(String id) {}
  @override
  Future<LocalTableRound?> sendRound(DiningTableSession s) async {
    sent = await delta(s);
    validateRound!(sent);
    sends++;
    return null;
  }
}

void main() {
  testWidgets(
    'OBS4 first kitchen tap after add-on Apply sends the chosen size once',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const rear = MethodChannel('pos_machine/rear_display_host');
      const secure = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            secure,
            (c) async => c.method == 'read' ? 'fixture' : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(secure, null),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            rear,
            (_) async => <Map<String, dynamic>>[],
          );
      final memory = B3Memory();
      debugOrderStorageOverride = memory;
      addTearDown(() {
        debugOrderStorageOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(rear, null);
      });
      final coordinator = _Coordinator(memory);
      const coffee = Product(
        id: '7',
        name: 'Coffee',
        category: 'Coffee',
        price: 1,
        addonGroupIds: [1],
      );
      await pumpWorkspaceMachine(
        tester,
        mode: 'live',
        toggle: false,
        coordinator: coordinator,
        wrapStaff: (child) => MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(0.8)),
          child: child,
        ),
        catalog: const CatalogSnapshot(
          categories: ['Coffee'],
          products: [coffee],
          floors: [DiningFloor(id: '1', label: 'Ground')],
          tables: [
            DiningTableDefinition(
              id: '1',
              floorId: '1',
              name: 'Table 1',
              sizeLabel: '2',
              seats: 2,
              sortOrder: 1,
            ),
          ],
          taxes: [],
          addonGroups: [
            AddonGroup(
              id: 1,
              name: 'Size',
              multiSelect: false,
              minSelections: 1,
              options: [AddonOption(id: 11, label: 'Large', priceDelta: 0.2)],
            ),
          ],
        ),
      );
      final dynamic host = tester.state(find.byType(StaffPosScreen));
      final PosController c = host.controller;
      await c.openDiningTable('1');
      c.addProduct(coffee);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add On'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Large'));
      await tester.pump();
      coordinator.approval = Completer<void>();
      await tester.tap(find.textContaining('Apply '));
      // The cashier can tap the exposed button as soon as Apply closes the sheet.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Keep the editor visible until the existing sent-line safety check finishes.
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_CustomizeCartItemDialog',
        ),
        findsOneWidget,
      );
      coordinator.approval!.complete();
      await tester.pumpAndSettle();
      final send = find.byKey(const ValueKey('table-send-to-kitchen'));
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(coordinator.sends, 1);
      expect(coordinator.sent.single['addon_ids'], [11]);
      expect(coordinator.sent.single['qty'], 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
