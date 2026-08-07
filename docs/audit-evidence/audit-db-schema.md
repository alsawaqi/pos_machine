# MITHQAL 2.0 — Database Schema Audit (audit-db-schema)

Scope: every migration in `pos_admin/src/database/migrations` (the schema owner — 153 files, all read in full),
plus the two test-mirror schemas (`pos_api/src/database/migrations/0000_00_00_000000_create_test_schema.php`,
`pos_merchant/src/database/migrations/0000_00_00_000000_create_test_schema.php`), plus targeted verification in
app config/models. All statements below are VERIFIED against file content unless marked INFERRED / Cannot-Verify.
Evidence format: `repo/relative/path:line`. Migration paths are abbreviated `pos_admin/.../migrations/<file>`.

---

## 1. Ground facts (verified)

| Fact | Evidence |
|---|---|
| pos_admin is the sole owner of pos_* DDL; pos_api + pos_merchant each have exactly ONE migration, a `testing`-env-guarded sqlite mirror | dir listings; pos_api/src/database/migrations/0000_00_00_000000_create_test_schema.php:28-30; pos_merchant mirror :50, :1773 |
| pos_admin's migration-history table is `pos_admin_migrations`; pos_api and pos_merchant use the default `migrations` table (the same physical table the charity app uses in the shared DB) | pos_admin/src/config/database.php:130-131; pos_api/src/config/database.php:130-131; pos_merchant/src/config/database.php:130-131 |
| All three Laravel apps run `'timezone' => 'UTC'` — DB timestamps are UTC wall-clock; business time is carried in dedicated `occurred_at`/`opened_at`/`captured_at` columns distinct from `created_at` | pos_admin/src/config/app.php:85; pos_api/src/config/app.php:68; pos_merchant/src/config/app.php:68 |
| Original schema was `pos_admin_*`; renamed wholesale to `pos_*` (16 tables) on 2026-05-24; index/constraint names deliberately keep the `pos_admin_*` form | pos_admin/.../migrations/2026_05_24_000000_rename_pos_admin_tables_to_pos_prefix.php:25-82 |
| Duplicate Laravel infra tables (pos_admin_sessions/cache/jobs/PAT…) were dropped; pos_admin reuses the charity DB's canonical `sessions`, `password_reset_tokens`, `cache`, `jobs`, `personal_access_tokens` | 2026_05_18_000000_drop_duplicate_pos_admin_infrastructure_tables.php:18-33 |
| POS **never writes `charity_transactions` directly** — round-ups land in POS-owned `pos_roundup_donations`; forwarding to charity happens over HTTP (`POST /api/donations-pos-roundup`) from pos_api and pos_admin | 2026_06_18_010000_create_pos_roundup_donations_table.php:8-20; pos_api/src/app/Actions/Device/Sync/ForwardCharityDonationAction.php:14; pos_admin/src/app/Actions/Admin/Reconciliation/ForwardCharityDonationAction.php:20; pos_api/src/app/Actions/Device/Sync/Handlers/DonationRecordHandler.php:30 |
| Charity/marketing-owned tables the POS touches: **reads + real FKs**: `banks`, `commission_profiles`, `organizations` (pos_devices FKs, restrictOnDelete); **reads, soft ids**: `countries`/`regions`/`districts`/`cities` (pos_branches geo columns are plain indexed ids); **writes**: `advertisers` (admin onboarding), `content_assets` (review fields only) | 2026_05_25_020000:… commission_profile FK; 2026_05_26_020000 bank FK; 2026_06_27_000000 organization FK; 2026_05_12_160004 (branches geo ids, :120-123); pos_admin/src/app/Models/{Bank,Organization,CommissionProfile,Advertiser,ContentAsset}.php ($table overrides); pos_admin actions CreateAdvertiserAction/UpdateAdvertiserAction/ReviewContentAction |
| 9 conditional "stub" migrations create charity/marketing-owned tables only `if (!Schema::hasTable(...))`: commission_profiles, banks, countries, regions, districts, cities, organizations, advertisers, content_assets (+ pos_company_settings-if-missing) — no-ops in production **provided charity migrated first** | 2026_05_25_015000, 2026_05_26_010000, 2026_06_16_010000..010003, 2026_06_26_999999, 2026_06_26_100000/100001, 2026_08_04_010000 |

## 2. Entity inventory — ~105 live pos_* tables

Legend: C=company_id, B=branch_id, SD=softDeletes, AO=append-only (by convention), U=key unique constraints.
All money columns `decimal(12,3)` unless noted.

### 2.1 Tenancy / identity / access
| Table | Purpose | Keys / notes |
|---|---|---|
| pos_companies | merchant + advertiser-only tenants | uuid U; cr_number, vat_number idx; SD; `default_tax_rate` dec(5,2) def 5.00 (superseded by pos_taxes); `is_advertiser_only` flag (2026_06_26_110000) |
| pos_users | portal users (platform_admin + merchant); C nullable FK | email U; setup_token_hash U; branch_scope_json; must_change_password; 2FA columns (2026_07_06); phone TEXT (encrypted cast, 2026_05_26_030000) |
| pos_branches | branch master; C FK cascade | (C,code) U; geo ids (country/region/district/city) plain indexed ids — **no FK to charity geo**; lat/lng dec(10,7); geofence_radius_m def 500; opening_hours_json; receipt_template json; SD |
| pos_branch_user | user↔branch pivot | (branch,user) U |
| pos_company_owners | 1:N owners (replaced flat columns w/ data migration) | civil_id/phone/email TEXT (encrypted); is_primary app-enforced (no partial unique — documented choice, 2026_05_24_030000:984-990) |
| pos_business_activities / pos_company_activities | activity catalogue + pivot | code U; (C,activity) U |
| pos_company_documents | KYC docs | sha256 idx; verification_status; SD |
| pos_company_status_history | AO status trail | changed_at useCurrent |
| pos_permissions/pos_roles/pos_model_has_*/pos_role_has_permissions | spatie, teams=company_id | team-scoped role unique; pos_roles + is_system/description |
| pos_settings | platform key/value | key U (global) |
| pos_company_settings | per-merchant POS policy key/value | (C,key) U — **ownership contradiction, see F-8** |
| pos_saved_views | per-user filter presets | (user,view_key,name) U |
| pos_password_reset_tokens | POS-portal reset tokens, keyed by user_id (not email) to avoid the charity table | token_hash U; used_at single-use (2026_07_05_010000:585-611) |
| pos_audit_logs | portal audit trail | nullableMorphs auditable; created_at only |

### 2.2 Devices
| Table | Purpose | Keys / notes |
|---|---|---|
| pos_devices | fleet master | serial U, kiosk_id U, device_token U(hashed), (bank_id,terminal_id) U (2026_06_15 replaced global terminal U); FKs → charity `commission_profiles`/`banks`/`organizations` restrictOnDelete; terminal_pin plain string (deliberate — cross-APP_KEY, 2026_07_05_000000:24-31); last_lat/lng/battery; SD |
| pos_device_activation_tokens | one-time activation | token_hash U, expires_at idx |
| pos_device_assignments_history | AO assignment audit | (device,assigned_at) idx, (device,unassigned_at) idx; created_at only |
| pos_device_makes / pos_device_models | hardware catalogue | name U; (make,name) U |

### 2.3 Staff, floors, tables
| Table | Notes |
|---|---|
| pos_staff | PIN workforce; pin_hash bcrypt; phone TEXT(enc); **pgsql partial unique** (C,staff_code) WHERE staff_code NOT NULL AND deleted_at NULL (2026_05_27_010000:157-167) — one of only two tables with soft-delete-aware uniques; SD |
| pos_floors | (branch,name) U; C+B; SD |
| pos_tables | (floor,label) U; qr_token U global; planner x/y/w/h; SD |
| pos_order_tables | joined dine-in tables pivot; (order,table) U (2026_07_30) |

### 2.4 Catalog
| Table | Notes |
|---|---|
| pos_product_categories | (C,name) U (includes soft-deleted!); parent_id **no FK** (documented sqlite constraint, 2026_06_12:1774-1780); branch_availability_json |
| pos_products | base_price/cost_price/delivery_price 12,3; tax_rate 5,2 (NULL=inherit); **pgsql partial uniques** (C,sku)/(C,barcode) WHERE NOT NULL AND deleted_at NULL; stock_mode varchar16 ('ingredient'/'unit'/'untracked'/'cooked' — 'cooked' added with NO ddl, 2026_07_14 doc); low_stock_threshold; tax_inclusive (stored, **not honored** — 2026_07_04:472-481); show_on_customer_tablet; available_from/until HH:MM:SS; is_internal + internal_purpose; shelf_life_days; SD |
| pos_addon_groups | (C,name) U; selection_mode; min/max_selections; is_global; owner_product_id FK (private groups); SD |
| pos_addons | price_delta 12,3; ingredient_id FK wired late (2026_05_30_010200); linked_product_id FK (product-as-addon); is_default; SD |
| pos_addon_group_products / pos_addon_group_categories | binding pivots, U pairs |
| pos_addon_consumptions | per-option consumption lines; ingredient XOR component_product (app-enforced); direction add/remove; U (addon,ingredient,direction) + (addon,product,direction) |
| pos_product_components | components (cups/lids) per product; (product,component) U |
| pos_product_recipes | (product,ingredient) U; qty 12,3; unit_at_set snapshot |
| pos_product_recipe_versions | AO pre-edit recipe snapshots (recipe_json TEXT) — history for COGS (2026_05_30_010100) |
| pos_delivery_providers | (C,name) U; commission_percent 5,2; SD |
| pos_product_delivery_prices | (product,provider) U; price 12,3 |
| pos_taxes | (C,name) U; rate_percent 5,2; SD; supersedes companies.default_tax_rate |
| pos_discounts | 6-axis predicate; amount 12,3; dayofweek_mask tinyint; time HH:MM:SS strings; branch_scope_json; auto_apply (2026_07_09); SD |
| pos_discount_targets | polymorphic target_id **no FK** (documented); (discount,type,id) U |
| pos_offers | 5 offer types; config JSON with money in **integer baisas** (2026_07_13:1164-1167); same axes as discounts; SD |

### 2.5 Ingredient inventory
| Table | Notes |
|---|---|
| pos_suppliers | (C,name) U; SD |
| pos_ingredients | (C,name) U; unit varchar16; default_unit_cost 12,3; min_stock_threshold 12,3; piece model: piece_unit_label, units_per_piece dec(14,4), allow_fractional_pieces (2026_07_01_010000); SD |
| pos_ingredient_units | alternate entry units; factor dec(14,4); (ingredient,name) U; SD |
| pos_ingredient_purchases | purchase-batch costing; **unit_cost dec(12,6)** (documented deviation — per-gram costs < 0.001 OMR; 2026_07_01_010000:1838-1844); total_paid 12,3; links stock_movement_id |
| pos_branch_stock | mutable balance per (B,ingredient) U; invariant qty == SUM(movements) per branch (doc 2026_05_29_010200:1087-1093) |
| pos_ingredient_stock | central-pool mutable balance per (C,ingredient) U (2026_07_18) |
| pos_stock_movements | **AO ingredient ledger**; signed qty 12,3; unit_cost_at_time 12,3 frozen; polymorphic reference; occurred_at vs created_at; branch_id went NULLABLE for central rows (2026_07_18:1669-1672); idx (B,occurred), (ingredient,occurred), (ref_type,ref_id) |
| pos_waste_records | queryable waste view (reason enum) mirroring a waste movement; unit_cost_at_time frozen; no SD by design |
| pos_stock_counts / pos_stock_count_lines | day-end counts; expected/counted/variance frozen; links variance movement |
| pos_restock_requests / _lines | branch pull workflow (draft→submitted→approved→fulfilled); resolution 'warehouse'/'purchase' added 2026_08_05_010100 — **NULL = legacy rows that credited branch with NO central debit** (admitted in doc :1404-1407) |
| pos_branch_transfers / _lines | immediate paired transfer_out/in; (transfer,ingredient) U |
| pos_purchase_receipts / _lines / _charges / _payments | GRN + AP; frozen totals; tax columns (2026_07_25); is_credit/amount_paid/payment_status + AO payment history w/ balance_after (2026_07_26); destination_branch_id (2026_08_05_010200); SD on header |

### 2.6 Unit-product inventory
| Table | Notes |
|---|---|
| pos_branch_product | (B,product) U; is_available + stock_qty (NULL = not unit-tracked); **no-rows = available everywhere**; documented delta-sync blind spot (referenced in 2026_07_04:487-495) |
| pos_product_stock | central pool per (C,product) U |
| pos_product_stock_movements | **AO product-unit ledger** (parallel of pos_stock_movements); branch NULL = central; waste reason + frozen unit_cost added 2026_07_27; idx (C,product,occurred), (B,occurred), reference |
| pos_productions / pos_production_lines | kitchen batches (start/finish/cancel); expires_at per batch (2026_07_15); lines split recipe vs is_extra |

### 2.7 Customers / loyalty
| Table | Notes |
|---|---|
| pos_customers | (C,phone) U **includes soft-deleted rows**; wallet_balance 12,3 mutable; date_of_birth, tags_json; SD |
| pos_customer_vehicle_plates | went M:N 2026_07_08: (C,customer,plate) U + (C,plate) idx |
| pos_customer_wallet_ledger | AO; amount_delta/balance_after 12,3; kept when point ledger was dropped |
| pos_loyalty_rules | type + config_json; SD |
| pos_loyalty_accounts | (customer,rule) U; mutable stamp_count/point_balance |
| pos_loyalty_transactions | AO; signed deltas + balance_after_*; **order_id unsignedBigInteger, no FK, no index — the "Phase 8 wires this" promise was never delivered** (2026_06_08_010200:1502-1504; no later migration touches it) |
| (dropped) pos_customer_point_ledger, pos_customer_loyalty_configs | superseded by loyalty_* (2026_06_08_010300) |

### 2.8 Orders / payments / shifts / sync
| Table | Notes |
|---|---|
| pos_orders | C+B FKs; device/staff/customer/table nullable FKs; money: subtotal, discount_total, comp_total, tax_total, grand_total 12,3 frozen; invariant subtotal − discount − comp + tax == grand ±1 baisa (2026_07_04:477-480); `client_event_id` **globally unique** (2026_06_04_010000:596); opened_at/closed_at business time; lat/lng; void_reason_id FK + void_reason_label snapshot; receipt_number (not unique, daily reset); delivery lifecycle columns (12 cols, 2026_07_20); transfer columns (2026_07_31); idx: (C,opened), (B,opened), (C,status), customer, (staff,opened), (C,receipt), (C,provider), (B,transfer_target) — hot paths covered |
| pos_order_items | product_name_snapshot, unit_price_snapshot, line_discount, line_total 12,3; qty 12,3; recipe_snapshot_json; component_snapshot_json (2026_08_05 — closed the last live-read drift in void restock, doc :1349-1355); **no company/branch columns** (join through order) |
| pos_order_item_addons | add_on_name/price_delta snapshots; ingredient_snapshot_json; linked_product_id + product_snapshot_json; consumption_snapshot_json |
| pos_order_discounts | per-rule attribution; name/amount_type snapshots; discount_id XOR offer_id both nullable FKs; reason varchar160; C+B denormalised |
| pos_order_comps | comp write-offs; reason code/name snapshots; is_gift; approved_by_pos_staff_id |
| pos_void_reasons / pos_comp_reasons | (C,code) U; affects_inventory / max_amount; seeded defaults backfilled per company; SD |
| pos_payments | amount/change_given 12,3; softpos refs; status + pending_reconciliation flag; reconciled_by/at; captured_at (useCurrent default); bank_response jsonb; terminal_id/bank_id/device_id plain ids; roundup_amount; charity_transaction_id plain id; bank_fee 12,3 (2026_08_02); **no company_id/branch_id — tenant scope requires join through pos_orders**; idx order, pending_recon, (method,captured) |
| pos_shifts | opening/closing/expected_cash + variance 12,3; is_shared (HH-2, 2026_08_01); **no unique open-shift constraint (documented app-enforced)**; **no shift_id back-reference exists on pos_orders or pos_payments anywhere in the schema** (grep across all 153 migrations: zero hits for shift_id outside pos_shifts) |
| pos_order_sequences | numbering counters; functional unique idx COALESCE(branch,0)+COALESCE(seq_date,'1970-01-01') on pgsql+sqlite (2026_07_12_010000:1064-1078) |
| pos_sync_events | AO idempotency ledger; (device_id, client_event_id) U — re-scoped per device 2026_06_22 explicitly to kill a cross-tenant dedupe-suppression vector (doc :584-591); payload/result jsonb; client_timestamp vs server_received_at |
| pos_expenses | amount 12,3 gross + tax_amount/tax_rate (2026_07_25); branch nullable (2026_06_20); dual provenance staff/portal-user |
| pos_expense_categories | (C,key) U; seeded six defaults per company |

### 2.9 Money — commissions / settlements / payouts / invoices / round-ups
| Table | Notes |
|---|---|
| pos_commission_profiles | POS-owned per-merchant split (DISTINCT from charity `commission_profiles`); C U; merchant_percent 5,2 residual |
| pos_commission_shares | split lines; percent 5,2; applies_to all/card/cash_bank (2026_08_03_010300) |
| pos_sale_commissions | **AO per-sale split snapshot**; plain ids (no FKs, by design for device-written money tables); (order_id, sort_order) U = idempotency; gross/commission 12,3; `channel` card/cash_bank/'all'-legacy (2026_08_06_010000 — doc admits **"the confirmed leak"**: mixed-tender orders' whole-order merchant residual was claimed into payouts and the cash slice paid out twice, :1493-1500); settlement columns settled_amount/is_settled/settled_at/settlement_id (2026_07_28); payout_id claim (2026_07_01_010100); invoice_id claim (2026_08_03_010100) |
| pos_commission_settlements | settlement event header; estimated vs actual bank fee, variance; manual/bank_file; applied/reversed |
| pos_payouts | platform→merchant settlement; frozen split snapshot; pending/paid/cancelled; branch_id optional (2026_07_29, hasColumn-guarded — dev-DB drift admitted) |
| pos_commission_invoices | merchant→platform bill (cash/bank_pos channel); frozen split + cash_gross/bank_pos_gross; issued/paid/void |
| pos_roundup_donations | POS-owned donation rows mirroring charity_transactions shape for later UNION; `client_event_id` **globally unique** (2026_06_18:456); forwarded_at gate (2026_07_11 — donations on pending card charges withheld from charity until reconciled; backfill stamped history) |

### 2.10 Marketing / advertising
pos_marketing_sliders (+_items, +_targets): admin-curated ad loops; cross-app ids FK-free. pos_marketing_impressions: per-play telemetry; U (device_id, client_event_id) — **both columns nullable** ⇒ NULL event ids bypass the replay guard (2026_06_29_120000:1695-1718). pos_ad_rate_cards / pos_ad_invoices: advertiser billing; pricing/delivery snapshot frozen; period-overlap guard is action-level only (documented, 2026_08_06_010200:1603-1606).

### 2.11 Messaging / targets
pos_staff_messages(+reads), pos_portal_messages(+reads): read-time audience resolution; receipts U per (message, staff/user). pos_branch_targets(+windows): goal frozen at window finalization; (target, window_start) U.

---

## 3. Assessment against charter questions

### 3.1 Money precision (OMR 12,3?)
**VERIFIED consistent.** Every OMR money column across all 153 migrations is `decimal(12,3)`. Justified deviations, each documented in-migration: `pos_ingredient_purchases.unit_cost` dec(12,6) (per-gram costs; totals stay 12,3); percent columns dec(5,2); unit-conversion factors dec(14,4); offer/device-config wire money = integer baisas inside JSON (2026_07_13:1164-1167). No float/double money columns anywhere.

### 3.2 Ledger vs mutable-balance pairs
Four ledger/balance pairs, all same pattern (mutable balance + AO ledger, invariant enforced by an Action in one transaction, **no DB trigger/constraint enforcement**):
1. pos_branch_stock & pos_ingredient_stock ↔ pos_stock_movements
2. pos_branch_product.stock_qty & pos_product_stock ↔ pos_product_stock_movements
3. pos_loyalty_accounts ↔ pos_loyalty_transactions
4. pos_customers.wallet_balance ↔ pos_customer_wallet_ledger
Plus AO-with-running-balance: pos_purchase_receipt_payments (balance_after). Append-only is convention-only: nothing at the DB layer (trigger, rule, revoked UPDATE) prevents mutation of ledger rows — confirmed by reading every migration (zero CREATE TRIGGER/RULE statements).

### 3.3 Snapshot coverage / historical integrity
**Broadly excellent and consistently applied**: product name+unit price+recipe+components on order items; addon name/price/ingredient/product/consumption snapshots; discount + offer name/amount-type snapshots; comp + void reason snapshots; commission percent/party/profile snapshots; payout + invoice split snapshots; delivery commission percent + expected payout snapshots; GRN frozen totals + item-name snapshots; recipe versions table; target-window goal freeze; ad-invoice pricing snapshot. Known historical holes, both admitted in migration docblocks:
- component consumption was a live read until 2026_08_05_010000 (voids restocked the *new* component set → pos_branch_product / product-ledger drift for orders sold before then);
- legacy fulfilled restock requests (resolution NULL) credited branch stock with no central debit (2026_08_05_010100:1404-1407).
- **Deliberate history rewrite**: delivery-provider confirmation re-stamps `pos_orders.opened_at` to the confirmation moment (2026_07_20_010000:40-44) — the sale's business time mutates; the original moment survives only in delivery_punched_at. All opened_at-windowed history (reports, target windows) silently moves.

### 3.4 Idempotency / uniqueness
- pos_sync_events: (device_id, client_event_id) U — correct per-device scope after 2026_06_22 fix.
- **pos_orders.client_event_id and pos_roundup_donations.client_event_id are still GLOBALLY unique** (2026_06_04_010000:596; 2026_06_18_010000:456). The exact cross-tenant reasoning that forced the sync_events re-scope (2026_06_22:584-591) applies to these two: a colliding id from another tenant's device hits the same unique index. Insert-collision behavior lives in pos_api (other charter), but the schema-level inconsistency is verified.
- pos_sale_commissions: idempotent via (order_id, sort_order) U; client_event_id not unique (fine — supporting column).
- pos_marketing_impressions: (device_id, client_event_id) U with both nullable ⇒ NULL rows replayable.

### 3.5 Indexes on hot paths
Covered well: orders (C,opened)(B,opened)(C,status)(staff,opened)(customer); movements (B,occurred)(ingredient,occurred)(reference); product movements (C,product,occurred)(B,occurred); payments (order)(pending_recon)(method,captured)(bank)(device)(terminal); sale_commissions (C,created)(order,channel)(payout)(settlement)(invoice); sync_events (device,received)(ack_status). Gaps:
- pos_loyalty_transactions.order_id: no index, no FK (order→loyalty lookback scans).
- pos_payments has no company/branch columns: any admin per-company reconciliation list must join pos_orders (indexes exist on both sides; acceptable but the ONLY money table without direct tenant scope).
- No shift linkage on orders/payments (see F-5).

### 3.6 Soft-delete vs unique-constraint interplay
Only pos_products (sku/barcode) and pos_staff (staff_code) use pgsql partial uniques excluding `deleted_at`. Every other soft-deleted table pairs SD with a **hard** unique that includes trashed rows: pos_customers (C,phone), pos_ingredients (C,name), pos_suppliers (C,name), pos_product_categories (C,name), pos_addon_groups (C,name), pos_delivery_providers (C,name), pos_taxes (C,name), pos_floors (B,name), pos_tables (floor,label)+(qr_token), pos_void_reasons/(C,code), pos_comp_reasons/(C,code), pos_expense_categories/(C,key), pos_offers-none, pos_discounts-none. Consequence: soft-deleting then re-creating the same name/phone/code fails at the DB with a unique violation until the trashed row is restored or hard-deleted. Verified from the create migrations (no later partial-index migrations exist for these).

### 3.7 Duplicated / overlapping concepts
- Two parallel AO stock ledgers (ingredient vs product-unit) — deliberate, clean split, but every consumer must query both for "all stock activity".
- **Three purchase-entry constructs**: pos_ingredient_purchases (batch costing, 12,6 unit cost), restock-request fulfillment (movement writer), pos_purchase_receipts GRN (line_cost + expense booking). Unit-cost truth lives in three shapes; the resolution column (2026_08_05_010100) exists precisely because restock + purchase interplay double-counted stock.
- pos_waste_records (ingredient waste view) vs waste rows inside BOTH movement ledgers (product waste got reason/unit_cost columns instead of its own view table, 2026_07_27) — asymmetric modelling of the same concept.
- pos_companies.default_tax_rate + pos_products.tax_rate vs pos_taxes multi-tax list — the former superseded but still present (2026_06_24 doc says supersedes).
- Charity `commission_profiles` vs POS `pos_commission_profiles` — same name, different meaning; disambiguated only in docblocks (2026_06_26_010000:936-944).

### 3.8 Additive-migration coexistence with charity DB
- Rule "strictly additive" holds for pos_* tables with three deliberate exceptions (all pre-production, documented): drop of pos_admin infra duplicates, the pos_* rename, drop of legacy loyalty tables.
- Risks: (a) stub migrations assume charity migrates first on any fresh shared DB — if pos_admin runs first, the stubs create minimal `banks`/`countries`/… tables and the charity app's own CREATE TABLE migrations will subsequently fail (unenforced ordering assumption, stated only in comments). (b) Real FKs from pos_devices into charity-owned banks/organizations/commission_profiles restrictOnDelete: charity-side deletes now fail while POS rows reference them — cross-app coupling the charity team may not know about. (c) pos_api/pos_merchant share the charity's `migrations` history table name; a stray `php artisan migrate` from either app against the shared DB records the test-schema row in charity's migrations table (the body no-ops via the testing guard, so harmless but polluting).

### 3.9 Test-mirror drift (pos_api + pos_merchant sqlite mirrors)
Verified drift as of HEAD:
- `pos_payments.bank_fee` (prod 2026_08_02) missing from **both** mirrors (pos_api mirror pos_payments block; pos_merchant mirror pos_payments block — grep 'bank_fee' zero hits in both files).
- `pos_shifts.is_shared` (prod 2026_08_01) present in pos_api mirror (:841) but **missing from pos_merchant's** pos_shifts block.
- pos_api mirror carries admin-written columns for shape parity (settled_amount, invoice_id, channel, applies_to — verified present), so the bank_fee omission is an oversight, not policy.
- Structural relaxations are documented policy: mirrors use plain integer FKs, TEXT for jsonb; pos_api mirror omits merchant-only tables (payouts, purchase receipts, invoices, settlements, branch targets, portal messages), pos_merchant mirror omits pos_sync_events + marketing tables it never touches — both consistent with each app's read set except noted gaps.

### 3.10 Nullable use
Generally disciplined (NULL is load-bearing and documented: branch NULL=central, seq_date NULL=continuous, component_snapshot NULL=legacy…). Watch items: pos_expenses dual-provenance "exactly one of" pairs (staff/user) app-enforced only; pos_purchase_receipt_lines item_type XOR FKs app-enforced; pos_addon_consumptions XOR app-enforced. No CHECK constraints anywhere in the schema (portability choice).

---

## 4. Findings (ranked)

**F-1 (P1, verified)** — Mixed-tender commission double-pay: schema owner's own migration documents "the confirmed leak" — mixed card+cash orders recorded ONE whole-order merchant-residual row; payouts claimed it whole and paid the merchant the cash slice the platform never held. The 2026_08_06 `channel` column is "step one"; all pre-existing rows are `channel='all'` and any already-paid payouts that claimed mixed-order rows embody the overpayment (no backfill/correction migration exists in the schema). Evidence: pos_admin/.../2026_08_06_010000_add_channel_to_pos_sale_commissions.php:1493-1500.

**F-2 (P2, verified)** — Delivery confirmation mutates pos_orders.opened_at (business sale time) so revenue re-dates to confirmation; all historical opened_at-windowed aggregates silently shift, and only delivery_punched_at preserves the original. Deliberate, but it is the single place the schema's otherwise-strict "history never rewrites" rule is broken. Evidence: 2026_07_20_010000:40-44.

**F-3 (P2, verified)** — Idempotency-key scoping inconsistency: pos_sync_events was re-scoped to (device_id, client_event_id) explicitly to close a cross-tenant duplicate-suppression vector, but pos_orders.client_event_id and pos_roundup_donations.client_event_id remain globally unique, exposing the same class of cross-tenant collision at row level. Evidence: 2026_06_22_010000:584-591 (rationale); 2026_06_04_010000:596; 2026_06_18_010000:456.

**F-4 (P2, verified)** — Soft-delete/unique collision pattern: ~13 soft-deleted tables carry hard uniques that include trashed rows (customers phone, ingredient/supplier/category/addon-group/tax/provider names, floor/table labels, reason codes, expense-category keys); re-creating a deleted entity with the same natural key fails at the DB. Only pos_products and pos_staff received the partial-unique treatment. Evidence: 2026_06_01_010000:1760 vs 2026_05_27_040100:593-603.

**F-5 (P2, verified)** — No shift linkage in the schema: zero `shift_id` columns exist outside pos_shifts (grep across all 153 migrations). expected_cash/variance and all per-shift money attribution must be reconstructed by (device/staff, time-window) joins; with HH-2 shared shifts spanning devices, there is no referential anchor tying an order/payment to the shift that owns it. Evidence: 2026_06_04_020100:992-996 (doc says ShiftAction computes from "orders linked to this shift" — no link column); 2026_08_01_010000.

**F-6 (P2, verified)** — Historical ledger-conservation holes admitted in-migration: (a) legacy fulfilled restock requests credited branch stock with NO central debit (resolution NULL rows, 2026_08_05_010100:1404-1407); (b) pre-2026_08_05 orders void-restocked live component sets, drifting pos_branch_product + product ledger (2026_08_05_010000:1349-1355). No reconciliation/backfill migration corrects the drifted balances.

**F-7 (P2, verified)** — Charity-DB coexistence assumptions unenforced: 9 hasTable-guarded stubs create charity/marketing-owned tables when absent; ordering ("charity always migrates first") is comment-only, and pos_admin-first on a fresh DB would break charity's own CREATEs. Real restrictOnDelete FKs from pos_devices into charity `banks`/`organizations`/`commission_profiles` couple charity deletes to POS state. Evidence: 2026_05_25_015000:1407-1443; 2026_05_26_020000:1633-1645; 2026_06_27_000000.

**F-8 (P3, verified)** — pos_company_settings ownership contradiction: 2026_06_29_010000 (pos_admin) creates it unconditionally and calls the schema admin-owned; 2026_08_04_010000 (also pos_admin) declares "OWNED by pos_merchant — the merchant portal created it" and guards with hasTable. Both live in the same app's chain; the second is a permanent no-op there. Confusing ownership record for a shared table.

**F-9 (P3, verified)** — Test-mirror drift: pos_payments.bank_fee (2026_08_02) missing from both pos_api and pos_merchant mirrors; pos_shifts.is_shared (2026_08_01) missing from pos_merchant's mirror. Tests touching bank-fee prefill or shared-shift flows in those apps run against a stale shape. Evidence: pos_api/src/database/migrations/0000_00_00_000000_create_test_schema.php (pos_payments block, no bank_fee); pos_merchant mirror (pos_shifts block, no is_shared; pos_payments block, no bank_fee).

**F-10 (P3, verified)** — pos_marketing_impressions replay guard unique(device_id, client_event_id) has both columns nullable; rows with NULL client_event_id are freely duplicable — and impressions now drive advertiser billing (pos_ad_invoices metering). Evidence: 2026_06_29_120000:1695-1718; 2026_08_06_010100:1544-1547.

**F-11 (P3, verified)** — pos_loyalty_transactions.order_id: unconstrained AND unindexed; the create-migration's "Phase 8 wires this to pos_orders" promise was never delivered (no later migration touches the column). Evidence: 2026_06_08_010200:1502-1504.

**F-12 (P3, verified — behavior cannot-verify)** — Append-only ledgers and frozen snapshots are enforced purely at the application layer: no triggers, rules, CHECK constraints, or column privileges anywhere in the schema protect AO tables from UPDATE/DELETE. A bug or manual SQL can silently rewrite the ledgers the money model depends on. (Whether any code path does so is outside this charter.)

**F-13 (P3, schema fact verified; behavior cannot-verify)** — pos_payments.captured_at defaults to useCurrent (server clock). For offline card tenders synced hours later, correctness depends on pos_api always overwriting it with device capture time; the default silently stamps sync-time money otherwise. Evidence: 2026_06_04_020000:908.

## 5. Cannot-verify / out-of-charter notes
- Whether pos_api handles the pos_orders.client_event_id global-unique collision by replaying the ACK (info leak) or erroring (DoS) — pos_api charter.
- Whether payouts already issued against channel='all' rows were manually corrected — requires production data.
- Charity app's actual `migrations` table contents / geo table shapes — charity repo not audited beyond POS touchpoints.
