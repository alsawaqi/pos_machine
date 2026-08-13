// W-M2 / EXIT-03 — Response-loss replay against a stored (duplicate) ACK.
//
// Contract (PHASE_0_EXIT_COVERAGE_MATRIX.md Part B, EXIT-03): the server
// processes a push, but the response never reaches the device (connection dies
// on the response leg). The durable batch must be re-sent with the SAME
// client_event_ids verbatim; the replay is answered with the server's stored
// processed/duplicate ACK; the batch settles locally exactly once and no third
// send ever occurs. A lost response is transport loss — it must never advance
// the server-rejection (parking) counter.

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

  test(
    'a batch whose response was lost replays verbatim and settles exactly '
    'once on the stored ACK, with no third send',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final adapter = _ResponseLossAdapter();
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

      await db.enqueueOutbox(OrderOutboxCompanion.insert(
        orderUuid: 'order-replay-001',
        eventsJson: jsonEncode([
          {
            'client_event_id': 'create-order-replay-001',
            'event_type': 'order.create',
            'client_timestamp': '2026-08-13T10:00:00.000Z',
            'payload': {
              'order': {
                'uuid': 'order-replay-001',
                'total_baisas': 5250,
                'lines': [
                  {'product_id': 11, 'qty': 1, 'unit_price_baisas': 5250},
                ],
              },
            },
          },
          {
            'client_event_id': 'pay-order-replay-001',
            'event_type': 'order.pay',
            'client_timestamp': '2026-08-13T10:00:01.000Z',
            'payload': {
              'order_uuid': 'order-replay-001',
              'method': 'cash',
              'amount_baisas': 5250,
            },
          },
        ]),
        orderNumber: const Value(1002),
        createdAt: DateTime.utc(2026, 8, 13, 10),
      ));

      // Pass 1 — the server records (processes) the push, then the response
      // is lost. Locally this is a transport failure: durable, retryable,
      // never a rejection.
      expect(await repository.flush(), 0);
      expect(adapter.requests, hasLength(1));
      final afterLoss = (await db.pendingOutbox()).single;
      expect(afterLoss.syncedAt, isNull,
          reason: 'no ACK arrived — the batch must stay durably queued');
      expect(afterLoss.attempts, 1);
      expect(afterLoss.serverRejections, 0,
          reason: 'a lost response must not count toward parking');
      expect(OrderSyncRepository.isStuck(afterLoss), isFalse);

      // Pass 2 — the replay. The server answers its stored processed ACK
      // (duplicate: true) instead of applying the effects again.
      expect(await repository.flush(), 1);
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests[1],
        adapter.requests[0],
        reason: 'the replay must re-send the SAME client_event_ids and '
            'payloads verbatim from the durable batch',
      );

      final settledRows = await db.select(db.orderOutbox).get();
      expect(settledRows, hasLength(1),
          reason: 'exactly one durable row — settled once, never cloned');
      expect(settledRows.single.syncedAt, isNotNull);
      expect(settledRows.single.serverRejections, 0);

      // Pass 3 — the batch already settled: nothing may be sent again.
      expect(await repository.flush(), 0);
      expect(adapter.requests, hasLength(2),
          reason: 'no third send may occur after the stored ACK settled it');
    },
  );
}

/// First push: records the request (the server DID process it), then throws
/// before the response is delivered. Replays: answers the stored ACK
/// (processed + duplicate:true), mimicking pos_api's idempotency-store echo.
class _ResponseLossAdapter implements HttpClientAdapter {
  /// Deep-copied request batches in arrival order — recorded even when the
  /// response is subsequently lost, exactly like a server that committed the
  /// batch before the connection died.
  final List<List<Map<String, dynamic>>> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = (options.data as Map).cast<String, dynamic>();
    final events = (jsonDecode(jsonEncode(body['events'])) as List)
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    requests.add(events);

    if (requests.length == 1) {
      // The server committed the batch, but the response never arrives.
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'response lost after server-side processing',
      );
    }

    return ResponseBody.fromString(
      jsonEncode({
        'data': {
          'results': [
            for (final event in events)
              {
                'client_event_id': event['client_event_id'],
                'status': 'processed',
                'duplicate': true,
                'result': {'status': 'paid'},
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
