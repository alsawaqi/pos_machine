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
  final SyncMetaCompanion meta;
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

  static List<Map<String, dynamic>> _list(Object? v) =>
      (v as List?)
          ?.whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList() ??
      const [];

  static List<int> _intList(Object? v) =>
      (v as List?)?.map((e) => (e as num?)?.toInt()).whereType<int>().toList() ??
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

  /// API `data` map → Drift companions for AppDatabase.replaceConfig.
  static ParsedConfig parse(Map<String, dynamic> data, {DateTime? now}) {
    final meta = (data['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
    final branchMap = (data['branch'] as Map?)?.cast<String, dynamic>();

    final branch = BranchCacheCompanion(
      id: Value(_int(branchMap?['id']) ?? 0),
      name: Value(_str(branchMap?['name'])),
      nameAr: Value(_strN(branchMap?['name_ar'])),
      latitude: Value(_dbl(branchMap?['latitude'])),
      longitude: Value(_dbl(branchMap?['longitude'])),
      geofenceRadiusM: Value(_int(branchMap?['geofence_radius_m'])),
      defaultOrderType: Value(_strN(branchMap?['default_order_type'])),
      status: Value(_strN(branchMap?['status'])),
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

    final metaCompanion = SyncMetaCompanion(
      id: const Value(1),
      companyId: Value(_int(meta['company_id']) ?? _int(branchMap?['company_id'])),
      branchId: Value(_int(meta['branch_id']) ?? _int(branchMap?['id'])),
      lastConfigSyncAt: Value(now ?? DateTime.now()),
      configSchemaVersion: Value(_strN(meta['generated_at'])),
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
      meta: metaCompanion,
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
  ]) {
    final sortedCats = [...cats]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    final idToName = {for (final c in sortedCats) c.id: c.name};

    final products = prods
        .map((p) => Product(
              id: p.id.toString(),
              name: p.name,
              category: idToName[p.categoryId] ?? '',
              price: p.basePriceBaisas / 1000.0,
              addonGroupIds: _idsFromCsv(p.addonGroupIds),
              deliveryPrice: p.deliveryPriceBaisas != null
                  ? p.deliveryPriceBaisas! / 1000.0
                  : null,
              deliveryPriceByProvider: _deliveryOverrides(p.deliveryPricesJson),
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

    return CatalogSnapshot(
      categories: sortedCats.map((c) => c.name).toList(),
      products: products,
      floors: floorDefs,
      tables: tableDefs,
      taxes: companyTaxes,
      addonGroups: addonGroups,
      deliveryProviders: deliveryProviderDefs,
    );
  }
}
