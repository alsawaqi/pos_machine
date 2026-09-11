import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/qr_board_feed.dart';
import '../models/pos_models.dart';
import '../models/qr_till_models.dart';
import '../providers/providers.dart';
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
    this.openCheckout,
  });

  final List<DiningFloor> floors;
  final List<DiningTableDefinition> tables;
  final Duration pollInterval;
  final DateTime Function()? clock;
  final Future<void> Function(String)? openCheckout;

  @override
  ConsumerState<QrTablesScreen> createState() => _QrTablesScreenState();
}

class _QrTablesScreenState extends ConsumerState<QrTablesScreen>
    with WidgetsBindingObserver
    implements QrTableMoneyHost {
  late final QrBoardFeed _feed;

  List<QrTableBoardRow> get _board => _feed.board;
  Map<String, QrActiveOrder> get _active => _feed.active;
  String? get _floorId => _feed.floorId;
  String? get _tableKey => _feed.selectedKey;
  bool get _refreshing => _feed.refreshing;
  String? get _error => _feed.error;
  DateTime? get _updatedAt => _feed.updatedAt;
  List<_TableView> get _tables => _feed.tableViews;
  List<(String, String)> get _floors => _feed.floorViews;
  _TableView? get _selectedTable => _feed.selectedTable;

  @override
  void initState() {
    super.initState();
    _feed = QrBoardFeed(
      ref.read(qrTillServiceProvider),
      pollInterval: widget.pollInterval,
      clock: () => widget.clock?.call() ?? DateTime.now(),
      floors: widget.floors,
      tables: widget.tables,
      arabic: () => ref.read(settingsControllerProvider).language == 'ar',
      readService: () => ref.read(qrTillServiceProvider),
    )..addListener(_feedChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant QrTablesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _feed.updateConfiguration(
      floors: widget.floors,
      tables: widget.tables,
      pollInterval: widget.pollInterval,
    );
  }

  void _feedChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _feed
      ..removeListener(_feedChanged)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _feed.setForeground(state == AppLifecycleState.resumed);

  Future<void> _refresh() => _feed.refresh();
  Future<void> _forceRefresh() => _feed.forceRefresh();
  void _select(_TableView table) => _feed.selectTable(table);

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
  void applyOrderAction(QrOrderActionResult result) =>
      _feed.applyOrderAction(result);

  @override
  Widget build(BuildContext context) {
    final visible = _tables
        .where((table) => table.floorId == _floorId)
        .toList(growable: false);
    return QrTableMoneyPanel(
      host: this,
      openCheckout: widget.openCheckout,
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
                          onSelected: (_) => _feed.selectFloor(floor.$1),
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

typedef _TableView = QrBoardTableView;

extension on QrBoardTableView {
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
