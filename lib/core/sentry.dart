/// Phase C5 — crash reporting (blueprint §9.12). Sentry over Crashlytics:
/// the org already runs sentry-laravel (pos_admin) + @sentry/vue
/// (admin/merchant SPAs), and sentry-android is self-contained — no Play
/// Services on the sideloaded Sunmi fleet, crash envelopes persisted to disk
/// for next-launch delivery (offline-first POS).
///
/// House convention (pos_admin lib/sentry.ts / AttachSentryContext): an
/// absent DSN makes EVERYTHING here a complete no-op — dev builds and
/// unconfigured fleets run exactly as before.
library;

import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

/// Compile-time wiring, mirroring ApiConfig's --dart-define pattern:
///   flutter build apk --dart-define=SENTRY_DSN=https://… \
///                     --dart-define=SENTRY_ENVIRONMENT=pilot
class SentryConfig {
  static const String dsn = String.fromEnvironment('SENTRY_DSN');
  static const String environment =
      String.fromEnvironment('SENTRY_ENVIRONMENT', defaultValue: 'local');

  /// Explicit release (matches the backend SENTRY_RELEASE convention) so the
  /// auto-derived `com.example.pos_machine@…` never fractures release history
  /// when the applicationId is finally renamed. Bump alongside pubspec.
  static const String release = 'pos_machine@1.0.0+1';

  static const bool enabled = dsn != '';
}

/// Staff sign-in/out → Sentry user (modeled on pos_admin's setSentryUser).
/// Pass null id to clear on logout / re-pair.
Future<void> setSentryStaff({int? id, String? name, String? position}) async {
  if (!SentryConfig.enabled) return;
  await Sentry.configureScope((scope) async {
    if (id == null) {
      await scope.setUser(null);
      return;
    }
    await scope.setUser(SentryUser(
      id: '$id',
      username: name,
      // NEVER the PIN; position only — matches sendDefaultPii=false.
      data: {if (position != null && position.isNotEmpty) 'position': position},
    ));
  });
}

/// Structured breadcrumb (sync pushes, auth events, shift open/close). Bodies
/// and PII (PINs, customer phones, plates) must never be passed in [data].
void sentryBreadcrumb(
  String category,
  String message, {
  Map<String, dynamic>? data,
  SentryLevel level = SentryLevel.info,
}) {
  if (!SentryConfig.enabled) return;
  unawaited(Sentry.addBreadcrumb(Breadcrumb(
    category: category,
    message: message,
    data: data,
    level: level,
  )));
}

/// Promote an otherwise-invisible failure (e.g. the server rejecting an
/// outbox event) to a Sentry event. Call sites must dedupe (a 100-device
/// fleet retrying a flaky validation would flood the quota).
void sentryCaptureMessage(String message, {SentryLevel level = SentryLevel.warning}) {
  if (!SentryConfig.enabled) return;
  unawaited(Sentry.captureMessage(message, level: level));
}
