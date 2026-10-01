// LAUNCH-P1 device finding: after a successful re-activation started from the
// tenancy gate's "Activate device" button, the till must leave enrollment.
//
// Seen on the T3 (2026-10-01): the server activated the device and the till
// heartbeated with the new token, but the screen stayed on "Set up this
// device" until the app was restarted. Two causes: the post-activation refresh
// invalidated providers that listen to the session through the session's own
// ref (a circular dependency in debug builds, so the state never flipped), and
// the activation navigator shared the app's HeroController.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/config_repository.dart';
import 'package:pos_machine/data/table_shadow_repository.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/device_setup_screen.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
import 'package:pos_machine/tenancy/tenancy_gate.dart';
import 'package:pos_machine/tenancy/tenant_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _identityChannel = MethodChannel('mithqal/device_identity');
const _enrolled = BusinessIdentity(1, 2, 'live-device-uuid');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(BusinessBoundary.resetForTest);
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_identityChannel, null);
    BusinessBoundary.resetForTest();
  });

  for (final sameDevice in const [true, false]) {
    testWidgets('a revoked till re-activated from the gate leaves enrollment '
        '(${sameDevice ? 'same' : 'another'} identity)', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            _identityChannel,
            (call) async => switch (call.method) {
              'getSerial' => 'TV07P58G40097',
              'getBuildInfo' => {'manufacturer': 'SUNMI', 'model': 'T3'},
              _ => null,
            },
          );
      final session = (await tester.runAsync(_enrolledDevice))!;
      final server = _ActivationServer(
        sameDevice ? _enrolled : const BusinessIdentity(7, 8, 'new-uuid'),
      );
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = PosApiService(
        tokenGetter: () => session.deviceToken,
        dio: Dio(BaseOptions(baseUrl: 'https://pos.test/api/v1'))
          ..httpClientAdapter = server,
      );
      var tableShadowBuilds = 0;
      final container = ProviderContainer(
        overrides: [
          sessionServiceProvider.overrideWithValue(session),
          apiServiceProvider.overrideWithValue(api),
          configRepositoryProvider.overrideWithValue(_NoConfigRepository()),
          // Like the real repository: it listens to the session and is
          // rebuilt after a new activation.
          tableShadowRepositoryProvider.overrideWith((ref) {
            tableShadowBuilds++;
            ref.listen(sessionControllerProvider, (_, _) {});
            return _NoTableShadowRepository();
          }),
        ],
      );
      addTearDown(container.dispose);
      container.listen(tableShadowRepositoryProvider, (_, _) {});
      expect(tableShadowBuilds, 1);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            builder: (context, child) => TenancyGate(
              activation: (_) => const DeviceSetupScreen(),
              child: child!,
            ),
            home: const _StartupGateProbe(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('selling screen'), findsOneWidget);

      // The admin revoked the token: a 401 drops the till back to pairing.
      await tester.runAsync(
        () =>
            container.read(sessionControllerProvider.notifier).clearForRePair(),
      );
      await tester.pumpAndSettle();
      expect(find.text('This device needs activation'), findsOneWidget);

      await tester.tap(find.text('Activate device'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'THIS-DEVICE-CODE');
      final button = find.byType(OutlinedButton).last;
      await tester.ensureVisible(button);
      await tester.runAsync(() async {
        await tester.tap(button);
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();

      expect(server.activations, 1);
      expect(session.isConfigured, isTrue);
      expect(BusinessBoundary.blocked.value, isNull);
      expect(container.read(sessionControllerProvider).isConfigured, isTrue);
      expect(find.byType(DeviceSetupScreen), findsNothing);
      expect(find.text('selling screen'), findsOneWidget);
      // The new identity's table repository replaced the old one.
      container.read(tableShadowRepositoryProvider);
      expect(tableShadowBuilds, 2);
    });
  }
}

/// The first branch of StaffStartupGate: not configured -> enrollment.
class _StartupGateProbe extends ConsumerWidget {
  const _StartupGateProbe();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.isConfigured) return const DeviceSetupScreen();
    return const Scaffold(body: Text('selling screen'));
  }
}

Future<SessionService> _enrolledDevice() async {
  SharedPreferences.setMockInitialValues({
    BusinessBoundary.identityKey: _enrolled.encoded,
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

class _ActivationServer implements HttpClientAdapter {
  _ActivationServer(this.identity);
  final BusinessIdentity identity;
  int activations = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/auth/device/activate')) {
      activations++;
      return _json({
        'data': {
          'device_token': 'new-device-token',
          'device': {
            'uuid': identity.deviceUuid,
            'company_id': identity.companyId,
            'branch_id': identity.branchId,
            'kiosk_id': 'KIOSK-LIVE',
            'name': 'Front till',
            'location_mode': 'branch',
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

class _NoTableShadowRepository implements TableShadowRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoConfigRepository implements ConfigRepository {
  @override
  Future<void> fetchAndCache() async =>
      throw StateError('offline in this test');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
