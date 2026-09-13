import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/services/mosambee_payment_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({'terminal_pin':'TESTPIN'}));
  const channel = MethodChannel('com.example.mosambee');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'QR SoftPOS bridge forwards server baisas as an exact integer string',
    () async {
      SharedPreferences.setMockInitialValues({'terminal_id': 'TERM-1001'});
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            captured = call;
            return '{"status":"success","responseCode":"00","rrn":"RRN-1"}';
          });

      // Deliberately above IEEE-754's exact-integer boundary. This is not a real
      // sale size; it makes any accidental int→double OMR→int regression visible.
      const baisas = 9007199254740993;
      final result = await MosambeePaymentService()
          .payWithPreparedSessionBaisas(baisas);

      expect(result.isSuccess, isTrue);
      expect(captured?.method, 'payWithPreparedSession');
      final arguments = Map<String, dynamic>.from(captured?.arguments as Map);
      expect(arguments['amount'], '9007199254740993');
    },
  );
}
