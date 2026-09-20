import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'qr_checkout_models.dart';
import 'qr_checkout_store.dart';

abstract interface class CheckoutGateway {
  Future<void> preflight(String orderUuid);
  Future<CheckoutClaim> claim(String orderUuid);
  Future<Map<String, dynamic>> snapshot(String orderUuid);
  Future<void> release(
    String orderUuid,
    String outcome,
    List<Map<String, dynamic>> captures,
  );
  Future<List<Map<String, dynamic>>> push(Map<String, dynamic> event);
}

/// A structured refusal to acquire a NEW claim; never a blanket network error.
class CheckoutRefusal implements Exception {
  const CheckoutRefusal(this.code);
  final String code;
}

typedef CheckoutCaptureFn = Future<CheckoutCapture> Function(int baisas);

enum CheckoutPhase {
  loading,
  ready,
  busy,
  paid,
  released,
  pending,
  attention,
  empty,
}

/// No cart, pricing, order.create, stock mutation or payment retry API exists here.
/// All physical tenders are downstream of durable intent + same-holder replay.
class QrCheckoutController extends ChangeNotifier {
  QrCheckoutController({
    required this.gateway,
    required this.store,
    required this.captureCard,
    required this.captureBank,
    required this.authorizeGift,
    this.projectReceipt,
    DateTime Function()? now,
    String Function()? newId,
  }) : now = now ?? DateTime.now,
       newId = newId ?? checkoutUuid;
  final CheckoutGateway gateway;
  final CheckoutStore store;
  final CheckoutCaptureFn captureCard;
  final CheckoutCaptureFn captureBank;
  final Future<bool> Function() authorizeGift;
  final Future<void> Function(
    CheckoutSnapshot? snapshot,
    CheckoutAttempt attempt,
  )?
  projectReceipt;
  final DateTime Function() now;
  final String Function() newId;
  CheckoutAttempt? _attempt;
  CheckoutSnapshot? snapshot;
  CheckoutClaim? _claim;
  CheckoutPhase phase = CheckoutPhase.loading;
  String? notice;
  String cashInput = '';
  bool _busy = false;
  bool _disposed = false;
  CheckoutAttempt? get attempt => _attempt;
  bool get busy => _busy;
  bool get ready => phase == CheckoutPhase.ready && !_busy;
  bool get canLeave =>
      !_busy &&
      const [
        CheckoutPhase.paid,
        CheckoutPhase.released,
        CheckoutPhase.empty,
      ].contains(phase);
  String get reference =>
      snapshot?.reference ?? _attempt?.reference ?? _attempt?.orderUuid ?? '';
  int get total => _claim?.amount ?? (snapshot?.total ?? 0);
  int get cashBaisas => ((double.tryParse(cashInput) ?? 0) * 1000).round();
  int get changeBaisas => (cashBaisas - total).clamp(0, 999999999);
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void cashKey(String key) {
    if (!ready) return;
    if (key == 'back') {
      if (cashInput.isNotEmpty) {
        cashInput = cashInput.substring(0, cashInput.length - 1);
      }
    } else if (key == '.') {
      if (!cashInput.contains('.')) {
        cashInput = cashInput.isEmpty ? '0.' : '$cashInput.';
      }
    } else if (RegExp(r'^\d$').hasMatch(key)) {
      final parts = cashInput.split('.');
      if ((parts.length == 1 && parts.first.length < 6) ||
          (parts.length == 2 && parts.last.length < 3)) {
        cashInput += key;
      }
    }
    _changed();
  }

  void cashAmount(int baisas) {
    if (!ready || baisas < 0) return;
    cashInput = (baisas / 1000).toStringAsFixed(3);
    _changed();
  }

  Future<void> _save(CheckoutAttempt next) async {
    if (const {'refused', 'released', 'managed'}.contains(next.state)) {
      await projectReceipt?.call(snapshot, next);
    }
    await store.replace(_attempt!, next);
    _attempt = next;
  }

  Future<void> open(String? requestedUuid) async {
    if (_busy || _attempt != null) return;
    _busy = true;
    _changed();
    try {
      // Repair projections left by an older build or an interrupted transition.
      final journal = store;
      if (projectReceipt != null && journal is CheckoutReceiptJournal) {
        for (final ended
            in await (journal as CheckoutReceiptJournal)
                .endedWithoutReceipt()) {
          await projectReceipt!(null, ended);
        }
      }
      _attempt = await store.active();
      if (_attempt?.state == 'refused') {
        await projectReceipt?.call(null, _attempt!);
      }
      if (_attempt == null && requestedUuid == null) {
        phase = CheckoutPhase.empty;
        return;
      }
      final existing = _attempt;
      if (existing != null &&
          !const ['claiming', 'reserved'].contains(existing.state)) {
        phase = existing.state == 'pending'
            ? CheckoutPhase.pending
            : CheckoutPhase.attention;
        notice = existing.state == 'releasing' ? 'release_failed' : 'recovery';
        return;
      }
      final uuid = existing?.orderUuid ?? requestedUuid!;
      try {
        await gateway.preflight(uuid);
      } catch (_) {
        // No saved attempt and no claim request: closing this screen is safe.
        // Never strand an offline operator behind an online manager PIN here.
        if (existing == null) {
          phase = CheckoutPhase.empty;
          notice = 'unavailable';
          return;
        }
        rethrow;
      }
      if (existing == null) {
        final attempt = CheckoutAttempt(
          id: newId(),
          orderUuid: uuid,
          state: 'claiming',
          createdAt: now(),
          tenderMayHaveStarted: false,
          paymentContract: 'qr',
        );
        await store.create(attempt);
        _attempt = attempt;
      }
      final claim = await gateway.claim(uuid);
      if (claim.uuid != uuid) {
        throw const FormatException('Wrong claimed order');
      }
      final savedClaim = _attempt!.claim;
      // A replay with no saved reservation could predate this app/attempt.
      // Never infer "no previous card tap" from a missing local payment row.
      if (savedClaim == null && claim.replay) {
        await _save(_attempt!.copy(state: 'uncertain'));
        phase = CheckoutPhase.attention;
        notice = 'recovery';
        return;
      }
      if (savedClaim != null &&
          (!claim.replay ||
              !claim.sameReservation(CheckoutClaim(savedClaim)))) {
        await _save(_attempt!.copy(state: 'uncertain'));
        phase = CheckoutPhase.attention;
        notice = 'claim_changed';
        return;
      }
      _claim = claim;
      await _save(_attempt!.copy(state: 'reserved', claim: claim.json));
      snapshot = CheckoutSnapshot(await gateway.snapshot(uuid), claim);
      await _save(
        _attempt!.copy(orderId: snapshot!.id, reference: snapshot!.reference),
      );
      if (!claim.deadline.isAfter(now().add(const Duration(seconds: 5)))) {
        await _releaseBeforeTender('claim_changed');
      } else {
        phase = CheckoutPhase.ready;
      }
    } on CheckoutRefusal catch (error) {
      notice = error.code;
      if (_attempt != null &&
          _attempt!.claim == null &&
          _attempt!.state == 'claiming') {
        await _save(_attempt!.copy(state: 'released'));
        phase = CheckoutPhase.released;
      } else if (_claim != null) {
        await _releaseBeforeTender(error.code);
      } else {
        phase = CheckoutPhase.attention;
      }
    } catch (_) {
      if (_claim != null && _attempt?.state == 'reserved') {
        await _releaseBeforeTender('unavailable');
      } else {
        phase = CheckoutPhase.attention;
        notice = 'recovery';
      }
    } finally {
      _busy = false;
      _changed();
    }
  }

  Future<void> _releaseBeforeTender(String reason) async {
    notice = reason;
    try {
      await _save(_attempt!.copy(state: 'releasing'));
      await gateway.release(_attempt!.orderUuid, 'cancelled', const []);
      await _save(_attempt!.copy(state: 'released'));
      phase = CheckoutPhase.released;
    } catch (_) {
      phase = CheckoutPhase.attention;
      notice = 'release_failed';
    }
  }

  Future<void> cancel() async {
    if (_busy ||
        !const [CheckoutPhase.ready, CheckoutPhase.attention].contains(phase)) {
      return;
    }
    if (_attempt == null) return;
    if (!const ['reserved', 'releasing'].contains(_attempt!.state)) return;
    _busy = true;
    _changed();
    try {
      await _releaseBeforeTender('cancelled');
    } finally {
      _busy = false;
      _changed();
    }
  }

  Future<bool> _revalidate() async {
    final claim = _claim!;
    if (!claim.deadline.isAfter(now().add(const Duration(seconds: 5)))) {
      return false;
    }
    final replay = await gateway.claim(claim.uuid);
    return replay.replay &&
        claim.sameReservation(replay) &&
        replay.deadline.isAfter(now().add(const Duration(seconds: 5)));
  }

  Future<void> pay(List<CheckoutTender> input) async {
    if (!ready || snapshot == null || _claim == null) return;
    final plan = List<CheckoutTender>.unmodifiable(input);
    validateCheckoutPlan(plan, total);
    _busy = true;
    phase = CheckoutPhase.busy;
    _changed();
    try {
      if (plan.singleOrNull?.method == 'gift' && !await authorizeGift()) {
        phase = CheckoutPhase.ready;
        notice = 'manager_denied';
        return;
      }
      try {
        if (!await _revalidate()) {
          await _releaseBeforeTender('claim_changed');
          return;
        }
      } catch (_) {
        await _releaseBeforeTender('claim_changed');
        return;
      }
      // The durable marker MUST precede any physical tender, including a
      // manual bank terminal. A crash from here blocks another tender.
      await _save(
        _attempt!.copy(state: 'capturing', tenderMayHaveStarted: true),
      );
      final tenders = <Map<String, dynamic>>[];
      // Irreversible integrated card legs last; every successful leg is saved.
      final ordered = [
        ...plan.where((v) => v.method != 'card'),
        ...plan.where((v) => v.method == 'card'),
      ];
      for (final leg in ordered) {
        if (leg.method == 'card' || leg.method == 'bank_pos') {
          try {
            if (!await _revalidate()) {
              await _captureStopped('claim_changed', tenders);
              return;
            }
          } catch (_) {
            await _captureStopped('claim_changed', tenders);
            return;
          }
          final CheckoutCapture capture;
          try {
            capture = await (leg.method == 'card' ? captureCard : captureBank)(
              leg.amount,
            );
          } catch (_) {
            await _uncertain();
            return;
          }
          if (capture.state == CheckoutCaptureState.uncertain) {
            await _save(
              _attempt!.copy(
                captures: [
                  ..._attempt!.captures,
                  {...leg.json, ...capture.evidence, 'capture_uncertain': true},
                ],
              ),
            );
            await _uncertain();
            return;
          }
          if (capture.state != CheckoutCaptureState.approved) {
            final terminalBusy =
                const {
                  CheckoutCaptureState.notDispatched,
                  CheckoutCaptureState.cancelled,
                }.contains(capture.state) &&
                capture.evidence['bank_response'] is Map &&
                checkoutMap(
                      capture.evidence['bank_response'],
                    )['code']?.toString().toUpperCase() ==
                    'BUSY';
            await _captureStopped(
              terminalBusy ? 'terminal_busy' : 'cancelled',
              tenders,
            );
            return;
          }
          final tender = {
            ...leg.json,
            if (leg.method == 'card') ...capture.evidence,
          };
          // Adapters may supply evidence, never payment method/amount/status.
          tender.addAll(leg.json);
          tenders.add(tender);
        } else {
          tenders.add(leg.json);
        }
        await _save(_attempt!.copy(captures: List.from(tenders)));
      }
      final timestamp = now().toUtc().toIso8601String();
      final event = <String, dynamic>{
        'client_event_id': _attempt!.id,
        'event_type': 'order.pay',
        'client_timestamp': timestamp,
        'payload': {
          'order_uuid': _attempt!.orderUuid,
          'paid_at': timestamp,
          'payments': tenders,
        },
      };
      await _save(_attempt!.copy(state: 'pending', event: event));
      await _push();
    } catch (_) {
      // Includes storage failure after capture: its prior durable marker stays
      // unresolved. Do not release as cancelled, re-tender or invent a receipt.
      phase = CheckoutPhase.attention;
      notice = 'recovery';
    } finally {
      _busy = false;
      _changed();
    }
  }

  /// The normal staff table checkout retains payAndPrint + the real table
  /// outbox. Reservation and crash evidence still use this checkout journal.
  Future<CheckoutSnapshot?> beginTableTender() async {
    if (!ready || snapshot == null || _claim == null) return null;
    _busy = true;
    try {
      if (!await _revalidate()) {
        await _releaseBeforeTender('claim_changed');
        return null;
      }
      await _save(
        _attempt!.copy(state: 'capturing', tenderMayHaveStarted: true),
      );
      phase = CheckoutPhase.busy;
      return snapshot;
    } catch (_) {
      phase = CheckoutPhase.attention;
      notice = 'recovery';
      return null;
    } finally {
      _busy = false;
      _changed();
    }
  }

  /// Runs in the table outbox's beforeFlush hook. The one immutable pay event
  /// is recoverable through Check payment result even if the process stops.
  Future<Map<String, dynamic>> journalTablePay(
    Map<String, dynamic> event,
  ) async {
    final attempt = _attempt;
    if (attempt == null || attempt.state != 'capturing' || _claim == null) {
      throw StateError('Check payment result before another table payment.');
    }
    final payload = checkoutMap(event['payload']);
    final payments = (payload['payments'] as List).map(checkoutMap).toList();
    if (event['event_type'] != 'order.pay' ||
        payload['order_uuid'] != attempt.orderUuid ||
        payments.fold<int>(
              0,
              (sum, row) => sum + (row['amount_baisas'] as int),
            ) !=
            _claim!.amount) {
      throw const FormatException(
        'Table payment differs from the reserved bill',
      );
    }
    if (event['client_event_id'] != attempt.id) {
      throw const FormatException('Table payment identity changed');
    }
    final frozen = Map<String, dynamic>.from(event);
    await _save(
      attempt.copy(
        state: 'pending',
        captures: payments,
        event: frozen,
        paymentContract: 'table',
      ),
    );
    phase = CheckoutPhase.pending;
    _changed();
    return frozen;
  }

  /// A real table-outbox ACK can finish the same journal after restart. It
  /// cannot confirm any other event, total, bill, or payment status.
  Future<void> acceptTablePayAck(
    Map<String, dynamic> event,
    Map<String, dynamic> ack,
  ) async {
    final saved = await store.active();
    // Unrelated ACKs are not evidence for this attempt and must not decode
    // their payload through its frozen claim (which could throw).
    if (saved == null ||
        saved.state != 'pending' ||
        saved.event == null ||
        event['client_event_id'] != saved.id ||
        (event['payload'] is Map &&
            (event['payload'] as Map)['order_uuid'] != saved.orderUuid)) {
      return;
    }
    if (ack['client_event_id'] != saved.id ||
        !_sameTablePayment(saved, event)) {
      throw const FormatException('Check payment result: unmatched table ACK');
    }
    _attempt = saved;
    final result = checkoutMap(ack['result']);
    if (ack['status'] != 'processed' ||
        result['status'] != 'paid' ||
        result['order_id'] != saved.orderId ||
        result['receipt_number'] is! String ||
        (result['receipt_number'] as String).trim().isEmpty ||
        result['orphan_tender'] == true) {
      throw const FormatException(
        'Check payment result: payment proof missing',
      );
    }
    await _acceptPaymentAck(ack);
    if (_attempt?.state != 'paid') {
      throw StateError('Check payment result: table payment remains pending');
    }
    _changed();
  }

  bool _sameTablePayment(CheckoutAttempt saved, Map<String, dynamic> event) {
    // Validate both immutable journal and flushed event. GPS is transport
    // evidence, never payment identity; every retry may obtain a fresh fix.
    CheckoutAttempt.decode(jsonEncode(saved.json));
    CheckoutAttempt.decode(jsonEncode(saved.copy(event: event).json));
    final original = checkoutMap(saved.event!['payload']);
    final incoming = checkoutMap(event['payload']);
    return event['event_type'] == 'order.pay' &&
        original['order_uuid'] == incoming['order_uuid'] &&
        original['paid_at'] == incoming['paid_at'] &&
        jsonEncode(original['payments']) == jsonEncode(incoming['payments']);
  }

  Future<void> _captureStopped(
    String reason,
    List<Map<String, dynamic>> collected,
  ) async {
    if (collected.any(
      (v) => const ['card', 'bank_pos'].contains(v['method']),
    )) {
      await _uncertain();
    } else {
      await _releaseBeforeTender(
        collected.any((v) => v['method'] == 'cash') ? 'return_cash' : reason,
      );
    }
  }

  Future<void> _uncertain() async {
    await _save(_attempt!.copy(state: 'uncertain'));
    phase = CheckoutPhase.attention;
    notice = 'recovery';
    try {
      await gateway.release(
        _attempt!.orderUuid,
        'uncertain',
        _attempt!.captures,
      );
    } catch (_) {
      notice = 'release_failed';
    }
  }

  Future<void> _push() async {
    phase = CheckoutPhase.pending;
    try {
      await projectReceipt?.call(snapshot, _attempt!);
      final responses = await gateway.push(_attempt!.event!);
      if (responses.length != 1 ||
          responses.single['client_event_id'] != _attempt!.id) {
        return;
      }
      await _acceptPaymentAck(responses.single);
    } catch (_) {
      // No authoritative ACK, even when the transport throws an HTTP error.
      // Keep the SAME immutable event. Retry is a status replay, never a tender.
      phase = CheckoutPhase.pending;
    }
  }

  Future<void> _acceptPaymentAck(Map<String, dynamic> ack) async {
    if (ack['status'] == 'processed') {
      final result = checkoutMap(ack['result']);
      if (result['status'] != 'paid' ||
          result['order_id'] != _attempt!.orderId ||
          result['orphan_tender'] == true) {
        return;
      }
      final confirmed = _attempt!.copy(
        state: 'paid',
        receiptNumber: result['receipt_number'] as String?,
      );
      // Persist the official display/history before making the journal
      // terminal. A failed projection retries the same payment event.
      await projectReceipt?.call(snapshot, confirmed);
      await _save(confirmed);
      phase = CheckoutPhase.paid;
      notice = null;
    } else if (ack['status'] == 'failed') {
      await _save(_attempt!.copy(state: 'refused'));
      phase = CheckoutPhase.attention;
      final external = _attempt!.captures.any(
        (v) => const ['card', 'bank_pos'].contains(v['method']),
      );
      notice = external ? 'recovery' : 'return_cash';
      try {
        await gateway.release(
          _attempt!.orderUuid,
          external ? 'uncertain' : 'cancelled',
          _attempt!.captures,
        );
      } catch (_) {
        notice = 'release_failed';
      }
    }
  }

  Future<void> retryAcknowledgement() async {
    if (_busy || _attempt?.state != 'pending') return;
    _busy = true;
    _changed();
    try {
      await _push();
    } finally {
      _busy = false;
      _changed();
    }
  }

  /// Manager takeover allows route exit, not payment success or claim clearing.
  /// Pending events remain active and retryable; they must never be discarded.
  Future<bool> managerTakeover(Future<bool> Function() authorize) async {
    if (_busy ||
        !const [
          CheckoutPhase.attention,
          CheckoutPhase.pending,
        ].contains(phase)) {
      return false;
    }
    _busy = true;
    _changed();
    try {
      if (!await authorize()) return false;
      if (_attempt?.state == 'capturing') {
        await _uncertain();
      }
      if (_attempt != null &&
          (const ['uncertain', 'refused'].contains(_attempt!.state) ||
              (_attempt!.state == 'releasing' && _attempt!.event == null))) {
        // A failed release must not trap every other bill on this device.
        // Retain the exact claim/capture evidence for manager review. This is
        // NOT a release or payment resolution on the server. Never retire an
        // immutable pay event merely because a release could not complete.
        await _save(_attempt!.copy(state: 'managed'));
      }
      return true;
    } catch (_) {
      notice = 'handover_failed';
      return false;
    } finally {
      _busy = false;
      _changed();
    }
  }
}
