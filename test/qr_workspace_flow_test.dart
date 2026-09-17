import 'package:pos_machine/services/audience_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'qr_checkout_fakes.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/order_workspace/current_order_workspace.dart';
import 'package:pos_machine/qr_quick/qr_quick_controller.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'package:pos_machine/qr_quick/qr_quick_screen.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'qr_quick_controller_test.dart';
import 'support/fake_order_storage.dart';
import 'workspace_machine_harness.dart';

class WorkspaceGateway extends FakeQuickGateway
    implements QrQuickWorkspaceGateway {
  WorkspaceGateway() {
    orders = [
      QrQuickOrder({...quickJson(), 'edit_revision': 'revision-1'}),
    ];
  }
  final edits = <Map<String, dynamic>>[];
  final saved = <String, Map<String, dynamic>>{};
  bool loseEditReply = false;
  @override
  Future<Map<String, dynamic>> change(QrQuickRequest request) async {
    edits.add(jsonDecode(jsonEncode(request.payload)) as Map<String, dynamic>);
    final replay = saved.containsKey(request.id);
    if (!replay) {
      final row = Map<String, dynamic>.from(orders.single.json);
      if (request.change!['operation'] == 'clear') {
        row['items'] = <Map<String, dynamic>>[];
        row['grand_total_baisas'] = 0;
        row['actions'] = {'settle': false};
      } else if (request.change!['operation'] == 'transfer') {
        row['transferred_to_device_id'] = request.change!['target_device_id'];
        row['actions'] = {'settle': false};
      }
      row['edit_revision'] = 'revision-2';
      saved[request.id] = row;
      orders = [QrQuickOrder(row)];
    }
    if (loseEditReply) throw TimeoutException('Committed response lost');
    return {'order': saved[request.id], 'replayed': replay};
  }
}

class RecordingAudience implements AudienceService {
  final events = <String>[];
  @override
  Future<void> start() async {
    events.add('start');
  }

  @override
  Future<void> stop() async {
    events.add('stop');
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('Unexpected audience call');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'append returns its authoritative bill without another inbox round trip',
    () async {
      final gateway = FakeQuickGateway();
      final c = QrQuickController(gateway, MemoryQuickStore());
      await c.start();
      expect(await c.add('bill-1', [QrQuickLine(7, 1, [])]), true);
      expect(gateway.fetches, 1);
      expect(c.canAdd('bill-1'), true);
      c.dispose();
    },
  );
  test(
    'lost clear reply survives restart and replays the same request once',
    () async {
      final gateway = WorkspaceGateway()..loseEditReply = true;
      final store = MemoryQuickStore();
      var c = QrQuickController(gateway, store);
      await c.start();
      expect(await c.change('bill-1', {'operation': 'clear'}), false);
      final original = jsonEncode(gateway.edits.single);
      expect(c.canPay('bill-1'), false);
      c.dispose();
      c = QrQuickController(gateway, store);
      await c.start();
      gateway.loseEditReply = false;
      expect(await c.retry('bill-1'), true);
      expect(jsonEncode(gateway.edits.last), original);
      expect(gateway.saved, hasLength(1));
      expect(c.find('bill-1')!.total, 0);
      expect(c.canAdd('bill-1'), true);
      expect(c.canPay('bill-1'), false);
      expect(store.data, isEmpty);
      c.dispose();
    },
  );
  test('only an explicit target request transfers a whole QR order', () async {
    final gateway = WorkspaceGateway();
    final c = QrQuickController(gateway, MemoryQuickStore());
    await c.start();
    final items = jsonEncode(c.find('bill-1')!.items);
    expect(gateway.edits, isEmpty);
    expect(
      await c.change('bill-1', {
        'operation': 'transfer',
        'target_device_id': 42,
      }),
      true,
    );
    expect(gateway.edits.single['target_device_id'], 42);
    expect(jsonEncode(c.find('bill-1')!.items), items);
    expect(c.find('bill-1')!.total, 1000);
    expect(c.canAdd('bill-1'), false);
    expect(c.canPay('bill-1'), false);
    c.dispose();
  });
  testWidgets(
    'Clear edits the QR bill in place; Hold becomes Back to QR Orders',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      debugOrderStorageOverride = FakeOrderStorage();
      addTearDown(() => debugOrderStorageOverride = null);
      const channels = [
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        MethodChannel('pos_machine/rear_display_host'),
        MethodChannel('sunmi_printer_plus'),
      ];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final c in channels) {
        messenger.setMockMethodCallHandler(
          c,
          (call) async => call.method == 'read'
              ? 'test-token'
              : call.method == 'getPresentationDisplays'
              ? <Map<String, dynamic>>[]
              : null,
        );
        addTearDown(() => messenger.setMockMethodCallHandler(c, null));
      }
      final audience = RecordingAudience();
      await pumpWorkspaceMachine(
        tester,
        mode: 'live',
        audience: audience,
        audienceConsent: true,
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
      final original = jsonEncode(state.controller.snapshot().toMap());
      final gateway = WorkspaceGateway();
      late CurrentOrderWorkspace workspace;
      state.openServerWorkspace((CurrentOrderWorkspace w) {
        workspace = w;
        return QrQuickScreen(
          workspace: w,
          workspaceUuid: 'bill-1',
          createController: () async =>
              QrQuickController(gateway, MemoryQuickStore()),
          catalogue: () => [],
        );
      }, quick: true);
      await tester.pumpAndSettle();
      expect(find.text('Back to QR Orders'), findsOneWidget);
      expect(audience.events.last, 'stop');
      final dynamic footer = tester.widget(
        find.byWidgetPredicate(
          (w) =>
              w.runtimeType.toString() == '_FooterActionCard' &&
              (w as dynamic).title == 'Transfer',
        ),
      );
      expect(footer.enabled, true);
      final payment = CheckoutFixture().controller();
      await payment.open('qr-bill');
      unawaited(
        Navigator.of(tester.element(find.byType(StaffPosScreen))).push<void>(
          MaterialPageRoute(
            builder: (_) => state.buildQrPaymentPage(payment, () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic transfer = tester.widget(
        find.byWidgetPredicate(
          (w) =>
              w.runtimeType.toString() == '_PaymentTopActionCard' &&
              (w as dynamic).title == 'Transfer',
        ),
      );
      expect(transfer.onTap, isNotNull);
      Navigator.of(tester.element(find.text('Payment').first)).pop();
      await tester.pumpAndSettle();
      payment.dispose();
      expect(find.text('Clear'), findsOneWidget);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(workspace.bill!.total, 0);
      expect(find.text('Back to QR Orders'), findsOneWidget);
      expect(gateway.edits.single['operation'], 'clear');
      expect(jsonEncode(state.controller.snapshot().toMap()), original);
      workspace.returnToList = false;
      await tester.tap(find.text('Back to QR Orders'));
      await tester.pumpAndSettle();
      expect(find.text('Back to QR Orders'), findsNothing);
      expect(audience.events.last, 'start');
      expect(gateway.edits, hasLength(1));
      expect(jsonEncode(state.controller.snapshot().toMap()), original);
      final waiting = FakeQuickGateway()
        ..orders = [QrQuickOrder(quickJson(status: 'awaiting_payment'))];
      state.openServerWorkspace((CurrentOrderWorkspace w) {
        workspace = w;
        return QrQuickScreen(
          workspace: w,
          workspaceUuid: 'bill-1',
          createController: () async =>
              QrQuickController(waiting, MemoryQuickStore()),
          catalogue: () => [],
        );
      }, quick: true);
      await tester.pumpAndSettle();
      expect(waiting.moves, 1);
      expect(workspace.canAdd, true);
      await tester.tap(find.text('To Go'));
      await tester.pumpAndSettle();
      expect(find.text('Back to QR Orders'), findsNothing);
      expect(waiting.moves, 1);
      expect(waiting.requests, isEmpty);
    },
  );
}
