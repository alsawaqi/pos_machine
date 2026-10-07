import 'dart:convert';
import '../../tenancy/business_identity.dart';
import 'package:drift/drift.dart';

import '../../core/auth_wire.dart' show eventsWithoutStaffTokens;
import '../../core/training_flag.dart';
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
    Offers,
    StaffMessages,
    MarketingSliders,
    MarketingSliderItems,
  ],
)
class AppDatabase extends _$AppDatabase {
  static final _liveDatabases = <AppDatabase>{};
  static AppDatabase? get liveDatabase => _liveDatabases.firstOrNull;
  AppDatabase() : super(driftDatabase(name: 'pos_machine_cache')) {
    _registerTenancy();
  }

  /// For unit tests: inject an in-memory executor.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 31;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: BusinessBoundary.initialized
        ? (_) async {
            _openedForTenancy = true;
            if (BusinessBoundary.canWork) await prepareTenancy();
          }
        : null,
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
      if (from < 18) {
        // v18 — P-F2: cached vehicle-plate links per customer.
        await m.addColumn(cachedCustomers, cachedCustomers.platesJson);
      }
      if (from < 19) {
        // v19 — P-F4: order-scope auto-apply flag on discount rules.
        await m.addColumn(discounts, discounts.autoApply);
      }
      if (from < 20) {
        // v20 — P-F6: the device-reports access policy.
        await m.addColumn(syncMeta, syncMeta.reportsPositions);
      }
      if (from < 21) {
        // v21 — P-F8: the merchant order-numbering config.
        await m.addColumn(syncMeta, syncMeta.orderNumberingJson);
      }
      if (from < 22) {
        // v22 — P-F9: merchant offers (promotions).
        await m.createTable(offers);
      }
      if (from < 23) {
        // v23 — P-G1: the device Kitchen-screen access policy.
        await m.addColumn(syncMeta, syncMeta.kitchenPositions);
      }
      if (from < 24) {
        // v24 — P-G3: the product behind a product-as-add-on option.
        await m.addColumn(addons, addons.linkedProductId);
      }
      if (from < 25) {
        // v25 — P-G6: staff announcements from the portal.
        await m.createTable(staffMessages);
      }
      if (from < 26) {
        // v26 — PD3b: per-option stock-usage lines (availability gating).
        await m.addColumn(addons, addons.consumptionJson);
      }
      if (from < 27) {
        // v27 — Phase 3: marketing advertising sliders for the customer
        // (secondary) screen.
        await m.createTable(marketingSliders);
        await m.createTable(marketingSliderItems);
      }
      if (from >= 5 && from < 28) {
        // v28 — MC-001: count deterministic server rejections separately
        // from transport failures so rejected revenue can park after five.
        // A pre-v5 upgrade creates the latest outbox table above, including
        // this column, so only existing outbox installations add it here.
        await m.addColumn(orderOutbox, orderOutbox.serverRejections);
      }
      if (from < 29) {
        await m.addColumn(syncMeta, syncMeta.tableSessionsMode);
      }
      if (from < 30) {
        // LAUNCH-P4 — products and menu: display order, product kind,
        // channels, sold out, Arabic description, delivery listing, combo
        // lines; the category branch list; global add-on groups; the
        // merchant's VAT setup (company.tax). Each table is extended only
        // when it exists (every real cache has them; a partial test or
        // half-created cache must not abort the whole upgrade).
        Future<void> extend(
          TableInfo<Table, dynamic> table,
          List<GeneratedColumn<Object>> columns,
        ) async {
          final found = await customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
            variables: [Variable<String>(table.actualTableName)],
          ).get();
          if (found.isEmpty) return;
          for (final column in columns) {
            await m.addColumn(table, column);
          }
        }

        await extend(products, [
          products.displayOrder,
          products.productType,
          products.soldInStore,
          products.soldOnDelivery,
          products.soldOut,
          products.descriptionAr,
          products.deliveryUnlistedJson,
          products.comboJson,
        ]);
        await extend(categories, [categories.branchIdsJson]);
        await extend(addonGroups, [addonGroups.isGlobal]);
        await extend(syncMeta, [syncMeta.companyTaxJson]);
      }
      if (from < 31) {
        // LAUNCH combo add-on — the meal setups (`meals[]`).
        final found = await customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
          variables: [Variable<String>(syncMeta.actualTableName)],
        ).get();
        if (found.isNotEmpty) await m.addColumn(syncMeta, syncMeta.mealsJson);
      }
    },
  );

  final _ownerGeneration = BusinessBoundary.generation.value;
  bool _openedForTenancy = false;
  Future<void> prepareTenancy() => transaction(_prepareTenancy);
  Future<void> _prepareTenancy() async {
    if (!BusinessBoundary.initialized || BusinessBoundary.current == null)
      return;
    final owner = BusinessBoundary.storageIdentity!.encoded;
    final context = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='_p0_owner'",
    ).get();
    if (context.isEmpty) {
      await customStatement(
        'CREATE TABLE _p0_owner(id INTEGER PRIMARY KEY CHECK(id=1), identity TEXT NOT NULL)',
      );
      await customStatement('INSERT INTO _p0_owner(id,identity) VALUES(1,?)', [
        owner,
      ]);
    } else {
      final prior = await customSelect(
        'SELECT identity FROM _p0_owner WHERE id=1',
      ).get();
      if (prior.isEmpty || prior.single.data['identity'] != owner) {
        await customStatement(
          'INSERT OR REPLACE INTO _p0_owner(id,identity) VALUES(1,?)',
          [owner],
        );
      }
    }
    for (final table in allTables) {
      final name = table.actualTableName;
      final columns = await customSelect('PRAGMA table_info("$name")').get();
      if (!columns.any((row) => row.data['name'] == '_business_identity')) {
        await customStatement(
          'ALTER TABLE "$name" ADD COLUMN _business_identity TEXT',
        );
        if (BusinessBoundary.adoptingLegacy) {
          await customStatement('UPDATE "$name" SET _business_identity=?', [
            owner,
          ]);
        }
      }
      final installed = await customSelect(
        "SELECT name FROM sqlite_master WHERE type='trigger' AND name=?",
        variables: [Variable('_p0_stamp_v2_' + name)],
      ).get();
      if (installed.isEmpty) {
        final old = await customSelect(
          "SELECT name FROM sqlite_master WHERE type='trigger' AND name=?",
          variables: [Variable('_p0_stamp_' + name)],
        ).get();
        if (old.isNotEmpty)
          await customStatement('DROP TRIGGER "_p0_stamp_$name"');
        await customStatement(
          'CREATE TRIGGER "_p0_stamp_v2_$name" AFTER INSERT ON "$name" '
          'WHEN NEW._business_identity IS NULL BEGIN UPDATE "$name" '
          'SET _business_identity=(SELECT identity FROM _p0_owner WHERE id=1) WHERE rowid=NEW.rowid; END',
        );
      }
      final foreign = await customSelect(
        'SELECT rowid AS _p0_rowid, * FROM "$name" '
        'WHERE _business_identity IS NULL OR _business_identity != ?',
        variables: [Variable(BusinessBoundary.storageIdentity!.encoded)],
      ).get();
      for (final row in foreign) {
        if (name == orderOutbox.actualTableName) {
          await BusinessBoundary.quarantine(
            'drift:$name',
            (row.data['order_uuid'] ?? row.data['_p0_rowid']).toString(),
            row.data,
          );
        }
        await customStatement('DELETE FROM "$name" WHERE rowid = ?', [
          row.data['_p0_rowid'],
        ]);
      }
    }
  }

  Future<void> wipeTenantData() async {
    // Opening an existing cache is necessary even when the catalog has never
    // been visited in this process. The beforeOpen hook must not adopt old rows.
    final rows = await customSelect('SELECT * FROM order_outbox').get();
    for (final row in rows) {
      if (row.data['synced_at'] != null) continue;
      await BusinessBoundary.quarantine(
        'drift:order_outbox',
        row.data['order_uuid'].toString(),
        row.data,
      );
    }
    await transaction(() async {
      for (final table in allTables.toList().reversed) {
        await delete(table).go();
      }
    });
  }

  static Future<void> wipePersistedTenantData() async {
    if (_liveDatabases.isNotEmpty)
      return; // Each live handle is already a registered wiper.
    final db = AppDatabase();
    try {
      await db.wipeTenantData();
    } finally {
      await db.close();
    }
  }

  Future<void> _refreshTenancy() async {
    if (_openedForTenancy) await prepareTenancy();
  }

  void _registerTenancy() {
    _liveDatabases.add(this);
    BusinessBoundary.registerWiper(wipeTenantData);
    BusinessBoundary.registerActivator(_refreshTenancy);
  }

  @override
  Future<void> close() async {
    _liveDatabases.remove(this);
    BusinessBoundary.unregisterWiper(wipeTenantData);
    BusinessBoundary.unregisterActivator(_refreshTenancy);
    await super.close();
  }

  // ---------------------------------------------------------------------------
  // Reads / streams (consumed by the catalog bridge → PosController)
  // ---------------------------------------------------------------------------
  Future<BranchRow?> getBranch() => select(branchCache).getSingleOrNull();
  Stream<BranchRow?> watchBranch() => select(branchCache).watchSingleOrNull();

  Stream<SyncMetaRow?> watchSyncMeta() => select(syncMeta).watchSingleOrNull();

  Stream<List<CategoryRow>> watchCategories() => (select(
    categories,
  )..orderBy([(c) => OrderingTerm(expression: c.displayOrder)])).watch();

  // LAUNCH-P4 L1 — the merchant's menu display order (then id, stable).
  Stream<List<ProductRow>> watchProducts() =>
      (select(products)..orderBy([
            (p) => OrderingTerm(expression: p.displayOrder),
            (p) => OrderingTerm(expression: p.id),
          ]))
          .watch();

  /// LAUNCH-P4 C6 — the branch's sold-out list from GET /device/sold-out:
  /// exactly [soldOutIds] are sold out, every other cached product is on
  /// sale. Writes only rows whose flag changes, so an unchanged poll does
  /// not re-emit the catalog.
  Future<void> applySoldOut(Set<int> soldOutIds) => transaction(() async {
    final rows = await select(products).get();
    for (final row in rows) {
      final want = soldOutIds.contains(row.id);
      if ((row.soldOut ?? false) == want) continue;
      await (update(products)..where((p) => p.id.equals(row.id))).write(
        ProductsCompanion(soldOut: Value(want)),
      );
    }
  });

  /// LAUNCH-P4 C6 — one product toggled on this till (after the server
  /// accepted POST /device/products/{id}/sold-out).
  Future<void> setProductSoldOut(int productId, bool soldOut) =>
      (update(products)..where((p) => p.id.equals(productId))).write(
        ProductsCompanion(soldOut: Value(soldOut)),
      );

  Stream<List<FloorRow>> watchFloors() => (select(
    floors,
  )..orderBy([(f) => OrderingTerm(expression: f.displayOrder)])).watch();

  Stream<List<TableRow>> watchTables() => (select(
    posTables,
  )..orderBy([(t) => OrderingTerm(expression: t.displayOrder)])).watch();

  Stream<List<AddonGroupRow>> watchAddonGroups() => select(addonGroups).watch();

  Stream<List<AddonRow>> watchAddons() => select(addons).watch();

  Stream<List<TaxRow>> watchTaxes() => (select(
    taxCache,
  )..orderBy([(t) => OrderingTerm(expression: t.id)])).watch();

  Stream<List<DeliveryProviderRow>> watchDeliveryProviders() => (select(
    deliveryProviders,
  )..orderBy([(d) => OrderingTerm(expression: d.sortOrder)])).watch();

  Stream<List<ExpenseCategoryRow>> watchExpenseCategories() => (select(
    expenseCategories,
  )..orderBy([(e) => OrderingTerm(expression: e.sortOrder)])).watch();

  Stream<List<BranchIngredientStockRow>> watchBranchIngredientStock() =>
      select(branchIngredientStock).watch();

  Stream<List<DiscountRow>> watchDiscounts() => select(discounts).watch();

  Stream<List<OfferRow>> watchOffers() => select(offers).watch();

  // Phase 3 — marketing sliders + their slides for the customer-screen ad loop.
  Stream<List<MarketingSliderRow>> watchSliders() => (select(
    marketingSliders,
  )..orderBy([(s) => OrderingTerm(expression: s.displayOrder)])).watch();

  Stream<List<MarketingSliderItemRow>> watchSliderItems() => (select(
    marketingSliderItems,
  )..orderBy([(i) => OrderingTerm(expression: i.sortOrder)])).watch();

  // P-G6 — staff announcements, newest first.
  Stream<List<StaffMessageRow>> watchStaffMessages() =>
      (select(staffMessages)..orderBy([
            (s) =>
                OrderingTerm(expression: s.createdAt, mode: OrderingMode.desc),
          ]))
          .watch();

  Stream<List<LoyaltyRuleRow>> watchLoyaltyRules() =>
      select(loyaltyRules).watch();

  Stream<List<CustomerRow>> watchCustomers() => select(cachedCustomers).watch();

  Stream<List<IngredientRow>> watchIngredients() => (select(
    ingredients,
  )..orderBy([(i) => OrderingTerm(expression: i.name)])).watch();

  // Phase B — void/comp reason lists for the cancel + comp dialogs.
  Stream<List<VoidReasonRow>> watchVoidReasons() => (select(
    voidReasons,
  )..orderBy([(r) => OrderingTerm(expression: r.sortOrder)])).watch();

  Stream<List<CompReasonRow>> watchCompReasons() => (select(
    compReasons,
  )..orderBy([(r) => OrderingTerm(expression: r.sortOrder)])).watch();

  Future<List<TaxRow>> getTaxes() => (select(
    taxCache,
  )..orderBy([(t) => OrderingTerm(expression: t.id)])).get();

  Future<SyncMetaRow?> getSyncMeta() =>
      (select(syncMeta)..where((m) => m.id.equals(1))).getSingleOrNull();

  // ---------------------------------------------------------------------------
  // Order push outbox (offline-first order sync → /device/sync/push)
  // ---------------------------------------------------------------------------
  Future<void> enqueueOutbox(OrderOutboxCompanion row) async {
    BusinessBoundary.assertWritable();
    if (row.eventsJson.present &&
        (BusinessBoundary.initialized || TrainingMode.active)) {
      final events = (jsonDecode(row.eventsJson.value) as List).cast<Map>();
      row = row.copyWith(
        eventsJson: Value(
          jsonEncode([
            for (final event in events)
              _p5Stamp(
                BusinessBoundary.initialized
                    ? BusinessBoundary.stampEvent(event.cast<String, dynamic>())
                    : event.cast<String, dynamic>(),
              ),
          ]),
        ),
      );
    }
    await into(orderOutbox).insertOnConflictUpdate(row);
  }

  /// LAUNCH-P5 C7 — an event queued while training mode is on carries the
  /// `training: true` safety marker, so the server refuses it if it is
  /// ever sent. (`auth_v` is stamped by the event builders, not here: an
  /// event an older build created stays legacy, byte for byte.)
  static Map<String, dynamic> _p5Stamp(Map<String, dynamic> event) =>
      TrainingMode.active ? TrainingMode.mark(event) : event;

  Future<void> quarantineOutbox(OrderOutboxRow row) async {
    await BusinessBoundary.quarantine(
      'drift:order_outbox',
      row.orderUuid,
      jsonDecode(row.eventsJson),
    );
    await (delete(
      orderOutbox,
    )..where((entry) => entry.orderUuid.equals(row.orderUuid))).go();
  }

  Future<OrderOutboxRow?> getOutbox(String key) => (select(
    orderOutbox,
  )..where((row) => row.orderUuid.equals(key))).getSingleOrNull();

  /// Retire a payment attempt that the server affirmatively refused and whose
  /// physical tender has been resolved by staff. Keeping the row preserves the
  /// evidence while removing it from automatic outbox replay.
  Future<void> retireOutbox(String key, String reason, DateTime at) =>
      (update(orderOutbox)..where((row) => row.orderUuid.equals(key))).write(
        OrderOutboxCompanion(lastError: Value(reason), syncedAt: Value(at)),
      );

  /// Orders not yet ACKed by the server, oldest first.
  Future<List<OrderOutboxRow>> pendingOutbox() =>
      (select(orderOutbox)
            ..where((o) => o.syncedAt.isNull())
            ..orderBy([(o) => OrderingTerm(expression: o.createdAt)]))
          .get();

  Stream<List<OrderOutboxRow>> watchPendingOutbox() =>
      (select(orderOutbox)
            ..where((o) => o.syncedAt.isNull())
            ..orderBy([(o) => OrderingTerm(expression: o.createdAt)]))
          .watch();

  /// Pending revenue together with the cached branch fence that governs it.
  ///
  /// The left join deliberately makes this stream depend on both tables. That
  /// keeps operator-attention surfaces accurate when a branch fence changes,
  /// even if no outbox row is inserted or updated at the same time.
  Stream<({List<OrderOutboxRow> rows, BranchRow? branch})>
  watchPendingOutboxWithBranch() {
    final query =
        select(
            orderOutbox,
          ).join([leftOuterJoin(branchCache, const Constant(true))])
          ..where(orderOutbox.syncedAt.isNull())
          ..orderBy([OrderingTerm(expression: orderOutbox.createdAt)]);

    return query.watch().map((joinedRows) {
      if (joinedRows.isEmpty) {
        return (rows: const <OrderOutboxRow>[], branch: null);
      }
      return (
        rows: joinedRows
            .map((joined) => joined.readTable(orderOutbox))
            .toList(growable: false),
        branch: joinedRows.first.readTableOrNull(branchCache),
      );
    });
  }

  /// Acknowledged. LAUNCH-P5 fix order 2 (T11) — the row's staff tokens
  /// are stripped at the same time (the server has what it needed).
  Future<void> markOutboxSynced(String orderUuid, DateTime at) async {
    final row = await getOutbox(orderUuid);
    final stripped = row == null
        ? null
        : eventsWithoutStaffTokens(row.eventsJson);
    await (update(
      orderOutbox,
    )..where((o) => o.orderUuid.equals(orderUuid))).write(
      OrderOutboxCompanion(
        syncedAt: Value(at),
        eventsJson: stripped == null ? const Value.absent() : Value(stripped),
      ),
    );
  }

  Future<void> markOutboxAttempt(
    String orderUuid,
    int attempts,
    String? error,
  ) => (update(orderOutbox)..where((o) => o.orderUuid.equals(orderUuid))).write(
    OrderOutboxCompanion(attempts: Value(attempts), lastError: Value(error)),
  );

  Future<void> markOutboxServerRejection(
    String orderUuid,
    int attempts,
    int serverRejections,
    String error,
  ) => (update(orderOutbox)..where((o) => o.orderUuid.equals(orderUuid))).write(
    OrderOutboxCompanion(
      attempts: Value(attempts),
      serverRejections: Value(serverRejections),
      lastError: Value(error),
    ),
  );

  /// LAUNCH-P5 fix order 2 (T5) — un-park one unsent row (the server named
  /// its sale as missing), so the next flush sends it again.
  Future<int> unparkOutboxRow(String orderUuid) =>
      (update(orderOutbox)
            ..where((o) => o.orderUuid.equals(orderUuid) & o.syncedAt.isNull()))
          .write(const OrderOutboxCompanion(serverRejections: Value(0)));

  Future<int> resetStuckOutbox(int rejectionLimit) =>
      (update(orderOutbox)..where(
            (o) =>
                o.syncedAt.isNull() &
                o.serverRejections.isBiggerOrEqualValue(rejectionLimit) &
                o.orderUuid.like('%:pay').not(),
          ))
          .write(const OrderOutboxCompanion(serverRejections: Value(0)));

  /// #3 — locally decrement finite shelf stock (unit/cooked products) after a
  /// sale, clamped at 0, so the produced count survives an app restart until
  /// the next /device/config sync overwrites it with the server's authoritative
  /// balance. Only touches rows that already carry a non-null branchStockQty
  /// (shelf-tracked at this branch). [soldById] = {productId → quantity sold}.
  Future<void> consumeProductShelfStock(Map<int, double> soldById) async {
    if (soldById.isEmpty) return;
    await transaction(() async {
      for (final entry in soldById.entries) {
        final row = await (select(
          products,
        )..where((p) => p.id.equals(entry.key))).getSingleOrNull();
        final current = row?.branchStockQty;
        if (current == null) continue; // not shelf-tracked locally
        final next = current - entry.value;
        await (update(products)..where((p) => p.id.equals(entry.key))).write(
          ProductsCompanion(branchStockQty: Value(next < 0 ? 0 : next)),
        );
      }
    });
  }

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
    List<OffersCompanion> offerRows = const [],
    List<StaffMessagesCompanion> staffMessageRows = const [],
    List<MarketingSlidersCompanion> sliderRows = const [],
    List<MarketingSliderItemsCompanion> sliderItemRows = const [],
    required SyncMetaCompanion meta,
  }) {
    return transaction(() async {
      BusinessBoundary.assertGeneration(_ownerGeneration);
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
      await delete(offers).go();
      await delete(staffMessages).go();
      await delete(marketingSliders).go();
      await delete(marketingSliderItems).go();

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
        b.insertAll(offers, offerRows);
        b.insertAll(staffMessages, staffMessageRows);
        b.insertAll(marketingSliders, sliderRows);
        b.insertAll(marketingSliderItems, sliderItemRows);
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
    List<OffersCompanion> offerRows = const [],
    List<int> deletedOfferIds = const [],
    List<StaffMessagesCompanion> staffMessageRows = const [],
    List<int> deletedStaffMessageIds = const [],
    // Phase 3 — the slider slice always arrives in full, so it is replaced
    // wholesale (no per-row delta / deleted ids); an empty list = no ads here.
    List<MarketingSlidersCompanion> sliderRows = const [],
    List<MarketingSliderItemsCompanion> sliderItemRows = const [],
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
    // LAUNCH-P4 (H10) — the delta `deleted` map now also names taxes and
    // void / comp reasons, which used to linger until the next full sync.
    List<int> deletedTaxIds = const [],
    List<int> deletedVoidReasonIds = const [],
    List<int> deletedCompReasonIds = const [],
    required String? cursor,
    required DateTime now,
    String? orderCancelPositions,
    String? reportsPositions,
    String? kitchenPositions,
    String? orderNumberingJson,
    String? tableSessionsMode,
    String? companyTaxJson,
    String? mealsJson,
  }) {
    return transaction(() async {
      BusinessBoundary.assertGeneration(_ownerGeneration);
      // Upserts (changed rows only — untouched rows survive).
      if (hasBranch) {
        await into(branchCache).insertOnConflictUpdate(branch);
      }
      // Phase 3 — sliders are sent in full every pull; replace wholesale so
      // removed sliders/slides disappear without a deleted-ids list.
      await delete(marketingSliders).go();
      await delete(marketingSliderItems).go();
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
        b.insertAllOnConflictUpdate(
          branchIngredientStock,
          branchIngredientStockRows,
        );
        b.insertAllOnConflictUpdate(discounts, discountRows);
        b.insertAllOnConflictUpdate(loyaltyRules, loyaltyRuleRows);
        b.insertAllOnConflictUpdate(cachedCustomers, customerRows);
        b.insertAllOnConflictUpdate(ingredients, ingredientRows);
        b.insertAllOnConflictUpdate(voidReasons, voidReasonRows);
        b.insertAllOnConflictUpdate(compReasons, compReasonRows);
        b.insertAllOnConflictUpdate(offers, offerRows);
        b.insertAllOnConflictUpdate(staffMessages, staffMessageRows);
        b.insertAll(marketingSliders, sliderRows);
        b.insertAll(marketingSliderItems, sliderItemRows);
      });

      // Purge soft-deleted ids.
      if (deletedCategoryIds.isNotEmpty) {
        await (delete(
          categories,
        )..where((t) => t.id.isIn(deletedCategoryIds))).go();
      }
      if (deletedProductIds.isNotEmpty) {
        await (delete(
          products,
        )..where((t) => t.id.isIn(deletedProductIds))).go();
      }
      if (deletedFloorIds.isNotEmpty) {
        await (delete(floors)..where((t) => t.id.isIn(deletedFloorIds))).go();
      }
      if (deletedTableIds.isNotEmpty) {
        await (delete(
          posTables,
        )..where((t) => t.id.isIn(deletedTableIds))).go();
      }
      if (deletedAddonGroupIds.isNotEmpty) {
        await (delete(
          addonGroups,
        )..where((t) => t.id.isIn(deletedAddonGroupIds))).go();
      }
      if (deletedAddonIds.isNotEmpty) {
        await (delete(addons)..where((t) => t.id.isIn(deletedAddonIds))).go();
      }
      if (deletedIngredientIds.isNotEmpty) {
        await (delete(
          ingredients,
        )..where((t) => t.id.isIn(deletedIngredientIds))).go();
      }
      if (deletedDiscountIds.isNotEmpty) {
        await (delete(
          discounts,
        )..where((t) => t.id.isIn(deletedDiscountIds))).go();
      }
      if (deletedLoyaltyRuleIds.isNotEmpty) {
        await (delete(
          loyaltyRules,
        )..where((t) => t.id.isIn(deletedLoyaltyRuleIds))).go();
      }
      if (deletedCustomerIds.isNotEmpty) {
        await (delete(
          cachedCustomers,
        )..where((t) => t.id.isIn(deletedCustomerIds))).go();
      }
      if (deletedDeliveryProviderIds.isNotEmpty) {
        await (delete(
          deliveryProviders,
        )..where((t) => t.id.isIn(deletedDeliveryProviderIds))).go();
      }
      if (deletedExpenseCategoryIds.isNotEmpty) {
        await (delete(
          expenseCategories,
        )..where((t) => t.id.isIn(deletedExpenseCategoryIds))).go();
      }
      if (deletedOfferIds.isNotEmpty) {
        await (delete(offers)..where((t) => t.id.isIn(deletedOfferIds))).go();
      }
      if (deletedStaffMessageIds.isNotEmpty) {
        await (delete(
          staffMessages,
        )..where((t) => t.id.isIn(deletedStaffMessageIds))).go();
      }
      if (deletedTaxIds.isNotEmpty) {
        await (delete(taxCache)..where((t) => t.id.isIn(deletedTaxIds))).go();
      }
      if (deletedVoidReasonIds.isNotEmpty) {
        await (delete(
          voidReasons,
        )..where((t) => t.id.isIn(deletedVoidReasonIds))).go();
      }
      if (deletedCompReasonIds.isNotEmpty) {
        await (delete(
          compReasons,
        )..where((t) => t.id.isIn(deletedCompReasonIds))).go();
      }

      // Advance the cursor only — keep company/branch (absent = unchanged).
      // The cancel-policy is refreshed when present (always emitted by pos_api),
      // left untouched when null so a stray delta can't blank it.
      await into(syncMeta).insertOnConflictUpdate(
        SyncMetaCompanion(
          id: const Value(1),
          lastConfigSyncAt: Value(now),
          configSchemaVersion: Value(cursor),
          orderCancelPositions: orderCancelPositions == null
              ? const Value.absent()
              : Value(orderCancelPositions),
          reportsPositions: reportsPositions == null
              ? const Value.absent()
              : Value(reportsPositions),
          kitchenPositions: kitchenPositions == null
              ? const Value.absent()
              : Value(kitchenPositions),
          orderNumberingJson: orderNumberingJson == null
              ? const Value.absent()
              : Value(orderNumberingJson),
          tableSessionsMode: tableSessionsMode == null
              ? const Value.absent()
              : Value(tableSessionsMode),
          companyTaxJson: companyTaxJson == null
              ? const Value.absent()
              : Value(companyTaxJson),
          // LAUNCH combo add-on — every pull carries the full meal set.
          mealsJson: mealsJson == null
              ? const Value.absent()
              : Value(mealsJson),
        ),
      );
    });
  }
}
