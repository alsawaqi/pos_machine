import '../services/pos_api_service.dart';
import '../qr_quick/qr_quick_models.dart';
import 'dine_in_models.dart';
import 'dine_in_controller.dart';

class ApiDineInGateway implements DineInGateway, DineInContextGuard {
  ApiDineInGateway(this.api, this.currentScope, {this.mutationGuard})
    : scope = currentScope(),
      token = api.tokenGetter();
  final PosApiService api;
  final String Function() currentScope;
  final String scope;
  final String? token;
  final Future<void> Function()? mutationGuard;
  @override
  void check() {
    if (token == null ||
        token!.isEmpty ||
        token != api.tokenGetter() ||
        currentScope() != scope) {
      throw StateError('Device context changed');
    }
  }

  Future<T> _call<T>(
    Future<T> Function() action, {
    bool writes = false,
    bool adjustment = false,
  }) async {
    check();
    try {
      if (writes) await mutationGuard?.call();
      check();
      final result = await action();
      check();
      return result;
    } on ApiException catch (e) {
      throw QrQuickFailure(
        e.code ?? 'refresh',
        e.message,
        refused: adjustment
            ? !e.isNetwork &&
                  e.hasStructuredErrorCode &&
                  const {404, 409, 422}.contains(e.statusCode)
            : !e.isNetwork &&
                  (e.statusCode ?? 0) >= 400 &&
                  (e.statusCode ?? 0) < 500,
      );
    }
  }

  @override
  Future<DineInDetail> detail(int tableId) =>
      _call(() async => DineInDetail(await api.dineInDetail(tableId)));
  @override
  Future<Map<String, dynamic>> append(DineInRequest request) => _call(
    () => request.isCancellation
        ? api.dineInCancelLine(request.seatingUuid, request.cancellationPayload)
        : api.dineInAppend(request.seatingUuid, request.payload),
    writes: true,
  );
  @override
  Future<Map<String, dynamic>> adjust(DineInRequest request) => _call(
    () => api.dineInAdjust(request.seatingUuid, request.payload),
    writes: true,
    adjustment: true,
  );
  @override
  Future<void> review(
    DineInDetail detail,
    Map<String, dynamic> round,
    bool accept,
  ) => _call(
    () => api.dineInReview(
      detail.seatingUuid!,
      round['id'] as int,
      staff: round['entered_by'] == 'staff',
      accept: accept,
    ),
    writes: true,
  );
  @override
  Future<void> clear(int tableId, {String? seatingUuid}) => _call(
    () => api.dineInClear(tableId, seatingUuid: seatingUuid!),
    writes: true,
  );
  @override
  Future<void> reopen(String uuid) =>
      _call(() => api.dineInReopen(uuid), writes: true);
}
