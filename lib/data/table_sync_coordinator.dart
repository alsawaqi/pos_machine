import 'dart:async';
import 'dart:convert';

import '../models/pos_models.dart';
import '../models/table_sync_models.dart';
import '../services/order_sync_payload.dart';
import '../state/pos_controller.dart';
import 'db/app_database.dart';
import 'order_sync_repository.dart';

class TablePaymentContext {
  const TablePaymentContext({this.lat, this.lng, this.cardCharge});
  final double? lat;
  final double? lng;
  final CardCharge? cardCharge;
}

class TableVoidApproval {
  const TableVoidApproval({
    required this.authorizedBy,
    this.reason,
    this.reasonId,
  });
  final String authorizedBy;
  final String? reason;
  final int? reasonId;
}

/// Only cashier hooks and this device's own ACKs write local table identity.
/// The board/feed are intentionally not dependencies of this coordinator.
class TableSyncCoordinator implements DiningTableSyncHooks {
  TableSyncCoordinator({
    required this.outbox,
    required this.store,
    required this.loadSessions,
    required this.mode,
    required this.degraded,
    required this.staffId,
    required this.markPrinted,
    this.bindBillIdentity,
    this.stockModeForProduct,
    this.guardSession,
    DateTime Function()? clock,
    String Function()? newUuid,
  }) : clock = clock ?? DateTime.now,
       newUuid = newUuid ?? uuidV4 {
    outbox.addAckListener(_applyAcks);
    _flushSubscription = outbox.flushCompletions.listen((_) {
      unawaited(_publishVerdicts());
    });
  }

  final OrderSyncRepository outbox;
  final TableLedgerStore store;
  final Future<List<DiningTableSession>> Function() loadSessions;
  final String Function() mode;
  final bool Function() degraded;
  final int? Function() staffId;
  final Future<void> Function(String roundId) markPrinted;
  void Function(DiningTableSession session, String oldUuid, String newUuid)?
  bindBillIdentity;
  // Current device catalogue, not the frozen cart snapshot or a server read.
  String? Function(int productId)? stockModeForProduct;
  final DateTime Function() clock;
  final String Function() newUuid;
  final Future<void> Function(DiningTableSession)? guardSession;

  Future<bool> Function(DiningTableSession, List<Map<String, dynamic>>)?
  printRound;
  Future<TablePaymentContext> Function(OrderSnapshot)? paymentContext;
  TableVoidApproval? clearApproval;

  final _sessions = <String, DiningTableSession>{};
  final _changes = StreamController<void>.broadcast();
  final _verdicts = StreamController<List<TableSyncVerdict>>.broadcast();
  late final StreamSubscription<bool> _flushSubscription;
  Future<void> _tail = Future<void>.value();
  Object? lastError;
  bool _disposed = false;

  bool get live => mode() == 'live';
  Stream<void> get changes => _changes.stream;
  Stream<List<TableSyncVerdict>> get verdicts => _verdicts.stream;
  Future<void> get settled => _tail;
  DiningTableSession? cachedSession(String tableId) => _sessions[tableId];

  /// Called after durable archive. Never evicts a newer occupied generation.
  void forgetRecoveredSession({
    required String tableId,
    required String uuid,
    String? occupiedAt,
    String? seatingKey,
  }) {
    final current = _sessions[tableId];
    if (current != null &&
        (current.serverOrderUuid == uuid ||
            current.draft?.serverOrderUuid == uuid ||
            (occupiedAt != null &&
                current.occupiedAt?.toIso8601String() == occupiedAt) ||
            (seatingKey != null && current.seatingKey == seatingKey))) {
      _sessions.remove(tableId);
      _changed();
    }
  }

  Future<void> hydrate() async {
    for (final session in await loadSessions()) {
      await guardSession?.call(session);
      _sessions.putIfAbsent(session.tableId, () => session);
    }
    // The outbox is durable first. Recover a ledger write interrupted between
    // the Drift commit and sqflite preparation without ever printing again.
    for (final row in await outbox.pendingRows()) {
      final events = (jsonDecode(row.eventsJson) as List).whereType<Map>();
      for (final event in events) {
        if (event['payload'] is! Map) continue;
        final payload = Map<String, dynamic>.from(event['payload'] as Map);
        final seat = payload['seating_key']?.toString();
        if (seat == null) continue;
        final request = payload['client_request_id']?.toString();
        if (request == null) continue;
        if (event['event_type'] == 'table.session.round') {
          final rounds = await store.readLocalTableRounds(seatingKey: seat);
          if (rounds.any((r) => r.clientRequestId == request)) continue;
          await store.saveLocalTableRound(
            LocalTableRound(
              clientRequestId: request,
              tableId: payload['table_id'].toString(),
              seatingKey: seat,
              localRoundNo:
                  rounds.fold<int>(
                    0,
                    (n, r) => r.localRoundNo > n ? r.localRoundNo : n,
                  ) +
                  1,
              lines: (payload['lines'] as List)
                  .map((line) => Map<String, dynamic>.from(line as Map))
                  .toList(),
              submittedAt: DateTime.parse(payload['submitted_at'] as String),
              printedAt: DateTime.tryParse(
                payload['printed_at']?.toString() ?? '',
              ),
              outboxKey: row.orderUuid,
              orderUuid: payload['order_uuid']?.toString(),
            ),
          );
        } else if (event['event_type'] == 'table.session.cancel_line') {
          final cancellations = await store.readLocalLineCancellations(
            seatingKey: seat,
          );
          if (cancellations.any((c) => c.clientRequestId == request)) continue;
          await store.saveLocalLineCancellation(
            LocalLineCancellation(
              clientRequestId: request,
              tableId: payload['table_id'].toString(),
              seatingKey: seat,
              productId: payload['product_id'] as int,
              addonIds: (payload['addon_ids'] as List? ?? []).cast<int>(),
              qty: payload['qty'] as int,
              prepared: payload['prepared'] == true,
              cancelledAt: DateTime.parse(payload['cancelled_at'] as String),
              outboxKey: row.orderUuid,
              notes: payload['notes'] as String?,
              reason: payload['reason'] as String?,
              authorizedBy: payload['authorized_by'] as String?,
            ),
          );
        }
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    outbox.removeAckListener(_applyAcks);
    await _flushSubscription.cancel();
    await _changes.close();
    await _verdicts.close();
  }

  void _changed() {
    if (!_disposed) _changes.add(null);
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final run = _tail.then((_) => operation());
    _tail = run.then<void>(
      (_) {
        lastError = null;
      },
      onError: (Object error, StackTrace stack) {
        lastError = error;
        _changed();
      },
    );
    return run;
  }

  void _hook(Future<void> Function() operation) {
    if (!live || _disposed) return;
    unawaited(_serial(operation).catchError((Object _) {}));
  }

  DiningTableSession _copyIdentity(
    DiningTableSession session,
    DiningTableSession? identity,
  ) {
    if (identity == null ||
        identity.orderReference != session.orderReference ||
        (identity.occupiedAt != null &&
            session.occupiedAt != null &&
            identity.occupiedAt != session.occupiedAt)) {
      return session;
    }
    return session.copyWith(
      seatingKey: identity.seatingKey,
      seatingUuid: identity.seatingUuid,
      seatingState: identity.seatingState,
      serverOrderUuid: identity.serverOrderUuid,
      tempReference: identity.tempReference,
      winnerSeatingUuid: identity.winnerSeatingUuid,
      lastVerdict: identity.lastVerdict,
      lastVerdictAt: identity.lastVerdictAt,
    );
  }

  Future<DiningTableSession> _remember(DiningTableSession session) async {
    await guardSession?.call(session);
    var remembered = _copyIdentity(session, _sessions[session.tableId]);
    for (final stored in await loadSessions()) {
      if (stored.tableId == session.tableId && stored.seatingKey != null) {
        remembered = _copyIdentity(remembered, stored);
      }
    }
    await guardSession?.call(remembered);
    _sessions[session.tableId] = remembered;
    return remembered;
  }

  Map<String, Object?> _identityFields(DiningTableSession s) => {
    'seating_key': s.seatingKey,
    'seating_uuid': s.seatingUuid,
    'seating_state': s.seatingState,
    'server_order_uuid': s.serverOrderUuid,
    'temp_reference': s.tempReference,
    'winner_seating_uuid': s.winnerSeatingUuid,
    'last_verdict': s.lastVerdict,
    'last_verdict_at': s.lastVerdictAt?.toUtc().toIso8601String(),
  };

  Future<void> _saveIdentity(DiningTableSession s) async {
    await guardSession?.call(s);
    _sessions[s.tableId] = s;
    // Never recreate a cleared row or overwrite a later occupancy's identity.
    final current = (await loadSessions())
        .where((row) => row.tableId == s.tableId)
        .firstOrNull;
    if (current != null &&
        current.orderReference == s.orderReference &&
        (current.occupiedAt == null ||
            s.occupiedAt == null ||
            current.occupiedAt == s.occupiedAt) &&
        (current.seatingKey == null || current.seatingKey == s.seatingKey)) {
      await store.updateTableSyncFields(s.tableId, _identityFields(s));
    }
    _changed();
  }

  Future<DiningTableSession> _ensure(DiningTableSession source) async {
    var session = await _remember(source);
    if (session.isLinkedSecondary) {
      final head = (await loadSessions())
          .where((s) => s.tableId == session.primaryTableId)
          .firstOrNull;
      if (head != null) return _ensure(head);
    }
    if (session.seatingKey == null || session.seatingKey!.isEmpty) {
      final existingBill =
          session.serverOrderUuid ?? session.draft?.serverOrderUuid ?? '';
      final proposed = existingBill.isEmpty ? newUuid() : existingBill;
      session = session.copyWith(
        seatingKey: newUuid(),
        seatingState: 'opening',
        serverOrderUuid: proposed,
      );
      await _saveIdentity(session);
      bindBillIdentity?.call(session, existingBill, proposed);
    }
    if (session.seatingState == 'opening' || session.seatingState == 'local') {
      final event = _event('open', session, {
        'opened_at': (session.occupiedAt ?? session.updatedAt)
            .toUtc()
            .toIso8601String(),
        'order_uuid': session.serverOrderUuid,
        'joined_table_ids': session.linkedTableIds.map(int.parse).toList(),
      }, eventId: session.seatingKey);
      await outbox.enqueueEvent(
        'tbl:${session.seatingKey}:open',
        event,
        createdAt: clock(),
      );
    }
    return _sessions[session.tableId] ?? session;
  }

  Map<String, dynamic> _event(
    String kind,
    DiningTableSession session,
    Map<String, dynamic> payload, {
    String? eventId,
    DateTime? at,
  }) => buildTableSessionEvent(
    kind,
    seatingKey: session.seatingKey!,
    tableId: session.tableId,
    queuedOffline: degraded(),
    staffId: staffId(),
    payload: payload,
    now: at ?? clock(),
    newUuid: eventId == null ? newUuid : () => eventId,
  );

  @override
  void onTableOccupied(DiningTableSession s) => _hook(() async {
    if (s.draft?.items.isNotEmpty != true) return;
    await _ensure(s);
  });

  @override
  void onTableDraftPersisted(DiningTableSession s) => _hook(() async {
    if (s.draft?.items.isNotEmpty != true) return;
    await _ensure(s);
  });

  @override
  void onTableLeft(String tableId) => _hook(() async {
    final source =
        (await loadSessions()).where((s) => s.tableId == tableId).firstOrNull ??
        _sessions[tableId];
    if (source != null) await _sendRound(source);
  });

  @override
  void onTableTransferred(String fromId, DiningTableSession moved) =>
      _hook(() async {
        final old = _sessions[fromId];
        final session = _copyIdentity(moved, old);
        _sessions.remove(fromId);
        await _saveIdentity(session);
        final bound = await _ensure(session);
        final n = await outbox.nextTableOperationNumber(
          bound.seatingKey!,
          'move',
        );
        await outbox.enqueueEvent(
          'tbl:${bound.seatingKey}:move:$n',
          _event('move', bound, {
            'from_table_id': int.parse(fromId),
            'to_table_id': int.parse(moved.tableId),
            'moved_at': clock().toUtc().toIso8601String(),
          }),
        );
      });

  @override
  void onTablesJoined(DiningTableSession head, DiningTableSession seat) =>
      _hook(() async {
        final bound = await _ensure(head);
        final n = await outbox.nextTableOperationNumber(
          bound.seatingKey!,
          'join',
        );
        await outbox.enqueueEvent(
          'tbl:${bound.seatingKey}:join:$n',
          _event('join', bound, {
            'join_table_ids': [int.parse(seat.tableId)],
            'joined_at': clock().toUtc().toIso8601String(),
          }),
        );
      });

  @override
  void onTablesCleared(Set<String> groupIds, DiningTableSession? head) {
    final approval = clearApproval;
    clearApproval = null;
    _hook(() async {
      final source =
          head ??
          groupIds
              .map((id) => _sessions[id])
              .whereType<DiningTableSession>()
              .firstOrNull;
      if (source == null) return;
      final session = await _remember(source);
      if (session.seatingKey == null) return;
      final rounds = await store.readLocalTableRounds(
        seatingKey: session.seatingKey,
      );
      final hasServerBill =
          rounds.any((r) => r.serverRoundId != null) ||
          session.winnerSeatingUuid != null;
      if (rounds.isNotEmpty && approval == null) {
        throw StateError('Sent table lines require manager approval to clear.');
      }
      if (hasServerBill && (session.serverOrderUuid ?? '').isNotEmpty) {
        await outbox.enqueueEvent(
          '${session.serverOrderUuid}:void',
          buildOrderVoidEvent(
            orderUuid: session.serverOrderUuid!,
            reason: approval?.reason,
            voidReasonId: approval?.reasonId,
            staffId: staffId(),
            authorizedBy: approval?.authorizedBy,
            voidedAt: clock(),
            newUuid: newUuid,
          ),
        );
      } else {
        await outbox.enqueueEvent(
          'tbl:${session.seatingKey}:close',
          _event('close', session, {
            'closed_at': clock().toUtc().toIso8601String(),
            'reason': 'staff_close',
          }),
        );
      }
    });
  }

  @override
  void onTablePaid(DiningTableSession paid, OrderSnapshot snapshot) {
    if (!live) return;
    final context =
        paymentContext?.call(snapshot) ??
        Future.value(const TablePaymentContext());
    _hook(() async {
      final session = await _remember(paid);
      if (session.seatingKey == null) {
        throw StateError('A Live table payment must have a seating.');
      }
      final payment = await context;
      final bill = session.serverOrderUuid ?? snapshot.serverOrderUuid;
      final event = buildOrderPayEvent(
        snapshot,
        orderUuid: bill,
        lat: payment.lat,
        lng: payment.lng,
        cardCharge: payment.cardCharge,
        now: clock(),
        newUuid: newUuid,
      );
      // The original local UUID remains the key after an ACK rebind, so a
      // manager's later history-based void can resolve the canonical bill.
      await outbox.enqueueEvent(
        snapshot.serverOrderUuid.isEmpty ? bill : snapshot.serverOrderUuid,
        event,
        createdAt: clock(),
      );
    });
  }

  Future<List<Map<String, dynamic>>> delta(DiningTableSession session) async {
    final bound = await _remember(session);
    if (bound.seatingKey == null) {
      return buildTableRoundLines(bound.draft?.items ?? []);
    }
    return tableRoundDelta(
      bound.draft?.items ?? [],
      await store.readLocalTableRounds(seatingKey: bound.seatingKey),
      await store.readLocalLineCancellations(seatingKey: bound.seatingKey),
    );
  }

  Future<LocalTableRound?> sendRound(DiningTableSession session) {
    if (!live) return Future.value(null);
    return _serial(() => _sendRound(session));
  }

  Future<LocalTableRound?> _sendRound(DiningTableSession source) async {
    final session = await _ensure(source);
    final lines = (await delta(
      session,
    )).where((line) => (line['qty'] as int) > 0).toList();
    if (lines.isEmpty) return null;
    final requestId = newUuid();
    final at = clock().toUtc();
    final key = 'tbl:${session.seatingKey}:round:$requestId';
    final previous = await store.readLocalTableRounds(
      seatingKey: session.seatingKey,
    );
    final next =
        previous.fold<int>(
          0,
          (max, r) => r.localRoundNo > max ? r.localRoundNo : max,
        ) +
        1;
    var round = LocalTableRound(
      clientRequestId: requestId,
      tableId: session.tableId,
      seatingKey: session.seatingKey!,
      localRoundNo: next,
      lines: lines,
      submittedAt: at,
      outboxKey: key,
      orderUuid: session.serverOrderUuid,
    );
    final event = _event(
      'round',
      session,
      {
        'client_request_id': requestId,
        'lines': lines,
        'submitted_at': at.toIso8601String(),
        'printed_at': null,
        'order_uuid': session.serverOrderUuid,
      },
      eventId: requestId,
      at: at,
    );
    await outbox.enqueueEvent(
      key,
      event,
      createdAt: at,
      beforeFlush: () async {
        await store.saveLocalTableRound(round);
        final printable = <Map<String, dynamic>>[];
        for (final line in lines) {
          final item = session.draft?.items.where((item) {
            final wire = buildTableRoundLines([item]);
            return wire.isNotEmpty &&
                tableLineFingerprint(wire.single) == tableLineFingerprint(line);
          }).firstOrNull;
          if (item != null) {
            printable.add({...item.toMap(), 'qty': line['qty']});
          }
        }
        final printed = await printRound?.call(session, printable) ?? false;
        final printedAt = printed ? clock().toUtc() : null;
        round = round.withChanges({'printed_at': printedAt?.toIso8601String()});
        await store.saveLocalTableRound(round);
        _changed();
        return {
          ...event,
          'payload': {
            ...(event['payload'] as Map<String, dynamic>),
            'printed_at': printedAt?.toIso8601String(),
          },
        };
      },
    );
    return (await store.readLocalTableRounds(
          seatingKey: session.seatingKey,
        )).where((r) => r.clientRequestId == requestId).firstOrNull ??
        round;
  }

  Future<void> cancelLine(
    DiningTableSession source, {
    required Map<String, dynamic> line,
    required int qty,
    required bool prepared,
    required String authorizedBy,
    String? reason,
  }) async {
    if (!live) return;
    if (authorizedBy.trim().isEmpty || qty <= 0) {
      throw ArgumentError('A positive cancellation needs manager approval.');
    }
    await _serial(() async {
      final session = await _ensure(source);
      final requestId = newUuid();
      final at = clock().toUtc();
      final key = 'tbl:${session.seatingKey}:cancel:$requestId';
      final cancellation = LocalLineCancellation(
        clientRequestId: requestId,
        tableId: session.tableId,
        seatingKey: session.seatingKey!,
        productId: line['product_id'] as int,
        addonIds: (line['addon_ids'] as List? ?? []).cast<int>(),
        notes: line['notes'] as String?,
        qty: qty,
        prepared: prepared,
        reason: reason,
        authorizedBy: authorizedBy,
        cancelledAt: at,
        outboxKey: key,
      );
      final stockMode = stockModeForProduct?.call(cancellation.productId);
      final event = _event(
        'cancel_line',
        session,
        {
          'client_request_id': requestId,
          'product_id': cancellation.productId,
          'addon_ids': cancellation.addonIds,
          'notes': cancellation.notes,
          'qty': qty,
          'prepared': prepared,
          'reason': reason,
          'authorized_by': authorizedBy,
          'cancelled_at': at.toIso8601String(),
        },
        eventId: requestId,
        at: at,
      );
      await outbox.enqueueEvent(
        key,
        event,
        createdAt: at,
        followingEvents: {
          if (prepared && (stockMode == 'unit' || stockMode == 'cooked'))
            'tbl:${session.seatingKey}:waste:$requestId': {
              'client_event_id': newUuid(),
              'event_type': 'product.waste',
              'client_timestamp': at.toIso8601String(),
              'payload': {
                'lines': [
                  {
                    'product_id': cancellation.productId,
                    'qty': qty,
                    'reason': 'other',
                  },
                ],
                'note':
                    'cancelled after preparation — table ${session.draft?.diningTableName ?? session.tableId}, ref ${session.tempReference ?? session.orderReference}',
                'staff_id': staffId(),
                'wasted_at': at.toIso8601String(),
              },
            },
        },
        beforeFlush: () async {
          await store.saveLocalLineCancellation(cancellation);
          return event;
        },
      );
      _changed();
    });
  }

  Future<void> _publishVerdicts() async {
    if (_disposed) return;
    final rows = await store.readTableSyncVerdicts(unseenOnly: true);
    if (!_disposed && rows.isNotEmpty) _verdicts.add(rows);
  }

  Future<void> markVerdictsSeen(List<TableSyncVerdict> rows) async {
    await store.markTableSyncVerdictsSeen(
      rows.map((r) => r.id).whereType<int>().toList(),
    );
    _changed();
  }

  Future<void> _applyAcks(
    OrderOutboxRow row,
    List<Map<String, dynamic>> events,
    List<Map<String, dynamic>> results,
  ) async {
    for (final event in events) {
      final ack = results
          .where(
            (r) =>
                r['client_event_id'] == event['client_event_id'] &&
                r['status'] == 'processed',
          )
          .firstOrNull;
      if (ack == null || ack['result'] is! Map) continue;
      final result = Map<String, dynamic>.from(ack['result'] as Map);
      final payload = Map<String, dynamic>.from(event['payload'] as Map);
      final type = event['event_type'] as String;
      final kind = type.split('.').last;
      final tableEvent = type.startsWith('table.session.');
      if (!tableEvent && type != 'order.pay' && type != 'order.void') continue;
      if (!tableEvent && row.orderUuid.endsWith(':pay')) continue;
      final seatKey = payload['seating_key']?.toString();
      final known = <String, DiningTableSession>{
        ..._sessions,
        for (final s in await loadSessions())
          if (s.seatingKey != null) s.tableId: s,
      };
      var session = known.values
          .where(
            (s) => tableEvent
                ? s.seatingKey == seatKey
                : s.serverOrderUuid == payload['order_uuid'],
          )
          .firstOrNull;
      if (session == null) continue;
      final outcome =
          result['outcome']?.toString() ?? (tableEvent ? '' : 'processed');
      final oldUuid = session.serverOrderUuid ?? '';
      final newBill = result['order_uuid']?.toString();
      if (newBill != null && newBill.isNotEmpty && newBill != oldUuid) {
        await outbox.rewritePendingOrderUuid(
          session.seatingKey!,
          oldUuid,
          newBill,
        );
        final rebound = session.copyWith(serverOrderUuid: newBill);
        bindBillIdentity?.call(rebound, oldUuid, newBill);
        session = rebound;
      }
      session = session.copyWith(
        seatingUuid: result['table_session_uuid']?.toString(),
        winnerSeatingUuid: result['winner_table_session_uuid']?.toString(),
        tempReference: result['temp_reference']?.toString(),
        lastVerdict: outcome,
        lastVerdictAt: clock().toUtc(),
      );
      var sheet = false;
      if (kind == 'open') {
        final state = switch (outcome) {
          'merged' => 'merged',
          'already_closed' => 'closed',
          'opened' || 'replayed' || 'attached' => 'open',
          _ => session.seatingState,
        };
        session = session.copyWith(seatingState: state);
        sheet = const {
          'attached',
          'merged',
          'already_closed',
        }.contains(outcome);
      } else if (kind == 'round') {
        final rounds = await store.readLocalTableRounds(
          seatingKey: session.seatingKey,
        );
        var round = rounds
            .where((r) => r.clientRequestId == payload['client_request_id'])
            .firstOrNull;
        // Recover a durable row whose process died before the sqflite write.
        round ??= LocalTableRound(
          clientRequestId: payload['client_request_id'] as String,
          tableId: session.tableId,
          seatingKey: session.seatingKey!,
          localRoundNo: rounds.length + 1,
          lines: (payload['lines'] as List)
              .map((l) => Map<String, dynamic>.from(l as Map))
              .toList(),
          submittedAt: DateTime.parse(payload['submitted_at'] as String),
          printedAt: DateTime.tryParse(payload['printed_at']?.toString() ?? ''),
          outboxKey: row.orderUuid,
          orderUuid: payload['order_uuid']?.toString(),
        );
        if (outcome != 'replayed') {
          final status = const {'appended', 'seating_created'}.contains(outcome)
              ? 'appended'
              : outcome;
          await store.saveLocalTableRound(
            round.withChanges({
              'status': status,
              'server_round_id': result['round_id'],
              'server_round_no': result['round_no'],
              'order_uuid': session.serverOrderUuid,
              'total_baisas': result['total_baisas'],
              'review_reasons_json': jsonEncode(result['review_reasons'] ?? []),
              'held_lines_json': jsonEncode(result['held_lines'] ?? []),
              'acked_at': clock().toUtc().toIso8601String(),
            }),
          );
        }
        if (payload['printed_at'] != null && result['round_id'] is num) {
          await markPrinted((result['round_id'] as num).toInt().toString());
        }
        if (outcome == 'merged') {
          session = session.copyWith(seatingState: 'merged');
        } else if (const {
          'appended',
          'seating_created',
          'held',
        }.contains(outcome)) {
          session = session.copyWith(seatingState: 'open');
        }
        sheet = const {
          'held',
          'merged',
          'bill_terminal',
          'bill_unpaid',
        }.contains(outcome);
      } else if (kind == 'move') {
        sheet = const {
          'target_occupied',
          'stale_generation',
          'unknown_seating',
        }.contains(outcome);
      } else if (kind == 'join') {
        sheet = (result['refused'] as List? ?? []).isNotEmpty;
      } else if (kind == 'close') {
        if (const {
          'closed',
          'already_closed',
          'tombstoned',
          'stale_generation',
          'replayed',
        }.contains(outcome)) {
          session = session.copyWith(seatingState: 'closed');
        }
        sheet = outcome == 'bill_unpaid';
      } else if (kind == 'cancel_line') {
        final cancellations = await store.readLocalLineCancellations(
          seatingKey: session.seatingKey,
        );
        final cancellation = cancellations
            .where((c) => c.clientRequestId == payload['client_request_id'])
            .firstOrNull;
        final cancelledQty = (result['cancelled_qty'] as num?)?.toInt() ?? 0;
        if (cancellation != null) {
          await store.saveLocalLineCancellation(
            cancellation.withChanges({
              'status': outcome,
              'cancelled_qty': cancelledQty,
              'acked_at': clock().toUtc().toIso8601String(),
            }),
          );
        }
        sheet =
            const {'nothing_to_cancel', 'bill_terminal'}.contains(outcome) ||
            (outcome != 'unknown_seating' &&
                cancelledQty < (payload['qty'] as num).toInt());
      } else if (kind == 'pay' || kind == 'void') {
        session = session.copyWith(seatingState: 'closed');
      }
      await _saveIdentity(session);
      if (sheet) {
        final existing = await store.readTableSyncVerdicts();
        if (!existing.any(
          (v) => v.detail['client_event_id'] == event['client_event_id'],
        )) {
          await store.addTableSyncVerdict(
            TableSyncVerdict(
              observedAt: clock().toUtc(),
              tableId: session.tableId,
              seatingKey: session.seatingKey,
              eventKind: kind,
              outcome: outcome,
              detail: {
                ...result,
                'client_event_id': event['client_event_id'],
                'request': payload,
              },
            ),
          );
        }
      }
      _changed();
    }
  }
}
