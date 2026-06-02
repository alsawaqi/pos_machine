import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Offline cache for the branch-scoped config bundle fetched from pos_api.
/// Coexists with the existing sqflite order store (different database file);
/// this one only holds the read-only catalog the POS renders.
@DriftDatabase(
  tables: [
    BranchCache,
    Categories,
    Products,
    Floors,
    PosTables,
    AddonGroups,
    Addons,
    SyncMeta,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'pos_machine_cache'));

  /// For unit tests: inject an in-memory executor.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  // ---------------------------------------------------------------------------
  // Reads / streams (consumed by the catalog bridge → PosController)
  // ---------------------------------------------------------------------------
  Future<BranchRow?> getBranch() => select(branchCache).getSingleOrNull();
  Stream<BranchRow?> watchBranch() => select(branchCache).watchSingleOrNull();

  Stream<List<CategoryRow>> watchCategories() =>
      (select(categories)..orderBy([(c) => OrderingTerm(expression: c.displayOrder)])).watch();

  Stream<List<ProductRow>> watchProducts() => select(products).watch();

  Stream<List<FloorRow>> watchFloors() =>
      (select(floors)..orderBy([(f) => OrderingTerm(expression: f.displayOrder)])).watch();

  Stream<List<TableRow>> watchTables() =>
      (select(posTables)..orderBy([(t) => OrderingTerm(expression: t.displayOrder)])).watch();

  Future<SyncMetaRow?> getSyncMeta() =>
      (select(syncMeta)..where((m) => m.id.equals(1))).getSingleOrNull();

  /// True once at least one config sync has populated the cache.
  Future<bool> hasCachedConfig() async {
    final rows = await select(categories).get();
    return rows.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // Write: replace the entire cached config atomically (full-sync semantics)
  // ---------------------------------------------------------------------------
  Future<void> replaceConfig({
    required BranchCacheCompanion branch,
    required List<CategoriesCompanion> categoryRows,
    required List<ProductsCompanion> productRows,
    required List<FloorsCompanion> floorRows,
    required List<PosTablesCompanion> tableRows,
    required List<AddonGroupsCompanion> addonGroupRows,
    required List<AddonsCompanion> addonRows,
    required SyncMetaCompanion meta,
  }) {
    return transaction(() async {
      await delete(branchCache).go();
      await delete(categories).go();
      await delete(products).go();
      await delete(floors).go();
      await delete(posTables).go();
      await delete(addonGroups).go();
      await delete(addons).go();

      await into(branchCache).insert(branch);
      await batch((b) {
        b.insertAll(categories, categoryRows);
        b.insertAll(products, productRows);
        b.insertAll(floors, floorRows);
        b.insertAll(posTables, tableRows);
        b.insertAll(addonGroups, addonGroupRows);
        b.insertAll(addons, addonRows);
      });
      await into(syncMeta).insertOnConflictUpdate(meta);
    });
  }
}
