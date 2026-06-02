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
    TaxCache,
    SyncMeta,
    OrderOutbox,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'pos_machine_cache'));

  /// For unit tests: inject an in-memory executor.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // The cache is re-fetched + fully replaced on every login, so these
          // upgrades are purely additive.
          if (from < 2) {
            // v2 added the company-taxes cache.
            await m.createTable(taxCache);
          }
          if (from < 3) {
            // v3 added floor-plan layout columns to the tables cache.
            await m.addColumn(posTables, posTables.positionX);
            await m.addColumn(posTables, posTables.positionY);
            await m.addColumn(posTables, posTables.width);
            await m.addColumn(posTables, posTables.height);
          }
          if (from < 4) {
            // v4 added per-product add-on group ids (the modifier sheet).
            await m.addColumn(products, products.addonGroupIds);
          }
          if (from < 5) {
            // v5 added the order push outbox (offline-first order sync).
            await m.createTable(orderOutbox);
          }
        },
      );

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

  Stream<List<AddonGroupRow>> watchAddonGroups() => select(addonGroups).watch();

  Stream<List<AddonRow>> watchAddons() => select(addons).watch();

  Stream<List<TaxRow>> watchTaxes() =>
      (select(taxCache)..orderBy([(t) => OrderingTerm(expression: t.id)])).watch();

  Future<List<TaxRow>> getTaxes() =>
      (select(taxCache)..orderBy([(t) => OrderingTerm(expression: t.id)])).get();

  Future<SyncMetaRow?> getSyncMeta() =>
      (select(syncMeta)..where((m) => m.id.equals(1))).getSingleOrNull();

  // ---------------------------------------------------------------------------
  // Order push outbox (offline-first order sync → /device/sync/push)
  // ---------------------------------------------------------------------------
  Future<void> enqueueOutbox(OrderOutboxCompanion row) =>
      into(orderOutbox).insertOnConflictUpdate(row);

  /// Orders not yet ACKed by the server, oldest first.
  Future<List<OrderOutboxRow>> pendingOutbox() => (select(orderOutbox)
        ..where((o) => o.syncedAt.isNull())
        ..orderBy([(o) => OrderingTerm(expression: o.createdAt)]))
      .get();

  Stream<List<OrderOutboxRow>> watchPendingOutbox() => (select(orderOutbox)
        ..where((o) => o.syncedAt.isNull())
        ..orderBy([(o) => OrderingTerm(expression: o.createdAt)]))
      .watch();

  Future<void> markOutboxSynced(String orderUuid, DateTime at) =>
      (update(orderOutbox)..where((o) => o.orderUuid.equals(orderUuid)))
          .write(OrderOutboxCompanion(syncedAt: Value(at)));

  Future<void> markOutboxAttempt(String orderUuid, int attempts, String? error) =>
      (update(orderOutbox)..where((o) => o.orderUuid.equals(orderUuid))).write(
        OrderOutboxCompanion(attempts: Value(attempts), lastError: Value(error)),
      );

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
    required List<TaxCacheCompanion> taxRows,
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
      await delete(taxCache).go();

      await into(branchCache).insert(branch);
      await batch((b) {
        b.insertAll(categories, categoryRows);
        b.insertAll(products, productRows);
        b.insertAll(floors, floorRows);
        b.insertAll(posTables, tableRows);
        b.insertAll(addonGroups, addonGroupRows);
        b.insertAll(addons, addonRows);
        b.insertAll(taxCache, taxRows);
      });
      await into(syncMeta).insertOnConflictUpdate(meta);
    });
  }
}
