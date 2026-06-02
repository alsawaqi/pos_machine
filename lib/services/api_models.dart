// Plain DTOs for the auth responses from pos_api. The config bundle itself is
// handled as a raw Map and mapped in config_mapper.dart.

/// Result of POST /auth/device/pair — the device pairs with its kiosk ID + a
/// one-time activation token and receives a long-lived device token. (The bank
/// terminal ID is NOT here — it is fetched from the config bundle meta.)
class PairResult {
  const PairResult({
    required this.deviceToken,
    this.deviceUuid,
    this.companyId,
    this.branchId,
    this.deviceName,
  });

  final String deviceToken;
  final String? deviceUuid;
  final int? companyId;
  final int? branchId;
  final String? deviceName;

  factory PairResult.fromJson(Map<String, dynamic> json) {
    final device = json['device'] as Map<String, dynamic>?;
    return PairResult(
      deviceToken: json['device_token'] as String,
      deviceUuid: device?['uuid'] as String?,
      companyId: (device?['company_id'] as num?)?.toInt(),
      branchId: (device?['branch_id'] as num?)?.toInt(),
      deviceName: device?['name'] as String?,
    );
  }
}

class StaffSessionData {
  const StaffSessionData({
    required this.id,
    required this.name,
    this.uuid,
    this.position,
    this.branchId,
  });

  final int id;
  final String name;
  final String? uuid;
  final String? position;
  final int? branchId;

  factory StaffSessionData.fromJson(Map<String, dynamic> json) => StaffSessionData(
        id: (json['id'] as num).toInt(),
        name: (json['name'] ?? '').toString(),
        uuid: json['uuid'] as String?,
        position: json['position'] as String?,
        branchId: (json['branch_id'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'uuid': uuid,
        'position': position,
        'branch_id': branchId,
      };

  factory StaffSessionData.fromStored(Map<String, dynamic> json) => StaffSessionData.fromJson(json);

  /// A manager may perform manager-only POS actions.
  bool get isManager => (position ?? '').toLowerCase().contains('manager');
}
