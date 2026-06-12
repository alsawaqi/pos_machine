import 'dart:async';

import '../services/config_mapper.dart';
import '../services/pos_api_service.dart';
import '../services/session_service.dart';
import 'db/app_database.dart';

/// Fetches the branch config from pos_api, caches it in Drift, and exposes the
/// cached catalog as a stream. Drift is the single source of truth, so the UI
/// renders identically online or offline.
class ConfigRepository {
  ConfigRepository(this._api, this._db, this._session);

  final PosApiService _api;
  final AppDatabase _db;
  final SessionService _session;

  /// Online refresh: pull `/device/config`, replace the cache atomically, and
  /// persist the device's terminal ID (from meta) for the Soft POS.
  Future<void> fetchAndCache() async {
    final config = await _api.fetchConfig();
    final parsed = ConfigMapper.parse(config.data, cursor: config.generatedAt);
    await _db.replaceConfig(
      branch: parsed.branch,
      categoryRows: parsed.categories,
      productRows: parsed.products,
      floorRows: parsed.floors,
      tableRows: parsed.tables,
      addonGroupRows: parsed.addonGroups,
      addonRows: parsed.addons,
      taxRows: parsed.taxes,
      deliveryProviderRows: parsed.deliveryProviders,
      expenseCategoryRows: parsed.expenseCategories,
      branchIngredientStockRows: parsed.branchIngredientStock,
      discountRows: parsed.discounts,
      loyaltyRuleRows: parsed.loyaltyRules,
      customerRows: parsed.customers,
      ingredientRows: parsed.ingredients,
      // P-F1 bugfix: these were never passed, so replaceConfig's const-[]
      // defaults WIPED the reason tables on every full sync and the comp/
      // cancel-reason UI never saw a single reason.
      voidReasonRows: parsed.voidReasons,
      compReasonRows: parsed.compReasons,
      offerRows: parsed.offers,
      meta: parsed.meta,
    );
    await _session.saveTerminalId(config.terminalId);
    // Phase C3 — where to dial Reverb (null = live push off server-side).
    await _session.saveWebsocketConfig(config.websocket);
  }

  /// Incremental sync (Phase 7): a DELTA when we hold a cursor from a prior
  /// sync, else a full [fetchAndCache]. A delta failure (bad/expired cursor,
  /// transient error) falls back to a full sync, so the cache self-heals.
  ///
  /// Deltas don't signal a few deletions (taxes, branch_stock rows, a
  /// *deactivated* delivery provider) — those are healed by the full syncs that
  /// still run on device activation + staff login.
  Future<void> syncConfig({bool preferDelta = true}) async {
    final meta = await _db.getSyncMeta();
    final cursor = meta?.configSchemaVersion;
    if (!preferDelta || cursor == null || cursor.isEmpty) {
      await fetchAndCache();
      return;
    }
    try {
      final res = await _api.fetchConfigDelta(cursor);
      final delta = ConfigMapper.parseDelta(res.data, cursor: res.generatedAt);
      final c = delta.changed;
      final d = delta.deleted;
      await _db.applyDelta(
        hasBranch: delta.hasBranch,
        branch: c.branch,
        categoryRows: c.categories,
        productRows: c.products,
        floorRows: c.floors,
        tableRows: c.tables,
        addonGroupRows: c.addonGroups,
        addonRows: c.addons,
        taxRows: c.taxes,
        deliveryProviderRows: c.deliveryProviders,
        expenseCategoryRows: c.expenseCategories,
        branchIngredientStockRows: c.branchIngredientStock,
        discountRows: c.discounts,
        loyaltyRuleRows: c.loyaltyRules,
        customerRows: c.customers,
        ingredientRows: c.ingredients,
        // P-F1 bugfix: delta-changed reason rows upsert into the cache
        // (deactivations/deletions heal on the next full sync, like taxes).
        voidReasonRows: c.voidReasons,
        compReasonRows: c.compReasons,
        offerRows: c.offers,
        deletedOfferIds: d.offers,
        deletedCategoryIds: d.categories,
        deletedProductIds: d.products,
        deletedFloorIds: d.floors,
        deletedTableIds: d.tables,
        deletedAddonGroupIds: d.addonGroups,
        deletedAddonIds: d.addons,
        deletedIngredientIds: d.ingredients,
        deletedDiscountIds: d.discounts,
        deletedLoyaltyRuleIds: d.loyaltyRules,
        deletedCustomerIds: d.customers,
        deletedDeliveryProviderIds: d.deliveryProviders,
        deletedExpenseCategoryIds: d.expenseCategories,
        cursor: res.generatedAt,
        now: DateTime.now(),
        // The settings block is always emitted (full + delta); refresh.
        orderCancelPositions: c.meta.orderCancelPositions.value,
        reportsPositions: c.meta.reportsPositions.value,
        kitchenPositions: c.meta.kitchenPositions.value,
        orderNumberingJson: c.meta.orderNumberingJson.value,
      );
      await _session.saveTerminalId(res.terminalId);
      await _session.saveWebsocketConfig(res.websocket);
    } catch (_) {
      // Self-heal: drop back to a full sync on any delta failure.
      await fetchAndCache();
    }
  }

  Future<bool> hasCachedConfig() => _db.hasCachedConfig();
  Future<BranchRow?> getBranch() => _db.getBranch();
  Stream<BranchRow?> watchBranch() => _db.watchBranch();

  /// Combined stream of the cached catalog; emits once all four config tables
  /// have reported, then on any subsequent change. (Manual combineLatest — no
  /// rxdart dependency.)
  Stream<CatalogSnapshot> watchCatalog() {
    final controller = StreamController<CatalogSnapshot>();
    BranchRow? branch;
    var cats = <CategoryRow>[];
    var prods = <ProductRow>[];
    var floors = <FloorRow>[];
    var tables = <TableRow>[];
    var taxes = <TaxRow>[];
    var addonGroups = <AddonGroupRow>[];
    var addons = <AddonRow>[];
    var deliveryProviders = <DeliveryProviderRow>[];
    var expenseCategories = <ExpenseCategoryRow>[];
    var branchStock = <BranchIngredientStockRow>[];
    var discounts = <DiscountRow>[];
    var loyaltyRules = <LoyaltyRuleRow>[];
    var customers = <CustomerRow>[];
    var ingredients = <IngredientRow>[];
    // P-F1 bugfix: these two were never read back into the catalog, leaving
    // controller.voidReasons/compReasons permanently empty on the device.
    var voidReasons = <VoidReasonRow>[];
    var compReasons = <CompReasonRow>[];
    var offerRows = <OfferRow>[];
    SyncMetaRow? meta;
    var seenCats = false, seenProds = false, seenFloors = false, seenTables = false, seenTaxes = false;

    void emit() {
      if (seenCats && seenProds && seenFloors && seenTables && seenTaxes) {
        controller.add(ConfigMapper.toCatalog(
          branch, cats, prods, floors, tables, taxes, addonGroups, addons,
          deliveryProviders, expenseCategories, branchStock, discounts,
          loyaltyRules, customers, ingredients, meta,
          voidReasons, compReasons, offerRows,
        ));
      }
    }

    final subs = <StreamSubscription<dynamic>>[
      _db.watchBranch().listen((v) {
        branch = v;
        emit();
      }),
      _db.watchCategories().listen((v) {
        cats = v;
        seenCats = true;
        emit();
      }),
      _db.watchProducts().listen((v) {
        prods = v;
        seenProds = true;
        emit();
      }),
      _db.watchFloors().listen((v) {
        floors = v;
        seenFloors = true;
        emit();
      }),
      _db.watchTables().listen((v) {
        tables = v;
        seenTables = true;
        emit();
      }),
      _db.watchTaxes().listen((v) {
        taxes = v;
        seenTaxes = true;
        emit();
      }),
      _db.watchAddonGroups().listen((v) {
        addonGroups = v;
        emit();
      }),
      _db.watchAddons().listen((v) {
        addons = v;
        emit();
      }),
      _db.watchDeliveryProviders().listen((v) {
        deliveryProviders = v;
        emit();
      }),
      _db.watchExpenseCategories().listen((v) {
        expenseCategories = v;
        emit();
      }),
      _db.watchBranchIngredientStock().listen((v) {
        branchStock = v;
        emit();
      }),
      _db.watchDiscounts().listen((v) {
        discounts = v;
        emit();
      }),
      _db.watchLoyaltyRules().listen((v) {
        loyaltyRules = v;
        emit();
      }),
      _db.watchCustomers().listen((v) {
        customers = v;
        emit();
      }),
      _db.watchIngredients().listen((v) {
        ingredients = v;
        emit();
      }),
      _db.watchVoidReasons().listen((v) {
        voidReasons = v;
        emit();
      }),
      _db.watchCompReasons().listen((v) {
        compReasons = v;
        emit();
      }),
      _db.watchOffers().listen((v) {
        offerRows = v;
        emit();
      }),
      _db.watchSyncMeta().listen((v) {
        meta = v;
        emit();
      }),
    ];

    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
    };

    return controller.stream;
  }
}
