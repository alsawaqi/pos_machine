# Gap analysis — R9 Customers/CRM · R10 Reporting · R11 Charity Round-Up · R12 Deferred

Read-only gap analysis against requirements.md. Sources: audit-reporting.md, map-charity.md,
map-pos_merchant.md, audit-payments-rounding.md, keyfacts_all.md, plus direct code verification
this session (marked "VERIFIED here"). Paths repo-relative unless absolute.

---

## R9 — Customers / CRM

### R9.1 Customer profiles (AR/EN name, phone(s), email, DOB, tags, plates, merge, order history, loyalty activity, notes) — PARTIAL

VERIFIED here — schema `pos_admin/src/database/migrations/2026_06_01_010000_create_pos_customers_table.php`:
- Columns: `name`, `phone` (32 chars, `(company_id, phone)` unique), soft deletes. The migration
  docblock explicitly states: "Minimum scope for Phase 6a: name + phone only. **No email, no notes,
  no Arabic name yet** — keeps the surface small for the pilot. Later phases can additive-extend."
- `2026_07_03_010000_add_dob_and_tags_to_pos_customers.php` adds `date_of_birth` + `tags_json`
  (blueprint §5.7.2, tags as JSON per §10.6 — deliberate, not a pivot).
- Vehicle plates: sibling table `2026_06_01_010100_create_pos_customer_vehicle_plates_table.php`,
  made many-to-many by `2026_07_08_010000_make_pos_customer_vehicle_plates_many_to_many.php` (P-F2).

Present (VERIFIED via map-pos_merchant + directory listing here):
- Merge duplicates: `pos_merchant/src/app/Actions/Pos/Customers/MergeCustomersAction.php` (route
  web.php:672-696 block incl. merge/attachPlate/detachPlate).
- Order history + analytics: `CustomerOrdersAction` / `CustomerAnalyticsAction`
  (`pos_merchant/src/app/Actions/Pos/Reports/`), customer show page `Merchant/Customers/Show.vue`.
- Loyalty activity per customer: routes web.php:722-727 (`customers/{uuid}/loyalty`,
  `/loyalty/transactions`, `/loyalty/adjust`) — VERIFIED here by reading web.php:720-734.
- Tags endpoint + DOB in UI (commit 7cfde6f).

Missing vs blueprint §5.7: Arabic name, email, multiple phones (single phone is the unique natural
key), free-text notes. All four are explicitly deferred by the schema owner's docblock — deliberate
pilot scoping, not an oversight.

Status: **PARTIAL** (core CRM loop complete; profile-field surface deliberately narrow).
Priority: P3.

### R9.2 POS identification by phone OR vehicle plate — FULL

VERIFIED here — `pos_api/src/app/Http/Controllers/Api/V1/Device/DeviceCustomersController.php`:
- `GET /device/customers/search?q=` matches LOWER(name), LOWER(phone), and plate
  (`CustomerVehiclePlate.plate_number LIKE upper(q)`), company-scoped, limit 25, returns plates +
  loyalty accounts per hit (lines 33-84). Route `pos_api/src/routes/api.php:114` with comment
  "customer lookup by phone/plate, register a customer" (:99).
- `POST /device/customers` find-or-creates on phone incl. soft-deleted revival so the
  (company_id, phone) unique slot never 500s the device (store(), withTrashed logic).
- Devices consume it: 20 test methods in `pos_api/src/tests/Feature/DeviceCustomersTest.php`
  (per map-pos_api). pos_handheld additionally has plate OCR (keyfacts, map-pos_handheld).

Status: **FULL**. Priority: none (P3 nominal).

### R9.3 House accounts (credit limit, statement, ageing) [S6.5] — MISSING

VERIFIED here:
- Greps for `credit_limit`, `house_account`, "house account", statement/ageing concepts across
  pos_merchant/src/app, pos_api/src/app, pos_admin/src/app + migrations: zero relevant hits.
- What exists instead is a **prepaid customer wallet** (blueprint §6.2, store credit):
  `pos_customer_wallet_ledger` (migration 2026_06_02_010300, append-only, signed deltas,
  balance_after) with entry types topup / redemption_use / adjustment / refund_in
  (`pos_merchant/src/app/Enums/WalletLedgerEntryType.php:24-27`).
- The wallet explicitly REFUSES negative balances:
  `pos_merchant/src/app/Actions/Pos/Loyalty/WriteWalletLedgerEntryAction.php:27` ("Refusing to go
  negative") — i.e. it is the opposite of a house account (prepay vs credit).
- No POS spend path yet: `redemption_use` has no production writer (only the guard in
  WriteWalletLedgerEntryAction:77-78); `refund_in` writer absent (audit-refunds-voids); wire tender
  methods are cash/card/split_part/loyalty/gift/bank_pos — no wallet/house tender
  (pos_api/src/app/Models/Payment.php:44, per audit-payments-rounding §3).
- Wallet routes are merchant-portal only: topup/adjust/ledger web.php:729-734 (VERIFIED here),
  labeled "Wallet (store credit — separate from blueprint loyalty)".

Status: **MISSING** (S6.5 house accounts: tab, credit limit, statement, ageing — none exist; the
wallet is a different, prepaid product and even it has no POS redemption yet).
Priority: P2.

---

## R10 — Reporting

### R10.1 Ten portal reports + filters + consolidated/per-branch + Excel/PDF export + saved views — PARTIAL

From audit-reporting §1 + map-pos_merchant §3 (VERIFIED there):
- All ten blueprint reports exist as dedicated Actions, plus six more (16 report endpoints,
  `pos_merchant/src/routes/web.php:826-884`, one Action each in
  `pos_merchant/src/app/Actions/Pos/Reports/`, constructor-injected in ReportsController.php:53-71):
  Sales, Product Performance, Inventory Consumption (incl. ">20% above trailing average" anomaly
  flag, InventoryConsumptionReportAction.php:149-159), Recipe & Cost, Loss/Waste,
  Restock/Purchasing, Discounts, Customers, Round-Up Donation (RoundUpDonationReportAction over
  pos_roundup_donations), Staff Activity — plus Comps, Shifts, Payouts, Portion Variance,
  Discounted & Comped Products, Audit Log.
- Filters: `ReportFilter` (date range, branch) with P-G5 per-user branch clamp enforced once in
  `ReportFilter::fromArray` (ReportFilter.php:80-93) and applied uniformly (audit-reporting §5).
  Consolidated-vs-per-branch = branch filter present on every report.
- Export: CSV/PDF/XLSX via `Report{Csv,Pdf,Xlsx}Exporter`, `/api/reports/{report}/export`
  (web.php:831), reports.export permission — meets and exceeds "Excel/PDF".
- Test coverage: 18 `*ReportTest.php` feature files.
- **Saved views: backend-only.** SavedViews CRUD exists (web.php:814-820,
  `Pos/SavedViewsController.php`) but grep of resources/js shows ZERO frontend consumers
  (map-pos_merchant §7) — the blueprint's "saved views" is not reachable by any user.

Status: **PARTIAL** (10/10 reports + filters + export shipped; saved-views UI missing).
Priority: P3 (the saved-views gap itself; correctness is R10.4's row).

### R10.2 Variance report (theoretical vs actual per ingredient, money-valued, tolerances) — PARTIAL

- `PortionVarianceReportAction` exists (pos_merchant, commit 1a8fc52 "where the food went, in
  money"): theoretical (sales consumption from frozen snapshots) vs actual (counts/waste), valued
  at frozen costs, with double-count exclusions and correct separation of logistics movements
  (PortionVarianceReportAction.php:43-45,170-192; audit-inventory + audit-reporting F4).
- VERIFIED here: grep `tolerance|threshold` in PortionVarianceReportAction.php → zero hits.
  **No per-ingredient tolerance thresholds exist** (S5.7's "per-ingredient tolerance"); the only
  threshold anywhere is `pos_ingredients.min_stock_threshold` used by the consumption report for
  low-stock flags (InventoryConsumptionReportAction.php:81,173) — a different concept.
- The older Loss/Waste report ships a contradictory "shortfall" that counts transfers-out and
  production consumption as unexplained loss (LossWasteReportAction.php:123-141) — the newer
  report's own docblock calls that "the bug this avoids". Two variance numbers disagree for the
  same window (audit-reporting F4, P2).

Status: **PARTIAL**. Priority: P2 (add tolerances; retire/fix the Loss/Waste shortfall
computation so the two variance surfaces agree).

### R10.3 Comp report; shift report; supplier fill-rate/scorecard; outstanding supplier credits — PARTIAL

- Comp report: **exists** — `CompReportAction` (+ DiscountedCompedProductsReportAction), by-branch
  and by-staff breakdowns (audit-reporting §1; F20 notes a NULL-approver inner-join edge).
- Shift report: **exists** — `ShiftReportAction` (opening/expected/counted/variance/cash_collected)
  + audited same-day manager reopen (ShiftsController.php:36-90; audit-shifts-cash). Per-shift card
  sales/top-products admitted as follow-up in-file.
- Supplier fill-rate / scorecard: **missing** — VERIFIED here, grep
  `fill_rate|fill rate|scorecard|lead_time|on_time` across pos_merchant/src/app and
  pos_admin/src/app: zero hits. Root cause upstream: no PO/partial-receiving concept exists at all
  (GRN is an atomic one-shot receipt — audit-inventory), so fill-rate has nothing to measure.
- Outstanding supplier credits: **missing** — VERIFIED here, grep
  `credit_note|supplier_return|SupplierCredit`: zero hits. No supplier-return flow exists (R2.5
  domain); GRN has no void route (pos_merchant web.php:569-577). The GRN's accounts-payable
  payments (PurchaseReceiptPayment, recordPayment web.php:576) track money the merchant OWES, not
  credits owed TO the merchant.
- RestockPurchasingReportAction exists but attributes spend to the ingredient's CURRENT
  primary_supplier_id (live-config read, audit-reporting F16) — the closest thing to supplier
  analytics today.

Status: **PARTIAL** (2 of 4 present). Priority: P2 (blocked behind R2.4/R2.5/R2.6 features).

### R10.4 Reports reconcile to source events (Phase 7 exit criterion) — INCORRECT

The reconciliation property fails on multiple verified axes (all from audit-reporting, line-cited
there; independent of each other):
1. **F1 (P1)** All date/hour windows snap to UTC while Oman is UTC+4 — every daily figure
   platform-wide is misattributed across business days; heatmaps rotated 4h
   (ReportFilter.php:67-68; DashboardSummaryAction.php:85-91; BuildBranchReportAction.php:42-43).
2. **F2 (P1)** net_sales/gross_profit/net_profit never subtract comp_total although the server
   money invariant proves comps were never collected (SalesReportAction.php:115,159 vs
   CreateOrderHandler.php:631-636).
3. **F3 (P1)** Orders paid with pending_reconciliation card tenders (commission deferred) are
   reported as finalized 100%-merchant income, then silently restate on approval
   (SalesReportAction.php:523-544); orders-list shows the contradictory status for the same order.
4. **F7 (P2)** Orders-viewer totals banner includes voids and unpaid orders (merchant + admin) —
   can never reconcile with the Sales report for the same window.
5. **F8 (P2)** Device branch-report tender mix has no payment-status filter — failed + pending
   legs counted (BuildBranchReportAction.php:186-199), violating its own docblock invariant.
6. **F4/F5 (P2)** Loss/Waste shortfall and Inventory-Consumption pollute their aggregates with
   logistics/adjustment movements — contradicting the Portion Variance report by design.
7. **F10/F11 (P3)** "gross_sales" and finalized-income logic mean different things across
   merchant portal, admin portal, and orders list.
8. **F6 (P2)** COGS/margin exclude cooked/unit products and all component costs — margin tiles
   overstate for those merchants.

Status: **INCORRECT** (reports are internally query-consistent but demonstrably do not reconcile
to source events / each other). Priority: P1 (F1-F3 are the go-live-relevant restatements).

---

## R11 — Charity Round-Up

### R11.1 Round-up next-whole-OMR, CARD only, customer-facing only, no offer when whole — FULL

All from map-charity §2a + audit-payments-rounding §9 (VERIFIED there, line-cited):
- Gate `canOfferCharityRoundUp`: `selectedPaymentMethod == 'Credit Card'` AND not a delivery order
  AND ceil-to-OMR remainder ≥ 0.001 (pos_machine/lib/state/pos_controller.dart:1443-1461) — card
  only, never cash, and **no offer when the total is already whole** (remainder 0 < 0.001).
- Prompt is customer-facing: rear customer-display prompt with 2-min timeout that cancels only the
  PROMPT (pos_controller.dart:3364-3397); charge captures base + accepted round-up in one card
  capture (payableTotal, :1436-1447, 2888-2893).
- Handheld: zero donation/charity code (grep verified in audit-payments §9) — compliant with B9.6
  "never handheld". Note the same fact is ALSO listed as a parity gap by the payments agent (F-8);
  against the blueprint text it is compliance, not a gap.
- Server enforces card-ness: DonationRecordHandler hard-fails a payment_index that addresses a
  non-card tender (pos_api DonationRecordHandler.php:87-92).

Status: **FULL**. Priority: none.

### R11.2 Donation row to existing charity table in-process (same DB); linked; queued offline; idempotent; status queued/recorded/reconciled — DIFFERENT (valid design) with a P1 operational gap

Implemented differently from B9.6.3-9.6.4, with documented rationale (map-charity §2-3):
- **Not an in-process write to the charity table.** pos_api writes its own
  `pos_roundup_donations` (pos_admin migration 2026_06_18_010000) and forwards a real
  `charity_transactions` row over HTTP (`POST {CHARITY_API_URL}/api/donations-pos-roundup`).
  Reason documented in DonationRecordHandler docblock :26-38: `charity_transactions.device_id` and
  `country_id` are NOT NULL and assume a CHARITY device — a direct row is unrepresentable.
  Cross-system writes are HTTP-only (verified by grep both directions). Valid supersession.
- Linked to order/payment: order_id/payment_id on the donation row + back-links
  `pos_payments.roundup_amount`/`charity_transaction_id` (DonationRecordHandler.php:127-166).
- Queued offline + idempotent replay: donation.record rides the same durable OrderOutbox with
  stable client_event_id (unique per device at ingest AND globally unique on the donation table);
  charity side dedupes on partial-unique `idempotency_key = 'pos_roundup:{uuid}'` with race-loser
  200 replay (charity CharityTransactionsController.php:584-700). Exactly-once end-to-end.
- Status model: pending/success/void + `forwarded_at`, not queued/recorded/reconciled — same
  semantics, different names (pending≈queued, success+forwarded_at≈recorded/reconciled). P-F7:
  pending_reconciliation tenders defer status + forwarding until admin approval.
- **The P1 gap: the retry leg of the design does not run.** `RetryRoundupForwarding` ("the hourly
  retry sweep") is never scheduled — pos_admin/src/routes/console.php:14-17 registers only the
  document-expiry job; no schedule:run runner/cron exists in any repo (map-charity F1). A donation
  whose inline forward failed on a settled order sits forwarded_at NULL forever, and charity-side
  reporting never UNIONs pos_roundup_donations (map-charity F4) — the customer's money never
  reaches the charity system. Compounding: if the sweep IS run manually it (a) can forward
  donations of REJECTED/VOIDED orders (checks neither donation.status nor payment.status='failed' —
  audit-payments F-4) and (b) passes null status so charity mis-files as 'fail'
  (map-charity F2). The charity ingestion endpoint is also public/unauthenticated (map-charity F3,
  security agent's domain).

Status: **DIFFERENT** (architecture valid and better-justified than the blueprint; the
reliability tail — scheduled retry + status/void guards — is broken). Priority: **P1** (schedule
the sweep, add donation.status + payment.status guards, pass explicit status).

### R11.3 Merchant revenue excludes donation — FULL

- pos_payments.amount = base tender only; Σ(tenders)==grand_total which never includes the
  round-up; the donation rides pos_roundup_donations + payments.roundup_amount breadcrumb
  (audit-payments §8-9, DonationRecordHandler.php:154-158). Sales/commission/loyalty all compute
  from grand_total ⇒ donation excluded from revenue, commission base, and loyalty earn by
  construction.
- Split reporting per B9.6.3 exists on both portals: merchant `RoundUpDonationReportAction`
  (commit 5246ad1) and admin `AdminRoundUpReportAction`; machine Z-report prints round-up as its
  own labeled line, outside tender totals (shift_summary.dart:171-203).
- Related (payments domain, noted for cross-reference): the bank statement gross DOES include the
  round-up, and the admin bank auto-match compares payment.amount only ⇒ every donation-carrying
  charge lands in amount_mismatches (audit-payments F-1, P1 — owned by the payments/reconciliation
  row, not this one).

Status: **FULL**. Priority: none for the requirement itself.

---

## R12 — Deferred / explicitly-scoped-out (confirm absence is intentional) — FULL (intentional)

VERIFIED here by grep across pos_merchant/src/app, pos_api/src/app, pos_admin/src (+ audits):

| Item | Evidence of absence | Note |
|---|---|---|
| Order-ahead / scheduled orders | grep `order_ahead\|scheduled_order\|pickup_time\|preorder` → 0 hits | Matches S3.7 "arrive-then-order only" |
| Reservations | grep `reservation` → 0 hits | S6.8 table-only deferral |
| Delivery integrations (Talabat/UberEats) | No integration code; but the prescribed **manual-entry interim EXISTS**: P-G7 delivery providers + delivery orders (order.deliver → pending_verification → merchant confirm/settlement, pos_merchant web.php:451-456, 903-909) | Compliant with [A]'s interim plan |
| Gift cards | grep `gift_card\|giftcard` → 0 hits; audit-loyalty confirms "no coupons or gift cards (deferred)". The `gift` tender is zero-charge gifting, and the customer wallet is store credit — neither is a gift card | Intentional |
| Menu scheduling (S7.4) | No scheduling engine; NOTE a small early piece exists: product available-hours UI (pos_merchant commit f30c388, catalog flag) | Partial early work, doesn't contradict the deferral |
| Course management | grep `course` in pos_api app + pos_merchant Actions → 0 hits | Intentional |
| Full accounts payable | Only GRN receipt-level partial payments exist (PurchaseReceiptPayment, WriteReceiptPaymentAction — "accounts payable" per commit 1afac44); no AP ledger/ageing/statements | Matches S5.5 boundary ("track credits, no full AP") — though the credits-owed half is missing (see R10.3) |
| Retail barcode/SKU stock | `sku`/`barcode` exist ONLY as inert optional metadata columns on products + import template (UpdateProductAction.php:32-33, ImportProductsAction.php:177-178,212-213); no scanning, no stock-by-SKU | Intentional; columns are harmless metadata |
| Merchant self-registration | grep `self.regist` → 0 hits; onboarding is admin-manual (pos_admin) | Matches S6.9 |
| ZATCA/Fatoora | grep `zatca\|fatoora` → 0 hits in pos_admin/pos_api | Correct — explicitly N/A (S7.1); note the Oman-VAT-invoice sibling requirement is R8.10's row (hardcoded 'Tax (5%)' receipt label flagged by machine agent) |

Status: **FULL** — every deferral is genuinely absent (or present only as the prescribed interim),
with zero half-built dead surfaces beyond the two noted (available-hours UI, sku/barcode columns),
both harmless. Priority: none (P3 nominal).

---

## Summary of closure priorities in this domain

| Priority | Items |
|---|---|
| P1 | R10.4 report reconciliation failures (UTC day windows, comp subtraction, pending-recon-as-finalized); R11.2 unscheduled + unguarded round-up retry sweep (donations stranded / would forward rejected+voided if run) |
| P2 | R9.3 house accounts missing entirely; R10.2 variance tolerances + contradictory Loss/Waste shortfall; R10.3 supplier scorecard + outstanding credits (blocked on R2.4-R2.6) |
| P3 | R9.1 deferred profile fields (AR name, email, multi-phone, notes); R10.1 saved-views UI |
