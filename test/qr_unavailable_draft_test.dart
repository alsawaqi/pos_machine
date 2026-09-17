import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/order_workspace/current_order_workspace.dart';
import 'package:pos_machine/qr_quick/qr_quick_controller.dart';
import 'package:pos_machine/qr_quick/qr_quick_copy.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'package:pos_machine/qr_quick/qr_quick_screen.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'qr_quick_controller_test.dart';
import 'qr_quick_evidence.dart';
import 'qr_workspace_flow_test.dart' show WorkspaceGateway;
import 'support/fake_order_storage.dart';
import 'workspace_machine_harness.dart';

class AvailabilityGateway extends WorkspaceGateway {
  @override
  Future<Map<String, dynamic>> append(QrQuickRequest request) async {
    refusal = request.lines.any((line) => line.productId == 7)
        ? const QrQuickFailure(
            'product_unavailable',
            'Unavailable',
            refused: true,
          )
        : null;
    return super.append(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AvailabilityGateway gateway;
  late MemoryQuickStore store;
  late QrQuickController controller;
  late CurrentOrderWorkspace workspace;
  late String cashierDraft;
  dynamic staff;
  final paid = <String>[];
  setUp(() {
    gateway = AvailabilityGateway();
    store = MemoryQuickStore();
    controller = QrQuickController(gateway, store);
    paid.clear();
    debugOrderStorageOverride = FakeOrderStorage();
    const channels = [
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      MethodChannel('pos_machine/rear_display_host'),
      MethodChannel('sunmi_printer_plus'),
    ];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in channels) {
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

  Future<void> mount(WidgetTester tester, {bool arabic = false}) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await loadQuickEvidenceFonts(tester);
    await pumpWorkspaceMachine(
      tester,
      mode: 'live',
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
    staff = tester.state(find.byType(StaffPosScreen));
    cashierDraft = jsonEncode(staff.controller.snapshot().toMap());
    staff.openServerWorkspace((CurrentOrderWorkspace w) {
      workspace = w;
      return QrQuickScreen(
        workspace: w,
        workspaceUuid: 'bill-1',
        arabic: arabic,
        createController: () async => controller,
        catalogue: () => [],
        onPay: (_, order) async => paid.add(order.uuid),
      );
    }, quick: true);
    await tester.pumpAndSettle();
  }

  Future<void> add(WidgetTester tester, int id) async {
    final action = workspace.pick(
      QuickProduct(
        id,
        id == 7 ? 'Unavailable cake' : 'Available water',
        nameAr: id == 7 ? 'كعكة غير متاحة' : 'ماء متاح',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-option-add')), findsNothing);
    await tester.pumpAndSettle();
    await action;
  }

  for (final arabic in [false, true]) {
    testWidgets(
      'remove rejected unsent addition, then add and pay a valid item ${arabic ? 'AR' : 'EN'}',
      (tester) async {
        await mount(tester, arabic: arabic);
        final originalBill = jsonEncode(workspace.bill!.json);
        await add(tester, 7);
        expect(controller.notice, 'product_unavailable');
        expect(workspace.cartControls!.drafts, hasLength(1));
        expect(workspace.canPay, false);
        expect(store.data, isEmpty);
        await controller.refresh();
        await tester.pumpAndSettle();
        expect(workspace.cartControls!.drafts, hasLength(1));
        final remove = find.byKey(const ValueKey('workspace-remove-draft-0'));
        expect(remove, findsOneWidget);
        await tester.ensureVisible(remove);
        await tester.tap(remove);
        await tester.pumpAndSettle();
        expect(workspace.cartControls!.drafts, isEmpty);
        expect(controller.notice, isNull);
        expect(
          find.text(QuickCopy(arabic).message('product_unavailable')),
          findsNothing,
        );
        expect(jsonEncode(workspace.bill!.json), originalBill);
        expect(gateway.edits, isEmpty);
        expect(workspace.canPay, true);
        await add(tester, 8);
        expect(gateway.requests.last.lines.map((line) => line.productId), [8]);
        expect(gateway.mutations, 1);
        expect(workspace.cartControls!.drafts, isEmpty);
        expect(workspace.cartControls!.notices, isEmpty);
        await workspace.requestPay();
        await tester.pumpAndSettle();
        expect(paid, ['bill-1']);
        expect(jsonEncode(staff.controller.snapshot().toMap()), cashierDraft);
        expect(tester.takeException(), isNull);
        await disposeWorkspaceMachine(tester);
      },
    );
  }

  testWidgets(
    'Clear removes saved bill and rejected drafts before another addition',
    (tester) async {
      await mount(tester);
      await add(tester, 7);
      // A new item currently resends the rejected batch: reproduce that state.
      await add(tester, 8);
      expect(gateway.requests.last.lines.map((line) => line.productId), [7, 8]);
      expect(workspace.cartControls!.drafts, hasLength(2));
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(gateway.edits.single['operation'], 'clear');
      expect(workspace.bill!.total, 0);
      expect(workspace.cartControls!.drafts, isEmpty);
      expect(workspace.cartControls!.notices, isEmpty);
      expect(find.text('Back to QR Orders'), findsOneWidget);
      expect(workspace.canPay, false);
      await add(tester, 8);
      expect(gateway.requests.last.lines.map((line) => line.productId), [8]);
      expect(workspace.cartControls!.drafts, isEmpty);
      expect(workspace.canPay, true);
      expect(gateway.mutations, 1);
      expect(jsonEncode(staff.controller.snapshot().toMap()), cashierDraft);
      expect(tester.takeException(), isNull);
      await disposeWorkspaceMachine(tester);
    },
  );

  testWidgets(
    'Clear and draft removal cannot discard an uncertain accepted request',
    (tester) async {
      await mount(tester);
      gateway.lostResponse = true;
      await add(tester, 8);
      final request = jsonEncode(store.data.values.single.payload);
      expect(workspace.cartControls!.drafts, isEmpty);
      expect(controller.notice, 'uncertain');
      expect(workspace.cartControls!.clear, isNull);
      expect(
        find.byKey(const ValueKey('workspace-remove-draft-0')),
        findsNothing,
      );
      expect(workspace.canPay, false);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(jsonEncode(store.data.values.single.payload), request);
      expect(gateway.edits, isEmpty);
      gateway.lostResponse = false;
      await workspace.cartControls!.retry!();
      await tester.pumpAndSettle();
      expect(gateway.requests.map((r) => jsonEncode(r.payload)), [
        request,
        request,
      ]);
      expect(store.data, isEmpty);
      expect(gateway.mutations, 1);
      expect(workspace.canPay, true);
      expect(tester.takeException(), isNull);
      await disposeWorkspaceMachine(tester);
    },
  );
}
