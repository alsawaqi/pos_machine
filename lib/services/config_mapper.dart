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
  });

  final List<String> categories;
  final List<Product> products;
  final List<DiningFloor> floors;
  final List<DiningTableDefinition> tables;
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
    required this.meta,
  });

  final BranchCacheCompanion branch;
  final List<CategoriesCompanion> categories;
  final List<ProductsCompanion> products;
  final List<FloorsCompanion> floors;
  final List<PosTablesCompanion> tables;
  final List<AddonGroupsCompanion> addonGroups;
  final List<AddonsCompanion> addons;
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
  ) {
    final sortedCats = [...cats]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    final idToName = {for (final c in sortedCats) c.id: c.name};

    final products = prods
        .map((p) => Product(
              id: p.id.toString(),
              name: p.name,
              category: idToName[p.categoryId] ?? '',
              price: p.basePriceBaisas / 1000.0,
            ))
        .toList();

    final floorDefs = ([...floors]
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder)))
        .map((f) => DiningFloor(id: f.id.toString(), label: f.name))
        .toList();

    final tableDefs = ([...tables]
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder)))
        .map((t) => DiningTableDefinition(
              id: t.id.toString(),
              floorId: t.floorId.toString(),
              name: t.label,
              sizeLabel:
                  (t.shape == null || t.shape!.isEmpty) ? 'Standard' : t.shape!,
              seats: t.seats,
              sortOrder: t.displayOrder,
            ))
        .toList();

    return CatalogSnapshot(
      categories: sortedCats.map((c) => c.name).toList(),
      products: products,
      floors: floorDefs,
      tables: tableDefs,
    );
  }
}
