import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_config.dart';

/// Device-local POS settings (persisted in SharedPreferences). These are
/// operator/installer preferences — distinct from the device activation (layer
/// 1) and the staff session (layer 2).
class AppSettings {
  const AppSettings({
    this.serverBaseUrl,
    this.serverAddressLocked = false,
    this.printReceipts = true,
    this.printKitchenTickets = true,
    this.printQrKitchenRounds = false,
    this.showLegacyQrTablesTab = false,
    this.language = 'en',
    this.audienceMeasurement = false,
  });

  /// Debug/profile server base URL. Null/empty ⇒ fall back to the
  /// compile-time [ApiConfig.baseUrl]. Release builds ignore this value even
  /// if it survived from an older installation.
  final String? serverBaseUrl;

  /// Whether every network read must resolve to [ApiConfig.baseUrl].
  final bool serverAddressLocked;

  /// Whether to print a Sunmi receipt on order completion.
  final bool printReceipts;

  /// Phase C1 — whether to print an items-only kitchen ticket on order
  /// completion and on hold (blueprint §6.10).
  final bool printKitchenTickets;

  /// QR-002 S5 — independently opt this till into the accepted-round feed.
  /// Default OFF prevents two tills at one branch from double-printing.
  final bool printQrKitchenRounds;

  /// One-release fallback; branches in Off always retain the legacy tab.
  final bool showLegacyQrTablesTab;

  /// Phase C4 (blueprint §9.8) — the UI language: 'en' | 'ar'. Arabic flips
  /// the whole app RTL via MaterialApp's locale.
  final String language;

  /// Phase 1A — opt-in to anonymous on-device audience measurement (the
  /// customer-facing camera counts faces while ads play). Default OFF.
  final bool audienceMeasurement;

  /// The base URL actually used for API calls.
  String get effectiveBaseUrl {
    if (serverAddressLocked) return ApiConfig.baseUrl;
    return (serverBaseUrl != null && serverBaseUrl!.isNotEmpty)
        ? serverBaseUrl!
        : ApiConfig.baseUrl;
  }

  /// True when the server URL is the built-in default (not overridden).
  bool get usingDefaultServer =>
      serverAddressLocked || serverBaseUrl == null || serverBaseUrl!.isEmpty;

  AppSettings copyWith({
    String? serverBaseUrl,
    bool? serverAddressLocked,
    bool? printReceipts,
    bool? printKitchenTickets,
    bool? printQrKitchenRounds,
    bool? showLegacyQrTablesTab,
    String? language,
    bool? audienceMeasurement,
  }) =>
      AppSettings(
        serverBaseUrl: serverBaseUrl ?? this.serverBaseUrl,
        serverAddressLocked:
            serverAddressLocked ?? this.serverAddressLocked,
        printReceipts: printReceipts ?? this.printReceipts,
        printKitchenTickets: printKitchenTickets ?? this.printKitchenTickets,
        printQrKitchenRounds:
            printQrKitchenRounds ?? this.printQrKitchenRounds,
        showLegacyQrTablesTab:
            showLegacyQrTablesTab ?? this.showLegacyQrTablesTab,
        language: language ?? this.language,
        audienceMeasurement: audienceMeasurement ?? this.audienceMeasurement,
      );
}

class SettingsService {
  SettingsService(this._prefs, {this.serverAddressLocked = false});

  final SharedPreferences _prefs;
  final bool serverAddressLocked;

  static const _kBaseUrl = 'server_base_url';
  static const _kPrintReceipts = 'print_receipts';
  static const _kPrintKitchenTickets = 'print_kitchen_tickets';
  static const _kPrintQrKitchenRounds = 'print_qr_kitchen_rounds';
  static const _kShowLegacyQrTablesTab = 'show_legacy_qr_tables_tab';
  static const _kLanguage = 'app_language';
  static const _kAudience = 'audience_measurement';

  AppSettings snapshot() => AppSettings(
        serverBaseUrl: _prefs.getString(_kBaseUrl),
        serverAddressLocked: serverAddressLocked,
        printReceipts: _prefs.getBool(_kPrintReceipts) ?? true,
        printKitchenTickets: _prefs.getBool(_kPrintKitchenTickets) ?? true,
        printQrKitchenRounds:
            _prefs.getBool(_kPrintQrKitchenRounds) ?? false,
        showLegacyQrTablesTab: showLegacyQrTablesTab,
        language: _prefs.getString(_kLanguage) == 'ar' ? 'ar' : 'en',
        audienceMeasurement: _prefs.getBool(_kAudience) ?? false,
      );

  /// The base URL the API client should use right now.
  String get effectiveBaseUrl => snapshot().effectiveBaseUrl;

  bool get showLegacyQrTablesTab =>
      _prefs.getBool(_kShowLegacyQrTablesTab) ?? false;

  /// Persist a debug/profile server URL (normalized), or clear it (back to the
  /// default) when blank. The release read remains locked regardless.
  Future<void> saveServerBaseUrl(String? raw) async {
    final normalized = normalizeBaseUrl(raw);
    if (normalized == null) {
      await _prefs.remove(_kBaseUrl);
    } else {
      await _prefs.setString(_kBaseUrl, normalized);
    }
  }

  Future<void> savePrintReceipts(bool value) async {
    await _prefs.setBool(_kPrintReceipts, value);
  }

  Future<void> savePrintKitchenTickets(bool value) async {
    await _prefs.setBool(_kPrintKitchenTickets, value);
  }

  Future<void> savePrintQrKitchenRounds(bool value) async {
    await _prefs.setBool(_kPrintQrKitchenRounds, value);
  }

  Future<void> saveShowLegacyQrTablesTab(bool value) async {
    await _prefs.setBool(_kShowLegacyQrTablesTab, value);
  }

  Future<void> saveLanguage(String value) async {
    await _prefs.setString(_kLanguage, value == 'ar' ? 'ar' : 'en');
  }

  Future<void> saveAudienceMeasurement(bool value) async {
    await _prefs.setBool(_kAudience, value);
  }

  /// Normalize a debug/profile server URL: trim, default the scheme to http://,
  /// drop trailing slashes, and ensure the `/api/v{n}` base path. Blank input
  /// returns null (⇒ use the compile-time default).
  static String? normalizeBaseUrl(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;

    var url = trimmed;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    url = url.replaceAll(RegExp(r'/+$'), '');
    if (!RegExp(r'/api/v\d+$').hasMatch(url)) {
      url = '$url/api/v1';
    }
    return url;
  }
}
