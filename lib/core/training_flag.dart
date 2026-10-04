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
    return m == 'POST' &&
        (p == '/device/heartbeat' || p == '/device/auth/verify-manager-pin');
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
