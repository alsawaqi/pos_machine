import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/authorization.dart';
import '../l10n/l10n.dart';
import '../models/pos_models.dart' show VoidReasonRef;
import '../qr_quick/qr_quick_models.dart';
import 'tablet_order_models.dart';
import 'tablet_orders_controller.dart';

/// What the till lends the tablet orders screen: its gates and its existing
/// money paths. The screen itself never prices, pays or voids.
class TabletOrderActions {
  const TabletOrderActions({
    required this.authorize,
    this.takeCash,
    this.voidOrder,
    this.voidReasons = const [],
    this.openTable,
    this.moveToCounter,
    this.paymentReview,
    this.checkPaymentResult,
    this.pickItem,
    this.myStaffId,
    this.onOpened,
    this.printsKitchenTickets,
  });

  /// The till's `_authorizeAction`: the person's own tick, or an approver's
  /// PIN. Null = not allowed (nothing is sent).
  final Future<ActionAuthorization?> Function(
    String action, {
    String? subtitle,
    bool alwaysApproval,
  })
  authorize;

  /// The claim, then the existing cash pay of the order's frozen total.
  /// True once the server confirmed THIS order's payment; false when not
  /// paid; null when a saved checkout of another order was finished instead
  /// (T-2: this order is neither paid nor sent).
  final Future<bool?> Function(TabletOrderRow row)? takeCash;

  /// T-3 — false when this till does not print QR / tablet kitchen tickets
  /// (the "QR kitchen rounds" setting is off): staff are warned on send.
  final bool Function()? printsKitchenTickets;

  /// The existing `order.void` (durable outbox) with its gate's block.
  final Future<void> Function(
    TabletOrderRow row, {
    VoidReasonRef? reason,
    required ActionAuthorization authorization,
  })?
  voidOrder;
  final List<VoidReasonRef> voidReasons;

  /// A sent dine-in order is cancelled at its table.
  final void Function(TabletOrderRow row)? openTable;

  /// F-13 / F-15 — recovery of a lapsed or uncertain cash claim. Move to
  /// counter answers the server's refusal code (null when it worked, T-6).
  final Future<String?> Function(TabletOrderRow row)? moveToCounter;
  final Future<void> Function(TabletOrderRow row)? paymentReview;
  final Future<void> Function()? checkPaymentResult;

  /// The till's price-free item picker (for "Add item" in the edit).
  final Future<QrQuickLine?> Function(BuildContext context)? pickItem;
  final int? myStaffId;

  /// Opening an order stops its ring on this device.
  final void Function(String attentionKey)? onOpened;
}

String tabletMoney(int baisas) => (baisas / 1000).toStringAsFixed(3);

/// LAUNCH-P6 till fix order 1 (T-4) — the tablet list opens only over the
/// staff POS itself: null when [context]'s route is the current one, else
/// "Finish this screen first".
String? tabletOrdersOpenBlock(BuildContext context) =>
    ModalRoute.of(context)?.isCurrent ?? true
    ? null
    : L10n.of(context).tabletFinishScreenFirst;

String tabletTypeLabel(L10n l10n, TabletOrderRow row) =>
    switch (row.orderType) {
      'dine_in' => l10n.tabletTypeDineIn,
      'to_go' => l10n.tabletTypeToGo,
      _ => l10n.tabletTypeQuick,
    };

/// The refusal text of a tablet action notice.
String tabletNoticeText(L10n l10n, String code, String? name) => switch (code) {
  'tablet_order_taken' => l10n.tabletRefusedTaken(name ?? l10n.tabletSomeone),
  'tablet_order_closed' ||
  'tablet_order_paid' ||
  'tablet_order_sent' ||
  'tablet_round_not_sendable' ||
  'redeem_already_resolved' ||
  'redeem_not_requested' => l10n.tabletRefusedClosed,
  'tablet_order_being_paid' => l10n.tabletRefusedBeingPaid,
  'redeem_pending' => l10n.tabletResolvePointsFirst,
  'too_many_attempts' || 'rate_limited' => l10n.tabletRefusedRateLimited,
  'bill_reserved' => l10n.tabletRefusedBillReserved,
  'tablet_round_needs_update' => l10n.tabletRefusedNeedsUpdate,
  'approval_required' || 'approval_invalid' => l10n.tabletRefusedApproval,
  'loyalty_customer_limit' ||
  'loyalty_staff_limit' ||
  'loyalty_insufficient' ||
  'loyalty_rule_unsupported' ||
  'bill_points_already_used' => l10n.tabletRefusedLimit,
  'tablet_lines_unavailable' => l10n.tabletRefusedUnavailable,
  'network' => l10n.tabletRefusedNetwork,
  _ => l10n.tabletRefusedGeneric(code),
};

/// The points line: requested, approved (what was approved), rejected (0).
String? tabletPointsLine(L10n l10n, TabletRedeem? redeem) {
  if (redeem == null) return null;
  return switch (redeem.status) {
    'requested' => l10n.tabletPointsRequested(
      redeem.shownUnits,
      tabletMoney(redeem.shownAmountBaisas),
    ),
    'approved' => l10n.tabletPointsApproved(
      redeem.shownUnits,
      tabletMoney(redeem.shownAmountBaisas),
    ),
    'rejected' => l10n.tabletPointsRejected,
    _ => l10n.tabletPointsSuperseded,
  };
}

/// "Being paid on `device`" / "Needs recovery" for the charge state.
String? tabletChargeLine(
  L10n l10n,
  TabletOrderRow row,
  Map<int, String> devices,
) {
  final charge = row.charge;
  if (row.recoveryNeeded || charge.state == 'unknown') {
    return l10n.tabletNeedsRecovery;
  }
  if (charge.beingPaid) {
    final device = charge.heldByThisDevice
        ? l10n.tabletThisDevice
        : (devices[charge.deviceId] ?? l10n.tabletAnotherDevice);
    return l10n.tabletBeingPaidOn(device);
  }
  return null;
}

/// LAUNCH-P6 item 9 — the shift close's warning: unpaid tablet orders stay
/// open after the close (never blocks it).
class TabletUnpaidWarning extends StatelessWidget {
  const TabletUnpaidWarning({super.key, required this.rows});
  final List<TabletOrderRow> rows;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Container(
      key: const ValueKey('tablet-unpaid-warning'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x33E0A93B),
        border: Border.all(color: const Color(0xFFE0A93B)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white, height: 1.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.tabletShiftCloseWarning(rows.length),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            for (final row in rows)
              Text(
                '${row.label(tableWord: l10n.tabletTableWord)} · '
                '${tabletTypeLabel(l10n, row)} · '
                '${tabletMoney(row.payableBaisas)}',
              ),
            const SizedBox(height: 4),
            Text(l10n.tabletShiftCloseHint),
          ],
        ),
      ),
    );
  }
}

/// LAUNCH-P6 Part C item 4 — the tablet orders list (till).
class TabletOrdersScreen extends StatefulWidget {
  const TabletOrdersScreen({
    super.key,
    required this.controller,
    required this.actions,
    this.initialKey,
    this.openRequests,
    this.poll = const Duration(seconds: 5),
  });
  final TabletOrdersController controller;
  final TabletOrderActions actions;

  /// Later "Open" requests (banner) while this screen is up: they open the
  /// order here; a second list screen is never pushed.
  final ValueListenable<String?>? openRequests;

  /// Open this order (attention key or tablet order uuid) once listed.
  final String? initialKey;
  final Duration poll;

  @override
  State<TabletOrdersScreen> createState() => _TabletOrdersScreenState();
}

class _TabletOrdersScreenState extends State<TabletOrdersScreen> {
  Timer? _timer;
  bool _openedInitial = false;
  bool _sheetOpen = false;

  void _openRequested() => unawaited(_openRequestedAsync());

  /// T-5 — the requested order may be newer than this list: read it first.
  Future<void> _openRequestedAsync() async {
    final key = widget.openRequests?.value;
    if (key == null || _sheetOpen || !mounted) return;
    final uuid = key.startsWith('tablet:') ? key.substring(7) : key;
    if (widget.controller.find(uuid) == null) {
      await widget.controller.refresh();
    }
    if (!mounted || _sheetOpen || widget.openRequests?.value != key) return;
    if (widget.controller.find(uuid) != null) await _open(uuid);
  }

  @override
  void initState() {
    super.initState();
    widget.openRequests?.addListener(_openRequested);
    widget.controller.addListener(_maybeOpenInitial);
    unawaited(widget.controller.refresh());
    _timer = Timer.periodic(widget.poll, (_) {
      if (widget.controller.busy == null) {
        unawaited(widget.controller.refresh());
      }
    });
  }

  void _maybeOpenInitial() {
    final key = widget.initialKey;
    if (_openedInitial || key == null || !widget.controller.loaded) return;
    final uuid = key.startsWith('tablet:') ? key.substring(7) : key;
    final row = widget.controller.find(uuid);
    _openedInitial = true;
    if (row == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_open(row.uuid));
    });
  }

  Future<void> _open(String uuid) async {
    final row = widget.controller.find(uuid);
    if (row == null || _sheetOpen) return;
    widget.actions.onOpened?.call(row.attentionKey);
    _sheetOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => TabletOrderSheet(
          controller: widget.controller,
          actions: widget.actions,
          uuid: uuid,
        ),
      );
    } finally {
      _sheetOpen = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.openRequests?.removeListener(_openRequested);
    widget.controller.removeListener(_maybeOpenInitial);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabletOrdersTitle),
        actions: [
          IconButton(
            key: const ValueKey('tablet-orders-refresh'),
            tooltip: l10n.tabletOrdersRefresh,
            onPressed: () => unawaited(widget.controller.refresh()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          final rows = c.orders.where((row) => !row.closed).toList();
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (c.stale)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l10n.tabletOrdersStale,
                    key: const ValueKey('tablet-orders-stale'),
                    style: const TextStyle(color: Color(0xFFB3261E)),
                  ),
                ),
              if (c.loaded && rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.tabletOrdersEmpty,
                    key: const ValueKey('tablet-orders-empty'),
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final row in rows)
                TabletOrderCard(
                  row: row,
                  devices: c.devices,
                  myStaffId: widget.actions.myStaffId,
                  onTap: () => unawaited(_open(row.uuid)),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// One tablet order in the list.
class TabletOrderCard extends StatelessWidget {
  const TabletOrderCard({
    super.key,
    required this.row,
    required this.onTap,
    this.devices = const {},
    this.myStaffId,
  });
  final TabletOrderRow row;
  final VoidCallback onTap;
  final Map<int, String> devices;
  final int? myStaffId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final taken = row.takenBy;
    final points = tabletPointsLine(l10n, row.redeem);
    final charge = tabletChargeLine(l10n, row, devices);
    return Card(
      key: ValueKey('tablet-order-${row.uuid}'),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.label(tableWord: l10n.tabletTableWord),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(tabletTypeLabel(l10n, row)),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _Chip(row.pending ? l10n.tabletWaiting : l10n.tabletSent),
                  if (row.sentUnpaid)
                    _Chip(
                      l10n.tabletUnpaid,
                      key: ValueKey('tablet-unpaid-${row.uuid}'),
                      color: const Color(0xFFFFD6D1),
                    ),
                  if (row.paid)
                    _Chip(l10n.tabletPaid, color: const Color(0xFFD7F2DE)),
                ],
              ),
              const SizedBox(height: 6),
              Text(l10n.tabletTotalLine(tabletMoney(row.payableBaisas))),
              if (row.phoneMasked != null)
                Text(l10n.tabletPhone(row.phoneMasked!)),
              ?points == null ? null : Text(points),
              if (taken != null)
                Text(
                  taken.staffId != null && taken.staffId == myStaffId
                      ? l10n.tabletTakenByYou
                      : l10n.tabletTakenBy(taken.name ?? l10n.tabletSomeone),
                  key: ValueKey('tablet-taken-${row.uuid}'),
                ),
              ?charge == null
                  ? null
                  : Text(
                      charge,
                      style: const TextStyle(color: Color(0xFF8A5300)),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color ?? const Color(0xFFE6EEF2),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}

/// The order sheet: its lines, state and the staff actions.
class TabletOrderSheet extends StatefulWidget {
  const TabletOrderSheet({
    super.key,
    required this.controller,
    required this.actions,
    required this.uuid,
  });
  final TabletOrdersController controller;
  final TabletOrderActions actions;
  final String uuid;

  @override
  State<TabletOrderSheet> createState() => _TabletOrderSheetState();
}

class _TabletOrderSheetState extends State<TabletOrderSheet> {
  bool _working = false;
  String? _message;

  TabletOrdersController get c => widget.controller;
  TabletOrderActions get a => widget.actions;

  Future<void> _guard(Future<void> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await action();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<bool> _confirm(String text, {String? yes}) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(
              key: const ValueKey('tablet-confirm-no'),
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(L10n.of(dialog).commonCancel),
            ),
            FilledButton(
              key: const ValueKey('tablet-confirm-yes'),
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(yes ?? L10n.of(dialog).commonConfirm),
            ),
          ],
        ),
      ) ==
      true;

  bool _mine(TabletOrderRow row) {
    final taken = row.takenBy;
    return taken == null ||
        (taken.staffId != null && taken.staffId == a.myStaffId);
  }

  Future<void> _take(TabletOrderRow row) => _guard(() async {
    final other = row.takenBy != null && !_mine(row);
    if (other &&
        !await _confirm(
          L10n.of(context).tabletTakeOverConfirm(
            row.takenBy!.name ?? L10n.of(context).tabletSomeone,
          ),
          yes: L10n.of(context).tabletTakeOver,
        )) {
      return;
    }
    await c.take(row.uuid, takeOver: other);
  });

  /// T-3 — sent, but this till does not print the ticket.
  void _warnIfNoPrint() {
    if (a.printsKitchenTickets?.call() == false && mounted) {
      setState(() => _message = L10n.of(context).tabletPrintOffWarning);
    }
  }

  Future<void> _send(TabletOrderRow row) => _guard(() async {
    if (await c.send(row.uuid)) _warnIfNoPrint();
  });

  Future<void> _takeCash(TabletOrderRow row) => _guard(() async {
    final takeCash = a.takeCash;
    if (takeCash == null) return;
    if (row.redeemWaiting) {
      setState(() => _message = L10n.of(context).tabletResolvePointsFirst);
      return;
    }
    // Take it first, so another device sees who is taking the cash.
    if (row.takenBy == null && !await c.take(row.uuid)) return;
    final current = c.find(row.uuid) ?? row;
    final wasPending = current.pending;
    final paid = await takeCash(current);
    await c.refresh();
    if (!mounted) return;
    if (paid == null) {
      // T-2 — another order's saved checkout finished: not this one.
      setState(() => _message = L10n.of(context).tabletOtherCheckoutFinished);
      return;
    }
    if (!paid) return;
    // Cash first, then the kitchen.
    if (wasPending) {
      final sent = await c.send(row.uuid);
      if (!sent && mounted) {
        setState(() => _message = L10n.of(context).tabletPaidNotSent);
      } else {
        _warnIfNoPrint();
      }
    }
  });

  Future<void> _approve(TabletOrderRow row) => _guard(() async {
    final redeem = row.redeem;
    if (redeem == null) return;
    final l10n = L10n.of(context);
    final gate = await a.authorize(
      'loyalty.redeem',
      subtitle: l10n.tabletRedeemQuestion(
        redeem.units,
        tabletMoney(redeem.amountBaisas),
        row.phoneMasked ?? '',
      ),
    );
    if (gate == null || !mounted) return;
    await c.approve(row.uuid, gate);
  });

  Future<void> _reject(TabletOrderRow row) => _guard(() async {
    await c.reject(row.uuid);
  });

  Future<void> _cancel(TabletOrderRow row) => _guard(() async {
    final l10n = L10n.of(context);
    if (row.dineIn) {
      if (row.sent) {
        // Points still waiting: answer them here before the table.
        if (row.redeemWaiting &&
            !await _confirm(
              l10n.tabletResolvePointsFirst,
              yes: l10n.tabletCancelAtTable,
            )) {
          return;
        }
        a.openTable?.call(row);
        if (mounted) Navigator.of(context).pop();
        return;
      }
      if (!await _confirm(
        l10n.tabletCancelRoundConfirm,
        yes: l10n.tabletReject,
      )) {
        return;
      }
      await c.rejectRound(row.uuid);
      return;
    }
    final voidOrder = a.voidOrder;
    if (voidOrder == null) return;
    VoidReasonRef? reason;
    if (row.sent) {
      // After sending: the cancel-with-wastage rule (a "food was made"
      // reason books the sent lines as waste).
      final made = a.voidReasons.where((r) => r.affectsInventory).toList();
      if (made.isEmpty) {
        setState(() => _message = l10n.tabletCancelNoMadeReason);
        return;
      }
      reason = await showDialog<VoidReasonRef>(
        context: context,
        builder: (dialog) {
          final ar = Localizations.localeOf(dialog).languageCode == 'ar';
          return SimpleDialog(
            title: Text(l10n.tabletCancelMadeTitle),
            children: [
              for (final r in made)
                SimpleDialogOption(
                  key: ValueKey('tablet-void-reason-${r.id}'),
                  onPressed: () => Navigator.pop(dialog, r),
                  child: Text(
                    ar && (r.nameAr ?? '').isNotEmpty ? r.nameAr! : r.name,
                  ),
                ),
            ],
          );
        },
      );
      if (reason == null || !mounted) return;
    } else if (!await _confirm(
      l10n.tabletCancelUnsentConfirm,
      yes: l10n.tabletCancelOrder,
    )) {
      return;
    }
    if (!mounted) return;
    final gate = await a.authorize(
      'order.void_unpaid',
      alwaysApproval: reason?.requiresManager == true,
      subtitle: l10n.tabletCancelOrder,
    );
    if (gate == null || !mounted) return;
    await voidOrder(row, reason: reason, authorization: gate);
    if (mounted) setState(() => _message = l10n.tabletCancelQueued);
    await c.refresh();
  });

  Future<void> _edit(TabletOrderRow row) => _guard(() async {
    final lines = await showDialog<List<QrQuickLine>>(
      context: context,
      builder: (_) => TabletEditLinesDialog(row: row, pickItem: a.pickItem),
    );
    if (lines == null || lines.isEmpty || !mounted) return;
    await c.editLines(row.uuid, lines);
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final l10n = L10n.of(context);
      final row = c.find(widget.uuid);
      if (row == null) {
        return AlertDialog(
          content: Text(l10n.tabletRefusedClosed),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonClose),
            ),
          ],
        );
      }
      final busy = _working || c.busy != null;
      final mine = _mine(row);
      final ar = Localizations.localeOf(context).languageCode == 'ar';
      final points = tabletPointsLine(l10n, row.redeem);
      final charge = tabletChargeLine(l10n, row, c.devices);
      final notice = c.notice == null
          ? null
          : tabletNoticeText(l10n, c.notice!, c.noticeName);
      final open = !row.closed && row.unpaid;
      final recovery = row.recoveryNeeded || row.charge.state == 'unknown';
      final buttons = <Widget>[
        if (open && row.takenBy == null)
          FilledButton(
            key: const ValueKey('tablet-take'),
            onPressed: busy ? null : () => _take(row),
            child: Text(l10n.tabletTake),
          ),
        if (!row.closed && !mine)
          OutlinedButton(
            key: const ValueKey('tablet-take-over'),
            onPressed: busy ? null : () => _take(row),
            child: Text(l10n.tabletTakeOver),
          ),
        // Dine in: the server approves points once the round is sent.
        if (mine && open && row.redeemWaiting && (!row.dineIn || row.sent)) ...[
          FilledButton(
            key: const ValueKey('tablet-redeem-approve'),
            onPressed: busy ? null : () => _approve(row),
            child: Text(l10n.tabletApprove),
          ),
          OutlinedButton(
            key: const ValueKey('tablet-redeem-reject'),
            onPressed: busy ? null : () => _reject(row),
            child: Text(l10n.tabletReject),
          ),
        ],
        if (mine && row.pending && !row.closed && !recovery)
          FilledButton.tonal(
            key: const ValueKey('tablet-send'),
            onPressed: busy ? null : () => _send(row),
            child: Text(
              row.dineIn
                  ? l10n.tabletSendDineIn
                  : (row.paid ? l10n.tabletSendNow : l10n.tabletSendLater),
            ),
          ),
        // Shown but disabled while a points request waits (answer it first).
        if (mine &&
            !row.dineIn &&
            open &&
            row.charge.state == 'none' &&
            a.takeCash != null &&
            !recovery)
          FilledButton(
            key: const ValueKey('tablet-take-cash'),
            onPressed: busy || !row.canTakeCash ? null : () => _takeCash(row),
            child: Text(
              row.pending ? l10n.tabletTakeCashThenSend : l10n.tabletTakeCash,
            ),
          ),
        if (mine && row.editable)
          OutlinedButton(
            key: const ValueKey('tablet-edit'),
            onPressed: busy ? null : () => _edit(row),
            child: Text(l10n.tabletEditLines),
          ),
        // T-7 — a live claim held here (an interrupted checkout) too.
        if ((recovery || row.charge.beingPaid) &&
            row.charge.heldByThisDevice &&
            a.checkPaymentResult != null)
          FilledButton(
            key: const ValueKey('tablet-check-payment'),
            onPressed: busy
                ? null
                : () => _guard(() async {
                    await a.checkPaymentResult!();
                    await c.refresh();
                  }),
            child: Text(l10n.tabletCheckPayment),
          ),
        if (recovery &&
            !row.charge.heldByThisDevice &&
            row.charge.state != 'recovered' &&
            a.moveToCounter != null)
          OutlinedButton(
            key: const ValueKey('tablet-move-counter'),
            onPressed: busy
                ? null
                : () => _guard(() async {
                    final refusal = await a.moveToCounter!(row);
                    await c.refresh();
                    // T-6 — the refusal is shown, not swallowed.
                    if (refusal != null && mounted) {
                      setState(
                        () => _message = tabletNoticeText(
                          L10n.of(context),
                          refusal,
                          null,
                        ),
                      );
                    }
                  }),
            child: Text(l10n.tabletMoveToCounter),
          ),
        if (recovery && a.paymentReview != null)
          OutlinedButton(
            key: const ValueKey('tablet-payment-review'),
            onPressed: busy
                ? null
                : () => _guard(() async {
                    await a.paymentReview!(row);
                    await c.refresh();
                  }),
            child: Text(l10n.tabletPaymentReview),
          ),
        if (mine && open && !recovery && !row.charge.beingPaid)
          TextButton(
            key: const ValueKey('tablet-cancel'),
            onPressed: busy ? null : () => _cancel(row),
            child: Text(
              row.dineIn && row.sent
                  ? l10n.tabletCancelAtTable
                  : l10n.tabletCancelOrder,
            ),
          ),
      ];
      return AlertDialog(
        key: ValueKey('tablet-sheet-${row.uuid}'),
        title: Text(
          '${row.label(tableWord: l10n.tabletTableWord)} · '
          '${tabletTypeLabel(l10n, row)}',
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 6,
                  children: [
                    _Chip(row.pending ? l10n.tabletWaiting : l10n.tabletSent),
                    if (row.sentUnpaid)
                      _Chip(
                        l10n.tabletUnpaid,
                        key: const ValueKey('tablet-sheet-unpaid'),
                        color: const Color(0xFFFFD6D1),
                      ),
                    if (row.paid)
                      _Chip(l10n.tabletPaid, color: const Color(0xFFD7F2DE)),
                  ],
                ),
                const SizedBox(height: 8),
                for (final line in row.lines) ..._lineTexts(line, ar),
                const Divider(),
                Text(
                  l10n.tabletTotalLine(tabletMoney(row.payableBaisas)),
                  key: const ValueKey('tablet-sheet-total'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (row.phoneMasked != null)
                  Text(l10n.tabletPhone(row.phoneMasked!)),
                if (points != null)
                  Text(points, key: const ValueKey('tablet-sheet-points')),
                if (row.redeemWaiting && mine)
                  Text(
                    l10n.tabletRedeemQuestion(
                      row.redeem!.units,
                      tabletMoney(row.redeem!.amountBaisas),
                      row.phoneMasked ?? '',
                    ),
                    key: const ValueKey('tablet-redeem-question'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                if (row.redeemWaiting && mine && (!row.dineIn || row.sent))
                  Text(
                    l10n.tabletResolvePointsFirst,
                    key: const ValueKey('tablet-points-first'),
                  ),
                if (row.readyInMinutes != null)
                  Text(l10n.tabletReadyIn(row.readyInMinutes!)),
                if (row.takenBy != null)
                  Text(
                    mine
                        ? l10n.tabletTakenByYou
                        : l10n.tabletTakenBy(
                            row.takenBy!.name ?? l10n.tabletSomeone,
                          ),
                    key: const ValueKey('tablet-sheet-taken'),
                  ),
                if (row.sentToKitchen?.name != null)
                  Text(l10n.tabletSentBy(row.sentToKitchen!.name!)),
                if (charge != null)
                  Text(
                    charge,
                    key: const ValueKey('tablet-sheet-charge'),
                    style: const TextStyle(color: Color(0xFF8A5300)),
                  ),
                if (row.paid && row.pending) Text(l10n.tabletPaidNotSent),
                if (notice != null || _message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _message ?? notice!,
                      key: const ValueKey('tablet-sheet-notice'),
                      style: const TextStyle(color: Color(0xFFB3261E)),
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: buttons),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('tablet-sheet-close'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonClose),
          ),
        ],
      );
    },
  );

  List<Widget> _lineTexts(Map<String, dynamic> line, bool ar) {
    String name(Map<String, dynamic> m, String en, String arKey) {
      final arabic = m[arKey]?.toString().trim() ?? '';
      if (ar && arabic.isNotEmpty) return arabic;
      return m[en]?.toString() ?? '#${m['product_id']}';
    }

    final qty = (line['qty'] as num);
    return [
      Text(
        '${qty == qty.roundToDouble() ? qty.toInt() : qty} × '
        '${name(line, 'product_name', 'product_name_ar')}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      for (final addon in (line['addons'] as List?) ?? const [])
        if (addon is Map)
          Text(
            '   + ${name(Map<String, dynamic>.from(addon), 'name', 'name_ar')}',
          ),
      for (final label in serverComboLabels(line, arabic: ar))
        Text('   $label'),
    ];
  }
}

/// F-8 — staff change the lines before sending: quantity, remove, add.
class TabletEditLinesDialog extends StatefulWidget {
  const TabletEditLinesDialog({super.key, required this.row, this.pickItem});
  final TabletOrderRow row;
  final Future<QrQuickLine?> Function(BuildContext context)? pickItem;

  @override
  State<TabletEditLinesDialog> createState() => _TabletEditLinesDialogState();
}

class _TabletEditLinesDialogState extends State<TabletEditLinesDialog> {
  late final List<(String, QrQuickLine)> _lines;

  @override
  void initState() {
    super.initState();
    final names = <int, String>{};
    for (final line in widget.row.lines) {
      final id = (line['product_id'] as num?)?.toInt();
      if (id != null) names[id] = line['product_name']?.toString() ?? '#$id';
    }
    _lines = [
      for (final line in widget.row.editLines)
        (names[line.productId] ?? '#${line.productId}', line),
    ];
  }

  QrQuickLine _withQty(QrQuickLine line, int qty) =>
      QrQuickLine(line.productId, qty, line.addonIds, combo: line.combo);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AlertDialog(
      title: Text(l10n.tabletEditLines),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _lines.length; i++)
                Row(
                  key: ValueKey('tablet-edit-line-$i'),
                  children: [
                    Expanded(child: Text(_lines[i].$1)),
                    IconButton(
                      key: ValueKey('tablet-edit-minus-$i'),
                      onPressed: _lines[i].$2.quantity > 1
                          ? () => setState(
                              () => _lines[i] = (
                                _lines[i].$1,
                                _withQty(
                                  _lines[i].$2,
                                  _lines[i].$2.quantity - 1,
                                ),
                              ),
                            )
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Text('${_lines[i].$2.quantity}'),
                    IconButton(
                      key: ValueKey('tablet-edit-plus-$i'),
                      onPressed: _lines[i].$2.quantity < 99
                          ? () => setState(
                              () => _lines[i] = (
                                _lines[i].$1,
                                _withQty(
                                  _lines[i].$2,
                                  _lines[i].$2.quantity + 1,
                                ),
                              ),
                            )
                          : null,
                      icon: const Icon(Icons.add),
                    ),
                    IconButton(
                      key: ValueKey('tablet-edit-remove-$i'),
                      tooltip: l10n.tabletRemoveLine,
                      onPressed: () => setState(() => _lines.removeAt(i)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              if (widget.pickItem != null)
                TextButton.icon(
                  key: const ValueKey('tablet-edit-add'),
                  onPressed: () async {
                    final line = await widget.pickItem!(context);
                    if (line == null || !mounted) return;
                    setState(() => _lines.add(('#${line.productId}', line)));
                  },
                  icon: const Icon(Icons.add_circle_outline),
                  label: Text(l10n.tabletAddItem),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('tablet-edit-save'),
          onPressed: _lines.isEmpty
              ? null
              : () => Navigator.of(
                  context,
                ).pop([for (final line in _lines) line.$2]),
          child: Text(l10n.tabletSaveLines),
        ),
      ],
    );
  }
}
