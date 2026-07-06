import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_machine/services/mosambee_payment_service.dart';
import 'package:pos_machine/services/session_service.dart';

/// Per-device Mosambee terminal PIN — the bank-issued login PIN that pos_api
/// delivers beside terminal_id (config meta + activation payload). The device
/// caches it under prefs 'terminal_pin' and uses it as the Mosambee login
/// 'pin' arg; a missing/blank cache falls back to the factory default '1321'.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MosambeePaymentService.effectivePin', () {
    test('falls back to the default when the cache is null', () {
      expect(MosambeePaymentService.effectivePin(null),
          MosambeePaymentService.defaultTerminalPin);
      expect(MosambeePaymentService.effectivePin(null), '1321');
    });

    test('falls back to the default when the cache is empty', () {
      expect(MosambeePaymentService.effectivePin(''), '1321');
    });

    test('falls back to the default on a whitespace-only cache', () {
      expect(MosambeePaymentService.effectivePin('  '), '1321');
    });

    test('returns the cached per-device PIN when set', () {
      expect(MosambeePaymentService.effectivePin('9876'), '9876');
    });

    test('trims a padded cached PIN', () {
      expect(MosambeePaymentService.effectivePin(' 9876 '), '9876');
    });
  });

  group('Mosambee login pin flow (com.example.mosambee channel)', () {
    const channel = MethodChannel('com.example.mosambee');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    /// Installs a mock handler that records the args of [method] and answers
    /// with an approved-payment payload.
    Map<String, dynamic> captureArgsOf(String method) {
      final captured = <String, dynamic>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == method) {
          captured.addAll(Map<String, dynamic>.from(call.arguments as Map));
          return '{"status":"success","message":"Payment approved."}';
        }
        return null;
      });
      return captured;
    }

    test('loginAndPay sends the default PIN when prefs hold no terminal_pin',
        () async {
      SharedPreferences.setMockInitialValues({'terminal_id': 'TERM-1001'});
      final args = captureArgsOf('loginAndPay');

      final result = await MosambeePaymentService().loginAndPay(1.575);

      expect(result.isSuccess, isTrue);
      expect(args['userName'], 'TERM-1001');
      expect(args['pin'], '1321');
    });

    test('loginAndPay sends the cached per-device terminal PIN when set',
        () async {
      SharedPreferences.setMockInitialValues({
        'terminal_id': 'TERM-1001',
        'terminal_pin': '9876',
      });
      final args = captureArgsOf('loginAndPay');

      final result = await MosambeePaymentService().loginAndPay(2.000);

      expect(result.isSuccess, isTrue);
      expect(args['pin'], '9876');
    });

    test('prepareSession pre-warms the login with the cached terminal PIN',
        () async {
      SharedPreferences.setMockInitialValues({
        'terminal_id': 'TERM-1001',
        'terminal_pin': '9876',
      });
      final args = captureArgsOf('prepareLogin');

      await MosambeePaymentService().prepareSession();

      expect(args['userName'], 'TERM-1001');
      expect(args['pin'], '9876');
    });

    test('prepareSession falls back to the default PIN when none is cached',
        () async {
      SharedPreferences.setMockInitialValues({'terminal_id': 'TERM-1001'});
      final args = captureArgsOf('prepareLogin');

      await MosambeePaymentService().prepareSession();

      expect(args['pin'], '1321');
    });
  });

  group('SessionService.saveTerminalPin', () {
    test('stores a trimmed PIN and exposes it on the snapshot', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final session = SessionService(const FlutterSecureStorage(), prefs);

      await session.saveTerminalPin('  9876 ');

      expect(prefs.getString('terminal_pin'), '9876');
      expect(session.terminalPin, '9876');
      expect(session.snapshot().terminalPin, '9876');
    });

    test('null CLEARS the cached PIN (unlike saveTerminalId keep-last-known)',
        () async {
      SharedPreferences.setMockInitialValues({
        'terminal_id': 'TERM-1001',
        'terminal_pin': '9876',
      });
      final prefs = await SharedPreferences.getInstance();
      final session = SessionService(const FlutterSecureStorage(), prefs);

      // Contrast pinned on purpose: terminal_id keeps the last-known value on
      // a null refresh, but a null terminal_pin means the admin cleared it —
      // the device must revert to the default.
      await session.saveTerminalId(null);
      await session.saveTerminalPin(null);

      expect(prefs.getString('terminal_id'), 'TERM-1001');
      expect(prefs.getString('terminal_pin'), isNull);
      expect(session.terminalPin, isNull);
    });

    test('empty/whitespace also clears the cached PIN', () async {
      SharedPreferences.setMockInitialValues({'terminal_pin': '9876'});
      final prefs = await SharedPreferences.getInstance();
      final session = SessionService(const FlutterSecureStorage(), prefs);

      await session.saveTerminalPin('   ');

      expect(prefs.getString('terminal_pin'), isNull);
    });
  });
}
