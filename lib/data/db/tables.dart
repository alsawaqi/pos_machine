import 'package:drift/drift.dart';

// Drift tables that mirror the branch-scoped config bundle returned by
// pos_api `GET /api/v1/device/config`. This is the offline cache + single
// source of truth for the catalog the POS renders.
//
// IMPORTANT: money is stored as INTEGER baisas (1 OMR = 1000 baisas), matching
// the API wire format. Conversion to `double` OMR happens only at the bridge
// into the existing pos_machine models (see config_mapper.dart).
//
// Row data classes are named `...Row` via @DataClassName so they never collide
// with the existing UI models in lib/models/pos_models.dart (e.g. `Product`).

@DataClassName('BranchRow')
class BranchCache extends Table {
  // The device is assigned to exactly one branch, so this table holds a single row.
  IntColumn get id => integer()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get nameAr => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  IntColumn get geofenceRadiusM => integer().nullable()();
  TextColumn get defaultOrderType => text().nullable()();
  TextColumn get status => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CategoryRow')
class Categories extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get nameAr => text().nullable()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  TextColumn get status => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ProductRow')
class Products extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get nameAr => text().nullable()();
  IntColumn get categoryId => integer().nullable()();
  // MONEY (baisas)
  IntColumn get basePriceBaisas => integer().withDefault(const Constant(0))();
  // Per-branch unit stock; null = not unit-tracked / recipe-depleted.
  RealColumn get branchStockQty => real().nullable()();
  TextColumn get imageUrl => text().nullable()();
  TextColumn get status => text().nullable()();
  // Comma-separated add-on group ids assigned to this product (from the API
  // `addon_group_ids`), resolved against AddonGroups/Addons to build the
  // product's modifier sheet. Empty = no add-ons.
  TextColumn get addonGroupIds => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('FloorRow')
class Floors extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get nameAr => text().nullable()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  TextColumn get status => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TableRow')
class PosTables extends Table {
  IntColumn get id => integer()();
  IntColumn get floorId => integer()();
  TextColumn get label => text().withDefault(const Constant(''))();
  IntColumn get seats => integer().withDefault(const Constant(0))();
  // Floor-plan layout from the merchant planner (px in a 1200x800 canvas).
  // Nullable: null position = not placed yet; null size = use the shape default.
  IntColumn get positionX => integer().nullable()();
  IntColumn get positionY => integer().nullable()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  TextColumn get shape => text().nullable()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  TextColumn get status => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// Parsed + cached now for completeness, but not yet wired into the modifier UI
// (the modifier sheet is currently hardcoded — that is the next increment).
@DataClassName('AddonGroupRow')
class AddonGroups extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get nameAr => text().nullable()();
  TextColumn get selectionMode => text().nullable()(); // single | multiple
  TextColumn get status => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AddonRow')
class Addons extends Table {
  IntColumn get id => integer()();
  IntColumn get addOnGroupId => integer()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get nameAr => text().nullable()();
  // MONEY (baisas)
  IntColumn get priceDeltaBaisas => integer().withDefault(const Constant(0))();
  IntColumn get ingredientId => integer().nullable()();
  TextColumn get status => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// Single-row (id = 1) key/value style metadata about the last successful sync.
@DataClassName('SyncMetaRow')
class SyncMeta extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  IntColumn get companyId => integer().nullable()();
  IntColumn get branchId => integer().nullable()();
  DateTimeColumn get lastConfigSyncAt => dateTime().nullable()();
  TextColumn get configSchemaVersion => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// Company-level taxes (the active set) from the config bundle. Applied on top of
// the order subtotal (exclusive), shown as one cart/receipt line each. `rate` is
// a PERCENTAGE (5.0 = 5%) — not money, so it's a real, not baisas.
@DataClassName('TaxRow')
class TaxCache extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get nameAr => text().nullable()();
  RealColumn get ratePercent => real().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

// Durable outbox for completed orders awaiting push to pos_api
// (POST /device/sync/push). This is the offline-first guarantee: an order is
// persisted here the moment it completes and re-pushed until the server ACKs
// it. NOT part of the catalog cache — replaceConfig never touches it. One row
// per order; [eventsJson] holds the full event batch (order.create / order.pay
// / donation.record) with STABLE client_event_ids so a re-push settles exactly
// once. [syncedAt] null = still pending.
@DataClassName('OrderOutboxRow')
class OrderOutbox extends Table {
  TextColumn get orderUuid => text()();
  TextColumn get eventsJson => text()();
  IntColumn get orderNumber => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {orderUuid};
}
