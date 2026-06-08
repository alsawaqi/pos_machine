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
  // In-house delivery price (baisas); null = use base_price for delivery too.
  IntColumn get deliveryPriceBaisas => integer().nullable()();
  // Per-delivery-provider price overrides, JSON object {providerId: priceBaisas}.
  // Resolution on the device: this map[provider] → deliveryPriceBaisas → base.
  TextColumn get deliveryPricesJson => text().withDefault(const Constant('{}'))();
  // Phase 7 — stock mode: unit | ingredient | untracked. Drives device sold-out
  // enforcement (null = untracked).
  TextColumn get stockMode => text().nullable()();
  // Recipe ingredient lines, JSON array [{"ingredient_id":N,"quantity":Q}].
  // An ingredient-mode product is sold out when any line's branch ingredient
  // balance < its quantity (BranchIngredientStock).
  TextColumn get recipeJson => text().withDefault(const Constant('[]'))();

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

// Company delivery providers (Talabat, Otlob, …) for the POS provider picker
// shown on a delivery order. Per-product provider prices live on the product
// row (Products.deliveryPricesJson). `color` is an optional #RRGGBB UI hint.
@DataClassName('DeliveryProviderRow')
class DeliveryProviders extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get color => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

// Merchant discount rules from the config bundle (company-scoped). The device
// offers the currently-applicable ORDER-scope ones in the discount picker;
// applicability (validity window / day-of-week mask / time window / branch
// scope) is evaluated on-device (see MerchantDiscount). Money is baisas.
// product/category-scope discounts are cached but not yet applied (the device
// has no per-line discount model yet) — order-scope only for now.
@DataClassName('DiscountRow')
class Discounts extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get scope => text().nullable()(); // product | category | order
  TextColumn get amountType => text().nullable()(); // fixed | percent
  IntColumn get amountBaisas => integer().nullable()(); // fixed amount
  RealColumn get percent => real().nullable()(); // percent amount
  DateTimeColumn get validityStart => dateTime().nullable()();
  DateTimeColumn get validityEnd => dateTime().nullable()();
  IntColumn get dayofweekMask => integer().nullable()(); // 1<<dow, Sun=0; null=all
  TextColumn get timeStart => text().nullable()(); // 'HH:MM:SS'
  TextColumn get timeEnd => text().nullable()();
  TextColumn get branchScopeJson => text().nullable()(); // [branchId,...]; null=all
  BoolColumn get stackable => boolean().withDefault(const Constant(false))();
  BoolColumn get requiresManagerApproval =>
      boolean().withDefault(const Constant(false))();
  TextColumn get status => text().nullable()();
  // [{target_type, target_id}] — for product/category scope (cached for a future
  // per-line-discount increment; unused by the order-scope picker today).
  TextColumn get targetsJson => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}

// Per-branch INGREDIENT balances (from the config `branch_stock` slice), keyed
// by ingredient id. Drives ingredient-based product availability: a recipe
// product is sold out when a needed ingredient's balance here is below the
// recipe quantity.
@DataClassName('BranchIngredientStockRow')
class BranchIngredientStock extends Table {
  IntColumn get ingredientId => integer()();
  RealColumn get quantity => real().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {ingredientId};
}
