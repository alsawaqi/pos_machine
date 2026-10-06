import 'pos_api_service.dart';

abstract interface class TableShadowGateway {
  Future<List<Map<String, dynamic>>> fetchBoard();
  Future<TableShadowFeed> fetchFeed({required int after, int limit = 100});
}

class TableShadowFeed {
  const TableShadowFeed({
    required this.events,
    required this.latestId,
    required this.hasMore,
  });
  final List<TableShadowEvent> events;
  final int latestId;
  final bool hasMore;
}

class TableShadowEvent {
  const TableShadowEvent({
    required this.id,
    required this.tableId,
    this.eventType = '',
    this.payload = const {},
    this.deviceId,
    this.orderUuid,
    this.createdAt,
  });
  final int id, tableId;
  final String eventType;
  final Map<String, dynamic> payload;
  final int? deviceId;
  final String? orderUuid;
  final DateTime? createdAt;
}

/// Ephemeral B5 view of the existing board response. No new storage columns,
/// and no changes to the T5 shadow/disagreement projection.
class TableActivityBoardRow {
  const TableActivityBoardRow({
    required this.tableId,
    required this.label,
    this.reference,
    this.pendingCount = 0,
    this.pendingItems = const {},
  });
  final int tableId;
  final String label;
  final String? reference;
  final int pendingCount;
  final Map<int, int> pendingItems;

  factory TableActivityBoardRow.fromBoard(Map<String, dynamic> row) {
    final seating = row['seating'] as Map?;
    final bill = row['bill'] as Map?;
    return TableActivityBoardRow(
      tableId: (row['table_id'] as num).toInt(),
      label: row['table_label']?.toString() ?? row['table_id'].toString(),
      reference: (seating?['temp_reference'] ?? bill?['temp_reference'])
          ?.toString(),
      pendingCount: (bill?['pending_rounds'] as num?)?.toInt() ?? 0,
      pendingItems: {
        for (final round
            in (seating?['pending_rounds'] as List? ?? []).whereType<Map>())
          if (round['round_id'] is num)
            (round['round_id'] as num)
                .toInt(): (round['priced_lines'] as List? ?? [])
                .whereType<Map>()
                .fold<int>(
                  0,
                  (sum, line) => sum + ((line['qty'] as num?)?.toInt() ?? 0),
                ),
      },
    );
  }
}

enum TableActivityKind { pending, kitchen, bill }

class TableActivityNotice {
  const TableActivityNotice({
    required this.eventId,
    required this.tableId,
    required this.tableLabel,
    required this.kind,
    this.reference,
    this.itemCount,
  });
  final int eventId, tableId;
  final String tableLabel;
  final TableActivityKind kind;
  final String? reference;
  final int? itemCount;

  static TableActivityNotice? fromEvent(
    TableShadowEvent event,
    TableActivityBoardRow? row,
  ) {
    if (event.eventType != 'customer_order_arrived' || event.deviceId != null) {
      return null;
    }
    final roundId = (event.payload['round_id'] as num?)?.toInt();
    final items = roundId == null ? null : row?.pendingItems[roundId];
    return TableActivityNotice(
      eventId: event.id,
      tableId: event.tableId,
      tableLabel: row?.label ?? event.tableId.toString(),
      reference: row?.reference,
      kind: roundId == null
          ? TableActivityKind.bill
          : items != null
          ? TableActivityKind.pending
          : TableActivityKind.kitchen,
      itemCount: items,
    );
  }
}

class TableSearchResult {
  const TableSearchResult({
    required this.tableId,
    required this.floorId,
    required this.label,
    this.reference,
    this.totalBaisas,
  });
  final int tableId, floorId;
  final String label;
  final String? reference;
  final int? totalBaisas;
  factory TableSearchResult.fromBoard(Map<String, dynamic> row) {
    final seating = row['seating'] as Map?;
    final bill = row['bill'] as Map?;
    return TableSearchResult(
      tableId: (row['table_id'] as num).toInt(),
      floorId: (row['floor_id'] as num).toInt(),
      label: row['table_label'].toString(),
      reference: (seating?['temp_reference'] ?? bill?['temp_reference'])
          ?.toString(),
      totalBaisas: (bill?['grand_total_baisas'] as num?)?.toInt(),
    );
  }
}

class TableShadowService implements TableShadowGateway {
  const TableShadowService(this.api);
  final PosApiService api;

  @override
  Future<List<Map<String, dynamic>>> fetchBoard() => api.fetchTableBoard();
  @override
  Future<TableShadowFeed> fetchFeed({required int after, int limit = 100}) =>
      api.fetchTableFeed(after: after, limit: limit);
}
