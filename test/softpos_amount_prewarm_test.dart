import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_machine/services/mosambee_payment_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.mosambee');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    SharedPreferences.setMockInitialValues({'terminal_id': 'T'});
    FlutterSecureStorage.setMockInitialValues({'terminal_pin': 'PIN'});
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test(
    'arithmetic noise reaches bridge as integer baisas; bad amount is DART_ERROR',
    () async {
      final amounts = <int>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        amounts.add(call.arguments['amountBaisas'] as int);
        return '{"responseCode":"00","rrn":"R"}';
      });
      final service = MosambeePaymentService();
      for (final value in [0.1 + 0.2, 5.565 - 0.5]) {
        final result = await service.payWithPreparedSession(value);
        expect(result.isSuccess, isTrue);
      }
      expect(amounts, [300, 5065]);
      final bad = await service.payWithPreparedSession(1.0001);
      expect(bad.payload['code'], 'DART_ERROR');
      expect(bad.neverReachedTerminal, isTrue);
      expect(bad.isUncertain, isFalse);
      expect(amounts, [300, 5065]);
    },
  );
  test(
    'pay waits for in-flight pre-warm and duplicate pre-warm has one login',
    () async {
      final login = Completer<String>();
      final started = Completer<void>();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'prepareLogin') {
          if (!started.isCompleted) started.complete();
          return login.future;
        }
        return '{"responseCode":"00","rrn":"R"}';
      });
      final service = MosambeePaymentService();
      final warm = service.prepareSession();
      await started.future;
      final duplicate = service.prepareSession();
      final pay = service.payWithPreparedSession(1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final before = List<String>.of(calls);
      login.complete('{"stage":"login","responseCode":"00","sessionId":"S"}');
      await warm;
      await duplicate;
      final result = await pay;
      expect(before, ['prepareLogin']);
      expect(result.isSuccess, isTrue);
      expect(calls, ['prepareLogin', 'payWithPreparedSession']);
    },
  );
}
