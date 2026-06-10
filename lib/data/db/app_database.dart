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
    DeliveryProviders,
    ExpenseCategories,
    BranchIngredientStock,
    Discounts,
    LoyaltyRules,
    CachedCustomers,
    Ingredients,
    VoidReasons,
    CompReasons,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'pos_machine_cache'));

  /// For unit tests: inject an in-memory executor.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 17;

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
          if (from < 6) {
            // v6 added delivery providers + per-product delivery pricing.
            await m.addColumn(products, products.deliveryPriceBaisas);
            await m.addColumn(products, products.deliveryPricesJson);
            await m.createTable(deliveryProviders);
          }
          if (from < 7) {
            // v7 added stock mode + recipe + per-branch ingredient balances
            // (device sold-out enforcement).
            await m.addColumn(products, products.stockMode);
            await m.addColumn(products, products.recipeJson);
            await m.createTable(branchIngredientStock);
          }
          if (from < 8) {
            // v8 added cached merchant discount rules (from-API discounts).
            await m.createTable(discounts);
          }
          if (from < 9) {
            // v9 added cached loyalty rules + a customer slice (loyalty earn/
            // redeem + offline customer lookup).
            await m.createTable(loyaltyRules);
            await m.createTable(cachedCustomers);
          }
          if (from < 10) {
            // v10 added the ingredient catalogue (id+name+unit) for the device
            // restock-request picker.
            await m.createTable(ingredients);
          }
          if (from < 11) {
            // v11 cached per-customer loyalty balances (offline points/redeem).
            await m.addColumn(cachedCustomers, cachedCustomers.loyaltyJson);
          }
          if (from < 12) {
            // v12 added company expense categories (dynamic expense-log picker).
            await m.createTable(expenseCategories);
          }
          if (from < 13) {
            // v13 cached the order-cancel positions policy (device cancel gate).
            await m.addColumn(syncMeta, syncMeta.orderCancelPositions);
          }
          if (from < 14) {
            // v14 cached the per-branch custom receipt template.
            await m.addColumn(branchCache, branchCache.receiptTemplateJson);
          }
          if (from < 15) {
            // v15 — Phase A ingredient piece model (day-end counts in pieces).
            await m.addColumn(ingredients, ingredients.pieceUnitLabel);
            await m.addColumn(ingredients, ingredients.pieceUnitLabelAr);
            await m.addColumn(ingredients, ingredients.unitsPerPiece);
            await m.addColumn(ingredients, ingredients.allowFractionalPieces);
          }
          if (from < 16) {
            // v16 — Phase B restaurant controls: void/comp reason lists,
            // modifier-group constraints + defaults, category group bindings.
            await m.createTable(voidReasons);
            await m.createTable(compReasons);
            await m.addColumn(addonGroups, addonGroups.minSelections);
            await m.addColumn(addonGroups, addonGroups.maxSelections);
            await m.addColumn(addons, addons.isDefault);
            await m.addColumn(categories, categories.addonGroupIdsJson);
          }
          if (from < 17) {
            // v17 — Gap sweep G1: per-product daily availability window.
            await m.addColumn(products, products.availableFrom);
            await m.addColumn(products, products.availableUntil);
          }
        },
      );

  // ---------------------------------------------------------------------------
  // Reads / streams (consumed by the catalog bridge → PosController)
  // ---------------------------------------------------------------------------
  Future<BranchRow?> getBranch() => select(branchCache).getSingleOrNull();
  Stream<BranchRow?> watchBranch() => select(branchCache).watchSingleOrNull();

  Stream<SyncMetaRow?> watchSyncMeta() => select(syncMeta).watchSingleOrNull();

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

  Stream<List<DeliveryProviderRow>> watchDeliveryProviders() =>
      (select(deliveryProviders)..orderBy([(d) => OrderingTerm(expression: d.sortOrder)])).watch();

  Stream<List<ExpenseCategoryRow>> watchExpenseCategories() =>
      (select(expenseCategories)..orderBy([(e) => OrderingTerm(expression: e.sortOrder)])).watch();

  Stream<List<BranchIngredientStockRow>> watchBranchIngredientStock() =>
      select(branchIngredientStock).watch();

  Stream<List<DiscountRow>> watchDiscounts() => select(discounts).watch();

  Stream<List<LoyaltyRuleRow>> watchLoyaltyRules() =>
      select(loyaltyRules).watch();

  Stream<List<CustomerRow>> watchCustomers() => select(cachedCustomers).watch();

  Stream<List<IngredientRow>> watchIngredients() =>
      (select(ingredients)..orderBy([(i) => OrderingTerm(expression: i.name)])).watch();

  // Phase B — void/comp reason lists for the cancel + comp dialogs.
  Stream<List<VoidReasonRow>> watchVoidReasons() =>
      (select(voidReasons)..orderBy([(r) => OrderingTerm(expression: r.sortOrder)])).watch();

  Stream<List<CompReasonRow>> watchCompReasons() =>
      (select(compReasons)..orderBy([(r) => OrderingTerm(expression: r.sortOrder)])).watch();

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
    required List<DeliveryProvidersCompanion> deliveryProviderRows,
    required List<ExpenseCategoriesCompanion> expenseCategoryRows,
    required List<BranchIngredientStockCompanion> branchIngredientStockRows,
    required List<DiscountsCompanion> discountRows,
    required List<LoyaltyRulesCompanion> loyaltyRuleRows,
    required List<CachedCustomersCompanion> customerRows,
    required List<IngredientsCompanion> ingredientRows,
    List<VoidReasonsCompanion> voidReasonRows = const [],
    List<CompReasonsCompanion> compReasonRows = const [],
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
      await delete(deliveryProviders).go();
      await delete(expenseCategories).go();
      await delete(branchIngredientStock).go();
      await delete(discounts).go();
      await delete(loyaltyRules).go();
      await delete(cachedCustomers).go();
      await delete(ingredients).go();
      await delete(voidReasons).go();
      await delete(compReasons).go();

      await into(branchCache).insert(branch);
      await batch((b) {
        b.insertAll(categories, categoryRows);
        b.insertAll(products, productRows);
        b.insertAll(floors, floorRows);
        b.insertAll(posTables, tableRows);
        b.insertAll(addonGroups, addonGroupRows);
        b.insertAll(addons, addonRows);
        b.insertAll(taxCache, taxRows);
        b.insertAll(deliveryProviders, deliveryProviderRows);
        b.insertAll(expenseCategories, expenseCategoryRows);
        b.insertAll(branchIngredientStock, branchIngredientStockRows);
        b.insertAll(discounts, discountRows);
        b.insertAll(loyaltyRules, loyaltyRuleRows);
        b.insertAll(cachedCustomers, customerRows);
        b.insertAll(ingredients, ingredientRows);
        b.insertAll(voidReasons, voidReasonRows);
        b.insertAll(compReasons, compReasonRows);
      });
      await into(syncMeta).insertOnConflictUpdate(meta);
    });
  }

  // ---------------------------------------------------------------------------
  // Write: apply an incremental DELTA (Phase 7) — non-destructive sibling of
  // replaceConfig. Upserts the changed rows (no wipe), purges the soft-deleted
  // ids, then advances the cursor. company/branch on SyncMeta are left untouched
  // (absent columns) so an unchanged-branch delta doesn't blank them.
  // ---------------------------------------------------------------------------
  Future<void> applyDelta({
    required bool hasBranch,
    required BranchCacheCompanion branch,
    required List<CategoriesCompanion> categoryRows,
    required List<ProductsCompanion> productRows,
    required List<FloorsCompanion> floorRows,
    required List<PosTablesCompanion> tableRows,
    required List<AddonGroupsCompanion> addonGroupRows,
    required List<AddonsCompanion> addonRows,
    required List<TaxCacheCompanion> taxRows,
    required List<DeliveryProvidersCompanion> deliveryProviderRows,
    required List<ExpenseCategoriesCompanion> expenseCategoryRows,
    required List<BranchIngredientStockCompanion> branchIngredientStockRows,
    required List<DiscountsCompanion> discountRows,
    required List<LoyaltyRulesCompanion> loyaltyRuleRows,
    required List<CachedCustomersCompanion> customerRows,
    required List<IngredientsCompanion> ingredientRows,
    List<VoidReasonsCompanion> voidReasonRows = const [],
    List<CompReasonsCompanion> compReasonRows = const [],
    required List<int> deletedCategoryIds,
    required List<int> deletedProductIds,
    required List<int> deletedFloorIds,
    required List<int> deletedTableIds,
    required List<int> deletedAddonGroupIds,
    required List<int> deletedAddonIds,
    required List<int> deletedIngredientIds,
    required List<int> deletedDiscountIds,
    required List<int> deletedLoyaltyRuleIds,
    required List<int> deletedCustomerIds,
    required List<int> deletedDeliveryProviderIds,
    required List<int> deletedExpenseCategoryIds,
    required String? cursor,
    required DateTime now,
    String? orderCancelPositions,
  }) {
    return transaction(() async {
      // Upserts (changed rows only — untouched rows survive).
      if (hasBranch) {
        await into(branchCache).insertOnConflictUpdate(branch);
      }
      await batch((b) {
        b.insertAllOnConflictUpdate(categories, categoryRows);
        b.insertAllOnConflictUpdate(products, productRows);
        b.insertAllOnConflictUpdate(floors, floorRows);
        b.insertAllOnConflictUpdate(posTables, tableRows);
        b.insertAllOnConflictUpdate(addonGroups, addonGroupRows);
        b.insertAllOnConflictUpdate(addons, addonRows);
        b.insertAllOnConflictUpdate(taxCache, taxRows);
        b.insertAllOnConflictUpdate(deliveryProviders, deliveryProviderRows);
        b.insertAllOnConflictUpdate(expenseCategories, expenseCategoryRows);
        b.insertAllOnConflictUpdate(branchIngredientStock, branchIngredientStockRows);
        b.insertAllOnConflictUpdate(discounts, discountRows);
        b.insertAllOnConflictUpdate(loyaltyRules, loyaltyRuleRows);
        b.insertAllOnConflictUpdate(cachedCustomers, customerRows);
        b.insertAllOnConflictUpdate(ingredients, ingredientRows);
        b.insertAllOnConflictUpdate(voidReasons, voidReasonRows);
        b.insertAllOnConflictUpdate(compReasons, compReasonRows);
      });

      // Purge soft-deleted ids.
      if (deletedCategoryIds.isNotEmpty) {
        await (delete(categories)..where((t) => t.id.isIn(deletedCategoryIds))).go();
      }
      if (deletedProductIds.isNotEmpty) {
        await (delete(products)..where((t) => t.id.isIn(deletedProductIds))).go();
      }
      if (deletedFloorIds.isNotEmpty) {
        await (delete(floors)..where((t) => t.id.isIn(deletedFloorIds))).go();
      }
      if (deletedTableIds.isNotEmpty) {
        await (delete(posTables)..where((t) => t.id.isIn(deletedTableIds))).go();
      }
      if (deletedAddonGroupIds.isNotEmpty) {
        await (delete(addonGroups)..where((t) => t.id.isIn(deletedAddonGroupIds))).go();
      }
      if (deletedAddonIds.isNotEmpty) {
        await (delete(addons)..where((t) => t.id.isIn(deletedAddonIds))).go();
      }
      if (deletedIngredientIds.isNotEmpty) {
        await (delete(ingredients)..where((t) => t.id.isIn(deletedIngredientIds))).go();
      }
      if (deletedDiscountIds.isNotEmpty) {
        await (delete(discounts)..where((t) => t.id.isIn(deletedDiscountIds))).go();
      }
      if (deletedLoyaltyRuleIds.isNotEmpty) {
        await (delete(loyaltyRules)..where((t) => t.id.isIn(deletedLoyaltyRuleIds))).go();
      }
      if (deletedCustomerIds.isNotEmpty) {
        await (delete(cachedCustomers)..where((t) => t.id.isIn(deletedCustomerIds))).go();
      }
      if (deletedDeliveryProviderIds.isNotEmpty) {
        await (delete(deliveryProviders)..where((t) => t.id.isIn(deletedDeliveryProviderIds))).go();
      }
      if (deletedExpenseCategoryIds.isNotEmpty) {
        await (delete(expenseCategories)..where((t) => t.id.isIn(deletedExpenseCategoryIds))).go();
      }

      // Advance the cursor only — keep company/branch (absent = unchanged).
      // The cancel-policy is refreshed when present (always emitted by pos_api),
      // left untouched when null so a stray delta can't blank it.
      await into(syncMeta).insertOnConflictUpdate(SyncMetaCompanion(
        id: const Value(1),
        lastConfigSyncAt: Value(now),
        configSchemaVersion: Value(cursor),
        orderCancelPositions: orderCancelPositions == null
            ? const Value.absent()
            : Value(orderCancelPositions),
      ));
    });
  }
}
