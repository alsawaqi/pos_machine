import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:pos_machine/main.dart';
import 'package:pos_machine/models/kitchen_production.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/services/geofence_service.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/services/shift_payload.dart';
import 'package:pos_machine/services/shift_service.dart';

import 'support/fake_order_storage.dart';

void main() {
  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const rearDisplayChannel = MethodChannel('pos_machine/rear_display_host');
  const printerChannel = MethodChannel('sunmi_printer_plus');

  // Per-test device token served by the mocked secure-storage channel.
  // Null = unpaired device (the setup screen); set it to reach the POS.
  String? mockDeviceToken;

  setUp(() async {
    mockDeviceToken = null;
    // The expectations in this file are written against 5% VAT — taxes are
    // config-driven now (empty ⇒ no tax), so seed the historical rate.
    activeCompanyTaxes = const [CompanyTax(name: 'VAT', ratePercent: 5)];
    SharedPreferences.setMockInitialValues({});
    // SessionService.load() reads the device token from secure storage —
    // no plugin in tests, so serve the per-test token (or nothing).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          secureStorageChannel,
          (call) async => call.method == 'read' ? mockDeviceToken : null,
        );
    // The card flow hands the rear display to Mosambee before loginAndPay —
    // answer the host + printer channels so the awaits resolve in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(rearDisplayChannel, (call) async {
          switch (call.method) {
            case 'getPresentationDisplays':
              return <Map<String, dynamic>>[];
            case 'openRearDisplay':
            case 'hideRearDisplay':
            case 'transferDataToRear':
              return true;
            default:
              return null;
          }
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(printerChannel, (call) async => null);
    // In-memory storage: the sqflite database can't do I/O inside the
    // testWidgets FakeAsync zone.
    debugOrderStorageOverride = FakeOrderStorage();
  });

  tearDown(() {
    debugOrderStorageOverride = null;
    activeCompanyTaxes = const <CompanyTax>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(rearDisplayChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(printerChannel, null);
  });

  // A fully-signed-in device: paired (token via the channel), staff logged
  // in, shift open — the boot gate walks straight through to the POS. The
  // startup flow gained these gates after the tests were written; each POS
  // test seeds this instead of the old bare terminal_id.
  void seedSignedInSession({int staffId = 7, int shiftStaffId = 7}) {
    mockDeviceToken = 'test-device-token';
    SharedPreferences.setMockInitialValues({
      'terminal_id': 'TERM-1001',
      'kiosk_id': 'KIOSK-1',
      'company_id': 9,
      'branch_id': 6,
      'staff_session_json': jsonEncode({
        'id': staffId,
        'name': 'Test Cashier',
        'position': 'cashier',
        'branch_id': 6,
      }),
      'open_shift_json': jsonEncode({
        'uuid': 'shift-0001',
        'opening_cash_baisas': 0,
        'opened_at': DateTime(2026, 1, 1, 8).toIso8601String(),
        'staff_id': shiftStaffId,
      }),
    });
  }

  // The app under test, wired exactly like main(): StaffApp reads Riverpod
  // providers, and the two async singletons are overridden with instances
  // built from the (mocked) prefs + secure storage. The geofence stream is
  // pinned to "disabled" (no fence configured) so the location plugin —
  // absent in tests — never locks the POS.
  Future<Widget> testApp({
    PosApiService? apiService,
    ShiftService? shiftService,
    bool stubShiftReconciliation = true,
    bool? releaseBuild,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final session = SessionService(const FlutterSecureStorage(), prefs);
    await session.load();
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionServiceProvider.overrideWithValue(session),
        geofenceProvider.overrideWith(
          (ref) => Stream.value(const GeofenceStatus(FenceState.disabled)),
        ),
        if (apiService != null)
          apiServiceProvider.overrideWithValue(apiService),
        if (shiftService != null)
          shiftServiceProvider.overrideWithValue(shiftService),
        if (releaseBuild != null)
          releaseBuildProvider.overrideWithValue(releaseBuild),
        // Most widget cases exercise screens below the startup gate. Keep the
        // network-owned MC-003 reconciliation deterministic; focused tests
        // cover its API behavior separately.
        if (stubShiftReconciliation)
          shiftReconciliationProvider.overrideWith(
            (ref, staffId) async => null,
          ),
      ],
      child: releaseBuild == null
          ? const StaffApp()
          : StaffApp(key: ValueKey('staff-app-$releaseBuild')),
    );
  }

  testWidgets('staff POS renders and gates Server settings in both modes', (
    WidgetTester tester,
  ) async {
    seedSignedInSession();

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await testApp(releaseBuild: false));
    await tester.pumpAndSettle();

    expect(find.text('Current Order'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Process to Pay'), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('Mocha'), findsOneWidget);
    expect(find.text('Flat White'), findsOneWidget);
    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text('Order History'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-server-address')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(await testApp(releaseBuild: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-server-address')), findsNothing);
    expect(find.text('RECEIPTS'), findsOneWidget);
  });

  testWidgets('a foreign cached shift blocks POS until its drawer is closed', (
    WidgetTester tester,
  ) async {
    seedSignedInSession(staffId: 8, shiftStaffId: 7);
    final api = _WidgetShiftApi(const [_ShiftProbeFailure()]);

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      await testApp(apiService: api, stubShiftReconciliation: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Close shift'), findsWidgets);
    expect(find.text('Counted drawer cash (OMR)'), findsOneWidget);
    expect(find.text('Current Order'), findsNothing);
  });

  testWidgets('startup probes and adopts the signed-in staff shared shift', (
    WidgetTester tester,
  ) async {
    seedSignedInSession(staffId: 8, shiftStaffId: 7);
    final api = _WidgetShiftApi([
      OpenShiftData(
        uuid: 'shift-b',
        openingCashBaisas: 5000,
        openedAt: DateTime.utc(2026, 8, 8, 8),
        staffId: 8,
      ),
    ]);

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      await testApp(apiService: api, stubShiftReconciliation: false),
    );
    await tester.pumpAndSettle();

    expect(api.shiftCalls, [(staffId: 8, sharedStaffOnly: true)]);
    expect(find.text('Current Order'), findsOneWidget);
    expect(find.text('Close shift'), findsNothing);
  });

  testWidgets('forced handover can switch staff without clearing the drawer', (
    WidgetTester tester,
  ) async {
    seedSignedInSession(staffId: 8, shiftStaffId: 7);

    await tester.pumpWidget(await testApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch staff'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(find.text('Staff login'), findsOneWidget);
    expect(prefs.getString('staff_session_json'), isNull);
    expect(prefs.getString('open_shift_json'), isNotNull);
  });

  testWidgets('forced close saves the drawer owner on the Z ticket', (
    WidgetTester tester,
  ) async {
    seedSignedInSession(staffId: 8, shiftStaffId: 7);
    final api = _WidgetShiftApi(const []);

    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      await testApp(apiService: api, shiftService: _SettledShiftService(api)),
    );
    await tester.pumpAndSettle();
    final closeButton = find.widgetWithText(FilledButton, 'Close shift');
    await tester.ensureVisible(closeButton);
    await tester.tap(closeButton);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final saved =
        jsonDecode(prefs.getString('last_shift_summary_json')!)
            as Map<String, dynamic>;
    expect(saved['staff_name'], 'Shift owner #7');
    expect(saved['staff_name'], isNot('Test Cashier'));
  });

  testWidgets('staff POS defaults to low-cost rendering effects', (
    WidgetTester tester,
  ) async {
    seedSignedInSession();

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await testApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('payment page opens from process to pay', (
    WidgetTester tester,
  ) async {
    seedSignedInSession();

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Process to Pay'));
    await tester.pumpAndSettle();

    expect(find.text('Payment'), findsOneWidget);
    expect(find.text('Order Items'), findsOneWidget);
    expect(find.text('Customer Number (Optional)'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Card'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('current order accepts more than three visible items', (
    WidgetTester tester,
  ) async {
    seedSignedInSession();

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await testApp());
    await tester.pumpAndSettle();

    for (final productName in const [
      'Espresso',
      'Cappuccino',
      'Latte',
      'Americano',
    ]) {
      await tester.tap(find.text(productName));
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull);
    expect(find.text('(4)'), findsOneWidget);
    expect(find.text('AMERICANO'), findsOneWidget);
  });

  testWidgets('empty payment attempt shows animated popup warning', (
    WidgetTester tester,
  ) async {
    seedSignedInSession();

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Process to Pay'));
    await tester.pumpAndSettle();

    expect(find.text('Order Required'), findsOneWidget);
    expect(find.text('Add at least one item before paying.'), findsOneWidget);
  });

  testWidgets('cash keypad accepts decimal amounts and updates change', (
    WidgetTester tester,
  ) async {
    seedSignedInSession();

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Process to Pay'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('payment-key-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('payment-key-decimal')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('payment-key-5')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tendered-amount')), findsOneWidget);
    expect(find.text('2.500 OMR'), findsOneWidget);
    expect(find.byKey(const ValueKey('change-amount')), findsOneWidget);
    expect(find.text('0.925 OMR'), findsOneWidget);
  });

  testWidgets(
    'card payment switches to direct tap-to-pay state while Mosambee opens',
    (WidgetTester tester) async {
      seedSignedInSession();

      const paymentChannel = MethodChannel('com.example.mosambee');
      final paymentCompleter = Completer<String>();
      var loginStarted = false;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paymentChannel, (call) async {
            // No pre-warmed session in tests — report NO_SESSION so the
            // service takes its documented fallback into loginAndPay.
            if (call.method == 'payWithPreparedSession') {
              return '{"status":"failed","code":"NO_SESSION"}';
            }
            if (call.method == 'loginAndPay') {
              loginStarted = true;
              return paymentCompleter.future;
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(paymentChannel, null);
      });

      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(await testApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Process to Pay'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Card'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Yes, round up for charity'));
      await tester.pump();

      expect(loginStarted, isTrue);
      expect(find.text('Opening Payment Terminal'), findsNothing);
      expect(find.text('SECURE CARD PAYMENT'), findsNothing);

      paymentCompleter.complete(
        '{"status":"success","message":"Payment approved."}',
      );
      await tester.pumpAndSettle();
      // Let the 4s payment-result popup auto-dismiss so no timer outlives
      // the tree.
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'customer reference number is not sent with the card payment request',
    (WidgetTester tester) async {
      seedSignedInSession();

      const paymentChannel = MethodChannel('com.example.mosambee');
      String? sentMobNo;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paymentChannel, (call) async {
            // No pre-warmed session in tests — report NO_SESSION so the
            // service takes its documented fallback into loginAndPay.
            if (call.method == 'payWithPreparedSession') {
              return '{"status":"failed","code":"NO_SESSION"}';
            }
            if (call.method == 'loginAndPay') {
              final arguments = Map<String, dynamic>.from(
                call.arguments as Map,
              );
              sentMobNo = arguments['mobNo']?.toString();
              return '{"status":"success","message":"Payment approved."}';
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(paymentChannel, null);
      });

      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(await testApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Process to Pay'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('payment-customer-number')));
      await tester.pumpAndSettle();

      for (final key in const ['9', '1', '2', '3', '4', '5', '6', '7']) {
        await tester.tap(find.text(key).last);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Card'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('No, keep original total'));
      await tester.pumpAndSettle();

      expect(sentMobNo, '');

      // Let the 4s payment-result popup auto-dismiss so no timer outlives
      // the tree.
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'customized add-ons appear in current order and payment summary',
    (WidgetTester tester) async {
      seedSignedInSession();

      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(await testApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add On').first);
      await tester.pumpAndSettle();

      expect(find.text('Customize Espresso'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('customize-option-size_grande')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('customize-option-milk_oat')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('customize-option-addon_espresso_shot')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('customize-notes')),
        'Less sugar',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('customize-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Size (Required): Grande'), findsOneWidget);
      expect(find.text('Milk Type: Oat (+0.500 OMR)'), findsOneWidget);
      expect(find.text('Add-ons: Espresso Shot (+1.000 OMR)'), findsOneWidget);
      expect(find.text('Notes: Less sugar'), findsOneWidget);

      await tester.tap(find.text('Process to Pay'));
      await tester.pumpAndSettle();

      expect(find.text('Payment'), findsOneWidget);
      expect(find.text('Size (Required): Grande'), findsOneWidget);
      expect(find.text('Milk Type: Oat (+0.500 OMR)'), findsOneWidget);
      expect(find.text('Add-ons: Espresso Shot (+1.000 OMR)'), findsOneWidget);
      expect(find.text('Notes: Less sugar'), findsOneWidget);
    },
  );

  testWidgets('dine-in shows the floor plan and opens a table editor', (
    WidgetTester tester,
  ) async {
    seedSignedInSession();

    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dine In'));
    await tester.pumpAndSettle();

    expect(find.text('Floor Plan'), findsOneWidget);
    expect(find.text('Main Hall'), findsWidgets);
    expect(find.text('T1'), findsOneWidget);
    expect(find.text('T2'), findsOneWidget);

    await tester.tap(find.text('T1'));
    await tester.pumpAndSettle();

    expect(find.text('Current Order'), findsOneWidget);
    expect(find.text('Table T1'), findsOneWidget);
    expect(find.text('Back To Floor'), findsOneWidget);
  });

  testWidgets('device setup renders and gates Server settings in both modes', (
    WidgetTester tester,
  ) async {
    final api = _PingApi();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      await testApp(apiService: api, releaseBuild: false),
    );
    await tester.pumpAndSettle();

    // The unpaired device lands on the enrollment screen, never the POS.
    expect(find.text('Set up this device'), findsOneWidget);
    expect(find.text('Current Order'), findsNothing);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    final serverField = find.byKey(const ValueKey('settings-server-address'));
    expect(serverField, findsOneWidget);
    await tester.enterText(serverField, '192.0.2.10:8088');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Test connection'));
    await tester.pumpAndSettle();
    expect(api.pingedBaseUrl, 'http://192.0.2.10:8088/api/v1');
    expect(
      find.text('Server reachable at http://192.0.2.10:8088/api/v1'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(await testApp(apiService: api, releaseBuild: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-server-address')), findsNothing);
    expect(find.text('RECEIPTS'), findsOneWidget);
  });
}

class _PingApi extends PosApiService {
  _PingApi() : super(tokenGetter: () => null);

  String? pingedBaseUrl;

  @override
  Future<bool> pingBaseUrl(String baseUrl) async {
    pingedBaseUrl = baseUrl;
    return true;
  }
}

class _WidgetShiftApi extends PosApiService {
  _WidgetShiftApi(List<Object?> responses)
    : _responses = List.of(responses),
      super(tokenGetter: () => 'device-token');

  final List<Object?> _responses;
  final List<({int? staffId, bool sharedStaffOnly})> shiftCalls = [];

  @override
  Future<OpenShiftData?> fetchCurrentShift({
    int? staffId,
    bool sharedStaffOnly = false,
  }) async {
    shiftCalls.add((staffId: staffId, sharedStaffOnly: sharedStaffOnly));
    if (_responses.isEmpty) {
      throw StateError('Unexpected shift probe');
    }
    final response = _responses.removeAt(0);
    if (response is _ShiftProbeFailure) throw StateError('offline');
    return response as OpenShiftData?;
  }

  @override
  Future<List<DispositionItem>> fetchDisposition() async => const [];
}

class _ShiftProbeFailure {
  const _ShiftProbeFailure();
}

class _SettledShiftService extends ShiftService {
  _SettledShiftService(super.api);

  @override
  Future<ShiftCloseResult> close({
    required String shiftUuid,
    required int closingCashBaisas,
  }) async => const ShiftCloseResult(
    expectedCashBaisas: 0,
    varianceBaisas: 0,
    summaryJson: {},
  );
}
