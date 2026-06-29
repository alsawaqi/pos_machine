import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_config.dart';

/// Device-local POS settings (persisted in SharedPreferences). These are
/// operator/installer preferences — distinct from the device activation (layer
/// 1) and the staff session (layer 2).
class AppSettings {
  const AppSettings({
    this.serverBaseUrl,
    this.printReceipts = true,
    this.printKitchenTickets = true,
    this.language = 'en',
    this.audienceMeasurement = false,
  });

  /// Operator-set server base URL. Null/empty ⇒ fall back to the compile-time
  /// [ApiConfig.baseUrl]. Lets a real device on the LAN point at the right
  /// backend without a rebuild.
  final String? serverBaseUrl;

  /// Whether to print a Sunmi receipt on order completion.
  final bool printReceipts;

  /// Phase C1 — whether to print an items-only kitchen ticket on order
  /// completion and on hold (blueprint §6.10).
  final bool printKitchenTickets;

  /// Phase C4 (blueprint §9.8) — the UI language: 'en' | 'ar'. Arabic flips
  /// the whole app RTL via MaterialApp's locale.
  final String language;

  /// Phase 1A — opt-in to anonymous on-device audience measurement (the
  /// customer-facing camera counts faces while ads play). Default OFF.
  final bool audienceMeasurement;

  /// The base URL actually used for API calls.
  String get effectiveBaseUrl =>
      (serverBaseUrl != null && serverBaseUrl!.isNotEmpty)
          ? serverBaseUrl!
          : ApiConfig.baseUrl;

  /// True when the server URL is the built-in default (not overridden).
  bool get usingDefaultServer =>
      serverBaseUrl == null || serverBaseUrl!.isEmpty;

  AppSettings copyWith({
    String? serverBaseUrl,
    bool? printReceipts,
    bool? printKitchenTickets,
    String? language,
    bool? audienceMeasurement,
  }) =>
      AppSettings(
        serverBaseUrl: serverBaseUrl ?? this.serverBaseUrl,
        printReceipts: printReceipts ?? this.printReceipts,
        printKitchenTickets: printKitchenTickets ?? this.printKitchenTickets,
        language: language ?? this.language,
        audienceMeasurement: audienceMeasurement ?? this.audienceMeasurement,
      );
}

class SettingsService {
  SettingsService(this._prefs);

  final SharedPreferences _prefs;

  static const _kBaseUrl = 'server_base_url';
  static const _kPrintReceipts = 'print_receipts';
  static const _kPrintKitchenTickets = 'print_kitchen_tickets';
  static const _kLanguage = 'app_language';
  static const _kAudience = 'audience_measurement';

  AppSettings snapshot() => AppSettings(
        serverBaseUrl: _prefs.getString(_kBaseUrl),
        printReceipts: _prefs.getBool(_kPrintReceipts) ?? true,
        printKitchenTickets: _prefs.getBool(_kPrintKitchenTickets) ?? true,
        language: _prefs.getString(_kLanguage) == 'ar' ? 'ar' : 'en',
        audienceMeasurement: _prefs.getBool(_kAudience) ?? false,
      );

  /// The base URL the API client should use right now.
  String get effectiveBaseUrl => snapshot().effectiveBaseUrl;

  /// Persist a server URL (normalized), or clear it (back to the default) when
  /// blank. Returns the resulting [AppSettings].
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

  Future<void> saveLanguage(String value) async {
    await _prefs.setString(_kLanguage, value == 'ar' ? 'ar' : 'en');
  }

  Future<void> saveAudienceMeasurement(bool value) async {
    await _prefs.setBool(_kAudience, value);
  }

  /// Normalize an operator-entered server URL: trim, default the scheme to
  /// http://, drop trailing slashes, and ensure the `/api/v{n}` base path. Blank
  /// input returns null (⇒ use the compile-time default).
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
