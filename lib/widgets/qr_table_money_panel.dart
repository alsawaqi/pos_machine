import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/manager_auth.dart';
import '../models/qr_till_models.dart';
import '../qr_quick/qr_quick_models.dart' show serverComboLabels;
import '../providers/providers.dart';
import '../services/pos_api_service.dart';
import '../services/qr_settlement_coordinator.dart';
import '../services/qr_till_messages.dart';
import '../services/qr_till_service.dart';

/// The two orphan states are deliberately separate: an expired session still
/// exists, while a deleted opener can leave the order with no session link.
enum QrTableDisplayState {
  free,
  awaitingFirstScan,
  active,
  paymentRequested,
  orphanedExpired,
  orphanedMissingSession,
}

enum _QrRoundDecision { confirm, reject }

QrTableDisplayState qrTableDisplayStateFor(QrTableBoardRow? row) {
  if (row == null) return QrTableDisplayState.free;
  if (row.hasMissingSession) {
    return QrTableDisplayState.orphanedMissingSession;
  }
  if (row.orphaned || row.sessionStatus == 'expired') {
    return QrTableDisplayState.orphanedExpired;
  }
  if (row.order?.status == 'awaiting_payment' ||
      row.order?.status == 'held' ||
      row.sessionStatus == 'ordered') {
    return QrTableDisplayState.paymentRequested;
  }
  if (row.sessionStatus == 'pending') {
    return QrTableDisplayState.awaitingFirstScan;
  }
  return QrTableDisplayState.active;
}


abstract class QrTableMoneyHost {
  QrTableBoardRow? get row;
  QrActiveOrder? get active;
  void notice(String text, {bool success = false});
  Future<void> refresh();
  void applyOrderAction(QrOrderActionResult result);
  bool get arabic;
}

/// The host supplies read-only selection and board refreshes. All settlement
/// state and the route guard remain together, including while no table is selected.
class QrTableMoneyPanel extends ConsumerStatefulWidget {
  const QrTableMoneyPanel({
    super.key,
    required this.host,
    this.standaloneOrder,
    this.tableKey,
    this.tableLabel,
    this.forceRefresh,
    this.builder,
    this.openCheckout,
  });

  final QrTableMoneyHost host;
  final Future<void> Function(String)? openCheckout;
  final QrBoardOrder? standaloneOrder;
  final String? tableKey;
  final String? tableLabel;
  final Future<void> Function()? forceRefresh;
  final Widget Function(
    BuildContext context,
    Widget detail,
    Future<void> Function() requestRouteExit,
    bool settlementInFlight,
  )? builder;

  @override
  ConsumerState<QrTableMoneyPanel> createState() => _QrTableMoneyPanelState();
}

class _QrTableMoneyPanelState extends ConsumerState<QrTableMoneyPanel> {
  bool _acting = false;
  bool _claimInFlight = false;
  bool _settlementInFlight = false;
  bool _managerRecoveryRequired = false;
  QrSettlementClaim? _heldClaim;

  bool get _qrSettlementBlocked =>
      _acting || _heldClaim != null || _managerRecoveryRequired;

  Map<String, QrActiveOrder> get _active {
    final active = widget.host.active;
    return active == null ? const {} : {active.uuid: active};
  }
  bool get _arabic => widget.host.arabic;
  String _copy(String key) => qrTillUiCopy(key, arabic: _arabic);
  String _message(ApiException error) => error.code == null
      ? error.message
      : qrTillMessageForCode(error.code, arabic: _arabic);
  void _notice(String text, {bool success = false}) =>
      widget.host.notice(text, success: success);
  Future<void> _refresh() => widget.host.refresh();
  Future<void> _forceRefresh() =>
      widget.forceRefresh?.call() ?? widget.host.refresh();
  void _applyOrderAction(QrOrderActionResult result) =>
      widget.host.applyOrderAction(result);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _restorePendingManagerRecovery();
      if (mounted) await _refresh();
    });
  }

  Future<void> _restorePendingManagerRecovery() async {
    if (!mounted) return;
    final pending = ref
        .read(qrSettlementCoordinatorProvider)
        .pendingManagerRecoveries
        .firstOrNull;
    if (pending == null) return;

    setState(() {
      _heldClaim = pending.claim;
      _managerRecoveryRequired = true;
    });
    await _handleSettlementResult(pending);
  }


  @override
  Widget build(BuildContext context) {
    final standalone = widget.tableKey == null && widget.host.row == null
        ? widget.standaloneOrder
        : null;
    final key =
        widget.tableKey ??
        widget.host.row?.tableId.toString() ??
        (standalone == null ? null : 'quick-${standalone.uuid}');
    final table = key == null
        ? null
        : _TableView(
            key: key,
            floorId: '',
            label:
                widget.tableLabel ??
                widget.host.row?.tableLabel ??
                standalone?.receiptNumber ??
                standalone?.tempReference ??
                standalone?.uuid ??
                '',
            row: widget.host.row,
          );
    final detail = _detail(table);
    return PopScope(
      canPop: !_claimInFlight && !_settlementInFlight && _heldClaim == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestRouteExit());
      },
      child: widget.builder?.call(
            context, detail, _requestRouteExit, _settlementInFlight,
          ) ?? detail,
    );
  }

  Future<void> _action(
    Future<void> Function(QrTillGateway service) operation,
    String success,
  ) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await operation(ref.read(qrTillServiceProvider));
      if (!mounted) return;
      _notice(success, success: true);
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) _notice(_message(error));
    } catch (error) {
      if (mounted) _notice('The action could not be completed. $error');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _reviewPendingRound(QrPendingRound summary) async {
    if (_acting) return;
    setState(() => _acting = true);
    QrRoundEnvelope detail;
    try {
      detail = await ref.read(qrRoundGatewayProvider).fetchRound(summary.id);
    } on ApiException catch (error) {
      if (mounted) _notice(_message(error));
      return;
    } catch (error) {
      if (mounted) _notice('${_copy('round_awaiting')}: $error');
      return;
    } finally {
      if (mounted) setState(() => _acting = false);
    }
    if (!mounted) return;

    final decision = await showDialog<_QrRoundDecision>(
      context: context,
      builder: (context) => AlertDialog(
        key: ValueKey('qr-round-detail-${detail.round.id}'),
        title: Text('${_copy('round_title')} ${detail.round.roundNo}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final line in detail.round.lines)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${_qty(line.quantity)} × ${line.displayLabel(arabic: _arabic)}',
                    ),
                    subtitle: line.notes == null
                        ? null
                        : Text('${_copy('round_notes')}: ${line.notes}'),
                    trailing: Text(_money(line.lineTotalBaisas)),
                  ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _copy('round_total'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      _money(detail.round.totalBaisas),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_copy('round_keep')),
          ),
          OutlinedButton(
            key: const ValueKey('qr-round-reject'),
            onPressed: () => Navigator.pop(context, _QrRoundDecision.reject),
            child: Text(_copy('round_reject')),
          ),
          FilledButton(
            key: const ValueKey('qr-round-confirm'),
            onPressed: () => Navigator.pop(context, _QrRoundDecision.confirm),
            child: Text(_copy('round_confirm')),
          ),
        ],
      ),
    );
    if (decision == null || !mounted) return;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: ValueKey('qr-round-${decision.name}-confirmation'),
        title: Text(
          decision == _QrRoundDecision.confirm
              ? _copy('round_confirm')
              : _copy('round_reject'),
        ),
        content: Text(
          decision == _QrRoundDecision.confirm
              ? _copy('round_confirm_question')
              : _copy('round_reject_question'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_copy('round_keep')),
          ),
          FilledButton(
            key: ValueKey('qr-round-${decision.name}-proceed'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              decision == _QrRoundDecision.confirm
                  ? _copy('round_confirm')
                  : _copy('round_reject'),
            ),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    setState(() => _acting = true);
    try {
      final service = ref.read(qrRoundGatewayProvider);
      if (decision == _QrRoundDecision.reject) {
        await service.rejectRound(detail.round.id);
        if (mounted) _notice(_copy('round_rejected'), success: true);
      } else {
        final confirmed = await service.confirmRound(detail.round.id);
        var printed = true;
        if (ref.read(settingsControllerProvider).printKitchenTickets) {
          printed = await ref
              .read(qrRoundAutoPrintControllerProvider)
              .printConfirmedRound(confirmed);
        }
        if (mounted) _notice(_copy('round_confirmed'), success: true);
        if (!printed && mounted) {
          await _offerRoundPrintRetry(confirmed);
        }
      }
      if (mounted) await _forceRefresh();
    } on ApiException catch (error) {
      if (mounted) {
        _notice(_message(error));
        await _forceRefresh();
      }
    } catch (error) {
      if (mounted) _notice('${_copy('round_awaiting')}: $error');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _offerRoundPrintRetry(QrRoundEnvelope confirmed) async {
    var retry = true;
    while (retry) {
      if (!mounted) return;
      retry =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              key: const ValueKey('qr-round-print-failed'),
              title: Text(_copy('round_print_failed')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(_copy('round_done')),
                ),
                FilledButton(
                  key: const ValueKey('qr-round-retry-print'),
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(_copy('round_retry_print')),
                ),
              ],
            ),
          ) ??
          false;
      if (retry) {
        final printed = await ref
            .read(qrRoundAutoPrintControllerProvider)
            .printConfirmedRound(confirmed);
        if (printed) {
          retry = false;
          if (mounted) _notice(_copy('round_confirmed'), success: true);
        }
      }
    }
  }

  Future<void> _clear(_TableView table) async {
    final id = int.tryParse(table.key);
    if (id == null) return _notice('This table has no server identifier.');
    await _action((service) async {
      await service.clearTable(id);
    }, '${table.label} is clear and ready.');
  }

  Future<void> _reopen(QrBoardOrder order) => _action((service) async {
    await service.reopenPayment(order.uuid);
  }, 'Payment was reopened. The QR order is active again.');

  Future<void> _fallbackAndSettle(QrBoardOrder order) async {
    if (_qrSettlementBlocked) return;
    setState(() => _acting = true);
    try {
      final recovered = await ref
          .read(qrTillServiceProvider)
          .fallbackToCounter(order.uuid);
      if (!mounted) return;
      setState(() {
        _applyOrderAction(recovered);
        _acting = false;
      });
      _notice(
        'Order moved to the attended counter. Claim it before taking payment.',
        success: true,
      );
      // The expired/null session intentionally remains orphaned. Continue the
      // exact recovered UUID in sequence; do not rely on board reclassification
      // and never route it through the cart.
      await _claimAndSettle(order.uuid);
    } on ApiException catch (error) {
      if (mounted) _notice(_message(error));
    } catch (error) {
      if (mounted) {
        _notice('The order could not be moved to the counter. $error');
      }
    } finally {
      if (mounted && _acting) setState(() => _acting = false);
    }
  }

  void _markOrderStatus(String orderUuid, String status) {
    _applyOrderAction(
      QrOrderActionResult(orderUuid: orderUuid, status: status),
    );
  }

  Widget _detail(_TableView? table) {
    if (table == null) return const _EmptyDetail();
    final order = table.row?.order ?? widget.standaloneOrder;
    final standalone = table.row == null && widget.standaloneOrder != null;
    final active =
        order != null && (order.status == 'open' || order.status == 'held')
        ? _active[order.uuid]
        : null;
    return Container(
      key: ValueKey('qr-detail-${table.key}'),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        table.label,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      if (!standalone) _StatePill(state: table.state),
                    ],
                  ),
                ),
                if (order?.receiptNumber ?? order?.tempReference
                    case final reference?)
                  _ReceiptBadge(reference),
                if (table.row?.tableDeleted == true) ...[
                  const SizedBox(width: 8),
                  const Chip(
                    avatar: Icon(Icons.archive_outlined, size: 17),
                    label: Text('Archived table'),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                if (!standalone) _StateExplanation(state: table.state),
                if (order != null) ...[
                  const SizedBox(height: 16),
                  _Totals(board: order, active: active),
                ],
                if (active != null) ...[
                  const SizedBox(height: 16),
                  _CustomerFacts(active),
                  const SizedBox(height: 16),
                  _ReadOnlyItems(active),
                ],
                if (!standalone &&
                    table.row?.pendingRounds.isNotEmpty == true) ...[
                  const SizedBox(height: 16),
                  Text(
                    _copy('rounds_awaiting'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  for (final round in table.row!.pendingRounds)
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        key: ValueKey('qr-pending-round-${round.id}'),
                        leading: const Icon(Icons.hourglass_top_rounded),
                        title: Text('${_copy('round_title')} ${round.roundNo}'),
                        trailing: Text(_money(round.totalBaisas)),
                        enabled: !_acting,
                        onTap: () => _reviewPendingRound(round),
                      ),
                    ),
                ],
              ],
            ),
          ),
          _actions(table, active),
        ],
      ),
    );
  }

  Widget _actions(_TableView table, QrActiveOrder? active) {
    final order = table.row?.order ?? widget.standaloneOrder;
    final standalone = table.row == null && widget.standaloneOrder != null;
    final actions = <Widget>[];
    final orphan =
        table.state == QrTableDisplayState.orphanedExpired ||
        table.state == QrTableDisplayState.orphanedMissingSession;
    final terminal =
        order != null &&
        const {'paid', 'voided', 'cancelled'}.contains(order.status);
    if (terminal && !standalone) {
      actions.add(
        _Action(
          key: const ValueKey('qr-action-clear'),
          label: 'Clear table',
          icon: Icons.cleaning_services_outlined,
          primary: true,
          enabled: !_acting,
          onPressed: () => _clear(table),
        ),
      );
    } else if (!standalone && orphan && order != null) {
      // `held` is the durable restart marker written by fallback.
      final recovered = order.status == 'held';
      actions.add(
        _Action(
          key: ValueKey(
            recovered ? 'qr-action-settle-recovered' : 'qr-action-fallback',
          ),
          label: recovered
              ? 'Settle recovered order'
              : 'Move to counter & settle',
          icon: recovered
              ? Icons.payments_rounded
              : Icons.move_to_inbox_rounded,
          primary: true,
          enabled: !_qrSettlementBlocked,
          onPressed: () => recovered
              ? _claimAndSettle(order.uuid)
              : _fallbackAndSettle(order),
        ),
      );
    } else if (active?.isSettleable == true &&
        (order?.status == 'open' || order?.status == 'held')) {
      actions.add(
        _Action(
          key: const ValueKey('qr-action-settle'),
          label: standalone && _arabic ? 'تسوية' : 'Settle',
          icon: Icons.payments_rounded,
          primary: true,
          enabled: !_qrSettlementBlocked,
          onPressed: () => _claimAndSettle(active!.uuid),
        ),
      );
      actions.add(
        _Action(
          key: const ValueKey('qr-action-void'),
          label: standalone && _arabic ? 'إلغاء الطلب' : 'Void',
          icon: Icons.cancel_outlined,
          enabled: !_acting,
          onPressed: () => _void(active!),
        ),
      );
    } else if (!standalone && order?.status == 'awaiting_payment') {
      actions.add(
        _Action(
          key: const ValueKey('qr-action-reopen'),
          label: 'Reopen payment',
          icon: Icons.lock_open_rounded,
          primary: true,
          enabled: !_acting,
          onPressed: () => _reopen(order!),
        ),
      );
    } else if (!standalone &&
        (table.state == QrTableDisplayState.orphanedExpired ||
            table.state == QrTableDisplayState.orphanedMissingSession)) {
      actions.add(
        _Action(
          key: const ValueKey('qr-action-clear'),
          label: 'Clear table',
          icon: Icons.cleaning_services_outlined,
          primary: true,
          enabled: !_acting,
          onPressed: () => _clear(table),
        ),
      );
    }
    if (actions.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: Color(0xFFF7FAF9),
        border: Border(top: BorderSide(color: Color(0xFFD6E0DD))),
      ),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 9),
            Expanded(child: actions[i]),
          ],
        ],
      ),
    );
  }

  Future<void> _claimAndSettle(String orderUuid) async {
    if (_qrSettlementBlocked) return;
    if (widget.openCheckout case final checkout?) {
      setState(() => _acting = true);
      try {
        await checkout(orderUuid);
        await _refresh();
      } finally {
        if (mounted) setState(() => _acting = false);
      }
      return;
    }
    setState(() {
      _acting = true;
      _claimInFlight = true;
    });
    final flow = ref.read(qrSettlementCoordinatorProvider);
    QrSettlementClaim claim;
    try {
      // Nothing that can move money is shown until the server grants this
      // atomic claim and freezes the amount.
      claim = await flow.claim(orderUuid);
    } on QrPaymentAttemptUnresolved catch (error) {
      if (mounted) {
        _notice(qrTillMessageForCode(error.code));
        setState(() {
          _acting = false;
          _claimInFlight = false;
        });
      }
      return;
    } on ApiException catch (error) {
      if (mounted) {
        _notice(_message(error));
        setState(() {
          _acting = false;
          _claimInFlight = false;
        });
      }
      return;
    } catch (error) {
      if (mounted) {
        _notice(
          'This order could not be claimed. No payment was taken. $error',
        );
        setState(() {
          _acting = false;
          _claimInFlight = false;
        });
      }
      return;
    }

    if (!mounted) {
      // A host-driven route replacement can bypass PopScope. Best-effort
      // release prevents that disposal race from stranding a live claim.
      try {
        await flow.releaseClaim(claim, QrReleaseOutcome.cancelled);
      } catch (_) {
        // There is no mounted operator surface left on which to recover.
      }
      return;
    }
    setState(() {
      _claimInFlight = false;
      _heldClaim = claim;
      _managerRecoveryRequired = false;
    });
    final choice = await showDialog<_SettlementChoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SettlementClaimDialog(claim: claim),
    );
    if (!mounted) return;

    if (choice == null || choice == _SettlementChoice.abandon) {
      try {
        await flow.releaseClaim(claim, QrReleaseOutcome.cancelled);
        if (mounted) {
          setState(() {
            _heldClaim = null;
            _markOrderStatus(claim.orderUuid, 'awaiting_payment');
          });
          _notice(
            'Settlement claim released. No payment was taken.',
            success: true,
          );
        }
      } on ApiException catch (error) {
        if (mounted) {
          await _showProcedure(
            title: 'Claim release needs a manager',
            message:
                '${_message(error)} Do not take payment until the claim is resolved.',
          );
        }
      } catch (error) {
        if (mounted) {
          await _showProcedure(
            title: 'Claim release needs a manager',
            message:
                'The claim could not be released. Do not take payment. $error',
          );
        }
      } finally {
        if (mounted) setState(() => _acting = false);
      }
      return;
    }

    try {
      final tender = choice == _SettlementChoice.cash
          ? QrTender.cash
          : QrTender.card;
      setState(() => _settlementInFlight = true);
      final result = await flow.settleClaim(claim, tender);
      final recoveryMustRemain =
          result.managerRequired || result.releaseError != null;
      if (!mounted) return;
      setState(() {
        _heldClaim = recoveryMustRemain ? result.claim : null;
        _managerRecoveryRequired = recoveryMustRemain;
        if (result.kind == QrSettlementResultKind.cardCancelledBeforeCapture ||
            result.kind == QrSettlementResultKind.cardFailedBeforeCapture ||
            result.kind == QrSettlementResultKind.cashRefusedAfterTender) {
          _markOrderStatus(orderUuid, 'awaiting_payment');
        }
      });
      await _handleSettlementResult(result);
      await _refresh();
    } on QrSettlementClaimExpired catch (error) {
      await _handlePreTenderFence(error.code, releaseError: error.releaseError);
    } on QrSettlementClaimChanged catch (error) {
      await _handlePreTenderFence(error.code, releaseError: error.releaseError);
    } on QrSettlementRevalidationFailed catch (error) {
      await _handlePreTenderFence(
        error.code,
        releaseError: error.releaseError,
        fallback: error.cause.toString(),
      );
    } on QrSettlementClaimNotHeld catch (error) {
      await _releaseLocallyMismatchedClaim(flow, claim, error.code);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _managerRecoveryRequired = true);
        await _showProcedure(
          title: 'Settlement state is unclear',
          message:
              '${_message(error)} Do not retry, release as cancelled, or take a second payment. Call a manager.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _managerRecoveryRequired = true);
        await _showProcedure(
          title: 'Settlement state is unclear',
          message:
              'Do not retry, release as cancelled, or take a second payment. Call a manager to reconcile the terminal and server before leaving this screen. $error',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _acting = false;
          _settlementInFlight = false;
        });
      }
    }
  }

  Future<void> _handlePreTenderFence(
    String? code, {
    Object? releaseError,
    String? fallback,
  }) async {
    if (mounted && releaseError == null) {
      final heldUuid = _heldClaim?.orderUuid;
      setState(() {
        _heldClaim = null;
        if (heldUuid != null) {
          _markOrderStatus(heldUuid, 'awaiting_payment');
        }
      });
    }
    if (!mounted) return;
    await _showProcedure(
      title: 'Claim changed — no payment taken',
      message:
          '${code == null ? fallback ?? 'The claim could not be revalidated.' : qrTillMessageForCode(code)} Cash/card was not started. Refresh and claim again.${releaseError == null ? '' : ' The old claim did not release; call a manager. $releaseError'}',
    );
  }

  Future<void> _releaseLocallyMismatchedClaim(
    QrSettlementFlow flow,
    QrSettlementClaim claim,
    String code,
  ) async {
    Object? releaseError;
    try {
      await flow.releaseClaim(claim, QrReleaseOutcome.cancelled);
    } catch (error) {
      releaseError = error;
    }
    if (!mounted) return;
    setState(() {
      if (releaseError == null) {
        _heldClaim = null;
        _markOrderStatus(claim.orderUuid, 'awaiting_payment');
      } else {
        _heldClaim = claim;
        _managerRecoveryRequired = true;
      }
    });
    await _showProcedure(
      title: 'Claim is no longer held locally',
      message:
          '${qrTillMessageForCode(code)} No payment was started.${releaseError == null ? ' The server claim was released; refresh before trying again.' : ' The server claim did not release. Call a manager and do not take payment. $releaseError'}',
    );
  }

  Future<void> _void(QrActiveOrder order) async {
    if (_acting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Void this QR order?'),
        content: const Text(
          'This sends a standalone void. The order will never enter the till cart, drafts, held orders, or local history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            key: const ValueKey('qr-confirm-void'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Void order'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // LAUNCH-P5 C1 — the order.void_unpaid tick, or an approver's PIN.
    final gate = await authorizeAction(
      context,
      ref,
      action: 'order.void_unpaid',
    );
    if (gate == null || !mounted) return;
    setState(() => _acting = true);
    final staff = ref.read(sessionServiceProvider).staff;
    try {
      final block = gate.block(subjectUuid: order.uuid);
      gate.grant?.forget();
      await ref
          .read(qrSettlementCoordinatorProvider)
          .voidOrder(
            order.uuid,
            reason: 'Voided from the QR Tables board',
            staffId: staff?.id,
            authorizedBy: gate.authorizedByName,
            authorization: block,
          );
      if (!mounted) return;
      _notice('QR order void queued safely.', success: true);
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) _notice(_message(error));
    } catch (error) {
      if (mounted) _notice('The QR void could not be queued. $error');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _handleSettlementResult(QrSettlementResult result) async {
    final releaseSuffix = result.releaseError == null
        ? ''
        : ' The server claim also failed to release; a manager must resolve it.';
    switch (result.kind) {
      case QrSettlementResultKind.paid:
        _notice('Payment accepted. The QR order is settled.', success: true);
        return;
      case QrSettlementResultKind.cardCancelledBeforeCapture:
        await _showProcedure(
          title: 'Card payment cancelled',
          message:
              'No card capture completed. The claim was released.$releaseSuffix',
        );
        return;
      case QrSettlementResultKind.cardFailedBeforeCapture:
        await _showProcedure(
          title: 'Card terminal did not capture',
          message:
              'No card capture completed. ${result.serverError ?? ''}$releaseSuffix',
        );
        return;
      case QrSettlementResultKind.cardUncertain:
        await _showProcedure(
          title: 'Unknown card outcome — manager required',
          message:
              'STOP. Do not retry or take a second payment. Check the terminal and bank record, then follow the manager recovery procedure.${_serverDetail(result)}$releaseSuffix',
        );
        return;
      case QrSettlementResultKind.cashRefusedAfterTender:
        await _showProcedure(
          title: 'Return the cash',
          message:
              'The server refused the payment after cash was tendered. Return the full cash amount. Do not retry this tender.${_serverDetail(result)}$releaseSuffix',
        );
        return;
      case QrSettlementResultKind.cardRefusedAfterCapture:
        await _showProcedure(
          title: 'Card may be charged — manager required',
          message:
              'STOP. Do not retry or take a second payment. Keep the customer present, verify the terminal record, and follow the manager recovery procedure.${_serverDetail(result)}$releaseSuffix',
        );
        return;
      case QrSettlementResultKind.awaitingServerAcknowledgement:
        await _showProcedure(
          title: 'Payment awaiting server acknowledgement',
          message:
              'The same durable payment event will replay after reconnect. Do not retry or take a second payment. Keep this order with a manager until it is acknowledged.${_serverDetail(result)}',
        );
        return;
    }
  }

  String _serverDetail(QrSettlementResult result) {
    final detail = result.serverError?.trim();
    return detail == null || detail.isEmpty ? '' : ' Server detail: $detail';
  }

  Future<void> _showProcedure({
    required String title,
    required String message,
  }) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      key: const ValueKey('qr-settlement-procedure'),
      icon: const Icon(
        Icons.warning_amber_rounded,
        color: Color(0xFFB42318),
        size: 42,
      ),
      title: Text(title),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('I understand'),
        ),
      ],
    ),
  );

  Future<void> _requestRouteExit() async {
    if (_settlementInFlight) {
      _notice(
        'Payment is in progress. Do not leave or retry until its result is known.',
      );
      return;
    }
    if (_claimInFlight) {
      _notice(
        'The server claim is still in progress. Wait for it to finish before leaving.',
      );
      return;
    }
    final claim = _heldClaim;
    if (claim == null) {
      await Navigator.maybePop(context);
      return;
    }
    if (_managerRecoveryRequired) {
      final takenOver = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          key: const ValueKey('qr-manager-takeover-warning'),
          title: const Text('Manager recovery is required'),
          content: const Text(
            'The tender outcome may be unknown. Do not release this claim as cancelled. A manager must reconcile the terminal and server and take ownership of this order before the screen closes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Stay'),
            ),
            FilledButton(
              key: const ValueKey('qr-manager-took-over'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Manager has taken over'),
            ),
          ],
        ),
      );
      if (takenOver == true && mounted) {
        final navigator = Navigator.of(context);
        ref
            .read(qrSettlementCoordinatorProvider)
            .acknowledgeManagerRecovery(claim.orderUuid);
        setState(() {
          _managerRecoveryRequired = false;
          _heldClaim = null;
        });
        // Programmatic manager takeover has already satisfied the PopScope
        // guard. Avoid maybePop re-entering the stale pre-rebuild guard.
        if (navigator.canPop()) navigator.pop();
      }
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('qr-route-abandon-warning'),
        title: const Text('Release the settlement claim?'),
        content: const Text(
          'No payment has been taken. This screen cannot close until the live server claim is released.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            key: const ValueKey('qr-route-confirm-release'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Release and leave'),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    try {
      await ref
          .read(qrSettlementCoordinatorProvider)
          .releaseClaim(claim, QrReleaseOutcome.cancelled);
      if (!mounted) return;
      setState(() {
        _heldClaim = null;
        _markOrderStatus(claim.orderUuid, 'awaiting_payment');
      });
      await Navigator.maybePop(context);
    } catch (error) {
      if (mounted) {
        await _showProcedure(
          title: 'Claim release needs a manager',
          message:
              'The claim could not be released, so this screen remains open. Do not take payment. $error',
        );
      }
    }
  }
}

enum _SettlementChoice { cash, card, abandon }

class _SettlementClaimDialog extends StatefulWidget {
  const _SettlementClaimDialog({required this.claim});

  final QrSettlementClaim claim;

  @override
  State<_SettlementClaimDialog> createState() => _SettlementClaimDialogState();
}

class _SettlementClaimDialogState extends State<_SettlementClaimDialog> {
  Timer? _deadlineTimer;
  late bool _expired;

  @override
  void initState() {
    super.initState();
    final remaining = widget.claim.deadlineAt
        .subtract(const Duration(seconds: 5))
        .difference(DateTime.now());
    _expired = remaining <= Duration.zero;
    if (!_expired) {
      _deadlineTimer = Timer(remaining, () {
        if (mounted) setState(() => _expired = true);
      });
    }
  }

  @override
  void dispose() {
    _deadlineTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_confirmAbandon(context));
    },
    child: AlertDialog(
      key: const ValueKey('qr-settlement-sheet'),
      title: const Text('Standalone QR settlement'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'SERVER-FROZEN AMOUNT',
              style: TextStyle(
                color: Color(0xFF087A68),
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
            if (widget.claim.receiptNumber ?? widget.claim.tempReference
                case final reference?)
              Text(reference, key: const ValueKey('qr-claim-reference')),
            Text(
              _money(widget.claim.frozenAmountBaisas),
              key: const ValueKey('qr-frozen-amount'),
              style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text('Claim valid until ${widget.claim.deadlineAt.toLocal()}'),
            const SizedBox(height: 14),
            if (_expired)
              Container(
                key: const ValueKey('qr-claim-expired'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE9E7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'This claim expired. Cash and card are disabled. Release it, refresh the order, and claim again. No payment has been taken.',
                  style: TextStyle(
                    color: Color(0xFF8F2118),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            else
              const Text(
                'Choose one bare tender. The amount and server-priced order cannot be edited here.',
              ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('qr-tender-cash'),
                    onPressed: _expired
                        ? null
                        : () => Navigator.pop(context, _SettlementChoice.cash),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Cash'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('qr-tender-card'),
                    onPressed: _expired
                        ? null
                        : () => Navigator.pop(context, _SettlementChoice.card),
                    icon: const Icon(Icons.contactless_rounded),
                    label: const Text('Card'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          key: const ValueKey('qr-abandon-claim'),
          onPressed: () => _confirmAbandon(context),
          icon: const Icon(Icons.logout_rounded),
          label: Text(
            _expired ? 'Release expired claim' : 'Release claim and leave',
          ),
        ),
      ],
    ),
  );

  Future<void> _confirmAbandon(BuildContext context) async {
    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('qr-abandon-warning'),
        title: const Text('Leave this claimed settlement?'),
        content: const Text(
          'No payment has been taken. Leaving must release the server claim before another till can settle this order.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Continue settlement'),
          ),
          FilledButton(
            key: const ValueKey('qr-confirm-abandon'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Release and leave'),
          ),
        ],
      ),
    );
    if (leave == true && context.mounted) {
      Navigator.pop(context, _SettlementChoice.abandon);
    }
  }
}

class _TableView {
  const _TableView({
    required this.key,
    required this.floorId,
    required this.label,
    this.row,
  });
  final String key;
  final String floorId;
  final String label;
  final QrTableBoardRow? row;
  QrTableDisplayState get state => qrTableDisplayStateFor(row);
}


class _StatePill extends StatelessWidget {
  const _StatePill({required this.state});
  final QrTableDisplayState state;
  @override
  Widget build(BuildContext context) {
    final color = _stateColor(state);
    return Container(
      key: ValueKey('qr-state-${state.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        _stateLabel(state),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}


class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();
  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    child: const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app_outlined, size: 50, color: Color(0xFF8EA09B)),
          SizedBox(height: 10),
          Text(
            'Select a table',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          Text('Read-only details and safe actions appear here.'),
        ],
      ),
    ),
  );
}

class _StateExplanation extends StatelessWidget {
  const _StateExplanation({required this.state});
  final QrTableDisplayState state;
  @override
  Widget build(BuildContext context) {
    final color = _stateColor(state);
    final body = switch (state) {
      QrTableDisplayState.free => 'No QR session or unpaid order exists.',
      QrTableDisplayState.awaitingFirstScan =>
        'A QR session is open and waiting for its first customer scan.',
      QrTableDisplayState.active =>
        'The customer may still add server-priced rounds. This view is read-only.',
      QrTableDisplayState.paymentRequested =>
        'Use only the actions below. Never import this order into the till cart.',
      QrTableDisplayState.orphanedExpired =>
        'The unpaid order outlived its QR session and needs attended recovery.',
      QrTableDisplayState.orphanedMissingSession =>
        'The opening device was removed; the surviving order needs attended recovery.',
    };
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(_stateIcon(state), color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(body)),
        ],
      ),
    );
  }
}

class _ReceiptBadge extends StatelessWidget {
  const _ReceiptBadge(this.value);
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF087A68),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Text(
      value,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _Totals extends StatelessWidget {
  const _Totals({required this.board, this.active});
  final QrBoardOrder board;
  final QrActiveOrder? active;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (active != null) ...[
        _row('Subtotal', active!.subtotalBaisas),
        if (active!.discountTotalBaisas != 0)
          _row('Discount', -active!.discountTotalBaisas),
        if (active!.compTotalBaisas != 0)
          _row('Comp', -active!.compTotalBaisas),
        _row('Tax', active!.taxTotalBaisas),
      ],
      const Divider(),
      _row(
        'Server total',
        active?.grandTotalBaisas ?? board.acceptedTotalBaisas,
        bold: true,
      ),
    ],
  );

  Widget _row(String label, int amount, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w500,
            ),
          ),
        ),
        Text(
          _money(amount),
          style: TextStyle(
            fontWeight: bold ? FontWeight.w900 : FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class _CustomerFacts extends StatelessWidget {
  const _CustomerFacts(this.order);
  final QrActiveOrder order;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    children: [
      Chip(
        avatar: const Icon(Icons.badge_outlined, size: 18),
        label: Text('Customer ID ${order.customerId ?? '—'}'),
      ),
      Chip(
        avatar: const Icon(Icons.directions_car_outlined, size: 18),
        label: Text('Plate ${order.plateNumber ?? '—'}'),
      ),
    ],
  );
}

class _ReadOnlyItems extends StatelessWidget {
  const _ReadOnlyItems(this.order);
  final QrActiveOrder order;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'SERVER-PRICED ITEMS · READ ONLY',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
      ),
      for (final item in order.items)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(child: Text(_qty(item.quantity))),
          title: Text(
            item.name,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: item.addons.isEmpty && item.combo.isEmpty
              ? (item.notes == null ? null : Text(item.notes!))
              : Text(
                  [
                    // LAUNCH-P4 C7 — a combo's chosen items.
                    ...serverComboLabels(
                      {'combo': item.combo},
                      arabic:
                          Localizations.localeOf(context).languageCode == 'ar',
                    ),
                    ...item.addons.map((addon) => addon.name),
                  ].join(', '),
                ),
          trailing: Text(_money(item.lineTotalBaisas)),
        ),
    ],
  );
}

class _Action extends StatelessWidget {
  const _Action({
    super.key,
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
    this.primary = false,
  });
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;
  final bool primary;
  @override
  Widget build(BuildContext context) => primary
      ? FilledButton.icon(
          onPressed: enabled ? onPressed : null,
          icon: Icon(icon),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF087A68),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        )
      : OutlinedButton.icon(
          onPressed: enabled ? onPressed : null,
          icon: Icon(icon),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        );
}

Color _stateColor(QrTableDisplayState state) => switch (state) {
  QrTableDisplayState.free => const Color(0xFF157348),
  QrTableDisplayState.awaitingFirstScan => const Color(0xFF8B6900),
  QrTableDisplayState.active => const Color(0xFF076C98),
  QrTableDisplayState.paymentRequested => const Color(0xFF6B3FA0),
  QrTableDisplayState.orphanedExpired => const Color(0xFFB84B00),
  QrTableDisplayState.orphanedMissingSession => const Color(0xFFB42318),
};

IconData _stateIcon(QrTableDisplayState state) => switch (state) {
  QrTableDisplayState.free => Icons.check_circle_outline_rounded,
  QrTableDisplayState.awaitingFirstScan => Icons.qr_code_scanner_rounded,
  QrTableDisplayState.active => Icons.restaurant_rounded,
  QrTableDisplayState.paymentRequested => Icons.payments_outlined,
  QrTableDisplayState.orphanedExpired => Icons.warning_amber_rounded,
  QrTableDisplayState.orphanedMissingSession => Icons.link_off_rounded,
};

String _stateLabel(QrTableDisplayState state) => switch (state) {
  QrTableDisplayState.free => 'Free',
  QrTableDisplayState.awaitingFirstScan => 'Awaiting scan',
  QrTableDisplayState.active => 'Active',
  QrTableDisplayState.paymentRequested => 'Payment requested',
  QrTableDisplayState.orphanedExpired => 'Expired orphan',
  QrTableDisplayState.orphanedMissingSession => 'Deleted-opener orphan',
};

String _money(int baisas) => 'OMR ${(baisas / 1000).toStringAsFixed(3)}';

String _qty(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);
