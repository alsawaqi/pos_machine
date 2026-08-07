# map-pos_machine — Flutter main POS (C:\src\projects\pos_machine)

Audit date: 2026-08-07. READ-ONLY inspection. All paths repo-relative unless noted.
Repo has 123 commits (d10800f "first commit" → 5aea76b). Branch: main.

## 1. Repo shape

- Flutter app, Android-first (Sunmi T3 PRO hardware). `lib/` = 58 hand-written Dart files (plus generated `*.g.dart`, `l10n_*.dart`).
- Native Android layer: `android/app/src/main/kotlin/com/example/pos_machine/` — MainActivity.kt (191), MosambeeBridge.kt (627), PaymentProxyActivity.kt (320), RearPaymentProxyActivity.kt (332), RearDisplayHost.kt (231), RearDisplayPresentation.kt (166), SunmiRearDisplayBridge.kt (318), ManagerBiometricBridge.kt (91).
- Key lib sizes: `lib/screens/staff_pos_screen.dart` 14,159 lines (monolithic main screen), `lib/state/pos_controller.dart` 3,956 (ChangeNotifier, ALL cart/payment/held/table logic), `lib/screens/customer_display_screen.dart` 2,990, `lib/models/pos_models.dart` 2,241, `lib/services/config_mapper.dart` 1,186.
- `docs/`: RELEASE_SIGNING.md, `sunmi-support-customer-display-touch.md` (a full support ticket documenting the NP521 touch-binding bug), `docs/sunmi/SunmiFingerprintService Develop Document(1.0.6_RELEASE).docx`.
- `test/`: 48 test files (see §14).
- Release identity: `applicationId = "net.mithqal.pos.machine"` (android/app/build.gradle.kts:49), release keystore via key.properties scaffold (build.gradle.kts:58-78; commit 168595f). Kotlin package + MethodChannel names still `com.example.*`.

## 2. Boot / auth path (VERIFIED)

`lib/main.dart:17-75` — `main()` configures kiosk mode (landscape, immersiveSticky, main.dart:100-116), loads `SessionService` (secure storage + prefs), wraps in ProviderScope, optional Sentry init (`SentryConfig.enabled` = DSN present; `sendDefaultPii=false`, `attachScreenshot=false`, tracesSampleRate 0.1 — main.dart:41-74).

`lib/screens/staff_startup_gate.dart:11-36` — boot state machine:
1. not configured → `DeviceSetupScreen` (single admin activation code, QR-scannable — `POST /auth/device/activate`, pos_api_service.dart:83-88; QR scanner mobile_scanner, front camera per commit 91e6231)
2. no staff → `StaffPinLoginScreen` (`POST /auth/pos/login` with pin + live GPS lat/lng for server-side login geofence — pos_api_service.dart:93-105)
3. no open shift → `ShiftOpenScreen`
4. else → `GeofenceGate(StaffPosScreen)`.

Session layers (`lib/services/session_service.dart`): layer 1 = device token (FlutterSecureStorage) + kiosk_id/terminal_id/terminal_pin/company_id/branch_id (prefs), persists across staff logout; layer 2 = staff PIN session JSON. Only a BARE 401 (no errors[]) clears pairing (`clearForRePair`, session_service.dart:252-264; envelope logic pos_api_service.dart:530-575 — an invalid_pin 401 or geofence 422 does NOT unpair, commit f46356f). Open shift persists in prefs (`open_shift_json`) and survives staff logout (device-drawer semantics, session_service.dart:8-10, 244-248).

API base URL 3-tier (`lib/core/api_config.dart:17-30`): `--dart-define=POS_API_BASE_URL` → release default `https://posapi.mithqal.net/api/v1` → debug `http://localhost:8088/api/v1`; operator Settings runtime override wins over all (baseUrlGetter per request, pos_api_service.dart:31-46; providers.dart:158-172).

## 3. Drift schema (VERIFIED — schemaVersion 27)

`lib/data/db/app_database.dart:45` `schemaVersion => 27`. DB name `pos_machine_cache`. 23 tables (`lib/data/db/tables.dart`):

| Table | Purpose | Notes |
|---|---|---|
| BranchCache | single-row branch (geofence lat/lng/radius, receiptTemplateJson) | tables.dart:14-30 |
| Categories | + category-level addonGroupIdsJson (Phase B) | :32-45 |
| Products | basePriceBaisas, branchStockQty, addonGroupIds, deliveryPriceBaisas + deliveryPricesJson (per-provider), stockMode (unit/ingredient/untracked), recipeJson, availableFrom/Until windows | :47-82 |
| Floors / PosTables | floor-plan layout px in 1200x800 canvas, shape | :84-114 |
| AddonGroups / Addons | min/maxSelections, isDefault, linkedProductId (P-G3 sold-out grey), consumptionJson (PD3b per-option gating) | :118-155 |
| VoidReasons / CompReasons | Phase B; comp maxAmountBaisas cap | :159-186 |
| SyncMeta | single row: cursor (configSchemaVersion), orderCancelPositions, reportsPositions, kitchenPositions, orderNumberingJson (all JSON position lists; null = managers-only fallback) | :189-214 |
| TaxCache | company taxes, ratePercent | :219-228 |
| OrderOutbox | durable order outbox: orderUuid PK, eventsJson, attempts, lastError, syncedAt | :237-249 |
| DeliveryProviders | provider picker | :254-263 |
| ExpenseCategories | dynamic expense picker | :269-279 |
| Discounts | scope product/category/order, fixed/percent, validity+dow mask+time window+branch scope, stackable, requiresManagerApproval, autoApply (P-F4), targetsJson | :287-314 |
| Offers | P-F9 bogo/bundle/multi_buy/cheapest_free/spend_get, configJson | :320-339 |
| StaffMessages | P-G6 announcements + readStaffIdsJson | :346-359 |
| LoyaltyRules | visit_based/spend_based + configJson | :366-378 |
| CachedCustomers | offline slice: wallet, loyaltyJson per-rule balances, platesJson (P-F2) | :383-398 |
| BranchIngredientStock | ingredient balances → recipe sold-out | :404-411 |
| Ingredients | + piece model (pieceUnitLabel/unitsPerPiece/allowFractionalPieces, Phase A) | :417-435 |
| MarketingSliders / MarketingSliderItems | v27, Phase 3 customer-screen ads; replaced WHOLESALE every pull | :443-475 |

Migration ladder v2→v27 fully additive (app_database.dart:48-181). Money is integer baisas everywhere in the cache; conversion to double OMR only at the mapper bridge (tables.dart:7-9).

`replaceConfig` (app_database.dart:316-388) wipes+reinserts everything EXCEPT OrderOutbox in one transaction. `applyDelta` (:396-541) upserts changed rows + purges per-entity deleted-id lists; sliders always replaced wholesale; SyncMeta cursor advanced, policies refreshed only when present (null → Value.absent so a stray delta can't blank them, :523-539). `consumeProductShelfStock` (:291-305) locally decrements finite shelf stock clamped at 0 after a sale until next config sync overwrites.

## 4. Config sync (full + delta + live push)

`lib/data/config_repository.dart`:
- `fetchAndCache` (:20-56): GET /device/config → ConfigMapper.parse → replaceConfig; persists terminal_id, terminal_pin, meta.websocket, audience_measurement flag.
- `syncConfig` (:65-133): delta-preferring (`GET /device/config/delta?since=cursor`), any delta failure self-heals to a full sync. DOCUMENTED GAP (:62-64): deltas don't signal deletion of taxes, branch_stock rows, or deactivated delivery providers — healed only by full syncs at activation + staff login.
- P-F1 bugfix comments record two past wipe bugs: voidReasons/compReasons rows were never passed to replaceConfig (wiped every sync) and never read back into the catalog stream (config_repository.dart:39-42, 159-162) — now fixed.
- `watchCatalog` (:142-285): manual combineLatest over 22 Drift streams → CatalogSnapshot → PosController.

Live push (Phase C3): `lib/services/live_sync.dart` — hand-rolled Pusher-protocol-7 client over dart:io WebSocket (no SDK), joins `private-branch.{id}` (company fallback) with device-token auth via POST /broadcasting/auth (pos_api_service.dart:195-211; signature re-requested per reconnect). ANY domain event triggers a debounced delta sync — 3 s, or 700 ms for `marketing.sliders.changed` (providers.dart:254-268). Connectivity gates connect/teardown (providers.dart:271-278). Additionally StaffPosScreen runs a 60 s config poll timer and flushes the outbox on connectivity regain (staff_pos_screen.dart:249, 259, 345).

## 5. OrderOutbox + sync (offline-first)

`lib/data/order_sync_repository.dart`:
- `enqueue` (:25-74): builds order.create/order.pay(/order.deliver)/donation.record batch (pure builder, §6), persists to outbox BEFORE any network I/O, then `flush()`. Skips carts with no pushable lines (demo products).
- `enqueueVoid` (:82-108): own row keyed `{uuid}:void` so it can't collide with the (possibly already synced) order row; oldest-first flush ordering pushes create/pay before void.
- `enqueueHold` (:118-144): row `{uuid}:hold`, re-hold resets syncedAt/attempts (server upserts by uuid).
- `flush` (:150-209): per-row POST /device/sync/push; success = every event `status == 'processed'` (duplicates echo processed = success); rejection recorded to lastError + Sentry capture on FIRST failure only (flood control); transport failure just increments attempts. Idempotency on stable client_event_ids.
- `pushSliderDisplay` (:216-222): ad-play telemetry deliberately NOT durable (best-effort, dropped on failure).

## 6. Order sync payload (pure, unit-tested)

`lib/services/order_sync_payload.dart`:
- `omrToBaisas` (:24), `mapOrderType` (:27-39, quick_order→quick), `mapPaymentMethod` (:42-52: 'bank'→bank_pos checked BEFORE 'card'; gift; loyalty; default cash).
- `buildOrderSyncPayload` (:87-417): order.create carries uuid, order_type, source=main_pos, receipt_number (P-F8), subtotal/discount/comp/tax/grand baisas, lines+addons, discounts split into order-level + per-line + offer allocations (:179-217), comps: gift rows (is_gift, line_index) capped against comp budget + reasoned manager comp remainder — rows must sum EXACTLY to comp_total (server enforced) (:222-254), gps, staff/table/joined_table_ids, customer_id/plate/note (delivery provider recorded in the note — pos_orders has no provider column, :121-126).
- Tenders (:285-311): split → one row per SplitPaymentRecord with last-leg remainder forcing Σ == grand; card tender carries softpos_reference/auth_code/bank_response + status success|pending_reconciliation (`_applyCardCharge` :57-69).
- P-G7 pending delivery (:344-374): delivery order with a provider reference emits order.deliver INSTEAD of order.pay (no tender, lands pending_verification server-side; settled later on the merchant Deliveries page). Deliberately not conditioned on provider id so a missing provider fails server-side rather than becoming a phantom cash sale.
- Round-up donations (:383-414): one donation.record per rounding CARD leg with `payment_index` mapping to the exact pos_payments row (commit cbd4431); cash-leg round-ups defensively skipped.
- `buildOrderHoldEvent` (:426-505), `buildOrderTransferEvent` (:515-544, hold payload + target_device_id, pushed ONLINE with inline ACK — never the durable outbox), `buildOrderVoidEvent` (:553-582, void_reason_id + authorized_by audit trail).

## 7. Payment flows (PosController)

`lib/state/pos_controller.dart` (3,956 lines, ChangeNotifier):
- `payAndPrint` (:2745-2960): allocates P-F8 receipt number once per order with a 3 s fuse (offline → local number stands, :2764-2774); charity prompt if eligible; then branches: Cash (:2795-2833, validates tendered ≥ payable when round-up accepted), Bank POS (:2840-2859, record-only, wire method bank_pos — stays out of card-commission base), Gift (:2867-2882, Phase D4, screen owns the manager gate, tender method 'gift' at full grand total), else CARD via `_runCardCharge`.
- `_runCardCharge` (:3493-3522): `payWithPreparedSession` → success | isUncertain → `_promptForPendingReconciliation` (retry / record / cancel) | else aborted.
- Unresolved-charge prompt (:3527-3590): NO auto-cancel — "a timer must never answer a money question" (commit 5aea76b). After 2 min it ESCALATES (danger flag + SystemSound alert, :3558-3567) and waits for a human. Force-hide via order reset completes as cancel (:3901 area).
- Pending record path (:2897-2919): completes the sale with `CardCharge(status: 'pending_reconciliation')` → admin reconciliation queue. Classification lives in `MosambeePaymentResult` (§8) — `neverReachedTerminal` charges (MISSING_TERMINAL_ID / BAD_ARGS / app not installed) can NOT be marked paid (commit caefd36); only genuinely ambiguous verdicts (NFC timeout etc, `isUncertain`) offer the record button.
- Split payments: equal splits + Phase 3 custom amounts (commit f19b990); `payMixedCashAndCard` (:2962+) cash+card in one tender; split records in `_splitPayments` (SplitPaymentRecord: baseAmount, paidAmount, cardCharge, charityRoundUpAccepted/Amount — pos_models.dart:1333-1391); last-leg remainder equalizes to grand total in payload.
- Charity round-up: `canOfferCharityRoundUp` (:1449-1461) = NOT delivery AND selected method == 'Credit Card' AND round-up ≥ 0.001 — CARD-ONLY by design (commit f7930fd closed the cash-split till leak; rationale in code comment). Customer answers on the rear display (`charity_round_up_response` message, customer_display_screen.dart:1858); prompt timeout/cancel aborts payment (:2777-2792).
- Full cancel of a pushed order emits order.void via `onOrderVoided` (:2657-2671); server-history records (fromServer) are cancelled online instead (commit 82e878c). Void reasons required when configured; position policy `orderCancelPositions` gates who may cancel (v2 #14).
- Delivery: provider picker + per-provider prices (Products.deliveryPricesJson resolution map[provider] → deliveryPriceBaisas → base, tables.dart:63-67); delivery-provider orders carry zero tax (commit 10c7e88, `_isTaxExempt` :1338); P-G7 `completeDeliveryOrder` (:2684-2743) no-tender pending-verification close, provider frozen at punch time (:2697-2702).
- Taxes: dynamic company taxes from config (commit 9f1a603 "replaces hardcoded 5%"), `activeCompanyTaxes` (:739-741), `tax => _isTaxExempt ? 0 : taxTotalFor(_taxedBase)` (:1338).

## 8. Card charge hardware integration (Mosambee SoftPOS)

- NOT an SDK: the device launches the co-installed **Mosambee Dhofar SoftPOS APK** `com.mosambee.dhofar.softpos` via explicit intents `com.mosambee.softpos.login` / `com.mosambee.softpos.payment` with startActivityForResult (MosambeeBridge.kt:19-20, 217-242, 280-297). Flutter side `lib/services/mosambee_payment_service.dart` over MethodChannel `com.example.mosambee` (:220).
- Session pre-warm: `prepareLogin` (slow login done ahead), `payWithPreparedSession` falls back to `loginAndPay` on NO_SESSION/BUSY (:265-353). Login args: userName = terminal_id (bank-issued, from activation/config), pin = cached `terminal_pin` else default '1321' (:224-233). Amount sent in baisas (`(amountOmr*1000).round()`, :253-258).
- Result parsing `MosambeePaymentResult` (:8-217): isSuccess (status/success or responseCode 0/00 incl. nested receiptResponse), isCanceled, `neverReachedTerminal` (:87-94 — MISSING_TERMINAL_ID, BAD_ARGS, "is not installed"/"was not found"/"unable to launch") vs `isUncertain` (:100). Evidence extraction: softposReference (rrn/txn id — bank settlement match key, :109-118), softposAuthCode (:121-126). Comment block :79-94 documents the money-critical distinction (recording a never-sent charge would invent revenue no settlement file can match — commit caefd36).
- The payment activity can launch on the REAR display via `RearPaymentProxyActivity` (manifest, MainActivity/RearDisplayHost) so the customer taps their card on the customer-facing screen; `paymentLaunchState` events (login_started/payment_started, surface front|rear) drive the staff overlay and rear-display handoff (pos_controller.dart:3612-3639).
- Preflight: missing terminal_id fails fast with MISSING_TERMINAL_ID before launching SoftPOS (mosambee_payment_service.dart:302-313).

## 9. Printing (Sunmi)

`lib/services/sunmi_receipt_service.dart` via `sunmi_printer_plus ^4.1.1` (pubspec.yaml:38):
- `printReceipt` (:48-236): merchant per-branch template (logo base64 PNG, business name en/ar, header/footer lines, CR/VAT numbers, showQr toggle — from BranchCache.receiptTemplateJson) else default "MITHQAL 2.0". Items, discount, comp line (separate from discount), subtotal, tax, TOTAL, split payments with per-guest charity round-up lines, AMOUNT PAID, QR (`MITHQAL|TOTAL=...|STATUS=...`).
- NEVER throws: returns false on failure so callers alert staff (Phase G4 printer-failure alerts, commit 1192328); MissingPluginException (non-Sunmi dev hardware) silently clears `printerPluginAvailable` (:11-14, 52-58).
- Kitchen ticket (Phase C1, `lib/services/kitchen_ticket.dart`, no prices, manager-gated reprint), Z-report shift summary (Phase C6, `lib/services/shift_summary.dart` 478 lines — server summary preferred, local calculator fallback), mid-shift X-report (G3) via `printTicketLines`.
- FINDING: receipt tax line label is hardcoded `'Tax (5%)'` (sunmi_receipt_service.dart:159) while the amount is the dynamic multi-tax total — wrong label whenever company tax ≠ 5%.

## 10. Dual-screen customer display

- Second Flutter engine: `@pragma('vm:entry-point') secondaryDisplayMain()` (main.dart:77-98) → `CustomerDisplayApp`; separate engine, reads language itself from prefs; NO Sentry (double-native-init hazard).
- Native: `RearDisplayHost` + `RearDisplayPresentation` (android Presentation API) opened via MethodChannel `getPresentationDisplays`/`openRearDisplay` (MainActivity.kt:28-60); `SunmiRearDisplayBridge.kt` (318 lines) talks to the Sunmi USB-screen service. Flutter orchestration in `lib/services/presentation_service.dart` (215 lines; picks the presentation-category display, falls back with a mirror-only warning :38-45).
- Staff↔customer engines talk over `pos_machine/rear_display_channel` (customer_display_screen.dart:29): staff broadcasts order state/payment status/display notes; customer sends `charity_round_up_response` (:1858) and `slider.display` telemetry requests (:353-361, staff engine owns the API client).
- Ad slider (Phase 3): `lib/widgets/ad_slider.dart`, MarketingSliders/Items cache, image+video slides (video_player), per-slide durations, plays behind the order/payment UI; play telemetry → pos_marketing_impressions (best-effort). Audience measurement (Phase 1A/#46): `lib/services/audience_service.dart` (208 lines) — front camera frames → google_mlkit_face_detection FaceDetector fast-mode, in-memory only, counts folded into slider.display telemetry; gated by BOTH device Settings toggle and server-driven consent flag (`meta.audience_measurement`, session_service.dart:199-211; commit cb0be84).
- KNOWN HARDWARE BUG (documented, unresolved): 10.1" USB customer display (NP521) touch digitizer stays bound to displayId=0 — customer taps land on the staff POS. `docs/sunmi-support-customer-display-touch.md` is a complete Sunmi support ticket with adb/dumpsys evidence; `setScreenTpSwitch` received but ignored by firmware. Matches user memory note. Charity round-up "customer answers on rear screen" is therefore not safely usable on this hardware until Sunmi responds.

## 11. Shifts, manager gates, satellite screens

- Shifts: `shift.open`/`shift.close` sync events (`lib/services/shift_payload.dart` — shared_shift:true opt-in HH-2 model: one open shift per STAFF per branch adopted by every terminal, :57-72; expected_cash/variance computed server-side, :17-43). `ShiftOpenScreen` can ADOPT a server-side open shift on desync (fetchCurrentShift?staff_id, pos_api_service.dart:380-396; commit 77ee186). `ShiftCloseScreen` = cash reconciliation + printed Z-report; last summary persisted before clearShift for manager reprint (session_service.dart:227-242). Logout asks "close shift or just log out" (commit 29f0d58).
- Manager gates: fingerprint = REAL native BiometricPrompt (`ManagerBiometricBridge.kt:56-81`) via channel `com.example.manager_biometrics`; used for order cancellation, comps, gifts, discount approval, reprints, mid-shift report. WEAKNESS: "registration" merely sets prefs bool `manager_biometric_registered` after ANY successful device biometric (manager_authorization_service.dart:23-35) — the OS prompt accepts any fingerprint enrolled on the Android device; no binding to a manager identity. Mitigation: P-F1 manager PIN fallback verified SERVER-SIDE against manager_approval_positions (`/device/auth/verify-manager-pin`, pos_api_service.dart:107-129) — but PIN path is online-only ("PIN approval needs a connection — use the fingerprint instead", app_en.arb:1483).
- Kitchen (P-G1): online-only screen — fetchKitchen/startProduction/finishProduction (expiry P-G1.5)/cancelProduction (server-side manager PIN)/disposition day-end split (waste/give-away/carry-over, PIN-gated) — pos_api_service.dart:398-502. Walk-up gate: kitchen staff punch their own PIN (`verify-kitchen-pin`, :137-153).
- Expense logging / restock / stock count / waste: REAL, not stubs — `lib/services/expense_restock_service.dart` + `expense_restock_payload.dart` build expense.log / restock.request / stock.count / product.waste events pushed online through /device/sync/push (payload :57, 118, 178, 214); screens `log_expense_screen.dart`, `restock_request_screen.dart` (two-pane T3 landscape), `stock_count_screen.dart` (piece model), `waste_product_screen.dart`. Online-required by design (mirrors ShiftService).
- Reports (P-F6): full-screen branch dashboard, `/device/reports/branch`, access gated by reportsPositions policy.
- Messages (P-G6): staff announcements chip + sheet + read receipts (`/device/messages/read`).
- Order transfer (machine side, commit 5f1ad7b): send = order.transfer event online-only inline ACK; receive = poll `/device/transfers/incoming` (staff_pos_screen.dart `_transferPollTimer` :276) + claim `POST /device/transfers/{uuid}/claim` (409 transfer_unavailable on double claim). Controller legs at pos_controller.dart:2315-2360.
- Held orders: local storage (`lib/services/local_order_storage_service.dart`, 415 lines, sqflite-based order store separate from Drift cache) + Phase C2 server mirror via order.hold; resume at :2427; table transfer + merge (G2, :2091-2132).
- Settings screen: server URL override + test connection (pingBaseUrl), print-receipts / kitchen-tickets toggles, language en/ar, audience toggle (`lib/services/settings_service.dart` 129 lines).

## 12. Geofence

- Login: GPS sent with staff PIN; server rejects outside fence (commit b104b47).
- Runtime: `geofenceProvider` (providers.dart:292-350) re-syncs config first (delta-preferring) so admin fence edits apply, then streams Geolocator positions vs cached branch fence; fail-closed (no fix / no permission ⇒ locked; no fence configured ⇒ allowed). `GeofenceGate` (geofence_gate.dart:10-24) full-screen lock around StaffPosScreen. GPS also rides order.create/order.pay so the SERVER fails closed at fenced branches (order_sync_payload.dart:88-90).
- `lib/services/geofence_service.dart` (45 lines): haversine distance, defaultRadiusM, toleranceM.

## 13. l10n

- Phase C4: gen-l10n (`l10n.yaml`), `app_en.arb` (2,034 lines incl. metadata) + `app_ar.arb` (916 lines), runtime en/ar toggle with RTL Directionality (main.dart:122-133); separate customer engine re-reads language at engine start (main.dart:84-93). Arabic catalog names (name_ar) end-to-end (commit 5ec5f46).

## 14. Tests

48 files in `test/` covering: card charge classification, charity round-up gate + pos_controller charity flow, split plans, order sync payload, config delta, config mapper (addons, sliders), offer engine + offers-catalog bridge, delivery (pending/pricing/tax), discounts (auto-apply, line, merchant), loyalty (rules, offline, earn picker), shift payload/summary, order numbering/cancel-policy/history-server, kitchen production + ticket, receipt template, l10n, live_sync, messages, availability, audience gate, manager auth, terminal PIN, table transfer/merge, expense/restock, settings, customer display + plates, void/comp reasons. Memory note: baseline 17 known failures in charity-flow + widget tests. Commit cb0be84 "Green the suite (21 stale failures)". CI via GitHub Actions (commit 422bed1). NOT RE-RUN in this audit (read-only, time).

## 15. Recent git history themes (123 commits)

Chronological arcs:
1. Foundation: activation/pairing (single code + QR), catalog fetch (Riverpod+Drift), geofence, taxes-from-config, dine-in floor plan mirroring the merchant planner.
2. Money core: offline outbox push (f6687a3), Soft POS evidence capture (8fbde83, 80af94d), pending-reconciliation force-record (7d53fe3), shifts Phase 1a-1c, settings/server URL, merchant discounts Phase 3a-3c.
3. Loyalty/customers/expenses (Phase 4-5), delta sync (Phase 7), server order history, desynced-shift adoption.
4. v2 sweep: line discounts, order-cancel policy + order.void, loyalty earn rules on pay, custom receipt template + branch logo.
5. Phase A/B/C: stock count + piece model, void/comp reasons + modifier constraints, kitchen tickets, held-order mirroring (C2), Reverb live push (C3), Arabic i18n sweep (C4a-e), Sentry (C5), Z-report (C6), Phase D4 gifts, CI (D9).
6. Gap sweeps G1-G4: menu time windows, table transfer/merge, X-report, printer-failure alerts.
7. P-F1..F9: manager PIN fallback, customer details/plates, loyalty program picker, auto-apply discounts + custom values w/ reason, Bank POS tender + per-item gifts, reports dashboard, zero-tax delivery, merchant order numbers, offers engine (Drift v22).
8. P-G1..G7: kitchen production/expiry/disposition/walk-up gate, product-backed addon sold-out, messages, per-option consumption gating (v26), pending-verification deliveries, wastage.
9. Marketing phase: ad sliders (v27), staff screen work, audience gate (#46).
10. Final hardening: charity round-up card-only (f7930fd) + per-leg donation.record (cbd4431), custom split amounts (f19b990), release signing + applicationId, order transfer + HH-2 shared shifts + tiered base URL (5f1ad7b), card-charge classification (caefd36), no-timer unresolved-charge prompt (5aea76b).

## 16. Findings

1. **P3 — Hardcoded 'Tax (5%)' label on printed receipt** — sunmi_receipt_service.dart:159. Amount is the dynamic tax total; the LABEL always says 5% even when company taxes differ or are multiple/zero (delivery tax-exempt orders would print "Tax (5%) 0.000"). Cart UI uses dynamic tax names; only the printout lies. VERIFIED.
2. **P2 — Manager fingerprint gate trusts any device-enrolled fingerprint** — manager_authorization_service.dart:23-35 + ManagerBiometricBridge.kt:56-81. "Register manager" = one successful BiometricPrompt then a prefs bool; every later approval accepts ANY fingerprint enrolled in Android settings (e.g. a cashier who enrolled their own finger). Server-verified PIN fallback exists but is online-only (app_en.arb:1483). Offline, all manager gates (cancel/comp/gift/discount/reprint) reduce to device-enrolled-biometric. VERIFIED (code); real-world exploitability depends on who can enroll fingerprints on the terminal (MDM may lock Settings — not verifiable here).
3. **P2 — Cleartext HTTP enabled in the release manifest** — android/app/src/main/AndroidManifest.xml:21 `android:usesCleartextTraffic="true"` in the MAIN manifest (commit 82d60ae added it for dev). Combined with the operator-editable server URL in Settings, a production terminal can be pointed at an http:// endpoint and will send the device Bearer token and order data in cleartext. Default release URL is https, so this is a misconfiguration surface, not an active leak. VERIFIED.
4. **P2 — Customer-display touch bound to staff display (hardware/firmware)** — docs/sunmi-support-customer-display-touch.md. On the T3 PRO + NP521 10.1" customer display, customer taps are delivered to the operator screen; the charity round-up accept/decline on the rear display is the customer-facing input that this breaks (customer taps could trigger arbitrary staff-POS actions under the same coordinates). Ticket prepared for Sunmi; fix requires Sunmi USB-screen SDK/firmware. VERIFIED as documented + matches persistent memory; not device-verifiable here.
5. **P3 — Delta sync cannot delete taxes / branch stock rows / deactivated delivery providers** — config_repository.dart:62-64 (self-documented). Healed only by full syncs at activation + staff login, so a deleted tax can keep applying on a long-lived logged-in terminal until re-login. Mitigated by the 60 s poll being delta-only (does NOT heal) — heal requires full sync. VERIFIED (device side; server delta behavior belongs to pos_api's charter).
6. **P3 — Kotlin package / channel namespaces still com.example.*** — MainActivity.kt:1, mosambee channel 'com.example.mosambee' (mosambee_payment_service.dart:220) despite applicationId net.mithqal.pos.machine. Cosmetic/consistency; internal channels so no functional risk. VERIFIED.

## 17. Stubbed vs real (charter checklist)

- Expense logging: REAL (online-required sync event). Restock request: REAL. Stock count: REAL (piece model). Waste: REAL. Shift open/close screens: REAL (server-settled, Z-report printed). Fingerprint: REAL native BiometricPrompt but weak identity binding (finding 2). Kitchen production: REAL, online-only. Offers engine: REAL on-device evaluation (offer_engine.dart, 432 lines). Sunmi printing: REAL with dev-hardware silent fallback. Rear display: REAL rendering; touch broken by firmware (finding 4). Audience measurement: REAL (ML Kit face counting) but consent-gated both locally and server-side. Order transfer: REAL, online-only by design. Loyalty: REAL incl. offline cached balances. Demo/non-catalog products still exist in the UI model and are filtered out of every sync payload (order_sync_payload.dart:137, 146).

## Cannot-verify / out of scope

- Server-side behavior of every event type (contract belongs to pos_api charter).
- Actual test-suite pass state today (not re-run; memory says 17 known baseline failures).
- Whether MDM (Scalefusion) blocks fingerprint enrollment on terminals (mitigates finding 2).
- iOS/desktop folders exist but are unmaintained scaffolding (kiosk is Android-only).
