# MITHQAL 2.0 Audit — Reporting & Analytics Correctness (audit-reporting)

Auditor scope: every report/analytics surface in pos_merchant + pos_admin, plus the pos_api
device branch report. READ-ONLY audit; all evidence is repo-relative path + line numbers.
"VERIFIED" = read in code this session. "INFERRED" flagged explicitly.

---

## 1. Report inventory (enumeration — VERIFIED)

### pos_merchant (`src/app/Actions/Pos/Reports/`, routed in `src/routes/web.php:826-880`, controller `src/app/Http/Controllers/Pos/ReportsController.php`)

| Report | Action | Endpoint |
|---|---|---|
| Sales | SalesReportAction | GET /api/reports/sales |
| Customers | CustomerReportAction | /api/reports/customers |
| Discounts | DiscountReportAction | /api/reports/discounts |
| Discounted & Comped Products | DiscountedCompedProductsReportAction | /api/reports/discounted-comped-products |
| Comps | CompReportAction | /api/reports/comps |
| Shifts (cash variance) | ShiftReportAction | /api/reports/shifts |
| Payout / commission breakdown | PayoutBreakdownReportAction | /api/reports/payouts |
| Product Performance | ProductPerformanceReportAction | /api/reports/product-performance |
| Recipe & Cost | RecipeCostReportAction | /api/reports/recipe-cost |
| Staff Activity | StaffActivityReportAction | /api/reports/staff-activity |
| Inventory Consumption | InventoryConsumptionReportAction | /api/reports/inventory-consumption |
| Loss / Waste | LossWasteReportAction | /api/reports/loss-waste |
| Portion Variance | PortionVarianceReportAction | /api/reports/portion-variance |
| Restock / Purchasing | RestockPurchasingReportAction | /api/reports/restock-purchasing |
| Round-Up Donation | RoundUpDonationReportAction | /api/reports/round-up-donation |
| Audit Log viewer | AuditLogReportAction | /api/reports/audit-log (AuditLogView perm) |
| Export (csv/xlsx/pdf) | ReportsController::export | /api/reports/{report}/export (reports.export perm) |
| Dashboard | DashboardSummaryAction (+SalesComparisonAction) | dashboard summary route |
| Orders viewer | OrdersListAction / OrderDetailAction | orders list/detail |
| Branch control center | BranchActivityAction | branch detail |
| Table insights | TableInsightsAction | /api/table-insights |
| Production summary | ProductionSummaryAction | productions page |
| Customer analytics/orders | CustomerAnalyticsAction / CustomerOrdersAction | customer detail |
| Commission statements | CommissionInvoiceBranchLinesAction / PayoutBranchLinesAction | invoice/payout detail |

Test coverage exists for all main reports: `pos_merchant/src/tests/Feature/Pos/*ReportTest.php`
(18 files, VERIFIED by listing).

### pos_admin (`src/app/Actions/Admin/Reports/`, controllers in `src/app/Http/Controllers/Api/Admin/`)

| Report | Action/Controller |
|---|---|
| Platform / per-merchant Sales | AdminSalesReportAction + SalesReportController |
| Settlement (commission ledger) | AdminSettlementReportAction + SettlementReportController |
| Round-Up | AdminRoundUpReportAction + RoundUpReportController |
| Dashboard summary | DashboardSummaryController (KPIs, roundup_today, reconciliation_pending) |
| Orders viewer | OrdersController (paginated; totals banner) |

### pos_api (device)
| Report | Action |
|---|---|
| Device branch Reports dashboard | `pos_api/src/app/Actions/Device/BuildBranchReportAction.php` (GET /api/v1/device/reports/branch) |

---

## 2. P1 findings

### F1 (P1) — Every date-window filter uses UTC day boundaries; Oman is UTC+4 → daily figures are misattributed across days platform-wide

VERIFIED chain:
- All three Laravel apps run `'timezone' => 'UTC'`: pos_merchant/src/config/app.php:68,
  pos_admin/src/config/app.php:85, pos_api/src/config/app.php:68.
- The device sends business timestamps in UTC: pos_machine/lib/services/order_sync_payload.dart:104
  (`DateTime.now().toUtc().toIso8601String()` → `opened_at` at :269), stored as-is by
  pos_api/src/app/Actions/Device/Sync/Handlers/CreateOrderHandler.php:114.
- The merchant frontend sends bare `YYYY-MM-DD` dates (pos_merchant/src/resources/js/lib/api/reports.ts:23,
  useReportRunner.ts:27) and the backend snaps them to UTC days:
  pos_merchant/src/app/Data/Reports/ReportFilter.php:67-68 (`Carbon::parse(...)->startOfDay()/endOfDay()` in UTC).
- Same in pos_admin: SalesReportController.php:37-39 + parseBoundary (bare dates snap to UTC
  start/end of day), SettlementReportController.php:37-39, RoundUpReportController.php:36-38,
  DashboardSummaryController.php:232 (`now()->startOfDay()` = UTC).
- Merchant dashboard "today/yesterday/MTD": DashboardSummaryAction.php:85-91 (`Carbon::now()` UTC).
- Device branch report: BuildBranchReportAction.php:42-43 ("server tz" per its own docblock at ~line 20).
- All by_hour / by_weekday / heatmap breakdowns extract `EXTRACT(HOUR FROM opened_at)` on the UTC
  value (SalesReportAction.php:283-311, DashboardSummaryAction.php:202-207, AdminSalesReportAction.php:102-108).

Effect: a sale rung at 01:30 local Oman time on Aug 7 is stored 21:30 UTC Aug 6 and lands in the
"Aug 6" report; the "today" tile covers local 04:00→28:00; hour-of-day heatmaps are rotated by 4
hours (a 20:00-local dinner peak renders as 16:00). Every daily/hourly aggregate in merchant portal,
admin portal and the device Reports screen is shifted. No `APP_TIMEZONE` override exists in
.env.example of any repo (VERIFIED grep). Severity P1: numbers are internally consistent but
misattributed across business days — day-close totals will not match the drawer/shift reality for
any late-evening trade, and heatmaps mislead scheduling decisions.

### F2 (P1) — Sales report never subtracts comps: `net_sales`, `gross_profit` and `net_profit` are overstated by the comp write-off amount

VERIFIED chain:
- Server money invariant: `grand_total = subtotal − discount_total − comp_total + tax_total`
  (pos_api/src/app/Actions/Device/Sync/Handlers/CreateOrderHandler.php:631-636; comp_total written
  at :111). So comp money is genuinely never collected.
- SalesReportAction computes `net_sales = gross_sales(SUM subtotal) − discount_total` only
  (pos_merchant/src/app/Actions/Pos/Reports/SalesReportAction.php:115) and
  `net_profit = net_sales − commission_total − operating_expenses (+ recoverable purchase tax)`
  (:159-160). `comp_total` appears NOWHERE in the headline (:179-214) — no comp metric, no
  subtraction.
- gross_profit = net_sales − cogs (:122) inherits the same overstatement.
- SalesReportTest.php has zero comp coverage (VERIFIED grep — 'comp' only appears in doc words).
- Contrast: the ledger side is correct (commission `collected = grand_total`, comp already
  removed; merchant_net in commissionSettlement is right). The P&L headline is not.

Effect: a merchant comping 5% of revenue sees net_sales, gross_profit and net_profit each inflated
by that 5% (gross of tax). The Comp report exists separately but nothing reconciles it into the
"NET" figures the Sales report advertises. Fix is one more SUM(comp_total) term.

### F3 (P1) — Orders paid with an unconfirmed (pending_reconciliation) card charge are reported as fully-realised 100%-merchant income

VERIFIED chain:
- PayOrderHandler flips the order to `paid` even when a tender is
  `pending_reconciliation` (pos_api/.../PayOrderHandler.php:174 after :118-152) and
  **defers commission recording** for those orders (:185-205 — no pos_sale_commissions rows until
  the admin approves the charge).
- SalesReportAction.commissionSettlement treats any paid order with NO ledger rows as a
  "no-commission-profile" sale: `noneOrders` (SalesReportAction.php:523-529) → its `grand_total`
  (minus gift tenders only, :530-536) is added to BOTH `merchant_net` AND `finalized_net`
  (:543-544).
- So while a Soft-POS charge sits unresolved (money possibly never captured), the Sales report
  shows the full amount as commission-free, *finalized* (realised, cash-in-hand) merchant income,
  and `commission_total` (folded into net_profit) is understated. When the admin later approves,
  the same sale silently flips: commission appears, finalized shrinks.
- Inconsistently, the orders list shows the same order via SaleCommissionStatus::none() with
  `is_finalized = false` and status `none` ("no commission profile applied") —
  pos_merchant/.../Support/SaleCommissionStatus.php:194-209 — the two surfaces contradict each other.
- Payment-mix breakdowns exclude these tenders (`status = 'success'` filter,
  SalesReportAction.php:369), so by_payment_method no longer sums to gross for those days.

Effect: unresolved card charges — the exact case the platform hardened recently (pos_machine commits
5aea76b, caefd36) — are presented to the merchant as settled, commission-free income. Financially
misleading during the reconciliation window; silent retroactive restatement after it.

---

## 3. P2 findings

### F4 (P2) — Loss/Waste "shortfall" counts branch transfers-out and kitchen production consumption as unexplained depletion

- LossWasteReportAction.php:123-141: `total_depletion = ABS(SUM(quantity))` over ALL negative
  movements at a branch (only central branch_id-NULL rows excluded), while `sales_consumption`
  counts only sale/addon consumption. TransferOut and ProductionConsumption are negative,
  branch-scoped movement types (pos_merchant/src/app/Enums/StockMovementType.php cases + signed
  convention doc) — both land in `shortfall = total − sales` and `variance_pct`.
- The newer PortionVarianceReportAction explicitly names this as a bug it avoids:
  PortionVarianceReportAction.php:43-45 ("Logistics movements … are deliberately NOT usage …
  the Loss/Waste shortfall's transfer-out overstatement is the bug this avoids").
- Effect: any branch that transfers stock to a sister branch, or that runs kitchen production,
  shows large phantom "shortfall to investigate" in the Loss/Waste report. The two reports give
  contradictory variance numbers for the same window. The buggy section still ships.

### F5 (P2) — Inventory Consumption report (and dashboard top-ingredients) counts manual Adjustment-down movements as consumption

- InventoryConsumptionReportAction.php:38-47: `CONSUMPTION_TYPES` includes
  `StockMovementType::Adjustment` — the docblock admits it is a Phase-7 stand-in kept "so the
  seeded test data exercises the aggregation logic". Phase 8 sale consumption is long live.
- Same list mirrored in DashboardSummaryAction.php:61-65 (top_ingredients widget).
- Effects: `consumed`, `consumption_per_day`, `days_of_stock` and the ">20% above trailing
  average" anomaly flag (theft/waste watchdog, :149-159) are all polluted by manual stock
  corrections; a big adjust-down reads as a consumption spike / anomaly, and days_of_stock is
  understated. PortionVariance correctly separates adjustments into their own bucket
  (PortionVarianceReportAction.php:170-192) — the two reports disagree by design.

### F6 (P2) — Sales-report COGS/gross-margin excludes cooked ("production") and unit ("bought-in") products and all physical-item component costs

- COGS = recipe_snapshot_json + add-on ingredient snapshots only:
  SalesReportAction.php:556-582 + Support/RecipeSnapshotCost.php:30-52.
- pos_api freezes NO recipe snapshot for stock_mode 'cooked' or 'unit' products
  (CreateOrderHandler.php:657-661 returns null), and component_snapshot_json ({product_id, qty},
  no cost — migration pos_admin/src/database/migrations/2026_08_05_010000_add_component_snapshot_to_pos_order_items.php)
  is never read by any COGS path (VERIFIED: no reader in pos_merchant Reports).
- Effect: for merchants selling cooked/bought-in items or with cup/lid components, headline
  `cogs` is understated and `gross_profit`/margin overstated. Product Performance
  `recipe_cost`/`margin_pct` (ProductPerformanceReportAction.php:87-107) has the same hole —
  cooked/unit products show 100% margin. PD5 keeps net_profit honest via cash expenses (documented
  in SalesReportAction.php:127-132, 185-187), but the COGS/margin tiles are still displayed
  without any caveat about which products they cover.

### F7 (P2) — Orders viewers' money "totals" banner includes voided and unpaid orders by default (merchant + admin)

- Merchant: OrdersListAction.php:59-69 — totals sum `grand_total` over the whole filtered set,
  excluding ONLY pending_verification; default status filter is null (all statuses) —
  resources/js/Pages/Merchant/Orders/Index.vue:29 (`status: null`). Voids, open/held/kitchen and
  refunded orders all count into the banner.
- Admin mirror: pos_admin/src/app/Http/Controllers/Api/Admin/OrdersController.php:65-70 (same
  pattern, same default).
- Effect: the headline money figure over a period reads as revenue but includes written-off void
  value and not-yet-paid open orders; will never reconcile with the Sales report for the same window.

### F8 (P2) — Device branch report tender mix includes failed and pending-reconciliation payment legs

- BuildBranchReportAction::byMethod (pos_api/src/app/Actions/Device/BuildBranchReportAction.php:186-199)
  sums `pos_payments` for the window's paid orders with **no status filter** — unlike every
  merchant-side breakdown (`status='success'`, e.g. SalesReportAction.php:369) and unlike the
  orders list (`status <> 'failed'`, OrdersListAction.php:89).
- Effect: a failed card attempt retried as cash produces BOTH legs in the device's by_method mix;
  the docblock's own claim that "the method breakdown still sums to the summary gross" (:196-198)
  is violated. pending_reconciliation legs also count as if collected (see F3).

### F9 (P2) — Refund reporting is status-based and retroactive; refunds re-dated to the order's opened_at

- Reports select `status='paid'` / `status='refunded'` on the live status column and window on
  `opened_at` (SalesReportAction.php:78-92; AdminSalesReportAction.php:38-63). pos_orders has no
  refunded_at; only opened_at/closed_at (pos_admin migration
  2026_06_04_010000_create_pos_orders_table.php:123-130).
- Consequences when refunds go live: (a) refunding an order silently removes it from a past
  period's gross_sales (the SalesReportAction.php:73-77 comment "they were already counted when
  paid" is wrong for a status-based query — the sale vanishes from gross the moment status flips);
  (b) refunds_total is attributed to the ORDER'S opened window, not the refund date, so a refund
  today rewrites last month's report and today's shows nothing; (c) a UI/user computing
  gross − refunds double-subtracts. Asserted as intended behavior in
  SalesReportTest.php:146-163 — the design itself is the problem.
- Mitigating fact (VERIFIED): no code path writes STATUS_REFUNDED today — pos_api has no refund
  handler (grep: only VoidOrderHandler exists; STATUS_REFUNDED referenced only in guard lists).
  So this is latent, not yet corrupting live numbers → kept at P2 as a designed-in future
  restatement bug.

---

## 4. P3 findings (gaps / inconsistencies / perf)

### F10 (P3) — "gross_sales" means different things in merchant vs admin portals
Merchant: gross_sales = SUM(subtotal) pre-discount pre-tax (SalesReportAction.php:97).
Admin: gross_sales = SUM(grand_total) (AdminSalesReportAction.php:47,75). A merchant comparing
their portal to the admin's per-merchant Sales tab sees different "gross" for the same window.
avg_ticket also differs in base (merchant grand_total/count :209-213; admin gross/count :82).

### F11 (P3) — Finalized/pending income logic differs across three surfaces
- Sales headline realised test: payout paid OR channel='cash_bank' (SalesReportAction.php:509-512).
- Payout report by_month adds a legacy fallback: EXISTS cash/bank_pos tender AND NOT EXISTS card
  (PayoutBreakdownReportAction.php:193-198). Legacy pre-channel pure-cash sales are "pending"
  forever in the Sales headline but "finalized" in the payout by_month.
- Orders list: no-ledger orders get is_finalized=false (SaleCommissionStatus.php:194-209) while the
  Sales headline counts the same orders in finalized_net (SalesReportAction.php:543-544).
Also SaleCommissionStatus::forOrders folds mixed-channel merchant rows via MAX(payout_id) and one
status per order (SaleCommissionStatus.php:60-124) — a mixed order in a pending payout shows
IN_PAYOUT even for its already-realised cash slice (display-level only).

### F12 (P3) — Admin settlement "merchant_payable" includes cash-channel residuals the platform never pays out
AdminSettlementReportAction.php:166-172 headline sums ALL merchant residual rows (both channels);
actual payouts claim card-channel only (RecordSaleCommissionAction.php channel design:38-52;
PayoutBranchLinesAction channel filter 'card','all'). Label "total merchant payable" overstates
the platform's liability by the merchants' own drawer cash. Docblock says "direction-agnostic
visibility" — deliberate, but the headline label contradicts it.

### F13 (P3) — Legacy 'all'-channel rows can appear on both statement breakdowns
CommissionInvoiceBranchLinesAction.php:44 includes channels ('cash_bank','all');
PayoutBranchLinesAction.php:45 includes ('card','all'). A pre-channel-column MIXED order's 'all'
rows would render in both the invoice statement and the payout statement per-branch views
(claims themselves are disjoint; the statement detail is what double-shows). Edge/legacy only.

### F14 (P3) — Product Performance internal inconsistencies
- `top_addons.attach_revenue` = SUM(price_delta_snapshot) NOT scaled by parent line qty
  (ProductPerformanceReportAction.php:155-159), while per-product `addon_revenue` IS scaled
  (price_delta_snapshot * qty, :66-70). Same payload, two different revenue notions.
- `slow_movers` can only contain products that sold ≥1 time in window (:134-145 filters the
  sold set); a product with ZERO sales — the slowest mover — never appears.
- Revenue basis differs from dashboard: report uses line_total (:82); dashboard top-products uses
  qty * unit_price_snapshot pre-discount (DashboardSummaryAction.php:241-245). Numbers won't match.
- perProduct uses LIVE pos_products.name (:77-84) vs snapshot names elsewhere (rename-safety
  inconsistency; BuildBranchReportAction + dashboard use product_name_snapshot).

### F15 (P3) — Recipe & Cost report ignores its filter window and reads live config
RecipeCostReportAction.php:37-45 ("Branch scope doesn't really apply … ignore the branch axis"),
:47-57 uses TODAY's `default_unit_cost` only, yet echoes the window in the payload (:77-80). The
docblock-promised "average actual snapshotted cost" column (:17-18) is absent (_phase stub :83-85).
Cost trend = stub. Not snapshot-based — a price edit rewrites the apparent history of "cost".

### F16 (P3) — Restock/Purchasing supplier attribution reads live config
RestockPurchasingReportAction.php:57,81-98 attributes purchases to the ingredient's CURRENT
`primary_supplier_id`; re-assigning a supplier re-attributes all historical purchase spend.
(Restock movements carry no supplier snapshot — INFERRED from the report's join design; movement
schema not directly inspected.)

### F17 (P3) — Customer report loyalty block ignores branch scope
CustomerReportAction.php:113-130: points issued/redeemed/liability are company-wide with no
branchScope filter, while the rest of the report honors it. A P-G5 branch-restricted user reads
company-wide loyalty numbers (mild scope leak + apples-to-oranges within one payload).

### F18 (P3) — Expense feed counts pending-approval expenses in net_profit
SalesReportAction.php:133-140: every non-rejected expense (incl. status pending) reduces
net_profit at logged_at date. Approval later rejecting it silently restates the report.

### F19 (P3) — Perf notes (no pagination/N+1 on hot paths)
- SalesReportAction::cogs (:556-582) + ProductPerformanceReportAction::costByProduct (:191-207)
  load EVERY order-item row of the window into PHP to decode JSON snapshots — a year-long window
  on a busy tenant materialises 100k+ rows per request (and export runs it again).
- CustomerReportAction cohort (:79-106) loads first-order times for EVERY customer of the company
  regardless of window; then a per-customer PHP loop.
- ShiftReport/PortionVariance/LossWaste return unbounded row sets for the window (no pagination),
  acceptable at current scale; AuditLogReportAction is properly paginated (:57 + page/per_page).
- No caching layer on any report; every dashboard load recomputes ~15 aggregates. Fine now; noted.

### F20 (P3) — Comp report by-staff inner join
CompReportAction.php:117-125 inner-joins pos_staff on approved_by_pos_staff_id; a comp row with
NULL approver (docblock claims impossible; gift rows unverified) silently drops from by_staff while
remaining in headline. Cannot-verify the NULL-ness of gift approvers (schema not inspected) —
flagged, not asserted.

---

## 5. Reconciliation cross-checks performed (all VERIFIED reads)

- Money model: all reports emit decimal-3 strings; device report converts SUM(decimal) → integer
  baisas with a single round (BuildBranchReportAction::baisas). No float accumulation bug found in
  the aggregation paths (RecipeSnapshotCost rounds once per line, :37).
- Snapshot discipline: COGS reads recipe/addon snapshots (immutable) — correct where present (F6
  covers the holes). Discount/comp/offer breakdowns group by *_snapshot names — rename-safe.
  Product Performance + Recipe Cost + Restock supplier are the live-config exceptions (F14, F15, F16).
- Status discipline: merchant + admin sales aggregate status='paid' only; voids appear only in
  Loss/Waste (closed_at-windowed — correctly dated, LossWasteReportAction.php:205-231) and Staff
  Activity; pending_verification correctly excluded from revenue everywhere
  (OrderStatus doc, pos_merchant/src/app/Enums/OrderStatus.php:24-30) EXCEPT the orders-list
  totals caveat (F7). Offline-unsynced orders are absent by construction (server-side reports).
- Tenancy: every merchant report anchors company_id (spot-checked all files read); the P-G5 branch
  clamp is enforced once in ReportFilter::fromArray (ReportFilter.php:80-93) and controllers pass
  `allowedBranchIds()` uniformly (ReportsController.php — every method). Exception: loyalty block
  (F17). Commission statement twins rely on caller tenant-check (documented in-file).
- Commission math: RecordSaleCommissionAction splits integer baisas, merchant takes exact remainder
  per channel — Σ rows == collected (RecordSaleCommissionAction.php:100-165). Merchant payouts
  report + admin settlement both read settled-aware COALESCE(settled_amount, commission_amount) —
  consistent pair (PayoutBreakdownReportAction.php:58; AdminSettlementReportAction.php:45).
- Sales report vs payout report scope note: Sales windows on orders.opened_at, payouts window on
  commissions.occurred_at (= closed_at) — one-sided orders (opened before midnight, paid after)
  land in different windows of the two reports. Same-family issue as F1/F9; minor.

## 6. Cannot-verify / out of scope
- Actual production DB timezone content (no DB access) — F1 is asserted from code + device payload.
- Whether any operator relies on the orders-list totals banner as revenue (F7 severity judgment).
- pos_handheld money outbox parity (other agent's charter); bank reconciliation write path (other
  agent); charity forwarding pipeline (other agent).
