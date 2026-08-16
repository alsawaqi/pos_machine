import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_machine/services/mosambee_payment_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IMP-4 SoftPOS launch watchdog parity', () {
    const channel = MethodChannel('com.example.mosambee');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      SharedPreferences.setMockInitialValues({});
    });

    test('watchdog payload is never force-recordable', () {
      final result = MosambeePaymentResult.fromRaw(
        jsonEncode({
          'stage': 'payment',
          'status': 'failed',
          'code': 'SOFTPOS_NOT_RESPONDING',
          'message': 'Payment app not responding.',
        }),
      );

      expect(result.userMessage, 'Payment app not responding.');
      expect(result.neverReachedTerminal, isTrue);
      expect(result.isUncertain, isFalse);
    });

    test(
      'a bridge call with no result times out once and clears native state',
      () async {
        SharedPreferences.setMockInitialValues({'terminal_id': 'T-1'});
        final neverCompletes = Completer<String?>();
        final methods = <String>[];

        messenger.setMockMethodCallHandler(channel, (call) {
          methods.add(call.method);
          if (call.method == 'cancelPendingPayment') {
            return Future<Object?>.value(true);
          }
          return neverCompletes.future;
        });

        final result = await MosambeePaymentService(
          launchWatchdogTimeout: const Duration(milliseconds: 20),
        ).payWithPreparedSession(1.5);

        expect(methods, ['payWithPreparedSession', 'cancelPendingPayment']);
        expect(result.payload['code'], 'SOFTPOS_NOT_RESPONDING');
        expect(result.userMessage, 'Payment app not responding.');
        expect(result.neverReachedTerminal, isTrue);
        expect(result.isUncertain, isFalse);
      },
    );

    testWidgets(
      'background session preparation does not leave a Dart watchdog timer',
      (tester) async {
        SharedPreferences.setMockInitialValues({'terminal_id': 'T-1'});
        final neverCompletes = Completer<String?>();
        final methods = <String>[];

        messenger.setMockMethodCallHandler(channel, (call) {
          methods.add(call.method);
          return neverCompletes.future;
        });

        unawaited(
          MosambeePaymentService(
            launchWatchdogTimeout: const Duration(milliseconds: 20),
          ).prepareSession(),
        );
        await tester.pump();

        expect(methods, ['prepareLogin']);
      },
    );

    test('native callbacks are correlated to a unique active launch', () {
      final bridge = File(
        'android/app/src/main/kotlin/com/example/pos_machine/MosambeeBridge.kt',
      ).readAsStringSync();

      expect(bridge, contains('requestCode != activeRequestCode'));
      expect(bridge, contains('retiredRequestCodes.add(requestCode)'));
      expect(bridge, contains('retiredRequestCodes.remove(requestCode)'));
      expect(bridge, isNot(contains('LOGIN_REQUEST_CODE')));
      expect(bridge, isNot(contains('PAYMENT_REQUEST_CODE')));
    });
  });
}
