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
    final parsed = ConfigMapper.parse(config.data);
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
      meta: parsed.meta,
    );
    await _session.saveTerminalId(config.terminalId);
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
    var seenCats = false, seenProds = false, seenFloors = false, seenTables = false, seenTaxes = false;

    void emit() {
      if (seenCats && seenProds && seenFloors && seenTables && seenTaxes) {
        controller.add(ConfigMapper.toCatalog(
          branch, cats, prods, floors, tables, taxes, addonGroups, addons,
          deliveryProviders,
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
    ];

    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
    };

    return controller.stream;
  }
}
