# pos_api map (device-facing Laravel backend)

Repo: `\\wsl.localhost\ubuntu\home\abdallah644\projects\my-projects\pos\pos_api` (Laravel code under `src/`).
All facts below VERIFIED by reading files unless marked otherwise.

## 1. Request lifecycle for a device call

1. `src/bootstrap/app.php:10-40` — routing config: `api` routes from `src/routes/api.php`, health at `/up`, broadcasting channels from `src/routes/channels.php`. Middleware: `ForceJsonResponse` prepended to the api group (every `/api/*` treated as JSON regardless of Accept header), `AttachSentryDeviceContext` appended (Sentry tags: device/company/branch/request-id; no-op without SENTRY_LARAVEL_DSN). Exceptions render JSON for `api/*` and report to Sentry (`src/bootstrap/app.php:41-50`).
2. Route prefix: `/api/v1` (api group prefix + `Route::prefix('v1')`, `src/routes/api.php:44`).
3. Auth: custom `pos_device` guard via `Auth::viaRequest` — `src/app/Providers/AppServiceProvider.php:37-47`. Bearer token = `pos_devices.device_token` column (no Sanctum). Rejects `status IN ('blocked','inactive')`; SoftDeletes excludes deleted rows. Pre-pairing statuses carry no token.
4. Rate limiters (`AppServiceProvider.php:55-67`):
   - `device-pair`: 10/min per IP + 20/min per kiosk_id (pairing brute-force surface).
   - `device-api`: 120/min per resolved device id (fallback IP).
   - `pos-login`: 10/min per device — shared bucket across staff PIN login, verify-manager-pin, verify-kitchen-pin, productions/{uuid}/cancel, disposition POST (routes attach `throttle:pos-login`; `src/routes/api.php:64-86,141-155`).
5. Controllers → FormRequests (`src/app/Http/Requests/Api/V1/...`) → Actions (`src/app/Actions/Device/...`) → Models. Tenancy is derived from the device token (company_id/branch_id off the Device row), never from client input.

## 2. Full device endpoint list (src/routes/api.php)

| Method/Path (`/api/v1` prefix) | Controller | Purpose | Lines |
|---|---|---|---|
| POST `auth/device/pair` | DevicePairController | kiosk_id + one-time activation token → long-lived device_token (unauthenticated; `throttle:device-pair`) | 49-51 |
| POST `auth/device/activate` | DeviceActivateController | single admin-generated code (hash lookup) → device_token; `throttle:30,1` | 56-58 |
| POST `auth/pos/login` | StaffPosLoginController | staff PIN login on a paired device (`throttle:pos-login`); geofence enforced on login (commit ad42a43) | 64-66 |
| POST `device/auth/verify-manager-pin` | VerifyManagerPinController | P-F1 manager PIN for approval gates (comps/cancels/gifts) | 72-74 |
| POST `device/auth/verify-kitchen-pin` | VerifyKitchenPinController | P-G1.6 kitchen walk-up gate (session runs AS the verified chef) | 79-81 |
| POST `broadcasting/auth` | closure → `Broadcast::auth` | Reverb private-channel auth under the pos_device guard | 87-88 |
| POST `device/heartbeat` | HeartbeatController | liveness ping | 90 |
| GET `device/config` | DeviceConfigController@show | full config bundle snapshot | 93 |
| GET `device/config/delta` | DeviceConfigController@delta | incremental delta since timestamp | 94 |
| POST `device/sync/push` | SyncPushController | idempotent batch offline-sync ingestion | 97 |
| GET `device/orders/active` | DeviceOrdersController@active | branch's active orders | 101 |
| GET `device/orders/history` | DeviceOrdersController@history | branch order history (finalized/refunded) | 102 |
| GET `device/branch-devices` | DeviceBranchDevicesController | transfer-target picker list | 106 |
| GET `device/transfers/incoming` | DeviceTransfersController@incoming | receiving device's transfer inbox | 107 |
| POST `device/transfers/{uuid}/claim` | DeviceTransfersController@claim | atomic claim of a transferred order | 108 |
| POST `device/orders/next-number` | DeviceOrderNumberController | P-F8 atomic merchant order-number allocation; 409 `numbering_disabled` if policy off | 112 |
| GET `device/shift/current` | DeviceShiftController@current | recover a desynced open shift | 113 |
| GET `device/customers/search` | DeviceCustomersController@search | lookup by phone/plate | 114 |
| GET `device/customers/{id}` | DeviceCustomersController@show | P-F2 customer details (whereNumber) | 117-119 |
| POST `device/customers` | DeviceCustomersController@store | register a customer (revives soft-deleted phones, commit 50d9803) | 120 |
| GET `device/reports/branch` | DeviceBranchReportController | P-F6 date-windowed branch sales/tender/product/discount/loyalty/consumption aggregates | 126 |
| GET `device/kitchen` | DeviceKitchenController@show | P-G1 kitchen production screen data (ONLINE-ONLY) | 135 |
| POST `device/productions` | DeviceProductionsController@store | start a production batch | 136 |
| POST `device/productions/{uuid}/finish` | @finish | finish batch (server validates fresh ingredient balances) | 137 |
| POST `device/productions/{uuid}/cancel` | @cancel | cancel with manager PIN (pos-login bucket) | 138-140 |
| GET `device/disposition` | DeviceDispositionController@show | P-G1.5 day-end expired-cooked-pieces view | 146 |
| POST `device/disposition` | @store | apply disposition (may carry manager PIN → pos-login bucket) | 147-149 |
| POST `device/messages/read` | DeviceMessagesController@read | P-G6 staff-announcement read receipts | 154-155 |

`src/routes/web.php` has only the default welcome route. No other route files carry device functionality.

## 3. Sync-push pipeline and event dispatch table

- `SyncPushController` → `IngestSyncEventsAction` (`src/app/Actions/Device/IngestSyncEventsAction.php`).
- Idempotency contract (lines 13-36, 53-111): EXACTLY-ONCE keyed on UNIQUE `(device_id, client_event_id)`; first sight inserts `received` row and dispatches inline; duplicate ACKs `{duplicate:true}` with the ORIGINAL row's status/result; a `failed` row IS re-dispatched on re-push (transient-fault retry, lines 59-75); insert race caught via `UniqueConstraintViolationException` (101-111). Inserts are per-event, no outer transaction.
- `SyncEventDispatcher` (`src/app/Actions/Device/Sync/SyncEventDispatcher.php:62-79`) — event_type → handler match:

| event_type | Handler | Notes |
|---|---|---|
| order.create | CreateOrderHandler (820 lines) | pricing snapshot-authoritative (device money trusted, invariant validated, not re-evaluated); freezes recipe snapshot per line (§9.9); geofence fail-closed via GeofenceGuard; offer attribution (P-F9); joined_table_ids persisted |
| order.hold | HoldOrderHandler | server-side held orders (Phase C2) |
| order.transfer | TransferOrderHandler | upserts held mirror for device-to-device transfer send leg |
| order.pay | PayOrderHandler (290 lines) | tenders recorded (split = several payment rows), order → paid, inventory deducted at payment; `pending_reconciliation` card path; Σ(tendered)==grand_total invariant; commission recording, loyalty, round-up wiring |
| order.deliver | DeliverOrderHandler | P-G7 no-tender delivery intake as pending verification |
| order.void | VoidOrderHandler (276 lines) | full unwind in ONE txn: reverse inventory, inverse loyalty ledger rows (clamped), flip round-up donation to `void` (forwarded charity txn NOT reversed — manual op), delete commission breakdown EXCEPT payout/invoice-CLAIMED rows (commits cdbcacf, 6249f10); "already void" guard is sole idempotency |
| shift.open | OpenShiftHandler | HH-2 shared shifts (open once/day, any terminal) |
| shift.close | CloseShiftHandler (220 lines) | drawer reconciliation: expected_cash = opening + Σ(cash − change); shared shift attributes by STAFF across terminals, legacy by device; Z-report summary on close (Phase C6) |
| expense.log | ExpenseLogHandler | device expense entries |
| restock.request | RestockRequestHandler | branch restock requests |
| donation.record | DonationRecordHandler (224 lines) | card round-up → pos-owned `pos_roundup_donations` row (NOT charity_transactions directly); then best-effort forward via ForwardCharityDonationAction |
| stock.count | StockCountHandler (281 lines) | day-end physical count, mirrors pos_merchant SubmitStockCountAction; variance → waste record / positive adjustment; ledger invariant Σ(movements)==balance |
| product.waste | ProductWasteHandler | signed-negative product waste movements |
| slider.display | SliderDisplayHandler | ad-slide impression → pos_marketing_impressions; billing columns written only on first sight (replay refines telemetry, never money) |
| (unknown) | none — row stays `received` | dispatcher returns without stamping |

- Post-processing: handler success stamps `processed` + result_json; failure stamps `failed` + error (SyncEventDispatcher:84-99). Then `DeviceSyncBroadcast` fired best-effort in its own try/catch (lines 101-119) — Reverb outage never fails the durable domain event.
- Shared guards: `GeofenceGuard` (`src/app/Actions/Device/GeofenceGuard.php`) — haversine distance vs branch radius (default 500 m) + 100 m tolerance; enforced only when a GPS fix is supplied and branch has coordinates; judged at order-time GPS for replayed offline orders. `TenantReferenceGuard` (`src/app/Actions/Device/Sync/TenantReferenceGuard.php:31-37`) — every client-sent pos_staff id must resolve within the device's company (withTrashed so terminated cashiers' queued events settle); mismatch throws → event `failed`.
- Support actions: `ConsumeInventoryAction`, `RecordSaleCommissionAction` (per-channel commission bases, mixed-tender apportionment — commits f18d670, c076237), `ApplyLoyaltyEarnAction` / `ApplyLoyaltyRedeemAction`, `ForwardCharityDonationAction`.

### Charity round-up forwarding
`ForwardCharityDonationAction` (`src/app/Actions/Device/Sync/ForwardCharityDonationAction.php`): POST `{CHARITY_API_URL}/api/donations-pos-roundup`, sends POS device + branch ids + branch geo (shared id-space with charity geo tables) + bank receipt + pos_reference (donation uuid, commit 69e8257). Best-effort, never throws; returns true only on charity 2xx acceptance → stamps `pos_roundup_donations.forwarded_at`; false leaves marker NULL for admin retry. Skipped when `services.charity.url` unset (tests). Round-up addresses the exact card leg via payment_index (commit 3f9a5c6). Deferred when the funding tender is pending-reconciliation (P-F7, commit 08fdd61).

## 4. Config bundle + delta

`DeviceConfigController@show` / `@delta` → `BuildDeviceConfigAction` (`src/app/Actions/Device/BuildDeviceConfigAction.php`, 1292 lines, single `handle(Device, ?Carbon $since)` for both modes).

Top-level `data` keys (lines ~313-381): `settings` (order_cancel_positions, manager_approval_positions, reports_positions, kitchen_positions, order_numbering policy), `branch`, `floors`, `tables` (incl. `qr_token`, position/size for floor layout — line 757), `categories`, `products` (recipe rows, branch shelf, delivery prices, low-stock flag, stock_mode, availability windows, internal_purpose, product-as-add-on links), `delivery_providers`, `addon_groups`/add-ons (with consumption lines), `ingredients`, `branch_stock`, `discounts` (with targets + auto_apply), `offers`, `sliders` (marketing/ads), `staff_messages` (with read receipts), `loyalty_rules`, `customers` (with loyalty balances + vehicle plates M2M), `taxes`, `expense_categories`, `void_reasons`, `comp_reasons`, `deleted` (tombstone map for delta purges, lines 594-687).

`meta` (lines 386-405): mode full|delta, since, generated_at, money_unit='baisas', company_id, branch_id, terminal_id, terminal_pin, `websocket` (Reverb connection meta, lines 492-518), `audience_measurement` server-driven gate (Marketing #46).

Delta mechanics: `changed()` filters by updated_at >= since (line 578); `deletedMap`/`trashedIds` emit soft-deleted ids so the device purges (incl. branch-disabled product purge, commit 12e4c1d; re-emit on shelf-only change, commit 54cae0d).

## 5. Broadcasting (Reverb)

- Driver: `reverb` default (`src/config/broadcasting.php:19,23-24`); production runs self-hosted `php artisan reverb:start` (Phase C3, commit de573a8). Test broadcaster is `null` (channel classes unit-tested directly, per `src/routes/channels.php:27-30`).
- Channels (`src/routes/channels.php:33-35`), all guarded `['guards' => ['pos_device']]`:
  - `company.{id}` → `App\Broadcasting\CompanyChannel` — company-wide (config.changed, catalogue).
  - `branch.{id}` → `BranchChannel` — branch operational stream, "the main POS / handheld / KDS feed".
  - `device.{id}` → `DeviceChannel` — point-to-point terminal commands.
- Auth endpoint: POST `/api/v1/broadcasting/auth` inside the guard group (api.php:87-88); a device may only join its own company/branch/device channels (channel classes are the boundary).
- The single broadcast event: `DeviceSyncBroadcast` (`src/app/Events/DeviceSyncBroadcast.php`) — `ShouldBroadcastNow` (no queue worker in the device container), generic event keyed by sync `event_type` via `broadcastAs()`; lean payload {type, event_id, company_id, branch_id, result}; broadcasts on `branch.{id}` (fallback `company.{id}` for branchless device). Fired from SyncEventDispatcher after durable `processed` stamp, best-effort.

## 6. Models (src/app/Models, 46 files)

Tenancy/device: Device, DeviceActivationToken, PosStaff, User, Shift, SyncEvent.
Catalog: Product, ProductCategory, BranchProduct, AddOn, AddOnGroup, Ingredient, Offer, Discount, Tax, CompReason, VoidReason, ExpenseCategory.
Orders/money: Order, OrderItem, OrderItemAddon, OrderComp, OrderDiscount, Payment, SaleCommission, MerchantCommissionProfile, MerchantCommissionShare, RoundupDonation, Expense.
Inventory: BranchStock, StockMovement, ProductStockMovement, StockCount, StockCountLine, RestockRequest, RestockRequestLine, WasteRecord, Production, ProductionLine.
Loyalty/customers: Customer, CustomerVehiclePlate, LoyaltyAccount, LoyaltyRule, LoyaltyTransaction.
Floor plan: Branch, Floor, Table.
Marketing/comms: MarketingSlider, MarketingSliderItem, MarketingSliderTarget, MarketingImpression, ContentAsset, StaffMessage, StaffMessageRead.
Support: `src/app/Support/Money.php` (baisas↔OMR boundary conversion), `src/app/Support/OrderNumbering.php` (P-F8 policy).
No migrations own schema here — schema is owned by pos_admin; pos_api tests run against a mirrored SQLite test schema (many "mirror ... into the test schema" commits: ea0d366, 8c1dadd, eef6e61, 84c09d8, 0a9cc87).

## 7. Test suite (contract tests)

`src/tests/Feature/Device*Test.php` — 42 files, 434 `test_` methods total (counted). These ARE the device contract. Per file (name | tests | what it locks down):

- DeviceActivateTest (7) — single-code activation → device_token exchange.
- DeviceActiveOrdersTest (5) — GET orders/active shape and scoping.
- DeviceAddonConsumptionTest (8) — add-on ingredient consumption at sale.
- DeviceApiHardeningTest (7) — JSON error envelopes regardless of Accept header; auth failures.
- DeviceBranchReportTest (20) — P-F6 report aggregation over company+branch PAID orders.
- DeviceBroadcastAuthTest (6) — channel auth deny/allow per company/branch/device.
- DeviceComponentsTest (8) — frozen component set consumption (PD3b et al).
- DeviceConfigSliderTest (5) — slider slice in config.
- DeviceConfigTest (36) — the config bundle + delta contract (largest).
- DeviceCurrentShiftTest (11) — shift adoption after desync.
- DeviceCustomersTest (20) — search/show/store, plates M2M, soft-delete revival.
- DeviceDispositionTest (13) — P-G1.5 day-end disposition.
- DeviceGeofenceTest (9) — fail-closed geofence on create/pay/login.
- DeviceHeartbeatTest (4) — heartbeat endpoint.
- DeviceKitchenPinVerifyTest (5) — kitchen walk-up PIN gate.
- DeviceKitchenProductionTest (17) — P-G1 two-phase batch lifecycle.
- DeviceManagerPinVerifyTest (12) — P-F1 manager PIN verify.
- DeviceMessagesTest (5) — P-G6 read receipts.
- DeviceOfferTest (7) — P-F9 offers + attribution.
- DeviceOrderDiscountTest (5) — discount persistence incl. reason.
- DeviceOrderHistoryTest (7) — branch order history endpoint.
- DeviceOrderNumberTest (12) — P-F8 allocator, 409 numbering_disabled.
- DeviceOrderTransferTest (9) — transfer event → held mirror + claim.
- DevicePairTest (7) — kiosk+token pairing.
- DeviceProductAddonTest (4) — product-as-add-on (P-G3).
- DeviceStaffLoginTest (11) — PIN login, throttling, geofence.
- DeviceSyncBroadcastTest (4) — broadcast fired on branch channel post-processing.
- DeviceSyncCommissionTest (16) — per-sale commission breakdown incl. per-channel + mixed-tender.
- DeviceSyncCompVoidReasonTest (14) — comps + reasoned voids (Phase B).
- DeviceSyncDeliverOrderTest (4) — P-G7 deliveries.
- DeviceSyncDonationTest (12) — round-up donation record + forward + void semantics.
- DeviceSyncExpenseRestockTest (8) — expense.log + restock.request.
- DeviceSyncHoldOrderTest (10) — order.hold server mirror.
- DeviceSyncLoyaltyTest (13) — multi-rule earn, redeem, void unwind.
- DeviceSyncOrderTest (36) — order.create/pay/void core contract (largest sync file).
- DeviceSyncProductWasteTest (6) — product.waste signed-negative movements.
- DeviceSyncPushTest (8) — idempotency/ACK/duplicate/failed-retry mechanics.
- DeviceSyncShiftTest (13) — shift.open/close incl. shared-shift attribution.
- DeviceSyncSliderBillingIntegrityTest (13) — ad billing integrity (device can't choose what advertiser is billed, commit f93e46d).
- DeviceSyncSliderTest (9) — impression recording.
- DeviceSyncStockCountTest (8) — stock.count reconciliation.

`src/tests/Unit` has only ExampleTest. CI: GitHub Actions (commits f9cc68f, bfb89d1) with auto-deploy to production VPS after green tests (c23321d).

## 8. QR ordering / KDS / print agent / waiter screen — presence check

Grepped `src/app`, `src/routes`, `src/config` for qr/kds/kitchen display/print agent/waiter:

- **QR ordering: ABSENT.** The only QR artifact is `tables[].qr_token` shipped in the config bundle (`BuildDeviceConfigAction.php:757`); there is NO customer-facing QR ordering endpoint, route, controller, or menu surface in pos_api. (VERIFIED absent by route + controller inventory.)
- **Kitchen display / KDS: ABSENT as a product surface.** "KDS" appears only in comments describing the `branch.{id}` channel as "the main POS / handheld / KDS feed" (`src/routes/channels.php:24`, `BranchChannel.php:12`, `SyncEventDispatcher.php:100`, `DeviceSyncBroadcast.php:58`) — i.e. the broadcast plumbing anticipates a KDS consumer, but no KDS endpoints, tickets, bump/recall state, or station routing exist. The existing "kitchen" features (DeviceKitchenController, productions, disposition, kitchen PIN) are kitchen PRODUCTION (batch cooking/inventory), not a kitchen display of order tickets.
- **Print agent: ABSENT.** No print/printer/print-agent code anywhere in pos_api (receipt printing is device-side; the config ships `receipt_template` + logo per commits caf4f9e/16bf149, but no server print agent).
- **Waiter screen: ABSENT.** No waiter-specific endpoints/roles/surfaces. Table/floor data in config + order transfer are the closest primitives.

## 9. Git history themes (last ~85 commits, newest → oldest)

1. Billing/money integrity hardening (newest): ad-billing server-authoritative (f93e46d), mixed-tender per-channel commission apportionment + void fixes (c076237), charity forward pos_reference (69e8257), atomic sale-path stock writes (d832222), frozen component-set consumption (a655f46), offline orders surviving mid-queue catalog deletes (bf0bf72).
2. Multi-terminal features: HH-2 shared shifts (a6e8a4a), order transfer + terminal PIN + round-up payment_index (7f30a7c, 3f9a5c6, b321200), joined dine-in tables (805a218, b321200).
3. Sync hardening: device-supplied FK ownership validation (c70f2cb, Phase 4), recipe→branch deduction concurrency/ledger/retry (d46a8a3).
4. Config delta correctness: purge/re-emit rules (12e4c1d, 54cae0d), kitchen role access (e65467a).
5. P-G series (kitchen production, batch expiry/FIFO disposition, physical items, central warehouse, product-as-add-on, messaging, deliveries): 2df8075…518b017.
6. P-F series (manager PIN, plates M2M, discounts auto_apply, bank_pos tender + gift comps, branch report, deferred commission/charity on pending-reconciliation, order numbering, offers): 0c8a6e7…1d07f98.
7. Prod ops: docker compose deploy one-shots, CI auto-deploy (5ccbf03…c23321d, f9cc68f, bfb89d1).
8. Phase A–D device contract build-out: comps/voids, stock.count, Reverb (de573a8), order.hold, Z-report, Sentry + product-stock ledger, gift orders, catalog flags, availability windows.
9. v2 sweep: loyalty multi-rule earn, void unwind incl. claimed-commission protection (cdbcacf, 085d8f9), expense categories, loyalty balances in config, GET shift/current, order history.
10. Round-up/charity lineage: store_dhofar forward → generalized POS round-up endpoint with device/branch geo linkage (09cdc04, 0c8a312, ab46bf7).
11. Commission foundations: per-sale breakdown at pay, card-only bank cut, acquirer snapshot on payments (92c3b95, 053c3df, 960ac50).
12. Earliest in window: geofence on PIN login, single-code activation, revert of claim-by-terminal-id back to kiosk+token pairing (ad42a43, 62b0831, a64cc5d).

## 10. Notable observations (for the audit)

- Sync processing is INLINE in the HTTP request (IngestSyncEventsAction.php:97) — no queue; a large offline backlog batch runs all handlers synchronously within the request. Broadcast is also inline (`ShouldBroadcastNow`, documented rationale: no queue worker in the container). Design choice, documented; latency risk on big backlogs. (INFERRED risk; behavior VERIFIED.)
- Pricing on order.create is snapshot-authoritative: server trusts device-computed money, validating only invariants (CreateOrderHandler docblock). Deliberate per §9.1.6; means a compromised device can shape its own prices within invariant limits. (VERIFIED design; risk assessment out of scope here.)
- Failed-event retry happens on device re-push only (no server-side retry job) — a device that never re-pushes leaves the event `failed` forever (IngestSyncEventsAction.php:59-75). (VERIFIED behavior; consequence INFERRED.)
- Unknown event_types are silently accepted and stay `received` forever (SyncEventDispatcher.php:81-83) — forward-compatible but no alerting. (VERIFIED.)
- Void does NOT reverse an already-forwarded charity transaction (VoidOrderHandler docblock) — manual charity-side op. (VERIFIED, documented.)
