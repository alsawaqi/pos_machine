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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('stuck sale is visible with details and can be retried',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final adapter = _ProcessedSyncAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://pos.test'))
      ..httpClientAdapter = adapter;
    final api = PosApiService(tokenGetter: () => 'device-token', dio: dio);
    final repository = OrderSyncRepository(api, db);

    addTearDown(() async {
      dio.close(force: true);
      await db.close();
    });

    await db.enqueueOutbox(OrderOutboxCompanion.insert(
      orderUuid: 'stuck-operator-sale',
      eventsJson: jsonEncode([
        {
          'client_event_id': 'event-stuck-operator-sale',
          'event_type': 'order.create',
          'payload': <String, dynamic>{},
        },
      ]),
      orderNumber: const Value(1001),
      createdAt: DateTime.utc(2026, 8, 8, 10),
      attempts: const Value(5),
      serverRejections: const Value(5),
      lastError: const Value('customer was deleted'),
    ));

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
    expect(find.text('customer was deleted'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('settings-stuck-sales-retry-all')),
    );
    for (var frame = 0; frame < 20 && adapter.requestCount == 0; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _pumpFrames(tester);

    expect(adapter.requestCount, 1);
    expect(await db.pendingOutbox(), isEmpty);
    expect(
      find.byKey(const ValueKey('settings-stuck-sales-tile')),
      findsNothing,
    );

    // Dispose the provider subscription before the database teardown.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _ProcessedSyncAdapter implements HttpClientAdapter {
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
