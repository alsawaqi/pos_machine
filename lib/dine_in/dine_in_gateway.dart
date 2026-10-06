import '../table_cancellation/table_bill_cancellation.dart'
    show tableApprovalRefusals;
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
                  (const {404, 409, 422}.contains(e.statusCode) ||
                      // LAUNCH-P5 F3 — a refused (or expired) approval
                      // wrote nothing: final, and the next try asks again.
                      (e.statusCode == 403 &&
                          tableApprovalRefusals.contains(e.code)))
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
        ? api.dineInCancelLine(
            request.seatingUuid,
            request.cancellationPayload,
            staffToken: request.staffToken,
          )
        : api.dineInAppend(
            request.seatingUuid,
            request.payload,
            staffToken: request.staffToken,
          ),
    writes: true,
    adjustment: request.isCancellation,
  );
  @override
  Future<Map<String, dynamic>> adjust(DineInRequest request) => _call(
    () => api.dineInAdjust(
      request.seatingUuid,
      request.payload,
      staffToken: request.staffToken,
    ),
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
      // LAUNCH-P6 (F-6) — a tablet round is confirmed (= sent to the
      // kitchen) or rejected through the staff table route, with the staff
      // token and the capability header.
      staff: const {'staff', 'tablet'}.contains(round['entered_by']),
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
