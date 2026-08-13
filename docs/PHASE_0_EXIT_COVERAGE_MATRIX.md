# MITHQAL 2.0 — Phase 0 Exit Coverage Matrix

- **Prepared:** 2026-08-13 (Asia/Muscat)
- **Prepared by:** Independent Phase 0 testing agent (T0 read-only inventory deliverable)
- **Authority:** `MITHQAL_2.0_FULL_TESTING_AI_HANDOFF.md` §8 T0; sources listed below
- **Scope:** Maps all ten Phase 0 items to their owning regressions, and `EXIT-01`…`EXIT-16` to existing coverage and missing test-only work. No production code was read for modification; no test was executed for this document.

## 1. Sources and tested state

Documents read in the required order: `MITHQAL_2.0_PHASE_0_HANDOFF.md` (2026-08-11), `MITHQAL_2.0_START_HERE.md`, `MITHQAL_2.0_ARCHITECTURE.md`, `MITHQAL_2.0_SYSTEM_AUDIT.md` (2026-08-07) + `docs/audit-evidence/` (22 files), `pos_api/docs/runbooks/stranded-sync-event-sweeper-cutover.md` (understanding only), `sunmi-support-customer-display-touch.md`. Stale progress counters in START_HERE/ARCHITECTURE ("3 of 10") are confirmed stale by the Phase 0 handoff itself; all ten items are locally committed.

Repository state at inventory (all verified, none assumed):

| Repository | Root | HEAD | Dirty state |
|---|---|---|---|
| pos_machine | `C:\src\projects\pos_machine` | `c0fff6a` (testing-handoff doc commit after `4b81272`/`2b480d6`) | modified submodule `.codex_inspect/SunmiFingerprintDemo`; untracked `.agents/`, `skills-lock.json` (preserve) |
| pos_handheld | `C:\src\projects\pos_handheld` | `52678b2` | clean |
| pos_api | WSL `~/projects/my-projects/pos/pos_api` | `07f92c4` | clean |
| pos_admin | WSL `~/projects/my-projects/pos/pos_admin` | `972a1a1` | clean |
| pos_merchant | WSL `~/projects/my-projects/pos/pos_merchant` | `c3b0cdf` | clean |
| charity receiver | WSL `~/projects/my-projects/charity/charity-laravel-api` | `c7481ea` | unrelated in-progress RemoteSession/TURN work (preserve; awaiting owner confirmation) |

Runtimes recorded: Flutter **3.44.9** stable / Dart 3.12.2 (machine CI pins **3.44.0** — mismatch recorded per §10; interpret any machine-only difference against this), Java 1.8.0_501, Docker 29.7.2 / Compose v5.3.1 (WSL). `adb` sees the G7 handheld (USB) and a Sunmi T3 (wireless).

## 2. Coverage legend

| Class | Meaning |
|---|---|
| `COVERED` | An existing regression proves the obligation at its layer |
| `PARTIAL` | A fragment is proven; the named gap remains |
| `MISSING` | No coverage; new test-only work required (authorized paths only) |
| `HARNESS` | Provable only in the integrated disposable PostgreSQL/Redis harness (T4/T5) — SQLite `:memory:`/sync-queue baselines structurally cannot prove it |

Work items for T2 are labelled `W-M*` (pos_machine `test/phase0_exit/`), `W-H*` (pos_handheld `test/phase0_exit/`), `W-A*` (pos_api `tests/Feature/Phase0Exit/`), `W-D*` (pos_admin `tests/Feature/Admin/Phase0Exit/`), `W-C*` (charity receiver `tests/Feature/`, idempotency contract only), `W-X*` (integrated orchestrator `tool/phase0_exit*`).

## 3. Part A — Ten Phase 0 items → owning regressions

All named files verified present on disk at the SHAs above.

| # | Item | Owning regressions (repo: file) | Coverage at its layer |
|---|---|---|---|
| 1 | **HH-001** handheld outbox concurrency | handheld: `outbox_race_test.dart`, `outbox_stuck_test.dart` | `COVERED` — deterministic Completer barriers, no sleeps; mid-flush enqueue, dual enqueue, init-merge, corrupt-store quarantine, batchKey identity |
| 2 | **HH-002** card force-record classification (both devices) | handheld: `mosambee_classification_test.dart`; machine: `card_charge_classification_test.dart` | `COVERED` — neverReachedTerminal vs isUncertain split on both devices, incl. producer-side payloads and preflight; machine prompt-escalation in `pos_controller_charity_flow_test.dart` (CI-excluded — see §6) |
| 3 | **MC-001** machine parking/operator surface | machine: `order_sync_parking_regression_test.dart`, `stuck_sales_surface_test.dart` | `COVERED` — 5-rejection park, transport-vs-rejection split, stuck tile + manual retry (park state seeded, not derived end-to-end) |
| 4 | **MC-002** geofence re-enrichment | machine: `order_sync_geofence_reenrichment_test.dart` | `COVERED` — fresh-fix patch of both payloads, identity preserved across retries, GPS-hold isolation, no-overwrite |
| 5 | **MC-003** cross-staff/shared-shift (machine + API) | machine: `shift_reconciliation_test.dart`, `widget_test.dart` (CI-excluded — see §6); API: `DeviceSyncShiftTest.php`, `DeviceCurrentShiftTest.php` | `COVERED` — probe/adopt/handover on machine; shared-vs-legacy semantics, disjoint closes, strict probe on API. The two tests the audit said "pin old behavior" have been deliberately updated |
| 6 | **API-001** loyalty clamp/review/replay/void restoration | API: `DeviceSyncLoyaltyTest.php`, `DeviceSyncOrderTest.php`; admin: `LoyaltyShortfallReviewSchemaTest.php`; merchant: `LoyaltyShortfallReviewTest.php` | `COVERED` at API layer — clamp settles sale, immutable zero-delta ADJUST marker, stored-ACK replay, frozen-payload heal, void restores applied-only. Locked-balance concurrency is `HARNESS` (see EXIT-04) |
| 7 | **API-002** atomic dispatch/recovery/floor quarantine/schedule gate | API: `DeviceSyncStrandedEventTest.php`, `DeviceSyncDonationTest.php`, `DeviceSyncExpenseRestockTest.php`, `DeviceSyncSliderTest.php`, `DeviceSyncSliderBillingIntegrityTest.php` | `COVERED` at API layer — one-commit effect+ACK, stale-candidate recheck, lock serialization (array cache), floor fail-closed, sweep eligibility matrix, schedule/compose text pins. Real worker kill + Redis lock contention are `HARNESS` (EXIT-09) |
| 8 | **API-003** cash/change accounting | API: `DeviceSyncShiftTest.php` (change_given excluded from expected cash and Z), `DeviceSyncOrderTest.php`, `DeviceSyncCommissionTest.php` | `COVERED` — incl. the contract case the audit demanded (cash with `change_given_baisas > 0`) |
| 9 | **ADM-001** terminal void/deferred effects | admin: `PendingReconciliationTest.php`, `ForwardCharityDonationActionTest.php` | `COVERED` sequentially — void terminal/non-actionable on approve+reject+forward, atomic paths, commit-before-HTTP. Mid-flight void races are `MISSING`/`HARNESS` (EXIT-11) |
| 10 | **ADM-003→ADM-002** retry eligibility, then scheduling/workers | admin: `RetryRoundupForwardingTest.php`, `SchedulerTest.php`, `RoundupDonationTableTest.php`, `ScanExpiringCompanyDocumentsJobTest.php`; merchant: `RoundupDonationSchemaTest.php` | `COVERED` — full eligibility matrix incl. void-race revalidation under order lock; cron/overlap/one-server/worker pins (requires `docker-compose.prod.yml` mounted above `src/` — see §6) |

**Regression-pack note (mandatory):** a green integrated scenario never permits skipping this pack; the pack must run explicitly, including HH-002 on both devices, API-003 and MC-003 (Phase 0 handoff §11.2).

## 4. Part B — EXIT-01…EXIT-16 coverage and gaps

### EXIT-01 — Machine backlog + concurrent enqueue while flushing

- Existing: `MISSING` on the machine. Every existing `flush()` test is sequential; nothing enqueues while a flush awaits its HTTP response. (Machine's Drift outbox lacks the handheld's read-modify-write hazard, but the interleaving invariant is unproven.)
- **W-M1**: driver blocking a flush on a completer-controlled fake adapter, enqueue N sales mid-flight, release; assert every row drains-with-ACK or stays pending; no loss, no duplicate send.
- **W-X**: re-run within integrated harness against real API.

### EXIT-02 — Handheld backlog + concurrent enqueue race

- Existing: `COVERED` at unit layer (`outbox_race_test.dart` — the strongest file in either device repo; barrier-driven, no sleeps).
- **W-H1**: thin integrated driver re-proving it inside the exit gate (reuse the existing harness pattern: process-global `orderSync` + `resetForTest()`, injected pusher, Completer barriers).

### EXIT-03 — Response-loss replay; stored ACK; no duplicate effects

- Existing: `PARTIAL`. API: replay dedupe, stored-ACK, failed re-dispatch, per-device idempotency scope all proven single-connection. Machine: client_event_id stability across retries proven; **no test ever receives `duplicate:true`/stored-ACK** — repository behavior on "response lost after server processed" is unexercised. Handheld: batchKey identity proven; same replay gap.
- **W-M2**: machine driver — adapter processes batch, throws on response leg once, answers processed/duplicate on replay; assert exactly-once local settlement.
- **W-H2**: handheld equivalent (same client_event_ids re-sent, drains once on duplicate ACK).
- **W-X (HARNESS)**: two real PG connections racing identical pushes; prove `(device_id, client_event_id)` unique index + savepoint recovery from a real 23505 yields one effect set; replay arriving while first attempt's transaction is still open.

### EXIT-04 — Loyalty exceeds locked balance: clamp, review, idempotent evidence

- Existing: `PARTIAL`. API layer essentially complete (`DeviceSyncLoyaltyTest`): clamp settles everything, exact shortfall marker, replay = stored-ACK zero rows, void restores applied-only, frozen-payload heal. Merchant review surface covered. Devices: only request-shape pinned; **no device test handles a processed-with-clamp ACK** (does it mark synced or count a rejection?).
- **W-M3 / W-H3**: device drivers with adapter returning processed-with-clamp result payloads; assert batch drains once, no park, no re-debit on replay.
- **W-A1**: sweep-path recovery of a stranded (`received`) order.pay carrying loyalty_redeem — heal via `sync:sweep-stranded-events`, currently only push-path tested.
- **W-X (HARNESS)**: two concurrent pays redeeming from one account on PG — proves the `lockForUpdate` clamp actually serializes (SQLite ignores FOR UPDATE; a wrong lock pattern would double-spend points and no current test would fail).

### EXIT-05 — Customer deleted before replay: park visibly, never falsely processed

- Existing: `PARTIAL` devices / `MISSING` API. Devices: generic deterministic-rejection→park mechanism covered (machine surface test seeds the parked state; handheld pure-function). **API: entirely uncovered** — no test deletes the customer between create and queued pay/loyalty replay, on either the push or sweep path.
- **W-A2**: push path — pay referencing deleted customer fails visibly with an exact parkable error (never NULL-customer processes, never discards); sweep path — stranded event whose customer vanished lands `failed` with error in result_json; donation.record variant.
- **W-M4 / W-H4**: end-to-end device drivers deriving the park from an actual customer-deleted rejection (not seeded), asserting the exact server error text surfaces for manual action.

### EXIT-06 — Fenced queued order gets fresh GPS fix: re-enrich, process once

- Existing: `COVERED` on machine (`order_sync_geofence_reenrichment_test.dart` — enrichment per-attempt, identity per-event). Handheld: by design **no re-enrichment path exists** — not an EXIT-06 surface (see EXIT-07).
- **W-X**: integrated confirmation that the enriched replay is accepted by the real API exactly once.

### EXIT-07 — No valid GPS fix: durable and visible, never silently lost

- Existing: `PARTIAL`, with a **product-behavior question flagged**. Machine: durability proven (GPS-held batch stays pending, attempts=0, others proceed) but **nothing asserts a GPS-held batch is operator-visible** — the stuck tile keys off the 5-rejection cap and a GPS hold never increments rejections, so a permanently unfixable fenced batch may be durable yet invisible. Handheld: payloads frozen at enqueue, gps omitted → server rejects → park **is** the supported outcome (per-client difference sanctioned by the architecture); end-to-end driver missing. Location degrade chain covered (`location_service_test.dart`).
- **W-M5**: machine visibility driver — assert the held batch surfaces to the operator, or record the outcome as a candidate `FAIL-PRODUCT`/owner clarification (visibility definition) — do **not** weaken the assertion to match current behavior.
- **W-H5**: handheld no-fix fenced sale driver — enqueue gps-omitted, deterministic fenced rejection, assert park-at-cap durable + visible.

### EXIT-08 — Shift closes with sales queued: sales survive

- Existing: `MISSING` everywhere at the interaction level. Machine widget tests close shifts only on a fake storage with an empty outbox; handheld shift tests stop at builders/parsers; **no API test delivers an order.pay into a shift whose close already processed**.
- Scope carve-out (authoritative): assert durability + processed-or-visible only; do **not** assert final Z/EOD attribution (orders lack shift_id until DB-001; temporal attribution stands).
- **W-M6 / W-H6**: device drivers — enqueue sale batches, close shift, assert rows survive and later flush processes (or parks visibly).
- **W-A3**: API driver — pay whose paid_at falls inside a closed shift's window arriving after close: pin the supported outcome (re-attributed, flagged actionable, or visible somewhere — never silently absent from everything).

### EXIT-09 — Worker dies after ingest: eligible event recovers exactly once

- Existing: `COVERED` as simulation (`DeviceSyncStrandedEventTest` — eligibility matrix, floor fail-closed, lock-skip-then-process, unsafe-device skips; billing-time variant in slider tests). Triple qualifier confirmed by runbook: registered handler + id strictly above floor + `server_received_at` ≥ 10 min (server time, never device time). Manual invocation works with sweep disabled (flag gates only the schedule).
- **W-X (HARNESS)**: real worker killed between handler work and ACK on PG (proves the one-commit claim physically); two concurrent sweepers on separate processes contending via real Redis `Cache::lock`; recovered event settles exactly once; `schedule:work` actually invoking the sweeper in a container.

### EXIT-10 — At/below-floor rows stay quarantined forever

- Existing: `COVERED` for the quarantine logic (strict inequality: `id > floor` processes, `id == floor` quarantines; floor never auto-derived). **Gap: operator visibility of quarantined rows is asserted nowhere** — they sit `received` forever, indistinguishable from fresh strandings except by id.
- **W-A4**: visibility assertion (admin surface/metric/alert) — or record the absence as a documented owner-decision item; never silently accept invisibility as a pass.
- **W-X**: harness boots with real env and confirms the sweep honors the configured floor and the `onOneServer` mutex engages on real Redis.

### EXIT-11 — Reconciliation approval races void: void terminal

- Existing: `PARTIAL`. Sequential terminality thoroughly covered (admin `PendingReconciliationTest`: approve/reject/forward all no-op on void; API `DeviceSyncDonationTest`: approval-at-transaction-boundary observed by locked snapshot; void-races-retry revalidation under order lock proven for the **sweep** only).
- **W-D1**: mid-flight void race against `ApprovePendingReconciliationAction` **and** `ReconcilePaymentsAction` using the same model-event technique the sweep test uses (void after candidate select, before tender flip): zero commissions, zero forwards, no audit.
- **W-D2**: bank-file path void-**order** guard — commit a payment whose parent order is void; assert no commission minted, no forward (currently unpinned; donation-status-only coverage exists).
- **W-X (HARNESS)**: two concurrent approvals in parallel transactions; device-originated void via pos_api racing an in-flight admin approval on one shared PG.

### EXIT-12 — Charity forward fails after settlement: stable-UUID retry → one receiver set

- Existing: `COVERED` better than expected. Local half strong (commit-before-HTTP with listener proof; forwarded_at NULL retry; stable `pos_reference` = donation uuid; snapshot-only payload). **Receiver contract test already exists**: charity `CharityPosRoundupTest.php` — same `pos_reference` posted twice yields exactly one `charity_transactions` row (`pos_roundup:<uuid>`, partial unique index) + 2xx replay.
- **W-C1** (optional strengthening, authorized path): replay **with** a commission profile asserting the share set stays at the original count; the concurrent-race path (unique-violation → 200 idempotent) currently untested.
- **W-D3**: pos_admin timeout/`ConnectionException` ambiguity (receiver may have committed before response loss): forwarded_at stays NULL, retry same uuid, no local rollback. And: 2xx-with-`success:false` must NOT stamp forwarded_at (currently unpinned — a receiver validation failure could silently mark a donation forwarded and lose it).
- **W-X**: integrated pos_admin → charity receiver against one disposable DB proving the full retry loop end-to-end.

### EXIT-13 — Transport failures: retry continues, rejection counter unchanged

- Existing: `COVERED` machine (7 transport failures = 7 requests, rejections stay 0); handheld mechanism covered but single-pass only. Server complement covered (failed re-dispatch under lock).
- **W-H7**: N consecutive flushes against a throwing pusher — attempts grow, rejections stay 0, never parks, pendingCount holds.

### EXIT-14 — Five deterministic rejections: park at cap, visible, auto-retry stops

- Existing: `COVERED` machine (five rejections park; sixth flush sends nothing; retryStuck drains). Handheld: cap proven at pure-function level + pre-seeded stuck row only.
- **W-H8**: five real `flush()` passes against a deterministically-rejecting pusher — parks exactly on the fifth, `stuckCount` flips, sixth flush never invokes the pusher for it.

### EXIT-15 — Tenant-scoped client-ID collision

- Existing: `PARTIAL`. Cross-company client_event_id reuse (no dedupe leak), cross-tenant refs (product/addon/customer/table/staff), cross-tenant rule/ingredient/order refs all covered.
- **W-A5**: same-company/different-device reuse of one client_event_id → two independent ledger rows (unpinned); cross-tenant **order-UUID** collision at order.create (CreateOrderHandler locks by uuid globally — colliding foreign uuid must be rejected, not adopted; no test pins this).
- **W-X (HARNESS)**: collision under true concurrency (two devices, two connections, same second).

### EXIT-16 — Machine + handheld concurrent same-branch streams at a barrier

- Existing: `MISSING` everywhere; in-repo tests structurally cannot prove it. Client-side contributions exist (money invariants, idempotent ids, race-safe outboxes).
- **W-X (HARNESS)** — the core integrated scenario: fixtures with two devices, fenced branch, two staff, shared shift, product/stock, customer, loyalty rule/balance, pending payment; both device payload builders (real builders where practical) submitting through parallel connections against one disposable PG at an explicit barrier; assert no loss, no duplicate effects, no stock overdraw, no staff/tenant leakage. Known residual documented honestly: offline sale syncing after a stock count still double-counts (INV-002, out of Phase 0 scope).

## 5. Part C — Consolidated T2 build list

**New test files (authorized paths only):**

| Repo / path | Work items |
|---|---|
| `pos_machine/test/phase0_exit/` | W-M1 enqueue-during-flush, W-M2 duplicate-ACK replay, W-M3 clamp-ACK handling, W-M4 customer-deleted end-to-end, W-M5 GPS-held visibility, W-M6 shift-close-with-backlog |
| `pos_handheld/test/phase0_exit/` | W-H1 integrated race re-proof, W-H2 response-loss replay, W-H3 clamp-ACK, W-H4 customer-deleted park, W-H5 no-fix fenced park, W-H6 shift-close-with-backlog, W-H7 multi-pass transport, W-H8 five-real-flush park |
| `pos_api/src/tests/Feature/Phase0Exit/` | W-A1 stranded loyalty-pay sweep heal, W-A2 deleted-customer push+sweep+donation, W-A3 pay-after-shift-close, W-A4 quarantine visibility, W-A5 same-tenant id reuse + cross-tenant order-uuid |
| `pos_admin/src/tests/Feature/Admin/Phase0Exit/` | W-D1 mid-flight void vs approval/bank actions, W-D2 bank-file void-order guard, W-D3 timeout ambiguity + 2xx-success:false |
| `charity .../src/tests/Feature/` | W-C1 replay-with-shares + race-path (idempotency contract only) |

**Integrated harness (`pos_machine/tool/phase0_exit.ps1` + manifest + helpers):** disposable PG + Redis compose (test-only), allowlist/denylist preflight (abort unless `APP_ENV=testing` + owner-approved targets; `charity_db` unconditionally denylisted), deterministic fixtures + stable UUIDs + frozen clocks + explicit barriers, both device payload builders as scenario drivers, real-worker-kill and dual-sweeper machinery (EXIT-09), two-connection race drivers (EXIT-03/04/11/15/16), effect-count collector (orders/payments, stock, loyalty, commission, donations, stranded rows, duplicates), sanitized Markdown/JSON/JUnit artifacts under `build/phase0_exit/<run-id>/`, run-all-even-on-failure, run-twice comparison.

**Environment-imposed harness requirements:** parameterized repo roots; admin container must mount repo-root `docker-compose.prod.yml` above `src/` (SchedulerTest hard requirement) plus `.env.example`/`.env.production.example`; charity tests run inside their container; PHP suites only in the PHP 8.4 containers via `wsl -e bash -lc` (host PHP 8.2 insufficient); Windows tooling for Flutter repos, WSL tooling for Laravel repos.

## 6. Part D — Known exclusions, debt and boundary facts to baseline in T1

1. **Machine CI subset** excludes `widget_test.dart` (missing ProviderScope harness) and `pos_controller_charity_flow_test.dart` (stale 5%-tax expectations). T1 must capture both exact current signatures; a *different* failure in those files is never "inherited".
2. **Admin PHPStan**: 566 inherited Eloquent/model-annotation diagnostics; compare normalized diagnostic sets, not the count; any new diagnostic fails T6.
3. **SQLite `:memory:` boundary** (pos_api `phpunit.xml`: sqlite + sync queue + array cache + null broadcast; same class of config in admin/merchant/charity): cannot prove PG `FOR UPDATE` serialization, Redis dispatch-lock cross-process exclusion/TTL, real worker interruption, scheduler mutexes, PG 23505 savepoint recovery, or timestamptz/DATE semantics. Green Composer baselines ≠ green exit gate.
4. **Flutter version**: local 3.44.9 vs machine CI pin 3.44.0 (mismatch recorded; decide per-difference whether to reproduce under 3.44.0).
5. **Two historically behavior-pinning tests already deliberately updated** (verify at T1, do not re-flag): `DeviceCurrentShiftTest` now covers the strict probe; `DeviceSyncLoyaltyTest` now covers the clamp.
6. **Sunmi NP521/T3 PRO touch routing**: customer-panel taps land on operator display 0 (fw 1.3.6 / usbscreen 2.5.4 / SUNMI OS Android 13). Physical smoke must prove display-only rendering and that deliberate customer-panel taps change nothing on either screen; the touch interaction itself is never marked passed.
7. **Charity repo dirty state**: unrelated RemoteSession/TURN in-progress work; if its suite misbehaves for that reason, classify as environment state, not Phase 0 product failure.
8. **Sweeper runbook**: `SYNC_STRANDED_SWEEP_ENABLED` gates only the schedule (manual run works with a valid floor — this is what the disposable-env tests exploit); floor is captured once from the sequence high-water mark, never derived, never 0, never raised/lowered; live cutover is never performed by this assignment.

## 7. Flagged scenario risks (candidate findings, to be proven not assumed)

| Flag | Scenario | Risk |
|---|---|---|
| F-1 | EXIT-07 (machine) | GPS-held batch may be durable but operator-invisible (stuck tile keys off rejection cap; GPS holds never increment it). If confirmed, this is a `FAIL-PRODUCT` candidate against "never silently lost", or an owner clarification of "visible". |
| F-2 | EXIT-10 | Quarantined rows have no asserted operator surface anywhere. Same treatment as F-1. |
| F-3 | EXIT-08 (API) | Pay landing after its covering shift closed is completely unpinned server-side — outcome unknown. |
| F-4 | EXIT-11 | Bank-file commit path has no void-*order* guard test; if the guard is absent in code, a bank file listing a voided order's tender would mint commission. |
| F-5 | EXIT-12 | 2xx-with-`success:false` from the receiver may be stamped as forwarded (unpinned) — silent donation loss. |
| F-6 | EXIT-04/15/16 | All locking claims rest on PG `FOR UPDATE` semantics no current test executes. |

These flags are hypotheses from coverage analysis. Each is resolved only by running the corresponding test; none may be reported as a defect without a failing reproduction, and none may be quietly "fixed" by weakening an assertion.
