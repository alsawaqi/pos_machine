import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithqal_softpos/mithqal_softpos.dart';
import 'package:pos_machine/state/card_reversal_controller.dart';
import 'package:pos_machine/services/mosambee_payment_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final refusal in [
    'declined login',
    'empty login',
    'BUSY',
    'NO_BRIDGE',
    'NO_SESSION',
  ]) {
    test('$refusal cancels reservation with no slip or recovery', () async {
      SharedPreferences.setMockInitialValues({'terminal_id': 'T'});
      FlutterSecureStorage.setMockInitialValues({'terminal_pin': 'PIN'});

      final calls = <String>[];
      final reports = <Map<String, dynamic>>[];
      var prints = 0;
      const channel = MethodChannel('com.example.mosambee');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (refusal == 'BUSY') {
          throw PlatformException(code: 'BUSY', message: 'Busy');
        }
        if (refusal == 'NO_BRIDGE') throw MissingPluginException('Absent');
        if (refusal == 'NO_SESSION') {
          return '{"code":"NO_SESSION","status":"uncertain","dispatchFailed":true}';
        }
        if (refusal == 'empty login') return '{}';
        return '{"stage":"login","responseCode":"05","sessionId":"UNSAFE","resultCode":-1,"description":"Declined login"}';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final service = MosambeePaymentService();
      final c = CardReversalController(
        profile: const SoftPosProfile(),
        verifyManager: (_) async => 'Manager',
        bank: service.invokeBank,
        printSlip: (_) async {
          prints++;
          return true;
        },
        request: (_, path, body) async {
          if (path.endsWith('/result')) {
            reports.add(Map.of(body!));
            return {'status': body['status']};
          }
          return {
            'reversal_uuid': 'R',
            'kind': 'void',
            'amount_baisas': 1000,
            'currency': '0512',
            'original_transaction_id': 'T',
            'softpos': {
              'package': 'com.mosambee.muscat.softpos',
              'needs_session': refusal.contains('login'),
            },
          };
        },
      );
      addTearDown(c.dispose);
      await c.execute(
        payment: {'payment_uuid': 'P', 'can_void': true},
        kind: 'void',
        managerPin: 'PIN',
        voidReasonId: 1,
        confirmAmount: (_, _) async => true,
      );
      expect(calls, [
        refusal.contains('login') ? 'prepareLogin' : 'voidTransaction',
      ]);
      expect(reports.single['status'], 'cancelled');
      if (refusal == 'declined login') {
        expect(reports.single['response_code'], '05');
        expect(reports.single['description'], 'Declined login');
      }
      expect(c.needsRecovery, isFalse);
      expect(c.slip, isEmpty);
      expect(prints, 0);
      await c.reprint();
      expect(prints, 0);
    });
  }
}
