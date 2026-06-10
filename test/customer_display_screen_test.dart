import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/screens/customer_display_screen.dart';

const rearChannel = MethodChannel('pos_machine/rear_display_channel');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(rearChannel, null);
  });

  testWidgets(
    'charity selection shows an immediate blocking overlay on the customer display',
    (tester) async {
      final charityDecisionCompleter = Completer<bool>();
      var charityDecisionCalls = 0;
      var touchTestCalls = 0;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(rearChannel, (call) async {
            if (call.method != 'customerEvent') {
              return true;
            }

            final arguments = Map<String, dynamic>.from(call.arguments as Map);
            if (arguments['type'] == 'charity_round_up_response') {
              charityDecisionCalls++;
              return charityDecisionCompleter.future;
            }

            if (arguments['type'] == 'customer_event') {
              touchTestCalls++;
              return true;
            }

            return true;
          });

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_localizedCustomerDisplayApp());
      await tester.pump();

      await _sendOrderSnapshot({
        'items': <Map<String, dynamic>>[],
        'subtotal': 1.500,
        'tax': 0.075,
        'total': 1.575,
        'payableTotal': 1.575,
        'paymentStatus': 'Awaiting customer',
        'paymentMethod': 'Credit Card',
        'note': 'Would you like to round up 0.425 OMR to charity?',
        'showCharityRoundUpPrompt': true,
        'showPaymentLaunchOverlay': false,
        'charityRoundUpAccepted': false,
        'charityRoundUpAmount': 0.425,
        'charityRoundUpTotal': 2.000,
      });
      await tester.pump();

      expect(find.text('No'), findsOneWidget);

      await tester.tap(find.text('No'));
      await tester.pump();

      expect(find.text('Processing Selection'), findsOneWidget);
      expect(charityDecisionCalls, 1);

      await tester.tap(find.text('Touch Test'), warnIfMissed: false);
      await tester.pump();

      expect(find.textContaining('Touch OK'), findsNothing);
      expect(charityDecisionCalls, 1);
      expect(touchTestCalls, 0);

      charityDecisionCompleter.complete(true);
    },
  );

  testWidgets(
    'pressing yes on the compact charity layout sends an accepted response',
    (tester) async {
      final charityDecisionCompleter = Completer<bool>();
      bool? acceptedValue;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(rearChannel, (call) async {
            if (call.method != 'customerEvent') {
              return true;
            }

            final arguments = Map<String, dynamic>.from(call.arguments as Map);
            if (arguments['type'] == 'charity_round_up_response') {
              acceptedValue = arguments['accepted'] == true;
              return charityDecisionCompleter.future;
            }

            return true;
          });

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_localizedCustomerDisplayApp());
      await tester.pump();

      await _sendOrderSnapshot({
        'items': <Map<String, dynamic>>[],
        'subtotal': 1.500,
        'tax': 0.075,
        'total': 1.575,
        'payableTotal': 1.575,
        'paymentStatus': 'Awaiting customer',
        'paymentMethod': 'Credit Card',
        'note': 'Would you like to round up 0.425 OMR to charity?',
        'showCharityRoundUpPrompt': true,
        'showPaymentLaunchOverlay': false,
        'charityRoundUpAccepted': false,
        'charityRoundUpAmount': 0.425,
        'charityRoundUpTotal': 2.000,
      });
      await tester.pump();

      await tester.tap(find.text('Yes'));
      await tester.pump();

      expect(acceptedValue, isTrue);
      expect(find.text('Processing Selection'), findsOneWidget);

      charityDecisionCompleter.complete(true);
    },
  );

  testWidgets(
    'charity prompt keeps the message, totals, and actions visible on the presentation layout',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_localizedCustomerDisplayApp());
      await tester.pump();

      await _sendOrderSnapshot({
        'items': <Map<String, dynamic>>[],
        'subtotal': 1.500,
        'tax': 0.075,
        'total': 1.575,
        'payableTotal': 1.575,
        'paymentStatus': 'Awaiting customer',
        'paymentMethod': 'Credit Card',
        'note': 'Would you like to round up 0.425 OMR to charity?',
        'showCharityRoundUpPrompt': true,
        'showPaymentLaunchOverlay': false,
        'charityRoundUpAccepted': false,
        'charityRoundUpAmount': 0.425,
        'charityRoundUpTotal': 2.000,
      });
      await tester.pump();

      expect(find.text('Round Up For Charity?'), findsOneWidget);
      expect(find.text('Order Total'), findsOneWidget);
      expect(find.text('Round Up'), findsOneWidget);
      expect(find.text('New Total'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tap-to-pay layout shows the payable total when charity round-up is accepted',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_localizedCustomerDisplayApp());
      await tester.pump();

      await _sendOrderSnapshot({
        'items': <Map<String, dynamic>>[],
        'subtotal': 1.500,
        'tax': 0.075,
        'total': 1.575,
        'payableTotal': 2.000,
        'paymentStatus': 'Processing payment',
        'paymentMethod': 'Credit Card',
        'note':
            'Thank you for rounding up for charity. Tap your card or phone on the rear NFC area to pay.',
        'showCharityRoundUpPrompt': false,
        'showPaymentLaunchOverlay': false,
        'charityRoundUpAccepted': true,
        'charityRoundUpAmount': 0.425,
        'charityRoundUpTotal': 2.000,
      });
      await tester.pump();

      expect(find.text('Total to pay'), findsOneWidget);
      expect(find.text('2.000 OMR'), findsOneWidget);
      expect(
        find.text('Includes 0.425 OMR charity round-up.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'customer display shows the animated payment overlay during Mosambee launch',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_localizedCustomerDisplayApp());
      await tester.pump();

      await _sendOrderSnapshot({
        'items': <Map<String, dynamic>>[],
        'subtotal': 1.500,
        'tax': 0.075,
        'total': 1.575,
        'payableTotal': 2.000,
        'paymentStatus': 'Preparing payment',
        'paymentMethod': 'Credit Card',
        'paymentOverlayTitle': 'Opening Payment Terminal',
        'note':
            'We are securely sending the rounded payment total to the card terminal.',
        'showCharityRoundUpPrompt': false,
        'showPaymentLaunchOverlay': true,
        'charityRoundUpAccepted': true,
        'charityRoundUpAmount': 0.425,
        'charityRoundUpTotal': 2.000,
      });
      await tester.pump();

      expect(find.text('Opening Payment Terminal'), findsOneWidget);
      expect(find.text('SECURE CARD PAYMENT'), findsOneWidget);
      expect(
        find.text(
          'We are securely sending the rounded payment total to the card terminal.',
        ),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'customer display shows add-ons and notes from the order snapshot',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_localizedCustomerDisplayApp());
      await tester.pump();

      await _sendOrderSnapshot({
        'items': <Map<String, dynamic>>[
          {
            'name': 'Latte',
            'qty': 1,
            'lineTotal': 3.700,
            'imageAsset': null,
            'detailLines': <String>[
              'Size (Required): Grande',
              'Milk Type: Oat (+0.500 OMR)',
              'Add-ons: Espresso Shot (+1.000 OMR)',
              'Notes: Less sugar',
            ],
            'notes': 'Less sugar',
          },
        ],
        'subtotal': 3.700,
        'tax': 0.185,
        'total': 3.885,
        'payableTotal': 3.885,
        'paymentStatus': 'Waiting',
        'paymentMethod': 'Cash',
        'note': '',
        'showCharityRoundUpPrompt': false,
        'showPaymentLaunchOverlay': false,
        'charityRoundUpAccepted': false,
        'charityRoundUpAmount': 0.000,
        'charityRoundUpTotal': 0.000,
      });
      await tester.pump();

      expect(find.text('Size (Required): Grande'), findsOneWidget);
      expect(find.text('Milk Type: Oat (+0.500 OMR)'), findsOneWidget);
      expect(find.text('Add-ons: Espresso Shot (+1.000 OMR)'), findsOneWidget);
      expect(find.text('Notes: Less sugar'), findsOneWidget);
    },
  );

  testWidgets('customer display defaults to low-cost rendering effects', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_localizedCustomerDisplayApp());
    await tester.pump();

    await _sendOrderSnapshot({
      'items': <Map<String, dynamic>>[
        {
          'id': 'item_1',
          'name': 'Item 1',
          'qty': 1,
          'lineTotal': 1.000,
          'imageAsset': null,
          'detailLines': <String>[],
          'notes': '',
        },
      ],
      'subtotal': 1.000,
      'tax': 0.050,
      'total': 1.050,
      'payableTotal': 1.050,
      'paymentStatus': 'Waiting',
      'paymentMethod': 'Cash',
      'note': '',
      'showCharityRoundUpPrompt': false,
      'showPaymentLaunchOverlay': false,
      'charityRoundUpAccepted': false,
      'charityRoundUpAmount': 0.000,
      'charityRoundUpTotal': 0.000,
    });
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets(
    'customer display accepts more than four order items',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_localizedCustomerDisplayApp());
      await tester.pump();

      final items = List.generate(5, (index) {
        return <String, dynamic>{
          'id': 'item_$index',
          'name': 'Item ${index + 1}',
          'qty': 1,
          'lineTotal': 1.000,
          'imageAsset': null,
          'detailLines': <String>[],
          'notes': '',
        };
      });

      await _sendOrderSnapshot({
        'items': items,
        'subtotal': 5.000,
        'tax': 0.250,
        'total': 5.250,
        'payableTotal': 5.250,
        'paymentStatus': 'Waiting',
        'paymentMethod': 'Cash',
        'note': '',
        'showCharityRoundUpPrompt': false,
        'showPaymentLaunchOverlay': false,
        'charityRoundUpAccepted': false,
        'charityRoundUpAmount': 0.000,
        'charityRoundUpTotal': 0.000,
      });
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('5 item lines in the current order'), findsOneWidget);
    },
  );
}

Widget _localizedCustomerDisplayApp() {
  return const MaterialApp(
    locale: Locale('en'),
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: L10n.localizationsDelegates,
    home: CustomerDisplayScreen(),
  );
}

Future<void> _sendOrderSnapshot(Map<String, dynamic> snapshot) async {
  final message = const StandardMethodCodec().encodeMethodCall(
    MethodCall('updateOrder', <String, dynamic>{
      'type': 'order_snapshot',
      ...snapshot,
    }),
  );

  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(rearChannel.name, message, (_) {});
}
