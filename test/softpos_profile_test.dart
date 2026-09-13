import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mithqal_softpos/mithqal_softpos.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/services/mosambee_payment_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secure = FlutterSecureStorage();
  const channel = MethodChannel('com.example.mosambee');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'legacy PIN migrates once and server null clears secure authority',
    () async {
      SharedPreferences.setMockInitialValues({
        'terminal_id': 'T',
        'terminal_pin': '9876',
      });
      final prefs = await SharedPreferences.getInstance();
      final local = SessionService(
        secure,
        await SharedPreferences.getInstance(),
      );
      await local.load();
      expect(local.terminalPin, '9876');
      expect(await secure.read(key: 'terminal_pin'), '9876');
      expect(prefs.containsKey('terminal_pin'), isFalse);
      await prefs.setString('terminal_pin', 'STALE');
      await local.load();
      expect(local.terminalPin, '9876');
      expect(prefs.containsKey('terminal_pin'), isFalse);
      await local.saveTerminalPin(null);
      expect(local.terminalPin, isNull);
      expect(await secure.read(key: 'terminal_pin'), isNull);
      expect(
        local.softpos.canPay(terminalId: 'T', terminalPin: local.terminalPin),
        isFalse,
      );
    },
  );

  test(
    'Muscat profile persists and sale receives package currency and exact baisas',
    () async {
      SharedPreferences.setMockInitialValues({'terminal_id': 'T'});
      await secure.write(key: 'terminal_pin', value: 'BANKPIN');
      final local = SessionService(
        secure,
        await SharedPreferences.getInstance(),
      );
      await local.load();
      await local.saveSoftpos(
        SoftPosProfile.fromJson({
          'provider': 'mosambee_muscat',
          'package': 'com.mosambee.muscat.softpos',
          'currency': '0512',
        }),
      );
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return '{"stage":"payment","responseCode":"00","rrn":"R"}';
      });

      final result = await MosambeePaymentService()
          .payWithPreparedSessionBaisas(4750);
      expect(result.isSuccess, isTrue);
      expect(
        calls.where((call) => call.method == 'payWithPreparedSession'),
        hasLength(1),
      );
      final args = calls.first.arguments as Map;
      expect(args['packageName'], 'com.mosambee.muscat.softpos');
      expect(args['currency'], '0512');
      expect(args['amountBaisas'], 4750);
      expect(args['pin'], 'BANKPIN');
      final restored = SessionService(
        secure,
        await SharedPreferences.getInstance(),
      );
      await restored.load();
      expect(restored.softpos.provider, 'mosambee_muscat');
    },
  );

  test(
    'BUSY is returned after exactly one channel launch, without login fallback',
    () async {
      SharedPreferences.setMockInitialValues({'terminal_id': 'T'});
      await secure.write(key: 'terminal_pin', value: 'PIN');
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        throw PlatformException(code: 'BUSY');
      });
      final result = await MosambeePaymentService()
          .payWithPreparedSessionBaisas(4750);
      expect(result.payload['code'], 'BUSY');
      expect(result.isUncertain, isTrue);
      expect(calls, ['payWithPreparedSession']);
    },
  );
  test(
    'empty financial payload is uncertain and failing login cannot retain a session',
    () async {
      SharedPreferences.setMockInitialValues({'terminal_id': 'T'});
      await secure.write(key: 'terminal_pin', value: 'PIN');
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'prepareLogin'
            ? '{"stage":"login","responseCode":"51","sessionId":"UNSAFE","resultCode":-1}'
            : '',
      );
      final result = await MosambeePaymentService()
          .payWithPreparedSessionBaisas(4750);
      expect(result.isSuccess, isFalse);
      expect(result.isUncertain, isTrue);
      final login = await MosambeePaymentService().invokeBank(
        'prepareLogin',
        {},
      );
      expect(login.verdict, SoftPosVerdict.declined);
      expect(login.sessionId, isNull);
    },
  );
  test('blocked profile prevents any sale channel call', () async {
    SharedPreferences.setMockInitialValues({'terminal_id': 'T'});
    await secure.write(key: 'terminal_pin', value: 'PIN');
    final local = SessionService(secure, await SharedPreferences.getInstance());
    await local.load();
    await local.saveSoftpos(
      SoftPosProfile.fromJson({
        'provider': 'mosambee_muscat',
        'blocked_reason': 'softpos_mismatch',
      }),
    );
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });

    final result = await MosambeePaymentService().payWithPreparedSessionBaisas(
      4750,
    );
    expect(result.isSuccess, isFalse);
    expect(calls, 0);
  });
}
