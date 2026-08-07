# pos_merchant map (merchant portal) — audit evidence

Repo: `\\wsl.localhost\ubuntu\home\abdallah644\projects\my-projects\pos\pos_merchant` (Laravel under `src/`).
All paths below are repo-relative (`src/...`). Read-only audit; facts VERIFIED unless marked otherwise.

## Architecture shape (VERIFIED)

- Single-SPA Laravel app: all API routes live in `src/routes/web.php` (1049 lines), session-auth (no api.php). SPA catch-all `Route::get('/{path?}', SpaController::class)` at `src/routes/web.php:1042`; Vue 3 SPA with its own router `src/resources/js/router.ts` (439 lines).
- Controllers: `src/app/Http/Controllers/Auth` (7: login, 2FA TOTP, password reset, profile, change-password, CSRF), `Portal` (BranchesController, PortalUsersController), `Pos` (49 controllers — full list captured below).
- Business logic in Actions: `src/app/Actions/Pos/{Branch,Catalogue,Customers,Deliveries,DeliveryProviders,Discounts,Expenses,FloorPlan,Inventory,Loyalty,Messaging,Offers,OrderReasons,Orders,Reports,Role,Settings,Staff,Targets,Taxes}`.
- Owns NO schema: `src/database/migrations` contains exactly ONE file, `0000_00_00_000000_create_test_schema.php` (SQLite test mirror). Real schema owned by pos_admin (per briefing).
- Tenancy: global scope `src/app/Models/Scopes/BelongsToCompanyScope.php` — constrains every company-owned model to `MerchantTenantContext->id()`; deliberate NO-OP when no tenant pinned (guests/console/queue), documented in the class docblock. Trait `src/app/Models/Concerns/BelongsToCompany.php`. Coverage guarded by tests `src/tests/Feature/TenantGlobalScopeTest.php` and `TenantScopeCoverageTest.php`. Commits 30e3326 (Phase 2a global scope), 8563b27 (Phase 2b pin-before-binding), fbac3d5.
- Per-user branch scope: `src/app/Support/BranchScope.php` (commit 2db710a "P-G5 enforce per-user branch scope across the portal"), test `src/tests/Feature/Pos/BranchScopeEnforcementTest.php`.
- Permissions: enum `src/app/Enums/MerchantPermission.php` — portal_users.*, pos_staff.*, branches.{view,update,transition_status}, roles.*, floor_plan.*, catalogue.*, inventory.{view,manage}, inventory.restock_request.{create,review}, customers.*, loyalty.*, discounts.*, expenses.*, reports.{view,export}, audit_log.view, orders.cancel, production.view, messages.send, deliveries.manage, targets.manage, devices.live.{view,control}. Catalog in `src/app/Support/PermissionCatalog.php`.
- Support: `ScalefusionClient.php` (restricted MDM port for Device Live), `ReverbPublisher.php` (websockets), `Report{Csv,Pdf,Xlsx}Exporter.php`, `AuditContext.php`, `MerchantTenantContext.php`, `DecryptsDefensively` model concern (APP_KEY drift hardening, commit 1f41779).
- Tests: 101 PHP test files; `src/tests/Feature/Pos` has ~70+ controller/report tests (one per module, see listing in section 9).

## 1. Vue page tree (`src/resources/js/Pages`) (VERIFIED)

- `Auth/`: Login, ForgotPassword, ResetPassword, TwoFactorChallenge, ChangePassword, Profile.
- `Merchant/Dashboard.vue` — summary + sales comparison + charts (commits 182f793, 7e802e7: period comparison, sales-by-hour, radial/radar/polar).
- `Merchant/Orders/Index.vue` + `components/OrderDetailDrawer.vue` — orders list with per-leg tender chips + Split badge (commit fd24033), full order detail (9560b97).
- `Merchant/Catalogue/`: Index.vue, ProductWizard.vue (3-step create/edit page, commit 8d68f80), ProductStockDialog.vue, AddonConsumptionEditor.vue.
- `Merchant/Inventory/`: Index.vue (4049 lines, tabbed: `ingredients | physical_items | suppliers | stock | movements | waste | stock_counts | restock_requests | transfers` — TabKey at Inventory/Index.vue:135), IngredientStockDialog.vue, PurchaseCostFields.vue, PurchaseTaxField.vue, `PurchaseReceipts/{Index,Create,Show}.vue` (GRN pages).
- `Merchant/Customers/{Index,Show}.vue`; `Loyalty/Index.vue`; `Discounts/Index.vue`; `Offers/Index.vue`.
- `Merchant/Expenses/Index.vue`; `ExpenseCategories/Index.vue`; `Taxes/Index.vue`.
- `Merchant/Deliveries/Index.vue` (tabs pending|confirmed, settlement confirm/adjust).
- `Merchant/Reports/`: Index + 15 report pages (Sales, Customers, Discounts, DiscountedCompedProducts, Comps, Shifts, Payouts, ProductPerformance, RecipeCost, StaffActivity, InventoryConsumption, PortionVariance, LossWaste, RestockPurchasing, RoundUpDonation) + shared components (ReportShell, ReportChart, ReportFiltersBar, HeadlineGrid, SalesComparison, SalesHeatmap, useReportRunner.ts).
- `Merchant/FloorPlan/{Index,FloorPlanner}.vue`; `Tables/{Index,Show}.vue` (per-table dine-in insights, commits 502fc72/55082b7).
- `Merchant/Branches/{Index,Show}.vue` + components (BranchAddStockDialog, BranchAssignStaffDialog, DeviceLiveDialog, ReceiptTemplateDialog) — branch "one-page control center" (commit ea2cb2f).
- `Merchant/Production/Index.vue` + KitchenProductionCharts.vue (kitchen production graphical view, commit fe3308a).
- `Merchant/Messages/Index.vue` (announcements to POS staff + portal inbox, commit ac06c76-era P-G6).
- `Merchant/BranchTargets/Index.vue` (P-G8 windowed targets); `PortalUsers/Index.vue`; `PosStaff/Index.vue`; `Roles/Index.vue`; `AuditLog/Index.vue`.
- `Merchant/Settings/OrderCancellation.vue` — actually the "POS Settings hub" (commit 91dcdf2 renamed it): contains void/comp cancellation positions + manager-approval + reports-positions + kitchen-positions sections (imports at Settings/OrderCancellation.vue:15-50; sections at :173, :241, :312). `Settings/OrderNumbering.vue` separate page.

SPA routes (router.ts): /, /orders, /portal-users, /pos-staff, /branches[/:uuid], /roles, /floor-plan, /tables[/:uuid], /catalogue (+ products/new, products/:uuid/edit), /taxes, /expense-categories, /production, /messages, /deliveries, /branch-targets, /inventory (+ /inventory/receipts, /new, /:uuid), /customers[/:uuid], /discounts, /offers, /expenses, /loyalty, /reports + 15 report routes (router.ts:339-354), /settings/order-cancellation, /settings/order-numbering, /audit-log, /change-password, /profile.

## 2. Routes/controllers by module (all in `src/routes/web.php`) (VERIFIED)

- Auth: login :136, 2FA challenge :144-149, TOTP enroll/confirm/destroy :175-183, forgot/reset :123-128, change-password :162, profile :168, session-fresh middleware `EnsureMerchantSessionIsFresh` :155.
- Portal users: index/store/update/suspend/reactivate/reset-password/assign-roles :190-208. Roles CRUD + catalog :248-257.
- Branches: portal list :213; POS branches show/devices/products/staff/activity/update/receipt-template :221-240.
- Floor plans: floors CRUD + saveLayout :264-274; tables CRUD + regenerate-qr :278-285; table-insights overview/show :293-296.
- Catalogue: categories CRUD :301-308; products CRUD + import + wizard :311-326; addon-groups CRUD :335-342; addons CRUD :346-351; product↔addon-group sync + inline group create :355-362; sync-branches :364; recipe update :372; component-options / addon-link-options / components :378-384 (product-as-add-on P-G3, cooked components PD3b); product show :389.
- Product stock: show/receive/receive-distribute/allocate/transfer/adjust/waste/movements :394-410 (per-branch UNITS for ready/bought-in products, PD1/PD2; central-warehouse receive+distribute P-G4 parity).
- Productions: index + summary :416-421 (kitchen production history, P-G1 cooked type).
- Messaging: staff-messages index/store/destroy :427-432; portal messages inbox/sent/unread-count/recipients/store/read :433-444.
- Deliveries: index/confirm/adjust :451-456 (P-G7 settlement). Delivery providers CRUD :903-909; per-product delivery prices list/set/remove :1008-1013.
- Branch targets: index/performance/store/update/destroy :461-469 (P-G8 window engine).
- Device Live (Scalefusion MDM): show/reboot/shutdown/alarm/message :478-487 (P-G9), controller `Pos/DeviceLiveController.php`, client `app/Support/ScalefusionClient.php`.
- Ingredients: CRUD + purchases :493-502; ingredient stock show/receive/receive-distribute/allocate/transfer/adjust/movements :508-521; ingredient units CRUD :525-537 (unit-of-measure model, PD4 metric family auto-units, guard b59b36b).
- Physical items: CRUD :544-550 (P-G2/PD3a — physical items live in Inventory, out of catalogue).
- Suppliers: CRUD :553-559.
- Purchase receipts (GRN): index/store/show/recordPayment :569-576 (PD6 one-page delivery; accounts payable + partial payments 1afac44; deliver straight to branch "GRN Phase B" 33a1ad9... actually 52137df).
- Branch stock: index/adjust/restock/purchase/movements :581-590; stock counts index/store :594-596 (day-end counts, Phase A 96a2d64); branch transfers index/show/store :603-607; waste index/store :616-618 (ingredient waste; product waste via product-stock.waste :407, commit 6c82799... actually d8f902b-era "Product wastage" 6cd9933-adjacent commit `d641496`? — correct commit: "Product wastage: record waste of cooked + bought-in products").
- Restock requests: index/show/store/suggestions/update/submit/approve/reject/cancel/allocate/resolve-purchased :632-654 (Restock Phase A fulfilment debits warehouse 48973fe).
- Customers: index/tags/show/analytics/orders/store/update/destroy/merge/attachPlate/detachPlate :672-696 (vehicle plates many-to-many P-F2; merge).
- Loyalty: rules CRUD/pause/resume :709-719; per-customer loyalty show/adjust/transactions :722-726; wallet topup/adjust/ledger :729-733.
- Discounts: CRUD/pause/resume/syncTargets :740-754 (auto_apply P-F4). Offers: CRUD/pause/resume :761-773 (P-F9).
- Expenses: index/store/review/reject :780-786; expense categories CRUD :792-798.
- Dashboard: summary :805, sales-comparison :808.
- Saved views: CRUD :814-820 — **no frontend usage found** (grep for savedViews/saved-views in resources/js: zero hits) → backend-only.
- Reports: export :831 + 16 GET endpoints :833-884 (see section 3); shift reopen :848; payouts index/lines :856-858; commission-invoices index/lines :862-864.
- Orders: index :889, show :892.
- Taxes CRUD :916-919 (incl. purchase tax "PT" aa468be).
- Settings: purchase-tax-recoverable :924-926; order-cancellation :932-934; manager-approval :942-944; reports-positions :951-953; kitchen-positions :960-962; order-numbering :971-973.
- Void reasons CRUD :979-985; comp reasons CRUD :987-993.
- POS staff: index/store/update/suspend/reactivate/terminate/reset-pin :1022-1034.

## 3. Reports — every report + query source (VERIFIED)

Controller `src/app/Http/Controllers/Pos/ReportsController.php` (322 lines) dispatches one Action per report (constructor :53-71); export supports CSV/PDF/XLSX via `ReportExportRequest` + `Report{Csv,Pdf,Xlsx}Exporter` (Phase D6 acf6559). All actions in `src/app/Actions/Pos/Reports/`. Source tables per action (grep of `pos_*` table refs):

| Report | Action | Source tables |
|---|---|---|
| Sales | SalesReportAction | pos_orders, pos_order_items, pos_order_item_addons, pos_order_discounts, pos_payments, pos_payouts, pos_sale_commissions, pos_expenses, pos_expense_categories, pos_company_settings, pos_branches (incl. finalized/pending commission split, SalesReportAction.php:511; mixed-tender apportionment 08b6db2) |
| Customers | CustomerReportAction | pos_customers, pos_orders, pos_loyalty_accounts, pos_loyalty_transactions |
| Discounts | DiscountReportAction | pos_orders, pos_order_discounts, pos_staff |
| Discounted & comped products | DiscountedCompedProductsReportAction | pos_orders, pos_order_items, pos_order_discounts, pos_order_comps |
| Comps | CompReportAction | pos_orders, pos_order_comps, pos_branches, pos_staff |
| Shifts | ShiftReportAction | pos_shifts, pos_branches, pos_staff (+ same-day reopen action, ShiftsController) |
| Payouts | PayoutBreakdownReportAction | pos_payments, pos_payouts, pos_sale_commissions |
| Product performance | ProductPerformanceReportAction | pos_orders, pos_order_items, pos_order_item_addons, pos_products |
| Recipe cost | RecipeCostReportAction | Eloquent-based (no raw pos_ table strings; uses recipe/ingredient models) |
| Staff activity | StaffActivityReportAction | pos_orders, pos_shifts, pos_staff |
| Inventory consumption | InventoryConsumptionReportAction | pos_stock_movements, pos_branch_stock, pos_ingredients, pos_stock_counts, pos_stock_count_lines |
| Portion variance | PortionVarianceReportAction | pos_stock_movements, pos_stock_counts, pos_stock_count_lines, pos_waste_records, pos_ingredients (commit 1a8fc52 "where the food went, in money") |
| Loss & waste | LossWasteReportAction | pos_waste_records, pos_stock_movements, pos_product_stock_movements, pos_orders (voids), pos_products, pos_ingredients, pos_branches, pos_staff |
| Restock & purchasing | RestockPurchasingReportAction | pos_stock_movements, pos_suppliers, pos_ingredients, pos_branches |
| Round-up donation | RoundUpDonationReportAction | pos_roundup_donations (real aggregation, commit 5246ad1) |
| Audit log | AuditLogReportAction | pos_audit_logs |

Non-report analytic actions: DashboardSummaryAction, SalesComparisonAction, TableInsightsAction, CustomerAnalyticsAction, CustomerOrdersAction, OrdersListAction, OrderDetailAction, ProductionSummaryAction, BranchActivityAction, PayoutBranchLinesAction, CommissionInvoiceBranchLinesAction (all `src/app/Actions/Pos/Reports/`).

## 4. Catalog module (VERIFIED)

Models: Product, ProductCategory, ProductComponent, ProductRecipe, ProductRecipeVersion, AddOn, AddOnGroup, AddOnConsumption, BranchProduct, ProductDeliveryPrice (`src/app/Models/`). Actions in `src/app/Actions/Pos/Catalogue/` (19 actions incl. CreateProductWizardAction, UpdateProductRecipeAction, UpdateProductComponentsAction, SyncAddOnConsumptionAction, ImportProductsAction).
- Product types: ready / bought-in / cooked (P-G1) with recipe versioning; wizard warns when saving ingredient/cooked product with no recipe (33a1ad9).
- Modifier groups = AddOnGroups with min/max constraints (commit fbbe324 "modifier-group constraints"; unsatisfiable-minimum guard a1914ad); product-as-add-on linked product picker (b79257a); per-option stock usage editor (28a59de, 3f0395d).
- Catalog flags: low-stock threshold, tax-inclusive, tablet visibility, category branch availability (c641937); product available-hours UI (f30c388); delta-sync visibility bumps for device config (951ad62, 1383555, 3d77e9e).

## 5. Inventory module (VERIFIED)

Actions in `src/app/Actions/Pos/Inventory/` (39 actions). Append-only ledgers: `WriteStockMovementAction.php`, `WriteProductStockMovementAction.php`. Two parallel stock domains: ingredient stock (IngredientStock, warehouse receive/distribute/allocate/transfer/adjust) and product stock (ProductStock, same verbs + waste). Unit-of-measure: IngredientAltUnit + `IngredientUnitConverter.php` (PD4 metric families). GRN: PurchaseReceipt{,Line,Charge,Payment} models, `CreatePurchaseReceiptAction`, `WriteReceiptPaymentAction` (accounts payable); receive cost books a "Stock purchases" expense (c03e646, f566589 cash-model expenses). Restock: RestockRequest{,Line}, Suggest/Create/Submit/Review/Allocate/ResolvePurchased/Cancel actions; fulfilment debits the warehouse (48973fe). Stock counts: StockCount{,Line}, SubmitStockCountAction (day-end counts). Waste: WasteRecord, RecordWasteAction + RecordProductWasteAction. Branch transfers: BranchTransfer{,Line}, TransferStockAction/TransferProductStockAction. Guards: ingredient delete vs add-on usage + unit-change vs recipe refs (ce3710d, b59b36b). Shelf life + batch expiry + disposition reporting (2c36afa P-G1.5).

## 6. Other modules (VERIFIED)

- Customers: merge, tags + DOB (7cfde6f), vehicle plates many-to-many (5f4ba4b), analytics.
- Loyalty: LoyaltyRule/Account/Transaction + customer wallet (CustomerWalletLedgerEntry; TopUpWallet/AdjustWalletBalance/WriteWalletLedgerEntry actions).
- Discounts: Discount + DiscountTarget, EvaluateDiscounts (test EvaluateDiscountsTest.php), auto_apply. Offers: Offer model + OfferConfig support (P-F9).
- Expenses: review/reject workflow; purchase-tax recoverable setting (aa468be PT).
- Commissions (merchant view): Payout, CommissionInvoice models; per-sale breakdown Slice A/B/C (a1efb24, 932c4bd, 97658de), per-channel delivery commission + invoice received-split (b59acae, bd770f7), monthly summary export (6cd9933), gifted value excluded from net (31231ec), settlement flow (04697b2).
- Floor plans/tables: Floor, Table models; layout save, QR regenerate; TableInsights (joined orders under every covered table 55082b7).
- Staff: PosStaff lifecycle (suspend/reactivate/terminate/reset-pin); PortalUser roles via spatie (reseed_roles.php at src root; role-cache fix fd6fe59).
- Devices: Device, DeviceActivationToken models; Live tab via Scalefusion (1e99b00) — reboot/shutdown/alarm/message only (restricted port).
- Messaging: StaffMessage{,Read} (to POS staff), PortalMessage{,Read} (portal inbox) + ReverbPublisher.
- Settings: CompanySetting model; six setting endpoints (section 2); order numbering with receipt_number (12fb5bc); manager-approval positions (b08811f); kitchen access always/optional (91dcdf2); reports_positions device gating (da4bc9c).
- Round-up: report only (device-side capture lives in pos_api); giftTotals anchored on company_id via pos_orders join (06523d6).

## 7. UI vs backend-only (VERIFIED by frontend grep)

Backend-only (routes exist, no Vue consumer found):
- **SavedViews CRUD** (`web.php:814-820`, `Pos/SavedViewsController.php`) — zero hits for `savedViews`/`saved-views` in `resources/js`. Dead or future surface.
- **DeliveryProviders CRUD** (`web.php:903-909`) — `resources/js/lib/api/deliveryProviders.ts` is imported ONLY by `Catalogue/ProductWizard.vue:83` and `Catalogue/Index.vue:62` (per-product delivery prices). No page found that creates/edits/deletes providers themselves (Deliveries/Index.vue imports only `api/deliveries`). Cannot fully rule out inline usage elsewhere — marked partially verified.

Everything else in section 2 has a mapped Vue surface (section 1). Settings for manager-approval / reports-positions / kitchen-positions / void+comp reasons all live inside `Settings/OrderCancellation.vue` (the POS Settings hub), not separate pages. Purchase-tax-recoverable setting surfaced in Inventory/Expenses purchase forms (`PurchaseTaxField.vue`, `PurchaseReceipts/Create.vue`, `Expenses/Index.vue`).

## 8. Git history themes (260 commits total; last ~80 verified via `git log --oneline`)

Newest → oldest themes:
1. **Split/mixed tender + delivery money** (08b6db2 apportionment, fd24033 per-leg tender chips, b59acae/bd770f7 per-channel commission + invoice received-split, 7e690d9 commission invoices merchant view).
2. **Food-cost analytics** (1a8fc52 Portion Variance, b5438c1 discounted/comped products, fe3308a kitchen production charts).
3. **Inventory hardening** (52137df GRN deliver-to-branch, 48973fe restock fulfilment debits warehouse, ce3710d delete/parity guards, 33a1ad9 no-recipe confirm, 1afac44 accounts payable).
4. **Tenant isolation phases 2a/2b/3/5** (30e3326 global scope, 8563b27 pin-before-binding, fbac3d5 scope-coverage guard, bd3a100 per-app remember-me cookie, 06523d6 giftTotals anchor).
5. **Commission/payout slices A/B/C + settlement** (a1efb24, 932c4bd, 97658de, 04697b2, 9952f31, d641496).
6. **Table insights** (502fc72, 55082b7). **Dashboard charts** (182f793, 7e802e7).
7. **PD1–PD6 product/stock model rework** (b06b5f9 per-branch UNITS, 8d68f80 wizard, 4594948 physical items, 28a59de per-option usage, 60882c5 metric units, f566589 cash-model expenses, 4382a1e GRN, aa468be purchase tax).
8. **P-G series** (G1 kitchen production, G1.5 shelf life, G2 physical items, G3 product-as-add-on, G4 central warehouse, G5 branch scope, G6 messaging, G7 deliveries, G8 targets, G9 device Live/Scalefusion).
9. **Ops/CI** (2dbced0 auto-deploy VPS, ac06c76 CI env, several prod-compose fixes, 422f67e/77c7658 flaky-CI factory fixes).
10. Earlier: P-F series (offers, order numbering, reports positions, bank_pos tender, auto_apply, plates M2M, manager approval), Phase D (2FA, password reset, exports, dashboard, CI), receipt templates + logo, sales heatmap, v2 #17/#18 payout + round-up reports, Phase A/B (piece purchases, day-end counts, void/comp reasons, modifier constraints).

## 9. Findings

- P3: SavedViews API is backend-only with no UI consumer (`src/routes/web.php:814-820`; grep of resources/js shows zero references). Either dead code or future surface.
- P3 (verified:false on completeness): DeliveryProviders CRUD endpoints (`src/routes/web.php:903-909`) have no discovered management UI; the api client is only used for per-product delivery prices in Catalogue. Providers may be seeded/managed elsewhere (pos_admin?) — outside this charter to confirm.
- P3: `Settings/OrderCancellation.vue` is a misnamed file — it is the whole POS Settings hub (order cancellation + manager approval + reports positions + kitchen positions), route `/settings/order-cancellation`.
- Note (not a defect): tenant scope is deliberately no-op when unpinned (documented in `BelongsToCompanyScope.php`), relying on pin-before-binding (Phase 2b) + scope-coverage test as compensation.

## Cannot-verify / inferred

- Runtime behavior (auth flows, Scalefusion calls) not executed — static read only.
- Exact per-commit content beyond messages spot-checked (SalesReportAction finalized/pending SQL verified at line 511).
