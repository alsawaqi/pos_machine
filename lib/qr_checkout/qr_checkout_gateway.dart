import '../services/pos_api_service.dart';
import 'qr_checkout_controller.dart';
import 'qr_checkout_models.dart';

class ApiCheckoutGateway implements CheckoutGateway {
  ApiCheckoutGateway({
    required this.api,
    required this.currentScope,
    required this.location,
    required this.legacyGuard,
    this.mutationGuard,
  }) : scope = currentScope(),
       token = api.tokenGetter();
  final PosApiService api;
  final String Function() currentScope;
  final Future<({double lat, double lng})?> Function() location;
  final Future<void> Function(String uuid) legacyGuard;
  final Future<void> Function()? mutationGuard;
  final String scope;
  final String? token;
  ({double lat, double lng})? _fix;
  CheckoutClaim? _reservation;
  bool _editableQrOrder = false;
  void checkScope() {
    if (scope != currentScope() ||
        token == null ||
        token!.isEmpty ||
        token != api.tokenGetter()) {
      throw StateError('Checkout device identity changed');
    }
  }

  Future<T> _call<T>(Future<T> Function() call, {bool writes = false}) async {
    checkScope();
    if (writes) await mutationGuard?.call();
    checkScope();
    final result = await call();
    checkScope();
    return result;
  }

  @override
  Future<void> preflight(String orderUuid) async {
    checkScope();
    await legacyGuard(orderUuid);
    _fix = await location();
    checkScope();
  }

  @override
  Future<CheckoutClaim> claim(String orderUuid) async {
    try {
      return _reservation = CheckoutClaim(
        await _call(
          () => api.checkoutClaim({
            'order_uuid': orderUuid,
            if (_fix != null) 'gps': {'lat': _fix!.lat, 'lng': _fix!.lng},
          }),
          writes: true,
        ),
      );
    } on ApiException catch (error) {
      // These are authoritative no-new-claim verdicts, not network/5xx errors.
      if (!error.isNetwork &&
          (error.statusCode ?? 0) >= 400 &&
          (error.statusCode ?? 0) < 500 &&
          const {
            'order_not_found',
            'device_not_attended',
            'qr_order_not_settleable',
            'staff_bill_owner_required',
            'charge_already_claimed',
            'qr_charge_recovery_required',
            'order_not_bound_to_device_session',
            'qr_session_expired',
            'qr_session_not_settleable',
            'geofence_fix_required',
            'geofence_outside',
          }.contains(error.code)) {
        throw CheckoutRefusal(error.code!);
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> snapshot(String orderUuid) => _call(() async {
    final result = await api.checkoutRead(orderUuid);
    final order = checkoutMap(result['order']);
    _editableQrOrder =
        order['source'] == 'qr_web' &&
        const ['quick', 'dine_in'].contains(order['order_type']);
    return result;
  });
  @override
  Future<void> release(
    String orderUuid,
    String outcome,
    List<Map<String, dynamic>> captures,
  ) => _call(
    () =>
        _editableQrOrder &&
            outcome == 'cancelled' &&
            captures.isEmpty &&
            _reservation != null
        ? api.cancelQuickReservation({
            'order_uuid': orderUuid,
            'charge_claimed_at': _reservation!.json['charge_claimed_at'],
            'charge_deadline_at': _reservation!.json['charge_deadline_at'],
          })
        : api.checkoutRelease({
            'order_uuid': orderUuid,
            'outcome': outcome,
            if (captures.isNotEmpty)
              'bank_response': {'checkout_tenders': captures},
            if (captures
                    .where((c) => c['softpos_reference'] is String)
                    .firstOrNull
                case final row?)
              'softpos_reference': row['softpos_reference'],
            if (captures
                    .where((c) => c['softpos_auth_code'] is String)
                    .firstOrNull
                case final row?)
              'softpos_auth_code': row['softpos_auth_code'],
          }),
    writes: true,
  );
  @override
  Future<List<Map<String, dynamic>>> push(Map<String, dynamic> event) =>
      _call(() => api.checkoutPush(event), writes: true);
}
