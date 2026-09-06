import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/pos_models.dart';
import '../models/qr_till_models.dart';
import '../services/pos_api_service.dart';
import '../services/qr_till_messages.dart';
import '../services/qr_till_service.dart';

/// Read-only QR board/detail polling shared by the legacy tab and table sheet.
/// It starts only when a host requests refresh; the host owns app lifecycle.
class QrBoardFeed extends ChangeNotifier {
  QrBoardFeed(
    QrTillGateway service, {
    this.pollInterval = const Duration(seconds: 10),
    this.clock,
    List<DiningFloor> floors = const [],
    List<DiningTableDefinition> tables = const [],
    bool Function()? arabic,
    QrTillGateway Function()? readService,
  }) : _service = service,
       _configuredFloors = floors,
       _configuredTables = tables,
       _arabic = arabic,
       _readService = readService,
       _floorId = floors.firstOrNull?.id;

  static const _archivedFloor = '__archived_qr_tables__';

  final QrTillGateway _service;
  Duration pollInterval;
  final DateTime Function()? clock;
  final bool Function()? _arabic;
  final QrTillGateway Function()? _readService;
  List<DiningFloor> _configuredFloors;
  List<DiningTableDefinition> _configuredTables;
  bool _disposed = false;
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

  List<QrTableBoardRow> get board => _board;
  Map<String, QrActiveOrder> get active => _active;
  String? get error => _error;
  DateTime? get updatedAt => _updatedAt;
  bool get refreshing => _refreshing;
  String? get selectedKey => _tableKey;
  String? get floorId => _floorId;
  QrTableBoardRow? get selectedRow => _selectedBoardRow(_board);
  QrBoardTableView? get selectedTable => _selectedTable;
  List<QrBoardTableView> get tableViews => _tables;
  List<(String, String)> get floorViews => _floors;

  DateTime _now() => clock?.call() ?? DateTime.now();

  void _change(VoidCallback update) {
    update();
    notifyListeners();
  }

  /// Config changes do not repair selection until a successful board refresh,
  /// matching the tab's original widget-backed projection.
  void updateConfiguration({
    required List<DiningFloor> floors,
    required List<DiningTableDefinition> tables,
    Duration? pollInterval,
  }) {
    _configuredFloors = floors;
    _configuredTables = tables;
    if (pollInterval != null) this.pollInterval = pollInterval;
  }

  void select(String tableId) {
    final table = _tables.where((table) => table.key == tableId).firstOrNull;
    if (table == null) {
      _change(() => _tableKey = tableId);
      return;
    }
    _select(table);
  }

  void selectTable(QrBoardTableView table) => _select(table);

  void selectFloor(String floorId) {
    _change(() {
      _floorId = floorId;
      _tableKey = null;
    });
  }

  Future<void> refresh() => _refresh();
  Future<void> forceRefresh() => _forceRefresh();
  void applyOrderAction(QrOrderActionResult result) =>
      _change(() => _applyOrderAction(result));

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    super.dispose();
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
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
    if (_disposed || !_foreground) return;
    final candidate = serverDelay ?? pollInterval;
    final delay = candidate < pollInterval
        ? pollInterval
        : candidate;
    _pollTimer = Timer(delay, _refresh);
  }

  Future<void> _refresh() async {
    if (_disposed || !_foreground || _refreshing || _backingOff) return;
    _pollTimer?.cancel();
    _change(() => _refreshing = true);
    Duration? retryAfter;
    try {
      final service = _readService?.call() ?? _service;
      final now = _now();
      var board = _board;
      if (_lastBoardFetchAt == null ||
          now.difference(_lastBoardFetchAt!) >= pollInterval) {
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
              now.difference(_lastActiveFetchAt!) >= pollInterval)) {
        _lastActiveFetchAt = now;
        final rows = await service.fetchActiveQrOrders();
        // Branch-active reads include main_pos orders. Drop them at the seam:
        // a non-QR order must never reach this board or its action handlers.
        active = {
          for (final order in rows)
            if (order.isQrWeb) order.uuid: order,
        };
      }
      if (_disposed) return;
      _change(() {
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
      if (!_disposed) _change(() => _error = _message(error));
    } catch (error) {
      if (!_disposed) {
        _change(() => _error = 'Could not refresh QR tables. $error');
      }
    } finally {
      if (!_disposed) _change(() => _refreshing = false);
      if (retryAfter != null) {
        _pollTimer?.cancel();
        _backingOff = true;
        final delay = retryAfter < pollInterval
            ? pollInterval
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

  List<QrBoardTableView> get _tables {
    final live = <String, QrTableBoardRow>{
      for (final row in _board) '${row.tableId}': row,
    };
    final result = <QrBoardTableView>[
      for (final table in _configuredTables)
        _configuredTableView(table, live.remove(table.id)),
    ];
    // Soft-deleted tables are absent from config. The board still exposes the
    // recovery root but not its floor, so keep it in an explicit archive.
    result.addAll(
      live.values.map(
        (row) => QrBoardTableView(
          key: '${row.tableId}',
          floorId: _archivedFloor,
          label: row.tableLabel,
          row: row,
        ),
      ),
    );
    return result;
  }

  QrBoardTableView _configuredTableView(
    DiningTableDefinition table,
    QrTableBoardRow? row,
  ) => QrBoardTableView(
    key: table.id,
    floorId: row?.tableDeleted == true ? _archivedFloor : table.floorId,
    label: table.name,
    row: row,
  );

  List<(String, String)> get _floors => [
    for (final floor in _configuredFloors) (floor.id, floor.label),
    if (_tables.any((table) => table.floorId == _archivedFloor))
      (_archivedFloor, 'Archived tables'),
  ];

  QrBoardTableView? get _selectedTable {
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

  void _select(QrBoardTableView table) {
    _change(() => _tableKey = table.key);
    if (table.row?.order?.status == 'open' ||
        table.row?.order?.status == 'held') {
      _refresh();
    }
  }

  String _message(ApiException error) {
    if (error.code == null) return error.message;
    return qrTillMessageForCode(
      error.code,
      arabic: _arabic?.call() ?? false,
    );
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
}

class QrBoardTableView {
  const QrBoardTableView({
    required this.key,
    required this.floorId,
    required this.label,
    this.row,
  });

  final String key;
  final String floorId;
  final String label;
  final QrTableBoardRow? row;
}
