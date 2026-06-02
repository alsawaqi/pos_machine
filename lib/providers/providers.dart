import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/config_repository.dart';
import '../data/db/app_database.dart';
import '../services/api_models.dart';
import '../services/config_mapper.dart';
import '../services/geofence_service.dart';
import '../services/pos_api_service.dart';
import '../services/session_service.dart';

// --- async-initialized singletons (overridden in main()) -------------------
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override sharedPreferencesProvider in main()'),
);

final sessionServiceProvider = Provider<SessionService>(
  (ref) => throw UnimplementedError('Override sessionServiceProvider in main()'),
);

final secureStorageProvider =
    Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());

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

  Future<void> savePairing(PairResult result, String kioskId) async {
    await _svc.savePairing(result, kioskId);
    state = _svc.snapshot();
  }

  Future<void> saveStaff(StaffSessionData staff) async {
    await _svc.saveStaff(staff);
    state = _svc.snapshot();
  }

  Future<void> logoutStaff() async {
    await _svc.clearStaff();
    state = _svc.snapshot();
  }

  Future<void> clearForRePair() async {
    await _svc.clearForRePair();
    state = _svc.snapshot();
  }
}

// --- API + config ----------------------------------------------------------
final apiServiceProvider = Provider<PosApiService>((ref) {
  final session = ref.read(sessionServiceProvider);
  return PosApiService(
    tokenGetter: () => session.deviceToken,
    onUnauthorized: () {
      // A 401 means the device was blocked/unpaired → drop back to pairing.
      Future.microtask(
        () => ref.read(sessionControllerProvider.notifier).clearForRePair(),
      );
    },
  );
});

final configRepositoryProvider = Provider<ConfigRepository>(
  (ref) => ConfigRepository(
    ref.read(apiServiceProvider),
    ref.read(appDatabaseProvider),
    ref.read(sessionServiceProvider),
  ),
);

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

// --- geofence --------------------------------------------------------------
/// Streams the geofence status by comparing live GPS to the cached branch fence.
/// Fails closed: no fix / no permission ⇒ locked. If the branch has no fence
/// configured, ordering is allowed (the server enforces nothing there).
final geofenceProvider = StreamProvider<GeofenceStatus>((ref) async* {
  final branch = await ref.read(configRepositoryProvider).getBranch();
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
