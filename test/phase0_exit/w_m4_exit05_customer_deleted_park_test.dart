// W-M4 / EXIT-05 — End-to-end customer-deleted park: the parked state is
// DERIVED from real flush() passes against a deterministic customer-not-found
// rejection (never seeded), then the operator surface must display the order
// and the exact server error text for manual action.
//
// Contract (PHASE_0_EXIT_COVERAGE_MATRIX.md Part B, EXIT-05): a sale whose
// customer was deleted before replay is never discarded and never falsely
// processed — the deterministic rejection parks the batch at the 5-rejection
// cap, automatic retry stops, and the stuck-sales surface shows the order and
// the server's error verbatim.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/settings_screen.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _serverError =
    'Customer #4207 not found: the customer record was deleted before this '
    'sale could sync.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'five real customer-deleted rejections park the sale and the stuck '
    'surface shows the exact server error',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final adapter = _CustomerDeletedAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://pos.test'))
        ..httpClientAdapter = adapter;
      final api = PosApiService(tokenGetter: () => 'device-token', dio: dio);
      final repository = OrderSyncRepository(api, db);

      addTearDown(() async {
        dio.close(force: true);
        await db.close();
      });

      await db.enqueueOutbox(OrderOutboxCompanion.insert(
        orderUuid: 'order-cust-deleted-001',
        eventsJson: jsonEncode([
          {
            'client_event_id': 'create-order-cust-deleted-001',
            'event_type': 'order.create',
            'client_timestamp': '2026-08-13T10:00:00.000Z',
            'payload': {
              'order': {
                'uuid': 'order-cust-deleted-001',
                'total_baisas': 2750,
                'customer_id': 4207,
                'lines': [
                  {'product_id': 11, 'qty': 1, 'unit_price_baisas': 2750},
                ],
              },
            },
          },
          {
            'client_event_id': 'pay-order-cust-deleted-001',
            'event_type': 'order.pay',
            'client_timestamp': '2026-08-13T10:00:01.000Z',
            'payload': {
              'order_uuid': 'order-cust-deleted-001',
              'method': 'cash',
              'amount_baisas': 2750,
              'customer_id': 4207,
            },
          },
        ]),
        orderNumber: const Value(1001),
        createdAt: DateTime.utc(2026, 8, 13, 10),
      ));

      // Derive the park through five REAL flush passes — never seeded.
      for (var pass = 1; pass <= 5; pass++) {
        expect(await _flush(tester, repository), 0,
            reason: 'pass $pass must not settle a rejected sale');
      }
      expect(adapter.requestCount, 5);

      final parked = (await db.pendingOutbox()).single;
      expect(parked.syncedAt, isNull,
          reason: 'the sale must never be falsely processed');
      expect(parked.attempts, 5);
      expect(parked.serverRejections, 5);
      expect(parked.lastError, _serverError,
          reason: 'the exact server error must be retained for the operator');
      expect(OrderSyncRepository.isStuck(parked), isTrue);

      // Automatic retry stops at the cap.
      expect(await _flush(tester, repository), 0);
      expect(adapter.requestCount, 5,
          reason: 'a parked sale must not keep hammering the server');

      // Operator surface: the derived park is visible with its details.
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

      expect(
        find.byKey(const ValueKey('settings-stuck-sales-tile')),
        findsOneWidget,
      );
      expect(find.text('Stuck sales (1)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('settings-stuck-sales-tile')));
      await _pumpFrames(tester);

      expect(find.text('Order #1001'), findsOneWidget);
      expect(find.text(_serverError), findsOneWidget,
          reason: 'the dialog must show the server error text verbatim');

      await tester.tap(find.text('Close'));
      await _pumpFrames(tester);

      // The park survives the surface visit untouched (manual retry only).
      final still = (await db.pendingOutbox()).single;
      expect(still.serverRejections, 5);
      expect(adapter.requestCount, 5);

      // Dispose the provider subscription before the database teardown.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
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

/// Deterministic customer-deleted rejection: order.create settles (a replay
/// echoes it as a duplicate), order.pay always fails with the same
/// customer-not-found error body — the batch can never fully process.
class _CustomerDeletedAdapter implements HttpClientAdapter {
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    final body = (options.data as Map).cast<String, dynamic>();
    final events = (body['events'] as List)
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    return ResponseBody.fromString(
      jsonEncode({
        'data': {
          'results': [
            for (final event in events)
              event['event_type'] == 'order.create'
                  ? {
                      'client_event_id': event['client_event_id'],
                      'status': 'processed',
                      'duplicate': requestCount > 1,
                      'result': {'order_id': 501},
                    }
                  : {
                      'client_event_id': event['client_event_id'],
                      'status': 'failed',
                      'duplicate': false,
                      'result': {'error': _serverError},
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
