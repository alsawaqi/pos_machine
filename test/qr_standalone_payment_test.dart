import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/services/pos_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const orderUuid = '11111111-1111-4111-8111-111111111111';
  const firstEventUuid = '22222222-2222-4222-8222-222222222222';
  const secondEventUuid = '33333333-3333-4333-8333-333333333333';

  test(
    'standalone QR pay is one exact-baisas GPS event with a wire UUID',
    () async {
      final harness = _Harness([_SyncOutcome.processed]);
      addTearDown(harness.close);

      final result = await harness.repository.enqueueStandaloneQrPay(
        orderUuid: orderUuid,
        frozenAmountBaisas: 4750,
        method: 'cash',
        lat: 23.588,
        lng: 58.383,
        paidAt: DateTime.utc(2026, 8, 30, 12),
        newUuid: () => firstEventUuid,
      );

      expect(result.state, StandaloneQrPayState.processed);
      expect(result.outboxKey, '$orderUuid:pay');
      expect(result.clientEventId, firstEventUuid);
      expect(harness.adapter.requests, hasLength(1));

      final events = harness.adapter.requests.single;
      expect(events, hasLength(1));
      final event = events.single;
      expect(event['event_type'], 'order.pay');
      expect(event['client_event_id'], firstEventUuid);
      expect(
        event['client_event_id'],
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(event['client_event_id'], isNot('$orderUuid:pay'));

      final payload = (event['payload'] as Map).cast<String, dynamic>();
      expect(payload['order_uuid'], orderUuid);
      expect(payload['gps'], {'lat': 23.588, 'lng': 58.383});
      expect(
        payload.keys,
        // LAUNCH-P5 C3 — plus the P5 wire marker.
        unorderedEquals(['order_uuid', 'paid_at', 'payments', 'gps', 'auth_v']),
      );
      final payments = (payload['payments'] as List).cast<Map>();
      expect(payments, hasLength(1));
      expect(payments.single, {
        'method': 'cash',
        'amount_baisas': 4750,
        'status': 'success',
      });
      expect(
        jsonEncode(events),
        isNot(anyOf(contains('order.create'), contains('order.hold'))),
      );
    },
  );

  test('a processed pay is terminal and cannot be overwritten', () async {
    final harness = _Harness([_SyncOutcome.processed]);
    addTearDown(harness.close);

    final first = await harness.repository.enqueueStandaloneQrPay(
      orderUuid: orderUuid,
      frozenAmountBaisas: 4750,
      method: 'cash',
      newUuid: () => firstEventUuid,
    );
    final replay = await harness.repository.enqueueStandaloneQrPay(
      orderUuid: orderUuid,
      frozenAmountBaisas: 999999,
      method: 'cash',
      newUuid: () => secondEventUuid,
    );

    expect(first.state, StandaloneQrPayState.processed);
    expect(replay.state, StandaloneQrPayState.processed);
    expect(replay.clientEventId, firstEventUuid);
    expect(harness.adapter.requests, hasLength(1));
    final stored = await harness.db.getOutbox('$orderUuid:pay');
    final event = (jsonDecode(stored!.eventsJson) as List).single as Map;
    final payment =
        (((event['payload'] as Map)['payments'] as List).single as Map);
    expect(payment['amount_baisas'], 4750);

    await expectLater(
      harness.repository.retireStandaloneQrPay(orderUuid, reason: 'invalid'),
      throwsStateError,
    );
  });

  test(
    'a lost response reuses one durable UUID and blocks replacement',
    () async {
      final harness = _Harness([
        _SyncOutcome.networkFailure,
        _SyncOutcome.processed,
      ]);
      addTearDown(harness.close);

      final first = await harness.repository.enqueueStandaloneQrPay(
        orderUuid: orderUuid,
        frozenAmountBaisas: 4750,
        method: 'cash',
        newUuid: () => firstEventUuid,
      );
      final second = await harness.repository.enqueueStandaloneQrPay(
        orderUuid: orderUuid,
        frozenAmountBaisas: 9000,
        method: 'cash',
        newUuid: () => secondEventUuid,
      );

      expect(first.state, StandaloneQrPayState.pending);
      expect(second.state, StandaloneQrPayState.pending);
      expect(second.clientEventId, firstEventUuid);
      expect(harness.adapter.requests, hasLength(1));
      expect(
        await harness.repository.hasUnresolvedStandaloneQrPay(orderUuid),
        isTrue,
      );

      expect(await harness.repository.flush(), 1);
      expect(harness.adapter.requests, hasLength(2));
      expect(
        harness.adapter.requests.map(
          (events) => events.single['client_event_id'],
        ),
        everyElement(firstEventUuid),
      );
    },
  );

  test(
    'refusal parks once; accepted release retirement permits fresh attempt',
    () async {
      final harness = _Harness([_SyncOutcome.refused, _SyncOutcome.processed]);
      addTearDown(harness.close);

      final refused = await harness.repository.enqueueStandaloneQrPay(
        orderUuid: orderUuid,
        frozenAmountBaisas: 4750,
        method: 'cash',
        newUuid: () => firstEventUuid,
      );
      expect(refused.state, StandaloneQrPayState.refused);
      expect(
        await harness.repository.hasUnresolvedStandaloneQrPay(orderUuid),
        isTrue,
      );

      expect(await harness.repository.flush(), 0);
      expect(harness.adapter.requests, hasLength(1));
      expect(
        await harness.repository.retryStuck(),
        0,
        reason: 'Generic stuck-sale retry must never relaunch a QR payment.',
      );
      expect(harness.adapter.requests, hasLength(1));

      // This call represents the coordinator's path after the server accepted a
      // cancelled/uncertain release for the refused physical tender.
      await harness.repository.retireStandaloneQrPay(
        orderUuid,
        reason: 'accepted cancelled release',
      );
      expect(
        await harness.repository.hasUnresolvedStandaloneQrPay(orderUuid),
        isFalse,
      );

      final replacement = await harness.repository.enqueueStandaloneQrPay(
        orderUuid: orderUuid,
        frozenAmountBaisas: 4750,
        method: 'cash',
        newUuid: () => secondEventUuid,
      );
      expect(replacement.state, StandaloneQrPayState.processed);
      expect(replacement.clientEventId, secondEventUuid);
      expect(harness.adapter.requests, hasLength(2));
    },
  );

  test(
    'processed but non-paid, missing, or mismatched ACK is never success',
    () async {
      for (final outcome in const [
        _SyncOutcome.processedNonPaid,
        _SyncOutcome.processedMissingResult,
        _SyncOutcome.processedMismatchedId,
      ]) {
        final harness = _Harness([outcome]);
        try {
          final result = await harness.repository.enqueueStandaloneQrPay(
            orderUuid: orderUuid,
            frozenAmountBaisas: 4750,
            method: 'cash',
            newUuid: () => firstEventUuid,
          );

          expect(
            result.state,
            StandaloneQrPayState.refused,
            reason: '$outcome',
          );
          expect(
            await harness.repository.hasUnresolvedStandaloneQrPay(orderUuid),
            isTrue,
          );
          expect(await harness.repository.flush(), 0);
          expect(harness.adapter.requests, hasLength(1));
        } finally {
          await harness.close();
        }
      }
    },
  );
}

class _Harness {
  _Harness(List<_SyncOutcome> outcomes)
    : db = AppDatabase.forTesting(NativeDatabase.memory()),
      adapter = _SyncAdapter(outcomes) {
    dio = Dio(BaseOptions(baseUrl: 'https://pos.test'))
      ..httpClientAdapter = adapter;
    repository = OrderSyncRepository(
      PosApiService(tokenGetter: () => 'device-token', dio: dio),
      db,
    );
  }

  final AppDatabase db;
  final _SyncAdapter adapter;
  late final Dio dio;
  late final OrderSyncRepository repository;

  Future<void> close() async {
    dio.close(force: true);
    await db.close();
  }
}

enum _SyncOutcome {
  processed,
  processedNonPaid,
  processedMissingResult,
  processedMismatchedId,
  refused,
  networkFailure,
}

class _SyncAdapter implements HttpClientAdapter {
  _SyncAdapter(List<_SyncOutcome> outcomes) : _outcomes = List.of(outcomes);

  final List<_SyncOutcome> _outcomes;
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
        .map((event) => event.cast<String, dynamic>())
        .toList(growable: false);
    requests.add(events);

    final outcome = _outcomes.isEmpty
        ? _SyncOutcome.processed
        : _outcomes.removeAt(0);
    if (outcome == _SyncOutcome.networkFailure) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'response lost',
      );
    }

    return ResponseBody.fromString(
      jsonEncode({
        'data': {
          'results': [
            for (final event in events)
              {
                'client_event_id': outcome == _SyncOutcome.processedMismatchedId
                    ? '99999999-9999-4999-8999-999999999999'
                    : event['client_event_id'],
                'status': outcome != _SyncOutcome.refused
                    ? 'processed'
                    : 'failed',
                'duplicate': false,
                if (outcome != _SyncOutcome.processedMissingResult)
                  'result': switch (outcome) {
                    _SyncOutcome.processed => {'status': 'paid'},
                    _SyncOutcome.processedNonPaid => {'status': 'held'},
                    _SyncOutcome.processedMismatchedId => {'status': 'paid'},
                    _ => {'error': 'settlement refused'},
                  },
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
