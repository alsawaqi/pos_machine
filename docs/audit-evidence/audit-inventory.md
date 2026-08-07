# Audit: Inventory & Ingredient Flows (agent: audit-inventory)

Date: 2026-08-07. Read-only audit. All paths repo-relative (Laravel code under each repo's `src/`).
Legend: **VERIFIED** = read in code. **INFERRED** = deduced from verified code, scenario not executed. **CANNOT-VERIFY** = claim of absence / not fully provable by grep.

---

## 1. Ingredient model vs Additions-doc unit-of-measure model

Additions doc (scratchpad `additions.txt` §2.3, lines 233-256) defines: `primary_unit`, `piece_unit_label`, `units_per_piece`, `allow_fractional_pieces`, `cost_per_unit` (= total_paid / total_units_received, last purchase), `min_stock_threshold`.

**VERIFIED — all fields exist** (naming differs slightly):

| Doc field | DB column | Evidence |
|---|---|---|
| primary_unit | `pos_ingredients.unit` (string 16, app enum) | pos_admin/database/migrations/2026_05_29_010100_create_pos_ingredients_table.php:62 |
| piece_unit_label (+Arabic) | `piece_unit_label`, `piece_unit_label_ar` | pos_admin/database/migrations/2026_07_01_010000_add_uom_piece_model_and_stock_counts.php:69-70 |
| units_per_piece | `units_per_piece` decimal(14,4) | same migration:71 |
| allow_fractional_pieces | `allow_fractional_pieces` bool default true | same migration:72 |
| cost_per_unit | `default_unit_cost` decimal(12,3) | 2026_05_29_010100:63 |
| min_stock_threshold | `min_stock_threshold` decimal(12,3) nullable | 2026_05_29_010100:67 |

Supporting tables (same 2026_07_01 migration):
- `pos_ingredient_purchases` (batch rows: pieces_received, units_received, total_paid, unit_cost decimal(12,6), units_per_piece_at_purchase, is_loose, stock_movement_id link): lines 75-120.
- `pos_stock_counts` + `pos_stock_count_lines` (counted_pieces, counted_units, expected_units, variance_units, unit_cost_at_time, stock_movement_id): lines 122-174.
- Alternate entry units: `pos_ingredient_units` (factor decimal(14,4), convert-at-entry, store-in-base) — pos_admin/database/migrations/2026_06_30_010000_create_pos_ingredient_units_table.php.

**VERIFIED** — conversion at entry: pos_merchant/app/Actions/Pos/Inventory/IngredientUnitConverter.php (toBase :41-53; factorFor with base passthrough → custom alt-unit → PD4 metric siblings :62-95; refuses non-positive factor :79-81; caps at 999,999,999.999 to protect decimal(12,3) :34,45-50). Used by transfer (:84 in TransferStockAction), waste (:92 RecordWasteAction), restock, adjust.

**CANNOT-VERIFY (absence)** — *Yield factors do not exist.* `grep -rni 'yield'` over pos_merchant/pos_api app code returns only comment noise (3 hits, none inventory). No yield/shrinkage column anywhere in migrations. Recipes consume gross quantities only.

## 2. stock_mode (unit / ingredient / untracked / cooked)

**VERIFIED** — `pos_products.stock_mode` string(16) default 'untracked' with backfill (recipe→ingredient, else branch stock_qty→unit): pos_admin/database/migrations/2026_06_25_010000_add_stock_mode_to_pos_products.php:32-49. A fourth mode `'cooked'` (kitchen production, P-G1) appears throughout pos_api/devices (e.g. ConsumeInventoryAction.php:164, machine pos_controller.dart:853).
- Product unit-stock tables: `pos_product_stock` (central pool) + `pos_product_stock_movements` (ledger): 2026_06_25_010100/010200. Waste fields (reason, unit_cost) added 2026_07_27_010000_add_waste_fields_to_pos_product_stock_movements.php.
- Central ingredient pool: `pos_ingredient_stock` + `pos_stock_movements.branch_id` made NULLABLE (NULL = central row): pos_admin/database/migrations/2026_07_18_000000_add_central_ingredient_warehouse.php:36-54.

## 3. Consumption at order.pay — ConsumeInventoryAction (pos_api)

File: pos_api/app/Actions/Device/Sync/ConsumeInventoryAction.php. **VERIFIED end-to-end.**

- `consume()` = apply(order, -1); `reverse()` = apply(order, +1): :33-42. Callers:
  - PayOrderHandler.php:178 (`order.pay` — after status flip to PAID, inside one DB txn).
  - DeliverOrderHandler.php:127 (P-G7 no-tender delivery intake consumes at intake).
  - VoidOrderHandler.php:130 (reverse, only when order was paid/pending-verification AND void reason doesn't keep inventory).
- **Double-consume protection**: PayOrderHandler re-reads + `lockForUpdate()` the order inside the txn and re-checks terminal status (PayOrderHandler.php:89-104) — two concurrent pays with different client_event_ids serialize; loser sees STATUS_PAID and throws. Same pattern in VoidOrderHandler.php:101-110 for double-reverse.
- **Ingredient path**: reads the FROZEN `recipe_snapshot_json` per line; merges PD3b option add/remove deltas (`consumption_snapshot_json` on addon rows) clamped at zero per ingredient (`total = max(0, base+Σdelta)`, removal never restocks; sale vs option attribution split): mergeItemConsumption :228-297. Plans rounded to 3dp to avoid float-residue junk rows :273-283.
- **Frozen component consumption (commit a655f46)**: order items carry `component_snapshot_json` written at create (CreateOrderHandler.php:153, snapshotComponents :697-707 — `[]` means genuinely none, NULL = legacy row); pay/void consume the frozen set; live `pos_product_components` read kept ONLY for legacy NULL rows (ConsumeInventoryAction.php:53-67, 238-251). **INFERRED**: voids of pre-freeze legacy orders after a component edit can restock a different set than was consumed — known bounded legacy limitation.
- **Atomic increments (commit d832222)**: `move()` rounds once to 3dp, skips zero, writes the `pos_stock_movements` row via `StockMovement::create` then does a race-safe `firstOrCreate` + SQL-expression `increment('quantity', $qty)` with explicit `updated_at` bump (device delta slice keys on it): :299-346. Same for product shelf in `moveProductStock()` (`whereNotNull('stock_qty')` keeps not-tracked-here = no-op; affected 0 → no ledger row): :364-404. Docblocks name the fixed lost-update bug (read-modify-write absolute save).
- **Unit/product path**: parent product's own shelf (:76), P-G2 components split component/option (:92-109), classic single-ingredient add-ons (skip when PD3b lines present — anti-double-count guard :139-142), P-G3 product-as-add-on by FROZEN stock_mode (unit/cooked → shelf; ingredient → frozen recipe; untracked → nothing; plus the linked product's own frozen components): :161-201.
- **Cost snapshot at sale**: recipe_snapshot_json freezes `unit_cost` per line from `pos_ingredients.default_unit_cost` at create (CreateOrderHandler snapshotRecipe :657-682); movement rows carry `unit_cost_at_time` → historical COGS immune to later cost edits. **PD2**: unit/cooked products freeze NO recipe (:659-661 + docblock 643-655) — prevents double COGS (purchase expense + recipe consumption) and double ingredient depletion (cooked consumed at production).

## 4. Negative stock / oversell policy — coherent matrix, VERIFIED

| Path | Negative allowed? | Evidence |
|---|---|---|
| Sale consumption (ingredient + product shelf) | YES, by design (§9.1.6) | ConsumeInventoryAction.php:26-28, 349-354 |
| Manual waste (merchant) | NO — refuses beyond balance | RecordWasteAction.php:103-116 |
| Device product waste | NO — capped by locked shelf row | ProductWasteHandler.php docblock :28-30 |
| Branch transfer | NO — refuses overdraw (but see finding F3) | TransferStockAction.php:89-97 |
| Restock fulfilment from warehouse | NO — central rows locked, overdraw refused | AllocateRestockRequestAction.php:153-173 |
| Kitchen production start | NO — batch refused if short, rows locked | pos_api StartProductionAction.php:28-29,126 |
| Day-end disposition | NO — capped, locked | ApplyDispositionAction.php:32,105 |

## 5. Append-only ledgers — every writer enumerated (VERIFIED via grep over all three Laravel repos)

`pos_stock_movements` (ingredients) writers:
- pos_merchant: **WriteStockMovementAction** (canonical: ledger row + balance in one txn; tenant re-check; branch NULL = central `pos_ingredient_stock` pool; audit row) — WriteStockMovementAction.php:101-193. Delegating actions: AdjustStockAction / AdjustIngredientStockAction, RestockAction, RecordPurchaseAction, ReceiveIngredientStockAction, AllocateIngredientStockAction, AllocateRestockRequestAction, TransferStockAction, RecordWasteAction, SubmitStockCountAction (via RecordWasteAction/AdjustStockAction).
- pos_api: ConsumeInventoryAction (sale/addon ± reversal), StockCountHandler (waste/adjustment variance), Production actions (StartProduction consumes ingredients, Cancel returns).
- pos_admin: **no writers** — only the read model (pos_admin/app/Models/StockMovement.php); grep for `StockMovement::create|BranchStock::` in pos_admin/app returns nothing.

`pos_product_stock_movements` (product units) writers:
- pos_merchant: **WriteProductStockMovementAction** (canonical; branch NULL = central `pos_product_stock`, else `pos_branch_product.stock_qty`; NULL stock_qty promoted to 0 on allocate) — WriteProductStockMovementAction.php:55-113. Delegators: ReceiveProductStockAction, AllocateProductStockAction, TransferProductStockAction, AdjustProductStockAction, RecordProductWasteAction.
- pos_api: ConsumeInventoryAction::moveProductStock (branch-side sale rows; central pool untouched by design :358-362), ProductWasteHandler, FinishProductionAction (+shelf), ApplyDispositionAction.

No update/delete of ledger rows found anywhere; corrections are new adjustment rows (documented at pos_merchant Models/StockMovement.php:18 and migration docblocks). **CANNOT-VERIFY** exhaustively that no raw `DB::table('pos_stock_movements')->update/delete` exists outside grepped namespaces, but targeted greps found none.

Invariant: `pos_branch_stock.quantity == Σ(movements)` per (branch, ingredient) — enforced by both canonical writers wrapping ledger + balance in one txn (WriteStockMovementAction.php:33-36; ConsumeInventoryAction docblock :20-24); central twins on `pos_ingredient_stock`/`pos_product_stock` where branch_id IS NULL (2026_07_18 migration :17-21).

## 6. Restock request → fulfilment

**VERIFIED** lifecycle: draft/submitted (device: pos_api RestockRequestHandler.php:46-75 — creates request rows only, NO stock movement) → review (ReviewRestockRequestAction) → Approved → either:
- **Warehouse fulfilment** (AllocateRestockRequestAction.php): pre-plan per line (override ≤ requested, 0 legal), per-ingredient needs totalled, central `pos_ingredient_stock` rows locked in deterministic ksort order, overdraw refused (:153-173); paired legs per non-zero line — `allocation_out` at central (negative) + `restock` at branch (positive), both referencing RestockRequestLine (:199-229); status → Fulfilled, `resolution='warehouse'` (:232-238). Docblock records that **pre-Phase-A fulfilment credited the branch with no debit anywhere** ("stock appeared from nothing", :28-31) — legacy rows have resolution NULL and were never corrected (2026_08_05_010100 migration :24-26).
- **Purchased closure** (ResolvePurchasedRestockRequestAction.php:56-64): status → Fulfilled, `resolution='purchase'`, deliberately NO stock movement (goods entered via the purchase record; avoids double count).
- Cancel path exists (CancelRestockRequestAction). Resolution columns: pos_admin migration 2026_08_05_010100.

## 7. GRN purchase receipts (Phase A / Phase B)

**VERIFIED** — pos_merchant CreatePurchaseReceiptAction.php:
- Phase A (migration 2026_07_24_010000_create_pos_purchase_receipts_tables.php): one atomic submit; mixed ingredient/product lines each fan out to ReceiveAndDistribute{Ingredient,Product}StockAction (central receive + optional per-line branch splits; undistributed remainder stays central); named charges book their own expenses; credit/AP fields (is_credit, due_date, amount_paid, payment_status :146-158; payables migration 2026_07_26); tax columns (2026_07_25).
- Phase B (migration 2026_08_05_010200): `destination_branch_id` — direct-to-branch delivery; every line's allocations overridden to 100% destination (:89-98) through the same conserved pipeline (central +receive then allocation_out/in pair, net central zero).
- ReceiveAndDistributeIngredientStockAction guards distributed ≤ received up front (:60-70); inner allocate re-checks ≤ central balance under row lock.
- **Partial receiving: N/A** — there is no purchase-order stage; a GRN is a one-shot document created already in status `'received'` (:111). Nothing to partially receive against. **CANNOT-VERIFY** any PO concept exists anywhere (none found in migrations/routes).
- **No void/reversal of a GRN**: routes are index/store/show/payments only (pos_merchant routes/web.php:569-577). A mis-entered receipt can only be unwound by manual adjustments (stock) — the booked expenses and AP rows have no linked reversal flow. See finding F4.

## 8. Branch-to-branch transfers

**VERIFIED** backend: TransferStockAction.php — header `pos_branch_transfers` + lines w/ unit_at_set + unit_cost_at_time (migration 2026_06_13_010000); paired transfer_out (−) / transfer_in (+) both referencing the transfer (:129-150); alt-unit conversion before checks (:84); refuses overdraw (:89-97). Product twin: TransferProductStockAction. UI exists: merchant routes `branch-transfers` (web.php:599-606), product/ingredient stock transfer endpoints (web.php:402-403, 516-517), 25 `Transfer` matches in Pages/Merchant/Inventory/Index.vue. Devices have no transfer feature (by design; central actions are portal-only — devices never see central rows, 2026_07_18 migration :29-30).

**Finding F3 (TOCTOU)**: the available-stock check runs BEFORE `DB::transaction` with no row lock (TransferStockAction.php:89-100 vs txn at :102); a concurrent device sale (which may legally drive stock negative) or second transfer can invalidate it → source goes negative despite the refuse-overdraw intent. Ledger invariant still holds (blind increment); only the policy is violated. Same pattern in RecordWasteAction (:106-116 check outside the txn at :122).

## 9. Central pool vs branch stock

**VERIFIED** — dual-pool design for both ingredients (`pos_ingredient_stock` central / `pos_branch_stock` per-branch, movements branch_id NULL vs set — 2026_07_18 migration) and products (`pos_product_stock` central / `pos_branch_product.stock_qty` — 2026_06_25 migrations). Devices only ever read/write branch rows (ConsumeInventoryAction moveProductStock deliberately leaves central untouched :358-362). Central overdraw refused everywhere (allocate/fulfil/production).

## 10. Waste logging

**VERIFIED**:
- Ingredient waste (merchant): RecordWasteAction — `pos_waste_records` row (positive qty, reason enum, 'other' requires notes :99-101, frozen unit_cost) + negative `waste` movement in one txn; no DeleteWasteAction by design (:53-55).
- Product waste (merchant): RecordProductWasteAction — frozen per-unit cost = cost_price, else cooked recipe cost (:89-91).
- Product waste (device): pos_api ProductWasteHandler — `product.waste` sync event, atomic multi-line, reasons mirrored (:41), shelf-capped under lock, cost frozen; "loss-tracking, NOT an expense" (cash model) :32-34.
- Machine UI: waste_product_screen.dart; handheld: HH-9 ops_screens.dart:137.
- Count shortfalls auto-write waste rows with reason `reconciliation_variance` (see §12).

## 11. Portion variance report

**VERIFIED** — pos_merchant PortionVarianceReportAction.php: per-ingredient decomposition in qty AND money using FROZEN unit_cost_at_time; buckets = theoretical (sale+addon movements), waste (excl. reconciliation_variance), count_variance (from pos_stock_count_lines), manual adjustments (not count-linked), production net; logistics movements excluded; double-count exclusions via reason filter + stock_movement_id link; coverage honesty (last_counted_at, uncounted headline); cadence caveat documented (:1-66). Also InventoryConsumptionReportAction (counted/variance columns per Additions §2.11) and LossWasteReportAction; device-side BuildBranchReportAction stockConsumption nets sale+addon movements so voids cancel (:310-346).

## 12. Day-end count / reconciliation

**VERIFIED** — dual-surface, mirrored logic:
- Portal: SubmitStockCountAction — counted pieces × units_per_piece → units; expected = CURRENT running balance; variance <0 → WasteRecord(reconciliation_variance) + waste movement, >0 → adjustment; one txn (:22-47; shortfall value at :171, cost at :195).
- Device: pos_api StockCountHandler — same conversion (unitsPerPiece mirror :210-217; fractional-piece rejection :98-102), expected read per line at apply time (:134-138), waste/adjustment movements + count lines (:140-198). Machine screen: stock_count_screen.dart (submits via `stock.count` sync event, **online-required** — expense_restock_service.dart:13-16, 58-67; refreshes config after so gating sees corrected balances :91-96). Handheld parity: HH-9 (order_sync_service.dart:633-756, ops_screens.dart:595).
- **NOT blind**: the machine count screen lists each ingredient WITH its on-book balance (stock_count_screen.dart:13-14, 124, 160-171); the merchant page likewise shows balances. Staff can see the expected number while counting — variance is gameable. The Additions doc doesn't mandate blind counting, but controls-wise this is a gap (finding F5).
- **Timing hazard (finding F2)**: expected = balance at server apply time. The machine does NOT flush its own OrderOutbox before pushing a `stock.count` (stock_count_screen.dart:84-96 calls submitStockCount directly; flush lives in order_sync_repository.dart:150 and is triggered from staff_pos_screen timers :249,345 — not from the count flow). If unsynced paid orders exist (own outbox, or another device offline), the count reconciles against a balance that excludes them; when they replay, consumption deducts AGAIN on top of the variance waste → stock understates by the overlap (and waste is over-blamed). INFERRED scenario over VERIFIED mechanics.

## 13. Costing

- **Sale-time snapshot**: VERIFIED (§3) — recipe lines freeze unit_cost at order create; movements freeze unit_cost_at_time; reports use frozen costs.
- **Cost recalculation on receipt**: model is *last-purchase-wins*, NOT average — and only on ONE of the two purchase paths. RecordPurchaseAction (piece-aware purchase form, Additions §2.4): `default_unit_cost = total_paid / units` + loose-batch units_per_piece update (:219-229). **The GRN path never recalculates**: ReceiveIngredientStockAction stamps the OLD `default_unit_cost` on the movement and updates nothing (:105-115); grep confirms only RecordPurchaseAction + UpdateIngredientAction (manual) write `default_unit_cost`. Product `cost_price` is only ever manual (UpdateProductAction/ImportProductsAction) — a product GRN line's cost never updates it. Finding F1.
- `pos_ingredient_purchases.unit_cost` is decimal(12,6) for sub-baisa per-gram costs (2026_07_01 migration :47-48, :100).

## 14. Sold-out gating on devices (machine + handheld parity)

**VERIFIED parity** (same switch semantics):
- Machine: pos_controller.dart `isOutOfStock` :848-865 — unit: qty!=null && ≤0 (null = untracked-here = sellable); cooked: (qty ?? 0) ≤ 0 (never produced = sold out); ingredient: any recipe line's branch balance < one unit's need; untracked: never. Add-on gating `isAddonOptionUnavailable` :879-922 (linked product same pool; PD3b 'add' lines gate qty-aware for unit/cooked; missing-from-catalog product lines SKIPPED not blocked — internal packaging never ships to devices, server consumes it, may go negative by policy :874-878).
- Handheld: catalog.dart:1283-1304 (`soldOut` switch, comment names machine parity), addon lines :797-822.
- Local depletion after sale: **shelf counts only** (unit/cooked) on both devices, clamped at 0, overwritten by next config sync — machine app_database.dart consumeProductShelfStock :286-305; handheld main.dart _consumeShelfStockLocally :707-737 (with double-decrement guard when a config poll replaced the snapshot mid-flow :717-727) + shelf-cap add-to-cart guard (`_isAtShelfCap` :709, catalog.dart:780).
- **Ingredient balances are NOT depleted locally** — machine `ingredientBalances` is only assigned on config apply (pos_controller.dart:250,705; no other mutation). Offline, ingredient-mode gating goes stale and oversells silently (policy-consistent with negative stock, but unbounded while offline). Server delta re-emits products whose branch shelf moved (BuildDeviceConfigAction.php:119-143 — delta ORs in pos_branch_product.updated_at > cursor, fixing the stale-cooked-cap bug) and branch_stock delta keys on updated_at (ConsumeInventoryAction.php:330-332).
- Ingredient-mode gating checks ONE unit's requirement, not cart quantity — a cart of 10 passes when stock covers 1 (pos_controller.dart:855-861). Oversell tolerated by policy; noted only.

## 15. Paths where stock can silently become wrong (charter sweep)

| Path | Status |
|---|---|
| Void/refund restoration | SOUND: full reverse on paid void inside one txn + row lock; `affects_inventory` void reasons intentionally KEEP consumption (VoidOrderHandler.php:85-99,130); no refund flow exists at all (void is the only unwind; docblock :47-51). Pending-verification delivery voids unwind like paid (:111-115). |
| Double pay / double void replay | SOUND: (device_id, client_event_id) UNIQUE + lockForUpdate re-check; FAILED events are re-dispatched on re-push, so a transient fault can't strand a paid sale with no consumption (IngestSyncEventsAction.php:59-76). |
| Offline replay vs day-end count | **F2** — expected-at-apply-time vs queued sales (own outbox not flushed first; other devices' queues). |
| Transfers | **F3** — TOCTOU on the availability check (policy only, ledger stays consistent). |
| GRN mistakes | **F4** — no GRN void/reversal document. |
| Deletes of ingredients in use | SOUND: DeleteIngredientAction refuses when any branch stock ≠ 0, central pool ≠ 0, recipe refs, PD3b add-on consumption lines, legacy add-on refs, open restock lines (DeleteIngredientAction.php:66-120+). Unit-change guard in UpdateIngredientAction. Soft-delete keeps history resolvable. |
| Deletes of products mid-queue | SOUND: create snapshots resolve withTrashed (CreateOrderHandler.php:139); commit bf0bf72 "Offline orders survive a mid-queue product/add-on delete". |
| Cross-branch leakage | SOUND: pay/void resolve order scoped to device company+branch; WriteStockMovementAction re-checks tenant (:87-92); device order transfer restricted to same company+branch (TransferOrderHandler.php:27-28,54). |
| Legacy pre-Phase-A restock fulfilments | Stock was credited from nothing; acknowledged, not retro-corrected (resolution NULL rows). Historical books overstate inflows. |
| Rounding drift | Addressed: 3dp-once rule in move()/moveProductStock() (d832222 follow-up), plan rounding in mergeItemConsumption (:270-283). |
| Negative-stock anomaly surfacing | Additions §2.6 says negative balances are "flagged as anomalies" — no dedicated anomaly flag/badge found in merchant UI or reports (low-stock badge exists via min_stock_threshold). CANNOT fully verify absence (F6, verified:false). |

## 16. Key commits (pos_api git log, VERIFIED present)
- a655f46 "Consume the component set frozen at order create, not the live rows"
- d832222 "Sale-path stock writes: atomic increments, no more lost updates"
- d46a8a3 "Harden recipe→branch inventory deduction (concurrency, ledger, retry)"
- 53d0777 device product.waste; df5fe08 Phase A device contract (piece fields + stock.count); 2df8075/36ac307 kitchen production + FIFO day-end disposition; eef6e61/P-G4 central warehouse; 8cf241e P-G2 components; acf94e0 P-G3 product-as-add-on; d55e931 PD3b frozen option consumption; 52848cf PD2 unit products freeze no recipe.

## Findings

**F1 (P2)** — GRN receiving never updates ingredient `default_unit_cost` (or product `cost_price`), so sale-time COGS snapshots go stale for merchants using the GRN flow. ReceiveIngredientStockAction.php:105-115 stamps the old cost and updates nothing; only RecordPurchaseAction.php:219-229 implements Additions §2.4 step 4. The two purchase paths produce different costing states for identical purchases. Also NO average-cost model exists anywhere — last-purchase-wins only (matches Additions doc, so the gap is the GRN path, not the model choice).

**F2 (P2)** — Day-end count reconciles against the balance at server-apply time; the machine does not flush its order outbox before submitting `stock.count`, and other devices' queued sales can land after the count → the late sales deduct on top of the variance waste (double depletion; waste over-blamed). stock_count_screen.dart:84-96; StockCountHandler.php:134-138; order_sync_repository.dart:150. Mechanics verified; the loss scenario is inferred (timing-dependent).

**F3 (P3)** — Transfer/waste availability checks are TOCTOU (pre-transaction, no lock): TransferStockAction.php:89-102, RecordWasteAction.php:106-122. A concurrent sale can push the source negative despite the refuse-overdraw intent. Ledger invariant unaffected.

**F4 (P3)** — No GRN void/correction flow (routes/web.php:569-577: index/store/show/payments only). Data-entry mistakes require manual stock adjustments; the auto-booked expenses/AP rows have no linked reversal.

**F5 (P3)** — Day-end counts are not blind: both surfaces show the on-book balance next to the entry field (stock_count_screen.dart:13-14,160-171), so the variance number is trivially gameable by staff.

**F6 (P3, verified:false)** — No negative-stock "anomaly" flag found (Additions §2.6 expects one); greps over merchant Inventory UI + reports found none, but absence is not exhaustively provable.

**F7 (P3)** — Offline ingredient-mode oversell is unbounded: ingredientBalances only refresh on config sync, never depleted locally (pos_controller.dart:250,705). Consistent with the negative-stock policy but silent while offline. Shelf-tracked products DO deplete locally on both devices.

**F8 (P3, informational)** — Pre-Phase-A restock fulfilments credited branches without any debit (AllocateRestockRequestAction.php:28-31; 2026_08_05_010100 migration :24-26). Historical ledger inflows overstated; no backfill correction.
