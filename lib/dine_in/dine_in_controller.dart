import '../table_cancellation/table_bill_cancellation.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/auth_wire.dart' show makerStaffToken;
import '../core/authorization.dart';
import '../qr_quick/qr_quick_models.dart';
import 'dine_in_models.dart';
import 'dine_in_store.dart';

abstract interface class DineInGateway {
  Future<DineInDetail> detail(int tableId);
  Future<Map<String, dynamic>> append(DineInRequest request);
  Future<Map<String, dynamic>> adjust(DineInRequest request);
  Future<void> review(
    DineInDetail detail,
    Map<String, dynamic> round,
    bool accept,
  );
  Future<void> clear(int tableId, {String? seatingUuid});
  Future<void> reopen(String uuid);
}

abstract interface class DineInContextGuard {
  void check();
}

class DineInController extends ChangeNotifier {
  DineInController(
    this.gateway,
    DineInStore store,
    this.tableId, {
    this.staffId,
    this.localDraftTables,
    this.printAccepted,
    this.recordCancellationWaste,
    this.tabletPrintOff,
  }) : store = store is SqliteDineInStore ? store.forTable(tableId) : store;
  final DineInGateway gateway;
  final DineInStore store;
  final int tableId;
  final int? staffId;
  final Future<void> Function(DineInRequest, int)? recordCancellationWaste;
  final Set<int> Function()? localDraftTables;
  final Future<bool> Function(DineInDetail, Map<String, dynamic>)?
  printAccepted;

  /// LAUNCH-P6 T-3 — this till does not print a confirmed tablet round.
  final bool Function()? tabletPrintOff;
  bool _localConflict(DineInDetail value) => value.coveredTableIds.any(
    (id) => localDraftTables?.call().contains(id) == true,
  );
  bool get hasLocalConflict => detail != null && _localConflict(detail!);
  DineInDetail? detail;
  DineInRequest? pending;
  bool ready = false, stale = true, busy = false;
  bool _reading = false, _disposed = false, _foreground = true;
  int _generation = 0;
  String? notice;
  bool get available =>
      ready &&
      !stale &&
      !busy &&
      _foreground &&
      pending == null &&
      !hasLocalConflict;
  bool get canAdd => available && detail?.canAppend == true;
  bool get canAdjust =>
      available &&
      detail?.canAppend == true &&
      detail?.billUuid != null &&
      !detail!.pendingReview;
  String? get adjustmentBlocked => pending != null
      ? 'pending_adjustment'
      : detail?.billUuid == null
      ? 'bill_missing'
      : detail?.pendingReview == true
      ? 'adjustment_review'
      : detail?.canAppend != true
      ? 'bill_reserved'
      : !available
      ? 'refresh'
      : null;
  bool get canPay =>
      available &&
      detail?.protectedCheckout == true &&
      !detail!.pendingReview &&
      const {
        'open',
        'held',
        'awaiting_payment',
      }.contains(detail?.bill?['status']);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    try {
      pending = await store.load();
      ready = true;
      await refresh();
    } catch (_) {
      ready = false;
      notice = 'storage';
    }
    _notify();
  }

  void setForeground(bool value) {
    _foreground = value;
    stale = true;
    _generation++;
    _notify();
  }

  Future<void> refresh() async {
    if (!ready || busy || _reading || _disposed || !_foreground) return;
    _reading = true;
    final generation = _generation;
    try {
      final next = await gateway.detail(tableId);
      if (next.tableId != tableId) throw const FormatException('Wrong table');
      if (generation == _generation && !_disposed) {
        detail = next;
        stale = false;
      }
    } catch (_) {
      if (generation == _generation) stale = true;
    } finally {
      _reading = false;
      _notify();
    }
  }

  Future<bool> add(
    List<QrQuickLine> lines, {
    String? expectedSeating,
    String? expectedBill,
  }) async {
    if (!canAdd || lines.isEmpty) return false;
    final before = detail!;
    if (expectedSeating != null &&
        (before.seatingUuid != expectedSeating ||
            before.billUuid != expectedBill)) {
      notice = 'changed';
      _notify();
      return false;
    }
    busy = true;
    _generation++;
    notice = null;
    _notify();
    try {
      // Re-read immediately; never retarget an unsent draft to a new party.
      final now = await gateway.detail(tableId);
      if (!now.canAppend ||
          _localConflict(now) ||
          now.seatingUuid != before.seatingUuid ||
          now.billUuid != before.billUuid) {
        detail = now;
        notice = 'changed';
        return false;
      }
      final request = DineInRequest.create(now, lines, staffId);
      try {
        await store.save(request); // Must commit before POST.
      } catch (_) {
        // Another host may have saved an intent since this one opened.
        // Re-read it; never let a stale in-memory empty journal enable payment.
        try {
          pending = await store.load();
        } catch (_) {
          ready = false;
        }
        if (pending == null) ready = false;
        notice = 'storage';
        return false;
      }
      pending = request;
      return await _send(request, fresh: true);
    } catch (_) {
      notice = pending == null ? 'refresh' : 'uncertain';
      return false;
    } finally {
      busy = false;
      stale = true;
      _notify();
      await refresh();
    }
  }

  /// Uses the normal manager gate, revalidates the bill after approval, and
  /// persists one immutable cancellation before sending it to the same seating.
  Future<bool> cancelLine(
    Map<String, dynamic> line,
    int qty, {
    required Future<Map<String, dynamic>?> Function() approve,
  }) async {
    if (!canAdd ||
        qty < 1 ||
        qty > (line['qty'] as num) ||
        detail?.billUuid == null) {
      return false;
    }
    final before = detail!;
    final ids = (line['item_ids'] as List?) ?? [line['id']];
    final currentLines = (before.bill!['items'] as List)
        .map(tableMap)
        .where((r) => ids.contains(r['id']))
        .toList();
    String selector(Map<String, dynamic> row) => jsonEncode([
      row['product_id'],
      ((row['addons'] as List? ?? [])
          .map((a) => qrMap(a)['add_on_id'])
          .toSet()
          .toList()
        ..sort()),
      (row['notes'] as String? ?? '')
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ')
          .toLowerCase(),
    ]);
    if (currentLines.length != ids.length ||
        currentLines.any((r) => selector(r) != selector(line)) ||
        currentLines.fold<num>(0, (n, r) => n + (r['qty'] as num)) !=
            line['qty'] ||
        currentLines.fold<int>(
              0,
              (n, r) => n + (r['line_total_baisas'] as int),
            ) !=
            line['line_total_baisas']) {
      notice = 'changed';
      _notify();
      return false;
    }
    busy = true;
    _generation++;
    notice = null;
    _notify();
    try {
      final approval = await approve();
      if (approval == null || _disposed || !_foreground) return false;
      final current = await gateway.detail(tableId);
      if (_disposed ||
          !_foreground ||
          !current.canAppend ||
          _localConflict(current) ||
          current.seatingUuid != before.seatingUuid ||
          current.billUuid != before.billUuid ||
          jsonEncode(current.bill) != jsonEncode(before.bill) ||
          jsonEncode(current.rounds) != jsonEncode(before.rounds)) {
        notice = 'changed';
        return false;
      }
      if (approval['prepared'] == true && recordCancellationWaste == null) {
        throw StateError('Waste journal unavailable');
      }
      // LAUNCH-P5 C3 — the table.cancel_line gate, signed over this
      // request's seating_key (one approval may cover several lines of a
      // clear).
      final requestId = QrQuickRequest.newId();
      final seatingKey = QrQuickRequest.newId();
      final gate = approval['gate'];
      final authorization = gate is ActionAuthorization
          ? gate.block(subjectUuid: seatingKey, ref: requestId)
          : null;
      final request = DineInRequest(
        tableId: tableId,
        seatingUuid: current.seatingUuid!,
        billUuid: current.billUuid,
        staffToken: makerStaffToken(staffId),
        payload: {
          'table_id': current.primaryTableId!,
          'seating_key': seatingKey,
          'client_request_id': requestId,
          'queued_offline': false,
          'staff_id': ?staffId,
          'authorization': ?authorization,
          if (authorization != null) 'auth_v': 1,
          'cancellation': {
            'product_id': line['product_id'],
            'qty': qty,
            'addon_ids': [
              for (final raw in line['addons'] as List? ?? [])
                qrMap(raw)['add_on_id'],
            ],
            'notes': line['notes'],
            'prepared': approval['prepared'],
            'authorized_by':
                (approval['authorized_by'] as String?)?.trim().isNotEmpty ==
                    true
                ? approval['authorized_by']
                : 'Manager',
            'reason': approval['reason'],
            'cancelled_at': DateTime.now().toUtc().toIso8601String(),
            'waste_event_id': QrQuickRequest.newId(),
          },
        },
      );
      try {
        await store.save(request);
      } catch (_) {
        pending = await store.load();
        if (pending == null) ready = false;
        notice = 'storage';
        return false;
      }
      pending = request;
      return await _send(request, fresh: true);
    } catch (_) {
      notice = pending == null ? 'refresh' : 'uncertain';
      return false;
    } finally {
      busy = false;
      stale = true;
      _notify();
      await refresh();
    }
  }

  /// The picker includes the existing manager gate. It runs only after a
  /// fresh read; a second byte-for-byte read fences the entire approval window.
  ///
  /// LAUNCH-P5 fix order 2 (T7) — when the server refuses it with
  /// `approval_required` (the person's tick did not cover it), [approvalPick]
  /// is run once: the same choice, through the approval sheet, as a new
  /// request.
  Future<bool> adjust(
    Future<Map<String, dynamic>?> Function(DineInDetail) pick, {
    Future<Map<String, dynamic>?> Function(DineInDetail)? approvalPick,
  }) async {
    final ok = await _adjustOnce(pick);
    if (ok ||
        approvalPick == null ||
        notice != 'adjust_refused:approval_required') {
      return ok;
    }
    return _adjustOnce(approvalPick);
  }

  Future<bool> _adjustOnce(
    Future<Map<String, dynamic>?> Function(DineInDetail) pick,
  ) async {
    if (!canAdjust) return false;
    final previous = detail!;
    busy = true;
    _generation++;
    notice = null;
    _notify();
    try {
      final before = await gateway.detail(tableId);
      if (!before.canAppend ||
          before.pendingReview ||
          _localConflict(before) ||
          before.seatingUuid != previous.seatingUuid ||
          before.billUuid != previous.billUuid) {
        notice = 'changed';
        return false;
      }
      detail = before;
      final picked = await pick(before);
      if (picked == null) return false;
      // LAUNCH-P5 C3 — the gate rides beside the price-free intent, never
      // inside it; it is signed over this request's seating_key and, for a
      // fixed discount, its amount (Part A §6).
      final intent = Map<String, dynamic>.from(picked);
      final gate = intent.remove('gate');
      final rule = intent.remove('gate_rule_amount');
      final seatingKey = QrQuickRequest.newId();
      // LAUNCH-P5 fix order 1 (F3/F4) — one proof per request: its ref is
      // this request's client_request_id, and a discount is signed over
      // the amount the server computes for it.
      final requestId = QrQuickRequest.newId();
      final authorization = gate is ActionAuthorization
          ? gate.block(
              subjectUuid: seatingKey,
              amountBaisas: tableAdjustProofAmount(
                before,
                intent,
                rule: rule is Map ? rule : null,
              ),
              ref: requestId,
            )
          : null;
      if (gate is ActionAuthorization) gate.grant?.forget();
      if (_disposed || !_foreground) {
        notice = 'refresh';
        return false;
      }
      final current = await gateway.detail(tableId);
      if (_disposed ||
          !_foreground ||
          !current.canAppend ||
          current.pendingReview ||
          _localConflict(current) ||
          current.seatingUuid != before.seatingUuid ||
          current.billUuid != before.billUuid ||
          jsonEncode(current.bill) != jsonEncode(before.bill) ||
          jsonEncode(current.rounds) != jsonEncode(before.rounds)) {
        notice = 'changed';
        return false;
      }
      final request = DineInRequest(
        tableId: tableId,
        seatingUuid: current.seatingUuid!,
        billUuid: current.billUuid,
        staffToken: makerStaffToken(staffId),
        payload: {
          'table_id': current.primaryTableId!,
          'seating_key': seatingKey,
          'client_request_id': requestId,
          'queued_offline': false,
          'staff_id': ?staffId,
          'adjustment': intent,
          'authorization': ?authorization,
          if (authorization != null) 'auth_v': 1,
        },
      );
      try {
        await store.save(request);
      } catch (_) {
        pending = await store.load();
        if (pending == null) ready = false;
        notice = 'storage';
        return false;
      }
      pending = request;
      return await _send(request, fresh: true);
    } catch (_) {
      notice = pending == null ? 'refresh' : 'uncertain';
      return false;
    } finally {
      busy = false;
      stale = true;
      _notify();
      await refresh();
    }
  }

  Future<bool> retry() async {
    if (!ready || busy || !_foreground || pending == null) return false;
    busy = true;
    _generation++;
    notice = null;
    _notify();
    try {
      final request = pending!;
      // An adjustment retry keeps its original route and payload. Even if the
      // board changed, only the server may decide replay versus refusal.
      if (request.isAdjustment) return await _send(request, fresh: false);
      // An old intent may not open a new seating after a clear/prune/reassignment.
      final current = await gateway.detail(request.tableId);
      if (_localConflict(current) ||
          current.seatingUuid != request.seatingUuid ||
          (request.billUuid != null && current.billUuid != request.billUuid)) {
        notice = 'recovery';
        return false;
      }
      return await _send(request, fresh: false);
    } catch (_) {
      notice = 'uncertain';
      return false;
    } finally {
      busy = false;
      stale = true;
      _notify();
      await refresh();
    }
  }

  bool get canDiscardAdjustment =>
      ready &&
      !busy &&
      _foreground &&
      pending?.isAdjustment == true &&
      (notice == 'uncertain' || notice == 'staff_unverified') &&
      store is SqliteDineInStore;

  Future<bool> discardPendingAdjustment(Future<bool> Function() approve) async {
    if (!canDiscardAdjustment) return false;
    final request = pending!;
    busy = true;
    _notify();
    try {
      if (gateway case final DineInContextGuard guard) {
        guard.check();
      }
      if (!await approve() ||
          _disposed ||
          !_foreground ||
          pending?.encoded != request.encoded) {
        return false;
      }
      if (gateway case final DineInContextGuard guard) {
        guard.check();
      }
      await (store as SqliteDineInStore).discardAdjustment(request, staffId);
      pending = null;
      notice = 'adjustment_discarded';
      return true;
    } catch (_) {
      notice = 'storage';
      return false;
    } finally {
      busy = false;
      stale = true;
      _notify();
      await refresh();
    }
  }

  Future<bool> _send(DineInRequest request, {required bool fresh}) async {
    try {
      final result = request.isAdjustment
          ? await gateway.adjust(request)
          : await gateway.append(request);
      final outcome = result['outcome'];
      if (request.isAdjustment) {
        if (!const {'adjusted', 'replayed'}.contains(outcome) ||
            (result['winner_table_session_uuid'] ??
                    result['table_session_uuid']) !=
                request.seatingUuid ||
            result['seating_key'] != request.payload['seating_key'] ||
            result['table_id'] != request.payload['table_id'] ||
            result['order_uuid'] != request.billUuid ||
            result['client_request_id'] != request.id ||
            result['kind'] != request.adjustment['kind'] ||
            result['mode'] != request.adjustment['mode'] ||
            result['grand_total_baisas'] is! int ||
            (result['grand_total_baisas'] as int) < 1) {
          throw const FormatException('Uncertain adjustment acknowledgement');
        }
        await store.remove(request);
        pending = null;
        notice = outcome == 'replayed' ? 'adjustment_replayed' : null;
        return true;
      }
      if (request.isCancellation) {
        final count = result['cancelled_qty'];
        if (!const {
              'cancelled',
              'replayed',
              'nothing_to_cancel',
              'bill_terminal',
            }.contains(outcome) ||
            (result['winner_table_session_uuid'] ??
                    result['table_session_uuid']) !=
                request.seatingUuid ||
            result['seating_key'] != request.payload['seating_key'] ||
            result['table_id'] != request.payload['table_id'] ||
            result['order_uuid'] != request.billUuid ||
            count is! int ||
            count < 0 ||
            count > (request.cancellation['qty'] as int) ||
            result['grand_total_baisas'] is! int) {
          throw const FormatException('Uncertain cancellation acknowledgement');
        }
        if (count > 0 && request.cancellation['prepared'] == true) {
          if (recordCancellationWaste == null) {
            throw StateError('Waste journal unavailable');
          }
          await recordCancellationWaste!(request, count);
        }
        await store.remove(request);
        pending = null;
        notice = count == request.cancellation['qty']
            ? ((result['waste'] as Map?)?['booked'] == true &&
                      (result['waste'] as Map?)?['cost_baisas'] is int
                  ? 'cancel_waste:${((result['waste']['cost_baisas'] as int) / 1000).toStringAsFixed(3)}'
                  : null)
            : 'changed';
        return count == request.cancellation['qty'];
      }
      if (fresh && const {'bill_terminal', 'bill_unpaid'}.contains(outcome)) {
        // These two business verdicts store no round. Only a NEW attempt may unlock.
        await store.remove(request);
        pending = null;
        notice = outcome as String;
        return false;
      }
      if (!const {
            'appended',
            'held',
            'merged',
            'replayed',
            'seating_created',
          }.contains(outcome) ||
          (result['winner_table_session_uuid'] ??
                  result['table_session_uuid']) !=
              request.seatingUuid ||
          result['seating_key'] != request.payload['seating_key'] ||
          result['table_id'] != request.payload['table_id'] ||
          result['order_uuid'] is! String ||
          (request.billUuid != null &&
              result['order_uuid'] != request.billUuid) ||
          result['round_id'] is! int ||
          (result['round_id'] as int) < 1 ||
          result['round_no'] is! int ||
          result['total_baisas'] is! int ||
          !const {
            'accepted',
            'pending_confirmation',
            'rejected',
          }.contains(result['round_status'])) {
        throw const FormatException('Uncertain round acknowledgement');
      }
      await store.remove(request);
      pending = null;
      notice = result['round_status'] == 'pending_confirmation'
          ? 'held'
          : 'added';
      if (result['round_status'] == 'accepted') {
        await _printAcceptedRound(request.tableId, result['round_id'] as int);
      }
      return true;
    } on QrQuickFailure catch (error) {
      if (request.isCancellation &&
          error.refused &&
          tableCancelRefusals.contains(error.code)) {
        await store.remove(request);
        pending = null;
        notice = 'cancel_refused:${error.code}';
        return false;
      }
      if (request.isAdjustment && error.refused) {
        await store.remove(request);
        pending = null;
        notice = 'adjust_refused:${error.code}';
        return false;
      }
      // LAUNCH-P5 F1 — the server did not accept the token this request
      // went with. It is kept (the server wrote nothing); a retry of
      // somebody else's saved request never signs this person out.
      notice = error.code == 'staff_unverified'
          ? 'staff_unverified'
          : 'uncertain';
      return false;
    } catch (_) {
      // Unknown errors, HTTP refusals and lost responses keep the immutable intent.
      // Never give a retry a new identity, even after navigation or restart.
      notice = 'uncertain';
      return false;
    }
  }

  Future<void> review(int roundId, bool accept) async {
    if (!available) return;
    final before = detail!;
    await _action(() async {
      final now = await gateway.detail(tableId);
      if (_localConflict(now) ||
          now.seatingUuid != before.seatingUuid ||
          now.billUuid != before.billUuid) {
        throw StateError('changed');
      }
      final round = now.rounds.where((r) => r['id'] == roundId).firstOrNull;
      if (round == null || round['status'] != 'pending_confirmation') return;
      await gateway.review(now, round, accept);
      if (accept) await _printAcceptedRound(tableId, roundId);
      if (accept &&
          round['entered_by'] == 'tablet' &&
          tabletPrintOff?.call() == true &&
          notice == null) {
        notice = 'tablet_print_off';
      }
    });
  }

  Future<void> clear() async {
    if (!available || detail?.canClearEmpty != true) return;
    final uuid = detail!.seatingUuid!;
    await _action(() => gateway.clear(tableId, seatingUuid: uuid));
  }

  Future<void> reopen() async {
    if (!available ||
        detail?.protectedCheckout != true ||
        detail?.billUuid == null) {
      return;
    }
    await _action(() => gateway.reopen(detail!.billUuid!));
  }

  Future<void> retryPrint(int roundId) async {
    if (!available || printAccepted == null) return;
    await _action(() => _printAcceptedRound(tableId, roundId));
  }

  Future<void> _printAcceptedRound(int selectedTableId, int roundId) async {
    if (printAccepted == null) return;
    try {
      final current = await gateway.detail(selectedTableId);
      final round = current.rounds
          .where((row) => row['id'] == roundId)
          .firstOrNull;
      if (round == null || current.billUuid == null) {
        notice = 'print_failed';
        return;
      }
      if (round['status'] != 'accepted' ||
          round['kitchen_printed_at'] != null) {
        return;
      }
      if (!await printAccepted!(current, round)) notice = 'print_failed';
    } catch (_) {
      notice = 'print_failed';
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    busy = true;
    _generation++;
    notice = null;
    _notify();
    try {
      await action();
    } on QrQuickFailure catch (error) {
      notice = error.message;
    } catch (_) {
      notice = 'refresh';
    } finally {
      busy = false;
      stale = true;
      _notify();
      await refresh();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// LAUNCH-P5 fix order 1 (F4) — the amount a table adjustment's approval
/// is signed over, exactly as the server derives it: a fixed discount's
/// own amount; a percent or percent-rule discount from the bill's
/// `adjustment_basis_baisas` (the server's base; the till never computes
/// it — absent from an older server = an empty amount); a fixed rule's
/// amount; nothing (empty) for every other adjustment. [rule] is a
/// merchant rule's `{type, value}` (percent, or OMR for a fixed rule).
int? tableAdjustProofAmount(
  DineInDetail detail,
  Map<String, dynamic> intent, {
  Map<dynamic, dynamic>? rule,
}) {
  if (intent['kind'] != 'discount') return null;
  switch (intent['mode']) {
    case 'fixed':
      final amount = intent['amount_baisas'];
      return amount is num ? amount.toInt() : null;
    case 'percent':
      final bp = intent['percent_bp'];
      final basis = detail.bill?['adjustment_basis_baisas'];
      if (bp is! num || basis is! num) return null;
      return (basis.toInt() * bp.toInt() / 10000).round();
    case 'rule':
      final value = rule?['value'];
      if (value is! num) return null;
      if (rule?['type'] != 'percent') return (value.toDouble() * 1000).round();
      final basis = detail.bill?['adjustment_basis_baisas'];
      if (basis is! num) return null;
      return (basis.toInt() * value.toDouble() / 100).round();
  }
  return null;
}
