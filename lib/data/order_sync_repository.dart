import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show SentryLevel;

import '../core/sentry.dart';
import '../models/pos_models.dart';
import '../services/order_sync_payload.dart';
import '../services/pos_api_service.dart';
import 'db/app_database.dart';

enum OrderSyncAttentionReason { serverRejected, awaitingGps }

enum StandaloneQrPayState { processed, refused, pending }

typedef OutboxAckListener =
    FutureOr<void> Function(
      OrderOutboxRow row,
      List<Map<String, dynamic>> events,
      List<Map<String, dynamic>> results,
    );

class StandaloneQrPayResult {
  const StandaloneQrPayResult({
    required this.state,
    required this.outboxKey,
    required this.clientEventId,
    this.error,
  });

  final StandaloneQrPayState state;
  final String outboxKey;
  final String clientEventId;
  final String? error;
}

class OrderSyncAttention {
  const OrderSyncAttention({required this.row, required this.reason});

  final OrderOutboxRow row;
  final OrderSyncAttentionReason reason;
}

/// Offline-first order sync: a completed order is persisted to a durable Drift
/// outbox the moment it finishes, then pushed to pos_api (/device/sync/push)
/// and re-pushed until the server ACKs it. Idempotent on client_event_id, so a
/// replay after a 4-hour outage settles exactly once (no double sale / charge).
class OrderSyncRepository {
  OrderSyncRepository(this._api, this._db, {this.mutationGuard});

  /// Only explicit, deterministic server refusals count toward parking.
  /// Offline / transport failures remain retry-forever.
  static const int maxServerRejections = 5;
  static const String _retiredQrPayMarker = 'qr-attempt-retired:';

  final PosApiService _api;
  final AppDatabase _db;

  /// Rechecked inside the serialized queue before any outbox mutation or push.
  /// Reads stay available while a durable draft recovery blocks new work.
  final Future<void> Function()? mutationGuard;
  Future<void> _flushTail = Future<void>.value();
  final Object _ackMutationScopeKey = Object();
  final List<OutboxAckListener> _ackListeners = [];
  final _flushCompletions = StreamController<bool>.broadcast();

  Stream<bool> get flushCompletions => _flushCompletions.stream;

  void addAckListener(OutboxAckListener listener) =>
      _ackListeners.add(listener);
  void removeAckListener(OutboxAckListener listener) =>
      _ackListeners.remove(listener);

  Future<void> dispose() => _flushCompletions.close();

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final run = _flushTail.then((_) => operation());
    _flushTail = run.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return run;
  }

  Future<T> _prepare<T>(Future<T> Function() operation) => _serialize(() async {
    await mutationGuard?.call();
    return operation();
  });

  /// A generic durable single-event row. An existing key is immutable: retries
  /// retain the first event ID/payload, including rows already acknowledged.
  Future<void> enqueueEvent(
    String key,
    Map<String, dynamic> event, {
    DateTime? createdAt,
    Future<Map<String, dynamic>> Function()? beforeFlush,
    Map<String, Map<String, dynamic>> followingEvents = const {},
  }) async {
    // Serialize preparation with pushes: a local kitchen print and its
    // evidence must finish before any pass can see this newly durable row.
    await _prepare(() async {
      if (await _db.getOutbox(key) != null) return;
      await _db.transaction(() async {
        final at = createdAt ?? DateTime.now();
        for (final entry in {key: event, ...followingEvents}.entries) {
          if (await _db.getOutbox(entry.key) != null) continue;
          await _db.enqueueOutbox(
            OrderOutboxCompanion(
              orderUuid: Value(entry.key),
              eventsJson: Value(jsonEncode([entry.value])),
              orderNumber: const Value(0),
              createdAt: Value(at),
            ),
          );
        }
      });
      if (beforeFlush != null) {
        final prepared = await beforeFlush();
        if (prepared['client_event_id'] != event['client_event_id'] ||
            prepared['event_type'] != event['event_type']) {
          throw StateError('Event preparation cannot change its identity.');
        }
        await (_db.update(_db.orderOutbox)..where(
              (table) => table.orderUuid.equals(key) & table.syncedAt.isNull(),
            ))
            .write(
              OrderOutboxCompanion(eventsJson: Value(jsonEncode([prepared]))),
            );
      }
    });
    await flush();
  }

  Future<List<OrderOutboxRow>> pendingRows() => _db.pendingOutbox();

  /// Read-only combine admission: includes parked/GPS-blocked rows and waits
  /// for existing preparation/ACK callbacks. Never flushes or deletes a row.
  Future<void> assertIdleForCombine() async {
    await _flushTail;
    if ((await pendingRows()).any((row) => !isParkedWaste(row))) {
      throw StateError(
        'Sync all pending orders and payments before combining.',
      );
    }
  }

  /// Reserve the preparation/flush queue while creating a recovery journal.
  /// Existing preparations and ACK listeners finish first; every pending row,
  /// including parked/GPS-blocked work, refuses admission without changing it.
  /// The callback must only do short local admission work: no network or calls
  /// back into this repository's queued mutation methods. It must durably set
  /// the state checked by [mutationGuard] before returning.
  Future<void> admitDraftRecovery(Future<void> Function() operation) =>
      _serialize(() async {
        if ((await pendingRows()).any((row) => !isParkedWaste(row))) {
          throw StateError(
            'Sync all pending orders and payments before recovering a draft.',
          );
        }
        await operation();
      });

  Future<OrderOutboxRow?> rowForKey(String key) => _db.getOutbox(key);

  /// A historical local UUID remains the durable row key after rebinding.
  /// Resolve a later manager void without editing the saved receipt or a
  /// synced row. This never follows the independent QR :pay namespace.
  Future<String> resolveTableBillUuid(String localUuid) async {
    final row = await _db.getOutbox(localUuid);
    if (row == null) return localUuid;
    final events = (jsonDecode(row.eventsJson) as List).whereType<Map>();
    if (events.length != 1 || events.single['event_type'] != 'order.pay') {
      return localUuid;
    }
    return (events.single['payload'] as Map)['order_uuid']?.toString() ??
        localUuid;
  }

  /// Derive monotonic move/join suffixes from retained durable rows, including
  /// synced ones, so a process restart cannot reuse an earlier operation key.
  Future<int> nextTableOperationNumber(String seatingKey, String kind) async {
    final prefix = 'tbl:$seatingKey:$kind:';
    final rows = await (_db.select(_db.orderOutbox)).get();
    var largest = 0;
    for (final row in rows) {
      if (!row.orderUuid.startsWith(prefix)) continue;
      final number = int.tryParse(row.orderUuid.substring(prefix.length)) ?? 0;
      if (number > largest) largest = number;
    }
    return largest + 1;
  }

  /// Only the named seating's pending pay/void wire UUIDs change. Keep each
  /// internal row key and event ID stable, avoiding collisions when two local
  /// tenders are rebound to one server bill. Synced rows are never rewritten.
  Future<void> rewritePendingOrderUuid(
    String seatingKey,
    String oldUuid,
    String newUuid,
  ) {
    // A table ACK can rebind a later payment during its current flush. Only
    // that awaited listener scope may reuse the queue slot; other callers
    // serialize normally, even while a listener is suspended.
    final scope = Zone.current[_ackMutationScopeKey];
    if (scope is _OutboxAckMutationScope && scope.active) {
      return _rewritePendingOrderUuid(seatingKey, oldUuid, newUuid);
    }
    return _prepare(
      () => _rewritePendingOrderUuid(seatingKey, oldUuid, newUuid),
    );
  }

  Future<void> _rewritePendingOrderUuid(
    String seatingKey,
    String oldUuid,
    String newUuid,
  ) async {
    if (seatingKey.isEmpty ||
        oldUuid.isEmpty ||
        oldUuid == newUuid ||
        newUuid.isEmpty) {
      return;
    }
    await _db.transaction(() async {
      final rows = await _db.pendingOutbox();
      for (final row in rows) {
        if (row.orderUuid.endsWith(':pay')) continue;
        final events = (jsonDecode(row.eventsJson) as List)
            .whereType<Map>()
            .map((event) => event.cast<String, dynamic>())
            .toList();
        if (events.length != 1) {
          continue; // Never rewrite legacy create batches.
        }
        var changed = false;
        for (final event in events) {
          if (event['event_type'] != 'order.pay' &&
              event['event_type'] != 'order.void') {
            continue;
          }
          final payload = event['payload'];
          if (payload is Map && payload['order_uuid'] == oldUuid) {
            payload['order_uuid'] = newUuid;
            changed = true;
          }
        }
        if (changed) {
          await (_db.update(_db.orderOutbox)..where(
                (table) =>
                    table.orderUuid.equals(row.orderUuid) &
                    table.syncedAt.isNull(),
              ))
              .write(
                OrderOutboxCompanion(eventsJson: Value(jsonEncode(events))),
              );
        }
      }
    });
  }

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
    final enqueued = await _prepare(() async {
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
        return false;
      }

      await _db.enqueueOutbox(
        OrderOutboxCompanion(
          orderUuid: Value(payload.orderUuid),
          eventsJson: Value(jsonEncode(payload.events)),
          orderNumber: Value(snapshot.orderNumber),
          createdAt: Value(DateTime.now()),
        ),
      );
      sentryBreadcrumb(
        'sync',
        'order enqueued',
        data: {'order': payload.orderUuid, 'events': payload.events.length},
      );
      return true;
    });
    if (enqueued) await flush();
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
    final enqueued = await _prepare(() async {
      if (orderUuid.isEmpty) return false;

      final event = buildOrderVoidEvent(
        orderUuid: orderUuid,
        reason: reason,
        voidReasonId: voidReasonId,
        staffId: staffId,
        authorizedBy: authorizedBy,
      );

      await _db.enqueueOutbox(
        OrderOutboxCompanion(
          orderUuid: Value('$orderUuid:void'),
          eventsJson: Value(jsonEncode([event])),
          orderNumber: Value(orderNumber ?? 0),
          createdAt: Value(DateTime.now()),
        ),
      );
      return true;
    });
    if (enqueued) await flush();
  }

  /// QR-002 S2 — queue exactly one standalone `order.pay` for a server-owned
  /// QR order. `[orderUuid]:pay` is an internal row key only; the wire event id
  /// is a freshly-minted UUID persisted inside [eventsJson] and replayed
  /// unchanged after response loss.
  Future<StandaloneQrPayResult> enqueueStandaloneQrPay({
    required String orderUuid,
    required int frozenAmountBaisas,
    required String method,
    CardCharge? cardCharge,
    double? lat,
    double? lng,
    DateTime? paidAt,
    String Function()? newUuid,
  }) async {
    final key = '$orderUuid:pay';
    final existingResult = await _prepare<StandaloneQrPayResult?>(() async {
      final existing = await _db.getOutbox(key);
      if (existing != null) {
        final explicitlyRetired =
            existing.syncedAt != null &&
            (existing.lastError ?? '').startsWith(_retiredQrPayMarker);
        if (!explicitlyRetired) return _standaloneQrResult(existing);
      }

      final event = buildStandaloneQrPayEvent(
        orderUuid: orderUuid,
        frozenAmountBaisas: frozenAmountBaisas,
        method: method,
        cardCharge: cardCharge,
        lat: lat,
        lng: lng,
        paidAt: paidAt,
        newUuid: newUuid,
      );
      await _db.enqueueOutbox(
        OrderOutboxCompanion(
          orderUuid: Value(key),
          eventsJson: Value(jsonEncode(<Map<String, dynamic>>[event])),
          orderNumber: const Value(0),
          createdAt: Value(paidAt ?? DateTime.now()),
          attempts: const Value(0),
          serverRejections: const Value(0),
          lastError: const Value(null),
          syncedAt: const Value(null),
        ),
      );
      return null;
    });
    if (existingResult != null) return existingResult;

    await flush();
    final row = await _db.getOutbox(key);
    if (row == null) {
      throw StateError('The QR payment outbox row disappeared.');
    }
    return _standaloneQrResult(row);
  }

  /// A pending QR pay row means a charge/pay attempt has an unresolved fate.
  /// The settle sheet must never open a second tender while it exists.
  Future<bool> hasUnresolvedStandaloneQrPay(String orderUuid) async {
    final row = await _db.getOutbox('$orderUuid:pay');
    return row != null && row.syncedAt == null;
  }

  /// Stop automatic replay only after staff has resolved the physical tender
  /// and the server has accepted an explicit cancelled/uncertain release.
  Future<void> retireStandaloneQrPay(
    String orderUuid, {
    required String reason,
  }) => _prepare(() async {
    final key = '$orderUuid:pay';
    final row = await _db.getOutbox(key);
    if (row == null || row.syncedAt != null || row.serverRejections == 0) {
      throw StateError(
        'Only an affirmatively refused QR payment can be retired.',
      );
    }
    await _db.retireOutbox(key, '$_retiredQrPayMarker$reason', DateTime.now());
  });

  StandaloneQrPayResult _standaloneQrResult(OrderOutboxRow row) {
    final decoded = jsonDecode(row.eventsJson) as List;
    final event = (decoded.single as Map).cast<String, dynamic>();
    final state = row.syncedAt != null
        ? StandaloneQrPayState.processed
        : row.serverRejections > 0
        ? StandaloneQrPayState.refused
        : StandaloneQrPayState.pending;
    return StandaloneQrPayResult(
      state: state,
      outboxKey: row.orderUuid,
      clientEventId: event['client_event_id']?.toString() ?? '',
      error: row.lastError,
    );
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
    final enqueued = await _prepare(() async {
      final event = buildOrderHoldEvent(
        draft,
        orderUuid: draft.serverOrderUuid,
        staffId: staffId,
        tableId: tableId,
        joinedTableIds: joinedTableIds,
      );
      if (event == null) return false;

      await _db.enqueueOutbox(
        OrderOutboxCompanion(
          orderUuid: Value('${draft.serverOrderUuid}:hold'),
          eventsJson: Value(jsonEncode([event])),
          orderNumber: Value(draft.orderNumber ?? 0),
          createdAt: Value(DateTime.now()),
          attempts: const Value(0),
          serverRejections: const Value(0),
          lastError: const Value(null),
          syncedAt: const Value(null),
        ),
      );
      return true;
    });
    if (enqueued) await flush();
  }

  /// Push every pending order. Best-effort and safe to call repeatedly: a
  /// network failure leaves the row queued for the next attempt; a server-side
  /// rejection of an event is recorded (lastError) for visibility. Returns the
  /// number of orders confirmed synced this run.
  Future<int> flush() {
    // Multiple triggers can overlap (startup, reconnect, and a newly-enqueued
    // sale). Queue each pass so rejection counters cannot race or page twice.
    // A pass requested mid-flush still runs afterwards and sees any new rows.
    return _prepare(_flushOnce);
  }

  /// Re-open only the SAME durable table pay for ACK recovery. No new event,
  /// tender or payload. This also heals the historical synced/pending split.
  Future<int> recoverTablePayment(String orderUuid, String eventId) =>
      _prepare(() async {
        // The durable key may be the snapshot's original serverOrderUuid
        // while the event has since been rebound to the canonical bill.
        // Match BOTH immutable event id and canonical uuid; never :pay rows.
        final matching = (await _db.select(_db.orderOutbox).get()).where((row) {
          if (row.orderUuid.endsWith(':pay')) return false;
          try {
            final events = jsonDecode(row.eventsJson);
            return events is List &&
                events.length == 1 &&
                events.single is Map &&
                events.single['event_type'] == 'order.pay' &&
                events.single['client_event_id'] == eventId &&
                events.single['payload'] is Map &&
                events.single['payload']['order_uuid'] == orderUuid;
          } catch (_) {
            return false;
          }
        }).toList();
        if (matching.length != 1) {
          throw StateError('Saved table payment is unavailable');
        }
        final row = matching.single;
        final events = (jsonDecode(row.eventsJson) as List).cast<Map>();
        if (events.length != 1 ||
            events.single['event_type'] != 'order.pay' ||
            events.single['client_event_id'] != eventId ||
            (events.single['payload'] as Map)['order_uuid'] != orderUuid) {
          throw StateError('Saved table payment identity differs');
        }
        if (row.syncedAt != null || isStuck(row)) {
          // Replay this named payment once to obtain an authoritative result.
          // Keep the saved payload/id; do not unpark unrelated sales.
          await (_db.update(_db.orderOutbox)..where(
                (t) =>
                    t.orderUuid.equals(row.orderUuid) &
                    t.eventsJson.equals(row.eventsJson),
              ))
              .write(
                const OrderOutboxCompanion(
                  syncedAt: Value(null),
                  serverRejections: Value(0),
                ),
              );
        }
        return _flushOnce(recoveringTableEventId: eventId);
      });

  Future<int> _flushOnce({String? recoveringTableEventId}) async {
    final pending = await _db.pendingOutbox();
    final branch = await _db.getBranch();
    final branchIsFenced =
        branch?.latitude != null && branch?.longitude != null;
    Future<({double lat, double lng})?>? freshFix;
    var synced = 0;
    var successful = true;

    for (final queuedRow in pending) {
      // A preceding table ACK may have rebound a later payment in this very
      // pass. Decode its current durable payload, not the captured snapshot.
      final row = await _db.getOutbox(queuedRow.orderUuid);
      if (row == null || row.syncedAt != null) continue;
      // Parked revenue is retained forever but no longer hammers a deterministic
      // refusal. Manual retry resets only the rejection counter.
      if (isStuck(row)) continue;

      final List<Map<String, dynamic>> events;
      try {
        events = (jsonDecode(row.eventsJson) as List)
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      } catch (e) {
        successful = false;
        await _db.markOutboxAttempt(
          row.orderUuid,
          row.attempts + 1,
          'corrupt outbox payload: $e',
        );
        continue;
      }

      if (row.orderUuid.startsWith('tbl:') &&
          DateTime.now().difference(row.createdAt).inSeconds > 300) {
        var changed = false;
        for (final event in events) {
          if (!(event['event_type']?.toString() ?? '').startsWith(
            'table.session.',
          )) {
            continue;
          }
          final payload = event['payload'];
          if (payload is Map && payload['queued_offline'] != true) {
            payload['queued_offline'] = true;
            changed = true;
          }
        }
        if (changed) {
          await (_db.update(_db.orderOutbox)..where(
                (table) =>
                    table.orderUuid.equals(row.orderUuid) &
                    table.syncedAt.isNull(),
              ))
              .write(
                OrderOutboxCompanion(eventsJson: Value(jsonEncode(events))),
              );
        }
      }

      // A fenced branch fails closed when create/pay reaches the server without
      // GPS. Re-enrich the decoded durable batch at flush time, retaining every
      // stable event id/timestamp. One fresh fix is shared by this flush pass.
      if (branchIsFenced) {
        final missingGps = _missingGpsContainers(events);
        if (missingGps.isNotEmpty) {
          freshFix ??= _acquireFreshFix();
          final fix = await freshFix;
          if (fix == null) {
            successful = false;
            // Keep the sale queued without manufacturing a deterministic server
            // rejection. Other eligible rows in this pass can still settle.
            continue;
          }
          for (final container in missingGps) {
            container['gps'] = {'lat': fix.lat, 'lng': fix.lng};
          }
        }
      }

      try {
        final data = await _api.pushSync(events);
        final results = (data['results'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();

        // Every event must have settled `processed` (a duplicate re-push echoes
        // the original processed state, which is also success).
        final allProcessed =
            results.isNotEmpty &&
            results.every((r) => r['status'] == 'processed');
        final qrPaymentConfirmed =
            !row.orderUuid.endsWith(':pay') ||
            _isMatchingPaidQrAck(events, results);

        if (allProcessed && qrPaymentConfirmed) {
          for (final listener in List<OutboxAckListener>.of(_ackListeners)) {
            final scope = _OutboxAckMutationScope();
            try {
              await runZoned(
                () async => listener(row, events, results),
                zoneValues: {_ackMutationScopeKey: scope},
              );
            } finally {
              scope.active = false;
            }
          }
          await _db.markOutboxSynced(row.orderUuid, DateTime.now());
          synced++;
        } else {
          successful = false;
          final error = _firstError(results);
          // A table payment refusal is durable checkout evidence too. Other
          // event types and missing/malformed ACKs keep their classification.
          final failedTablePayment =
              recoveringTableEventId != null &&
              recoveringTableEventId ==
                  events.singleOrNull?['client_event_id'] &&
              !row.orderUuid.endsWith(':pay') &&
              events.length == 1 &&
              events.single['event_type'] == 'order.pay' &&
              results.length == 1 &&
              results.single['status'] == 'failed' &&
              results.single['client_event_id'] ==
                  events.single['client_event_id'];
          await _recordServerRejection(
            row,
            error,
            parkPayment: failedTablePayment,
          );
          if (failedTablePayment) {
            for (final listener in List<OutboxAckListener>.of(_ackListeners)) {
              await listener(row, events, results);
            }
          }
        }
      } on ApiException catch (e) {
        successful = false;
        if (_isDeterministicServerRejection(e)) {
          await _recordServerRejection(row, e.message);
        } else {
          await _db.markOutboxAttempt(
            row.orderUuid,
            row.attempts + 1,
            e.toString(),
          );
        }
      } catch (e) {
        successful = false;
        // Network / transport failure — no ACK at all. The same batch (same
        // client_event_ids) re-pushes cleanly next time.
        await _db.markOutboxAttempt(
          row.orderUuid,
          row.attempts + 1,
          e.toString(),
        );
      }
    }

    if (!_flushCompletions.isClosed) _flushCompletions.add(successful);
    return synced;
  }

  Future<({double lat, double lng})?> _acquireFreshFix() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 5));
      return (lat: position.latitude, lng: position.longitude);
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _missingGpsContainers(
    List<Map<String, dynamic>> events,
  ) {
    final missing = <Map<String, dynamic>>[];
    for (final event in events) {
      final container = _gpsContainer(event);
      if (container == null) continue;

      final gps = container['gps'];
      final hasCompleteGps =
          gps is Map && gps['lat'] is num && gps['lng'] is num;
      if (!hasCompleteGps) missing.add(container);
    }
    return missing;
  }

  Map<String, dynamic>? _gpsContainer(Map<String, dynamic> event) {
    final rawPayload = event['payload'];
    if (rawPayload is! Map) return null;
    final payload = rawPayload.cast<String, dynamic>();

    switch (event['event_type']) {
      case 'order.create':
        final rawOrder = payload['order'];
        return rawOrder is Map ? rawOrder.cast<String, dynamic>() : null;
      case 'order.pay':
        return payload;
      default:
        return null;
    }
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

  Stream<List<OrderOutboxRow>> watchStuck() =>
      watchPending().map((rows) => rows.where(isStuck).toList(growable: false));

  /// Revenue that requires an operator's attention: either a deterministically
  /// rejected batch parked at the cap, or a fenced sale that cannot leave the
  /// durable outbox until this device obtains a complete GPS fix.
  Stream<List<OrderSyncAttention>> watchAttention() =>
      _db.watchPendingOutboxWithBranch().map((snapshot) {
        final branch = snapshot.branch;
        final branchIsFenced =
            branch?.latitude != null && branch?.longitude != null;

        return <OrderSyncAttention>[
          for (final row in snapshot.rows)
            if (isStuck(row))
              OrderSyncAttention(
                row: row,
                reason: OrderSyncAttentionReason.serverRejected,
              )
            else if (branchIsFenced && _hasMissingGps(row))
              OrderSyncAttention(
                row: row,
                reason: OrderSyncAttentionReason.awaitingGps,
              ),
        ];
      });

  Future<List<OrderOutboxRow>> stuckBatches() async =>
      (await _db.pendingOutbox()).where(isStuck).toList(growable: false);

  /// Retry every attention-worthy batch. Parked rows are first un-parked;
  /// GPS-held rows remain pending and [flush] retries them without changing
  /// their rejection counters when no valid fix is available.
  Future<int> retryAttention() async {
    await _prepare(() => _db.resetStuckOutbox(maxServerRejections));
    return flush();
  }

  /// Un-park every rejected batch and immediately make one serialized retry.
  /// Stable client_event_ids make this safe when the server processed a prior
  /// request but its response was lost.
  Future<int> retryStuck() async {
    return retryAttention();
  }

  static bool isStuck(OrderOutboxRow row) =>
      row.serverRejections >= maxServerRejections;

  /// Only a parked, waste-only batch is unrelated to bill ownership/payment.
  /// Mixed, corrupt or financial batches retain the existing blocking policy.
  static bool isParkedWaste(OrderOutboxRow row) {
    if (!isStuck(row)) return false;
    try {
      final events = jsonDecode(row.eventsJson);
      return events is List &&
          events.isNotEmpty &&
          events.every(
            (e) =>
                e is Map &&
                e['event_type'] == 'product.waste' &&
                e['payload'] is Map,
          );
    } catch (_) {
      return false;
    }
  }

  static bool isTableWork(OrderOutboxRow row) {
    if (!row.orderUuid.startsWith('tbl:')) return false;
    try {
      final events = jsonDecode(row.eventsJson);
      return events is! List ||
          events.isEmpty ||
          events.any((e) => e is! Map || e['event_type'] != 'product.waste');
    } catch (_) {
      return true;
    }
  }

  bool _hasMissingGps(OrderOutboxRow row) {
    try {
      final decoded = jsonDecode(row.eventsJson);
      if (decoded is! List) return false;
      final events = decoded
          .whereType<Map>()
          .map((event) => event.cast<String, dynamic>())
          .toList(growable: false);
      return _missingGpsContainers(events).isNotEmpty;
    } catch (_) {
      // Corrupt payloads follow the existing attempt/error path in flush();
      // they are not mislabeled as location holds.
      return false;
    }
  }

  Future<void> _recordServerRejection(
    OrderOutboxRow row,
    String error, {
    bool parkPayment = false,
  }) async {
    // A deterministic refusal after a QR tender must not be retried silently:
    // staff may already have returned cash or escalated a charged card. Park it
    // immediately. Transport/no-ACK failures still replay the same event UUID.
    final rejections = row.orderUuid.endsWith(':pay') || parkPayment
        ? maxServerRejections
        : row.serverRejections + 1;
    await _db.markOutboxServerRejection(
      row.orderUuid,
      row.attempts + 1,
      rejections,
      error,
    );

    sentryBreadcrumb(
      'sync',
      'push rejected',
      data: {'order': row.orderUuid, 'server_rejections': rejections},
      level: SentryLevel.warning,
    );

    if (rejections == maxServerRejections) {
      // Raw server text stays local: validation/SQL errors can include customer
      // data. The UUID and existing device/company/branch tags are enough for
      // support to locate the durable row with the operator.
      sentryCaptureMessage(
        'outbox batch parked after repeated server rejections '
        '(order ${row.orderUuid})',
        level: SentryLevel.error,
      );
    }
  }

  bool _isDeterministicServerRejection(ApiException error) {
    final status = error.statusCode;
    if (error.isNetwork || error.isUnauthorized || status == null) return false;
    // Timeouts and throttling are answered HTTP requests but are transient,
    // unlike validation/conflict/not-found responses that will not self-heal.
    return status >= 400 &&
        status < 500 &&
        status != 408 &&
        status != 425 &&
        status != 429;
  }

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

  bool _isMatchingPaidQrAck(
    List<Map<String, dynamic>> events,
    List<Map<String, dynamic>> results,
  ) {
    if (events.length != 1 || results.length != 1) return false;
    final eventId = events.single['client_event_id']?.toString();
    final ack = results.single;
    final rawResult = ack['result'];
    return eventId != null &&
        eventId.isNotEmpty &&
        ack['client_event_id']?.toString() == eventId &&
        ack['status'] == 'processed' &&
        rawResult is Map &&
        rawResult['status'] == 'paid';
  }
}

class _OutboxAckMutationScope {
  bool active = true;
}
