import 'package:mithqal_softpos/mithqal_softpos.dart';

import 'device_location_mode.dart';

// Plain DTOs for the auth responses from pos_api. The config bundle itself is
// handled as a raw Map and mapped in config_mapper.dart.

/// Result of POST /auth/device/activate — the device exchanges the single
/// admin-generated activation code for a device token, plus its kiosk ID and
/// bank terminal ID (both stored at layer 1 for the Soft POS / Mosambee).
class PairResult {
  const PairResult({
    required this.deviceToken,
    this.deviceUuid,
    this.companyId,
    this.branchId,
    this.kioskId,
    this.terminalId,
    this.terminalPin,
    this.softpos = const SoftPosProfile(),
    this.deviceName,
    this.locationMode,
  });

  final String deviceToken;
  final String? deviceUuid;
  final int? companyId;
  final int? branchId;
  final String? kioskId;
  final String? terminalId;
  final SoftPosProfile softpos;
  final String? terminalPin; // bank-issued Mosambee PIN (null = card disabled)
  final String? deviceName;

  /// LAUNCH-P1 decision 2a; null when the server did not send it.
  final DeviceLocationMode? locationMode;

  factory PairResult.fromJson(Map<String, dynamic> json) {
    final device = json['device'] as Map<String, dynamic>?;
    return PairResult(
      deviceToken: json['device_token'] as String,
      deviceUuid: device?['uuid'] as String?,
      companyId: (device?['company_id'] as num?)?.toInt(),
      branchId: (device?['branch_id'] as num?)?.toInt(),
      kioskId: device?['kiosk_id'] as String?,
      terminalId: device?['terminal_id'] as String?,
      terminalPin: device?['terminal_pin'] as String?,
      softpos: SoftPosProfile.fromJson(
        (device?['softpos'] as Map?)?.cast<String, dynamic>(),
      ),
      deviceName: device?['name'] as String?,
      locationMode: DeviceLocationMode.fromActivation(json),
    );
  }
}

/// LAUNCH-P5 C6 — the login reply's attendance state for this person.
class StaffAttendance {
  const StaffAttendance({required this.open, this.clockInAt, this.uuid});

  final bool open;
  final DateTime? clockInAt;

  /// The open attendance row's uuid when the server sends it.
  final String? uuid;

  static StaffAttendance? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return StaffAttendance(
      open: raw['open'] == true,
      clockInAt: DateTime.tryParse(raw['clock_in_at']?.toString() ?? ''),
      uuid: raw['uuid']?.toString() ?? raw['attendance_uuid']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'open': open,
    if (clockInAt != null) 'clock_in_at': clockInAt!.toUtc().toIso8601String(),
    if (uuid != null) 'uuid': uuid,
  };
}

class StaffSessionData {
  const StaffSessionData({
    required this.id,
    required this.name,
    this.uuid,
    this.position,
    this.branchId,
    this.branchIds = const <int>[],
    this.attendance,
    this.staffToken,
  });

  final int id;
  final String name;
  final String? uuid;
  final String? position;
  final int? branchId;

  /// LAUNCH-P5 — every branch this person works at (home branch included).
  final List<int> branchIds;

  /// LAUNCH-P5 C6 — the attendance state; null from an older server.
  final StaffAttendance? attendance;

  /// LAUNCH-P5 fix order 1 (F1) — the login reply's signed staff token
  /// (opaque). Only a fresh login carries it; it is kept in secure storage
  /// by [SessionService] and never written by [toJson].
  final String? staffToken;

  factory StaffSessionData.fromJson(Map<String, dynamic> json) =>
      StaffSessionData(
        id: (json['id'] as num).toInt(),
        name: (json['name'] ?? '').toString(),
        uuid: json['uuid'] as String?,
        position: json['position'] as String?,
        branchId: (json['branch_id'] as num?)?.toInt(),
        branchIds: [
          for (final id in json['branch_ids'] as List? ?? const [])
            if (id is num) id.toInt(),
        ],
        attendance: StaffAttendance.fromJson(json['attendance']),
        staffToken: json['staff_token'] is String
            ? json['staff_token'] as String
            : null,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'uuid': uuid,
    'position': position,
    'branch_id': branchId,
    if (branchIds.isNotEmpty) 'branch_ids': branchIds,
    if (attendance != null) 'attendance': attendance!.toJson(),
  };

  StaffSessionData withAttendance(StaffAttendance? attendance) =>
      StaffSessionData(
        id: id,
        name: name,
        uuid: uuid,
        position: position,
        branchId: branchId,
        branchIds: branchIds,
        attendance: attendance,
        staffToken: staffToken,
      );

  /// A stored session never carries the token (prefs are not secret).
  factory StaffSessionData.fromStored(Map<String, dynamic> json) =>
      StaffSessionData.fromJson({...json}..remove('staff_token'));

  /// A manager may perform manager-only POS actions.
  bool get isManager => (position ?? '').toLowerCase().contains('manager');
}
