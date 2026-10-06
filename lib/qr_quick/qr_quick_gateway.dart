import 'dart:convert';
import 'qr_expired_cancel.dart';
import 'qr_payment_review.dart';
import '../qr_checkout/payment_review_store.dart';
import '../services/pos_api_service.dart';
import '../services/row_parsing.dart';
import 'qr_quick_controller.dart';
import 'qr_quick_models.dart';

String quickDeviceScope(
  String baseUrl,
  int? companyId,
  int? branchId,
  String? kioskId,
) {
  if (companyId == null ||
      companyId < 1 ||
      branchId == null ||
      branchId < 1 ||
      kioskId == null ||
      kioskId.isEmpty) {
    throw const QrQuickFailure('identity_changed', 'Missing device identity');
  }
  return jsonEncode([
    baseUrl.replaceFirst(RegExp(r'/+$'), ''),
    companyId,
    branchId,
    kioskId,
  ]);
}

/// Uses the app's existing authenticated client; never a server lookup for prices.
class ApiQrQuickGateway
    implements
        QrQuickGateway,
        QrQuickWorkspaceGateway,
        QrQuickCancellationGateway,
        QrQuickPaymentReviewGateway {
  ApiQrQuickGateway(
    this.api,
    this.currentScope, {
    this.mutationGuard,
    this.cancellationGuard,
    this.localPaymentOrders,
    this.loadPaymentEvidence,
    this.recordPaymentReview,
    this.currentGps,
  }) : scope = currentScope(),
       token = api.tokenGetter();
  final PosApiService api;
  final String Function() currentScope;
  final String scope;
  final String? token;
  final Future<void> Function()? mutationGuard;
  final Future<void> Function(String)? cancellationGuard;
  final Future<Set<String>> Function()? localPaymentOrders;
  final Future<PaymentReviewEvidence> Function(String)? loadPaymentEvidence;
  final Future<void> Function(
    String uuid,
    PaymentReviewEvidence evidence,
    String requestId,
    Map<String, dynamic> result,
  )?
  recordPaymentReview;
  final Future<Map<String, double>?> Function()? currentGps;
  final _cancellationReviews = <String, List<String>>{};
  void _check() {
    if (token == null ||
        token!.isEmpty ||
        api.tokenGetter() != token ||
        currentScope() != scope) {
      throw const QrQuickFailure('identity_changed', 'Device context changed');
    }
  }

  Future<T> _call<T>(Future<T> Function() action, {bool writes = false}) async {
    _check();
    try {
      if (writes) await mutationGuard?.call();
      _check();
      final result = await action();
      _check();
      return result;
    } on ApiException catch (error) {
      // A structured no-write response can release a NEW request only.
      // Unknown errors and transport/5xx keep its original persisted identity.
      final status = error.statusCode ?? 0;
      throw QrQuickFailure(
        error.code ?? 'refresh',
        error.message,
        refused:
            !error.isNetwork &&
            status >= 400 &&
            status < 500 &&
            const {
              'order_changed',
              'transfer_unavailable',
              'order_not_found',
              'device_not_attended',
              'order_not_editable',
              'charge_already_claimed',
              'qr_charge_recovery_required',
              'validation_failed',
              'client_priced_payload_rejected',
              'product_unavailable',
              'addon_unavailable',
              'addon_selection_invalid',
              'invalid_catalogue_line',
            }.contains(error.code),
      );
    }
  }

  @override
  Future<Map<String, dynamic>> previewCancel(String? uuid) async {
    _check();
    var result = await api.previewExpiredQuickCancellation(uuid);
    _check();
    // A bulk review must not fail because one order's local payment evidence
    // needs review: leave those orders out (never cancelled) and review the rest.
    final leftOut = <Map<String, String>>[];
    if (uuid == null) {
      for (final row in (result['orders'] as List).map(qrMap)) {
        try {
          await cancellationGuard?.call(row['uuid'] as String);
        } on StateError catch (error) {
          leftOut.add({
            'uuid': row['uuid'] as String,
            'reference': row['reference'] as String,
            'reason': error.message,
          });
        }
        _check();
      }
      if (leftOut.isNotEmpty) {
        result = await api.previewExpiredQuickCancellation(
          null,
          exclude: [for (final order in leftOut) order['uuid']!],
        );
        _check();
      }
    }
    // Every order in the final review still passes the full guard.
    for (final row in (result['orders'] as List).map(qrMap)) {
      await cancellationGuard?.call(row['uuid'] as String);
      _check();
    }
    _cancellationReviews[result['preview_token']
        as String] = (result['orders'] as List)
        .map((row) => qrMap(row)['uuid'] as String)
        .toList();
    return {...result, if (leftOut.isNotEmpty) 'left_out': leftOut};
  }

  @override
  Future<Map<String, dynamic>> cancelExpired(
    Map<String, dynamic> payload,
  ) async {
    _check();
    await mutationGuard?.call();
    final orders = _cancellationReviews[payload['preview_token']];
    if (orders == null) throw StateError('Cancellation review is missing');
    for (final uuid in orders) {
      await cancellationGuard?.call(uuid);
      _check();
    }
    _check();
    final result = await api.cancelExpiredQuickOrders(payload);
    _check();
    return result;
  }

  @override
  Future<Set<String>> ordersWithLocalPaymentEvidence() async {
    _check();
    final orders = await localPaymentOrders?.call() ?? <String>{};
    _check();
    return orders;
  }

  @override
  Future<PaymentReviewEvidence> paymentEvidence(String uuid) async {
    _check();
    final evidence =
        await loadPaymentEvidence?.call(uuid) ?? const PaymentReviewEvidence();
    _check();
    return evidence;
  }

  @override
  Future<Map<String, dynamic>> reviewPayment(
    String uuid,
    PaymentReviewEvidence evidence,
    Map<String, dynamic> payload,
  ) async {
    _check();
    await mutationGuard?.call();
    // The till's saved payments must still be exactly what the manager saw.
    final fresh = await paymentEvidence(uuid);
    if (fresh.blocked ||
        fresh.attemptIds.join(',') != evidence.attemptIds.join(',')) {
      throw StateError('Saved checkout changed; review again');
    }
    // The ordinary payment keeps its location check; a retry may re-read it.
    final gps = payload['decision'] == 'paid' ? await currentGps?.call() : null;
    _check();
    final result = await api.reviewQuickPayment(uuid, {
      ...payload,
      'gps': ?gps,
    });
    _check();
    if (result['order_uuid'] != uuid ||
        result['decision'] != payload['decision'] ||
        result['reference'] != payload['reference'] ||
        result['status'] != (payload['decision'] == 'paid' ? 'paid' : 'held') ||
        result['replayed'] is! bool) {
      throw const FormatException('Payment review acknowledgement mismatch');
    }
    try {
      await recordPaymentReview?.call(
        uuid,
        fresh,
        payload['client_request_id'] as String,
        result,
      );
    } catch (_) {
      throw const PaymentReviewNotSaved();
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> change(QrQuickRequest request) => _call(
    () => api.changeQuickWorkspace(request.orderUuid, request.payload),
    writes: true,
  );

  @override
  Future<List<QrQuickOrder>> fetch() => _call(() async {
    final data = await api.fetchQuickInbox();
    if (data['orders'] is! List) {
      throw const FormatException('Missing quick orders');
    }
    // LAUNCH-P6 — one unknown or bad row (another source, a new field
    // shape) is skipped and logged; it never empties the whole inbox.
    return parseRowsSkippingBad(
      data['orders'],
      QrQuickOrder.new,
      list: 'qr/quick-inbox',
    );
  });
  @override
  Future<void> move(String uuid) =>
      _call(() => api.moveQuickInbox(uuid), writes: true);
  @override
  Future<Map<String, dynamic>> append(QrQuickRequest request) => _call(
    () => api.appendQuickInbox(request.orderUuid, request.payload),
    writes: true,
  );
}
