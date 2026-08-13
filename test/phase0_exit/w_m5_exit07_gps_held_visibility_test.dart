// W-M5 / EXIT-07 — A GPS-held fenced sale must stay durable AND be
// operator-visible ("never silently lost"). Coverage-matrix flag F-1.
//
// Investigation (read-only, 2026-08-13) — every operator surface consuming
// pending/held outbox batches:
//   * lib/providers/providers.dart:260 `stuckOrderSyncProvider`
//     → OrderSyncRepository.watchStuck(), which filters
//       isStuck = serverRejections >= 5;
//   * lib/screens/settings_screen.dart — stuck-sales tile + detail dialog
//     (renders only when stuckRows is non-empty);
//   * lib/screens/staff_pos_screen.dart:4909 — the settings-gear badge count,
//     also fed by stuckOrderSyncProvider.
// No other lib/ consumer of watchPending()/watchStuck()/stuckBatches() exists.
//
// A GPS-held batch at a fenced branch (no valid fix) is deliberately held by
// order_sync_repository.dart _flushOnce WITHOUT a request, an attempt or a
// rejection (attempts=0, serverRejections=0) — so it can never satisfy
// isStuck and never reaches any of the surfaces above. This test pins the
// EXIT-07 contract that such revenue must be visible to the operator. If the
// final assertion FAILS, that is candidate finding F-1 (FAIL-PRODUCT against
// "never silently lost", or an owner clarification of "visible"); per the
// handoff the assertion must NOT be weakened to match current behavior.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/settings_screen.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a fenced sale held for GPS stays durable and surfaces to the operator',
    (tester) async {
      final originalGeolocator = GeolocatorPlatform.instance;
      GeolocatorPlatform.instance = _NoFixGeolocator();
      addTearDown(() => GeolocatorPlatform.instance = originalGeolocator);

      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final adapter = _ProcessedAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://pos.test'))
        ..httpClientAdapter = adapter;
      final api = PosApiService(tokenGetter: () => 'device-token', dio: dio);
      final repository = OrderSyncRepository(api, db);

      addTearDown(() async {
        dio.close(force: true);
        await db.close();
      });

      // A geofenced branch: create/pay must not reach the server without GPS.
      await db.into(db.branchCache).insert(BranchCacheCompanion.insert(
            id: const Value(1),
            latitude: const Value(23.59),
            longitude: const Value(58.38),
          ));

      await db.enqueueOutbox(OrderOutboxCompanion.insert(
        orderUuid: 'order-gps-held-001',
        eventsJson: jsonEncode([
          {
            'client_event_id': 'create-order-gps-held-001',
            'event_type': 'order.create',
            'client_timestamp': '2026-08-13T10:00:00.000Z',
            'payload': {
              'order': {
                'uuid': 'order-gps-held-001',
                'total_baisas': 6000,
                'lines': [
                  {'product_id': 11, 'qty': 2, 'unit_price_baisas': 3000},
                ],
              },
            },
          },
          {
            'client_event_id': 'pay-order-gps-held-001',
            'event_type': 'order.pay',
            'client_timestamp': '2026-08-13T10:00:01.000Z',
            'payload': {
              'order_uuid': 'order-gps-held-001',
              'method': 'cash',
              'amount_baisas': 6000,
            },
          },
        ]),
        orderNumber: const Value(1001),
        createdAt: DateTime.utc(2026, 8, 13, 10),
      ));

      // Derive the GPS-held state through a real flush: no fix is available,
      // so the batch is held without a request, attempt or rejection.
      expect(await _flush(tester, repository), 0);
      expect(adapter.requestCount, 0,
          reason: 'a fenced batch without GPS must never reach the server');

      final held = (await db.pendingOutbox()).single;
      expect(held.syncedAt, isNull, reason: 'the sale must stay durable');
      expect(held.attempts, 0);
      expect(held.serverRejections, 0);
      expect(OrderSyncRepository.isStuck(held), isFalse);

      // Visibility contract: the held revenue must appear on an operator
      // surface. The machine's only surface for un-synced revenue is the
      // stuck-sales tile (plus the gear badge fed by the same provider).
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            appDatabaseProvider.overrideWithValue(db),
            apiServiceProvider.overrideWithValue(api),
            orderSyncRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const SettingsScreen(showOperations: true),
          ),
        ),
      );
      await _pumpFrames(tester);

      final heldSaleVisible = find
          .byKey(const ValueKey('settings-stuck-sales-tile'))
          .evaluate()
          .isNotEmpty;

      // Dispose the provider subscription before the database teardown, so a
      // contract failure below reports cleanly.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));

      expect(
        heldSaleVisible,
        isTrue,
        reason: 'EXIT-07: a permanently GPS-held fenced sale is durable but '
            'must also be operator-visible ("never silently lost"). The only '
            'pending-batch operator surface (stuckOrderSyncProvider → '
            'watchStuck) filters serverRejections >= 5, and a GPS hold never '
            'increments rejections — so this batch appears on NO surface. '
            'Failure here is coverage-matrix flag F-1 (candidate '
            'FAIL-PRODUCT / owner clarification), not a harness defect.',
      );
    },
  );
}

/// Runs flush() to completion under the widget test's fake-async clock using
/// bounded frame pumps (no arbitrary sleeps).
Future<int> _flush(WidgetTester tester, OrderSyncRepository repository) async {
  int? synced;
  unawaited(repository.flush().then((value) => synced = value));
  for (var frame = 0; frame < 40 && synced == null; frame++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
  expect(synced, isNotNull,
      reason: 'flush() did not settle under the test pump');
  return synced!;
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// No GPS fix is ever available (permanently unfixable hold).
class _NoFixGeolocator extends GeolocatorPlatform {
  int requestCount = 0;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    requestCount++;
    return Future.error(StateError('no GPS fix available'));
  }
}

/// Would answer `processed` — but a GPS-held batch must never produce a
/// request at all, so [requestCount] staying 0 is part of the contract.
class _ProcessedAdapter implements HttpClientAdapter {
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    final body = (options.data as Map).cast<String, dynamic>();
    final events = (body['events'] as List).whereType<Map>();
    return ResponseBody.fromString(
      jsonEncode({
        'data': {
          'results': [
            for (final event in events)
              {
                'client_event_id': event['client_event_id'],
                'status': 'processed',
                'duplicate': false,
                'result': <String, dynamic>{},
              },
          ],
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
