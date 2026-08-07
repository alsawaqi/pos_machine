# map-pos_admin — Evidence file

Audited: `\\wsl.localhost\ubuntu\home\abdallah644\projects\my-projects\pos\pos_admin` (read-only). All paths repo-relative unless noted. Laravel code under `src/`.

## 0. Repo state (VERIFIED)

- **Working tree is CLEAN** — `git status --porcelain` returns 0 lines; "nothing to commit, working tree clean". The charter's "~150 dirty/untracked files" expectation does NOT hold for pos_admin at audit time. The branch `main` is **2 commits ahead of `origin/main`** (unpushed): `ed4cd58` "Ad billing: stop devices choosing what an advertiser is billed for" and `33ca794` "Advertiser pages: say what business activity actually does".
- 216 total commits; 153 migration files in `src/database/migrations`.
- Stack: `laravel/framework ^13.7`, `spatie/laravel-permission ^7.4` (src/composer.json:11,19). Vue 3 SPA under `src/resources/js` (Pages/Components/Layouts/stores/composables/locales), Vite + vue-tsc, TS config `src/tsconfig.json`.
- Deploy: `docker-compose.prod.yml` — php-fpm app (`pos_admin`), `nginx`, `pos_admin_redis`, one-shot `composer` / `node-build` / `artisan` (`php artisan migrate --force`, line 127) / `deploy` / `init-perms` services; joined to external `charity_net` network (line 192). APP_ENV/APP_DEBUG forced in compose env (lines 39-42).

## 1. Recent git history themes (last ~80 commits, VERIFIED via `git log --oneline`)

Reverse-chronological clusters:
1. **Advertiser billing (Phase 5, newest)**: rate cards + delivery-metered invoices (`d2c3f0e`), device-proof billing (`ed4cd58`), advertiser page copy (`33ca794`), competitor advisory in slider builder (`4153050`).
2. **Charity round-up robustness**: hourly retry sweep command (`1dcda22`), mixed-tender apportionment ("stop paying merchants their own drawer money", `ed40469`), split visibility per-leg tender chips (`d750569`).
3. **Commission settlement & invoicing**: estimate→settled actual bank fee (`23ddc67`,`b189004`), settlement UI (`65e7863`,`4ae3a37`,`e671e37`), reconcile-before-payout enforcement (`5a07002`), gate bypass fix (`9a0d32a`), commission invoices for cash/bank-POS (`7b291fd`), per-channel card-vs-cash profiles (`6b737f7`,`cf2c0b2`).
4. **Schema-on-behalf-of-other-apps** (pos_admin as schema owner): P-G1..G8 (kitchen production, day-end disposition, physical items, add-on linked products, central warehouse, messaging, deliveries, targets), PD3/PD6 (addon consumptions, GRN), AP/PT tax columns, HH-2 shared shifts, order transfer, `component_snapshot_json` (P-G2 freeze), restock resolution, GRN destination branch.
5. **Marketing/ads platform**: slider builder (multi-select, touch reorder, camera capture), audience analytics, audience-measurement consent (#46), marketing impressions.
6. **Earlier phases**: settlement/payout workflow (Slice A-D), dine-in joined tables pivot, TOTP 2FA (D8), CI + auto-deploy to production VPS, offers (P-F9), order-number sequences (P-F8), pending-reconciliation queue (P-F7).

## 2. Migrations — authoritative pos_* schema (VERIFIED)

153 migrations in `src/database/migrations`, from `2026_05_12_160000` to `2026_08_06_010200`. Full `Schema::create` inventory (extracted by grep; excludes ALTERs):

### Charity-shared stubs (create-if-missing; charity app is authoritative)
`banks`, `commission_profiles` (charity round-up ref), `countries`, `regions`, `districts`, `cities`, `organizations`, `advertisers`, `content_assets` — created by `ensure_*_stub` / `*_if_missing` migrations (e.g. `2026_05_26_010000_ensure_banks_stub.php`, `2026_06_26_100000_create_advertisers_table_if_missing.php`, `2026_06_26_999999_ensure_organizations_stub.php`). Comments state authoritative writes live in the charity/marketing-api apps; POS reads only (also stated in `src/routes/admin.php:51-67`).

### Legacy `pos_admin_*` names (renamed 2026_05_24 `rename_pos_admin_tables_to_pos_prefix.php` to `pos_*`)
Created as `pos_admin_companies/users/branches/devices/business_activities/company_activities/company_documents/company_status_history/audit_logs/branch_user/device_activation_tokens/devices` + permission tables (`2026_05_12_160005`) + `pos_admin_device_assignments_history` (in foundation tables `2026_05_12_160004`). After rename these live as `pos_companies`, `pos_users`, `pos_branches`, `pos_devices`, etc. (`pos_admin_audit_logs` → `pos_audit_logs` presumed by rename migration; rename mapping not re-listed here line-by-line — the rename file is authoritative).

### Full table list by domain (table → purpose, creation migration date)
**Identity/tenancy/platform**: pos_companies (merchants + advertising-only companies, `is_advertiser_only` 06_26), pos_users (portal+platform users, `must_change_password` 06_21, 2FA cols 07_06), pos_company_owners (05_24), pos_password_reset_tokens (07_05), pos_settings (05_26 platform key/value), pos_company_settings (06_29 + duplicate-guard 08_04 `create_pos_company_settings_table_if_missing`), pos_saved_views (06_14), permission tables (spatie: pos_roles etc., 05_12; `is_system`+description 05_27).

**Merchant onboarding/compliance**: pos_business_activities (05_17), pos_company_activities, pos_company_documents, pos_company_status_history; Oman compliance fields on companies (05_17).

**Devices/MDM**: pos_devices (blueprint fields 05_24, terminal_id+commission_profile 05_25, bank_id 05_26, terminal_id unique per bank 06_15, organization_id 06_27, terminal PIN 07_05), pos_device_makes/pos_device_models (05_25), pos_device_assignments_history, pos_device_activation_tokens.

**Branch/floor/table**: pos_branches (blueprint fields 05_24, receipt_template 06_25), pos_floors, pos_tables (05_27, position 05_27), pos_order_tables (07_30 joined dine-in pivot), pos_branch_product (06_23).

**Catalog**: pos_product_categories (parent_id 06_12), pos_products (default tax 05_27, delivery_price 05_28, stock_mode 06_25, catalog flags 07_04, availability window 07_07, internal flag+components 07_16, internal_purpose 07_22), pos_addon_groups/pos_addons/pos_addon_group_categories/pos_addon_group_products (05_28), pos_product_components (07_16), linked product on addons (07_17), pos_addon_consumptions (07_23), pos_offers (07_13), pos_taxes (06_24).

**Inventory**: pos_suppliers, pos_ingredients, pos_branch_stock, pos_stock_movements (05_29), pos_product_recipes/pos_product_recipe_versions (05_30), pos_waste_records, pos_restock_requests/lines (05_31, resolution 08_05), pos_branch_transfers/lines (06_13), pos_product_stock/pos_product_stock_movements (06_25, waste fields 07_27), pos_ingredient_units (06_30), UoM piece model + pos_ingredient_purchases + pos_stock_counts/lines (07_01), pos_ingredient_stock central warehouse (07_18), pos_productions/pos_production_lines (07_14 kitchen production), cooked shelf-life + batch expiry (07_15), pos_purchase_receipts/lines/charges/payments (07_24 GRN, purchase tax 07_25, AP payables 07_26, destination_branch_id 08_05).

**Customers/loyalty**: pos_customers (06_01, dob+tags 07_03), pos_customer_vehicle_plates (06_01, many-to-many 07_08), legacy pos_customer_loyalty_configs/point_ledger (06_02, dropped 06_08), pos_customer_wallet_ledger (06_02), pos_loyalty_rules/accounts/transactions (06_08).

**Orders/payments**: pos_orders (06_04; location 06_19; receipt_number 07_12; order transfer cols 07_31), pos_order_items (06_04, component_snapshot_json 08_05), pos_order_item_addons, pos_payments (06_04; bank+roundup fields 06_17; bank_fee 08_02), pos_shifts (06_04, is_shared HH-2 08_01), pos_order_sequences (07_12), pos_discounts/pos_discount_targets (06_05, auto_apply 07_09), pos_order_discounts (06_10, reason 07_09, offer_id 07_13), pos_void_reasons/pos_comp_reasons/pos_order_comps (07_02 Phase B, is_gift 07_10), pos_expenses (06_07, branch nullable 06_20), pos_expense_categories (06_27), pos_delivery_providers/pos_product_delivery_prices (06_03, delivery lifecycle 07_20), pos_sync_events (06_09, idempotency scoped per device 06_22).

**Money/commissions/donations**: pos_roundup_donations (06_18, forwarded_at 07_11), pos_commission_profiles/pos_commission_shares/pos_sale_commissions (06_26 — see §5), pos_payouts (07_01, branch_id 07_29), settlement cols on sale_commissions + pos_commission_settlements (07_28), pos_commission_invoices (08_03, method split 08_03, applies_to on shares 08_03), channel on sale commissions (08_06).

**Marketing/ads**: pos_marketing_sliders/items/targets (06_26), pos_marketing_impressions (06_29), pos_ad_rate_cards + pos_ad_invoices (08_06 — see §7).

**Messaging/targets**: pos_staff (05_27), pos_staff_messages/pos_staff_message_reads + pos_portal_messages/pos_portal_message_reads (07_19 P-G6), pos_branch_targets/pos_branch_target_windows (07_21 P-G8).

Notable structural conventions (VERIFIED from migration doc-blocks): money tables use **plain indexed ids, no FKs** for cross-concern references (`2026_06_26_010200_create_pos_sale_commissions_table.php:18-22`, `2026_07_28_010100:22-24`); profile/percent **snapshots** for immutability; PII columns widened for encryption (`2026_05_26_030000`).

## 3. Routes / controllers (VERIFIED)

- `src/routes/web.php` (119 lines): SPA shell + auth. `/` → `/admin`; `/auth/csrf`, `/auth/login` (rate limit inside controller, line ~75-84), TOTP 2FA challenge routes (public by design with server-side pending state, lines 59-70), enrol/confirm/disable (lines 101-113), `/admin/{path?}` SPA fallback **excluding `/admin/api/*`** (lines 88-97, prevents SPA-HTML-instead-of-403), FQCN middleware (not aliases) per header comment.
- `src/routes/admin.php` (473 lines): all admin API under `admin/api/v1`, middleware `['auth', 'pos.admin.session', 'pos.tenant']` (line 47). Aliases in `src/bootstrap/app.php:34-35` → `EnsurePosAdminSessionIsFresh`, `SetTenantContext`. Custom `pos_admin_session` guard driver in `src/app/Providers/AuthServiceProvider.php:77-90`.
- 39 Api/Admin controllers (`src/app/Http/Controllers/Api/Admin/`). Route groups: commission-profiles/banks/organizations (read-only charity refs, lines 54-67), bank-reconciliation preview/commit (72-75), pending-reconciliation index/approve/reject (82-87), geography CRUD (91-109), business-activities (115-122), marketing advertisers/content/sliders/upload (130-192), merchants + nested documents/status/activities/audience/commission-profile/portal-users (194-265), branches (267-309), devices + assign/unassign/decommission/activation-token/scalefusion (277-313), device-makes/models (320-341), platform-team + roles (347-378), dashboard summary (385), settings (391-394), audit-logs + CSV export (403-406), orders + summary (410-415), sales/settlement/roundup reports (420-430), payouts (434-439), commission-settlements (444-450), commission-invoices (455-461), ad-billing (465-472).
- `src/routes/api.php` is 12 lines (essentially empty); `console.php` 17 lines.

## 4. Vue page tree (VERIFIED — 35 pages under `src/resources/js/Pages`)

Auth: Login, TwoFactorChallenge. Admin: Dashboard, Security, AdBilling/Index, AuditLog/Index, CashSales/Index, Devices/{Index,Register,Edit,Show}, Invoices/Index (commission invoices), Marketing/{Advertisers/{Index,Create,Show}, Review/{Index,Show}, Sliders/{Index,Builder,Audience}}, Merchants/{Index,Create,Show}, Orders/Index, PendingReconciliation/Index, Roles/Index, RoundUpDonations/Index, Settings/{Index, BankReconciliation/Index, BusinessActivities/Index, DeviceCatalog/Index, Geography/Index}, Settlements/{Index,Reconcile}, Payouts implied inside Settlements/Invoices pages, Team/Index.

## 5. Commissions module (VERIFIED)

- **Two distinct "commission profile" concepts** (explicitly documented): charity-owned `commission_profiles` (round-up shares, read-only ref; `src/routes/admin.php:51-55`) vs POS-owned `pos_commission_profiles` per-merchant revenue split (`2026_06_26_010000` doc-block; one profile per company_id unique; merchant takes residual = 100 − Σ shares, stored as `merchant_percent` decimal(5,2)).
- `pos_commission_shares`: share lines (platform/bank/other) + `applies_to` channel scoping added `2026_08_03_010300` (card vs cash_bank sections; commit `6b737f7`).
- `pos_sale_commissions`: append-only per-sale breakdown, one row per party incl. merchant residual, plain-id no-FK, profile+percent snapshotted (`2026_06_26_010200:9-23`); `payout_id` (07_01), settlement cols `settled_amount`+`settlement_id` (07_28), `invoice_id` (08_03), `channel` card|cash_bank (08_06).
- `RecordSaleCommissionAction` (`src/app/Actions/Admin/Reconciliation/RecordSaleCommissionAction.php`) — declared **TWIN of pos_api's `app/Actions/Device/Sync/RecordSaleCommissionAction.php`, "keep in sync"** (lines 15-19). Splits in integer baisas, merchant takes exact remainder (Σ rows == grand_total to the baisa); bank line charged only on card-paid portion; gift tenders excluded from collected; fully-gifted order records no rows; idempotent if breakdown exists; per-channel residuals for mixed tenders (lines 25-55).
- Settlement flow: `pos_commission_settlements` header (estimate → actual bank fee, variance; source manual|bank_file; status applied|reversed; reversible only before payout claim — `2026_07_28_010100:9-24`). Actions: `SettleCommissionAction`, `SettlementOrdersAction`, `SettlementPendingAction` (`src/app/Actions/Admin/Reconciliation/`). Reconcile-before-payout enforced server-side (commit `5a07002`; gate bypass closed `9a0d32a`).
- Payouts (`pos_payouts`, card channel — platform holds money, pays merchant): `src/app/Actions/Admin/Payouts/{CreatePayoutAction, MarkPayoutPaidAction, BatchMarkPayoutsPaidAction, CancelPayoutAction, PayoutBranchLinesAction}`. Routes: read on reports.view, mutate on settings.manage (`admin.php:432-439`).
- Commission invoices (`pos_commission_invoices`, cash/bank_pos channel — merchant holds money, owes platform): `src/app/Actions/Admin/Invoices/*`; amounts decimal(12,3): gross/platform/other/merchant/total_owed; lifecycle issued→paid|void (migration `2026_08_03_010000:41-67`).

## 6. Pending reconciliation + charity round-up forwarding (VERIFIED)

- P-F7 queue: `PendingReconciliationController` index/approve/reject (`admin.php:77-87`); approve fires DEFERRED effects — commission split + charity forwarding — via `ReconcileDeferredEffectsAction`, `ApprovePendingReconciliationAction`, `RejectPendingReconciliationAction` (`src/app/Actions/Admin/Reconciliation/`).
- `ForwardCharityDonationAction` — **TWIN of pos_api's version, "keep in sync"** (lines 13-17). POSTs to charity `POST /api/donations-pos-roundup`; best-effort, never throws, skipped when `services.charity.url` unset; returns true only on 2xx → stamps `pos_roundup_donations.forwarded_at`; false leaves NULL for retry (lines 26-34). Sends device/branch snapshot, charity commission_profile_id, organization_id (lines 60-70+).
- Retry sweep: `src/app/Console/Commands/RetryRoundupForwarding.php` (`donations:retry-roundup-forwarding`, limit 200/run). Eligibility: forwarded_at NULL, payment not pending_reconciliation, ≥10 min old; idempotent via pos_reference dedupe on charity side (doc-block lines 15-32). Test: `src/tests/Feature/Admin/RetryRoundupForwardingTest.php`.
- **FINDING (P2): the retry command is NOT scheduled anywhere in this repo.** `src/routes/console.php` schedules only `ScanExpiringCompanyDocumentsJob` (dailyAt 02:00, lines 14-17). Grep for `donations:retry`/`RetryRoundupForwarding` outside the command+test finds nothing; `docker-compose.prod.yml` has NO scheduler/cron/`schedule:run` service (services: pos_admin php-fpm, nginx, redis, one-shots only; verified by service list + grep for schedule/cron/supervisord/queue:work in `docker/prod` — zero hits). Commit `1dcda22` calls it an "hourly retry sweep" but nothing in-repo runs it hourly. Even the daily document scan has no visible `schedule:run` runner. A host crontab outside the repo could exist — cannot verify.

## 7. Advertiser/ads billing module (VERIFIED)

- `pos_ad_rate_cards` (`2026_08_06_010100`): pricing_model `per_day_per_screen` (rate × distinct device-day actually played) or `per_thousand_impressions` (rate × plays/1000); billing delivery-metered from `pos_marketing_impressions`, replay-guarded ("over-billing structurally impossible"); advertiser_id app-level link to marketing-api-owned `advertisers`, no DB FK; one active card per advertiser enforced by `SetAdRateCardAction` (doc lines 10-27).
- `pos_ad_invoices` (`2026_08_06_010200`): full snapshot at issue (pricing_model, rate, metered quantities); lifecycle issued→paid|void, re-issuable after void; duplicate protection action-level under lockForUpdate in `CreateAdInvoiceAction`; advertiser-facing copy read by marketing-api over the shared table (doc lines 10-27).
- Actions: `src/app/Actions/Admin/AdBilling/{PendingAdBillingAction, CreateAdInvoiceAction, AdInvoiceLinesAction, MarkAdInvoicePaidAction, VoidAdInvoiceAction, SetAdRateCardAction}`. Routes `admin.php:463-472` (read reports.view, money settings.manage). Test `AdBillingTest.php`.
- Marketing pipeline: advertisers CRUD incl. `storeWithCompany` advertising-only company wizard (`admin.php:130-152`), content review approve/reject (writes only review fields on marketing-api-owned `content_assets`, `admin.php:154-165`), slider builder with conflict check + audience + targets (`admin.php:167-192`), content upload forwarded to marketing-api's shared store (`admin.php:187-192`). Per-merchant audience-measurement consent (#46) at `admin.php:211-216`.

## 8. Bank reconciliation module (VERIFIED)

`src/app/Services/Admin/BankReconciliationService.php` — ported logic-for-logic from charity's `BankReconciliationPreviewService`; reconciles `pos_payments` (card tenders) instead of charity_transactions (doc lines 21-31).
- **Banks/formats** (resolveBankConfig, lines ~232-286): bank_id **2 or name contains "dhofar" → Bank Dhofar** `bank_dhofar_v1`, xlsx sheet "Table 1", header date in cell E4, columns DATE/TERMINAL ID/AUTHO CODE/GROSS AMOUNT/CARD NO, header date trusted over row cells; bank_id **1 or "oman arab"/"oab" → Oman Arab Bank** `bank_oab_csv_v1`, CSV with TRANSACTION_DATE/TERMINAL_ID/AUTH_CODE/TRANSACTION_AMOUNT/NET_AMOUNT/SETTLEMENTDATE etc., strict row-date validation. Any other bank → ValidationException "parser is not configured" (line ~282).
- Match key: normalized terminal_id + auth code; amount tolerance < 0.0005 OMR; payment terminal_id/bank_id from payment snapshot cols first, else the device (lines 28-31, 161-203). Bank fee = max(0, gross − net) stored on the payment at commit for settlement pre-fill (A2 comment, ~line 118).
- Routes preview/commit (`admin.php:69-75`); commit via `ReconcilePaymentsAction` + `MarkPaymentReconciledAction`. UI `Pages/Admin/Settings/BankReconciliation/Index.vue`. Test `BankReconciliationTest.php`.
- Note: bank_id 1/2 hardcoded with name fallback — adding a bank requires code change (by design; INFERRED as accepted limitation).

## 9. Scalefusion MDM integration (VERIFIED)

`src/app/Services/ScalefusionService.php` — "Ported verbatim from the charity app"; talks to Scalefusion v3 devices API; kiosk_id-keyed summary map cached (fresh TTL 120s default, stale 900s, refresh lock 20s, max 25 pages; config `services.scalefusion.*`; lines 13-45). Public API: getDevicesSummaryMapCached, findDevicesByIds, getDevice, getDeviceLocations, reboot, sendAlarm, broadcastMessage, runAction, clearAppData, lock, unlock (lines 29-547). POS joins against `pos_devices.kiosk_id` only. Controller `DeviceScalefusionController` — read gated by DevicesView, every control action by DevicesControl + audited (`admin.php:293-305`): show/locations/reboot/alarm/lock/unlock/clear-app-data/action/broadcast-message. Tests: `DeviceScalefusionTest.php`, `DeviceScalefusionControlTest.php`, `ScalefusionServiceTest.php`.

## 10. Geography (VERIFIED)

Countries/regions/districts/cities are charity-shared tables (ensure-stub migrations 2026_06_16); full CRUD in admin (`admin.php:89-109`) — read open to any admin, mutations gated by settings.manage in controllers (route comment lines 89-90). Controllers: CountriesController, RegionsController, DistrictsController, CitiesController; models under `src/app/Models/Geo`. UI `Pages/Admin/Settings/Geography/Index.vue`. Test `GeographyTest.php`.

## 11. Roles / permissions (VERIFIED)

- `src/app/Enums/PlatformPermission.php` — **39 cases**: merchants.{view,create,update,transition_status,delete}; merchant_documents.{view,upload,verify}; branches.{view,create,update,transition_status,delete}; devices.{view,register,assign,unassign,decommission,activate,control}; device_models.manage; device_shipments.manage; merchant_users.{view,invite,revoke}; platform_users.{view,invite,update_roles,suspend}; audit_logs.view; reports.{view,export}; settings.manage; business_activities.manage; roles.{view,manage}; marketing.advertisers.manage; marketing.content.review; marketing.sliders.manage (lines 9-89).
- `PlatformRole.php` — 5 seed roles: platform_super_admin, onboarding_officer, device_operations, support, finance_viewer (lines 9-13).
- Roles builder manages roles under **team_id=0 platform sentinel** (`admin.php:364-368`); role mutation is a separate meta-permission `platform_users.update_roles` (`admin.php:357-362`).
- 12 Policy classes (`src/app/Policies/`): Advertiser, AuditLog, Branch, BusinessActivity, CompanyDocument, Company, ContentAsset, DeviceMake, DeviceModel, Device, MarketingSlider, PortalUser. PlatformTeamController and RolesController use direct can() checks (no policy; documented `admin.php:343-346,364-368`).
- Tenancy: `pos.tenant` → `SetTenantContext` middleware (`src/bootstrap/app.php:35`); tenant context binding was fixed from singleton to scoped (commit `1265094`).

## 12. Audit logging (VERIFIED)

- `src/app/Actions/Security/WriteAuditLogAction.php`: writes AuditLog rows (actor_user_id, company_id, branch_id, event, auditable morph, ip, user_agent, old/new values, metadata).
- **40 call sites** across actions: all 2FA actions, merchant/company lifecycle (create/update/delete/status/activities/documents verify+reject+upload), branch create/update/delete, device assign/unassign/decommission/update/activation-token, platform user invite/update/suspend/reactivate, role CRUD + assignment, portal user actions, settings update, advertiser create/update/reset-password, content review, business activities CRUD, device catalog CRUD, and money actions (SettleCommissionAction, MarkPaymentReconciledAction, ReconcileDeferredEffectsAction, RejectPendingReconciliationAction).
- Viewer: AuditLogsController index + `export.csv` sharing filter parsing (`admin.php:396-406`), gated by AuditLogPolicy/audit_logs.view. UI `Pages/Admin/AuditLog/Index.vue`.
- Not every action audits (e.g. Payout/Invoice/AdBilling actions not in the WriteAuditLogAction grep list — those may log via other means or not at all; INFERRED gap, not fully traced).

## 13. Devices & activation (VERIFIED)

Register/assign/unassign/decommission workflow with history rows + audit (`admin.php:274-291`); one-shot activation code minted by `CreateDeviceActivationTokenAction`, exchanged on pos_merchant for a Sanctum PAT (route comment `admin.php:288-291`); terminal PIN (07_05), terminal_id unique per bank (06_15), device makes/models catalogue with scoped bindings (`admin.php:329-341`).

## 14. Tests (VERIFIED)

58 test files; `src/tests/Feature/Admin/` covers each module: AdBilling, AuditLogs, BankReconciliation, CommissionInvoice, CommissionSettlement, MixedTenderApportionment, PendingReconciliation, Payouts, RetryRoundupForwarding, Scalefusion (x3), marketing (x5), merchants/branches/devices, roles/platform team, reports (sales/settlement/roundup), geography, settings, 2FA (under Auth/Security dirs). CI: GitHub Actions with auto-deploy to production VPS after green tests (commits `d6255e7`, `394b3b2`).

## 15. Findings summary

1. **P2 — Round-up retry sweep not scheduled in-repo** (see §6). `donations:retry-roundup-forwarding` exists + tested but no Schedule:: entry (`src/routes/console.php` has only the document scan) and no scheduler/cron service in `docker-compose.prod.yml` / `docker/prod`. If no host crontab exists, failed charity forwards are never retried (the exact problem commit `1dcda22` set out to fix). Also affects `ScanExpiringCompanyDocumentsJob` (scheduled in code but nothing visibly runs `schedule:run`). verified: repo state true; production crontab unverifiable.
2. **P2 — Twin-action code duplication is load-bearing**: `RecordSaleCommissionAction` and `ForwardCharityDonationAction` are hand-maintained twins of pos_api files with "keep in sync" comments (RecordSaleCommissionAction.php:15-19; ForwardCharityDonationAction.php:13-17). Any drift silently diverges deferred-approval money math from device-path money math. Accepted-cost per comments, but it's a standing risk.
3. **P3 — Charter mismatch**: expected ~150 dirty/untracked files; working tree is clean, but `main` is 2 commits ahead of origin (unpushed ad-billing work). The dirty state may have been committed between briefings.
4. **P3 — Bank parser coverage**: only Bank Dhofar (xlsx) and Oman Arab Bank (csv) configured; hardcoded bank_id 1/2 + name matching (BankReconciliationService.php resolveBankConfig). Other banks hard-fail with a clear validation message (fail-safe).
5. **P3 — Audit coverage gap (INFERRED)**: payout/commission-invoice/ad-billing actions do not appear in the WriteAuditLogAction call-site list; money-moving mark-paid/void events may be unaudited. Not fully traced — verified:false at the "unaudited" level.
