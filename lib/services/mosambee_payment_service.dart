import 'package:mithqal_softpos/mithqal_softpos.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'local_storage_service.dart';

/// Physical-dispatch truth used by flows where taking a second payment is the
/// dominant risk. This is deliberately separate from the legacy Phase 0
/// [MosambeePaymentResult.neverReachedTerminal] presentation policy.
enum MosambeeFailurePhase { none, preDispatch, postDispatchUnknown }

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

  SoftPosOutcome get outcome => SoftPosOutcome.fromPayload(payload);
  SoftPosReceiptIdentifiers get identifiers => outcome.identifiers;
  bool get isSuccess => outcome.verdict == SoftPosVerdict.approved;
  bool get isDeclined => outcome.verdict == SoftPosVerdict.declined;
  bool get isCanceled => outcome.verdict == SoftPosVerdict.cancelled;

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
    if (isSuccess) return false;
    final code = payload['code']?.toString().toUpperCase();
    if (code == 'SOFTPOS_NOT_RESPONDING') return false;
    if (code != 'BUSY' &&
        (payload['status'] == 'cancelled' || payload['status'] == 'canceled') &&
        isCanceled) {
      return false;
    }
    if (code == 'BUSY' ||
        payload['dispatch_failed'] == true ||
        payload['dispatchFailed'] == true) {
      return true;
    }
    if (isCanceled) return false;
    return const {
          'NO_SESSION',
          'BAD_ARGS',
          'NO_BRIDGE',
          'MISSING_TERMINAL_ID',
          'NO_TERMINAL_CREDENTIALS',
        }.contains(code) ||
        payload['dispatch_failed'] == true ||
        payload['dispatchFailed'] == true ||
        payload['stage'] == 'preflight' ||
        payload['stage'] == 'login';
  }

  /// Whether a failed result is proven to precede the payment intent, or may
  /// have happened after SoftPOS was dispatched.
  ///
  /// The 95-second watchdog is post-dispatch: best-effort native cancellation
  /// cannot undo a card tap that may already have completed, and the late
  /// activity result is discarded. QR settlement must therefore treat it as
  /// unknown even though the older Phase 0 UI deliberately suppresses its
  /// force-record action through [neverReachedTerminal].
  MosambeeFailurePhase get failurePhase {
    if (neverReachedTerminal) return MosambeeFailurePhase.preDispatch;
    if (isSuccess || isCanceled) return MosambeeFailurePhase.none;

    final code = _lookupString(payload, const ['code']).toUpperCase();
    if (code == 'SOFTPOS_NOT_RESPONDING') {
      return MosambeeFailurePhase.postDispatchUnknown;
    }

    return neverReachedTerminal
        ? MosambeeFailurePhase.preDispatch
        : MosambeeFailurePhase.postDispatchUnknown;
  }

  /// Neither a clear success nor an explicit cancel (e.g. an NFC timeout or an
  /// ambiguous terminal verdict). The cashier may force-record these as
  /// pending reconciliation rather than losing the sale — but only when the
  /// charge actually reached the terminal (see [neverReachedTerminal]).
  bool get isUncertain =>
      !isSuccess && !isDeclined && !isCanceled && !neverReachedTerminal;

  /// The native bridge had no pre-warmed login session to pay with (so the caller
  /// should fall back to a full login+pay).
  /// BUSY refuses this attempt before dispatch; force-record stays refused.
  bool get isTerminalBusy =>
      payload['code']?.toString().toUpperCase() == 'BUSY';

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
        'status': 'uncertain',
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
      'status': 'uncertain',
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

class _SoftPosNotRespondingException implements Exception {
  const _SoftPosNotRespondingException();
}

class MosambeePaymentService {
  static const MethodChannel _platform = MethodChannel('com.example.mosambee');
  static bool _handlerInstalled = false;
  static void Function(Map<String, dynamic> event)? _launchStateListener;

  static const String appPackageName = 'com.mosambee.dhofar.softpos';
  static const String partnerId = '';
  static const Duration defaultLaunchWatchdogTimeout = Duration(seconds: 95);

  /// The Mosambee login PIN to use: the bank-issued per-device PIN cached
  /// under prefs 'terminal_pin' when set, else the [defaultTerminalPin].
  static String effectivePin(String? cached) => cached?.trim() ?? '';

  MosambeePaymentService({
    this.launchWatchdogTimeout = defaultLaunchWatchdogTimeout,
  }) {
    _ensureHandlerInstalled();
  }

  final Duration launchWatchdogTimeout;

  void setLaunchStateListener(
    void Function(Map<String, dynamic> event)? listener,
  ) {
    _launchStateListener = listener;
    _ensureHandlerInstalled();
  }

  SoftPosProfile _profile = const SoftPosProfile();

  Map<String, dynamic> _loginArgs(String terminalId, String pin) => {
    'userName': terminalId,
    'pin': pin,
    'partnerId': partnerId,
    ..._profile.channelArguments,
  };

  Map<String, dynamic> _paymentArgsBaisas(int amountBaisas) => {
    ..._profile.channelArguments,
    'amount': amountBaisas.toString(),
    'amountBaisas': amountBaisas,
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
    _profile = await LocalStorageService.getSoftposProfile();
    final terminalId = (await LocalStorageService.getTerminalId())?.trim();
    if (terminalId == null || terminalId.isEmpty) {
      return null; // not configured — nothing to warm
    }
    final pin = MosambeePaymentService.effectivePin(
      await LocalStorageService.getTerminalPin(),
    );
    if (!_profile.canPay(terminalId: terminalId, terminalPin: pin)) return null;
    // Native owns the background pre-warm watchdog. Starting a 95-second Dart
    // timer here would outlive screens/tests that intentionally fire-and-forget
    // this best-effort warm-up. The payment path applies its own bounded wait
    // before it ever depends on this future.
    return _platform.invokeMethod<String>(
      'prepareLogin',
      _loginArgs(terminalId, pin),
    );
  }

  /// Pay using the pre-warmed session (fast — no login). Falls back to a full
  /// [loginAndPay] when no warm session is available (already consumed, expired,
  /// or never prepared), so a sale never fails just because the session lapsed.
  Future<MosambeePaymentResult> payWithPreparedSession(double amountOmr) async {
    try {
      return await payWithPreparedSessionBaisas(omrToBaisas(amountOmr));
    } catch (error) {
      return _dispatchFailure('flutter', 'DART_ERROR', error.toString());
    }
  }

  /// Integer-baisas entrypoint for server-priced QR settlements. Keeping the
  /// amount in its wire unit avoids an unnecessary baisas→double OMR→baisas
  /// round-trip before the native bridge.
  Future<MosambeePaymentResult> payWithPreparedSessionBaisas(
    int amountBaisas,
  ) async {
    // Preflight (mirrors pos_handheld's payment screen): a device with no
    // bank terminal assigned can never charge, so fail FAST and clearly
    // instead of launching the SoftPOS app to watch it reject us.
    _profile = await LocalStorageService.getSoftposProfile();
    final terminalId = (await LocalStorageService.getTerminalId())?.trim();
    if (terminalId == null || terminalId.isEmpty) {
      return MosambeePaymentResult.fromRaw(
        jsonEncode({
          'stage': 'preflight',
          'status': 'uncertain',
          'code': 'MISSING_TERMINAL_ID',
          'message': 'Terminal ID is not set.',
        }),
      );
    }

    baisasToOmr(amountBaisas);
    final pin = await LocalStorageService.getTerminalPin();
    final reason = _profile.unavailableReason(
      terminalId: terminalId,
      terminalPin: pin,
    );
    if (reason != null) {
      return _dispatchFailure('preflight', 'NO_TERMINAL_CREDENTIALS', reason);
    }
    // Let any in-flight pre-warm finish first, to avoid a native BUSY race.
    final inFlight = _prepareInFlight;
    if (inFlight != null) {
      try {
        await _awaitInFlightPreparation(inFlight);
      } on _SoftPosNotRespondingException {
        return _notRespondingFailure();
      }
    }

    try {
      final raw = await _invokeWithLaunchWatchdog<String>(
        'payWithPreparedSession',
        {..._loginArgs(terminalId, pin!), ..._paymentArgsBaisas(amountBaisas)},
      );
      final result = MosambeePaymentResult.fromRaw(raw);
      if (result.isNoSession) {
        return await loginAndPayBaisas(amountBaisas);
      }
      return result;
    } on _SoftPosNotRespondingException {
      return _notRespondingFailure();
    } on PlatformException catch (error) {
      return _dispatchFailure(
        'flutter_platform',
        error.code,
        error.message,
        details: error.details,
      );
    } on MissingPluginException catch (error) {
      return _dispatchFailure('flutter_platform', 'NO_BRIDGE', error.message);
    } catch (error) {
      return _dispatchFailure('flutter', 'DART_ERROR', error.toString());
    }
  }

  Future<void> _awaitInFlightPreparation(Future<String?> inFlight) async {
    try {
      await inFlight.timeout(launchWatchdogTimeout);
    } on TimeoutException {
      await _clearNativePendingPayment();
      if (identical(_prepareInFlight, inFlight)) {
        _prepareInFlight = null;
      }
      throw const _SoftPosNotRespondingException();
    } catch (_) {
      // Best-effort pre-warm failures fall through to the normal payment path.
    }
  }

  /// A failure raised on the DART side of the channel, i.e. before the native
  /// bridge dispatched anything to the SoftPOS app. The bridge only calls
  /// `result.error()` ahead of `startActivityForResult`, so these payloads
  /// provably represent a card that was never charged — [dispatch_failed]
  /// says exactly that, so the classification does not depend on anyone
  /// remembering to add each new error code to a list.
  MosambeePaymentResult _dispatchFailure(
    String stage,
    String code,
    String? message, {
    Object? details,
  }) => MosambeePaymentResult.fromRaw(
    jsonEncode({
      'stage': stage,
      'status': 'uncertain',
      'dispatch_failed': const {
        'BAD_ARGS',
        'NO_BRIDGE',
        'MISSING_TERMINAL_ID',
        'NO_TERMINAL_CREDENTIALS',
        'DART_ERROR',
      }.contains(code),
      'code': code,
      'message': message,
      'details': ?details,
    }),
  );

  /// Waits for exactly one native activity result. If the SoftPOS activity
  /// never returns, the cashier flow resolves once and asks native to release
  /// its pending MethodChannel result so later attempts are not stuck BUSY.
  Future<T?> _invokeWithLaunchWatchdog<T>(
    String method,
    Object? arguments,
  ) async {
    try {
      return await _platform
          .invokeMethod<T>(method, arguments)
          .timeout(launchWatchdogTimeout);
    } on TimeoutException {
      await _clearNativePendingPayment();
      throw const _SoftPosNotRespondingException();
    }
  }

  /// Best-effort and independently bounded: a stuck native bridge must not
  /// turn the watchdog itself into another indefinite wait.
  Future<void> _clearNativePendingPayment() async {
    try {
      await _platform
          .invokeMethod<bool>('cancelPendingOperation')
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  MosambeePaymentResult _notRespondingFailure() =>
      MosambeePaymentResult.fromRaw(
        jsonEncode({
          'stage': 'watchdog',
          'status': 'uncertain',
          'code': 'SOFTPOS_NOT_RESPONDING',
          'message': 'Payment app not responding.',
        }),
      );

  Future<MosambeePaymentResult> loginAndPay(double amountOmr) async {
    try {
      return await loginAndPayBaisas(omrToBaisas(amountOmr));
    } catch (error) {
      return _dispatchFailure('flutter', 'DART_ERROR', error.toString());
    }
  }

  Future<MosambeePaymentResult> loginAndPayBaisas(int amountBaisas) async {
    try {
      _profile = await LocalStorageService.getSoftposProfile();
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
      baisasToOmr(amountBaisas);
      final reason = _profile.unavailableReason(
        terminalId: terminalId,
        terminalPin: pin,
      );
      if (reason != null) {
        return _dispatchFailure('preflight', 'NO_TERMINAL_CREDENTIALS', reason);
      }
      final result = await _invokeWithLaunchWatchdog<String>('loginAndPay', {
        ..._loginArgs(terminalId, pin),
        ..._paymentArgsBaisas(amountBaisas),
      });

      return MosambeePaymentResult.fromRaw(result);
    } on _SoftPosNotRespondingException {
      return _notRespondingFailure();
    } on PlatformException catch (error) {
      return _dispatchFailure(
        'flutter_platform',
        error.code,
        error.message,
        details: error.details,
      );
    } on MissingPluginException catch (error) {
      return _dispatchFailure('flutter_platform', 'NO_BRIDGE', error.message);
    } catch (error) {
      return _dispatchFailure('flutter', 'DART_ERROR', error.toString());
    }
  }

  Future<SoftPosOutcome> checkTerminal() async {
    final profile = await LocalStorageService.getSoftposProfile();
    return invokeBank('healthCheck', profile.channelArguments);
  }

  Future<SoftPosOutcome> invokeBank(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    final profile = await LocalStorageService.getSoftposProfile();
    final userName = await LocalStorageService.getTerminalId();
    final pin = await LocalStorageService.getTerminalPin();
    try {
      return SoftPosOutcome.fromRaw(
        await _invokeWithLaunchWatchdog<String>(method, {
          ...profile.channelArguments,
          'userName': userName,
          'pin': pin,
          ...arguments,
        }),
      );
    } on _SoftPosNotRespondingException {
      return SoftPosOutcome.fromPayload(_notRespondingFailure().payload);
    } on PlatformException catch (error) {
      return SoftPosOutcome.fromPayload({
        'code': error.code,
        'status': 'cancelled',
        'dispatchFailed': true,
        'description': error.message,
      });
    } on MissingPluginException catch (error) {
      return SoftPosOutcome.fromPayload({
        'code': 'NO_BRIDGE',
        'status': 'cancelled',
        'dispatchFailed': true,
        'description': error.message,
      });
    } catch (_) {
      return SoftPosOutcome.fromPayload({'status': 'uncertain'});
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
