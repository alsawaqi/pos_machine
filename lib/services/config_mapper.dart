import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/db/app_database.dart';
import '../models/pos_models.dart';

/// The catalog slice the existing UI consumes, derived from the Drift cache.
class CatalogSnapshot {
  const CatalogSnapshot({
    required this.categories,
    required this.products,
    required this.floors,
    required this.tables,
    required this.taxes,
    this.addonGroups = const <AddonGroup>[],
    this.deliveryProviders = const <DeliveryProvider>[],
    this.expenseCategories = const <({String key, String name})>[],
    this.ingredientBalances = const <int, double>{},
    this.discounts = const <MerchantDiscount>[],
    this.loyaltyRules = const <LoyaltyRule>[],
    this.customers = const <CustomerRef>[],
    this.ingredients = const <IngredientRef>[],
    this.cancelOrderPositions = const <String>['manager'],
    this.receiptTemplate,
  });

  final List<String> categories;
  final List<Product> products;
  final List<DiningFloor> floors;
  final List<DiningTableDefinition> tables;
  final List<CompanyTax> taxes;
  // Company add-on groups (each with its options); products reference them by id.
  final List<AddonGroup> addonGroups;
  // Company delivery providers for the POS provider picker (delivery orders).
  final List<DeliveryProvider> deliveryProviders;
  // Company expense categories for the expense-log picker (value = key, label =
  // name). Empty = no config categories cached → the screen uses its const list.
  final List<({String key, String name})> expenseCategories;
  // This branch's ingredient balances by ingredient id; drives ingredient-based
  // sold-out (a recipe product is out when a needed ingredient runs low).
  final Map<int, double> ingredientBalances;
  // Merchant discount rules; the POS offers the currently-applicable order-scope
  // ones in the discount picker.
  final List<MerchantDiscount> discounts;
  // Merchant loyalty rules (stamp card / points); drive earn + redeem.
  final List<LoyaltyRule> loyaltyRules;
  // Cached customer slice for offline lookup / order attach.
  final List<CustomerRef> customers;
  // Company ingredient catalogue (id+name+unit) for the restock-request picker.
  final List<IngredientRef> ingredients;
  // v2 #14 — staff positions allowed to cancel an order at the POS (company
  // policy). Defaults to managers-only until a config sync populates it.
  final List<String> cancelOrderPositions;
  // Per-branch custom receipt template; null = device prints its default.
  final ReceiptTemplate? receiptTemplate;
}

/// Drift companions parsed from an API config bundle, ready for replaceConfig().
class ParsedConfig {
  ParsedConfig({
    required this.branch,
    required this.categories,
    required this.products,
    required this.floors,
    required this.tables,
    required this.addonGroups,
    required this.addons,
    required this.taxes,
    required this.deliveryProviders,
    required this.expenseCategories,
    required this.branchIngredientStock,
    required this.discounts,
    required this.loyaltyRules,
    required this.customers,
    required this.ingredients,
    required this.meta,
  });

  final BranchCacheCompanion branch;
  final List<CategoriesCompanion> categories;
  final List<ProductsCompanion> products;
  final List<FloorsCompanion> floors;
  final List<PosTablesCompanion> tables;
  final List<AddonGroupsCompanion> addonGroups;
  final List<AddonsCompanion> addons;
  final List<TaxCacheCompanion> taxes;
  final List<DeliveryProvidersCompanion> deliveryProviders;
  final List<ExpenseCategoriesCompanion> expenseCategories;
  final List<BranchIngredientStockCompanion> branchIngredientStock;
  final List<DiscountsCompanion> discounts;
  final List<LoyaltyRulesCompanion> loyaltyRules;
  final List<CachedCustomersCompanion> customers;
  final List<IngredientsCompanion> ingredients;
  final SyncMetaCompanion meta;
}

/// Per-entity ids soft-deleted since the last sync (the delta's `data.deleted{}`
/// map). The device purges these rows from its Drift cache.
class DeletedIds {
  const DeletedIds({
    this.floors = const [],
    this.tables = const [],
    this.categories = const [],
    this.products = const [],
    this.addonGroups = const [],
    this.addons = const [],
    this.ingredients = const [],
    this.discounts = const [],
    this.loyaltyRules = const [],
    this.customers = const [],
    this.deliveryProviders = const [],
    this.expenseCategories = const [],
  });

  final List<int> floors;
  final List<int> tables;
  final List<int> categories;
  final List<int> products;
  final List<int> addonGroups;
  final List<int> addons;
  final List<int> ingredients;
  final List<int> discounts;
  final List<int> loyaltyRules;
  final List<int> customers;
  final List<int> deliveryProviders;
  final List<int> expenseCategories;
}

/// A parsed config delta: the changed-row companions (built via
/// [ConfigMapper.parse]) + [hasBranch] (false = the branch row was unchanged, so
/// leave branchCache untouched) + the [deleted] ids to purge.
class ConfigDelta {
  ConfigDelta({required this.changed, required this.hasBranch, required this.deleted});

  final ParsedConfig changed;
  final bool hasBranch;
  final DeletedIds deleted;
}

/// Two-way mapping: API JSON → Drift companions, and Drift rows → existing UI
/// models. Money stays integer baisas in Drift and becomes `double` OMR only in
/// [toCatalog] (the boundary into the existing pos_machine models).
class ConfigMapper {
  const ConfigMapper._();

  static int? _int(Object? v) => (v as num?)?.toInt();
  static double? _dbl(Object? v) => (v as num?)?.toDouble();
  static String _str(Object? v) => v?.toString() ?? '';
  static String? _strN(Object? v) => v?.toString();
  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  static List<Map<String, dynamic>> _list(Object? v) =>
      (v as List?)
          ?.whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList() ??
      const [];

  static List<int> _intList(Object? v) =>
      (v as List?)?.map((e) => (e as num?)?.toInt()).whereType<int>().toList() ??
      const [];

  static List<String> _strList(Object? v) =>
      (v as List?)
          ?.map((e) => e?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList() ??
      const [];

  static List<int> _idsFromCsv(String csv) => csv.isEmpty
      ? const []
      : csv
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toList();

  /// API per-product `delivery_prices` ([{provider_id, price_baisas}]) → a JSON
  /// object {providerId: priceBaisas} stored on the product row.
  static String _deliveryPricesJson(Object? v) {
    final map = <String, int>{};
    for (final e in (v as List? ?? const [])) {
      if (e is! Map) continue;
      final pid = (e['provider_id'] as num?)?.toInt();
      final price = (e['price_baisas'] as num?)?.toInt();
      if (pid != null && price != null) map['$pid'] = price;
    }
    return jsonEncode(map);
  }

  /// Decode the stored {providerId: priceBaisas} JSON → {providerId: OMR}.
  static Map<int, double> _deliveryOverrides(String json) {
    if (json.isEmpty || json == '{}') return const {};
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map) {
        final out = <int, double>{};
        decoded.forEach((k, v) {
          final pid = int.tryParse('$k');
          final price = (v as num?)?.toDouble();
          if (pid != null && price != null) out[pid] = price / 1000.0;
        });
        return out;
      }
    } catch (_) {}
    return const {};
  }

  /// API per-product `recipe` ([{ingredient_id, quantity, unit}]) → compact JSON
  /// array [{ingredient_id, quantity}] stored on the product row.
  static String _recipeJson(Object? v) {
    final out = <Map<String, num>>[];
    for (final e in (v as List? ?? const [])) {
      if (e is! Map) continue;
      final iid = (e['ingredient_id'] as num?)?.toInt();
      final qty = (e['quantity'] as num?)?.toDouble();
      if (iid != null && qty != null) out.add({'ingredient_id': iid, 'quantity': qty});
    }
    return jsonEncode(out);
  }

  /// Decode the stored recipe JSON → recipe lines.
  static List<RecipeLine> _recipeFromJson(String json) {
    if (json.isEmpty || json == '[]') return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) => RecipeLine(
                  ingredientId: (m['ingredient_id'] as num?)?.toInt() ?? 0,
                  quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
                ))
            .where((l) => l.ingredientId != 0)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// API `data` map → Drift companions for AppDatabase.replaceConfig. [cursor]
  /// is the envelope's meta.generated_at (a sibling of `data`, so it can't be
  /// read from `data` here) — persisted as the next delta `since`.
  static ParsedConfig parse(Map<String, dynamic> data, {DateTime? now, String? cursor}) {
    final meta = (data['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
    final branchMap = (data['branch'] as Map?)?.cast<String, dynamic>();

    final receiptTemplate = branchMap?['receipt_template'];
    final branch = BranchCacheCompanion(
      id: Value(_int(branchMap?['id']) ?? 0),
      name: Value(_str(branchMap?['name'])),
      nameAr: Value(_strN(branchMap?['name_ar'])),
      latitude: Value(_dbl(branchMap?['latitude'])),
      longitude: Value(_dbl(branchMap?['longitude'])),
      geofenceRadiusM: Value(_int(branchMap?['geofence_radius_m'])),
      defaultOrderType: Value(_strN(branchMap?['default_order_type'])),
      status: Value(_strN(branchMap?['status'])),
      receiptTemplateJson:
          Value(receiptTemplate is Map ? jsonEncode(receiptTemplate) : null),
    );

    final categories = _list(data['categories'])
        .map((c) => CategoriesCompanion(
              id: Value(_int(c['id']) ?? 0),
              name: Value(_str(c['name'])),
              nameAr: Value(_strN(c['name_ar'])),
              displayOrder: Value(_int(c['display_order']) ?? 0),
              status: Value(_strN(c['status'])),
            ))
        .toList();

    final products = _list(data['products'])
        .map((p) => ProductsCompanion(
              id: Value(_int(p['id']) ?? 0),
              name: Value(_str(p['name'])),
              nameAr: Value(_strN(p['name_ar'])),
              categoryId: Value(_int(p['category_id'])),
              basePriceBaisas: Value(_int(p['base_price_baisas']) ?? 0),
              branchStockQty: Value(_dbl(p['branch_stock_qty'])),
              imageUrl: Value(_strN(p['image_url'])),
              status: Value(_strN(p['status'])),
              addonGroupIds: Value(_intList(p['addon_group_ids']).join(',')),
              deliveryPriceBaisas: Value(_int(p['delivery_price_baisas'])),
              deliveryPricesJson: Value(_deliveryPricesJson(p['delivery_prices'])),
              stockMode: Value(_strN(p['stock_mode'])),
              recipeJson: Value(_recipeJson(p['recipe'])),
            ))
        .toList();

    final floors = _list(data['floors'])
        .map((f) => FloorsCompanion(
              id: Value(_int(f['id']) ?? 0),
              name: Value(_str(f['name'])),
              nameAr: Value(_strN(f['name_ar'])),
              displayOrder: Value(_int(f['display_order']) ?? 0),
              status: Value(_strN(f['status'])),
            ))
        .toList();

    final tables = _list(data['tables'])
        .map((t) => PosTablesCompanion(
              id: Value(_int(t['id']) ?? 0),
              floorId: Value(_int(t['floor_id']) ?? 0),
              label: Value(_str(t['label'])),
              seats: Value(_int(t['seats']) ?? 0),
              positionX: Value(_int(t['position_x'])),
              positionY: Value(_int(t['position_y'])),
              width: Value(_int(t['width'])),
              height: Value(_int(t['height'])),
              shape: Value(_strN(t['shape'])),
              displayOrder: Value(_int(t['display_order']) ?? 0),
              status: Value(_strN(t['status'])),
            ))
        .toList();

    final addonGroups = <AddonGroupsCompanion>[];
    final addons = <AddonsCompanion>[];
    for (final g in _list(data['addon_groups'])) {
      final gid = _int(g['id']) ?? 0;
      addonGroups.add(AddonGroupsCompanion(
        id: Value(gid),
        name: Value(_str(g['name'])),
        nameAr: Value(_strN(g['name_ar'])),
        selectionMode: Value(_strN(g['selection_mode'])),
        status: Value(_strN(g['status'])),
      ));
      for (final a in _list(g['addons'])) {
        addons.add(AddonsCompanion(
          id: Value(_int(a['id']) ?? 0),
          addOnGroupId: Value(_int(a['add_on_group_id']) ?? gid),
          name: Value(_str(a['name'])),
          nameAr: Value(_strN(a['name_ar'])),
          priceDeltaBaisas: Value(_int(a['price_delta_baisas']) ?? 0),
          ingredientId: Value(_int(a['ingredient_id'])),
          status: Value(_strN(a['status'])),
        ));
      }
    }

    final taxes = _list(data['taxes'])
        .map((t) => TaxCacheCompanion(
              id: Value(_int(t['id']) ?? 0),
              name: Value(_str(t['name'])),
              nameAr: Value(_strN(t['name_ar'])),
              ratePercent: Value(_dbl(t['rate_percent']) ?? 0),
            ))
        .toList();

    final deliveryProviders = _list(data['delivery_providers'])
        .map((d) => DeliveryProvidersCompanion(
              id: Value(_int(d['id']) ?? 0),
              name: Value(_str(d['name'])),
              color: Value(_strN(d['color'])),
              sortOrder: Value(_int(d['sort_order']) ?? 0),
            ))
        .toList();

    final expenseCategories = _list(data['expense_categories'])
        .map((e) => ExpenseCategoriesCompanion(
              id: Value(_int(e['id']) ?? 0),
              key: Value(_str(e['key'])),
              name: Value(_str(e['name'])),
              nameAr: Value(_strN(e['name_ar'])),
              sortOrder: Value(_int(e['sort_order']) ?? 0),
            ))
        .toList();

    // Per-branch ingredient balances (the device's branch). Drives
    // ingredient-based product availability.
    final branchIngredientStock = _list(data['branch_stock'])
        .map((s) => BranchIngredientStockCompanion(
              ingredientId: Value(_int(s['ingredient_id']) ?? 0),
              quantity: Value(_dbl(s['quantity']) ?? 0),
            ))
        .toList();

    // Merchant discount rules (company-scoped). branch_scope_json + targets are
    // stored as JSON strings; applicability is evaluated on-device.
    final discounts = _list(data['discounts'])
        .map((d) => DiscountsCompanion(
              id: Value(_int(d['id']) ?? 0),
              name: Value(_str(d['name'])),
              scope: Value(_strN(d['scope'])),
              amountType: Value(_strN(d['amount_type'])),
              amountBaisas: Value(_int(d['amount_baisas'])),
              percent: Value(_dbl(d['percent'])),
              validityStart: Value(_date(d['validity_start'])),
              validityEnd: Value(_date(d['validity_end'])),
              dayofweekMask: Value(_int(d['dayofweek_mask'])),
              timeStart: Value(_strN(d['time_start'])),
              timeEnd: Value(_strN(d['time_end'])),
              branchScopeJson: Value(
                d['branch_scope_json'] == null
                    ? null
                    : jsonEncode(d['branch_scope_json']),
              ),
              stackable: Value(d['stackable'] == true),
              requiresManagerApproval:
                  Value(d['requires_manager_approval'] == true),
              status: Value(_strN(d['status'])),
              targetsJson: Value(jsonEncode(d['targets'] ?? const [])),
            ))
        .toList();

    // Loyalty rules (company-scoped). config is stored as a JSON string.
    final loyaltyRules = _list(data['loyalty_rules'])
        .map((r) => LoyaltyRulesCompanion(
              id: Value(_int(r['id']) ?? 0),
              name: Value(_str(r['name'])),
              type: Value(_strN(r['type'])),
              configJson: Value(jsonEncode(r['config'] ?? const {})),
              validityStart: Value(_date(r['validity_start'])),
              validityEnd: Value(_date(r['validity_end'])),
              status: Value(_strN(r['status'])),
            ))
        .toList();

    // Cached customer slice.
    final customers = _list(data['customers'])
        .map((c) => CachedCustomersCompanion(
              id: Value(_int(c['id']) ?? 0),
              name: Value(_str(c['name'])),
              phone: Value(_strN(c['phone'])),
              walletBalanceBaisas: Value(_int(c['wallet_balance_baisas']) ?? 0),
              loyaltyJson: Value(jsonEncode(c['loyalty'] ?? const [])),
            ))
        .toList();

    // Company ingredient catalogue (id + name + unit) for the restock picker.
    final ingredients = _list(data['ingredients'])
        .map((i) => IngredientsCompanion(
              id: Value(_int(i['id']) ?? 0),
              name: Value(_str(i['name'])),
              nameAr: Value(_strN(i['name_ar'])),
              unit: Value(_strN(i['unit'])),
            ))
        .toList();

    // v2 #14 — company POS policy: which staff positions may cancel an order.
    final settings = (data['settings'] as Map?)?.cast<String, dynamic>() ?? const {};
    final cancelPositions = _strList(settings['order_cancel_positions']);

    final metaCompanion = SyncMetaCompanion(
      id: const Value(1),
      companyId: Value(_int(meta['company_id']) ?? _int(branchMap?['company_id'])),
      branchId: Value(_int(meta['branch_id']) ?? _int(branchMap?['id'])),
      lastConfigSyncAt: Value(now ?? DateTime.now()),
      configSchemaVersion: Value(cursor ?? _strN(meta['generated_at'])),
      orderCancelPositions: Value(jsonEncode(cancelPositions)),
    );

    return ParsedConfig(
      branch: branch,
      categories: categories,
      products: products,
      floors: floors,
      tables: tables,
      addonGroups: addonGroups,
      addons: addons,
      taxes: taxes,
      deliveryProviders: deliveryProviders,
      expenseCategories: expenseCategories,
      branchIngredientStock: branchIngredientStock,
      discounts: discounts,
      loyaltyRules: loyaltyRules,
      customers: customers,
      ingredients: ingredients,
      meta: metaCompanion,
    );
  }

  /// API delta `data` map → changed companions + ids to purge. Reuses [parse]
  /// for the changed-row companions (in delta mode `data` holds only the rows
  /// changed since the cursor). `branch` is upserted only when present
  /// ([ConfigDelta.hasBranch] false = the branch row was unchanged this delta).
  static ConfigDelta parseDelta(Map<String, dynamic> data, {DateTime? now, String? cursor}) {
    final changed = parse(data, now: now, cursor: cursor);
    final del = (data['deleted'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ConfigDelta(
      changed: changed,
      hasBranch: data['branch'] != null,
      deleted: DeletedIds(
        floors: _intList(del['floors']),
        tables: _intList(del['tables']),
        categories: _intList(del['categories']),
        products: _intList(del['products']),
        addonGroups: _intList(del['addon_groups']),
        addons: _intList(del['addons']),
        ingredients: _intList(del['ingredients']),
        discounts: _intList(del['discounts']),
        loyaltyRules: _intList(del['loyalty_rules']),
        customers: _intList(del['customers']),
        deliveryProviders: _intList(del['delivery_providers']),
        expenseCategories: _intList(del['expense_categories']),
      ),
    );
  }

  /// Drift rows → existing pos_machine UI models (baisas → double OMR).
  static CatalogSnapshot toCatalog(
    BranchRow? branch,
    List<CategoryRow> cats,
    List<ProductRow> prods,
    List<FloorRow> floors,
    List<TableRow> tables,
    List<TaxRow> taxes, [
    List<AddonGroupRow> addonGroupRows = const [],
    List<AddonRow> addonRows = const [],
    List<DeliveryProviderRow> deliveryProviderRows = const [],
    List<ExpenseCategoryRow> expenseCategoryRows = const [],
    List<BranchIngredientStockRow> branchStockRows = const [],
    List<DiscountRow> discountRows = const [],
    List<LoyaltyRuleRow> loyaltyRuleRows = const [],
    List<CustomerRow> customerRows = const [],
    List<IngredientRow> ingredientRows = const [],
    SyncMetaRow? meta,
  ]) {
    final sortedCats = [...cats]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    final idToName = {for (final c in sortedCats) c.id: c.name};

    final products = prods
        .map((p) => Product(
              id: p.id.toString(),
              name: p.name,
              category: idToName[p.categoryId] ?? '',
              categoryId: p.categoryId,
              price: p.basePriceBaisas / 1000.0,
              addonGroupIds: _idsFromCsv(p.addonGroupIds),
              deliveryPrice: p.deliveryPriceBaisas != null
                  ? p.deliveryPriceBaisas! / 1000.0
                  : null,
              deliveryPriceByProvider: _deliveryOverrides(p.deliveryPricesJson),
              stockMode: p.stockMode,
              recipe: _recipeFromJson(p.recipeJson),
              branchStockQty: p.branchStockQty,
            ))
        .toList();

    final floorDefs = ([...floors]
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder)))
        .map((f) => DiningFloor(id: f.id.toString(), label: f.name))
        .toList();

    // Planner shape default sizes (mirror pos_merchant FloorPlanner SHAPE_DEFAULTS)
    // + auto-arrange for tables not yet placed (mirror the planner: 6-col grid,
    // start (40,40), step 140), so every table still appears on the POS.
    const shapeW = {'round': 80.0, 'square': 80.0, 'rectangle': 120.0, 'oval': 100.0, 'counter': 160.0};
    const shapeH = {'round': 80.0, 'square': 80.0, 'rectangle': 60.0, 'oval': 70.0, 'counter': 40.0};
    const autoStart = 40.0, autoStep = 140.0, autoCols = 6;
    final autoIndexByFloor = <int, int>{};

    final tableDefs = ([...tables]
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder)))
        .map((t) {
          final shape =
              (t.shape == null || t.shape!.isEmpty) ? 'square' : t.shape!;
          final w = t.width?.toDouble() ?? shapeW[shape] ?? 80.0;
          final h = t.height?.toDouble() ?? shapeH[shape] ?? 80.0;
          double x;
          double y;
          if (t.positionX != null && t.positionY != null) {
            x = t.positionX!.toDouble();
            y = t.positionY!.toDouble();
          } else {
            final i = autoIndexByFloor.update(
              t.floorId,
              (v) => v + 1,
              ifAbsent: () => 0,
            );
            x = autoStart + (i % autoCols) * autoStep;
            y = autoStart + (i ~/ autoCols) * autoStep;
          }
          return DiningTableDefinition(
            id: t.id.toString(),
            floorId: t.floorId.toString(),
            name: t.label,
            sizeLabel: shape,
            seats: t.seats,
            sortOrder: t.displayOrder,
            shape: shape,
            positionX: x,
            positionY: y,
            width: w,
            height: h,
          );
        })
        .toList();

    final companyTaxes = ([...taxes]..sort((a, b) => a.id.compareTo(b.id)))
        .map((t) => CompanyTax(name: t.name, nameAr: t.nameAr, ratePercent: t.ratePercent))
        .toList();

    // Add-on groups (company set) + their options; baisas → OMR. Options keep
    // their cached/inserted order (API display_order). Inactive/archived rows
    // are dropped so they never show on the modifier sheet.
    final optionsByGroup = <int, List<AddonOption>>{};
    for (final a in addonRows) {
      if (a.status == 'inactive' || a.status == 'archived') continue;
      (optionsByGroup[a.addOnGroupId] ??= <AddonOption>[]).add(AddonOption(
        id: a.id,
        label: a.name,
        labelAr: a.nameAr,
        priceDelta: a.priceDeltaBaisas / 1000.0,
      ));
    }
    final addonGroups = addonGroupRows
        .where((g) => g.status != 'inactive' && g.status != 'archived')
        .map((g) => AddonGroup(
              id: g.id,
              name: g.name,
              nameAr: g.nameAr,
              multiSelect: (g.selectionMode ?? 'single') == 'multiple',
              options: optionsByGroup[g.id] ?? const <AddonOption>[],
            ))
        .toList();

    final deliveryProviderDefs = ([...deliveryProviderRows]
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
        .map((d) => DeliveryProvider(
              id: d.id,
              name: d.name,
              color: d.color,
              sortOrder: d.sortOrder,
            ))
        .toList();

    final expenseCategoryDefs = ([...expenseCategoryRows]
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
        .map((e) => (key: e.key, name: e.name))
        .toList();

    final ingredientBalances = <int, double>{
      for (final s in branchStockRows) s.ingredientId: s.quantity,
    };

    final receiptTemplate = _receiptTemplate(branch?.receiptTemplateJson);

    final discounts = discountRows
        .map((d) => MerchantDiscount(
              id: d.id,
              name: d.name,
              scope: d.scope ?? 'order',
              amountType: d.amountType ?? 'fixed',
              fixedAmount:
                  d.amountBaisas != null ? d.amountBaisas! / 1000.0 : null,
              percent: d.percent,
              validityStart: d.validityStart,
              validityEnd: d.validityEnd,
              dayOfWeekMask: d.dayofweekMask,
              timeStart: d.timeStart,
              timeEnd: d.timeEnd,
              branchScope: _branchScope(d.branchScopeJson),
              stackable: d.stackable,
              requiresManagerApproval: d.requiresManagerApproval,
              isActive: d.status == null || d.status == 'active',
              targets: _discountTargets(d.targetsJson),
            ))
        .toList();

    final loyaltyRules = loyaltyRuleRows
        .map((r) => LoyaltyRule(
              id: r.id,
              name: r.name,
              type: r.type ?? '',
              config: _decodeConfig(r.configJson),
              isActive: r.status == null || r.status == 'active',
            ))
        .toList();

    final customers = customerRows
        .map((c) => CustomerRef(
              id: c.id,
              name: c.name,
              phone: c.phone ?? '',
              walletBalance: c.walletBalanceBaisas / 1000.0,
              loyalty: _loyaltyBalances(c.loyaltyJson),
            ))
        .toList();

    final ingredients = ingredientRows
        .map((i) => IngredientRef(
              id: i.id,
              name: i.name,
              nameAr: i.nameAr,
              unit: i.unit,
            ))
        .toList();

    return CatalogSnapshot(
      categories: sortedCats.map((c) => c.name).toList(),
      products: products,
      floors: floorDefs,
      tables: tableDefs,
      taxes: companyTaxes,
      addonGroups: addonGroups,
      deliveryProviders: deliveryProviderDefs,
      expenseCategories: expenseCategoryDefs,
      ingredientBalances: ingredientBalances,
      discounts: discounts,
      loyaltyRules: loyaltyRules,
      customers: customers,
      ingredients: ingredients,
      cancelOrderPositions: _cancelPositionsFromMeta(meta),
      receiptTemplate: receiptTemplate,
    );
  }

  /// Decode the cached per-branch receipt template JSON → [ReceiptTemplate].
  /// Returns null when unset / malformed (device falls back to its default).
  static ReceiptTemplate? _receiptTemplate(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      return decoded is Map<String, dynamic>
          ? ReceiptTemplate.fromJson(decoded)
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Decode the cached order-cancel policy JSON → position list. Falls back to
  /// managers-only when unset (older cache / never synced) or malformed.
  static List<String> _cancelPositionsFromMeta(SyncMetaRow? meta) {
    final json = meta?.orderCancelPositions;
    if (json == null || json.isEmpty) return const ['manager'];
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        final out = decoded
            .map((e) => e?.toString().trim() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
        return out.isEmpty ? const ['manager'] : out;
      }
    } catch (_) {}
    return const ['manager'];
  }

  /// Decode a loyalty rule's stored config JSON → map (empty on any failure).
  static Map<String, dynamic> _decodeConfig(String json) {
    if (json.isEmpty || json == '{}') return const {};
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return const {};
  }

  /// Decode a discount's stored targets JSON ([{target_type, target_id}]) →
  /// list of DiscountTarget (for product/category-scope applicability).
  static List<DiscountTarget> _discountTargets(String json) {
    if (json.isEmpty || json == '[]') return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) => DiscountTarget(
                  targetType: m['target_type']?.toString() ?? '',
                  targetId: (m['target_id'] as num?)?.toInt() ?? 0,
                ))
            .where((t) => t.targetType.isNotEmpty && t.targetId != 0)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Decode a cached customer's loyalty JSON ([{rule_id, points, stamps}]) →
  /// LoyaltyBalance list (for offline points display + redeem).
  static List<LoyaltyBalance> _loyaltyBalances(String json) {
    if (json.isEmpty || json == '[]') return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) => LoyaltyBalance.fromJson(m.cast<String, dynamic>()))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Decode a stored branch_scope JSON string → list of branch ids (empty = all).
  static List<int> _branchScope(String? json) {
    if (json == null || json.isEmpty || json == 'null') return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return decoded.map((e) => (e as num?)?.toInt()).whereType<int>().toList();
      }
    } catch (_) {}
    return const [];
  }
}
