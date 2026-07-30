import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'local_storage_service.dart';

class MosambeePaymentResult {
  final String rawPayload;
  final Map<String, dynamic> payload;

  const MosambeePaymentResult({
    required this.rawPayload,
    required this.payload,
  });

  factory MosambeePaymentResult.fromRaw(String? rawPayload) {
    final safeRaw = rawPayload?.trim() ?? '';
    final decoded = _decodePayload(safeRaw);
    return MosambeePaymentResult(rawPayload: safeRaw, payload: decoded);
  }

  bool get isSuccess {
    final statusRaw = _lookupString(payload, const [
      'status',
      'result',
      'paymentStatus',
      'payment_status',
    ]).toLowerCase();

    final receiptResponse = _nestedMap(payload['receiptResponse']);
    final responseCode = _lookupString(payload, const [
      'paymentResponseCode',
      'responseCode',
    ]).trim();
    final receiptCode = _lookupString(receiptResponse, const [
      'responseCode',
      'paymentResponseCode',
    ]).trim();
    final receiptResult = _lookupString(receiptResponse, const [
      'result',
    ]).toLowerCase();

    return statusRaw == 'success' ||
        responseCode == '0' ||
        responseCode == '00' ||
        receiptCode == '0' ||
        receiptCode == '00' ||
        receiptResult == 'success';
  }

  bool get isCanceled {
    final statusRaw = _lookupString(payload, const [
      'status',
      'result',
      'paymentStatus',
      'payment_status',
    ]).toLowerCase();
    // _reportedMessage, NOT userMessage: userMessage's last-resort fallback
    // asks isCanceled, so using it here made the two recurse forever (a
    // stack overflow at the till) whenever the terminal answered without
    // any message field.
    final message = _reportedMessage.toLowerCase();

    return statusRaw == 'canceled' ||
        statusRaw == 'cancelled' ||
        message.contains('cancel');
  }

  /// This device has no bank terminal assigned — the one
  /// [neverReachedTerminal] case the cashier can act on (call the admin),
  /// so it gets its own localized message instead of the raw technical text.
  bool get isMissingTerminalId =>
      _lookupString(payload, const ['code']).toUpperCase() ==
      'MISSING_TERMINAL_ID';

  /// The charge PROVABLY never reached the acquirer — a configuration or
  /// launch failure (no terminal id, SoftPOS app missing, activity not
  /// found), not an ambiguous terminal verdict.
  ///
  /// This distinction is money-critical. [isUncertain] offers the cashier a
  /// "Mark paid — pending reconciliation" button, which books a card sale on
  /// the customer's behalf. That is right after an NFC timeout (the card may
  /// genuinely have been charged) and WRONG here: nothing was ever sent to
  /// the bank, so recording it would invent revenue that no settlement file
  /// can ever match.
  bool get neverReachedTerminal {
    final code = _lookupString(payload, const ['code']).toUpperCase();
    if (code == 'MISSING_TERMINAL_ID' || code == 'BAD_ARGS') return true;
    final message = _reportedMessage.toLowerCase();
    return message.contains('is not installed') ||
        message.contains('was not found') ||
        message.contains('unable to launch');
  }

  /// Neither a clear success nor an explicit cancel (e.g. an NFC timeout or an
  /// ambiguous terminal verdict). The cashier may force-record these as
  /// pending reconciliation rather than losing the sale — but only when the
  /// charge actually reached the terminal (see [neverReachedTerminal]).
  bool get isUncertain => !isSuccess && !isCanceled && !neverReachedTerminal;

  /// The native bridge had no pre-warmed login session to pay with (so the caller
  /// should fall back to a full login+pay).
  bool get isNoSession =>
      _lookupString(payload, const ['code']).toUpperCase() == 'NO_SESSION';

  /// The acquirer transaction reference (RRN / txn id) — the key the bank
  /// settlement file is matched on. Looks top-level and inside receiptResponse.
  String? get softposReference => _firstNonEmpty(const [
    'rrn',
    'retrievalReferenceNumber',
    'transactionId',
    'txnId',
    'paymentId',
    'invoiceNo',
    'invoiceNumber',
    'tid',
  ]);

  /// The card authorization / approval code.
  String? get softposAuthCode => _firstNonEmpty(const [
    'authCode',
    'approvalCode',
    'authorizationCode',
    'approvalNo',
  ]);

  /// Look [keys] up in the top-level payload, falling back to the nested
  /// receiptResponse. Returns null when none is present.
  String? _firstNonEmpty(List<String> keys) {
    final top = _lookupString(payload, keys);
    if (top.isNotEmpty) return top;
    final nested = _lookupString(_nestedMap(payload['receiptResponse']), keys);
    return nested.isEmpty ? null : nested;
  }

  /// The message the terminal ACTUALLY reported, with no derived fallback.
  /// [isCanceled] and [neverReachedTerminal] read this instead of
  /// [userMessage] so they can never recurse back into it.
  String get _reportedMessage {
    final message = _lookupString(payload, const [
      'paymentDescription',
      'message',
      'error',
      'errorMessage',
      'details',
    ]);
    if (message.isNotEmpty) return message;

    return _lookupString(_nestedMap(payload['receiptResponse']), const [
      'paymentDescription',
      'message',
      'error',
      'responseMessage',
      'responseDescription',
    ]);
  }

  String get userMessage {
    final reported = _reportedMessage;
    if (reported.isNotEmpty) return reported;

    return isSuccess
        ? 'Payment approved.'
        : isCanceled
        ? 'Payment was canceled.'
        : 'Payment was not successful.';
  }

  static Map<String, dynamic> _decodePayload(String rawPayload) {
    if (rawPayload.isEmpty) {
      return <String, dynamic>{
        'status': 'failed',
        'message': 'Empty payment response.',
      };
    }

    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}

    return <String, dynamic>{
      'status': 'failed',
      'raw': rawPayload,
      'message': rawPayload,
    };
  }

  static Map<String, dynamic> _nestedMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return const <String, dynamic>{};
  }

  static String _lookupString(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value == null) continue;
      final stringValue = value.toString().trim();
      if (stringValue.isNotEmpty && stringValue.toLowerCase() != 'null') {
        return stringValue;
      }
    }
    return '';
  }
}

class MosambeePaymentService {
  static const MethodChannel _platform = MethodChannel('com.example.mosambee');
  static bool _handlerInstalled = false;
  static void Function(Map<String, dynamic> event)? _launchStateListener;

  static const String appPackageName = 'com.mosambee.dhofar.softpos';
  static const String defaultTerminalPin = '1321';
  static const String partnerId = '';

  /// The Mosambee login PIN to use: the bank-issued per-device PIN cached
  /// under prefs 'terminal_pin' when set, else the [defaultTerminalPin].
  static String effectivePin(String? cached) =>
      (cached == null || cached.trim().isEmpty)
          ? defaultTerminalPin
          : cached.trim();

  MosambeePaymentService() {
    _ensureHandlerInstalled();
  }

  void setLaunchStateListener(
    void Function(Map<String, dynamic> event)? listener,
  ) {
    _launchStateListener = listener;
    _ensureHandlerInstalled();
  }

  Map<String, String> _loginArgs(String terminalId, String pin) => {
    'userName': terminalId,
    'pin': pin,
    'partnerId': partnerId,
    'packageName': appPackageName,
  };

  Map<String, String> _paymentArgs(double amountOmr) => {
    'packageName': appPackageName,
    'amount': (amountOmr * 1000).round().toString(),
    'mobNo': '',
    'description': 'Mithqal POS Order',
  };

  Future<String?>? _prepareInFlight;

  /// Pre-warm a Mosambee login session so the next card payment can skip the
  /// (slow) login. Best-effort and idempotent — it de-duplicates an in-flight
  /// warm-up and never throws.
  Future<void> prepareSession() async {
    final existing = _prepareInFlight;
    if (existing != null) {
      await existing.catchError((_) => null);
      return;
    }
    final future = _prepareSessionOnce();
    _prepareInFlight = future;
    try {
      await future;
    } catch (_) {
      // best-effort warm-up; ignore failures
    } finally {
      if (identical(_prepareInFlight, future)) _prepareInFlight = null;
    }
  }

  Future<String?> _prepareSessionOnce() async {
    final terminalId = (await LocalStorageService.getTerminalId())?.trim();
    if (terminalId == null || terminalId.isEmpty) {
      return null; // not configured — nothing to warm
    }
    final pin = MosambeePaymentService.effectivePin(
      await LocalStorageService.getTerminalPin(),
    );
    return _platform.invokeMethod<String>(
      'prepareLogin',
      _loginArgs(terminalId, pin),
    );
  }

  /// Pay using the pre-warmed session (fast — no login). Falls back to a full
  /// [loginAndPay] when no warm session is available (already consumed, expired,
  /// or never prepared), so a sale never fails just because the session lapsed.
  Future<MosambeePaymentResult> payWithPreparedSession(double amountOmr) async {
    // Preflight (mirrors pos_handheld's payment screen): a device with no
    // bank terminal assigned can never charge, so fail FAST and clearly
    // instead of launching the SoftPOS app to watch it reject us.
    final terminalId = (await LocalStorageService.getTerminalId())?.trim();
    if (terminalId == null || terminalId.isEmpty) {
      return MosambeePaymentResult.fromRaw(
        jsonEncode({
          'stage': 'preflight',
          'status': 'failed',
          'code': 'MISSING_TERMINAL_ID',
          'message': 'Terminal ID is not set.',
        }),
      );
    }

    // Let any in-flight pre-warm finish first, to avoid a native BUSY race.
    final inFlight = _prepareInFlight;
    if (inFlight != null) {
      await inFlight.catchError((_) => null);
    }

    try {
      final raw = await _platform.invokeMethod<String>(
        'payWithPreparedSession',
        _paymentArgs(amountOmr),
      );
      final result = MosambeePaymentResult.fromRaw(raw);
      if (result.isNoSession) {
        return loginAndPay(amountOmr);
      }
      return result;
    } on PlatformException catch (error) {
      if (error.code == 'BUSY') {
        return loginAndPay(amountOmr);
      }
      return MosambeePaymentResult.fromRaw(
        jsonEncode({
          'stage': 'flutter_platform',
          'status': 'failed',
          'code': error.code,
          'message': error.message,
          'details': error.details,
        }),
      );
    } catch (error) {
      return MosambeePaymentResult.fromRaw(
        jsonEncode({
          'stage': 'flutter',
          'status': 'failed',
          'error': error.toString(),
        }),
      );
    }
  }

  Future<MosambeePaymentResult> loginAndPay(double amountOmr) async {
    try {
      final terminalId = (await LocalStorageService.getTerminalId())?.trim();
      if (terminalId == null || terminalId.isEmpty) {
        throw PlatformException(
          code: 'MISSING_TERMINAL_ID',
          message: 'Terminal ID is not set.',
        );
      }

      final pin = MosambeePaymentService.effectivePin(
        await LocalStorageService.getTerminalPin(),
      );
      final result = await _platform.invokeMethod<String>('loginAndPay', {
        ..._loginArgs(terminalId, pin),
        ..._paymentArgs(amountOmr),
      });

      return MosambeePaymentResult.fromRaw(result);
    } on PlatformException catch (error) {
      return MosambeePaymentResult.fromRaw(
        jsonEncode({
          'stage': 'flutter_platform',
          'status': 'failed',
          'code': error.code,
          'message': error.message,
          'details': error.details,
        }),
      );
    } catch (error) {
      return MosambeePaymentResult.fromRaw(
        jsonEncode({
          'stage': 'flutter',
          'status': 'failed',
          'error': error.toString(),
        }),
      );
    }
  }

  static void _ensureHandlerInstalled() {
    if (_handlerInstalled) return;

    _platform.setMethodCallHandler((call) async {
      if (call.method != 'paymentLaunchState') return;

      final arguments = call.arguments;
      final event = arguments is Map
          ? Map<String, dynamic>.from(arguments)
          : <String, dynamic>{};
      debugPrint('MosambeePaymentService launch event: $event');
      _launchStateListener?.call(event);
    });
    _handlerInstalled = true;
  }
}
