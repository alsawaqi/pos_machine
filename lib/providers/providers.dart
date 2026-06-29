import 'dart:async';
import 'dart:ui' show Locale;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show SentryLevel;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/sentry.dart';
import '../data/config_repository.dart';
import '../l10n/l10n.dart';
import '../data/db/app_database.dart';
import '../data/order_sync_repository.dart';
import '../services/api_models.dart';
import '../services/audience_service.dart';
import '../services/config_mapper.dart';
import '../services/expense_restock_service.dart';
import '../services/geofence_service.dart';
import '../services/live_sync.dart';
import '../services/pos_api_service.dart';
import '../services/session_service.dart';
import '../services/settings_service.dart';
import '../services/shift_service.dart';

// --- async-initialized singletons (overridden in main()) -------------------
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override sharedPreferencesProvider in main()'),
);

final sessionServiceProvider = Provider<SessionService>(
  (ref) => throw UnimplementedError('Override sessionServiceProvider in main()'),
);

final secureStorageProvider =
    Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());

// --- device-local settings (server URL, printer) ---------------------------
final settingsServiceProvider = Provider<SettingsService>(
  (ref) => SettingsService(ref.read(sharedPreferencesProvider)),
);

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends Notifier<AppSettings> {
  SettingsService get _svc => ref.read(settingsServiceProvider);

  @override
  AppSettings build() => _svc.snapshot();

  Future<void> setServerBaseUrl(String? raw) async {
    await _svc.saveServerBaseUrl(raw);
    state = _svc.snapshot();
  }

  Future<void> setPrintReceipts(bool value) async {
    await _svc.savePrintReceipts(value);
    state = _svc.snapshot();
  }

  Future<void> setPrintKitchenTickets(bool value) async {
    await _svc.savePrintKitchenTickets(value);
    state = _svc.snapshot();
  }

  /// Phase C4 — switch the UI language ('en' | 'ar'); applies immediately
  /// (MaterialApp watches [localeProvider]).
  Future<void> setLanguage(String value) async {
    await _svc.saveLanguage(value);
    state = _svc.snapshot();
  }

  Future<void> setAudienceMeasurement(bool value) async {
    await _svc.saveAudienceMeasurement(value);
    state = _svc.snapshot();
  }
}

/// Phase C4 — the active UI locale, derived from Settings.
final localeProvider = Provider<Locale>(
  (ref) => Locale(ref.watch(settingsControllerProvider).language),
);

/// Phase C4 — context-free strings for code that has no BuildContext
/// (PosController messages, services, dialogs built from controllers).
final l10nProvider = Provider<L10n>(
  (ref) => lookupL10n(ref.watch(localeProvider)),
);

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

// --- reactive session ------------------------------------------------------
final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

class SessionController extends Notifier<SessionState> {
  SessionService get _svc => ref.read(sessionServiceProvider);

  @override
  SessionState build() => _svc.snapshot();

  Future<void> saveActivation(PairResult result) async {
    await _svc.saveActivation(result);
    state = _svc.snapshot();
  }

  Future<void> saveStaff(StaffSessionData staff) async {
    await _svc.saveStaff(staff);
    state = _svc.snapshot();
    // Phase C5 — crashes attribute to the signed-in cashier (no-op w/o DSN).
    await setSentryStaff(
      id: staff.id,
      name: staff.name,
      position: staff.position,
    );
    sentryBreadcrumb('auth', 'staff login');
  }

  Future<void> logoutStaff() async {
    await _svc.clearStaff();
    state = _svc.snapshot();
    await setSentryStaff(id: null);
    sentryBreadcrumb('auth', 'staff logout');
  }

  /// Record the device's open shift after the server ACKs shift.open — flips
  /// the gate from the open-shift screen into the POS.
  Future<void> markShiftOpen(OpenShiftData shift) async {
    await _svc.saveOpenShift(shift);
    state = _svc.snapshot();
  }

  /// Clear the open shift after a settled shift.close.
  Future<void> markShiftClosed() async {
    await _svc.clearShift();
    state = _svc.snapshot();
  }

  Future<void> clearForRePair() async {
    await _svc.clearForRePair();
    state = _svc.snapshot();
    await setSentryStaff(id: null);
    sentryBreadcrumb(
      'auth',
      'device token rejected — dropped back to pairing',
      level: SentryLevel.warning,
    );
  }
}

// --- API + config ----------------------------------------------------------
final apiServiceProvider = Provider<PosApiService>((ref) {
  final session = ref.read(sessionServiceProvider);
  final settings = ref.read(settingsServiceProvider);
  return PosApiService(
    tokenGetter: () => session.deviceToken,
    // Resolve the operator-configured server URL per request.
    baseUrlGetter: () => settings.effectiveBaseUrl,
    onUnauthorized: () {
      // A 401 means the device was blocked/unpaired → drop back to pairing.
      Future.microtask(
        () => ref.read(sessionControllerProvider.notifier).clearForRePair(),
      );
    },
  );
});

/// Opens / closes cash-drawer shifts through the device sync pipeline.
final shiftServiceProvider = Provider<ShiftService>(
  (ref) => ShiftService(ref.read(apiServiceProvider)),
);

/// Logs expenses / raises restock requests through the device sync pipeline.
final expenseRestockServiceProvider = Provider<ExpenseRestockService>(
  (ref) => ExpenseRestockService(ref.read(apiServiceProvider)),
);

final configRepositoryProvider = Provider<ConfigRepository>(
  (ref) => ConfigRepository(
    ref.read(apiServiceProvider),
    ref.read(appDatabaseProvider),
    ref.read(sessionServiceProvider),
  ),
);

/// Offline-first order push: enqueues a completed order to the durable outbox
/// and flushes it to pos_api (now + on reconnect).
final orderSyncRepositoryProvider = Provider<OrderSyncRepository>(
  (ref) => OrderSyncRepository(
    ref.read(apiServiceProvider),
    ref.read(appDatabaseProvider),
  ),
);

/// Phase 1A — anonymous on-device audience measurement (customer-facing camera
/// → ML Kit face counts), folded into slider.display telemetry. Off unless the
/// operator enables it in Settings. Auxiliary: never blocks the POS.
final audienceServiceProvider = Provider<AudienceService>((ref) {
  final service = AudienceService();
  ref.onDispose(() => unawaited(service.stop()));
  return service;
});

/// The cached catalog, streamed from Drift. Drives the bridge into PosController.
final catalogProvider = StreamProvider<CatalogSnapshot>(
  (ref) => ref.read(configRepositoryProvider).watchCatalog(),
);

// --- connectivity ----------------------------------------------------------
bool _isOnline(List<ConnectivityResult> results) =>
    results.any((r) => r != ConnectivityResult.none);

final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  yield _isOnline(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(_isOnline);
});

// --- live sync (Phase C3, §9.3/§11.5) ---------------------------------------
/// Reverb subscription on the device. Joins `private-branch.{id}` (company
/// fallback) with device-token auth; ANY domain event on the channel —
/// including echoes of this device's own pushes — triggers a DEBOUNCED delta
/// config sync, so another terminal's sale, an admin stock edit, or a held
/// order placed across the room shows up here within seconds. The endpoint
/// comes from /device/config meta.websocket (persisted by ConfigRepository);
/// unconfigured installs simply never connect. Started from StaffPosScreen;
/// connectivity gates connect/teardown.
final liveSyncProvider = Provider<LiveSyncService>((ref) {
  Timer? debounce;

  final service = LiveSyncService(
    endpointGetter: () =>
        WebsocketEndpoint.fromJson(ref.read(sessionServiceProvider).websocketConfig),
    apiBaseUrlGetter: () => ref.read(settingsServiceProvider).effectiveBaseUrl,
    channelGetter: () {
      final session = ref.read(sessionServiceProvider);
      if (!session.isConfigured) return null;
      return channelFor(
        branchId: session.branchId,
        companyId: session.companyId,
      );
    },
    authorize: ({required socketId, required channelName}) =>
        ref.read(apiServiceProvider).authorizeBroadcast(
              socketId: socketId,
              channelName: channelName,
            ),
    onLiveEvent: (eventType) {
      // Trailing-edge debounce: a completion burst (create+pay+donation, plus
      // our own echo) coalesces into ONE delta sync. Marketing-slider edits use
      // a much shorter window so the customer-screen ad loop refreshes almost
      // instantly when admin changes a slider (images/order/interval).
      final delay = eventType == 'marketing.sliders.changed'
          ? const Duration(milliseconds: 700)
          : const Duration(seconds: 3);
      debounce?.cancel();
      debounce = Timer(delay, () {
        unawaited(
          ref.read(configRepositoryProvider).syncConfig().catchError((_) {}),
        );
      });
    },
  );

  ref.listen(connectivityProvider, (previous, next) {
    final online = next.asData?.value;
    if (online == true) {
      service.notifyOnline();
    } else if (online == false) {
      service.notifyOffline();
    }
  });

  ref.onDispose(() {
    debounce?.cancel();
    unawaited(service.stop());
  });

  return service;
});

// --- geofence --------------------------------------------------------------
/// Streams the geofence status by comparing live GPS to the cached branch fence.
/// Fails closed: no fix / no permission ⇒ locked. If the branch has no fence
/// configured, ordering is allowed (the server enforces nothing there).
final geofenceProvider = StreamProvider<GeofenceStatus>((ref) async* {
  final repo = ref.read(configRepositoryProvider);
  // Pull the latest branch fence (radius / lat / lng) from the server first, so
  // edits made by the admin in pos_admin take effect on the device. Without this
  // the device keeps whatever was cached at login and never sees the change.
  // Re-runs on every Retry (the gate invalidates this provider). Offline or
  // transient failures fall back to the cached branch.
  try {
    // Delta-preferring (Phase 7): this is the hottest sync path, so it only
    // pulls changed rows once a cursor exists. A branch geofence edit bumps the
    // branch's updated_at, so it still comes back in the delta.
    await repo.syncConfig();
  } catch (_) {
    // keep going with the cached branch
  }
  final branch = await repo.getBranch();
  if (branch == null || branch.latitude == null || branch.longitude == null) {
    yield const GeofenceStatus(FenceState.disabled);
    return;
  }
  final radius =
      (branch.geofenceRadiusM ?? GeofenceService.defaultRadiusM.toInt()).toDouble();

  if (!await Geolocator.isLocationServiceEnabled()) {
    yield GeofenceStatus(FenceState.noPermission, radiusM: radius);
    return;
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    yield GeofenceStatus(FenceState.noPermission, radiusM: radius);
    return;
  }

  yield GeofenceStatus(FenceState.locating, radiusM: radius);
  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    ),
  ).map((pos) {
    final d = GeofenceService.distanceMeters(
      branch.latitude!,
      branch.longitude!,
      pos.latitude,
      pos.longitude,
    );
    final inside = d <= radius + GeofenceService.toleranceM;
    return GeofenceStatus(
      inside ? FenceState.inside : FenceState.outside,
      distanceM: d,
      radiusM: radius,
    );
  });
});
