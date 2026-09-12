import 'dart:convert';
import '../services/pos_api_service.dart';
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
class ApiQrQuickGateway implements QrQuickGateway {
  ApiQrQuickGateway(this.api, this.currentScope, {this.mutationGuard})
    : scope = currentScope(),
      token = api.tokenGetter();
  final PosApiService api;
  final String Function() currentScope;
  final String scope;
  final String? token;
  final Future<void> Function()? mutationGuard;
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
  Future<List<QrQuickOrder>> fetch() => _call(() async {
    final data = await api.fetchQuickInbox();
    return (data['orders'] as List)
        .map((row) => QrQuickOrder(qrMap(row)))
        .toList();
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
