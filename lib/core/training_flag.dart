import '../models/pos_models.dart';

/// LAUNCH-P5 C7 — the training-mode flag read by the layers below the UI
/// (API client, outbox). See training_mode.dart.
class TrainingMode {
  TrainingMode._();

  /// Read by the deep layers (API client, outbox) that have no Riverpod ref.
  static bool active = false;

  static const preferenceKey = 'p5_training_active';

  static bool allows(String method, String path) {
    final p = path.split('?').first;
    final m = method.toUpperCase();
    if (m == 'GET') {
      return p == '/device/config' ||
          p == '/device/config/delta' ||
          p == '/device/staff-status' ||
          p == '/device/approvers' ||
          p.startsWith('/device/identity');
    }
    // LAUNCH-P5 fix order 2 (T10) — pairing, login and the login unlock
    // are never refused: a till left in training must still re-pair or
    // sign someone in (both also leave training).
    return m == 'POST' &&
        (p == '/device/heartbeat' ||
            p == '/device/auth/verify-manager-pin' ||
            p == '/device/auth/unlock-pin-lock' ||
            p == '/auth/pos/login' ||
            p == '/auth/device/activate');
  }

  /// The safety marker on an event that might reach the server.
  static Map<String, dynamic> mark(Map<String, dynamic> event) {
    final payload = event['payload'];
    if (payload is! Map) return {...event, 'training': true};
    return {
      ...event,
      'payload': {...payload.cast<String, dynamic>(), 'training': true},
    };
  }
}

/// LAUNCH-P5 fix order 2 (T9) — the number on the n-th training slip.
String trainingReceiptNumber(int n) => 'TRAINING-$n';

/// LAUNCH-P5 fix order 2 (T1) — training starts only from a counter order
/// (quick or to-go) with no table and no server bill open.
bool trainingOrderTypeAllowed(
  OrderType type, {
  String? activeTableId,
  bool workspaceOpen = false,
}) =>
    (type == OrderType.quickOrder || type == OrderType.toGo) &&
    (activeTableId == null || activeTableId.isEmpty) &&
    !workspaceOpen;

/// Thrown into the API client when training mode refuses a request.
class TrainingModeRefusal implements Exception {
  const TrainingModeRefusal();
  @override
  String toString() => 'Not available in training mode.';
}

/// The separate local store of training sales (memory only; discarded on
/// exit).
class TrainingOrderStore {
  TrainingOrderStore._();
  static final List<OrderSnapshot> orders = <OrderSnapshot>[];
  static void clear() => orders.clear();
}
