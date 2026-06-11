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
  // Merchant-authored custom receipt template (JSON); null = device default.
  TextColumn get receiptTemplateJson => text().nullable()();

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
  // Phase B — add-on groups bound at the CATEGORY level (JSON int array).
  // A product's modifier sheet unions these with its own addonGroupIds.
  TextColumn get addonGroupIdsJson => text().withDefault(const Constant('[]'))();

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
  // Gap sweep G1 — daily availability window 'HH:MM:SS' (both null = always
  // orderable; from > until wraps midnight). Evaluated on the device clock.
  TextColumn get availableFrom => text().nullable()();
  TextColumn get availableUntil => text().nullable()();

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
  // Phase B — selection constraints. NULL = unbounded; min >= 1 makes the
  // group REQUIRED (the customize sheet blocks Add until satisfied).
  IntColumn get minSelections => integer().nullable()();
  IntColumn get maxSelections => integer().nullable()();
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
  // Phase B — pre-selected when the customize sheet opens.
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  IntColumn get ingredientId => integer().nullable()();
  TextColumn get status => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// Phase B (Additions §1.2) — company void reason codes: the cancel dialog
// requires one when any exist; order.void sends the picked id back.
@DataClassName('VoidReasonRow')
class VoidReasons extends Table {
  IntColumn get id => integer()();
  TextColumn get code => text().withDefault(const Constant(''))();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get nameAr => text().nullable()();
  BoolColumn get affectsInventory => boolean().withDefault(const Constant(false))();
  BoolColumn get requiresManager => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

// Phase B — comp reasons (manager write-offs). max_amount caps a single comp.
@DataClassName('CompReasonRow')
class CompReasons extends Table {
  IntColumn get id => integer()();
  TextColumn get code => text().withDefault(const Constant(''))();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get nameAr => text().nullable()();
  // MONEY (baisas); null = no cap.
  IntColumn get maxAmountBaisas => integer().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

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
  // v2 #14 — JSON list of staff positions allowed to cancel an order at the POS
  // (company policy from /device/config `settings.order_cancel_positions`).
  // null = not yet synced → the device falls back to managers-only.
  TextColumn get orderCancelPositions => text().nullable()();
  // P-F6 — JSON list of staff positions allowed to open the branch Reports
  // screen (`settings.reports_positions`). null = managers-only fallback.
  TextColumn get reportsPositions => text().nullable()();

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

// Company expense categories (Utilities, Supplies, …) for the device's
// expense-logging screen. The device offers these by `key` (the value
// submitted to the API) labelled by `name`. Cached offline; the screen falls
// back to a hardcoded const list when this table is empty.
@DataClassName('ExpenseCategoryRow')
class ExpenseCategories extends Table {
  IntColumn get id => integer()();
  TextColumn get key => text().withDefault(const Constant(''))();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get nameAr => text().nullable()();
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
  // P-F4 — order-scope rules with auto_apply self-apply to every qualifying
  // order (product/category scopes auto-apply per line regardless).
  BoolColumn get autoApply => boolean().withDefault(const Constant(false))();
  TextColumn get status => text().nullable()();
  // [{target_type, target_id}] — for product/category scope (cached for a future
  // per-line-discount increment; unused by the order-scope picker today).
  TextColumn get targetsJson => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}

// Merchant loyalty rules from the config bundle (company-scoped). `type` is
// visit_based (stamp card) | spend_based (points); `configJson` holds the
// type-specific config (stamps_required / points_per_omr / redemption_value …).
// The device sends a rule id on order.pay to earn, and uses spend_based config
// to fund a redemption discount.
@DataClassName('LoyaltyRuleRow')
class LoyaltyRules extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get type => text().nullable()(); // visit_based | spend_based
  TextColumn get configJson => text().withDefault(const Constant('{}'))();
  DateTimeColumn get validityStart => dateTime().nullable()();
  DateTimeColumn get validityEnd => dateTime().nullable()();
  TextColumn get status => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// A cached slice of the company customer book (for offline lookup + attaching a
// customer to an order). The full book is searched online via
// /device/customers/search; this is the offline fallback. Money is baisas.
@DataClassName('CustomerRow')
class CachedCustomers extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get phone => text().nullable()();
  IntColumn get walletBalanceBaisas => integer().withDefault(const Constant(0))();
  // Cached loyalty balances per rule: JSON [{rule_id, points, stamps}]. Drives
  // OFFLINE points display + redeem (the live search refreshes it when online).
  TextColumn get loyaltyJson => text().withDefault(const Constant('[]'))();
  // P-F2 — the customer's vehicle-plate links, JSON ["1234AB", ...]. Offline
  // plate lookup + the customer-details dialog.
  TextColumn get platesJson => text().withDefault(const Constant('[]'))();

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

// Company ingredient catalogue (id + name + unit) from the config `ingredients`
// slice. Lets the device's restock-request screen show ingredient NAMES while
// sending the integer ingredient_id the server expects. (BranchIngredientStock
// only holds balances keyed by id — no names — so this is the name lookup.)
@DataClassName('IngredientRow')
class Ingredients extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get nameAr => text().nullable()();
  TextColumn get unit => text().nullable()(); // kg, litre, piece, …
  // Phase A (Additions §2.3) — the piece model, so the day-end count
  // screen can ask for "bottles on the shelf" instead of litres.
  // label + ratio come as a pair from /device/config; both null =
  // not piece-tracked (unless unit itself is 'piece' → ratio 1).
  TextColumn get pieceUnitLabel => text().nullable()();
  TextColumn get pieceUnitLabelAr => text().nullable()();
  RealColumn get unitsPerPiece => real().nullable()();
  BoolColumn get allowFractionalPieces =>
      boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}
