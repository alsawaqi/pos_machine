import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_models.dart';

/// Immutable snapshot of the device/staff session, watched by the boot gate.
class SessionState {
  const SessionState({
    this.isPaired = false,
    this.companyId,
    this.branchId,
    this.kioskId,
    this.staff,
  });

  final bool isPaired;
  final int? companyId;
  final int? branchId;
  final String? kioskId;
  final StaffSessionData? staff;

  bool get hasStaff => staff != null;

  static const empty = SessionState();

  SessionState copyWith({
    bool? isPaired,
    int? companyId,
    int? branchId,
    String? kioskId,
    StaffSessionData? staff,
    bool clearStaff = false,
  }) {
    return SessionState(
      isPaired: isPaired ?? this.isPaired,
      companyId: companyId ?? this.companyId,
      branchId: branchId ?? this.branchId,
      kioskId: kioskId ?? this.kioskId,
      staff: clearStaff ? null : (staff ?? this.staff),
    );
  }
}

/// Persists the device token (secure) + non-sensitive session bits (prefs),
/// and keeps the token in memory so the API client can read it synchronously.
class SessionService {
  SessionService(this._secure, this._prefs);

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  static const _kDeviceToken = 'device_token'; // secure storage
  static const _kKioskId = 'kiosk_id';
  static const _kCompanyId = 'company_id';
  static const _kBranchId = 'branch_id';
  static const _kStaff = 'staff_session_json';

  String? _deviceToken; // in-memory cache for the dio interceptor

  /// Synchronous token accessor for [PosApiService.tokenGetter].
  String? get deviceToken => _deviceToken;
  bool get isPaired => _deviceToken != null && _deviceToken!.isNotEmpty;

  String? get kioskId => _prefs.getString(_kKioskId);
  int? get companyId => _prefs.getInt(_kCompanyId);
  int? get branchId => _prefs.getInt(_kBranchId);

  StaffSessionData? get staff {
    final raw = _prefs.getString(_kStaff);
    if (raw == null || raw.isEmpty) return null;
    try {
      return StaffSessionData.fromStored(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Read the persisted token into memory at startup.
  Future<void> load() async {
    _deviceToken = await _secure.read(key: _kDeviceToken);
  }

  SessionState snapshot() => SessionState(
        isPaired: isPaired,
        companyId: companyId,
        branchId: branchId,
        kioskId: kioskId,
        staff: staff,
      );

  Future<void> savePairing(PairResult result, String kioskId) async {
    _deviceToken = result.deviceToken;
    await _secure.write(key: _kDeviceToken, value: result.deviceToken);
    await _prefs.setString(_kKioskId, kioskId);
    if (result.companyId != null) {
      await _prefs.setInt(_kCompanyId, result.companyId!);
    }
    if (result.branchId != null) {
      await _prefs.setInt(_kBranchId, result.branchId!);
    }
  }

  Future<void> saveStaff(StaffSessionData staff) async {
    await _prefs.setString(_kStaff, jsonEncode(staff.toJson()));
  }

  /// Staff logout (keeps the device paired).
  Future<void> clearStaff() async {
    await _prefs.remove(_kStaff);
  }

  /// Full reset back to pairing (e.g. on a 401 / revoked device). Keeps the last
  /// kiosk id so the pairing screen can pre-fill it.
  Future<void> clearForRePair() async {
    _deviceToken = null;
    await _secure.delete(key: _kDeviceToken);
    await _prefs.remove(_kStaff);
    await _prefs.remove(_kCompanyId);
    await _prefs.remove(_kBranchId);
  }
}
