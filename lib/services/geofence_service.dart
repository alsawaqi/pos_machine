import 'dart:math';

enum FenceState { inside, outside, locating, disabled, noPermission }

class GeofenceStatus {
  const GeofenceStatus(this.state, {this.distanceM, this.radiusM = 0});

  final FenceState state;
  final double? distanceM;
  final double radiusM;

  /// POS ordering is allowed only when confirmed inside the fence, or when the
  /// branch has no fence configured. Everything else (outside, still locating,
  /// permission/location unavailable) fails closed to a lock screen — matching
  /// the server's fail-closed enforcement on order.create / order.pay.
  bool get allowsPos => state == FenceState.inside || state == FenceState.disabled;
  bool get isLocked => !allowsPos;
}

/// Haversine geofence math. Mirrors the server's constants (earth radius
/// 6,371,000 m) plus a 50 m on-device buffer (blueprint §9.4 device layer); the
/// server applies its own 100 m tolerance as the backstop.
class GeofenceService {
  const GeofenceService._();

  static const double earthRadiusM = 6371000;
  static const double toleranceM = 50;
  static const double defaultRadiusM = 500;

  static double distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * asin(min(1.0, sqrt(a)));
    return earthRadiusM * c;
  }

  static double _rad(double deg) => deg * pi / 180.0;
}
