import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import 'package:pos_machine/main.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalOrderStorageService.instance.clearAllData();
  });

  testWidgets('staff POS screen renders after a terminal ID is restored', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'terminal_id': 'TERM-1001'});

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const StaffApp());
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
    SharedPreferences.setMockInitialValues({'terminal_id': 'TERM-1001'});

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const StaffApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('payment page opens from process to pay', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'terminal_id': 'TERM-1001'});

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const StaffApp());
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
    SharedPreferences.setMockInitialValues({'terminal_id': 'TERM-1001'});

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const StaffApp());
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
    SharedPreferences.setMockInitialValues({'terminal_id': 'TERM-1001'});

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const StaffApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Process to Pay'));
    await tester.pumpAndSettle();

    expect(find.text('Order Required'), findsOneWidget);
    expect(find.text('Add at least one item before paying.'), findsOneWidget);
  });

  testWidgets('cash keypad accepts decimal amounts and updates change', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'terminal_id': 'TERM-1001'});

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const StaffApp());
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
      SharedPreferences.setMockInitialValues({'terminal_id': 'TERM-1001'});

      const paymentChannel = MethodChannel('com.example.mosambee');
      final paymentCompleter = Completer<String>();
      var loginStarted = false;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paymentChannel, (call) async {
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

      await tester.pumpWidget(const StaffApp());
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
    },
  );

  testWidgets(
    'customer reference number is not sent with the card payment request',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'terminal_id': 'TERM-1001'});

      const paymentChannel = MethodChannel('com.example.mosambee');
      String? sentMobNo;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paymentChannel, (call) async {
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

      await tester.pumpWidget(const StaffApp());
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
    },
  );

  testWidgets(
    'customized add-ons appear in current order and payment summary',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'terminal_id': 'TERM-1001'});

      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const StaffApp());
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
    SharedPreferences.setMockInitialValues({'terminal_id': 'TERM-1001'});

    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const StaffApp());
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

    await tester.pumpWidget(const StaffApp());
    await tester.pumpAndSettle();

    expect(find.text('Connect This POS Terminal'), findsOneWidget);
    expect(find.text('Terminal ID'), findsOneWidget);
    expect(find.text('Continue To POS'), findsOneWidget);
  });
}
