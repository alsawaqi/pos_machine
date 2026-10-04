import '../tenancy/business_identity.dart';
import 'dart:convert';
import 'package:mithqal_softpos/mithqal_softpos.dart';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/auth_wire.dart';
import '../core/permissions.dart';
import 'api_models.dart';
import 'device_location_mode.dart';

/// The cached open cash-drawer shift (null = no open shift). Shared shifts are
/// staff-owned; a foreign shift may survive logout only long enough for the next
/// cashier to reconcile and close that drawer, never to inherit it for sales.
class OpenShiftData {
  const OpenShiftData({
    required this.uuid,
    required this.openingCashBaisas,
    required this.openedAt,
    required this.staffId,
    this.reopenCount = 0,
  });

  final String uuid;
  final int openingCashBaisas;
  final DateTime openedAt;
  final int staffId;

  /// LAUNCH-P5 C5 — how many times the portal re-opened this shift (part
  /// of the fixed close event id; 0 from an older server).
  final int reopenCount;

  factory OpenShiftData.fromJson(Map<String, dynamic> json) => OpenShiftData(
    uuid: json['uuid'].toString(),
    openingCashBaisas: (json['opening_cash_baisas'] as num?)?.toInt() ?? 0,
    openedAt:
        DateTime.tryParse(json['opened_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    staffId: (json['staff_id'] as num?)?.toInt() ?? 0,
    reopenCount: (json['reopen_count'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'opening_cash_baisas': openingCashBaisas,
    'opened_at': openedAt.toIso8601String(),
    'staff_id': staffId,
    if (reopenCount != 0) 'reopen_count': reopenCount,
  };
}

/// Immutable snapshot of the device/staff session, watched by the boot gate.
class SessionState {
  const SessionState({
    this.isConfigured = false,
    this.companyId,
    this.branchId,
    this.kioskId,
    this.terminalId,
    this.terminalPin,
    this.softpos = const SoftPosProfile(),
    this.staff,
    this.openShift,
  });

  final bool isConfigured;
  final int? companyId;
  final int? branchId;
  final String? kioskId; // fetched at activation (layer 1)
  final String?
  terminalId; // fetched at activation + refreshed from config (Soft POS)
  final String? terminalPin; // Null disables card payments.
  final SoftPosProfile softpos;
  final StaffSessionData? staff;
  final OpenShiftData? openShift;

  bool get hasStaff => staff != null;
  bool get hasOpenShift => openShift != null;

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
  // LAUNCH-P5 F1 — the logged-in person's signed staff token (secure).
  static const _kStaffToken = 'staff_token';
  static const _kKioskId = 'kiosk_id';
  static const _kTerminalId = 'terminal_id';
  static const _kTerminalPin = 'terminal_pin';
  static const _kCompanyId = 'company_id';
  static const _kBranchId = 'branch_id';
  static const _kStaff = 'staff_session_json';
  static const _kShift = 'open_shift_json';
  static const _kWebsocket = 'websocket_config_json';
  static const _kLastShiftSummary = 'last_shift_summary_json';
  static const _kAudienceServer = 'audience_measurement_server';
  static const _kLocationMode = 'location_mode';
  // LAUNCH-P5 — `settings.position_permissions` (JSON) and
  // `settings.shift_end_reminder_at` ("HH:MM", Muscat) from the config.
  static const _kPositionPermissions = 'p5_position_permissions_json';
  static const _kShiftEndReminderAt = 'p5_shift_end_reminder_at';
  // LAUNCH-P5 fix order 1 (F4) — product id → uuid from /device/config
  // (the sold-out approval is signed over the product uuid).
  static const _kProductUuids = 'p5_product_uuids_json';

  String? _deviceToken; // in-memory cache for the dio interceptor
  String? _staffToken; // LAUNCH-P5 F1 — in-memory copy of the staff token

  /// LAUNCH-P5 F1 — the logged-in person's staff token (null = nobody, or
  /// an older server that sends none).
  String? get staffToken => _staffToken;

  /// LAUNCH-P5 F1 — [load] found a staff session without a token (an
  /// upgrade from a build before the staff token) and signed it out.
  bool get reloginRequired => _reloginRequired;
  bool _reloginRequired = false;

  /// LAUNCH-P1 decision 2a — where this till may sell. Defaults to `branch`
  /// (the geofence applies) until the server says `any`.
  DeviceLocationMode get locationMode =>
      DeviceLocationMode.fromWire(_prefs.getString(_kLocationMode)) ??
      DeviceLocationMode.branch;

  /// Fires when activation or a config sync changes [locationMode], so the
  /// geofence gate re-evaluates without a restart.
  ValueListenable<DeviceLocationMode> get locationModeListenable =>
      _locationMode;
  final _locationMode = ValueNotifier<DeviceLocationMode>(
    DeviceLocationMode.branch,
  );

  /// Persist the server's location mode. Null (an older server that does not
  /// send it) keeps the stored value.
  Future<void> saveLocationMode(DeviceLocationMode? mode) async {
    if (mode == null) return;
    await _prefs.setString(_kLocationMode, mode.wire);
    _locationMode.value = mode;
  }

  /// Synchronous token accessor for [PosApiService.tokenGetter].
  String? get deviceToken => _deviceToken;
  bool get isConfigured => _deviceToken != null && _deviceToken!.isNotEmpty;

  String? get kioskId => _prefs.getString(_kKioskId);
  String? get terminalId => _prefs.getString(_kTerminalId);
  String? _terminalPin;
  String? get terminalPin => _terminalPin;
  SoftPosProfile get softpos {
    final raw = _prefs.getString('softpos_profile');
    if (raw == null) return const SoftPosProfile();
    return SoftPosProfile.fromJson(softPosObject(raw));
  }

  Future<void> saveSoftpos(SoftPosProfile profile) =>
      _prefs.setString('softpos_profile', jsonEncode(profile.toJson()));

  int? get companyId => _prefs.getInt(_kCompanyId);
  int? get branchId => _prefs.getInt(_kBranchId);

  StaffSessionData? get staff {
    final raw = _prefs.getString(_kStaff);
    if (raw == null || raw.isEmpty) return null;
    try {
      return StaffSessionData.fromStored(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  OpenShiftData? get openShift {
    final raw = _prefs.getString(_kShift);
    if (raw == null || raw.isEmpty) return null;
    try {
      return OpenShiftData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Read the persisted token into memory at startup.
  Future<void> load() async {
    _deviceToken = await _secure.read(key: _kDeviceToken);
    await BusinessBoundary.adoptLegacy(_deviceToken);
    _terminalPin = await _secure.read(key: _kTerminalPin);
    final legacy = _prefs.getString(_kTerminalPin);
    if (_terminalPin == null && legacy != null && legacy.trim().isNotEmpty) {
      await _secure.write(key: _kTerminalPin, value: legacy.trim());
      _terminalPin = legacy.trim();
    }
    await _prefs.remove(_kTerminalPin);
    _locationMode.value = locationMode;
    // LAUNCH-P5 F1 — a staff session restored without its token (saved by
    // a build before the staff token) cannot name its maker: log in again.
    // The open shift and every queued event stay.
    _staffToken = await _secure.read(key: _kStaffToken);
    if ((_staffToken ?? '').trim().isEmpty) {
      _staffToken = null;
      final stored = _prefs.getString(_kStaff);
      if (stored != null && stored.isNotEmpty) {
        await _prefs.remove(_kStaff);
        _reloginRequired = true;
      }
    } else if (staff == null) {
      // A token without a session (the session was wiped): drop it.
      _staffToken = null;
      await _storeStaffToken(null);
    }
    StaffTokenHolder.set(staff?.id, _staffToken);
  }

  SessionState snapshot() => SessionState(
    isConfigured: isConfigured,
    companyId: companyId,
    branchId: branchId,
    kioskId: kioskId,
    terminalId: terminalId,
    terminalPin: terminalPin,
    softpos: softpos,
    staff: staff,
    openShift: openShift,
  );

  /// Store a successful device activation: device token + kiosk ID + terminal ID
  /// + company/branch. Layer-1 data that PERSISTS (only [clearForRePair] removes it).
  Future<void> saveActivation(PairResult result) async {
    if (BusinessBoundary.initialized &&
        (result.companyId == null ||
            result.branchId == null ||
            (result.deviceUuid ?? '').isEmpty)) {
      throw StateError(
        'Activation did not include a complete device identity.',
      );
    }
    Future<void> install() async {
      if (result.deviceUuid != null)
        await _prefs.setString('device_uuid', result.deviceUuid!);

      if (result.kioskId != null) {
        await _prefs.setString(_kKioskId, result.kioskId!);
      }
      if (result.terminalId != null) {
        await _prefs.setString(_kTerminalId, result.terminalId!);
      }
      await saveTerminalPin(result.terminalPin);
      await saveSoftpos(result.softpos);
      if (result.companyId != null) {
        await _prefs.setInt(_kCompanyId, result.companyId!);
      }
      if (result.branchId != null) {
        await _prefs.setInt(_kBranchId, result.branchId!);
      }
      // A new enrollment never inherits a previous one's mode: absent means
      // the fail-closed default.
      await saveLocationMode(result.locationMode ?? DeviceLocationMode.branch);
      await _secure.write(key: _kDeviceToken, value: result.deviceToken);
      _deviceToken = result.deviceToken;
    }

    if (BusinessBoundary.initialized) {
      await BusinessBoundary.accept(
        BusinessIdentity(
          result.companyId!,
          result.branchId!,
          result.deviceUuid!,
        ),
        install: install,
      );
    } else {
      await install();
    }
  }

  /// Refresh the terminal ID from the config bundle meta (kept in sync).
  Future<void> saveTerminalId(String? terminalId) async {
    if (terminalId == null || terminalId.isEmpty) return;
    await _prefs.setString(_kTerminalId, terminalId);
  }

  /// Refresh the Mosambee terminal PIN from the server (activation + config).
  /// Unlike [saveTerminalId] (keep-last-known), null/empty REMOVES the cached
  /// value — an admin clearing the PIN disables card payments.
  Future<void> saveTerminalPin(String? terminalPin) async {
    final trimmed = terminalPin?.trim();
    _terminalPin = trimmed == null || trimmed.isEmpty ? null : trimmed;
    if (_terminalPin == null) {
      await _secure.delete(key: _kTerminalPin);
    } else {
      await _secure.write(key: _kTerminalPin, value: _terminalPin);
    }
    await _prefs.remove(_kTerminalPin);
  }

  /// Phase C3 — the Reverb endpoint from /device/config meta.websocket
  /// ({app_key, host, port, scheme}). Null = the server has live push off →
  /// clear, so the device stops dialing.
  Map<String, dynamic>? get websocketConfig {
    final raw = _prefs.getString(_kWebsocket);
    if (raw == null || raw.isEmpty) return null;
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  Future<void> saveWebsocketConfig(Map<String, dynamic>? config) async {
    if (config == null) {
      await _prefs.remove(_kWebsocket);
    } else {
      await _prefs.setString(_kWebsocket, jsonEncode(config));
    }
  }

  /// Marketing #46 — the server-driven audience-measurement consent from
  /// /device/config meta. Null = the server didn't state a policy (older
  /// pos_api) — the device-local Settings toggle stays in charge then.
  bool? get serverAudienceMeasurement => _prefs.containsKey(_kAudienceServer)
      ? _prefs.getBool(_kAudienceServer)
      : null;

  Future<void> saveServerAudienceMeasurement(bool? enabled) async {
    if (enabled == null) {
      await _prefs.remove(_kAudienceServer);
    } else {
      await _prefs.setBool(_kAudienceServer, enabled);
    }
  }

  /// LAUNCH-P5 C1 — the merchant's tick list, resolved over the shared
  /// defaults (nothing cached yet = the defaults).
  PositionPermissions get positionPermissions =>
      PositionPermissions.resolve(_prefs.getString(_kPositionPermissions));

  /// LAUNCH-P5 C8 — the branch's shift-end reminder time ("HH:MM", Muscat),
  /// or null when the branch has none.
  String? get shiftEndReminderAt {
    final raw = _prefs.getString(_kShiftEndReminderAt)?.trim() ?? '';
    return raw.isEmpty ? null : raw;
  }

  /// Fires after [saveStaffSettings] changes either value, so open screens
  /// re-read the tick list without a restart.
  ValueListenable<int> get staffSettingsRevision => _staffSettingsRevision;
  final _staffSettingsRevision = ValueNotifier<int>(0);

  /// Persist the P5 keys of the config `settings` block. A key the server
  /// did not send keeps the stored value; an explicit null clears it.
  Future<void> saveStaffSettings(Map<String, dynamic>? settings) async {
    if (settings == null) return;
    var changed = false;
    if (settings.containsKey('position_permissions')) {
      final value = settings['position_permissions'];
      if (value is Map) {
        await _prefs.setString(_kPositionPermissions, jsonEncode(value));
      } else {
        await _prefs.remove(_kPositionPermissions);
      }
      changed = true;
    }
    if (settings.containsKey('shift_end_reminder_at')) {
      final value = settings['shift_end_reminder_at'];
      if (value is String && value.trim().isNotEmpty) {
        await _prefs.setString(_kShiftEndReminderAt, value.trim());
      } else {
        await _prefs.remove(_kShiftEndReminderAt);
      }
      changed = true;
    }
    if (changed) _staffSettingsRevision.value++;
  }

  /// Keep (or, with null, remove) the staff token in secure storage. A
  /// storage failure never blocks a login or a logout: the in-memory token
  /// still names the person, and a session restored without its token logs
  /// in again.
  Future<void> _storeStaffToken(String? token) async {
    try {
      if (token == null) {
        await _secure.delete(key: _kStaffToken);
      } else {
        await _secure.write(key: _kStaffToken, value: token);
      }
    } catch (_) {}
  }

  /// LAUNCH-P5 F4 — the uuid of product [productId] from the last config
  /// sync (null = unknown: not synced yet, or an older server).
  String? productUuid(int productId) {
    final raw = _prefs.getString(_kProductUuids);
    if (raw == null || raw.isEmpty) return null;
    try {
      final uuid = (jsonDecode(raw) as Map)['$productId'];
      return uuid is String && uuid.isNotEmpty ? uuid : null;
    } catch (_) {
      return null;
    }
  }

  /// Keep the product uuids of a config [products] list: a full sync
  /// ([replace]) starts afresh; a delta merges and drops [deleted] ids.
  Future<void> saveProductUuids(
    Object? products, {
    bool replace = false,
    List<int> deleted = const <int>[],
  }) async {
    final map = <String, String>{};
    if (!replace) {
      try {
        final raw = _prefs.getString(_kProductUuids);
        if (raw != null && raw.isNotEmpty) {
          map.addAll(
            (jsonDecode(raw) as Map).map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            ),
          );
        }
      } catch (_) {}
    }
    for (final id in deleted) {
      map.remove('$id');
    }
    if (products is List) {
      for (final p in products) {
        if (p is! Map) continue;
        final id = p['id'], uuid = p['uuid'];
        if (id is num && uuid is String && uuid.isNotEmpty) {
          map['${id.toInt()}'] = uuid;
        }
      }
    }
    await _prefs.setString(_kProductUuids, jsonEncode(map));
  }

  /// Persist the staff session. A [login] also stores (or, from an older
  /// server, clears) the person's staff token; any other save (attendance)
  /// keeps the token of the session it updates.
  Future<void> saveStaff(StaffSessionData staff, {bool login = false}) async {
    await _prefs.setString(_kStaff, jsonEncode(staff.toJson()));
    if (!login && staff.staffToken == null) return;
    final token = staff.staffToken?.trim();
    if (token == null || token.isEmpty) {
      _staffToken = null;
      await _storeStaffToken(null);
    } else {
      _staffToken = token;
      await _storeStaffToken(token);
    }
    _reloginRequired = false;
    StaffTokenHolder.set(staff.id, _staffToken);
  }

  /// Persist the device's open shift (after the server ACKs shift.open).
  Future<void> saveOpenShift(OpenShiftData shift) async {
    await _prefs.setString(_kShift, jsonEncode(shift.toJson()));
  }

  /// Clear the open shift (after a settled shift.close).
  Future<void> clearShift() async {
    await _prefs.remove(_kShift);
  }

  /// Phase C6 — the LAST closed shift's printed Z-report snapshot, persisted
  /// BEFORE clearShift() erases the device's only record of the shift window,
  /// so a manager can reprint it from the staff menu. Survives staff logout.
  Map<String, dynamic>? get lastShiftSummary {
    final raw = _prefs.getString(_kLastShiftSummary);
    if (raw == null || raw.isEmpty) return null;
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLastShiftSummary(Map<String, dynamic> snapshot) async {
    await _prefs.setString(_kLastShiftSummary, jsonEncode(snapshot));
  }

  /// Staff logout (layer 2 only — keeps the device activated and retains the
  /// shift record so the next login can adopt its own shift or close a foreign
  /// drawer before selling).
  Future<void> clearStaff() async {
    await _prefs.remove(_kStaff);
    // LAUNCH-P5 F1 — the token leaves with the person.
    _staffToken = null;
    StaffTokenHolder.clear();
    await _storeStaffToken(null);
  }

  /// Full reset back to device setup (only on a 401 / revoked device). Clears
  /// the layer-1 identity too, so the device must be re-activated with a new code.
  Future<void> clearForRePair() async {
    BusinessBoundary.block('device_reactivation_required');
    await BusinessBoundary.paymentsSettled;
    _deviceToken = null;
    await _secure.delete(key: _kDeviceToken);
    _staffToken = null;
    StaffTokenHolder.clear();
    await _storeStaffToken(null);
  }
}
