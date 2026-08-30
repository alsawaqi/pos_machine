import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pos_models.dart';
import '../models/qr_till_models.dart';
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

/// Staff-only QR table board. It reads table/floor configuration but never
/// touches PosController or the local DiningTableSession occupancy store.
class QrTablesScreen extends ConsumerStatefulWidget {
  const QrTablesScreen({
    super.key,
    required this.floors,
    required this.tables,
    this.pollInterval = const Duration(seconds: 10),
    this.clock,
  });

  final List<DiningFloor> floors;
  final List<DiningTableDefinition> tables;
  final Duration pollInterval;
  final DateTime Function()? clock;

  @override
  ConsumerState<QrTablesScreen> createState() => _QrTablesScreenState();
}

class _QrTablesScreenState extends ConsumerState<QrTablesScreen>
    with WidgetsBindingObserver {
  static const _archivedFloor = '__archived_qr_tables__';

  Timer? _pollTimer;
  List<QrTableBoardRow> _board = const [];
  Map<String, QrActiveOrder> _active = const {};
  String? _floorId;
  String? _tableKey;
  bool _foreground = true;
  bool _refreshing = false;
  bool _acting = false;
  bool _claimInFlight = false;
  bool _settlementInFlight = false;
  bool _managerRecoveryRequired = false;
  QrSettlementClaim? _heldClaim;
  String? _error;
  DateTime? _updatedAt;
  DateTime? _lastBoardFetchAt;
  DateTime? _lastActiveFetchAt;
  bool _backingOff = false;

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _floorId = widget.floors.firstOrNull?.id;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      // Keep a Retry-After timer alive only as a clock. Its callback cannot
      // request in the background, and resume still cannot bypass it.
      if (!_backingOff) {
        _pollTimer?.cancel();
        _pollTimer = null;
      }
    } else {
      _refresh();
    }
  }

  void _schedule([Duration? serverDelay]) {
    _pollTimer?.cancel();
    if (!mounted || !_foreground) return;
    final candidate = serverDelay ?? widget.pollInterval;
    final delay = candidate < widget.pollInterval
        ? widget.pollInterval
        : candidate;
    _pollTimer = Timer(delay, _refresh);
  }

  Future<void> _refresh() async {
    if (!mounted || !_foreground || _refreshing || _backingOff) return;
    _pollTimer?.cancel();
    setState(() => _refreshing = true);
    Duration? retryAfter;
    try {
      final service = ref.read(qrTillServiceProvider);
      final now = _now();
      var board = _board;
      if (_lastBoardFetchAt == null ||
          now.difference(_lastBoardFetchAt!) >= widget.pollInterval) {
        // Record the attempt before awaiting so overlapping UI events cannot
        // create a second request inside the ten-second budget.
        _lastBoardFetchAt = now;
        board = await service.fetchTableBoard();
      }
      Map<String, QrActiveOrder> active = _active;
      final selected = _selectedBoardRow(board);
      if ((selected?.order?.status == 'open' ||
              selected?.order?.status == 'held') &&
          (_lastActiveFetchAt == null ||
              now.difference(_lastActiveFetchAt!) >= widget.pollInterval)) {
        _lastActiveFetchAt = now;
        final rows = await service.fetchActiveQrOrders();
        // Branch-active reads include main_pos orders. Drop them at the seam:
        // a non-QR order must never reach this board or its action handlers.
        active = {
          for (final order in rows)
            if (order.isQrWeb) order.uuid: order,
        };
      }
      if (!mounted) return;
      setState(() {
        _board = board;
        _active = active;
        _updatedAt = _now();
        _error = null;
        _repairSelection();
      });
    } on ApiException catch (error) {
      if (error.statusCode == 429) {
        retryAfter = error.retryAfter;
      }
      if (mounted) setState(() => _error = _message(error));
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not refresh QR tables. $error');
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
      if (retryAfter != null) {
        _pollTimer?.cancel();
        _backingOff = true;
        final delay = retryAfter < widget.pollInterval
            ? widget.pollInterval
            : retryAfter;
        _pollTimer = Timer(delay, () {
          _backingOff = false;
          _refresh();
        });
      } else {
        _schedule();
      }
    }
  }

  QrTableBoardRow? _selectedBoardRow(List<QrTableBoardRow> rows) {
    final key = _tableKey;
    if (key == null) return null;
    for (final row in rows) {
      if ('${row.tableId}' == key) return row;
    }
    return null;
  }

  List<_TableView> get _tables {
    final live = <String, QrTableBoardRow>{
      for (final row in _board) '${row.tableId}': row,
    };
    final result = <_TableView>[
      for (final table in widget.tables)
        _configuredTableView(table, live.remove(table.id)),
    ];
    // Soft-deleted tables are absent from config. The board still exposes the
    // recovery root but not its floor, so keep it in an explicit archive.
    result.addAll(
      live.values.map(
        (row) => _TableView(
          key: '${row.tableId}',
          floorId: _archivedFloor,
          label: row.tableLabel,
          row: row,
        ),
      ),
    );
    return result;
  }

  _TableView _configuredTableView(
    DiningTableDefinition table,
    QrTableBoardRow? row,
  ) => _TableView(
    key: table.id,
    floorId: row?.tableDeleted == true ? _archivedFloor : table.floorId,
    label: table.name,
    row: row,
  );

  List<(String, String)> get _floors => [
    for (final floor in widget.floors) (floor.id, floor.label),
    if (_tables.any((table) => table.floorId == _archivedFloor))
      (_archivedFloor, 'Archived tables'),
  ];

  _TableView? get _selectedTable {
    final key = _tableKey;
    if (key == null) return null;
    for (final table in _tables) {
      if (table.key == key) return table;
    }
    return null;
  }

  void _repairSelection() {
    if (_tableKey != null && !_tables.any((table) => table.key == _tableKey)) {
      _tableKey = null;
    }
    if (_floorId == null || !_floors.any((floor) => floor.$1 == _floorId)) {
      _floorId = _floors.firstOrNull?.$1;
    }
  }

  void _select(_TableView table) {
    setState(() => _tableKey = table.key);
    if (table.row?.order?.status == 'open' ||
        table.row?.order?.status == 'held') {
      _refresh();
    }
  }

  String _message(ApiException error) {
    if (error.code == null) return error.message;
    return qrTillMessageForCode(error.code);
  }

  void _notice(String text, {bool success = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: success
              ? const Color(0xFF12694F)
              : const Color(0xFF9B2C2C),
          content: Text(text),
        ),
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
    if (_acting) return;
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

  void _applyOrderAction(QrOrderActionResult result) {
    _board = [
      for (final row in _board)
        if (row.order?.uuid == result.orderUuid)
          QrTableBoardRow(
            tableId: row.tableId,
            tableLabel: row.tableLabel,
            tableStatus: row.tableStatus,
            tableDeleted: row.tableDeleted,
            orphaned: row.orphaned,
            pendingRounds: row.pendingRounds,
            sessionUuid: row.sessionUuid,
            sessionStatus: result.sessionStatus ?? row.sessionStatus,
            expiresAt: row.expiresAt,
            order: QrBoardOrder(
              uuid: row.order!.uuid,
              status: result.status,
              receiptNumber: result.receiptNumber ?? row.order!.receiptNumber,
              acceptedTotalBaisas: row.order!.acceptedTotalBaisas,
            ),
          )
        else
          row,
    ];
  }

  void _markOrderStatus(String orderUuid, String status) {
    _applyOrderAction(
      QrOrderActionResult(orderUuid: orderUuid, status: status),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _tables
        .where((table) => table.floorId == _floorId)
        .toList(growable: false);
    return PopScope(
      canPop: !_claimInFlight && !_settlementInFlight && _heldClaim == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestRouteExit());
      },
      child: Scaffold(
        key: const ValueKey('qr-tables-screen'),
        backgroundColor: const Color(0xFFF2F7F6),
        body: SafeArea(
          child: Column(
            children: [
              _header(),
              if (_error != null)
                MaterialBanner(
                  key: const ValueKey('qr-board-error'),
                  content: Text(_error!),
                  leading: const Icon(Icons.wifi_off_rounded),
                  actions: [
                    TextButton(
                      onPressed: _refresh,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(flex: 7, child: _boardGrid(visible)),
                    const VerticalDivider(width: 1),
                    Expanded(flex: 5, child: _detail(_selectedTable)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
    child: Column(
      children: [
        Row(
          children: [
            IconButton.filledTonal(
              key: const ValueKey('qr-board-back'),
              onPressed: _settlementInFlight ? null : _requestRouteExit,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 12),
            const Icon(
              Icons.qr_code_2_rounded,
              size: 34,
              color: Color(0xFF087A68),
            ),
            const SizedBox(width: 8),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QR tables',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                Text('Server orders · read-only till surface'),
              ],
            ),
            const Spacer(),
            if (_updatedAt != null)
              Text(
                'Updated ${TimeOfDay.fromDateTime(_updatedAt!).format(context)}',
              ),
            const SizedBox(width: 10),
            IconButton.outlined(
              key: const ValueKey('qr-board-refresh'),
              onPressed: _refreshing ? null : _refresh,
              icon: _refreshing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final floor in _floors)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          key: ValueKey('qr-floor-${floor.$1}'),
                          label: Text(floor.$2),
                          selected: floor.$1 == _floorId,
                          onSelected: (_) => setState(() {
                            _floorId = floor.$1;
                            _tableKey = null;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const _Legend(),
          ],
        ),
      ],
    ),
  );

  Widget _boardGrid(List<_TableView> tables) {
    if (_refreshing && _board.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tables.isEmpty) {
      return const Center(
        child: Text('No tables are configured on this floor.'),
      );
    }
    return GridView.builder(
      key: const ValueKey('qr-board-grid'),
      padding: const EdgeInsets.all(18),
      itemCount: tables.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 13,
        mainAxisSpacing: 13,
        childAspectRatio: 1.45,
      ),
      itemBuilder: (_, index) => _TableCard(
        table: tables[index],
        selected: tables[index].key == _tableKey,
        onTap: () => _select(tables[index]),
      ),
    );
  }

  Widget _detail(_TableView? table) {
    if (table == null) return const _EmptyDetail();
    final order = table.row?.order;
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
                      _StatePill(state: table.state),
                    ],
                  ),
                ),
                if (order?.receiptNumber != null)
                  _ReceiptBadge(order!.receiptNumber!),
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
                _StateExplanation(state: table.state),
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
                if (table.row?.pendingRounds.isNotEmpty == true) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Rounds awaiting confirmation',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  for (final round in table.row!.pendingRounds)
                    ListTile(
                      leading: const Icon(Icons.hourglass_top_rounded),
                      title: Text('Round ${round.roundNo}'),
                      trailing: Text(_money(round.totalBaisas)),
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
    final order = table.row?.order;
    final actions = <Widget>[];
    final orphan =
        table.state == QrTableDisplayState.orphanedExpired ||
        table.state == QrTableDisplayState.orphanedMissingSession;
    final terminal =
        order != null &&
        const {'paid', 'voided', 'cancelled'}.contains(order.status);
    if (terminal) {
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
    } else if (orphan && order != null) {
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
          enabled: !_acting,
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
          label: 'Settle',
          icon: Icons.payments_rounded,
          primary: true,
          enabled: !_acting,
          onPressed: () => _claimAndSettle(active!.uuid),
        ),
      );
      actions.add(
        _Action(
          key: const ValueKey('qr-action-void'),
          label: 'Void',
          icon: Icons.cancel_outlined,
          enabled: !_acting,
          onPressed: () => _void(active!),
        ),
      );
    } else if (order?.status == 'awaiting_payment') {
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
    } else if (table.state == QrTableDisplayState.orphanedExpired ||
        table.state == QrTableDisplayState.orphanedMissingSession) {
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
    if (_acting) return;
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
      if (!mounted) return;
      final recoveryMustRemain =
          result.kind == QrSettlementResultKind.awaitingServerAcknowledgement ||
          result.releaseError != null;
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
    setState(() => _acting = true);
    final staff = ref.read(sessionServiceProvider).staff;
    try {
      await ref
          .read(qrSettlementCoordinatorProvider)
          .voidOrder(
            order.uuid,
            reason: 'Voided from the QR Tables board',
            staffId: staff?.id,
            authorizedBy: staff?.name,
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
        setState(() {
          _managerRecoveryRequired = false;
          _heldClaim = null;
        });
        await Navigator.maybePop(context);
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

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.selected,
    required this.onTap,
  });
  final _TableView table;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _stateColor(table.state);
    final order = table.row?.order;
    return Material(
      key: ValueKey('qr-table-${table.key}'),
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: color, width: selected ? 3 : 1),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      table.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Icon(_stateIcon(table.state), color: color),
                ],
              ),
              const SizedBox(height: 7),
              _StatePill(state: table.state),
              if (table.row?.tableDeleted == true) ...[
                const SizedBox(height: 5),
                const Row(
                  children: [
                    Icon(Icons.archive_outlined, size: 14),
                    SizedBox(width: 4),
                    Text('Archived table', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ],
              const Spacer(),
              if (order != null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        order.receiptNumber ?? 'QR order',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _money(order.acceptedTotalBaisas),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                )
              else
                const Text(
                  'No accepted order',
                  style: TextStyle(color: Color(0xFF687873)),
                ),
            ],
          ),
        ),
      ),
    );
  }
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

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 7,
    children: [
      for (final state in QrTableDisplayState.values)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: _stateColor(state)),
            const SizedBox(width: 3),
            Text(_stateLabel(state), style: const TextStyle(fontSize: 10)),
          ],
        ),
    ],
  );
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
          subtitle: item.addons.isEmpty
              ? (item.notes == null ? null : Text(item.notes!))
              : Text(item.addons.map((addon) => addon.name).join(', ')),
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
