import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/core/manager_auth.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';

import 'support/fake_order_storage.dart';
import 'workspace_machine_harness.dart';

/// LAUNCH-P5 C1 / C9 — real-screen gates: an action the person's position
/// is not ticked for opens the approval sheet (here: sold out for a
/// cashier); the hard-coded sold-out positions are gone; the partial cancel
/// of a paid order and the QR quick-order Void stay hidden.
class _Api implements PosApiService {
  final switches = <Map<String, Object?>>[];

  @override
  Future<List<Map<String, dynamic>>> fetchIncomingTransfers() async => [];

  @override
  Future<ApproverVerification?> verifyApprover(String pin) async =>
      pin == '654321'
      ? const ApproverVerification(staffId: 3, name: 'Mona')
      : null;

  @override
  Future<void> setProductSoldOut(
    int productId, {
    required bool soldOut,
    required int staffId,
    Map<String, dynamic>? authorization,
    String? clientRequestId,
  }) async {
    switches.add({
      'product': productId,
      'sold_out': soldOut,
      'staff': staffId,
      'authorization': authorization,
      'client_request_id': clientRequestId,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected network operation: ${invocation.memberName}',
  );
}

void main() {
  const latte = Product(
    id: '10',
    name: 'Latte',
    category: 'Coffee',
    price: 1.5,
  );
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

  Future<_Api> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _Api();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await pumpWorkspaceMachine(
      tester,
      mode: 'off',
      toggle: false,
      api: api,
      database: db,
      // The shared defaults: the harness cashier has no sold_out.toggle.
      allowAllTicks: false,
      catalog: const CatalogSnapshot(
        categories: ['Coffee'],
        products: [latte],
        floors: [],
        tables: [],
        taxes: [],
      ),
    );
    return api;
  }

  Future<void> switchSoldOut(WidgetTester tester) async {
    await tester.longPress(find.text('Latte').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sold-out-switch-confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a cashier needs an approver to switch sold out; cancel = nothing',
    (tester) async {
      final api = await mount(tester);
      await switchSoldOut(tester);
      expect(find.byType(ManagerApprovalSheet), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(api.switches, isEmpty);
      await disposeWorkspaceMachine(tester);
    },
  );

  testWidgets('an approver\'s PIN switches it, with the approval block', (
    tester,
  ) async {
    final api = await mount(tester);
    await switchSoldOut(tester);
    final sheet = find.byType(ManagerApprovalSheet);
    for (final d in '654321'.split('')) {
      await tester.tap(find.descendant(of: sheet, matching: find.text(d)));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('manager-approval-verify')));
    for (var i = 0; i < 20 && api.switches.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    final block = api.switches.single['authorization'] as Map;
    expect(block['action'], 'sold_out.toggle');
    expect(block['mode'], 'approval');
    expect(block['approver_staff_id'], 3);
    expect(block['actor_staff_id'], 7);
    expect(block['method'], 'online');
    await tester.pumpAndSettle();
    await disposeWorkspaceMachine(tester);
  });

  test(
    'C9: paid orders cancel whole only; the QR quick-order Void is hidden',
    () {
      final screen = File(
        'lib/screens/staff_pos_screen.dart',
      ).readAsStringSync();
      expect(screen, contains('fullOrderOnly: true,'));
      expect(screen, isNot(contains('fullOrderOnly: record.fromServer')));
      final quick = File(
        'lib/screens/qr_quick_orders_screen.dart',
      ).readAsStringSync();
      expect(quick, contains('onVoid: null,'));
      expect(
        quick,
        isNot(contains('onVoid: (uuid) => openMachineWorkspaceVoid')),
      );
    },
  );

  test('C2: the fingerprint approval and its registration are gone', () {
    expect(
      File('lib/services/manager_authorization_service.dart').existsSync(),
      isFalse,
    );
    final screen = File('lib/screens/staff_pos_screen.dart').readAsStringSync();
    expect(screen, isNot(contains('manager_biometrics')));
    expect(screen, isNot(contains('registerManagerFingerprint')));
    expect(screen, isNot(contains('_ManagerPinDialog')));
  });
}
