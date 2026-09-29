import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/tenancy/business_identity.dart';
import '../lib/tenancy/tenant_preferences.dart';
import '../lib/tenancy/tenancy_gate.dart';
import '../lib/tenancy/tenancy_interceptor.dart';
import '../lib/tenancy/device_heartbeat.dart';

const oldOwner = BusinessIdentity(11, 21, 'device-uuid');
const newOwner = BusinessIdentity(12, 22, 'device-uuid');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences raw;
  setUp(() async {
    BusinessBoundary.resetForTest();
    SharedPreferences.setMockInitialValues({
      BusinessBoundary.identityKey: oldOwner.encoded,
    });
    raw = await SharedPreferences.getInstance();
    await BusinessBoundary.initialize(raw);
  });
  tearDown(() {
    DeviceHeartbeat.stop();
    BusinessBoundary.resetForTest();
  });

  test(
    'W2 changed company or branch wipes business preferences and retains device settings',
    () async {
      final prefs = await businessPreferences();
      await prefs.setString('server_base_url', 'http://local.test');
      await prefs.setString('printer_address', 'local-printer');
      for (final key in [
        'held_order',
        'history',
        'draft',
        'table',
        'print_cursor',
        'report',
        'customer_cache',
        'softpos_profile',
        'manager_fingerprint',
        'config',
      ]) {
        await prefs.setString(key, 'old merchant data');
        expect(raw.getString('_p0.tag.$key'), oldOwner.encoded);
      }
      await prefs.setString(
        'order_outbox_v1',
        jsonEncode([
          BusinessBoundary.stamp({'amount': 1200}),
        ]),
      );
      await BusinessBoundary.accept(newOwner);
      for (final key in [
        'held_order',
        'history',
        'draft',
        'table',
        'print_cursor',
        'report',
        'customer_cache',
        'softpos_profile',
        'manager_fingerprint',
        'config',
        'order_outbox_v1',
      ]) {
        expect(raw.containsKey(key), false, reason: key);
      }
      expect(prefs.getString('server_base_url'), 'http://local.test');
      expect(prefs.getString('printer_address'), 'local-printer');
      expect(BusinessBoundary.quarantinedCount, 1);
      expect(BusinessBoundary.current!.encoded, newOwner.encoded);
    },
  );

  test(
    'W2 a paused old preference write cannot overwrite a newly activated owner',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final delayed = _PausedTagRemoval(raw, entered, release);
      final write = TenantPreferences(
        delayed,
      ).setString('draft', 'old owner draft');
      final rejected = expectLater(write, throwsStateError);
      await entered.future;
      await BusinessBoundary.accept(
        newOwner,
        install: () async {
          await TenantPreferences(raw).setString('draft', 'new owner draft');
        },
      );
      release.complete();
      await rejected;
      expect(raw.getString('draft'), 'new owner draft');
      expect(raw.getString('_p0.tag.draft'), newOwner.encoded);
    },
  );

  test('W2 same identity activation preserves its business records', () async {
    final prefs = await businessPreferences();
    await prefs.setString('draft', 'mine');
    BusinessBoundary.block('device_reactivation_required');
    await BusinessBoundary.accept(oldOwner);
    expect(prefs.getString('draft'), 'mine');
    expect(BusinessBoundary.canWork, true);
    await BusinessBoundary.accept(
      const BusinessIdentity(11, 99, 'device-uuid'),
    );
    expect(prefs.getString('draft'), isNull);
  });

  test(
    'W2 interrupted transition stays blocked on restart and retries the wipe',
    () async {
      final prefs = await businessPreferences();
      await prefs.setString('draft', 'old');
      Future<void> fail() async => throw StateError('storage unavailable');
      BusinessBoundary.registerWiper(fail);
      await expectLater(BusinessBoundary.accept(newOwner), throwsStateError);
      expect(raw.getString('draft'), 'old');
      expect(raw.containsKey(BusinessBoundary.transitionKey), true);
      await BusinessBoundary.initialize(raw);
      expect(BusinessBoundary.canWork, false);
      BusinessBoundary.unregisterWiper(fail);
      await BusinessBoundary.accept(newOwner);
      expect(raw.getString('draft'), isNull);
      expect(BusinessBoundary.canWork, true);
    },
  );

  test(
    'W2 activation stays blocked until credentials finish persisting',
    () async {
      await BusinessBoundary.accept(
        newOwner,
        install: () async {
          expect(BusinessBoundary.canWork, false);
          await TenantPreferences(raw).setString('softpos_profile', 'new bank');
        },
      );
      expect(BusinessBoundary.canWork, true);
      expect(TenantPreferences(raw).getString('softpos_profile'), 'new bank');
    },
  );

  test(
    'W2 foreign preference outbox is quarantined before another write can overwrite it',
    () async {
      await raw.setString('order_outbox_v1', '[{"money":1200}]');
      await raw.setString('_p0.tag.order_outbox_v1', newOwner.encoded);
      final prefs = await businessPreferences();
      expect(prefs.getString('order_outbox_v1'), isNull);
      expect(BusinessBoundary.quarantinedCount, 1);
      await prefs.setString('order_outbox_v1', '[]');
      expect(BusinessBoundary.quarantinedCount, 1);
    },
  );

  for (final refusal in [
    (401, 'device_reactivation_required'),
    (403, 'company_suspended'),
    (409, 'device_unassigned'),
  ]) {
    testWidgets('W2 blocks every route and keeps records: ' + refusal.$2, (
      tester,
    ) async {
      final prefs = await businessPreferences();
      await prefs.setString('draft', 'preserved');
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => TenancyGate(
            child: child!,
            activation: (_) => const Scaffold(body: Text('activation form')),
          ),
          home: const Scaffold(body: Text('selling screen')),
        ),
      );
      BusinessBoundary.observeError(refusal.$1, refusal.$2);
      await tester.pumpAndSettle();
      expect(find.text('selling screen'), findsNothing);
      expect(
        find.text(
          refusal.$1 == 403
              ? 'Account suspended'
              : 'This device needs activation',
        ),
        findsOneWidget,
      );
      expect(raw.getString('draft'), 'preserved');
      expect(BusinessBoundary.canWork, false);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    test(
      'W2 actual Dio refusal blocks subsequent business requests: ' +
          refusal.$2,
      () async {
        final adapter = _Adapter(refusal.$1, {
          'errors': [
            {'code': refusal.$2},
          ],
        });
        final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
          ..httpClientAdapter = adapter;
        dio.interceptors.add(TenancyInterceptor());
        try {
          await dio.get<dynamic>('/device/config');
        } on DioException {}
        expect(BusinessBoundary.canWork, false);
        await expectLater(
          dio.post<dynamic>('/device/sync/push', data: {}),
          throwsA(isA<DioException>()),
        );
        expect(adapter.calls, 1);
        dio.close();
      },
    );
  }

  test(
    'W2 suspended account resumes only after a successful heartbeat for the same generation',
    () async {
      BusinessBoundary.block('company_suspended');
      await BusinessBoundary.confirmHeartbeat(
        BusinessBoundary.generation.value + 1,
      );
      expect(BusinessBoundary.canWork, false);
      await BusinessBoundary.confirmHeartbeat(
        BusinessBoundary.generation.value,
      );
      expect(BusinessBoundary.canWork, true);
    },
  );
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);
  final int status;
  final Map<String, dynamic> body;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _PausedTagRemoval implements SharedPreferences {
  _PausedTagRemoval(this.raw, this.entered, this.release);
  final SharedPreferences raw;
  final Completer<void> entered;
  final Completer<void> release;
  @override
  Future<bool> remove(String key) async {
    final result = await raw.remove(key);
    if (key == '_p0.tag.draft') {
      entered.complete();
      await release.future;
    }
    return result;
  }

  @override
  Future<bool> setString(String key, String value) => raw.setString(key, value);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected test preference operation');
}
