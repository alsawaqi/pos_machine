import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:sentry_flutter/sentry_flutter.dart' show SentryLevel;

import '../core/sentry.dart';
import '../models/pos_models.dart';
import '../services/order_sync_payload.dart';
import '../services/pos_api_service.dart';
import 'db/app_database.dart';

/// Offline-first order sync: a completed order is persisted to a durable Drift
/// outbox the moment it finishes, then pushed to pos_api (/device/sync/push)
/// and re-pushed until the server ACKs it. Idempotent on client_event_id, so a
/// replay after a 4-hour outage settles exactly once (no double sale / charge).
class OrderSyncRepository {
  OrderSyncRepository(this._api, this._db);

  final PosApiService _api;
  final AppDatabase _db;

  /// Build the push events for [snapshot], persist them to the outbox, then try
  /// to flush immediately. The DB write happens BEFORE any network I/O, so the
  /// order is durably queued even if the device is offline.
  Future<void> enqueue(
    OrderSnapshot snapshot, {
    double? lat,
    double? lng,
    int? staffId,
    int? tableId,
    List<int> joinedTableIds = const <int>[],
    int? customerId,
    String? plateNumber,
    String? deliveryProviderName,
    CardCharge? cardCharge,
    List<int> loyaltyRuleIds = const <int>[],
  }) async {
    final payload = buildOrderSyncPayload(
      snapshot,
      lat: lat,
      lng: lng,
      staffId: staffId,
      tableId: tableId,
      joinedTableIds: joinedTableIds,
      customerId: customerId,
      plateNumber: plateNumber,
      deliveryProviderName: deliveryProviderName,
      cardCharge: cardCharge,
      loyaltyRuleIds: loyaltyRuleIds,
    );

    // A snapshot with no pushable lines (e.g. only non-catalog demo products)
    // has nothing to persist server-side — skip it rather than queue a payload
    // the server will reject for an empty `lines`.
    final createPayload =
        payload.events.first['payload'] as Map<String, dynamic>;
    final order = createPayload['order'] as Map<String, dynamic>;
    if ((order['lines'] as List).isEmpty) {
      return;
    }

    await _db.enqueueOutbox(OrderOutboxCompanion(
      orderUuid: Value(payload.orderUuid),
      eventsJson: Value(jsonEncode(payload.events)),
      orderNumber: Value(snapshot.orderNumber),
      createdAt: Value(DateTime.now()),
    ));
    sentryBreadcrumb('sync', 'order enqueued', data: {
      'order': payload.orderUuid,
      'events': payload.events.length,
    });

    await flush();
  }

  /// Enqueue an `order.void` for an already-pushed order (a full cancellation),
  /// then flush. Persisted to its OWN durable outbox row keyed `[uuid]:void` so
  /// it never collides with the original order row (which may already be synced)
  /// and rides the same offline-first retry path. Created AFTER the order row,
  /// so the oldest-first flush pushes create/pay before the void. No-op without
  /// a server uuid (an order never pushed has nothing to void).
  Future<void> enqueueVoid(
    String orderUuid, {
    int? orderNumber,
    String? reason,
    int? voidReasonId,
    int? staffId,
    String? authorizedBy,
  }) async {
    if (orderUuid.isEmpty) return;

    final event = buildOrderVoidEvent(
      orderUuid: orderUuid,
      reason: reason,
      voidReasonId: voidReasonId,
      staffId: staffId,
      authorizedBy: authorizedBy,
    );

    await _db.enqueueOutbox(OrderOutboxCompanion(
      orderUuid: Value('$orderUuid:void'),
      eventsJson: Value(jsonEncode([event])),
      orderNumber: Value(orderNumber ?? 0),
      createdAt: Value(DateTime.now()),
    ));

    await flush();
  }

  /// Phase C2 — mirror a held (parked) order server-side (blueprint §6.7).
  /// Persisted to its OWN durable outbox row keyed `[uuid]:hold` so it never
  /// collides with the eventual completion row (plain `[uuid]`), and so a
  /// RE-hold of the same order replaces the row in place (PK upsert). The
  /// replace explicitly resets syncedAt/attempts/lastError — a re-hold after
  /// the first mirror synced must push again (the server upserts by uuid).
  /// No-op for a cart with no pushable lines (demo-only) or a draft without a
  /// server uuid.
  Future<void> enqueueHold(
    OrderSessionDraft draft, {
    int? staffId,
    int? tableId,
    List<int> joinedTableIds = const <int>[],
  }) async {
    final event = buildOrderHoldEvent(
      draft,
      orderUuid: draft.serverOrderUuid,
      staffId: staffId,
      tableId: tableId,
      joinedTableIds: joinedTableIds,
    );
    if (event == null) return;

    await _db.enqueueOutbox(OrderOutboxCompanion(
      orderUuid: Value('${draft.serverOrderUuid}:hold'),
      eventsJson: Value(jsonEncode([event])),
      orderNumber: Value(draft.orderNumber ?? 0),
      createdAt: Value(DateTime.now()),
      attempts: const Value(0),
      lastError: const Value(null),
      syncedAt: const Value(null),
    ));

    await flush();
  }

  /// Push every pending order. Best-effort and safe to call repeatedly: a
  /// network failure leaves the row queued for the next attempt; a server-side
  /// rejection of an event is recorded (lastError) for visibility. Returns the
  /// number of orders confirmed synced this run.
  Future<int> flush() async {
    final pending = await _db.pendingOutbox();
    var synced = 0;

    for (final row in pending) {
      final List<Map<String, dynamic>> events;
      try {
        events = (jsonDecode(row.eventsJson) as List)
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      } catch (e) {
        await _db.markOutboxAttempt(row.orderUuid, row.attempts + 1, 'corrupt outbox payload: $e');
        continue;
      }

      try {
        final data = await _api.pushSync(events);
        final results = (data['results'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();

        // Every event must have settled `processed` (a duplicate re-push echoes
        // the original processed state, which is also success).
        final allProcessed = results.isNotEmpty &&
            results.every((r) => r['status'] == 'processed');

        if (allProcessed) {
          await _db.markOutboxSynced(row.orderUuid, DateTime.now());
          synced++;
        } else {
          final error = _firstError(results);
          await _db.markOutboxAttempt(row.orderUuid, row.attempts + 1, error);
          // Phase C5 — a server-side REJECTION is otherwise invisible (it
          // only lands in a Drift column). Capture the FIRST failure per row
          // only, so a retrying fleet can't flood the quota.
          if (row.attempts == 0) {
            sentryCaptureMessage(
              'sync push rejected (${row.orderUuid}): $error',
              level: SentryLevel.warning,
            );
          } else {
            sentryBreadcrumb(
              'sync',
              'push retry rejected',
              data: {'order': row.orderUuid, 'attempts': row.attempts + 1},
              level: SentryLevel.warning,
            );
          }
        }
      } catch (e) {
        // Network / transport failure — no ACK at all. The same batch (same
        // client_event_ids) re-pushes cleanly next time.
        await _db.markOutboxAttempt(row.orderUuid, row.attempts + 1, e.toString());
      }
    }

    return synced;
  }

  /// Phase 3C — best-effort online push of a single advertising-display
  /// telemetry event (→ pos_marketing_impressions). Deliberately NOT durably
  /// queued: a dropped play on a flaky link is acceptable for analytics, and the
  /// high volume would otherwise bloat the order outbox. Idempotent server-side
  /// on the event's client_event_id.
  Future<void> pushSliderDisplay(Map<String, dynamic> event) async {
    try {
      await _api.pushSync([event]);
    } catch (_) {
      // best-effort telemetry — drop on any network/transport failure.
    }
  }

  Stream<List<OrderOutboxRow>> watchPending() => _db.watchPendingOutbox();

  String _firstError(List<Map<String, dynamic>> results) {
    for (final r in results) {
      if (r['status'] == 'failed') {
        final result = r['result'];
        if (result is Map && result['error'] != null) {
          return result['error'].toString();
        }
        return 'server rejected the event';
      }
    }
    final statuses = results.map((r) => r['status']).join(', ');
    return 'not settled (statuses: $statuses)';
  }
}
