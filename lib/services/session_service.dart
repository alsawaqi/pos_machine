import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_models.dart';

/// Immutable snapshot of the device/staff session, watched by the boot gate.
class SessionState {
  const SessionState({
    this.isConfigured = false,
    this.companyId,
    this.branchId,
    this.terminalId,
    this.staff,
  });

  final bool isConfigured;
  final int? companyId;
  final int? branchId;
  final String? terminalId;
  final StaffSessionData? staff;

  bool get hasStaff => staff != null;

  static const empty = SessionState();
}

/// Persists the device token (secure) + non-sensitive session bits (prefs),
/// and keeps the token in memory so the API client can read it synchronously.
///
/// The device identity is the admin-assigned **terminal ID** (claimed once at
/// install). After that, staff only enter their PIN.
class SessionService {
  SessionService(this._secure, this._prefs);

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  static const _kDeviceToken = 'device_token'; // secure storage
  static const _kTerminalId = 'terminal_id';
  static const _kCompanyId = 'company_id';
  static const _kBranchId = 'branch_id';
  static const _kStaff = 'staff_session_json';

  String? _deviceToken; // in-memory cache for the dio interceptor

  /// Synchronous token accessor for [PosApiService.tokenGetter].
  String? get deviceToken => _deviceToken;
  bool get isConfigured => _deviceToken != null && _deviceToken!.isNotEmpty;

  String? get terminalId => _prefs.getString(_kTerminalId);
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
        isConfigured: isConfigured,
        companyId: companyId,
        branchId: branchId,
        terminalId: terminalId,
        staff: staff,
      );

  /// Store the result of a successful device claim (terminal ID → device token).
  Future<void> saveClaim(ClaimResult result) async {
    _deviceToken = result.deviceToken;
    await _secure.write(key: _kDeviceToken, value: result.deviceToken);
    if (result.terminalId != null) {
      await _prefs.setString(_kTerminalId, result.terminalId!);
    }
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

  /// Staff logout (keeps the device claimed).
  Future<void> clearStaff() async {
    await _prefs.remove(_kStaff);
  }

  /// Full reset back to device setup (e.g. on a 401 / revoked device). Keeps the
  /// last terminal ID so the setup screen can pre-fill it on re-claim.
  Future<void> clearForRePair() async {
    _deviceToken = null;
    await _secure.delete(key: _kDeviceToken);
    await _prefs.remove(_kStaff);
    await _prefs.remove(_kCompanyId);
    await _prefs.remove(_kBranchId);
  }
}
