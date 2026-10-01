// LAUNCH-P1 part B2 — unit coverage for the new till surfaces: the Dart side
// of the `mithqal/device_identity` channel (P1-5) and the per-device location
// mode (P1-6) from activation and /device/config through to the live gate.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pos_machine/data/config_repository.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/geofence_gate.dart';
import 'package:pos_machine/services/api_models.dart';
import 'package:pos_machine/services/device_hardware_identity.dart';
import 'package:pos_machine/services/device_location_mode.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = DeviceHardwareIdentityReader.defaultChannel;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(BusinessBoundary.resetForTest);
  tearDown(() {
    _mock(null);
    BusinessBoundary.resetForTest();
  });

  group('P1-5 DeviceHardwareIdentityReader (Dart side of the channel)', () {
    test('trims the serial and build info', () async {
      _mock(
        (call) async => switch (call.method) {
          'getHardwareSerial' => ' 0620741070356857\n',
          'getBuildInfo' => {'manufacturer': ' ZCS ', 'model': 'Z92 '},
          _ => null,
        },
      );
      final identity = await const DeviceHardwareIdentityReader().read();
      expect(identity.serial, '0620741070356857');
      expect(identity.manufacturer, 'ZCS');
      expect(identity.model, 'Z92');
    });

    test('no host (unsupported platform / older APK) gives nulls', () async {
      final reader = const DeviceHardwareIdentityReader();
      expect(await reader.getHardwareSerial(), isNull);
      final identity = await reader.read();
      expect(identity.serial, isNull);
      expect(identity.manufacturer, isNull);
      expect(identity.model, isNull);
    });

    test('a null, blank or non-string answer is null', () async {
      for (final answer in <Object?>[
        null,
        '',
        '   ',
        42,
        const ['x'],
      ]) {
        _mock((call) async => answer);
        expect(
          await const DeviceHardwareIdentityReader().getHardwareSerial(),
          isNull,
          reason: 'answer: $answer',
        );
      }
    });

    test('a refusing vendor SDK (PlatformException) is null', () async {
      _mock((call) async => throw PlatformException(code: 'sdk_init_failed'));
      final identity = await const DeviceHardwareIdentityReader().read();
      expect(identity.serial, isNull);
      expect(identity.model, isNull);
    });

    test('notImplemented on an old host is null', () async {
      _mock((call) async => throw MissingPluginException());
      expect(
        await const DeviceHardwareIdentityReader().getHardwareSerial(),
        isNull,
      );
    });

    test('a hardware init that never answers times out to null', () async {
      final never = Completer<Object?>();
      _mock((call) => never.future);
      final reader = const DeviceHardwareIdentityReader(
        timeout: Duration(milliseconds: 20),
      );
      expect(await reader.getHardwareSerial(), isNull);
    });
  });

  group('P1-6 DeviceLocationMode parsing', () {
    test('wire values; unknown fails closed; absent stays absent', () {
      expect(DeviceLocationMode.fromWire('any'), DeviceLocationMode.any);
      expect(DeviceLocationMode.fromWire(' ANY '), DeviceLocationMode.any);
      expect(DeviceLocationMode.fromWire('branch'), DeviceLocationMode.branch);
      expect(DeviceLocationMode.fromWire('nearby'), DeviceLocationMode.branch);
      expect(DeviceLocationMode.fromWire(null), isNull);
      expect(DeviceLocationMode.fromWire(''), isNull);
      expect(DeviceLocationMode.fromWire(true), isNull);
    });

    test('activation response device section', () {
      final result = PairResult.fromJson({
        'device_token': 't',
        'device': {'uuid': 'u', 'location_mode': 'any'},
      });
      expect(result.locationMode, DeviceLocationMode.any);
      expect(
        PairResult.fromJson({
          'device_token': 't',
          'device': <String, dynamic>{},
        }).locationMode,
        isNull,
      );
    });

    test('config: data.device, meta.device, flat meta', () {
      expect(
        DeviceLocationMode.fromConfig({
          'device': {'location_mode': 'any'},
        }, {}),
        DeviceLocationMode.any,
      );
      expect(
        DeviceLocationMode.fromConfig({}, {
          'device': {'location_mode': 'any'},
        }),
        DeviceLocationMode.any,
      );
      expect(
        DeviceLocationMode.fromConfig({}, {'location_mode': 'branch'}),
        DeviceLocationMode.branch,
      );
      expect(DeviceLocationMode.fromConfig({}, {}), isNull);
    });

    test('PosApiService reads it from full and delta config', () async {
      final adapter = _ConfigServer({
        'data': {'branch': null},
        'meta': {'generated_at': 'c1', 'location_mode': 'any'},
        'errors': [],
      });
      final api = PosApiService(
        tokenGetter: () => 't',
        dio: Dio(BaseOptions(baseUrl: 'https://pos.test/api/v1'))
          ..httpClientAdapter = adapter,
      );
      expect((await api.fetchConfig()).locationMode, DeviceLocationMode.any);
      adapter.body = {
        'data': {
          'device': {'location_mode': 'branch'},
        },
        'meta': {'generated_at': 'c2'},
        'errors': [],
      };
      expect(
        (await api.fetchConfigDelta('c1')).locationMode,
        DeviceLocationMode.branch,
      );
      adapter.body = {
        'data': {},
        'meta': {'generated_at': 'c3'},
        'errors': [],
      };
      expect((await api.fetchConfig()).locationMode, isNull);
    });
  });

  group('P1-6 SessionService location mode', () {
    test('activation stores the mode; absent resets to branch', () async {
      final session = await _session({});
      await session.saveActivation(
        const PairResult(
          deviceToken: 't1',
          locationMode: DeviceLocationMode.any,
        ),
      );
      expect(session.locationMode, DeviceLocationMode.any);
      expect(session.locationModeListenable.value, DeviceLocationMode.any);
      await session.saveActivation(const PairResult(deviceToken: 't2'));
      expect(session.locationMode, DeviceLocationMode.branch);
      expect(session.locationModeListenable.value, DeviceLocationMode.branch);
    });

    test('a config without the mode keeps the stored one', () async {
      final session = await _session({'location_mode': 'any'});
      expect(session.locationModeListenable.value, DeviceLocationMode.any);
      await session.saveLocationMode(null);
      expect(session.locationMode, DeviceLocationMode.any);
    });

    test('the mode survives a restart', () async {
      final session = await _session({});
      await session.saveLocationMode(DeviceLocationMode.any);
      final prefs = await SharedPreferences.getInstance();
      final reloaded = SessionService(const FlutterSecureStorage(), prefs);
      await reloaded.load();
      expect(reloaded.locationMode, DeviceLocationMode.any);
      expect(reloaded.locationModeListenable.value, DeviceLocationMode.any);
    });

    test(
      'ConfigRepository persists the server mode (full and delta)',
      () async {
        final session = await _session({});
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final adapter = _ConfigServer({
          'data': {
            'branch': {'id': 2, 'company_id': 1, 'name': 'B'},
          },
          'meta': {
            'generated_at': '2026-10-01T09:00:00Z',
            'location_mode': 'any',
          },
          'errors': [],
        });
        final api = PosApiService(
          tokenGetter: () => 't',
          dio: Dio(BaseOptions(baseUrl: 'https://pos.test/api/v1'))
            ..httpClientAdapter = adapter,
        );
        final repo = ConfigRepository(api, db, session);
        await repo.fetchAndCache();
        expect(session.locationMode, DeviceLocationMode.any);

        adapter.body = {
          'data': {
            'device': {'location_mode': 'branch'},
            'deleted': {},
          },
          'meta': {'generated_at': '2026-10-01T09:05:00Z'},
          'errors': [],
        };
        await repo.syncConfig();
        expect(adapter.paths.last, '/device/config/delta');
        expect(session.locationMode, DeviceLocationMode.branch);
      },
    );
  });

  testWidgets(
    'P1-6 an admin switching the mode re-evaluates the gate without a restart',
    (tester) async {
      GeolocatorPlatform.instance = _OutsideGeolocator();
      final session = await tester.runAsync(() => _session({}));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionServiceProvider.overrideWithValue(session!),
            configRepositoryProvider.overrideWithValue(_FencedBranch()),
          ],
          child: MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const GeofenceGate(child: Text('selling screen')),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('selling screen'), findsNothing);

      // What a config sync does when the admin changes the device's mode.
      await session.saveLocationMode(DeviceLocationMode.any);
      await _settle(tester);
      expect(find.text('selling screen'), findsOneWidget);

      await session.saveLocationMode(DeviceLocationMode.branch);
      await _settle(tester);
      expect(find.text('selling screen'), findsNothing);
      expect(find.text('Outside the store area'), findsOneWidget);
    },
  );
}

void _mock(Future<Object?> Function(MethodCall)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

Future<SessionService> _session(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  FlutterSecureStorage.setMockInitialValues({});
  final raw = await SharedPreferences.getInstance();
  final session = SessionService(const FlutterSecureStorage(), raw);
  await session.load();
  return session;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

class _ConfigServer implements HttpClientAdapter {
  _ConfigServer(this.body);
  Map<String, dynamic> body;
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FencedBranch implements ConfigRepository {
  @override
  Future<void> syncConfig({bool preferDelta = true}) async {}

  @override
  Future<BranchRow?> getBranch() async => const BranchRow(
    id: 2,
    name: 'Fenced branch',
    latitude: 23.588,
    longitude: 58.3829,
    geofenceRadiusM: 500,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _OutsideGeolocator extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      Stream.value(
        Position(
          longitude: 58.0,
          latitude: 23.6,
          timestamp: DateTime.utc(2026, 10, 1, 9),
          accuracy: 5,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        ),
      );
}
