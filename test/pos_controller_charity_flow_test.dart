import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_machine/state/pos_controller.dart';

const _frontChannelName = 'pos_machine/front_display_channel';
const _codec = StandardMethodCodec();
const _androidOnly = TargetPlatformVariant(<TargetPlatform>{
  TargetPlatform.android,
});

Future<void> _sendCustomerDecision({required bool accepted}) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        _frontChannelName,
        _codec.encodeMethodCall(
          MethodCall(
            'customerEvent',
            {
              'type': 'charity_round_up_response',
              'accepted': accepted,
            },
          ),
        ),
        (_) {},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const hostChannel = MethodChannel('pos_machine/rear_display_host');
  const paymentChannel = MethodChannel('com.example.mosambee');
  const printerChannel = MethodChannel('sunmi_printer_plus');

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'terminal_id': 'TERM-1001',
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hostChannel, (call) async {
          switch (call.method) {
            case 'getPresentationDisplays':
              return <Map<String, dynamic>>[];
            case 'openRearDisplay':
              return true;
            case 'hideRearDisplay':
              return true;
            case 'transferDataToRear':
              return true;
            default:
              return null;
          }
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(printerChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hostChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paymentChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(printerChannel, null);
  });

  testWidgets('accepting the charity round-up launches payment with the rounded total', (
    tester,
  ) async {
    String? sentAmount;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paymentChannel, (call) async {
          if (call.method == 'loginAndPay') {
            final arguments = Map<String, dynamic>.from(call.arguments as Map);
            sentAmount = arguments['amount']?.toString();
            return '{"status":"success","message":"Payment approved."}';
          }
          return null;
        });

    final controller = PosController();
    addTearDown(controller.dispose);

    await controller.init();
    controller.addProduct(controller.allProducts.first);
    controller.selectPaymentMethod('Credit Card');

    final paymentFuture = controller.payAndPrint();
    await tester.pump();

    expect(controller.showCharityRoundUpPrompt, isTrue);
    expect(controller.charityRoundUpAmount, closeTo(0.425, 0.0001));

    await _sendCustomerDecision(accepted: true);
    await tester.pump(const Duration(milliseconds: 800));

    final message = await paymentFuture;
    expect(sentAmount, '2000');
    expect(message, contains('Payment approved.'));
  }, variant: _androidOnly);

  testWidgets('declining the charity round-up still launches payment with the original total', (
    tester,
  ) async {
    String? sentAmount;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paymentChannel, (call) async {
          if (call.method == 'loginAndPay') {
            final arguments = Map<String, dynamic>.from(call.arguments as Map);
            sentAmount = arguments['amount']?.toString();
            return '{"status":"success","message":"Payment approved."}';
          }
          return null;
        });

    final controller = PosController();
    addTearDown(controller.dispose);

    await controller.init();
    controller.addProduct(controller.allProducts.first);
    controller.selectPaymentMethod('Credit Card');

    final paymentFuture = controller.payAndPrint();
    await tester.pump();

    expect(controller.showCharityRoundUpPrompt, isTrue);

    await _sendCustomerDecision(accepted: false);
    await tester.pump(const Duration(milliseconds: 800));

    final message = await paymentFuture;
    expect(sentAmount, '1575');
    expect(message, contains('Payment approved.'));
  }, variant: _androidOnly);
}
