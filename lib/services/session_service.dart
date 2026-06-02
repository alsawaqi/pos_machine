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
    this.kioskId,
    this.terminalId,
    this.staff,
  });

  final bool isConfigured;
  final int? companyId;
  final int? branchId;
  final String? kioskId; // device identity, entered once at setup
  final String? terminalId; // bank terminal, FETCHED from config (Soft POS)
  final StaffSessionData? staff;

  bool get hasStaff => staff != null;

  static const empty = SessionState();
}

/// Persists the device token (secure) + non-sensitive session bits (prefs), and
/// keeps the token in memory so the API client can read it synchronously.
///
/// The device identity is the **kiosk ID** (paired once with an activation
/// token at install). The **terminal ID** is never entered — it's fetched from
/// the config bundle and stored here for the Soft POS / Mosambee payment call.
class SessionService {
  SessionService(this._secure, this._prefs);

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  static const _kDeviceToken = 'device_token'; // secure storage
  static const _kKioskId = 'kiosk_id';
  static const _kTerminalId = 'terminal_id';
  static const _kCompanyId = 'company_id';
  static const _kBranchId = 'branch_id';
  static const _kStaff = 'staff_session_json';

  String? _deviceToken; // in-memory cache for the dio interceptor

  /// Synchronous token accessor for [PosApiService.tokenGetter].
  String? get deviceToken => _deviceToken;
  bool get isConfigured => _deviceToken != null && _deviceToken!.isNotEmpty;

  String? get kioskId => _prefs.getString(_kKioskId);
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
        kioskId: kioskId,
        terminalId: terminalId,
        staff: staff,
      );

  /// Store the result of a successful device pairing (kiosk ID → device token).
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

  /// The device's bank terminal ID, fetched from the config bundle meta (used by
  /// the Soft POS / Mosambee payment call later). Never entered on the device.
  Future<void> saveTerminalId(String? terminalId) async {
    if (terminalId == null || terminalId.isEmpty) return;
    await _prefs.setString(_kTerminalId, terminalId);
  }

  Future<void> saveStaff(StaffSessionData staff) async {
    await _prefs.setString(_kStaff, jsonEncode(staff.toJson()));
  }

  /// Staff logout (keeps the device paired).
  Future<void> clearStaff() async {
    await _prefs.remove(_kStaff);
  }

  /// Full reset back to device setup (e.g. on a 401 / revoked device). Keeps the
  /// last kiosk ID so the setup screen can pre-fill it on re-pair.
  Future<void> clearForRePair() async {
    _deviceToken = null;
    await _secure.delete(key: _kDeviceToken);
    await _prefs.remove(_kStaff);
    await _prefs.remove(_kCompanyId);
    await _prefs.remove(_kBranchId);
    await _prefs.remove(_kTerminalId);
  }
}
