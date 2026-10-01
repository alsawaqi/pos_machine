// LAUNCH-P1 part B2 — device enrollment on the till.
//
// P1-5/P1-10 (decision 1a): activation carries the sticker serial, the app
// type and the build manufacturer/model; the three serial-lock refusals are
// explained in English and Arabic, keep the installer on the enrollment
// screen and leave any existing enrollment untouched.
// P1-6 (decision 2a): a till set to "any location" is never locked by the
// geofence gate; a "branch" till still is.
//
// Deliberately written against the pre-P1 public surface only (channel mock,
// preference key, widgets), so it compiles on the base commit and fails there
// by behaviour.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
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
import 'package:pos_machine/screens/device_setup_screen.dart';
import 'package:pos_machine/screens/geofence_gate.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
import 'package:pos_machine/tenancy/tenant_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _identityChannel = MethodChannel('mithqal/device_identity');
const _enrolled = BusinessIdentity(1, 2, 'live-device-uuid');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(BusinessBoundary.resetForTest);
  tearDown(() {
    _mockIdentityChannel(null);
    BusinessBoundary.resetForTest();
  });

  group('P1-5 activation request', () {
    testWidgets('carries the sticker serial, the app type and the build info', (
      tester,
    ) async {
      _mockIdentityChannel((call) async {
        switch (call.method) {
          case 'getHardwareSerial':
            return '  TV07P58G40097 ';
          case 'getBuildInfo':
            return {'manufacturer': 'SUNMI', 'model': 'T3'};
        }
        return null;
      });
      final server = _ActivationServer.success();
      final session = await tester.runAsync(_freshDevice);
      await _pumpSetup(tester, session!, server);

      await _activate(tester, 'CODE-1');

      expect(server.bodies, hasLength(1));
      expect(server.bodies.single, {
        'code': 'CODE-1',
        'serial': 'TV07P58G40097',
        'app': 'till',
        'manufacturer': 'SUNMI',
        'model': 'T3',
      });
    });

    testWidgets('an unreadable serial is left out, never invented', (
      tester,
    ) async {
      _mockIdentityChannel((call) async {
        if (call.method == 'getHardwareSerial') return null;
        throw PlatformException(code: 'unsupported');
      });
      final server = _ActivationServer.success();
      final session = await tester.runAsync(_freshDevice);
      await _pumpSetup(tester, session!, server);

      await _activate(tester, 'CODE-2');

      expect(server.bodies.single, {'code': 'CODE-2', 'app': 'till'});
    });

    testWidgets('an APK host without the channel still activates', (
      tester,
    ) async {
      final server = _ActivationServer.success();
      final session = await tester.runAsync(_freshDevice);
      await _pumpSetup(tester, session!, server);

      await _activate(tester, 'CODE-3');

      expect(server.bodies.single, {'code': 'CODE-3', 'app': 'till'});
      expect(session.deviceToken, 'new-device-token');
    });
  });

  group('P1-5/P1-10 activation refusals', () {
    const cases = {
      'activation_device_mismatch': (
        en:
            "This activation code belongs to another device. Ask the "
            "administrator for this device's code.",
        ar: 'رمز التفعيل هذا يخص جهازًا آخر. اطلب من المسؤول رمز هذا الجهاز.',
      ),
      'activation_serial_missing': (
        en:
            "Could not read this device's serial number, so the code cannot "
            'be checked. Restart the device and try again. If it keeps '
            'happening, contact support.',
        ar:
            'تعذّرت قراءة الرقم التسلسلي لهذا الجهاز، لذلك لا يمكن التحقق من '
            'الرمز. أعد تشغيل الجهاز وحاول مرة أخرى. إذا تكرر ذلك، تواصل مع '
            'الدعم.',
      ),
      'activation_app_mismatch': (
        en:
            'This code is for a different kind of device. Ask the '
            'administrator to check the device type, or use the matching app.',
        ar:
            'هذا الرمز مخصص لنوع آخر من الأجهزة. اطلب من المسؤول التحقق من '
            'نوع الجهاز، أو استخدم التطبيق المطابق.',
      ),
    };

    for (final entry in cases.entries) {
      for (final locale in const ['en', 'ar']) {
        testWidgets(
          '${entry.key} ($locale) explains itself, stays on enrollment and '
          'keeps the live enrollment',
          (tester) async {
            _mockIdentityChannel(_t3Identity);
            final server = _ActivationServer.refusal(entry.key);
            final session = await tester.runAsync(_enrolledDevice);
            await _pumpSetup(tester, session!, server, locale: Locale(locale));

            await _activate(tester, 'OTHER-DEVICE-CODE');

            final expected = locale == 'ar' ? entry.value.ar : entry.value.en;
            expect(find.text(expected), findsOneWidget);
            await _expectEnrollmentIntact(tester, session);
            // Still on the enrollment screen, code kept, retry possible.
            expect(find.byType(DeviceSetupScreen), findsOneWidget);
            expect(find.text('OTHER-DEVICE-CODE'), findsOneWidget);
            await _tapContinue(tester);
            expect(server.bodies, hasLength(2));
            await _expectEnrollmentIntact(tester, session);
          },
        );
      }
    }

    testWidgets('the refusal is also understood inside errors[]', (
      tester,
    ) async {
      _mockIdentityChannel(_t3Identity);
      final server = _ActivationServer.refusal(
        'activation_device_mismatch',
        envelope: true,
      );
      final session = await tester.runAsync(_enrolledDevice);
      await _pumpSetup(tester, session!, server);

      await _activate(tester, 'OTHER-DEVICE-CODE');

      expect(
        find.text(
          "This activation code belongs to another device. Ask the "
          "administrator for this device's code.",
        ),
        findsOneWidget,
      );
      await _expectEnrollmentIntact(tester, session);
    });

    testWidgets('an unrelated refusal keeps the server message', (
      tester,
    ) async {
      _mockIdentityChannel(_t3Identity);
      final server = _ActivationServer.refusal(
        'activation_failed',
        message: 'Activation failed: invalid or expired code.',
        envelope: true,
      );
      final session = await tester.runAsync(_enrolledDevice);
      await _pumpSetup(tester, session!, server);

      await _activate(tester, 'EXPIRED');

      expect(
        find.text('Activation failed: invalid or expired code.'),
        findsOneWidget,
      );
      await _expectEnrollmentIntact(tester, session);
    });
  });

  group('P1-6 till geofence gate', () {
    testWidgets('"any location" does not lock the till outside the fence', (
      tester,
    ) async {
      final geo = _OutsideGeolocator();
      GeolocatorPlatform.instance = geo;
      final session = await tester.runAsync(
        () => _sessionWithPrefs({'location_mode': 'any'}),
      );
      await _pumpGate(tester, session!);

      expect(find.text('selling screen'), findsOneWidget);
      expect(find.text('Outside the store area'), findsNothing);
    });

    testWidgets('"branch" still locks the till outside the fence', (
      tester,
    ) async {
      GeolocatorPlatform.instance = _OutsideGeolocator();
      final session = await tester.runAsync(
        () => _sessionWithPrefs({'location_mode': 'branch'}),
      );
      await _pumpGate(tester, session!);

      expect(find.text('selling screen'), findsNothing);
      expect(find.text('Outside the store area'), findsOneWidget);
    });

    testWidgets('no stored mode keeps the fail-closed branch lock', (
      tester,
    ) async {
      GeolocatorPlatform.instance = _OutsideGeolocator();
      final session = await tester.runAsync(() => _sessionWithPrefs({}));
      await _pumpGate(tester, session!);

      expect(find.text('selling screen'), findsNothing);
      expect(find.text('Outside the store area'), findsOneWidget);
    });
  });
}

// --- activation harness ------------------------------------------------------

Future<Object?> _t3Identity(MethodCall call) async => switch (call.method) {
  'getHardwareSerial' => 'TV07P58G40097',
  'getBuildInfo' => {'manufacturer': 'SUNMI', 'model': 'T3'},
  _ => null,
};

void _mockIdentityChannel(Future<Object?> Function(MethodCall)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_identityChannel, handler);
}

/// A brand-new install: no identity, no token.
Future<SessionService> _freshDevice() async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final raw = await SharedPreferences.getInstance();
  final session = SessionService(const FlutterSecureStorage(), raw);
  await session.load();
  return session;
}

/// An enrolled till sent back to the activation screen (the admin asked for
/// re-activation): the live identity and token must survive any refusal.
Future<SessionService> _enrolledDevice() async {
  SharedPreferences.setMockInitialValues({
    BusinessBoundary.identityKey: _enrolled.encoded,
    BusinessBoundary.blockedKey: 'device_reactivation_required',
    'company_id': _enrolled.companyId,
    'branch_id': _enrolled.branchId,
    'device_uuid': _enrolled.deviceUuid,
    'kiosk_id': 'KIOSK-LIVE',
  });
  FlutterSecureStorage.setMockInitialValues({'device_token': 'live-token'});
  final raw = await SharedPreferences.getInstance();
  await BusinessBoundary.initialize(raw);
  final session = SessionService(
    const FlutterSecureStorage(),
    TenantPreferences(raw),
  );
  await session.load();
  return session;
}

Future<void> _expectEnrollmentIntact(
  WidgetTester tester,
  SessionService session,
) async {
  expect(session.deviceToken, 'live-token');
  expect(session.isConfigured, isTrue);
  expect(session.kioskId, 'KIOSK-LIVE');
  expect(BusinessBoundary.current?.encoded, _enrolled.encoded);
  expect(BusinessBoundary.blocked.value, 'device_reactivation_required');
  final stored = await tester.runAsync(
    () => const FlutterSecureStorage().read(key: 'device_token'),
  );
  expect(stored, 'live-token');
  final raw = await tester.runAsync(SharedPreferences.getInstance);
  expect(raw!.getString(BusinessBoundary.identityKey), _enrolled.encoded);
}

Future<void> _pumpSetup(
  WidgetTester tester,
  SessionService session,
  _ActivationServer server, {
  Locale locale = const Locale('en'),
}) async {
  // The T3's landscape screen; the default 800x600 hides the Continue button.
  tester.view.physicalSize = const Size(1280, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = PosApiService(
    tokenGetter: () => session.deviceToken,
    dio: Dio(BaseOptions(baseUrl: 'https://pos.test/api/v1'))
      ..httpClientAdapter = server,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionServiceProvider.overrideWithValue(session),
        apiServiceProvider.overrideWithValue(api),
        configRepositoryProvider.overrideWithValue(_NoConfigRepository()),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const DeviceSetupScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _activate(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(TextField), code);
  await _tapContinue(tester);
}

/// The enrollment screen's last button is Continue (activate).
Future<void> _tapContinue(WidgetTester tester) async {
  final button = find.byType(OutlinedButton).last;
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

class _ActivationServer implements HttpClientAdapter {
  _ActivationServer.success()
    : refusalCode = null,
      message = '',
      envelope = false;
  _ActivationServer.refusal(
    String this.refusalCode, {
    this.message = 'Activation refused.',
    this.envelope = false,
  });

  final String? refusalCode;
  final String message;

  /// true: `{data, errors:[{code,message}]}`; false: `{message, code}`.
  final bool envelope;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/auth/device/activate')) {
      bodies.add(
        (jsonDecode(jsonEncode(options.data)) as Map).cast<String, dynamic>(),
      );
      final code = refusalCode;
      if (code != null) {
        return _json(
          envelope
              ? {
                  'data': null,
                  'errors': [
                    {'code': code, 'message': message},
                  ],
                }
              : {'message': message, 'code': code},
          422,
        );
      }
      return _json({
        'data': {
          'device_token': 'new-device-token',
          'device': {
            'uuid': 'new-device-uuid',
            'company_id': 7,
            'branch_id': 8,
            'kiosk_id': 'KIOSK-NEW',
            'name': 'Front till',
          },
        },
        'errors': [],
      }, 200);
    }
    return _json({'message': 'Not Found'}, 404);
  }

  ResponseBody _json(Object body, int status) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

class _NoConfigRepository implements ConfigRepository {
  @override
  Future<void> fetchAndCache() async =>
      throw StateError('offline in this test');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

// --- geofence harness ----------------------------------------------------------

Future<SessionService> _sessionWithPrefs(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  FlutterSecureStorage.setMockInitialValues({'device_token': 'live-token'});
  final raw = await SharedPreferences.getInstance();
  final session = SessionService(const FlutterSecureStorage(), raw);
  await session.load();
  return session;
}

Future<void> _pumpGate(WidgetTester tester, SessionService session) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionServiceProvider.overrideWithValue(session),
        configRepositoryProvider.overrideWithValue(_FencedBranchRepository()),
      ],
      child: MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const GeofenceGate(child: Scaffold(body: Text('selling screen'))),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// A fenced branch in Muscat; the fake GPS puts the till ~40 km away.
class _FencedBranchRepository implements ConfigRepository {
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
  Future<LocationPermission> requestPermission() async =>
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
