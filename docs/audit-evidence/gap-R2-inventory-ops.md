# Gap analysis — R2 Inventory Operations (14 reqs)

Agent: gap analyst, domain R2. Date 2026-08-07. Read-only. Sources: audit-inventory.md, map-pos_merchant.md, audit-db-schema.md, keyfacts_all.md, plus direct code verification (all direct checks below marked VERIFIED-NOW).

Legend: ✅ FULL · 🟡 PARTIAL · 🔴 MISSING · ⚠️ INCORRECT · 🔵 DIFFERENT · ⚪ CANNOT_VERIFY

| ID | Status | Priority |
|---|---|---|
| R2.1 | 🟡 PARTIAL | P2 |
| R2.2 | ✅ FULL | — |
| R2.3 | 🟡 PARTIAL | P1 |
| R2.4 | 🔴 MISSING | P2 |
| R2.5 | 🔴 MISSING | P2 |
| R2.6 | 🔴 MISSING | P2 |
| R2.7 | 🟡 PARTIAL | P3 |
| R2.8 | 🟡 PARTIAL | P3 |
| R2.9 | 🟡 PARTIAL | P2 |
| R2.10 | 🟡 PARTIAL | P3 |
| R2.11 | 🟡 PARTIAL | P3 |
| R2.12 | ✅ FULL | — |
| R2.13 | 🟡 PARTIAL | P3 |
| R2.14 | ✅ FULL | — |

---

## R2.1 — Blind stock counting + count-control features (S5.1) — 🟡 PARTIAL, P2

**Exists:** Stock counting is real on three surfaces: merchant portal (pos_merchant SubmitStockCountAction; stock-counts routes web.php:594-596), device sync `stock.count` (pos_api StockCountHandler with piece→unit conversion :98-108), machine screen (pos_machine lib/screens/stock_count_screen.dart), handheld HH-9 (pos_handheld lib/screens/ops_screens.dart:595, order_sync_service.dart:724-753). Schema: pos_stock_counts + pos_stock_count_lines (pos_admin migration 2026_07_01_010000:122-174) with expected/counted/variance frozen.

**Missing (each verified):**
- **Blind counting**: counts are NOT blind — the machine count screen lists each ingredient WITH its on-book balance (stock_count_screen.dart:13-14,160-171, per audit-inventory F5); the merchant page likewise shows balances. Variance is gameable by staff.
- **Value-based count frequency tiers (daily/weekly/monthly)**: no scheduling/frequency concept. VERIFIED-NOW: `grep -rniE "count_frequency|rotation|spot.?check|too.?perfect|blind"` over pos_merchant app/ + resources/js returns only unrelated hits (PortionVarianceReportAction "variance-blind" coverage wording, User.php key-rotation comment).
- **Count-when-idle w/ timestamp reconcile**: no count-timestamp back-dating; expected = balance at server APPLY time (StockCountHandler.php:134-138), which is the opposite of timestamp-reconciled counting and creates the queued-sale double-depletion window (audit-inventory F2).
- **Physical-layout ordering**: no layout/ordering concept on count lines (schema has none; UI lists ingredients alphabetically per audit).
- **Offline counting on handheld**: NOT offline. VERIFIED-NOW: pos_handheld pushes stock.count "ONLINE, NOT via the durable outbox … throws on a network error (the caller shows 'offline, try again')" (pos_handheld lib/services/order_sync_service.dart:755-766, pushOpsEvent). Machine likewise online-required (pos_machine lib/services/expense_restock_service.dart:13-16).
- **Counter rotation + spot checks, flag too-perfect counters**: nothing exists (same grep as above).

**Priority rationale:** counting mechanics work and reconcile; what is missing is the entire anti-fraud control layer that S5.1 is about, and blind counting is step 7 of the [S] Part 8 build order.

## R2.2 — Day-end reconciliation: pieces → units → variance waste + note (A§2.8) — ✅ FULL

- Portal: SubmitStockCountAction — counted pieces × units_per_piece → units; variance <0 → WasteRecord(reason `reconciliation_variance`) + waste movement, >0 → adjustment; one txn (audit-inventory §12). Note capture VERIFIED-NOW: `?string $note` param, trimmed and stored on the count row and propagated into per-line waste/adjustment notes (SubmitStockCountAction.php:63,130-137,165-179,211,222-237).
- Device: pos_api StockCountHandler mirrors conversion (unitsPerPiece :210-217), rejects fractional pieces when disallowed (:98-102 — VERIFIED-NOW at :88-100), accepts optional `note` (VERIFIED-NOW: validation :59, trim :75), writes waste/adjustment movements + count lines (:140-198).
- `reconciliation_variance` is machine-only vocabulary: WasteReason enum marks it "only SubmitStockCountAction emits it" (pos_merchant app/Enums/WasteReason.php, VERIFIED-NOW).

Caveats (defects, not absence): F2 timing hazard — machine does not flush its OrderOutbox before pushing stock.count, so queued sales replaying later double-deplete on top of the variance waste (stock_count_screen.dart:84-96; StockCountHandler.php:134-138); note is optional, not an enforced "manager note". Neither changes FULL status for the A§2.8 mechanics.

## R2.3 — Receiving (GRN): with/without PO, quick supplier, running-average cost, price-creep, three-way match, photo, unit conversion, offline (S5.2) — 🟡 PARTIAL, P1

**Exists:**
- GRN receiving without PO: pos_merchant CreatePurchaseReceiptAction — atomic one-shot receipt, mixed ingredient/product lines, central receive + per-line branch splits, Phase B direct-to-branch destination_branch_id (migration 2026_08_05_010200), charges booked as expenses, AP fields (audit-inventory §7). Routes: web.php:569-576 (index/store/show/recordPayment). Never pre-fills (nothing to pre-fill from — no PO exists).
- Unit conversion at entry: IngredientUnitConverter convert-at-entry store-in-base with overflow + non-positive-factor guards (IngredientUnitConverter.php:34-95).
- Supplier optional on a receipt: VERIFIED-NOW `supplier_uuid => nullable|uuid` (StorePurchaseReceiptRequest.php:29) — a receipt can be recorded with no supplier at all.

**Missing:**
- **Receiving WITH a PO**: no purchase-order concept anywhere. VERIFIED-NOW: `grep -rniE "purchase_order|pos_po_"` over all 153 pos_admin migrations = zero hits; audit-inventory §7 confirms no PO stage.
- **Cost capture recalculating running average**: the GRN path NEVER updates ingredient default_unit_cost or product cost_price (ReceiveIngredientStockAction.php:105-115 stamps the OLD cost; audit-inventory F1). Only the separate piece-purchase form (RecordPurchaseAction.php:219-229) updates cost, and as last-purchase-wins, not weighted average (weighted average is the R1.10 gap; the GRN staleness is this requirement's gap). Two purchase paths → two costing states for identical purchases.
- **Price-creep flag**: VERIFIED-NOW `grep -rniE "price.?creep"` over pos_merchant app/ + resources/js = zero hits.
- **Three-way match (ordered/received/invoiced)**: impossible without POs; nothing exists.
- **Photo of delivery note**: VERIFIED-NOW `grep -rniE "photo|upload|image"` over PurchaseReceipts Vue pages + PurchaseReceiptController = zero hits.
- **Quick supplier (name only) at receiving**: no inline supplier creation in the GRN flow (request accepts only an existing supplier_uuid); supplier creation is a separate Suppliers-tab CRUD (name+contact, web.php:553-559). Adjacent but not the "type a name at the door" flow.
- **Offline receiving**: receiving is portal-only (session-auth SPA); devices have no receiving surface (devices only send restock.request — pos_api RestockRequestHandler creates request rows only).

**Priority rationale:** P1 because the GRN-never-updates-cost defect silently stales every sale-time COGS snapshot for GRN-using merchants (financially wrong reports), and receiving is step 6 of the [S] build order.

## R2.4 — Partial deliveries: per-line PO states, backorder-vs-short-close, door rejection → supplier claim, over-delivery tolerance, fill-rate (S5.3) — 🔴 MISSING, P2

Nothing exists. No PO entity (see R2.3 evidence); GRN is created already in status `'received'` (CreatePurchaseReceiptAction.php:111) — there is nothing to partially receive against, no open/partially-received/closed line states, no backorder/short-close decision, no rejection-at-door concept, no over-delivery tolerance/approval, no supplier fill-rate metric (VERIFIED-NOW: `grep -rniE "fill.?rate"` over pos_merchant = zero hits). audit-inventory §7 states "Partial receiving: N/A — there is no purchase-order stage."

## R2.5 — Supplier returns & credit notes (S5.4) — 🔴 MISSING, P2

VERIFIED-NOW: `grep -rniE "credit_note|creditnote|supplier_return|supplier return|return_to_supplier"` over pos_merchant src/app = zero hits. No return document, no reversal-at-original-received-cost, no credit chain (raised→expected→received→reconciled), no outstanding-credits report, no credit-notes-without-returns. The only "credit" in the build is the GRN `is_credit` flag meaning *bought on credit* (accounts payable, StorePurchaseReceiptRequest.php:37) — the opposite direction of a supplier credit. Consequence: goods sent back to a supplier can only be recorded as waste or a manual adjustment, conflating supplier failures with shrinkage (exactly what S5.4 forbids). Note also there is no GRN void/reversal at all (audit-inventory F4; routes web.php:569-577).

## R2.6 — Supplier-item catalogue: multi-supplier prices, effective-dated price lists, lead time/delivery days, scorecard (S5.5) — 🔴 MISSING, P2

pos_suppliers is a minimal master only: name, contact, notes, status, softDeletes, (company,name) unique — VERIFIED-NOW from migration 2026_05_29_010000_create_pos_suppliers_table.php:26-41. No supplier-item link table, no price lists (VERIFIED-NOW: `grep -rniE "supplier_item|price_list|supplier_price"` over all pos_admin migrations = zero hits), no lead-time/delivery-days columns (`grep lead.?time` over pos_merchant = zero hits), no scorecard (fill rate / on-time / price creep / rejection — all greps zero). pos_ingredient_purchases rows do carry supplier linkage + cost history (2026_07_01_010000:75-120), and RestockPurchasingReportAction aggregates purchases by supplier (map-pos_merchant §3) — raw material exists for price comparison, but no comparison/catalogue feature is built.

## R2.7 — Scope boundary: track credits owed, NO full AP, export to accounting (S5.5) — 🟡 PARTIAL, P3

- The boundary itself is respected: no general-ledger/full-AP module exists.
- The build actually ships payables-lite in the *other* direction: GRN credit purchases with is_credit, due_date, amount_paid, payment_status + append-only payment history with balance_after (pos_purchase_receipt_payments, migration 2026_07_26; WriteReceiptPaymentAction; map-pos_merchant §5). That is money the merchant OWES suppliers.
- Supplier credits owed TO the merchant: nothing (dependent on R2.5, which is missing).
- Export to accounting software: no accounting-format export exists; generic report CSV/PDF/XLSX exporters exist (ReportCsv/Pdf/XlsxExporter, map-pos_merchant §3) which is a serviceable stand-in for the payables data that does exist.

## R2.8 — Waste logging: two taps, reason taxonomy, voids-before-fire vs comps (S5.6) — 🟡 PARTIAL, P3

**Exists:**
- Ingredient waste (portal): RecordWasteAction — pos_waste_records row + negative waste movement in one txn, frozen unit_cost_at_time, 'other' requires notes (RecordWasteAction.php:99-101; audit-inventory §10).
- Product waste (portal + both devices): RecordProductWasteAction; device `product.waste` sync event (pos_api ProductWasteHandler, shelf-capped under lock, cost frozen); machine waste_product_screen.dart; handheld ops_screens.dart:137 — a genuine short item+reason flow on POS.
- Voids before fire consume nothing: consumption happens only at order.pay (PayOrderHandler.php:178); an order cancelled before payment never touched stock, and paid voids reverse consumption unless the void reason's affects_inventory keeps it (VoidOrderHandler.php:99,130).
- Comps after make DO deduct: comps are order lines that consume normally; comp value is not revenue (audit-refunds-voids; CreateOrderHandler.php:460-538).

**Gap — reason taxonomy differs from S5.6:** VERIFIED-NOW WasteReason enum = expired / spoiled / broken / dropped / contamination / reconciliation_variance / other (pos_merchant app/Enums/WasteReason.php). Spec wants spoiled, burnt-dropped, **staff meal**, **customer return**, **prep waste**. Staff-meal, customer-return and prep-waste buckets do not exist, so those events land in 'other' free-text — they cannot be reported as their own cost categories (staff meals are an accounting category, customer returns are a quality signal). Ingredient waste is also portal-only (no device surface; devices only waste products).

## R2.9 — Variance report: expected-vs-counted formula, tolerances, money-valued (S5.7) — 🟡 PARTIAL, P2

**Exists:** PortionVarianceReportAction — per-ingredient decomposition in qty AND money using frozen unit_cost_at_time; buckets theoretical (sale+addon), waste (excl. reconciliation_variance), count_variance (from pos_stock_count_lines), manual adjustments, production net; double-count exclusions via reason filter + stock_movement_id link; coverage honesty (last_counted_at, "variance-blind" rows, uncounted headline) (PortionVarianceReportAction.php:1-66,278,300; audit-inventory §11). InventoryConsumptionReportAction adds counted/variance columns (Additions §2.11). Count lines freeze expected/counted/variance (2026_07_01_010000:122-174). This is a valid variance suite, money-valued as spec demands.

**Missing:**
- **Per-ingredient tolerance thresholds**: VERIFIED-NOW `grep -rniE "tolerance"` in PortionVarianceReportAction.php + InventoryConsumptionReportAction.php = zero hits; no threshold column exists on pos_ingredients besides min_stock_threshold (a reorder trigger, not a variance tolerance). Every gram of variance is reported flat, with no acceptable-band highlighting.
- **The explicit S5.7 identity** (opening + received − theoretical − waste ± transfers = expected, vs counted): the build reports variance as decomposed buckets since last count and deliberately excludes logistics movements (transfers) from the decomposition (PortionVarianceReportAction excludes logistics per its docblock) — a 🔵-flavored reformulation; expected is the running ledger balance rather than a recomputed identity. Functionally equivalent when the ledger is complete, but there is no opening/received presentation.
- Calibrate-recipes-first doctrine: documentation/philosophy only in spec; report's cadence caveat docblock partially reflects it. No product feature to point at (not counted against status).

## R2.10 — Multi-branch transfers: direct, piece-bridged conversion, both sides confirm (A§1.3, A§2.7) — 🟡 PARTIAL, P3

**Exists:** TransferStockAction — pos_branch_transfers header + lines with unit_at_set + unit_cost_at_time snapshots (VERIFIED-NOW migration lines :42-56: cost moves with stock so COGS stays consistent), paired transfer_out/transfer_in movements both referencing the transfer, alt-unit conversion at entry (TransferStockAction.php:84 via IngredientUnitConverter), overdraw refused (:89-97). Product twin TransferProductStockAction. UI in Inventory tab (routes web.php:599-607).

**Missing / different:**
- **Both sides confirm**: transfers are single-actor and immediate — routes are index/show/store only (web.php:603-607), both movement legs are written in one transaction by the sender; no in-transit state, no receiving-branch confirmation, no dispute path.
- **Piece-bridged conversion**: entry-unit conversion exists (custom alt units + PD4 metric siblings) but there is no automatic piece bridge using units_per_piece in the transfer flow; a merchant would have to define a "piece" alt unit manually.
- Known defect F3: availability check is TOCTOU (pre-transaction, no lock) — TransferStockAction.php:89-102 (policy-level only; ledger invariant holds).
- Devices have no transfer surface (portal-only, by design — central actions portal-only per 2026_07_18 migration :29-30).

## R2.11 — Mother/commissary kitchen: central recipes + batch production + transfer with cost (S6.1) — 🟡 PARTIAL, P3

**Exists (the parts):**
- Batch production: pos_productions / pos_production_lines (start/finish/cancel; StartProduction consumes ingredients at the branch under locks, FinishProduction credits the shelf; P-G1 'cooked' stock_mode) — audit-inventory §§2-4.
- Central warehouse pools: pos_ingredient_stock + pos_product_stock with branch_id-NULL ledger convention (2026_07_18, 2026_06_25 migrations); receive-and-distribute + allocation actions (P-G4).
- Transfers carrying cost: transfer lines freeze unit_cost_at_time (see R2.10) — "transfer as stock movement type with transfer cost" is satisfied mechanically (transfer_in/transfer_out are movement types, VERIFIED-NOW StockMovementType enum).

**Missing (the composition):** production is strictly branch-scoped — pos_productions.branch_id is a required FK (VERIFIED-NOW migration :55-57); there is no central/commissary production (a batch cannot be produced into the central pool), hence no central-kitchen→branch flow of finished prep with transfer cost. Recipes are company-level (usable by any branch) so "central recipes" is arguably satisfied, but the S6.1 commissary operating model as such does not exist. All building blocks are present; the flow is not composed.

## R2.12 — Restock requests: POS→approval→fulfilment movements; smart suggestions; allocation (B5.6.4–5.6.5) — ✅ FULL

- Device request: `restock.request` sync event creates request rows only, no stock movement (pos_api RestockRequestHandler.php:46-75). Machine + handheld both have real screens (pos_machine expense_restock_payload.dart:118; pos_handheld HH-9).
- Portal lifecycle: draft→submitted→approved with review, then either warehouse fulfilment — central rows locked in deterministic order, overdraw refused, paired allocation_out (central −) + restock (branch +) legs per line, status Fulfilled resolution='warehouse' (AllocateRestockRequestAction.php:153-238) — or purchased closure with deliberately NO movement (ResolvePurchasedRestockRequestAction.php:56-64), plus cancel. Routes web.php:632-654.
- Smart suggestions: SuggestRestockAction — per-ingredient daily burn from trailing consumption movements (sale/addon/adjustment types, mirroring the Consumption report), target = max(min_stock_threshold, daily×coverDays), suggested = target − current, biggest gap first (VERIFIED-NOW SuggestRestockAction.php:16-47). Window is caller-tunable: `?window_days` default 30, `?cover_days` default 14, clamped 1-365 (VERIFIED-NOW RestockRequestsController.php:137-156) — covers the blueprint's 7/14/30-day consumption windows via parameter.
- Stock allocation across branches: AllocateIngredientStockAction / AllocateProductStockAction (central→branch) + receive-and-distribute (map-pos_merchant §2 routes :508-521, :394-410).
- Caveat (historical, not a gap): pre-Phase-A fulfilments credited branches with no central debit; legacy resolution-NULL rows never corrected (audit-inventory F8).

## R2.13 — Ingredient expiry: batches w/ expiry, 7/3/1-day alerts, auto-fill expired waste (A§1.3, Ph7+) — 🟡 PARTIAL, P3

**Exists (products, not ingredients):** cooked-batch expiry — pos_products.shelf_life_days + pos_productions.expires_at per batch ("the CHEF's per-batch truth", VERIFIED-NOW migration 2026_07_15_010000_add_cooked_shelf_life_and_batch_expiry.php:18) with FIFO day-end disposition (ApplyDispositionAction, capped + locked; disposition device endpoints in pos_api routes; P-G1.5 shelf-life/disposition reporting per map-pos_merchant §5).

**Missing:** ingredient-side entirely — pos_ingredient_purchases batch rows carry NO expiry column (VERIFIED-NOW: `grep -rniE "expir"` across all 153 migrations shows expiry only on activation tokens, company CR dates, documents, and the cooked-batch migration); no 7/3/1-day expiry alerts anywhere; no auto-fill-expired-into-waste-confirmation flow (disposition is the cooked analogue). Requirement is explicitly Phase 7+ in [A], so MISSING-by-schedule; scored PARTIAL because the cooked-product half of the concept shipped.

## R2.14 — Stock movement ledger: append-only, typed, signed, cost-at-time, reference, user (B5.6.3) — ✅ FULL

VERIFIED-NOW from migration 2026_05_29_010300_create_pos_stock_movements_table.php:63-100 and pos_merchant app/Enums/StockMovementType.php:
- Typed: movement_type varchar(32) with enum Initial / Restock / SaleConsumption / AddOnConsumption / Waste / Loss / Adjustment / TransferIn / TransferOut + later ProductionConsumption / ProductionReturn / Received / AllocationOut / AllocationIn — a superset of B5.6.3's list, enum docblock cites §5.6.3.
- Signed qty: decimal(12,3) "SIGNED — Postgres decimal handles negatives" (:72-73).
- Cost at time: unit_cost_at_time decimal(12,3) frozen (:74).
- Reference: polymorphic reference_type/reference_id (:76-77) + hot-path indexes (branch,occurred / ingredient,occurred / reference) (:97-99).
- User: recorded_by_user_id (portal) XOR recorded_by_pos_staff_id (device) both FK'd nullOnDelete (:83-90), plus note and occurred_at-vs-created_at separation.
- Append-only: two canonical writers only (WriteStockMovementAction, WriteProductStockMovementAction + pos_api ConsumeInventoryAction family); no update/delete of ledger rows found anywhere (audit-inventory §5); parallel product-unit ledger pos_product_stock_movements mirrors the design.
- Caveat (shared with all ledgers, tracked under R8/db-schema F-12): append-only is application-convention only — zero DB triggers/CHECKs protect the ledger from raw UPDATE/DELETE.

---

## Cross-cutting observations for the report writer

1. The purchasing suite (S5.2–S5.5) is the weakest area of R2: receiving exists but PO/partial-delivery/returns/credits/supplier-catalogue are all absent, and the GRN path silently stales COGS (F1). These four gaps compound: no PO → no three-way match → no fill-rate → no scorecard.
2. The counting/variance suite (S5.1, S5.7, A§2.8) is mechanically strong (piece model, reconciliation_variance auto-waste, money-valued variance report) but ships none of S5.1's anti-fraud controls (blind, rotation, spot checks, tolerance bands).
3. The ledger backbone (R2.14) and restock workflow (R2.12) are the two fully-delivered requirements and are high quality (locked, conserved, snapshot-frozen).
4. Everything portal-side is online-only by architecture (session SPA); S5.2/S5.1 offline receiving/counting would require device-surface work plus outbox transport for ops events, which both devices deliberately avoid today (pushOpsEvent inline-online rationale, pos_handheld order_sync_service.dart:755-766).
