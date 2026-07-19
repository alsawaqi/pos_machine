import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:pos_machine/main.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/services/geofence_service.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/session_service.dart';

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
  void seedSignedInSession() {
    mockDeviceToken = 'test-device-token';
    SharedPreferences.setMockInitialValues({
      'terminal_id': 'TERM-1001',
      'kiosk_id': 'KIOSK-1',
      'company_id': 9,
      'branch_id': 6,
      'staff_session_json': jsonEncode({
        'id': 7,
        'name': 'Test Cashier',
        'position': 'cashier',
        'branch_id': 6,
      }),
      'open_shift_json': jsonEncode({
        'uuid': 'shift-0001',
        'opening_cash_baisas': 0,
        'opened_at': DateTime(2026, 1, 1, 8).toIso8601String(),
        'staff_id': 7,
      }),
    });
  }

  // The app under test, wired exactly like main(): StaffApp reads Riverpod
  // providers, and the two async singletons are overridden with instances
  // built from the (mocked) prefs + secure storage. The geofence stream is
  // pinned to "disabled" (no fence configured) so the location plugin —
  // absent in tests — never locks the POS.
  Future<Widget> testApp() async {
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
      ],
      child: const StaffApp(),
    );
  }

  testWidgets('staff POS screen renders after a terminal ID is restored', (
    WidgetTester tester,
  ) async {
    seedSignedInSession();

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await testApp());
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

  testWidgets('terminal setup screen is shown before the POS unlocks', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await testApp());
    await tester.pumpAndSettle();

    // The unpaired device lands on the enrollment screen, never the POS.
    expect(find.text('Set up this device'), findsOneWidget);
    expect(find.text('Current Order'), findsNothing);
  });
}
