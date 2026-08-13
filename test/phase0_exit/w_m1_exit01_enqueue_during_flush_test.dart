// W-M1 / EXIT-01 — Machine offline backlog + concurrent enqueue while flushing.
//
// Contract (PHASE_0_EXIT_COVERAGE_MATRIX.md Part B, EXIT-01): while a flush()
// pass is blocked awaiting its HTTP response, newly completed sales keep
// landing in the durable Drift outbox. No outbox row may be lost or duplicated:
// after the in-flight pass settles, every row is either drained-with-processed-
// ACK or still pending, and a subsequent flush drains the remainder exactly
// once. Deterministic concurrency: the fake Dio adapter is gated on Completers
// (no sleeps), against the real in-memory Drift outbox and the real
// OrderSyncRepository.

import 'dart:async';
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
    'sales enqueued while a flush awaits its response are neither lost nor '
    'duplicated, and a subsequent flush drains them exactly once',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      final db = harness.db;
      final adapter = harness.adapter;

      await _enqueueSale(db, 'backlog-1',
          createdAt: DateTime.utc(2026, 8, 13, 10, 0));
      await _enqueueSale(db, 'backlog-2',
          createdAt: DateTime.utc(2026, 8, 13, 10, 1));

      // Start the flush and hold it inside its first HTTP request.
      final inFlightFlush = harness.repository.flush();
      await adapter.firstRequestStarted.future;

      // Three new sale batches land mid-flight (a busy till keeps selling
      // while the earlier backlog is still on the wire).
      await _enqueueSale(db, 'concurrent-1',
          createdAt: DateTime.utc(2026, 8, 13, 10, 2));
      await _enqueueSale(db, 'concurrent-2',
          createdAt: DateTime.utc(2026, 8, 13, 10, 3));
      await _enqueueSale(db, 'concurrent-3',
          createdAt: DateTime.utc(2026, 8, 13, 10, 4));

      adapter.release();
      expect(await inFlightFlush, 2,
          reason: 'the gated pass saw only the two backlog rows');

      final rows = {
        for (final row in await db.select(db.orderOutbox).get())
          row.orderUuid: row,
      };
      expect(rows.length, 5, reason: 'no outbox row may be lost');
      expect(rows['backlog-1']!.syncedAt, isNotNull);
      expect(rows['backlog-2']!.syncedAt, isNotNull);
      for (final uuid in ['concurrent-1', 'concurrent-2', 'concurrent-3']) {
        final row = rows[uuid]!;
        expect(row.syncedAt, isNull,
            reason: '$uuid must still be pending after the in-flight pass');
        expect(row.attempts, 0,
            reason: '$uuid must not have been sent mid-flight');
        expect(row.serverRejections, 0);
      }
      expect(
        adapter.sentEventIds,
        [
          'create-backlog-1',
          'pay-backlog-1',
          'create-backlog-2',
          'pay-backlog-2',
        ],
        reason: 'the in-flight pass must not send the concurrent rows',
      );

      // A subsequent flush drains the mid-flight rows — exactly once.
      expect(await harness.repository.flush(), 3);

      expect(await db.pendingOutbox(), isEmpty);
      expect(
        _countByEventId(adapter.sentEventIds),
        _exactlyOnceFor([
          'backlog-1',
          'backlog-2',
          'concurrent-1',
          'concurrent-2',
          'concurrent-3',
        ]),
        reason: 'every event drained exactly once — no duplicate send',
      );
    },
  );

  test(
    'a flush requested while another is mid-flight runs afterwards, sees the '
    'new rows, and never double-sends anything',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      final db = harness.db;
      final adapter = harness.adapter;

      await _enqueueSale(db, 'backlog-1',
          createdAt: DateTime.utc(2026, 8, 13, 11, 0));

      final first = harness.repository.flush();
      await adapter.firstRequestStarted.future;

      await _enqueueSale(db, 'concurrent-1',
          createdAt: DateTime.utc(2026, 8, 13, 11, 1));
      await _enqueueSale(db, 'concurrent-2',
          createdAt: DateTime.utc(2026, 8, 13, 11, 2));
      await _enqueueSale(db, 'concurrent-3',
          createdAt: DateTime.utc(2026, 8, 13, 11, 3));

      // A reconnect / new-sale trigger overlaps the in-flight pass. The
      // repository serializes it; it must run afterwards and see the new rows.
      final queued = harness.repository.flush();

      adapter.release();
      expect(await first, 1);
      expect(await queued, 3);

      expect(await db.pendingOutbox(), isEmpty);
      expect(
        _countByEventId(adapter.sentEventIds),
        _exactlyOnceFor(
            ['backlog-1', 'concurrent-1', 'concurrent-2', 'concurrent-3']),
        reason: 'the overlapping flush must not re-send any settled batch',
      );

      // Nothing is left: one more pass sends no request at all.
      expect(await harness.repository.flush(), 0);
      expect(adapter.requestCount, 4);
    },
  );
}

/// One durable money batch (order.create + order.pay, integer baisas on the
/// wire) with stable client_event_ids derived from the order uuid.
Future<void> _enqueueSale(
  AppDatabase db,
  String orderUuid, {
  required DateTime createdAt,
}) =>
    db.enqueueOutbox(OrderOutboxCompanion.insert(
      orderUuid: orderUuid,
      eventsJson: jsonEncode([
        {
          'client_event_id': 'create-$orderUuid',
          'event_type': 'order.create',
          'client_timestamp': createdAt.toIso8601String(),
          'payload': {
            'order': {
              'uuid': orderUuid,
              'total_baisas': 4500,
              'lines': [
                {'product_id': 11, 'qty': 1, 'unit_price_baisas': 4500},
              ],
            },
          },
        },
        {
          'client_event_id': 'pay-$orderUuid',
          'event_type': 'order.pay',
          'client_timestamp': createdAt.toIso8601String(),
          'payload': {
            'order_uuid': orderUuid,
            'method': 'cash',
            'amount_baisas': 4500,
          },
        },
      ]),
      orderNumber: const Value(1001),
      createdAt: createdAt,
    ));

Map<String, int> _countByEventId(List<String> ids) {
  final counts = <String, int>{};
  for (final id in ids) {
    counts[id] = (counts[id] ?? 0) + 1;
  }
  return counts;
}

Map<String, int> _exactlyOnceFor(List<String> orderUuids) => {
      for (final uuid in orderUuids) ...{
        'create-$uuid': 1,
        'pay-$uuid': 1,
      },
    };

class _Harness {
  _Harness()
      : db = AppDatabase.forTesting(NativeDatabase.memory()),
        adapter = _GatedProcessedAdapter() {
    dio = Dio(BaseOptions(baseUrl: 'https://pos.test'))
      ..httpClientAdapter = adapter;
    repository = OrderSyncRepository(
      PosApiService(tokenGetter: () => 'device-token', dio: dio),
      db,
    );
  }

  final AppDatabase db;
  final _GatedProcessedAdapter adapter;
  late final Dio dio;
  late final OrderSyncRepository repository;

  Future<void> close() async {
    dio.close(force: true);
    await db.close();
  }
}

/// Answers every push `processed`, but holds each response behind a Completer
/// gate. [firstRequestStarted] fires as soon as the first request has been
/// received (the flush is then deterministically mid-flight); [release] lets
/// every held and subsequent response through.
class _GatedProcessedAdapter implements HttpClientAdapter {
  final Completer<void> firstRequestStarted = Completer<void>();
  final Completer<void> _gate = Completer<void>();
  final List<String> sentEventIds = [];
  int requestCount = 0;

  void release() => _gate.complete();

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
    sentEventIds.addAll(events.map((e) => e['client_event_id'].toString()));
    if (!firstRequestStarted.isCompleted) firstRequestStarted.complete();
    await _gate.future;
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
