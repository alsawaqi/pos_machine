import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/services/pos_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const maxServerRejections = 5;

  test(
    'five server rejections park a batch before a sixth automatic push',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final adapter = _SyncAdapter(_SyncOutcome.rejected);
      final dio = Dio(BaseOptions(baseUrl: 'https://pos.test'))
        ..httpClientAdapter = adapter;
      final repository = OrderSyncRepository(
        PosApiService(tokenGetter: () => 'device-token', dio: dio),
        db,
      );

      addTearDown(() async {
        dio.close(force: true);
        await db.close();
      });

      await db.enqueueOutbox(
        OrderOutboxCompanion.insert(
          orderUuid: 'order-001',
          eventsJson: jsonEncode([
            {
              'client_event_id': 'event-001',
              'event_type': 'order.create',
              'payload': <String, dynamic>{},
            },
          ]),
          orderNumber: const Value(1001),
          createdAt: DateTime.utc(2026, 8, 8, 10),
        ),
      );

      for (var attempt = 0; attempt < maxServerRejections; attempt++) {
        await repository.flush();
      }
      expect(adapter.requestCount, maxServerRejections);

      await repository.flush();

      expect(
        adapter.requestCount,
        maxServerRejections,
        reason: 'A parked revenue batch must not keep hammering the server.',
      );
      final queued = await db.pendingOutbox();
      expect(queued.single.syncedAt, isNull);
      expect(queued.single.attempts, maxServerRejections);
      expect(queued.single.serverRejections, maxServerRejections);
    },
  );

  test(
    'transport failures retry forever without advancing rejection count',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final adapter = _SyncAdapter(_SyncOutcome.networkFailure);
      final dio = Dio(BaseOptions(baseUrl: 'https://pos.test'))
        ..httpClientAdapter = adapter;
      final repository = OrderSyncRepository(
        PosApiService(tokenGetter: () => 'device-token', dio: dio),
        db,
      );

      addTearDown(() async {
        dio.close(force: true);
        await db.close();
      });

      await _enqueue(db, orderUuid: 'offline-order');

      for (var attempt = 0; attempt < 7; attempt++) {
        await repository.flush();
      }

      final queued = (await db.pendingOutbox()).single;
      expect(adapter.requestCount, 7);
      expect(queued.attempts, 7);
      expect(queued.serverRejections, 0);
      expect(OrderSyncRepository.isStuck(queued), isFalse);
    },
  );

  test('a stuck row does not block a later healthy row', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final adapter = _SyncAdapter(_SyncOutcome.processed);
    final dio = Dio(BaseOptions(baseUrl: 'https://pos.test'))
      ..httpClientAdapter = adapter;
    final repository = OrderSyncRepository(
      PosApiService(tokenGetter: () => 'device-token', dio: dio),
      db,
    );

    addTearDown(() async {
      dio.close(force: true);
      await db.close();
    });

    await _enqueue(
      db,
      orderUuid: 'stuck-order',
      serverRejections: maxServerRejections,
      createdAt: DateTime.utc(2026, 8, 8, 9),
    );
    await _enqueue(
      db,
      orderUuid: 'healthy-order',
      createdAt: DateTime.utc(2026, 8, 8, 10),
    );

    expect(await repository.flush(), 1);

    final rows = await db.pendingOutbox();
    expect(adapter.requestCount, 1);
    expect(rows.map((row) => row.orderUuid), ['stuck-order']);
    expect(rows.single.syncedAt, isNull);
  });

  test('manual retry un-parks and reuses the durable batch', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final adapter = _SyncAdapter(_SyncOutcome.processed);
    final dio = Dio(BaseOptions(baseUrl: 'https://pos.test'))
      ..httpClientAdapter = adapter;
    final repository = OrderSyncRepository(
      PosApiService(tokenGetter: () => 'device-token', dio: dio),
      db,
    );

    addTearDown(() async {
      dio.close(force: true);
      await db.close();
    });

    await _enqueue(
      db,
      orderUuid: 'retry-order',
      serverRejections: maxServerRejections,
    );

    expect(await repository.retryStuck(), 1);

    final rows = await db.pendingOutbox();
    expect(adapter.requestCount, 1);
    expect(rows, isEmpty);
  });
}

Future<void> _enqueue(
  AppDatabase db, {
  required String orderUuid,
  int serverRejections = 0,
  DateTime? createdAt,
}) => db.enqueueOutbox(
  OrderOutboxCompanion.insert(
    orderUuid: orderUuid,
    eventsJson: jsonEncode([
      {
        'client_event_id': 'event-$orderUuid',
        'event_type': 'order.create',
        'payload': <String, dynamic>{},
      },
    ]),
    orderNumber: const Value(1001),
    createdAt: createdAt ?? DateTime.utc(2026, 8, 8, 10),
    serverRejections: Value(serverRejections),
  ),
);

enum _SyncOutcome { processed, rejected, networkFailure }

class _SyncAdapter implements HttpClientAdapter {
  _SyncAdapter(this.outcome);

  final _SyncOutcome outcome;
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    if (outcome == _SyncOutcome.networkFailure) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'offline',
      );
    }

    final body = (options.data as Map).cast<String, dynamic>();
    final events = (body['events'] as List).whereType<Map>();
    return ResponseBody.fromString(
      jsonEncode({
        'data': {
          'results': [
            for (final event in events)
              {
                'client_event_id': event['client_event_id'],
                'status': outcome == _SyncOutcome.processed
                    ? 'processed'
                    : 'failed',
                'duplicate': false,
                'result': outcome == _SyncOutcome.processed
                    ? <String, dynamic>{}
                    : {'error': 'server rejected the sale'},
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
