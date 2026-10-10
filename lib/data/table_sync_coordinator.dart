import '../tenancy/business_identity.dart';
import '../services/table_round_validation.dart';
import '../services/table_action_deadline.dart';
import '../draft_recovery/saved_copy_discard.dart';
import 'dart:async';
import 'dart:convert';
import '../dine_in/dine_in_models.dart';
import '../table_cancellation/table_bill_cancellation.dart';
import '../table_cancellation/table_bill_cancel_dialog.dart';

import '../core/auth_wire.dart';
import '../core/authorization.dart';
import '../models/pos_models.dart';
import '../models/table_sync_models.dart';
import '../services/order_sync_payload.dart';
import '../state/pos_controller.dart';
import 'db/app_database.dart';
import 'order_sync_repository.dart';

class TablePaymentContext {
  const TablePaymentContext({
    this.lat,
    this.lng,
    this.cardCharge,
    this.prepareEvent,
    this.eventId,
  });
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)?
  prepareEvent;
  final String? eventId;
  final double? lat;
  final double? lng;
  final CardCharge? cardCharge;
}

class TableVoidApproval {
  const TableVoidApproval({
    required this.authorizedBy,
    this.reason,
    this.reasonId,
    this.authorization,
    this.seatingKey,
  });
  final String authorizedBy;
  final String? reason;
  final int? reasonId;

  /// LAUNCH-P5 C3 — the order.void_unpaid gate of the table clear.
  final ActionAuthorization? authorization;

  /// LAUNCH-P5 fix order 2 (T8) — the one table session this approval may
  /// clear (null = whichever table is cleared next, the pre-P5 behaviour).
  final String? seatingKey;

  /// Wipe the approver's key (once used, replaced or dropped).
  void forget() => authorization?.grant?.forget();
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
    if (store is ArchivedTableOutbox) {
      final archive = store as ArchivedTableOutbox;
      outbox.tableCopyArchived = archive.tableOutboxArchived;
      outbox.archivedTableCopies = archive.archivedTableOutbox;
    }
    outbox.cancellationRoute = (event) async {
      final intent = (await store.readTableSyncVerdicts(limit: 1000000))
          .singleWhere(
            (v) =>
                v.eventKind == 'cancel_bill_intent' &&
                v.detail['event']['client_event_id'] ==
                    event['client_event_id'],
          );
      if (jsonEncode(intent.detail['event']) != jsonEncode(event)) {
        throw StateError('Cancellation request changed');
      }
      return intent.detail['seating_uuid'] as String;
    };
    outbox.addAckListener(_applyAcks);
    _flushSubscription = outbox.flushCompletions.listen((_) {
      unawaited(_publishVerdicts());
    });
  }

  /// Validated pay ACK summaries for the completion notice, keyed by canonical bill.
  final Map<String, Map<String, dynamic>> loyaltyEarnedByOrder = {};
  final Set<String> _consumedLoyaltyNotices = {};

  /// Receipt refresh and late ACK listeners share one consumption boundary.
  /// A retry of the same canonical payment cannot publish the notice twice.
  Map<String, dynamic>? takeLoyaltyEarned(String orderUuid) {
    final earned = loyaltyEarnedByOrder.remove(orderUuid);
    if (earned == null || !_consumedLoyaltyNotices.add(orderUuid)) return null;
    return earned;
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
  void Function(List<Map<String, dynamic>> lines)? validateRound;
  final DateTime Function() clock;
  final String Function() newUuid;
  final Future<void> Function(DiningTableSession)? guardSession;

  Future<bool> Function(DiningTableSession, List<Map<String, dynamic>>)?
  printRound;
  Future<TablePaymentContext> Function(OrderSnapshot)? paymentContext;
  Future<void> Function(Map<String, dynamic>, Map<String, dynamic>)?
  paymentAcknowledged;

  /// LAUNCH-P5 fix order 2 (T8) — the approval for the next clear of one
  /// table session. Replacing or dropping it wipes the old approver key.
  TableVoidApproval? get clearApproval => _clearApproval;
  set clearApproval(TableVoidApproval? value) {
    final previous = _clearApproval;
    _clearApproval = value;
    if (previous != null && !identical(previous, value)) previous.forget();
  }

  TableVoidApproval? _clearApproval;

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
    for (final intent in await store.readTableSyncVerdicts(limit: 1000000)) {
      if (intent.eventKind != 'cancel_bill_intent') continue;
      final event = Map<String, dynamic>.from(intent.detail['event'] as Map);
      if (await outbox.rowForKey('cancel-bill:${event['client_event_id']}') ==
          null) {
        await outbox.enqueueEvent(
          'cancel-bill:${event['client_event_id']}',
          event,
          createdAt: DateTime.parse(event['client_timestamp'] as String),
        );
      }
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
    outbox.cancellationRoute = null;
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
    TableActionDeadline.background(() {
      unawaited(_serial(operation).catchError((Object _) {}));
    });
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
    final given = _clearApproval;
    _clearApproval = null;
    _hook(() async {
      try {
        await _clearTablesWith(given, groupIds, head);
      } finally {
        // LAUNCH-P5 fix order 2 (T8) — used or not, the key goes now.
        given?.forget();
      }
    });
  }

  Future<void> _clearTablesWith(
    TableVoidApproval? given,
    Set<String> groupIds,
    DiningTableSession? head,
  ) async {
    {
      final source =
          head ??
          groupIds
              .map((id) => _sessions[id])
              .whereType<DiningTableSession>()
              .firstOrNull;
      if (source == null) return;
      final session = await _remember(source);
      if (session.seatingKey == null) return;
      // LAUNCH-P5 fix order 2 (T8) — an approval given for another table
      // session never clears this one.
      final approval =
          given?.seatingKey == null || given!.seatingKey == session.seatingKey
          ? given
          : null;
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
            authorization: approval?.authorization?.block(
              subjectUuid: session.serverOrderUuid,
            ),
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
    }
  }

  @override
  Future<void> onTablePaid(
    DiningTableSession paid,
    OrderSnapshot snapshot,
  ) async {
    if (!live) return;
    final context =
        paymentContext?.call(snapshot) ??
        Future.value(const TablePaymentContext());
    await _serial(
      () => BusinessBoundary.persistPaid(snapshot.businessIdentity, () async {
        final session = await _remember(paid);
        if (session.seatingKey == null) {
          throw StateError('A Live table payment must have a seating.');
        }
        final payment = await context;
        final bill = session.serverOrderUuid ?? snapshot.serverOrderUuid;
        final event = buildOrderPayEvent(
          snapshot,
          orderUuid: bill,
          suppressDeviceLoyaltyRedeem: true,
          lat: payment.lat,
          lng: payment.lng,
          cardCharge: payment.cardCharge,
          now: clock(),
          newUuid: payment.eventId == null ? newUuid : () => payment.eventId!,
          staffId: staffId(),
        );
        // The original local UUID remains the key after an ACK rebind, so a
        // manager's later history-based void can resolve the canonical bill.
        await outbox.enqueueEvent(
          snapshot.serverOrderUuid.isEmpty ? bill : snapshot.serverOrderUuid,
          event,
          createdAt: clock(),
          waitForSync: false,
          enrichGps: payment.lat == null || payment.lng == null,
          beforeFlush: payment.prepareEvent == null
              ? null
              : () => payment.prepareEvent!(event),
        );
      }),
    );
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

  Future<List<LocalTableRound>> heldRounds(DiningTableSession source) async {
    final session = await _remember(source);
    return (await store.readLocalTableRounds(
      seatingKey: session.seatingKey,
    )).where((round) => round.status == 'held').toList();
  }

  /// Explicit staff action. Retain immutable requests/print evidence. A lost
  /// rejection response is recovered by rereading the exact server round.
  Future<void> rejectHeldRounds(
    DiningTableSession source, {
    required Future<Map<String, dynamic>> Function() readDetail,
    required Future<void> Function(String seatingUuid, int roundId) reject,
    required bool Function() isCurrent,
  }) => _serial(() async {
    final session = await _remember(source);
    void check() {
      if (!live ||
          !isCurrent() ||
          session.seatingUuid == null ||
          session.serverOrderUuid == null) {
        throw StateError('Table context changed.');
      }
    }

    check();
    if ((await outbox.pendingRows()).any(
      (row) => !OrderSyncRepository.isParkedWaste(row),
    )) {
      throw StateError('Finish pending sync before reviewing this round.');
    }
    final held = await heldRounds(session);
    for (final round in held) {
      Map<String, dynamic> exact(Map<String, dynamic> detail) {
        check();
        final seat = detail['seating'] as Map?;
        final bill = detail['bill'] as Map?;
        final server = (detail['rounds'] as List? ?? const [])
            .whereType<Map>()
            .where((r) => r['id'] == round.serverRoundId)
            .firstOrNull;
        if (round.serverRoundId == null ||
            round.ackedAt == null ||
            round.orderUuid != session.serverOrderUuid ||
            seat?['uuid'] != session.seatingUuid ||
            seat?['status'] != 'open' ||
            bill?['uuid'] != session.serverOrderUuid ||
            bill?['status'] != 'open' ||
            bill?['charge'] != 'none' ||
            server == null ||
            server['entered_by'] != 'staff' ||
            server['client_request_id'] != round.clientRequestId) {
          throw StateError('The held round changed. Refresh the table.');
        }
        return Map<String, dynamic>.from(server);
      }

      var server = exact(await readDetail());
      if (server['status'] == 'pending_confirmation') {
        check();
        await reject(session.seatingUuid!, round.serverRoundId!);
        server = exact(await readDetail());
      }
      if (server['status'] != 'rejected') {
        throw StateError('The round was not rejected. Review the server bill.');
      }
      check();
      await store.saveLocalTableRound(
        round.withChanges({'status': 'rejected'}),
      );
      _changed();
    }
  });

  Future<LocalTableRound?> sendRound(DiningTableSession session) {
    if (!live) return Future.value(null);
    return _serial(() => _sendRound(session));
  }

  Future<LocalTableRound?> _sendRound(DiningTableSession source) async {
    final session = await _ensure(source);
    if ((await heldRounds(session)).isNotEmpty) {
      throw const TableRoundReviewRequired();
    }
    final lines = (await delta(
      session,
    )).where((line) => (line['qty'] as int) > 0).toList();
    if (lines.isEmpty) return null;
    validateRound?.call(lines);
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
    // LAUNCH-P5 C3 — the table.cancel_line gate.
    ActionAuthorization? authorization,
  }) async {
    if (!live) return;
    if (outbox.managedKitchen?.call() == true) {
      throw StateError(
        'Use the connected table bill to cancel sent kitchen items.',
      );
    }
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
        line: line,
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
          // LAUNCH combo add-on — which line: a meal main is not the plain
          // main (the server matches on product / add-ons / notes today).
          if (line['meal_id'] != null) 'meal_id': line['meal_id'],
          'qty': qty,
          'prepared': prepared,
          'reason': reason,
          'authorized_by': authorizedBy,
          'cancelled_at': at.toIso8601String(),
          if (authorization != null)
            'authorization': authorization.block(
              subjectUuid: session.seatingKey,
              ref: requestId,
            ),
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
                'table_cancellation_request_id': requestId,
                ...authStamp(staffId: staffId()),
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

  /// The existing verdict journal retains immutable intent, identity, and ACK.
  /// The outbox carries only the exact server contract. Retrying never re-picks.
  Future<Map<String, dynamic>?> cancelBill({
    required int tableId,
    required String billUuid,
    required Future<DineInDetail> Function() read,
    required Future<BillCancelChoice?> Function(DineInDetail) pick,
    required Future<bool> Function() approve,
    required Future<void> Function() guard,
    // LAUNCH-P5 C3 — the table.cancel_bill gate, read after [approve].
    ActionAuthorization? Function()? authorization,
  }) => _serial(() async {
    if (!live || degraded()) throw StateError('cancel_offline');
    final history = await store.readTableSyncVerdicts(limit: 1000000);
    final pending = history
        .where(
          (v) =>
              v.eventKind == 'cancel_bill_intent' &&
              v.detail['order_uuid'] == billUuid &&
              !history.any(
                (a) =>
                    a.eventKind == 'cancel_bill' &&
                    a.detail['client_event_id'] ==
                        v.detail['event']['client_event_id'],
              ),
        )
        .toList();
    if (pending.length > 1) throw StateError('cancel_blocked');
    Map<String, dynamic> event;
    if (pending.isNotEmpty) {
      event = Map<String, dynamic>.from(pending.single.detail['event'] as Map);
    } else {
      await guard();
      await outbox.assertIdleForCombine();
      final before = await read();
      if (before.tableId != tableId ||
          before.billUuid != billUuid ||
          !before.canAppend) {
        throw StateError('bill_reserved');
      }
      final groups = BillCancelGroup.fromRounds(before.rounds);
      if (groups.isEmpty) throw StateError('nothing_to_cancel');
      final choice = await pick(before);
      if (choice == null || !await approve()) return null;
      await guard();
      await outbox.assertIdleForCombine();
      if (degraded()) throw StateError('cancel_offline');
      final after = await read();
      if (after.tableId != tableId ||
          !after.canAppend ||
          after.seatingUuid != before.seatingUuid ||
          after.billUuid != billUuid ||
          jsonEncode(after.bill) != jsonEncode(before.bill) ||
          jsonEncode(after.rounds) != jsonEncode(before.rounds)) {
        throw StateError('bill_changed');
      }
      if (choice.reason.trim().isEmpty ||
          choice.reason.length > 200 ||
          choice.lines.length != groups.length) {
        throw StateError('cancel_blocked');
      }
      final lines = <Map<String, dynamic>>[], waste = <String, dynamic>{};
      for (var i = 0; i < groups.length; i++) {
        final group = groups[i], line = choice.lines[i];
        if (jsonEncode({...group.selector, 'qty': group.qty}) !=
                jsonEncode({
                  for (final e in line.entries)
                    if (e.key != 'prepared') e.key: e.value,
                }) ||
            line['prepared'] is! bool) {
          throw StateError('bill_changed');
        }
        final id = newUuid();
        lines.add({'client_request_id': id, ...line});
        waste[id] = {
          'id': newUuid(),
          'stock_mode': stockModeForProduct?.call(line['product_id'] as int),
        };
      }
      final id = newUuid(), at = clock().toUtc().toIso8601String();
      final gate = authorization?.call();
      final local = (await loadSessions())
          .where(
            (s) => s.tableId == '$tableId' && s.serverOrderUuid == billUuid,
          )
          .firstOrNull;
      final seatingKey = local?.seatingKey ?? newUuid();
      event = {
        'client_event_id': id,
        'event_type': 'table.session.cancel_bill',
        'client_timestamp': at,
        'payload': {
          'client_request_id': id,
          'seating_key': seatingKey,
          'table_id': after.primaryTableId!,
          'queued_offline': false,
          'staff_id': ?staffId(),
          'reason': choice.reason.trim(),
          'authorized_by': gate?.authorizedByName ?? 'Manager',
          'cancelled_at': at,
          'lines': lines,
          if (gate != null)
            'authorization': gate.block(subjectUuid: seatingKey, ref: id),
          ...authStamp(staffId: staffId()),
        },
      };
      gate?.grant?.forget();
      await store.addTableSyncVerdict(
        TableSyncVerdict(
          observedAt: clock().toUtc(),
          tableId: '$tableId',
          seatingKey: event['payload']['seating_key'] as String,
          eventKind: 'cancel_bill_intent',
          outcome: 'saved',
          seen: true,
          detail: {
            'event': event,
            'order_uuid': billUuid,
            'seating_uuid': after.seatingUuid,
            'waste': waste,
          },
        ),
      );
    }
    await outbox.enqueueEvent(
      'cancel-bill:${event['client_event_id']}',
      event,
      createdAt: DateTime.parse(event['client_timestamp'] as String),
    );
    // An already-enqueued lost response still needs a fresh pass.
    final result = (await store.readTableSyncVerdicts(limit: 1000000))
        .where(
          (v) =>
              v.eventKind == 'cancel_bill' &&
              v.detail['client_event_id'] == event['client_event_id'],
        )
        .firstOrNull;
    if (result == null) return {'outcome': 'uncertain'};
    return result.detail;
  });

  Future<bool> _cancelAck(
    Map<String, dynamic> event,
    List<Map<String, dynamic>> results,
  ) async {
    final kind = event['event_type'];
    if (kind != 'table.session.cancel_bill' &&
        kind != 'table.session.cancel_line') {
      return false;
    }
    final code = cancellationFailedCode(event, results);
    final ack = results
        .where((r) => r['client_event_id'] == event['client_event_id'])
        .singleOrNull;
    if (ack == null) throw const FormatException('Missing cancellation result');
    if (code == null &&
        (ack['status'] != 'processed' || ack['result'] is! Map)) {
      throw const FormatException('Uncertain cancellation');
    }
    if (kind == 'table.session.cancel_line' && code == null) return false;
    final payload = Map<String, dynamic>.from(event['payload'] as Map);
    final result = code == null
        ? Map<String, dynamic>.from(ack['result'] as Map)
        : <String, dynamic>{
            'outcome': 'refused',
            'refusal_code': code,
            'server_ack': ack,
          };
    if (kind == 'table.session.cancel_bill' && code == null) {
      final intent = (await store.readTableSyncVerdicts(limit: 1000000))
          .singleWhere(
            (v) =>
                v.eventKind == 'cancel_bill_intent' &&
                v.detail['event']['client_event_id'] ==
                    event['client_event_id'],
          );
      validateBillCancellation(
        payload,
        result,
        intent.detail['order_uuid'] as String,
        intent.detail['seating_uuid'] as String,
      );
      for (final raw in payload['lines'] as List) {
        final line = Map<String, dynamic>.from(raw as Map),
            meta = Map<String, dynamic>.from(
              intent.detail['waste'][raw['client_request_id']] as Map,
            );
        if (line['prepared'] != true ||
            !const {'unit', 'cooked'}.contains(meta['stock_mode'])) {
          continue;
        }
        await outbox.enqueueAfterAcknowledgement(
          'cancel-waste:${line['client_request_id']}',
          {
            'client_event_id': meta['id'],
            'event_type': 'product.waste',
            'client_timestamp': event['client_timestamp'],
            'payload': {
              'table_cancellation_request_id': line['client_request_id'],
              'lines': [
                {
                  'product_id': line['product_id'],
                  'qty': line['qty'],
                  'reason': 'other',
                },
              ],
              'staff_id': payload['staff_id'],
              'wasted_at': payload['cancelled_at'],
              'note':
                  'cancelled after preparation — table ${payload['table_id']}',
              // The cancel_bill maker's token, not whoever is logged in
              // when the server acknowledges it.
              ...authStamp(
                staffId: payload['staff_id'] is int
                    ? payload['staff_id'] as int
                    : null,
                staffToken: payload['staff_token'] is String
                    ? payload['staff_token'] as String
                    : null,
              ),
            },
          },
        );
      }
    }
    final previous = await store.readTableSyncVerdicts(limit: 1000000);
    if (!previous.any(
      (v) =>
          v.eventKind == kind.toString().split('.').last &&
          v.detail['client_event_id'] == event['client_event_id'],
    )) {
      await store.addTableSyncVerdict(
        TableSyncVerdict(
          observedAt: clock().toUtc(),
          tableId: '${payload['table_id']}',
          seatingKey: payload['seating_key'] as String,
          eventKind: kind.toString().split('.').last,
          outcome: result['outcome'] as String,
          detail: {
            ...result,
            // LAUNCH-P5 fix order 2 (T11) — no staff token at rest.
            'request': payloadWithoutStaffToken(payload),
            'client_event_id': event['client_event_id'],
          },
        ),
      );
    }
    if (kind == 'table.session.cancel_line' && code != null) {
      final rows = await store.readLocalLineCancellations(
        seatingKey: payload['seating_key'] as String,
      );
      final row = rows
          .where((r) => r.clientRequestId == payload['client_request_id'])
          .firstOrNull;
      if (row != null) {
        await store.saveLocalLineCancellation(
          row.withChanges({
            'status': code,
            'cancelled_qty': 0,
            'acked_at': clock().toUtc().toIso8601String(),
          }),
        );
      }
    }
    _changed();
    return true;
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
      if (await _cancelAck(event, results)) continue;
      if (event['event_type'] == 'order.pay') {
        final paymentAck = results
            .where(
              (result) => result['client_event_id'] == event['client_event_id'],
            )
            .firstOrNull;
        if (paymentAck == null) {
          throw StateError('Check payment result: missing payment ACK');
        }
        await paymentAcknowledged?.call(event, paymentAck);
      }
      final ack = results
          .where(
            (r) =>
                r['client_event_id'] == event['client_event_id'] &&
                r['status'] == 'processed',
          )
          .firstOrNull;
      if (ack == null || ack['result'] is! Map) continue;
      final result = Map<String, dynamic>.from(ack['result'] as Map);
      if (event['event_type'] == 'product.waste' &&
          (result['wasted_lines'] as num? ?? 0) > 0) {
        final reference =
            (event['payload'] as Map)['table_cancellation_request_id'];
        final verdicts = await store.readTableSyncVerdicts(limit: 1000000);
        final intent = verdicts
            .where(
              (v) =>
                  v.eventKind == 'cancel_bill_intent' &&
                  (v.detail['waste'] as Map).containsKey(reference),
            )
            .firstOrNull;
        if (intent != null &&
            !verdicts.any(
              (v) =>
                  v.eventKind == 'cancel_shelf_waste' &&
                  v.detail['client_event_id'] == event['client_event_id'],
            )) {
          await store.addTableSyncVerdict(
            TableSyncVerdict(
              observedAt: clock().toUtc(),
              tableId: intent.tableId,
              seatingKey: intent.seatingKey,
              eventKind: 'cancel_shelf_waste',
              outcome: 'recorded',
              detail: {
                'client_event_id': event['client_event_id'],
                'table_cancellation_request_id': reference,
                'server_ack': ack,
              },
            ),
          );
        }
      }
      if (event['event_type'] == 'order.pay' &&
          (result['status'] != 'paid' || result['orphan_tender'] == true)) {
        continue; // A tender held for review did not close the seating.
      }
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
      if (type == 'order.pay' &&
          result['loyalty_earned'] is Map &&
          !_consumedLoyaltyNotices.contains(payload['order_uuid'])) {
        loyaltyEarnedByOrder[payload['order_uuid'] as String] =
            Map<String, dynamic>.from(result['loyalty_earned'] as Map);
      }
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
        // A replay of the original held acknowledgement cannot undo a later
        // verified rejection. Keep the review and print audit immutable.
        if (round?.status == 'rejected') continue;
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
            (result['waste'] as Map?)?['booked'] == true ||
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
                // LAUNCH-P5 fix order 2 (T11) — no staff token at rest.
                'request': payloadWithoutStaffToken(payload),
              },
            ),
          );
        }
      }
      _changed();
    }
  }
}
