# Gap analysis — R4 Order Channels & Fulfilment (12 reqs)

Analyst pass 2026-08-07. Read-only. Sources: map-pos_api.md, map-pos_machine.md, map-pos_merchant.md, audit-sales-flow.md + direct code verification (paths below). [V] = verified in code this pass or by the cited audit file's own code citation.

Overall picture: **the entire [S] Part 3 customer/kitchen channel program (QR ordering, print agent, print-job reliability, KDS, waiter screen, drive-up) is unbuilt** — only deliberate scaffolding exists (per-table `qr_token`, reserved `car` order type, "KDS feed" channel comments). What IS built is the staff-side fulfilment core: dine-in floors/tables with transfer/join, on-device Sunmi printing with failure alerts + reprints, product availability windows (ahead of schedule), and the full manual delivery-provider interim flow. This is consistent with [S] Part 8's build order, which puts money/inventory/compliance items 1–9 ahead of "waiter screen + station routing" (item 10).

## R4.1 QR ordering (S3.1) — MISSING (scaffolding only)

- Exists — per-table QR tokens, clearly built FOR this future feature:
  - Schema: `pos_admin/src/database/migrations/2026_05_27_030100_create_pos_tables_table.php:86` — `qr_token` VARCHAR(64) UNIQUE, comment: "Globally unique across all merchants so a stolen card from one restaurant can't accidentally land on another's **menu**". [V]
  - Mint + roll: `pos_merchant/src/app/Actions/Pos/FloorPlan/CreateTableAction.php:61` (auto-minted on create), `RegenerateTableQrAction.php:45`, route `POST /api/tables/{table:uuid}/regenerate-qr` (`TablesController.php:87-102`). [V]
  - Shipped to devices: `pos_api/src/app/Actions/Device/BuildDeviceConfigAction.php:757` (`tables[].qr_token`). [V per map-pos_api §8]
- Missing: any customer-facing surface. No public menu route, no branch codes, no customer order endpoint, no controller in pos_api (map-pos_api §8 presence check: "QR ordering: ABSENT", verified by full route+controller inventory). No QR-order code in pos_merchant (`grep -rniE 'kds|waiter|print_?agent|print_?job|station'` → only StaffPosition::Waiter enum + comments). [V]
- Status: **MISSING** · Priority **P2**.

## R4.2 Print agent (S3.2) — MISSING

- The persistent server connection the spec wants the agent to ride EXISTS (Reverb: pos_api `DeviceSyncBroadcast` on `private-branch.{id}`; pos_machine hand-rolled Pusher-7 client `lib/services/live_sync.dart`) but carries only config-delta nudges — no print-job event type among the 14 sync handlers, no print push. [V per map-pos_api §3, map-pos_machine §4]
- No print/printer/print-agent code anywhere in pos_api (map-pos_api §8: "Print agent: ABSENT"). No LAN printer or cloud-print client anywhere in pos_machine or pos_handheld (grep `esc_pos|escpos|9100|NetworkPrinter` → zero functional hits both repos). [V]
- Status: **MISSING** · Priority **P2** (prerequisite for R4.1/R4.5 remote channels; no consumer exists today).

## R4.3 Print reliability (S3.3, A§1.2 failover) — PARTIAL

- Exists (device-local resilience, order-money-safety honored):
  - Order is safe regardless of print outcome: outbox row persisted BEFORE print/network (`pos_machine/lib/data/order_sync_repository.dart:25-74`); print failure is non-fatal (`audit-sales-flow §1.2`). [V]
  - Fail-safe printing: `SunmiReceiptService` never throws, returns false (`lib/services/sunmi_receipt_service.dart:11-14,52-58`); Phase G4 failure alerts tell staff "The order is saved — reprint it from History" (`lib/l10n/l10n_en.dart:2769-2776`, kitchen + shift variants). [V]
  - Reprints: receipt from History, kitchen ticket manager-gated (`posKitchenReprint*` l10n, `pos_controller.dart:2274`), Z-report reprint. [V]
- Missing: print job as a first-class server entity (no `print_jobs` table in the 153 pos_admin migrations, no status pending→printed, no printer confirmation), no 10–15s unprinted flag, no managed queue with 3 retries (each print is one-shot), no printer-status banner, and the heartbeat carries NO printer status — `pos_api/src/app/Http/Controllers/Api/V1/Device/HeartbeatController.php:27-32` accepts only lat/lng/battery/app_version [V]; pos_machine never even calls /device/heartbeat (grep `heartbeat` in lib → one UI comment at `staff_pos_screen.dart:13599`; the online dot reads `last_seen_at` from GET /device/branch-devices, `pos_api_service.dart:225-229`). [V]
- Status: **PARTIAL** · Priority **P2**.

## R4.4 Printer hardware (S3.4: ESC/POS, network LAN, thermal counter + impact kitchen) — PARTIAL

- Exists: thermal counter printing on integrated device printers — Sunmi built-in via `sunmi_printer_plus ^4.1.1` (`pos_machine/pubspec.yaml:38`, `lib/services/sunmi_receipt_service.dart`); handheld KOZEN POIPrinterManager (reflection) + bundled ZCS/SZZT SDKs (`pos_handheld` MainActivity.kt:83-100). [V per maps]
- Missing: LAN/network printer support of any kind (no esc_pos lib, no port-9100 socket, greps above), no impact printer path — kitchen tickets print on the SAME counter thermal printer (`pos_controller.dart:3218-3225`), exactly what S3.4 says to avoid for hot kitchens.
- Status: **PARTIAL** (counter goal met on different — integrated — hardware; LAN + impact absent) · Priority **P3** (follows print agent; hardware procurement decision).

## R4.5 KDS (S3.5) — MISSING (anticipated in comments only)

- Presence check (map-pos_api §8, re-verified): no KDS routes/controllers/pages anywhere. pos_api `GET /device/kitchen` + productions endpoints are P-G1 **batch production** (start/finish/cancel/disposition), not a display station. [V]
- Anticipation artifacts: `pos_api/src/routes/channels.php:24` calls `branch.{id}` "the main POS / handheld / KDS feed"; `pos_merchant/src/app/Models/Order.php:189` orders items by id "so receipts + KDS render in the same order". Merchant "kitchen positions" setting is staff-access gating, not routing (`Settings/OrderCancellation.vue` hub). [V]
- Paper half of "paper+screen simultaneously" exists: kitchen tickets (Phase C1, toggleable, `pos_controller.dart:582,3218-3225`). No stations, no per-category routing, no split-with-parent-link, no all-stations-done completion. `STATUS_KITCHEN` exists in Order.php:31 but no handler ever writes it (audit-sales-flow F10). [V]
- Status: **MISSING** · Priority **P2** (station routing is [S] Part 8 build-order item 10).

## R4.6 Waiter/pass screen (S3.6, S6.7) — MISSING

- grep waiter in pos_merchant/pos_api → only `StaffPosition::Waiter` enum case (`pos_merchant/src/app/Enums/StaffPosition.php:19`) and OrderSource docblock. No pass-screen surface, route, or page anywhere (map-pos_api §8; map-pos_merchant page inventory). [V]
- Status: **MISSING** · Priority **P2** ([S] Part 8 item 10 pairs it with station routing).

## R4.7 Drive-up arrive-then-order (S3.7) — MISSING (staff-side primitives only)

- Exists (interim, staff-operated):
  - Plate on orders: `pos_machine/lib/services/order_sync_payload.dart:96-116,278` sends `plate_number`; server persists it (`pos_api CreateOrderHandler.php:107`); customer lookup by plate (P-F2 `platesJson`, handheld plate OCR). [V]
  - Reserved vocabulary: `'car'` ∈ `Order::TYPES` (`pos_api/src/app/Models/Order.php:46`) — but NEITHER device ever emits it (machine maps to quick, `order_sync_payload.dart:27-39`; handheld enum has no car — audit-sales-flow F10). [V]
  - Held orders could park unpaid orders, but that is a generic staff feature.
- Missing: branch-QR customer arrival flow, soft geofence on arrival, optional free-text car description, paid-fires-immediately vs unpaid-held-until-deliberate-release semantics, unpaid-fired flag. All depend on the absent customer QR channel (R4.1).
- Status: **MISSING** · Priority **P2** (part of the R4.1 channel program).

## R4.8 Order-ahead DEFERRED (S3.7, S6.8) — FULL (correctly absent)

- Requirement is that it NOT be built yet. Verified absent: `grep -rniE 'order[_-]?ahead|scheduled_(at|for)|pickup_time|preorder'` across pos_api + pos_merchant app code → zero hits. No future-dated order support in CreateOrderHandler. [V]
- Status: **FULL** (compliance by absence) · Priority **P3** (none).

## R4.9 Dine-in table service (B5.3.2, B6.5, A§1.3) — PARTIAL (strong)

- Exists:
  - Schema: `pos_floors` + `pos_tables` (`pos_admin` 2026_05_27_030000/030100) with label/seats/min-max party/shape/status(config)/display_order/qr_token, per-floor label uniqueness. [V]
  - Merchant: FloorPlanner + floors CRUD + saveLayout + tables CRUD (`pos_merchant/src/routes/web.php:264-285`); Tables/Show per-table insights. [V]
  - Device: Floors/PosTables cache with layout px (`pos_machine/lib/data/db/tables.dart:84-114`); table sessions with statuses `{available, occupied, paid}` (`lib/models/pos_models.dart:7`); joined tables persisted server-side (`pos_order_tables`, CreateOrderHandler `writeJoinedTables` :238-265). [V]
  - Transfer + merge (spec'd Ph7+, DELIVERED): `transferDiningTable` (`pos_controller.dart:2091-2136`, crash-safe save-before-delete) + join-free-table into one party (:2138+); G2 tests exist. [V]
  - Turn-time: TableInsightsAction computes per-table sit count, avg/total duration (opened_at→closed_at), busiest hour/weekday (scratchpad copy :27,:294-313). Analytics, not live flags — the Ph7+ ask was flags. [V]
- Gaps: table occupancy is DEVICE-LOCAL — server has no occupancy state (derived from active orders; audit-sales-flow §118) and machine pushes order.create only at completion, so another terminal cannot see a table's live open cart (double-seat risk in multi-terminal dine-in); no `reserved` status (reservations deferred per R12, consistent); merge deliberately does not combine two existing orders (one-bill join only); turn-time is retrospective analytics, no live flag.
- Status: **PARTIAL** · Priority **P3** (raise to P2 if multi-terminal dine-in branches are in pilot scope).

## R4.10 Kitchen queue priority (A§1.3, Ph7+) — MISSING (acceptably deferred)

- grep `priority|vip|allergy` in pos_machine/lib → zero; grep `priority` in pos_api + pos_merchant app code → zero. No queue to prioritize exists anyway (no KDS). [V]
- Status: **MISSING** (deferred scope, consistent with Ph7+) · Priority **P3**.

## R4.11 Menu time-windows (A§1.3, S7.4 — Ph7+) — FULL (delivered ahead of schedule, product-level)

- Schema: `pos_admin/src/database/migrations/2026_07_07_010000_add_availability_window_to_pos_products.php:44-45` — `available_from/available_until` VARCHAR(8), overnight wrap documented. [V]
- Merchant CRUD: `CreateProductAction.php:92`, `UpdateProductAction.php:59` (+ available-hours UI, commit f30c388). [V]
- Device config ships it: `pos_api BuildDeviceConfigAction.php` (`available_until` emit verified by grep). [V]
- Enforcement on BOTH devices: machine `Product.isAvailableAt` (`pos_models.dart:487-506`, inclusive bounds, midnight wrap, clone of discount time-match) gated at tile + add-to-cart (`pos_controller.dart:926-929`); handheld parity `main.dart:689` + `catalog.dart:738-767`. Machine has availability tests (test/ list). [V]
- Nuance: product-level daily windows only; category/menu-level scheduling remains deferred (S7.4, listed in R12) — consistent.
- Status: **FULL** · Priority **P3** (none).

## R4.12 Delivery platform integrations (A§1.3 — post-pilot; manual interim) — FULL (interim as specced)

- Manual-entry interim pipeline is complete end-to-end:
  - Provider registry: `DeliveryProvider` model (docblock names Hungerstation/Toyou/in-house), CRUD routes `pos_merchant web.php:903-909`; per-product per-provider prices (`ProductDeliveryPrice`, machine `deliveryPricesJson` resolution `tables.dart:63-67`). [V]
  - Device flow (P-G7): provider frozen at punch, reference required, tax/discount/offer/comp/loyalty/round-up all gated off (`pos_controller.dart:2684-2743`, `_isTaxExempt` :1338); emits `order.deliver` instead of order.pay (`order_sync_payload.dart:344-374`). [V]
  - Server: `DeliverOrderHandler.php:51-137` — pending_verification, freezes provider name + commission% + expected payout, inventory consumed at punch. [V]
  - Merchant settlement: Deliveries index/confirm/adjust (`web.php:451-456`), `ConfirmDeliveryOrdersAction` flips to paid with received/variance + delivery commission. [V]
- No Talabat/UberEats API integration — correct, post-pilot by requirement.
- Caveats owned by other domains: no provider-management UI discovered (map-pos_merchant P3); order.deliver lacks in-txn lock (audit-sales-flow F3, P2); confirmation re-dates opened_at (design decision).
- Status: **FULL** · Priority **P3**.

## Summary table

| ID | Status | Priority | One-liner |
|---|---|---|---|
| R4.1 | MISSING | P2 | qr_token scaffolding only; no customer surface |
| R4.2 | MISSING | P2 | Reverb pipe exists, no print-job push/LAN output |
| R4.3 | PARTIAL | P2 | fail-safe print + alerts + reprints; no job entity/queue/retries/heartbeat-printer-status |
| R4.4 | PARTIAL | P3 | integrated Sunmi/KOZEN thermal only; no LAN ESC/POS, no impact |
| R4.5 | MISSING | P2 | kitchen endpoints = batch production; paper tickets only |
| R4.6 | MISSING | P2 | only a Waiter staff-position enum |
| R4.7 | MISSING | P2 | plate primitives + reserved 'car' type; no arrive-then-order |
| R4.8 | FULL | P3 | correctly deferred (verified absent) |
| R4.9 | PARTIAL | P3 | floors/tables/transfer/join/turn-time analytics; occupancy device-local, no reserved, no live flags |
| R4.10 | MISSING | P3 | deferred as planned |
| R4.11 | FULL | P3 | product-level windows shipped ahead of schedule, both devices |
| R4.12 | FULL | P3 | manual interim complete; APIs correctly post-pilot |
