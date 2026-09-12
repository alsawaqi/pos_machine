import 'db/app_database.dart';

/// Admission evidence only. Reading configuration never edits a local bill.
class TableReplayConfiguration {
  const TableReplayConfiguration({required this.scope, required this.tableIds});
  final String scope;
  final Set<String> tableIds;

  static Future<TableReplayConfiguration?> read(
    AppDatabase db, {
    required String scope,
    required int? companyId,
    required int? branchId,
  }) async {
    if (scope.isEmpty ||
        companyId == null ||
        branchId == null ||
        companyId <= 0 ||
        branchId <= 0) {
      return null;
    }
    return db.transaction(() async {
      final meta = await db.getSyncMeta();
      if (meta?.companyId != companyId || meta?.branchId != branchId) {
        return null;
      }
      final tables = await db.select(db.posTables).get();
      return TableReplayConfiguration(
        scope: scope,
        tableIds: Set.unmodifiable(tables.map((table) => table.id.toString())),
      );
    });
  }
}
