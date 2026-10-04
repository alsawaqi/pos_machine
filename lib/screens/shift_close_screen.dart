import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/manager_auth.dart';
import '../data/db/app_database.dart' show OrderOutboxRow;
import '../data/order_sync_repository.dart';
import '../qr_checkout/checkout_close_hold.dart';
import '../qr_checkout/qr_checkout_controller.dart';
import '../qr_checkout/qr_checkout_gateway.dart';
import '../qr_checkout/qr_checkout_models.dart';
import '../qr_checkout/qr_checkout_receipt.dart';
import '../qr_checkout/qr_checkout_store.dart';
import '../qr_quick/qr_quick_gateway.dart' show quickDeviceScope;
import '../services/server_receipt_history.dart';
import '../l10n/l10n.dart';
import '../services/api_models.dart';
import '../services/pos_api_service.dart';
import '../services/session_service.dart' show OpenShiftData;
import '../providers/providers.dart';
import '../services/local_order_storage_service.dart';
import '../services/shift_payload.dart';
import '../services/shift_service.dart';
import '../services/shift_summary.dart';
import '../services/sunmi_receipt_service.dart';
import 'shift_close_preflight.dart';

/// Close the device's open cash-drawer shift: the cashier counts the drawer,
/// the server computes expected cash (opening + cash sales on this device) and
/// the variance, then the result is shown and the shift cleared. Pushed over
/// the POS; on Done the gate returns to the open-shift screen.
class ShiftCloseScreen extends ConsumerStatefulWidget {
  const ShiftCloseScreen({super.key, this.forcedHandover = false});

  /// A newly logged-in cashier found another staff member's drawer cached on
  /// this device. They must settle it before the startup gate offers a new
  /// opening float; there is no cancel path into sales.
  final bool forcedHandover;

  @override
  ConsumerState<ShiftCloseScreen> createState() => _ShiftCloseScreenState();
}

class _ShiftCloseScreenState extends ConsumerState<ShiftCloseScreen> {
  int _closingBaisas = 0;
  bool _busy = false;
  String? _error;
  ShiftCloseResult? _result;
  bool _forcedPreflightComplete = false;
  // LAUNCH-P5 C5 — paid sales still sending (they block the close), the
  // server's missing list, the close_other gate, and a count already sent.
  List<OrderOutboxRow> _unsent = const [];
  List<String> _missing = const [];
  // LAUNCH-P5 fix order 1 (F7) — this shift's drawer pay-outs still
  // sending (amounts in baisas); they block the close like sales.
  List<int> _payouts = const [];
  // LAUNCH-P5 fix order 2 (T4) — QR / workspace payments of this shift not
  // yet acknowledged (from the checkout journal); (T5) sales parked after
  // server errors, offered a Retry instead of "still sending".
  List<CheckoutAttempt> _checkoutUnsent = const [];
  List<OrderOutboxRow> _parked = const [];
  ActionAuthorization? _closeOther;
  // LAUNCH-P5 C6 — clock out with the close (default yes).
  bool _clockOutToo = true;

  static String _money(int baisas) {
    final omr = baisas / 1000;
    final sign = baisas < 0 ? '-' : '';
    return '$sign${omr.abs().toStringAsFixed(3)}';
  }

  void _tap(String digit) {
    if (_busy) return;
    final next = _closingBaisas * 10 + int.parse(digit);
    if (next > 9999999999) return;
    setState(() {
      _closingBaisas = next;
      _error = null;
    });
  }

  void _backspace() {
    if (_busy || _closingBaisas == 0) return;
    setState(() => _closingBaisas ~/= 10);
  }

  ShiftSummaryTicket? _ticket;
  // Phase G4 — the auto/manual summary print failed (real hardware only).
  bool _printFailed = false;

  /// LAUNCH-P5 C5 — the shift's re-open count, read fresh from the server
  /// right before the close (it is part of the fixed close id). Absent on
  /// an older server = 0.
  ///
  /// LAUNCH-P5 fix order 1 — the read carries the closer's staff token, and
  /// the server refuses a `staff_id` the token does not name: another
  /// cashier's drawer is looked up by this device only.
  Future<int> _freshReopenCount(OpenShiftData shift) async {
    final api = ref.read(apiServiceProvider);
    final closer = ref.read(sessionServiceProvider).staff?.id;
    for (final lookup in [
      if (closer != null && closer == shift.staffId)
        () => api.fetchCurrentShift(staffId: closer, sharedStaffOnly: true),
      () => api.fetchCurrentShift(),
    ]) {
      try {
        final current = await lookup();
        if (current?.uuid == shift.uuid) return current!.reopenCount;
      } on ApiException catch (e) {
        // Offline: closing needs the internet. A refused staff token has
        // already signed the person out: stop.
        if (e.isNetwork || e.isStaffUnverified) rethrow;
      } catch (_) {
        // A malformed reply: try the next lookup, then the cached count.
      }
    }
    return shift.reopenCount;
  }

  /// Flush the outbox and push this device's pending QR / workspace
  /// payment, then list this shift's paid sales, checkout payments and
  /// drawer pay-outs still unsent, and the parked sales.
  Future<_CloseCheck> _flushAndCheck(OpenShiftData shift) async {
    final outbox = ref.read(orderSyncRepositoryProvider);
    try {
      await outbox.flush();
    } catch (_) {
      // Still unsent rows are listed below.
    }
    CheckoutCloseHold? checkout;
    try {
      checkout = await ref.read(checkoutCloseHoldProvider)();
      await checkout?.flush();
    } catch (_) {
      checkout = null;
    }
    final sales = await outbox.paidSalesSince(shift.openedAt);
    final payouts = await outbox.unsentPayouts(shift.uuid);
    ({List<CheckoutAttempt> unsent, List<String> orderUuids})? checkouts;
    try {
      checkouts = await checkout?.since(shift.openedAt);
    } catch (_) {
      checkouts = null;
    }
    return _CloseCheck(
      unsent: sales.unsent,
      parked: sales.parked,
      checkoutUnsent: checkouts?.unsent ?? const [],
      orderUuids: [
        ...sales.orderUuids,
        for (final uuid in checkouts?.orderUuids ?? const <String>[])
          if (!sales.orderUuids.contains(uuid)) uuid,
      ],
      payouts: [for (final p in payouts) p.amountBaisas],
    );
  }

  /// Show what blocks the close; true when something does.
  bool _showBlocked(_CloseCheck check) {
    if (!check.blocks) return false;
    setState(() {
      _unsent = check.unsent;
      _checkoutUnsent = check.checkoutUnsent;
      _payouts = check.payouts;
    });
    return true;
  }

  /// LAUNCH-P5 fix order 2 (T5) — Retry the parked sales: un-park them,
  /// send them, then close again.
  Future<void> _retryParked() async {
    final uuids = {
      for (final row in _parked) ...OrderSyncRepository.paidOrderUuids(row),
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(orderSyncRepositoryProvider).unparkAndPush(uuids);
    } catch (_) {
      // The close below lists what is still missing.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _close();
  }

  Future<void> _close() async {
    final l10n = L10n.of(context);
    final shift = ref.read(sessionControllerProvider).openShift;
    if (shift == null) {
      setState(() => _error = l10n.shiftCloseNoOpenShift);
      return;
    }
    final staff = ref.read(sessionServiceProvider).staff;
    setState(() {
      _busy = true;
      _error = null;
      _unsent = const [];
      _missing = const [];
      _payouts = const [];
      _checkoutUnsent = const [];
      _parked = const [];
    });
    try {
      if (widget.forcedHandover && !_forcedPreflightComplete) {
        await runShiftClosePreflight(context, ref);
        if (!mounted) return;
        _forcedPreflightComplete = true;
      }
      // LAUNCH-P5 C5 — closing needs the server.
      if (ref.read(connectivityProvider).asData?.value == false) {
        setState(() => _error = l10n.shiftCloseNeedsInternet);
        return;
      }
      Map<String, dynamic>? authorization;
      // Closing another cashier's drawer: the shift.close_other tick, or an
      // approver's PIN.
      if (staff != null && shift.staffId != staff.id) {
        _closeOther ??= await authorizeAction(
          context,
          ref,
          action: 'shift.close_other',
          subtitle: l10n.shiftCloseOtherApproval,
        );
        if (!mounted) return;
        final gate = _closeOther;
        if (gate == null) {
          setState(() => _error = l10n.approvalNotGiven);
          return;
        }
        authorization = gate.block(subjectUuid: shift.uuid);
      }
      // Flush first; every paid sale of this shift must have reached the
      // server before the drawer can close (owner decision 3).
      final sales = await _flushAndCheck(shift);
      if (!mounted || _showBlocked(sales)) return;
      var reopenCount = await _freshReopenCount(shift);
      if (!mounted) return;
      final counted = _closingBaisas;
      Map<String, dynamic> event(List<String> orderUuids) =>
          buildShiftCloseEvent(
            shiftUuid: shift.uuid,
            closingCashBaisas: counted,
            closedByStaffId: staff?.id,
            orderUuids: orderUuids,
            authorization: authorization,
            reopenCount: reopenCount,
          );
      Future<ShiftCloseResult> push(Map<String, dynamic> close) => ref
          .read(shiftServiceProvider)
          .close(
            shiftUuid: shift.uuid,
            closingCashBaisas: counted,
            event: close,
          );
      // LAUNCH-P5 fix order 1 (L8) — `shift_reopened`: the portal
      // re-opened the shift since the count was read. Rebuild the fixed id
      // with the server's count and send once more.
      Future<ShiftCloseResult> send(List<String> orderUuids) async {
        try {
          return await push(event(orderUuids));
        } on ShiftReopenedException catch (e) {
          if (e.reopenCount == reopenCount) rethrow;
          reopenCount = e.reopenCount;
          return push(event(orderUuids));
        }
      }

      ShiftCloseResult result;
      try {
        result = await send(sales.orderUuids);
      } on ShiftUnsyncedSalesException catch (first) {
        // The server is still missing a sale. LAUNCH-P5 fix order 2 (T5) —
        // un-park and push the rows it names, flush again and retry once
        // (the same fixed id; the server takes the new payload).
        final outbox = ref.read(orderSyncRepositoryProvider);
        try {
          await outbox.unparkAndPush(first.missing);
        } catch (_) {}
        final again = await _flushAndCheck(shift);
        if (!mounted || _showBlocked(again)) return;
        try {
          result = await send(again.orderUuids);
        } on ShiftUnsyncedSalesException catch (e) {
          // Still missing: a parked sale is "parked — Retry", never
          // "still sending".
          final latest = await outbox.paidSalesSince(shift.openedAt);
          final parked = [
            for (final row in latest.parked)
              if (OrderSyncRepository.paidOrderUuids(
                row,
              ).any(e.missing.contains))
                row,
          ];
          final parkedUuids = {
            for (final row in parked)
              ...OrderSyncRepository.paidOrderUuids(row),
          };
          if (mounted) {
            setState(() {
              _parked = parked;
              _missing = [
                for (final uuid in e.missing)
                  if (!parkedUuids.contains(uuid)) uuid,
              ];
            });
          }
          return;
        }
      }
      _closeOther?.grant?.forget();
      _closeOther = null;
      // Phase C6 — assemble the Z-report: server numbers when present (same
      // transaction as the close), the device-local fold as the fallback.
      final closedAt = DateTime.now();
      var summary = ShiftSalesSummary.fromServerResult(result.summaryJson);
      if (summary == null) {
        final localHistory =
            await LocalOrderStorageService.instance.loadOrderHistory();
        summary = buildLocalShiftSummary(
          localHistory,
          openedAt: shift.openedAt,
          closedAt: closedAt,
        );
      }
      final session = ref.read(sessionServiceProvider);
      final ticketStaffName = session.staff?.id == shift.staffId
          ? session.staff?.name ?? ''
          : l10n.shiftHandoverOwner(shift.staffId);
      final ticket = ShiftSummaryTicket(
        deviceCode: session.kioskId ?? '',
        staffName: ticketStaffName,
        openedAt: shift.openedAt,
        closedAt: closedAt,
        openingBaisas: shift.openingCashBaisas,
        expectedBaisas: result.expectedCashBaisas,
        countedBaisas: counted,
        varianceBaisas: result.varianceBaisas,
        summary: summary,
      );
      // Persist the reprint snapshot BEFORE markShiftClosed erases the
      // device's only record of the shift window.
      await session.saveLastShiftSummary(ticket.toJson());
      if (ref.read(settingsControllerProvider).printReceipts) {
        // Auto-print once; fail-safe inside the service. Phase G4 — a
        // failure flips the inline banner on the result step (the close
        // itself already settled server-side).
        unawaited(SunmiReceiptService.printShiftSummary(ticket).then((ok) {
          if (!ok && mounted && SunmiReceiptService.printerPluginAvailable) {
            setState(() => _printFailed = true);
          }
        }));
      }
      // LAUNCH-P5 C6 — clock out with the close (default yes) when the
      // person closes their own shift.
      if (_clockOutToo &&
          staff != null &&
          shift.staffId == staff.id &&
          staff.attendance?.open == true) {
        try {
          await ref
              .read(attendanceServiceProvider)
              .clockOut(staff.id, attendanceUuid: staff.attendance?.uuid);
          await ref
              .read(sessionControllerProvider.notifier)
              .updateAttendance(const StaffAttendance(open: false));
        } catch (_) {
          // The close stands; the clock-out can be done from the PIN screen.
        }
      }
      if (mounted) {
        setState(() {
          _result = result;
          _closingBaisas = counted;
          _ticket = ticket;
        });
      }
    } on ShiftException catch (e) {
      // HH-2 — a shared shift can be closed from the OTHER terminal (the
      // handheld). This device's local record is then stale: heal by
      // marking it closed instead of dead-ending the till on an error it
      // can never resolve ("shift already closed" forever).
      if (e.message.toLowerCase().contains('already closed')) {
        await ref.read(sessionControllerProvider.notifier).markShiftClosed();
        if (mounted && !widget.forcedHandover) Navigator.of(context).pop();
        return;
      }
      if (mounted) setState(() => _error = e.message);
    } on ShiftReopenedException {
      // Re-opened again while closing: read the count afresh next time.
      if (mounted) setState(() => _error = l10n.shiftCloseReopenedRetry);
    } on ShiftApprovalRefusedException {
      // The server did not accept the close_other approval: ask again.
      _closeOther?.grant?.forget();
      _closeOther = null;
      if (mounted) setState(() => _error = l10n.approvalNotGiven);
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.isNetwork ? l10n.shiftCloseNeedsInternet : e.message,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = l10n.shiftCloseFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _done() async {
    await ref.read(sessionControllerProvider.notifier).markShiftClosed();
    if (mounted && !widget.forcedHandover) Navigator.of(context).pop();
  }

  Future<void> _switchStaff() async {
    if (_busy) return;
    await ref.read(sessionControllerProvider.notifier).logoutStaff();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final shift = ref.watch(sessionControllerProvider).openShift;
    // LAUNCH-P5 C5 — keep the online state current for the close check.
    ref.watch(connectivityProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF102028),
      appBar: AppBar(
        backgroundColor: const Color(0xFF102028),
        foregroundColor: Colors.white,
        title: Text(l10n.shiftCloseTitle),
        leading: _result == null && !widget.forcedHandover
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              )
            : null,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _result == null
                ? _buildCountStep(shift?.openingCashBaisas ?? 0)
                : _buildResultStep(_result!),
          ),
        ),
      ),
    );
  }

  Widget _buildCountStep(int openingBaisas) {
    final l10n = L10n.of(context);
    final shift = ref.read(sessionControllerProvider).openShift;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.forcedHandover && shift != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0x33E0A93B),
              border: Border.all(color: const Color(0xFFE0A93B)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              l10n.shiftHandoverWarning(shift.staffId),
              style: const TextStyle(color: Colors.white, height: 1.35),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _switchStaff,
              icon: const Icon(Icons.switch_account_rounded),
              label: Text(l10n.shiftHandoverSwitchStaff),
            ),
          ),
          const SizedBox(height: 18),
        ],
        _amountCard(l10n.shiftCloseOpeningFloatLabel, _money(openingBaisas),
            muted: true),
        const SizedBox(height: 12),
        _amountCard(l10n.shiftCloseCountedDrawerCashLabel, _money(_closingBaisas)),
        if (_unsent.isNotEmpty ||
            _missing.isNotEmpty ||
            _payouts.isNotEmpty ||
            _checkoutUnsent.isNotEmpty ||
            _parked.isNotEmpty) ...[
          const SizedBox(height: 14),
          _blockedCard(l10n),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 14),
          ),
        ],
        if (_ownShift) ...[
          const SizedBox(height: 10),
          CheckboxListTile(
            key: const ValueKey('shift-close-clock-out'),
            value: _clockOutToo,
            onChanged: _busy
                ? null
                : (v) => setState(() => _clockOutToo = v ?? true),
            title: Text(
              l10n.shiftCloseClockOutToo,
              style: const TextStyle(color: Colors.white),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ],
        const SizedBox(height: 18),
        _keypad(),
        const SizedBox(height: 18),
        SizedBox(
          width: 260,
          height: 52,
          child: FilledButton(
            onPressed: _busy ? null : _close,
            child: _busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.shiftCloseSubmitButton),
          ),
        ),
      ],
    );
  }

  /// The logged-in person closes their own shift and is clocked in.
  bool get _ownShift {
    final staff = ref.read(sessionServiceProvider).staff;
    final shift = ref.read(sessionControllerProvider).openShift;
    return staff != null &&
        shift != null &&
        shift.staffId == staff.id &&
        staff.attendance?.open == true;
  }

  /// "3 sales still sending" (or the server's own list) with a retry.
  Widget _blockedCard(L10n l10n) {
    final lines = [
      for (final row in _unsent)
        l10n.shiftCloseSendingSale(
          (row.orderNumber ?? 0) > 0
              ? '#${row.orderNumber}'
              : row.orderUuid.split(':').first,
        ),
      // LAUNCH-P5 fix order 2 (T4) — QR / workspace payments.
      for (final attempt in _checkoutUnsent)
        l10n.shiftCloseSendingQrSale(
          (attempt.reference ?? '').isNotEmpty
              ? attempt.reference!
              : attempt.orderUuid,
        ),
      if (_unsent.isEmpty && _checkoutUnsent.isEmpty)
        for (final uuid in _missing) l10n.shiftCloseSendingSale(uuid),
    ];
    final count = lines.length;
    final parked = [
      for (final row in _parked)
        l10n.shiftCloseParkedSale(
          (row.orderNumber ?? 0) > 0
              ? '#${row.orderNumber}'
              : row.orderUuid.split(':').first,
        ),
    ];
    final payouts = [
      for (final amount in _payouts)
        l10n.shiftCloseSendingPayout(_money(amount)),
    ];
    return Container(
      key: const ValueKey('shift-close-blocked'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x33E0A93B),
        border: Border.all(color: const Color(0xFFE0A93B)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (count > 0) ...[
            Text(
              l10n.shiftCloseSalesSending(count),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            for (final line in lines.take(8))
              Text(line, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
          ],
          // LAUNCH-P5 fix order 2 (T5) — parked, with a Retry.
          if (parked.isNotEmpty) ...[
            Text(
              l10n.shiftCloseSalesParked(parked.length),
              key: const ValueKey('shift-close-parked'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            for (final line in parked.take(8))
              Text(line, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            Text(
              l10n.shiftCloseParkedHint,
              style: const TextStyle(color: Colors.white60, fontSize: 12.5),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              key: const ValueKey('shift-close-retry-parked'),
              onPressed: _busy ? null : _retryParked,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.shiftCloseRetryParked),
            ),
            const SizedBox(height: 8),
          ],
          if (payouts.isNotEmpty) ...[
            Text(
              l10n.shiftClosePayoutsSending(payouts.length),
              key: const ValueKey('shift-close-blocked-payouts'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            for (final line in payouts.take(8))
              Text(line, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
          ],
          if (count > 0 || payouts.isNotEmpty)
            Text(
              count > 0
                  ? l10n.shiftCloseSalesSendingHint
                  : l10n.shiftClosePayoutsSendingHint,
              style: const TextStyle(color: Colors.white60, fontSize: 12.5),
            ),
        ],
      ),
    );
  }

  Widget _buildResultStep(ShiftCloseResult result) {
    final l10n = L10n.of(context);
    final variance = result.varianceBaisas;
    final (label, color) = variance == 0
        ? (l10n.shiftCloseDrawerBalanced, const Color(0xFF35C28B))
        : variance < 0
            ? (l10n.shiftCloseDrawerShort, const Color(0xFFFF6B6B))
            : (l10n.shiftCloseDrawerOver, const Color(0xFFE0A93B));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          variance == 0 ? Icons.check_circle_rounded : Icons.info_rounded,
          color: color,
          size: 56,
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 20),
        _resultRow(l10n.shiftCloseExpectedCash, _money(result.expectedCashBaisas)),
        _resultRow(l10n.shiftCloseCountedCash, _money(_closingBaisas)),
        const Divider(color: Colors.white24, height: 28),
        _resultRow(l10n.shiftCloseVariance, _money(variance), color: color, bold: true),
        const SizedBox(height: 24),
        if (_printFailed) ...[
          Text(
            l10n.shiftClosePrintFailed,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFE0A93B), fontSize: 13),
          ),
          const SizedBox(height: 10),
        ],
        if (_ticket != null) ...[
          SizedBox(
            width: 260,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () async {
                final ok =
                    await SunmiReceiptService.printShiftSummary(_ticket!);
                if (mounted) {
                  setState(() => _printFailed =
                      !ok && SunmiReceiptService.printerPluginAvailable);
                }
              },
              icon: const Icon(Icons.print_outlined, color: Colors.white70),
              label: Text(
                l10n.shiftClosePrintSummary,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: 260,
          height: 52,
          child: FilledButton(
            onPressed: _done,
            child: Text(l10n.commonDone),
          ),
        ),
      ],
    );
  }

  Widget _amountCard(String label, String value, {bool muted = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF16313B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: muted ? Colors.white70 : Colors.white,
              fontSize: muted ? 24 : 32,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value,
      {Color color = Colors.white, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 15)),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: bold ? 20 : 16,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _keypad() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '00', '0', '<'];
    return SizedBox(
      width: 300,
      child: GridView.count(
        shrinkWrap: true,
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        physics: const NeverScrollableScrollPhysics(),
        children: keys.map((k) {
          return Material(
            color: const Color(0xFF1B3540),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                if (k == '<') {
                  _backspace();
                } else if (k == '00') {
                  _tap('0');
                  _tap('0');
                } else {
                  _tap(k);
                }
              },
              child: Center(
                child: k == '<'
                    ? const Icon(Icons.backspace_outlined, color: Colors.white70)
                    : Text(
                        k,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// LAUNCH-P5 fix order 2 (T4) — what the close checks before it is sent.
class _CloseCheck {
  const _CloseCheck({
    required this.unsent,
    required this.parked,
    required this.checkoutUnsent,
    required this.orderUuids,
    required this.payouts,
  });
  final List<OrderOutboxRow> unsent;
  final List<OrderOutboxRow> parked;
  final List<CheckoutAttempt> checkoutUnsent;
  final List<String> orderUuids;
  final List<int> payouts;

  /// Sales, checkout payments or pay-outs still sending block the close.
  /// Parked rows do not: the server says whether it is missing them.
  bool get blocks =>
      unsent.isNotEmpty || checkoutUnsent.isNotEmpty || payouts.isNotEmpty;
}

/// LAUNCH-P5 fix order 2 (T4) — this device's checkout journal for the
/// close (null when the till has no server identity yet). Tests override.
final checkoutCloseHoldProvider =
    Provider<Future<CheckoutCloseHold?> Function()>(
      (ref) => () async {
        final api = ref.read(apiServiceProvider);
        final session = ref.read(sessionServiceProvider);
        String scope() => quickDeviceScope(
          api.quickOrderBaseUrl,
          session.companyId,
          session.branchId,
          session.kioskId,
        );
        final String current;
        try {
          current = scope();
        } catch (_) {
          return null;
        }
        final store = await SqliteCheckoutStore.open(current);
        return CheckoutCloseHold(
          db: store.db,
          scope: current,
          resume: () => QrCheckoutController(
            gateway: ApiCheckoutGateway(
              api: api,
              currentScope: scope,
              // Only used before a new tender, which the close never starts.
              location: () async => null,
              legacyGuard: (_) async {},
            ),
            store: store,
            captureCard: refuseCheckoutCapture,
            captureBank: refuseCheckoutCapture,
            authorizeGift: () async => false,
            staffId: () => session.staff?.id,
            projectReceipt: (snapshot, attempt) =>
                projectMachineCheckoutReceipt(
                  ServerReceiptHistory(
                    debugOrderStorageOverride ??
                        LocalOrderStorageService.instance,
                  ),
                  snapshot,
                  attempt,
                ),
          ),
        );
      },
    );
