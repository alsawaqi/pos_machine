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
    final message = userMessage.toLowerCase();

    return statusRaw == 'canceled' ||
        statusRaw == 'cancelled' ||
        message.contains('cancel');
  }

  /// Neither a clear success nor an explicit cancel (e.g. an NFC timeout or an
  /// ambiguous terminal verdict). The cashier may force-record these as
  /// pending reconciliation rather than losing the sale.
  bool get isUncertain => !isSuccess && !isCanceled;

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

  String get userMessage {
    final receiptResponse = _nestedMap(payload['receiptResponse']);

    final message = _lookupString(payload, const [
      'paymentDescription',
      'message',
      'error',
      'errorMessage',
      'details',
    ]);
    if (message.isNotEmpty) return message;

    final receiptMessage = _lookupString(receiptResponse, const [
      'paymentDescription',
      'message',
      'error',
      'responseMessage',
      'responseDescription',
    ]);
    if (receiptMessage.isNotEmpty) return receiptMessage;

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
  static const String terminalPin = '1321';
  static const String partnerId = '';

  MosambeePaymentService() {
    _ensureHandlerInstalled();
  }

  void setLaunchStateListener(
    void Function(Map<String, dynamic> event)? listener,
  ) {
    _launchStateListener = listener;
    _ensureHandlerInstalled();
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

      final result = await _platform.invokeMethod<String>('loginAndPay', {
        'userName': terminalId,
        'pin': terminalPin,
        'partnerId': partnerId,
        'packageName': appPackageName,
        'amount': (amountOmr * 1000).round().toString(),
        'mobNo': '',
        'description': 'Mithqal POS Order',
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
