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
  final String? kioskId; // fetched at activation (layer 1)
  final String? terminalId; // fetched at activation + refreshed from config (Soft POS)
  final StaffSessionData? staff;

  bool get hasStaff => staff != null;

  static const empty = SessionState();
}

/// Persists the device token (secure) + the layer-1 device identity (prefs), and
/// keeps the token in memory so the API client can read it synchronously.
///
/// Layer 1 = the device exchanges a single admin code for a device token + its
/// kiosk ID + terminal ID; that data PERSISTS (staff logout never clears it —
/// only a 401/revoke does). Layer 2 = the staff PIN session.
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

  /// Store a successful device activation: device token + kiosk ID + terminal ID
  /// + company/branch. Layer-1 data that PERSISTS (only [clearForRePair] removes it).
  Future<void> saveActivation(PairResult result) async {
    _deviceToken = result.deviceToken;
    await _secure.write(key: _kDeviceToken, value: result.deviceToken);
    if (result.kioskId != null) {
      await _prefs.setString(_kKioskId, result.kioskId!);
    }
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

  /// Refresh the terminal ID from the config bundle meta (kept in sync).
  Future<void> saveTerminalId(String? terminalId) async {
    if (terminalId == null || terminalId.isEmpty) return;
    await _prefs.setString(_kTerminalId, terminalId);
  }

  Future<void> saveStaff(StaffSessionData staff) async {
    await _prefs.setString(_kStaff, jsonEncode(staff.toJson()));
  }

  /// Staff logout (layer 2 only — keeps the device activated).
  Future<void> clearStaff() async {
    await _prefs.remove(_kStaff);
  }

  /// Full reset back to device setup (only on a 401 / revoked device). Clears
  /// the layer-1 identity too, so the device must be re-activated with a new code.
  Future<void> clearForRePair() async {
    _deviceToken = null;
    await _secure.delete(key: _kDeviceToken);
    await _prefs.remove(_kStaff);
    await _prefs.remove(_kCompanyId);
    await _prefs.remove(_kBranchId);
    await _prefs.remove(_kKioskId);
    await _prefs.remove(_kTerminalId);
  }
}
