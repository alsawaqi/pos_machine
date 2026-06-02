import 'dart:async';

import '../services/config_mapper.dart';
import '../services/pos_api_service.dart';
import 'db/app_database.dart';

/// Fetches the branch config from pos_api, caches it in Drift, and exposes the
/// cached catalog as a stream. Drift is the single source of truth, so the UI
/// renders identically online or offline.
class ConfigRepository {
  ConfigRepository(this._api, this._db);

  final PosApiService _api;
  final AppDatabase _db;

  /// Online refresh: pull `/device/config` and replace the cache atomically.
  Future<void> fetchAndCache() async {
    final data = await _api.fetchConfig();
    final parsed = ConfigMapper.parse(data);
    await _db.replaceConfig(
      branch: parsed.branch,
      categoryRows: parsed.categories,
      productRows: parsed.products,
      floorRows: parsed.floors,
      tableRows: parsed.tables,
      addonGroupRows: parsed.addonGroups,
      addonRows: parsed.addons,
      meta: parsed.meta,
    );
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
    var seenCats = false, seenProds = false, seenFloors = false, seenTables = false;

    void emit() {
      if (seenCats && seenProds && seenFloors && seenTables) {
        controller.add(ConfigMapper.toCatalog(branch, cats, prods, floors, tables));
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
    ];

    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
    };

    return controller.stream;
  }
}
