import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_machine/services/mosambee_payment_service.dart';

/// Money safety — a card charge that PROVABLY never reached the acquirer must
/// never be offered to the cashier as "Mark paid — pending reconciliation".
///
/// That prompt exists for genuinely AMBIGUOUS outcomes (an NFC timeout, where
/// the customer's card may really have been charged and the bank settlement
/// file will confirm it). Using it for a configuration failure — no terminal
/// assigned, SoftPOS app missing — would book card revenue that no settlement
/// file can ever match: invented money on a real order.
///
/// pos_handheld blocks this by refusing to start the charge without a terminal
/// id; these tests lock the equivalent guarantee into pos_machine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MosambeePaymentResult resultFor(Map<String, Object?> payload) =>
      MosambeePaymentResult.fromRaw(jsonEncode(payload));

  group('never-reached-the-terminal failures are NOT uncertain', () {
    test('missing terminal id', () {
      final r = resultFor({
        'stage': 'preflight',
        'status': 'failed',
        'code': 'MISSING_TERMINAL_ID',
        'message': 'Terminal ID is not set.',
      });

      expect(r.isSuccess, isFalse);
      expect(r.neverReachedTerminal, isTrue);
      expect(r.failurePhase, MosambeeFailurePhase.preDispatch);
      expect(r.isMissingTerminalId, isTrue);
      // The money-critical assertion: no force-record prompt.
      expect(r.isUncertain, isFalse);
    });

    test('SoftPOS app not installed', () {
      final r = resultFor({
        'status': 'failed',
        'message': 'Mosambee application is not installed.',
      });

      expect(r.neverReachedTerminal, isTrue);
      expect(r.failurePhase, MosambeeFailurePhase.preDispatch);
      expect(r.isUncertain, isFalse);
      expect(r.isMissingTerminalId, isFalse); // different remedy
    });

    test('payment activity not found', () {
      final r = resultFor({
        'status': 'failed',
        'message': 'Mosambee payment activity was not found.',
      });

      expect(r.neverReachedTerminal, isTrue);
      expect(r.failurePhase, MosambeeFailurePhase.preDispatch);
      expect(r.isUncertain, isFalse);
    });
  });

  group('genuinely ambiguous outcomes REMAIN uncertain', () {
    test('an NFC timeout still offers pending reconciliation', () {
      final r = resultFor({
        'status': 'failed',
        'message': 'Timeout waiting for card.',
      });

      expect(r.neverReachedTerminal, isFalse);
      expect(r.failurePhase, MosambeeFailurePhase.postDispatchUnknown);
      expect(r.isUncertain, isTrue, reason: 'the card may have been charged');
    });

    test('an empty terminal response stays uncertain', () {
      final r = MosambeePaymentResult.fromRaw('');

      expect(r.neverReachedTerminal, isFalse);
      expect(r.failurePhase, MosambeeFailurePhase.postDispatchUnknown);
      expect(r.isUncertain, isTrue);
    });
  });

  group('success and explicit cancel are unaffected', () {
    test('approved charge is a success', () {
      final r = resultFor({'status': 'success', 'rrn': 'RRN-1'});

      expect(r.isSuccess, isTrue);
      expect(r.isUncertain, isFalse);
      expect(r.neverReachedTerminal, isFalse);
      expect(r.softposReference, 'RRN-1');
    });

    test('customer cancelled at the terminal', () {
      final r = resultFor({'status': 'canceled'});

      expect(r.isCanceled, isTrue);
      expect(r.isUncertain, isFalse);
    });
  });

  group('no mutual recursion between isCanceled and userMessage', () {
    // Regression: isCanceled read userMessage, whose last-resort fallback
    // asked isCanceled — so any terminal response carrying a status but no
    // message field recursed until the stack overflowed. That is a crash in
    // the middle of taking a customer's money.
    test('a status-only cancel does not stack-overflow', () {
      final r = resultFor({'status': 'canceled'});

      expect(r.isCanceled, isTrue);
      expect(r.userMessage, 'Payment was canceled.');
    });

    test('a status-only failure does not stack-overflow', () {
      final r = resultFor({'status': 'failed'});

      expect(r.isCanceled, isFalse);
      expect(r.isUncertain, isTrue);
      expect(r.userMessage, 'Payment was not successful.');
    });

    test('a bare approval code response does not stack-overflow', () {
      final r = resultFor({'responseCode': '00', 'authCode': 'A1'});

      expect(r.isSuccess, isTrue);
      expect(r.userMessage, 'Payment approved.');
      expect(r.softposAuthCode, 'A1');
    });
  });

  group('preflight', () {
    const channel = MethodChannel('com.example.mosambee');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('an unassigned terminal never launches the SoftPOS app', () async {
      SharedPreferences.setMockInitialValues({}); // no terminal_id

      final invoked = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        invoked.add(call.method);
        return null;
      });

      final result = await MosambeePaymentService().payWithPreparedSession(1.5);

      expect(invoked, isEmpty, reason: 'must fail before touching the terminal');
      expect(result.isMissingTerminalId, isTrue);
      expect(result.isUncertain, isFalse);
    });
  });
}
