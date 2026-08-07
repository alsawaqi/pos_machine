# map-pos_handheld — Evidence file

Audit of `C:\src\projects\pos_handheld` (Flutter handheld POS, Phase 10). READ-ONLY audit, 2026-08-07.
All paths repo-relative to pos_handheld unless prefixed `pos_machine/`.

## 1. Repo shape (VERIFIED)

- Plain Flutter app, **no Riverpod, no Drift** (0 hits for `riverpod|drift` in pubspec.lock). State is `setState` + `ValueNotifier` singletons in `lib/core/services.dart` (47 lines). Contrast: pos_machine uses Riverpod 3 + Drift.
- Storage: `shared_preferences` (outbox, session scalars), `flutter_secure_storage` (device token), `sqflite` (order log HH-1 + held orders HH-3). Deps: pubspec.yaml:31-52 (dio ^5.9.2, geolocator ^14.0.1, mobile_scanner ^7.2.0, uuid ^4.5.1, sqflite ^2.4.1, google_mlkit_text_recognition ^0.16.0, camera ^0.12.0+1, sentry_flutter ^9.0.0).
- ~19.7k lines of Dart in lib/ (32 files). `lib/main.dart` is a **7,775-line monolith** holding the whole home POS screen, cart model, mock catalog, drawer, ~40 private widget/sheet classes (class index: main.dart:106-7455).
- lib/ layout: `core/` (api_config, manager_auth, palette, services, telemetry), `models/` (catalog 1363 ln, held_order, shift, transfer), `screens/` (device_setup, ops_screens 869 ln, order_history 669 ln, payment 2130 ln, plate_capture 526 ln, qr_scanner, shift_open, shift_report 734 ln, staff_login), `services/` (12 files).
- Feature codes used in comments/tests: HH-1 order log, HH-2 shared shifts, HH-3 hold/void, HH-4 discount/comp/gift, HH-5 split tenders, HH-6 customers/loyalty, HH-7 offer engine, HH-8 tables/delivery/transfer, HH-9 ops events, Step 11 Sentry.

## 2. Git history themes (VERIFIED — full log, only 9 commits)

```
ff568ac Release identity: applicationId net.mithqal.pos.handheld
5b3ef7d Step 11: Sentry crash reporting (disabled until a DSN is configured)
c5857d6 Money outbox: park repeatedly-refused batches, surface + manual retry
43145fc Release signing scaffold: real keystore via key.properties
f02d437 Gating parity with pos_machine: ingredient/cooked sold-out, shelf cap, option stock gating, bounded windows, local shelf decrement
495d532 new
9566c8b new
a96c00a..a96c98b (a96c8b) Handheld POS: full API integration + KOZEN hardware bridges + CI
8aea0d3 first commit
```
Themes: one giant "full API integration" commit (a96c98b/a96c8b `a96c8b` — exact hash `a96c8b`… see log: `a96c8b` = `a96c8b`) — history is far coarser than pos_machine's (~60+ granular commits). Two commits literally named "new" (495d532, 9566c8b) — poor traceability for a money app.

## 3. Contract doc (VERIFIED)

`docs/INTEGRATION_CONTRACTS.md` (158 lines) — distilled 2026-07-02 from pos_machine/pos_api/pos_admin source. Covers: enrollment QR (§1), config/delta (§2), geofence (§3, device 50 m buffer / server 100 m backstop), Mosambee SoftPOS (§4 — channel `com.example.mosambee`, target APK `com.mosambee.dhofar.softpos`, default terminal pin `'1321'`, AES-CBC fixed key noted in doc line 88), sync (§5 — baisas, stable client_event_id, 50/batch, order.create+order.pay one batch), receipt layout (§6), deps (§7), build order (§8).
`docs/RELEASE_SIGNING.md` — keystore workflow; warns debug-signed installs must be uninstalled (order log + held orders wiped; "flush the sync outbox first").

## 4. Money outbox (VERIFIED) — `lib/services/order_sync_service.dart` (1,277 ln)

- Durable-before-network: batch appended to SharedPreferences key `order_outbox_v1` before any I/O (order_sync_service.dart:169, 866-873). `_writeOutbox` swallows prefs failure (:785-795) — comment admits in-memory-only fallback "shouldn't happen on-device".
- Pure builder `buildOrderEvents` (:235-458): subtotal = Σ line totals; grand = subtotal − discount − comp + tax **derived** so the server invariant holds by construction (:361-364); last tender absorbs rounding so Σ tenders == grand exactly (:377-397). Comp rows sum exactly to comp_total (gift rows capped against budget, reasoned comp takes remainder, :286-317). Offers + manual discount clamped to subtotal, manual slice absorbs clamp (:319-344). `source: 'handheld'` (:408) — VERIFIED against pos_api `src/app/Models/Order.php:49` `SOURCES = ['main_pos','handheld','customer_tablet']`.
- Parked-batch ("stuck") mechanism (commit c5857d6): server *rejections* (server answered and refused) counted per batch; at `kMaxServerRejections = 5` (:186) batch gets `stuck: true` and is skipped by flush (:1189-1194); never auto-dropped ("revenue records", :180). Network errors never count (:183-185). Manual `retryStuck()` (:215-227) resets and re-flushes (safe — idempotent event ids). Parking fires a Sentry `captureMessage` with the order uuid in the message and a scrubbed server error (:1244-1259).
- Flush semantics (:1179-1276): batch leaves only when ALL events `processed`; order-log "synced" flag only flipped for batches carrying money events (order.create/order.pay, :1211-1221); if the sqlite flip fails, the batch stays queued (idempotent re-push) so the badge never lies (:1219-1229).
- Flush triggers: app start (main.dart:1056), every 60 s via the config-poll timer which drains the outbox FIRST so shelf balances aren't resurrected (main.dart:1062-1082), app-resume (main.dart:1070), after each enqueued order (`unawaited(flush())`, order_sync_service.dart:948, 1156, 1172), manual drawer tap (main.dart:3169). **No connectivity_plus listener** (grep: only comments mention connectivity) — contract §5 says "flush on connectivity regain"; the 60 s poll substitutes.
- Event builders: order.create/pay (:399-457), order.transfer (:534-567 — pushed inline, never outboxed), order.hold (:573-604, outboxed), order.void (:612-631, **deterministic id `order-void-<uuid>`** so a retry dedupes to the stored result), delivery order.create+order.deliver (no tender, tax 0, :959-1063, caps reference 64 / phone 32 chars so a long paste can't permanently stall the batch :1009-1016), HH-9 ops events product.waste / expense.log / restock.request / stock.count (:639-753) — pushed INLINE not outboxed because a legit server rejection would otherwise retry forever (rationale :755-761).

## 5. Shared shifts HH-2 (VERIFIED) — `lib/services/shift_service.dart` (209 ln)

- shift.open carries `'shared_shift': true` (:46-47) opting into the staff-shared one-shift-a-day-any-terminal model; legacy builds omit it and keep per-device semantics.
- shift.close uses deterministic `client_event_id: 'shift-close-<uuid>'` (:62) so a lost-response close retries verbatim and gets the STORED reconciliation/Z back. `_ensureProcessed` treats only status `processed` as success — a duplicate of a *failed* close surfaces the stored error (:117-132).
- Both open/close are online-only by design (:19-22). Server-computed Z arrives in close result (`ShiftCloseResult.fromResult`). Mid-shift X-report is device-local fold of the sqflite order log (`foldShiftOrders` :169-209; shift_report_screen.dart renders it and the Z, incl. server `round_up_baisas` display :208-210, 497-499).
- Adoption: `api.fetchCurrentShift({staffId})` probe (pos_api_service.dart:333) lets a second terminal adopt the staff's open shift.

## 6. KOZEN (+ ZCS) hardware bridges (VERIFIED)

- `android/.../MainActivity.kt` (700 ln): MethodChannel `pos_handheld/printer` (:45). Multi-vendor capability probe (`detectCapabilities` :127): KOZEN printer detected via installed pkg `com.pos.service` + reflection on `com.pos.sdk.printer.POIPrinterManager` (:83-86); KOZEN rear customer screen via pkg `com.kozen.component_service` (:88-89, driven through ComponentEngine/ISecondaryScreen, NOT an Android display :146-163); **ZCS/SZZT built-in printer** (G7 / PG3NBG7YA) via bundled `com.zcs.sdk` DriverManager/Printer (:20-25, 91-100). Flutter side keeps `_hasPrinter/_hasCustomerScreen` flags false until probed (main.dart:1035-1041) — plain tablets degrade gracefully.
- `MosambeeBridge.kt` (455 ln) + `lib/services/mosambee_payment_service.dart` (188 ln): channel `com.example.mosambee`, same constants/flow as pos_machine minus the rear-display proxy. `CardCharge` evidence: softpos_reference, auth code, full bank_response map, status success|pending_reconciliation (mosambee_payment_service.dart:95-111).
- `lib/services/kozen_printer_service.dart` (236 ln): fail-safe (returns false, never throws, :145-155); pure `buildReceiptLines` mirrors pos_machine SunmiReceiptService layout — merchant template header (logo/AR name/CR/VAT), items, offer/discount/comp rows, synced tax label, split-tender listing (HH-5), REPRINT banner, plate row, `show_qr`-gated QR payload `MITHQAL|TOTAL=…|STATUS=…` (:161-235).
- Plate capture (handheld-unique): `lib/services/plate_recognizer.dart` — pure Oman-plate heuristics over ML Kit OCR lines (Arabic-Indic digit transliteration, junk-letter filter); `screens/plate_capture_screen.dart` (526 ln) camera capture; plate rides order.create `plate_number` capped 16 chars (order_sync_service.dart:461-466).

## 7. API integration (VERIFIED) — `lib/services/pos_api_service.dart` (473 ln)

Endpoints: activateDevice (:209), staffLogin w/ GPS (:225), fetchConfig/Delta (:244-252), pushSync (:254), listBranchDevices (:272), fetchIncomingTransfers/claimTransfer (:283-308), verifyManagerPin (:310), fetchCurrentShift (:333), nextReceiptNumber (:349), searchCustomers/createCustomer (:359-397, HH-6 loyalty balances), markMessagesRead (:399). Bare-401 → `onUnauthorized` wipe-to-setup (:201). `core/api_config.dart`: 3-tier base URL (dart-define → release `https://posapi.mithqal.net/api/v1` → debug `http://localhost:8088/api/v1`); **only 3 diff lines vs pos_machine's api_config** (near-identical). Transfer inbox: 5 s poll while POS open, suppressed under FLUTTER_TEST (transfer_inbox.dart:26-33); silent-failure keeps last list.
Manager gate: `core/manager_auth.dart` — server-verified PIN via `verifyManagerPin`, fail-closed (callers must not proceed on null).

## 8. Gating parity (VERIFIED) — `lib/models/catalog.dart` (1,363 ln), commit f02d437

Duplicated from pos_machine by hand ("pos_machine parity" comments throughout):
- `Product.isAvailableAt` time windows — one-sided window is BOUNDED not always-open (:731-753).
- `shelfCapReached` — unit/cooked shelf vs cart qty (:775-783).
- `isAddonOptionUnavailable` — PD3b option-stock gating incl. consumption lines; missing product = merchant misconfig, does NOT gate (:790-825).
- `taxTotalFor` — per-tax-line round3 then sum (:646-650); `taxLabelFor` 'VAT (5%)' (:652-664).
- `Offer.appliesAt` time-window/day-mask/branch gating "identical" (:354-355).
- Local shelf decrement via `Product.copyWith` (:754-765).

## 9. Duplication vs pos_machine (file-by-file, VERIFIED via diff)

| Concern | pos_handheld | pos_machine | Divergence |
|---|---|---|---|
| Offer engine | lib/services/offer_engine.dart (442 ln) | lib/services/offer_engine.dart (432 ln) | "ported VERBATIM" (handheld header :3-5); diff = 192 lines, almost all the `OfferLine` adapter class + comments; algorithm same |
| Mosambee | lib/services/mosambee_payment_service.dart (188) | same name (410) | diff 556 ln — machine adds rear-display proxying; constants/flow shared |
| Shift payload | shift_service.dart builders | services/shift_payload.dart | "Shape mirrors pos_machine's shift_payload.dart exactly" (shift_service.dart:26-27) |
| API client | pos_api_service.dart (473) | pos_api_service.dart (616) | diff 1,024 ln — substantially re-written, same endpoints |
| Session | session_service.dart (197) | session_service.dart (265) | diff 424 ln |
| ApiConfig | core/api_config.dart | lib/core/api_config.dart | diff 3 ln — effectively identical |
| Tax calc | catalog.dart taxTotalFor:646 | state/pos_controller.dart taxTotalFor (:1338 uses it) | duplicated formula |
| Gating | catalog.dart :731-825 | config_mapper/pos_models + controller | duplicated (commit f02d437 explicitly a parity port) |
| Receipt layout | kozen_printer_service.dart | sunmi_receipt_service.dart | same layout, different printer API |
| Order events | order_sync_service.dart builders | services/order_sync_payload.dart (582) | parallel builders, same wire shape |
| Outbox parking | stuck/park at 5 rejections (:186-227) | **ABSENT** — `grep stuck\|park\|rejection` in pos_machine/lib/data/order_sync_repository.dart hits only unrelated lines (110 "parked order", 148 lastError) | machine has NO dead-letter parking (asymmetry) |

Not present in handheld (machine-only): round-up donations at payment (`grep donation lib` → only Z-report display), kitchen production, dual-screen customer display (KOZEN rear screen used only for slideshow/test card), i18n/Arabic UI (no lib/l10n), Reverb live sync (60 s poll instead), audience spike, waste screen exists via ops_screens (HH-9), Drift DB.
Handheld-only: plate capture OCR, ZCS printer support, outbox parking, money-outbox Sentry paging.

## 10. Sentry (VERIFIED) — `lib/core/telemetry.dart` (120 ln)

- `_productionDsn = ''` (:30) → Sentry entirely disabled until owner creates project or bakes `--dart-define=SENTRY_DSN`. main.dart:42 `main() => Telemetry.run(_appMain)`.
- Privacy posture: sendDefaultPii false, no screenshots, no print breadcrumbs, no tracing (:51-54); tags limited to device identity kiosk/terminal/company/branch (:63-71), cleared on wipe.
- `scrubServerError` strips Laravel `(Connection:`/`(SQL:` tails and masks quoted literals before leaving the device (:110-119) — tested (test/telemetry_scrub_test.dart, 5 tests).

## 11. CI, release (VERIFIED)

- `.github/workflows/ci.yml`: push-to-main + PR → analyze, `flutter test`, debug APK uploaded as artifact (14-day retention). No auto-deploy; production APKs built locally with dart-defines + signing.
- `android/app/build.gradle.kts`: applicationId `net.mithqal.pos.handheld` (:45); release signing from `android/key.properties` when present else debug keys (:17-74, BOM-strip for Notepad-saved files :20).

## 12. Tests (VERIFIED counts)

175 tests across 16 files: order_sync_payload 36, widget 35, catalog_gating 14, offer_engine 13, catalog_addons_tax 12, hold_void 9, plate_recognizer 8, receipt_template 8, shift_service 8, terminal_pin 7, order_log 6, telemetry_scrub 5, held_order 4, location_service 4, outbox_stuck 3, transfer 3. Order log runs under sqflite_common_ffi in pure Dart (pubspec dev deps).

## 13. Geofence/GPS (VERIFIED) — `lib/services/location_service.dart` (88 ln)

Best-effort fix for order events: fresh high-accuracy (forceLocationManager — no GMS on POS hardware, :66) → last-known → app-cached fix seeded at staff sign-in, refused after `maxCacheAge` 20 min (:23) so a stale replay can't turn server fail-closed into fail-open. No-fix ⇒ omit gps ⇒ server rejects honestly and outbox retries (:19-22). NOTE: unlike pos_machine there is NO GeofenceGate lock screen — the handheld relies on login-time GPS + server-side event-time enforcement (INFERRED from absence of any geofence gate widget in lib/; contract §3 describes machine's gate).

## 14. Findings (details)

**F1 (P1) Hand-maintained duplication of money/gating logic across two codebases.** All pricing-relevant logic (offer engine, tax rounding, discount/comp clamping, gating, receipt totals, sync payload invariants) exists twice, kept in sync only by manually-ported "parity" commits (f02d437) and verbatim copies (offer_engine header). Machine has since evolved (e.g. card-charge reconciliation commits caefd36/5aea76b, round-up cbd4431) with no mechanism to propagate. Concrete drift already exists: round-up donations (machine-only), outbox parking (handheld-only). Risk: the two POS surfaces charge/report differently for the same merchant config.

**F2 (P2) pos_machine outbox has no parked/dead-letter handling (divergence).** Handheld parks after 5 server rejections + pages Sentry + offers manual retry (order_sync_service.dart:186-227); pos_machine/lib/data/order_sync_repository.dart has no stuck/park/rejection mechanism (grep verified) — a permanently-rejected machine batch retries forever silently. (Machine internals are another agent's charter; flagged here as parity asymmetry.)

**F3 (P2) Mock catalog is sellable on an enrolled-but-unsynced device.** `_taxes`/products/categories fall back to hard-coded mocks whenever `_catalog == null` (main.dart:545-569; mock 5% tax :211; mock products with ids 1,2,… :213+). A device that activated but whose first config fetch failed shows the mock menu with fake prices and can complete sales; order.create would carry mock product_ids → server rejection → parked batch, while cash was already taken. The "demo seed" also pre-adds a mock cart line whenever catalog is null (main.dart:1047-1052) — the guard is catalog-null, not test-mode, though the comment claims "a real POS starts empty".

**F4 (P2) Charity round-up absent on handheld payments.** Machine records `donation.record` per rounding card leg (pos_machine commit cbd4431); handheld has zero donation code paths (grep) — only displays server `round_up_baisas` in the Z report. If handhelds take card payments at fenced branches, round-up revenue for charity is silently not offered on that surface.

**F5 (P3) Sentry ships disabled** (`_productionDsn = ''`, telemetry.dart:30) — the outbox-parking page (F2's mitigation) is a no-op until a DSN exists.

**F6 (P3) Outbox durability = one SharedPreferences JSON string** (`order_outbox_v1`), whole-list rewritten per mutation, failures swallowed (order_sync_service.dart:785-795) vs machine's Drift table. Prefs writes are atomic-ish on Android but a large parked backlog makes every sale rewrite the full blob; no per-row corruption isolation (a corrupt JSON list returns [] — :780-782 — silently discarding ALL queued revenue records).

**F7 (P3) Default Mosambee terminal PIN `'1321'`** when server sends none, and a server-sent null CLEARS a cached real pin back to the default (docs/INTEGRATION_CONTRACTS.md:86-88; terminal_pin_test.dart covers it). Behavior is deliberate machine-parity, but a misconfigured device silently falls back to a shared default credential.

**F8 (P3) Git hygiene:** commits "new"×2 (495d532, 9566c8b) and one mega-commit for the entire API+hardware integration — weak audit trail for a payments device.

## Cannot-verify / inferred
- Whether the KOZEN rear customer screen shows live order data during checkout (only slideshow/test-card methods seen in MainActivity.kt:146-231) — INFERRED display-only marketing use.
- Runtime behavior of ZCS printer path on real G7 hardware — code-only review.
- F3's server-side outcome (rejection vs cross-tenant product id acceptance) depends on pos_api validation — not traced here (other agent's charter); marked partially verified.
