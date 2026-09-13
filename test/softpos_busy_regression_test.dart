import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_machine/services/mosambee_payment_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'PAY002 BUSY makes exactly one launch and requires a manager check',
    () async {
      FlutterSecureStorage.setMockInitialValues({'terminal_pin': 'TESTPIN'});
      SharedPreferences.setMockInitialValues({
        'terminal_id': 'TEST',
        'terminal_pin': 'TESTPIN',
      });

      const channel = MethodChannel('com.example.mosambee');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        throw PlatformException(code: 'BUSY', message: 'Busy');
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final result = await MosambeePaymentService().payWithPreparedSession(
        4.750,
      );
      expect(calls, [
        'payWithPreparedSession',
      ], reason: 'No automatic loginAndPay: $calls');
      expect(result.payload['code'], 'BUSY');
      expect(result.isUncertain, isTrue);
    },
  );
}
