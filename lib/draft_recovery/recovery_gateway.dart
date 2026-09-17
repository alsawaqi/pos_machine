import '../dine_in/dine_in_controller.dart';
import '../dine_in/dine_in_gateway.dart';
import '../dine_in/dine_in_models.dart';
import '../services/pos_api_service.dart';
import 'recovery_controller.dart';
import 'recovery_models.dart';
import 'recovery_store.dart';

/// Pinned recovery port. Its sole write exception is the exact durable intent;
/// ordinary Dine-In gateways never receive a recovery bypass.
class ApiRecoveryGateway implements DraftRecoveryGateway, DineInGateway {
  ApiRecoveryGateway(PosApiService api, String Function() scope, this.store)
    : delegate = ApiDineInGateway(api, scope);
  final ApiDineInGateway delegate;
  final RecoveryStore store;
  String get scope => delegate.scope;
  void check() {
    delegate.check();
    if (store.scope != scope) {
      throw StateError('Recovery device scope changed.');
    }
  }

  Future<T> _call<T>(Future<T> Function() operation) async {
    check();
    final value = await operation();
    check();
    return value;
  }

  @override
  Future<Map<String, dynamic>> preview(
    int tableId,
    Map<String, dynamic> query,
  ) => _call(() => delegate.api.draftRecoveryPreview(tableId, query));

  @override
  Future<Map<String, dynamic>> confirm(
    int tableId,
    Map<String, dynamic> payload,
  ) => _call(() async {
    final saved = await store.active();
    await store.assertOwn(saved?.id);
    if (saved == null ||
        saved.state != 'pending' ||
        saved.local.tableId != tableId ||
        recoveryJson(saved.payload) != recoveryJson(payload)) {
      throw StateError('Only the immutable saved recovery may be submitted.');
    }
    check();
    return delegate.api.draftRecoveryConfirm(tableId, saved.payload);
  });

  @override
  Future<DineInDetail> detail(int tableId) =>
      _call(() => delegate.detail(tableId));

  @override
  Future<Map<String, dynamic>> append(DineInRequest request) => _call(() async {
    final saved = await store.active();
    await store.assertOwn(saved?.id);
    final exact = saved?.state == 'delta_pending' ? saved!.request : null;
    if (saved == null ||
        saved.state != 'delta_pending' ||
        exact == null ||
        exact.tableId != request.tableId ||
        exact.seatingUuid != request.seatingUuid ||
        exact.billUuid != request.billUuid ||
        exact.encoded != request.encoded) {
      throw StateError('Only the immutable saved additions may be submitted.');
    }
    check();
    return delegate.api.dineInAppend(exact.seatingUuid, exact.payload);
  });

  @override
  Future<void> clear(int tableId, {String? seatingUuid}) async =>
      throw StateError('Recovery cannot clear tables.');
  @override
  Future<void> reopen(String uuid) async =>
      throw StateError('Recovery cannot reopen payment.');
  @override
  Future<void> review(
    DineInDetail detail,
    Map<String, dynamic> round,
    bool accept,
  ) async =>
      throw StateError('Review recorded additions on the canonical bill.');
}
