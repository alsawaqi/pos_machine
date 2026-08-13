// W-M3 / EXIT-04 — A processed ACK carrying a loyalty clamp/shortfall marker
// is a SUCCESS on the device, never a rejection.
//
// Contract (PHASE_0_EXIT_COVERAGE_MATRIX.md Part B, EXIT-04): when a queued
// order.pay redeems more loyalty than the customer's locked balance, pos_api
// clamps the debit, settles every sale effect, and answers `processed` with a
// result payload carrying the shortfall review marker (verified read-only
// against pos_api DeviceSyncLoyaltyTest: result.status='paid',
// loyalty_redeem_transaction_id, loyalty_redeem_adjustment_id and a
// loyalty_redeem_warning containing
// "[LOYALTY_REDEMPTION_SHORTFALL][REVIEW_REQUIRED]").
//
// The machine repository must treat that ACK as drained-once success: the
// batch settles (serverRejections stays 0, never parks) and a replayed flush
// re-sends nothing. Grounding (read-only): order_sync_repository.dart
// _flushOnce marks a row synced when every per-event status is 'processed';
// per-event result payloads never feed the rejection counter.

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
    'a processed-with-clamp ACK drains the batch once, never parks it, and a '
    'replay flush re-sends nothing',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final adapter = _ClampAckAdapter();
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
        orderUuid: 'order-clamp-001',
        eventsJson: jsonEncode([
          {
            'client_event_id': 'create-order-clamp-001',
            'event_type': 'order.create',
            'client_timestamp': '2026-08-13T10:00:00.000Z',
            'payload': {
              'order': {
                'uuid': 'order-clamp-001',
                'total_baisas': 3000,
                'customer_id': 42,
                'lines': [
                  {'product_id': 11, 'qty': 1, 'unit_price_baisas': 3000},
                ],
              },
            },
          },
          {
            'client_event_id': 'pay-order-clamp-001',
            'event_type': 'order.pay',
            'client_timestamp': '2026-08-13T10:00:01.000Z',
            'payload': {
              'order_uuid': 'order-clamp-001',
              'method': 'cash',
              'amount_baisas': 3000,
              // Requests more points than the locked balance holds — the
              // server clamps (applied=30, shortfall=70) but still processes.
              'loyalty_redeem': {'rule_id': 2, 'points': 100},
            },
          },
        ]),
        orderNumber: const Value(1003),
        createdAt: DateTime.utc(2026, 8, 13, 10),
      ));

      // One flush drains the batch — the clamp outcome is a success.
      expect(await repository.flush(), 1);
      expect(adapter.requestCount, 1);

      final rows = await db.select(db.orderOutbox).get();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.syncedAt, isNotNull,
          reason: 'a processed-with-clamp ACK must settle the batch');
      expect(row.serverRejections, 0,
          reason: 'a clamp marker is a review flag, never a rejection');
      expect(row.lastError, isNull,
          reason: 'no server error may be recorded for a clamp success');
      expect(OrderSyncRepository.isStuck(row), isFalse);
      expect(await repository.stuckBatches(), isEmpty,
          reason: 'the batch must never reach the parked/stuck surface');

      // Replaying the queue re-sends nothing — the redeem cannot re-debit.
      expect(await repository.flush(), 0);
      expect(adapter.requestCount, 1,
          reason: 'a settled clamp batch must not be pushed again');
    },
  );
}

/// Answers `processed` with the pos_api order.pay clamp result shape: the sale
/// settled in full, the redeem was clamped, and the shortfall review marker
/// rides along in the result payload.
class _ClampAckAdapter implements HttpClientAdapter {
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
              {
                'client_event_id': event['client_event_id'],
                'status': 'processed',
                'duplicate': false,
                'result': event['event_type'] == 'order.pay'
                    ? {
                        'status': 'paid',
                        'payment_ids': [9101],
                        'movements': 1,
                        'sale_commission_ids': [301, 302],
                        'loyalty_transaction_ids': [501],
                        'loyalty_redeem_transaction_id': 502,
                        'loyalty_redeem_adjustment_id': 503,
                        'loyalty_redeem_warning':
                            '[LOYALTY_REDEMPTION_SHORTFALL][REVIEW_REQUIRED] '
                                'requested points=100 stamps=0; applied '
                                'points=30 stamps=0; shortfall points=70 '
                                'stamps=0',
                      }
                    : {'status': 'created'},
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
