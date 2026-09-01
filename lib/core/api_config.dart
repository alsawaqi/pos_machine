import 'package:flutter/foundation.dart' show kReleaseMode;

/// Static configuration for reaching pos_api.
///
/// The base URL resolves in three tiers (first match wins):
///
///  1. `--dart-define=POS_API_BASE_URL=…`  — explicit override, any build.
///  2. RELEASE builds                       — production (posapi.mithqal.net).
///  3. Debug/profile runs (the IDE ▶ button) — the local stack on the host
///     (`127.0.0.1:8088`). A physical device or emulator reaches it after
///     `adb reverse tcp:8088 tcp:8088` (re-run after every USB reconnect).
///
/// So the committed default is SAFE for release APKs, while day-to-day
/// development automatically talks to the local API with no edits or flags.
/// Debug/profile Settings can still override the URL at runtime. Release
/// SettingsService reads are locked back to this compile-time value.
class ApiConfig {
  const ApiConfig._();

  static const String _override = String.fromEnvironment('POS_API_BASE_URL');
  static const String _production = 'https://posapi.mithqal.net/api/v1';
  static const String _localDev = 'http://localhost:8088/api/v1';

  static const String baseUrl = _override != ''
      ? _override
      : (kReleaseMode ? _production : _localDev);

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 20);
}
