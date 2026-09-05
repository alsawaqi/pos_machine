import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pos_models.dart';
import '../models/qr_till_models.dart';
import '../providers/providers.dart';
import '../services/pos_api_service.dart';
import '../services/qr_till_messages.dart';
import '../widgets/qr_table_money_panel.dart';

export '../widgets/qr_table_money_panel.dart'
    show QrTableDisplayState, qrTableDisplayStateFor;

/// Staff-only QR table board. It reads table/floor configuration but never
/// touches PosController or the local DiningTableSession occupancy store.
/// Its only sanctioned writes are standalone QR settlement/table recovery and
/// server-owned pending-round confirmation/rejection; QR orders never enter
/// the local cart, draft, held, or history stores.
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
    with WidgetsBindingObserver
    implements QrTableMoneyHost {
  static const _archivedFloor = '__archived_qr_tables__';

  Timer? _pollTimer;
  List<QrTableBoardRow> _board = const [];
  Map<String, QrActiveOrder> _active = const {};
  String? _floorId;
  String? _tableKey;
  bool _foreground = true;
  bool _refreshing = false;
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

  Future<void> _forceRefresh() {
    _lastBoardFetchAt = null;
    _lastActiveFetchAt = null;
    return _refresh();
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
    return qrTillMessageForCode(
      error.code,
      arabic: ref.read(settingsControllerProvider).language == 'ar',
    );
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

  @override
  QrTableBoardRow? get row => _selectedTable?.row;

  @override
  QrActiveOrder? get active => _active[row?.order?.uuid];

  @override
  bool get arabic => ref.read(settingsControllerProvider).language == 'ar';

  @override
  void notice(String text, {bool success = false}) =>
      _notice(text, success: success);

  @override
  Future<void> refresh() => _refresh();

  @override
  void applyOrderAction(QrOrderActionResult result) {
    setState(() => _applyOrderAction(result));
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
              tempReference: result.tempReference ?? row.order!.tempReference,
              acceptedTotalBaisas: row.order!.acceptedTotalBaisas,
            ),
          )
        else
          row,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final visible = _tables
        .where((table) => table.floorId == _floorId)
        .toList(growable: false);
    return QrTableMoneyPanel(
      host: this,
      tableKey: _selectedTable?.key,
      tableLabel: _selectedTable?.label,
      forceRefresh: _forceRefresh,
      builder: (context, detail, requestRouteExit, settlementInFlight) => Scaffold(
        key: const ValueKey('qr-tables-screen'),
        backgroundColor: const Color(0xFFF2F7F6),
        body: SafeArea(
          child: Column(
            children: [
              _header(requestRouteExit, settlementInFlight),
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
                    Expanded(flex: 5, child: detail),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(Future<void> Function() requestRouteExit, bool settlementInFlight) => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
    child: Column(
      children: [
        Row(
          children: [
            IconButton.filledTonal(
              key: const ValueKey('qr-board-back'),
              onPressed: settlementInFlight ? null : requestRouteExit,
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
                        order.receiptNumber ?? order.tempReference ?? 'QR order',
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
