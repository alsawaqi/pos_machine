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
  const TableShadowEvent({required this.id, required this.tableId});
  final int id, tableId;
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
