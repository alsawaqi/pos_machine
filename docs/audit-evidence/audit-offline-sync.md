# MITHQAL 2.0 Audit — Offline-First & Sync (audit-offline-sync)

Auditor charter: OrderOutbox (machine), client_event_id stability, batch semantics, mid-queue
delete fix (bf0bf72), catalog sync, Reverb, clock skew, numbering, replay duplicate prevention,
handheld money-outbox parking (c5857d6), held orders / transfer / shared shifts cross-device.
All claims below are VERIFIED against code unless marked INFERRED / Cannot-Verify.

Repos referenced:
- pos_machine = C:\src\projects\pos_machine
- pos_handheld = C:\src\projects\pos_handheld
- pos_api = \\wsl\...\pos\pos_api (Laravel, code under src/)
- charity = \\wsl\...\charity\charity-laravel-api

---

## 1. Server ingestion pipeline (pos_api) — the idempotency backbone

### 1.1 Endpoint + batch contract
- `POST /api/v1/device/sync/push` → `SyncPushController` (pos_api/src/app/Http/Controllers/Api/V1/Device/SyncPushController.php:27-46). Unassigned device → 409.
- **Batch max 50 enforced**: `SyncPushRequest` rules `'events' => ['required','array','min:1','max:50']` (pos_api/src/app/Http/Requests/Api/V1/Device/SyncPushRequest.php:36-42). In-batch repeats of the same client_event_id are deliberately NOT rejected by the validator — they settle as duplicates in the ledger (file doc block lines 14-18).
- `client_timestamp` has **deliberately no recency bound** ("may be hours stale — the 4-hour-late replay case", SyncPushRequest.php:20-23).

### 1.2 Idempotency (IngestSyncEventsAction)
pos_api/src/app/Actions/Device/IngestSyncEventsAction.php:
- Exactly-once keyed on **(device_id, client_event_id)** composite UNIQUE (doc lines 17-31; select at 56-60, `UniqueConstraintViolationException` catch at 104-113 treats a concurrent insert race as duplicate).
- Duplicate re-push **echoes the ORIGINAL row's ack_status** (`ack()` at 135-147) — so a replayed `processed` event ACKs `status: processed, duplicate: true`. This is exactly what both device clients test for (`status == 'processed'`), so replay-after-lost-ACK settles cleanly. VERIFIED both ends.
- **`failed` rows are re-dispatched on every re-push** (lines 66-80): a transient handler fault (deadlock, DB blip) self-heals on the device's next retry. A permanent validation failure keeps failing forever (see findings F2/F3).
- Inserts are independent (no outer transaction) — one event never rolls back another; per-event ACK is per-event durable truth (doc lines 25-29).
- **Per-event ACK shape**: `{client_event_id, duplicate, status, event_id, server_received_at, processed_at, result}` (lines 135-147). Both `client_timestamp` and `server_received_at` are persisted on `pos_sync_events` (lines 87-93) — skew is *recorded* but never *acted on* (see §8).

### 1.3 Dispatcher (SyncEventDispatcher)
pos_api/src/app/Actions/Device/Sync/SyncEventDispatcher.php:
- Routes 14 event types (order.create/hold/transfer/pay/deliver/void, shift.open/close, expense.log, restock.request, donation.record, stock.count, product.waste, slider.display) — lines 62-79.
- Handler success → `ack_status=processed` + result_json; Throwable → `ack_status=failed` + `{error: message}` (85-101).
- After processing, best-effort **Reverb broadcast** `DeviceSyncBroadcast` to the branch channel, outside the handler try/catch, swallowed on failure (lines 104-121) — a Reverb outage can never fail a settled event.
- **GAP (F5)**: dispatch is NOT wrapped so that a *process crash* mid-handler is recovered. The SyncEvent insert commits first (its own write), the handler txn runs after; a worker kill/OOM/hard-timeout during the handler leaves the row stranded `ack_status='received'`. Rows in `received` are **never re-dispatched** (only `failed` rows are, IngestSyncEventsAction.php:66-80) and there is **no sweeper**: `grep STATUS_RECEIVED` finds only the insert site, and `src/routes/console.php` contains only the default `inspire` command. Result: the device replays forever, always ACKed `duplicate/received`, sale never settles, no server path to settle it. Handheld parks it as "stuck" after 5 rejections (visible); machine hammers invisibly.

### 1.4 Money handlers — duplicate prevention on replay
- **order.create** (CreateOrderHandler.php:66-135): UPSERT-BY-UUID inside `DB::transaction` with `lockForUpdate` on the existing row (line ~83). Cross-tenant uuid squatting rejected (§9.11, lines 84-90). Terminal statuses (paid / pending_verification / void / refunded) block the upsert (91-97). Money is snapshot-authoritative; handler validates invariant only.
- **order.pay** (PayOrderHandler.php): unlocked status pre-checks (63-77), then **inside the txn re-read + `lockForUpdate` + terminal-status re-check** (91-104: "two concurrent order.pay events with DIFFERENT client_event_ids … exactly one consume() ever runs"). Payment rows, inventory consume, commission, loyalty earn/redeem all inside the ONE txn (106-244). Tender sum must equal grand_total ±1 baisa (168-171). pending_reconciliation tender defers commission + charity forward but still consumes inventory/earns loyalty (186-203). **Replay same event id → deduped upstream; second pay with new id → "order already paid" throws.** No double-payment / double-stock path found. VERIFIED.
- **order.void** (VoidOrderHandler.php): "already void" is the SOLE idempotency mechanism, hardened by in-txn `lockForUpdate` + re-check (105-112). Unwind = inventory reverse (skipped when void reason `affects_inventory`), loyalty inverse-adjust clamped to remaining balance (never negative, never fails the void, 155-201), round-up rows flipped to `void` + payment breadcrumbs cleared (forwarded charity txn deliberately NOT reversed, 203-227), commission rows deleted unless any row claimed by payout/invoice (order-level guard, 229-273). **A re-void with a NEW client_event_id throws "already void"** — on the handheld this cannot happen (deterministic id, see §5); on the machine `enqueueVoid` mints a fresh id per call but the outbox PK `uuid:void` means only one row exists and its persisted id is reused on retry (see §2.2).
- **order.deliver** (DeliverOrderHandler.php): status guard at 76-80 ("already settled") but **NO in-txn lockForUpdate + re-check before `consume()`** (txn at 109-138 just updates + consumes) — unlike pay/void which both explicitly added the lock for the concurrent-different-id race. Exposure is narrow (the deliver event rides one outbox row; concurrent same-id pushes dedupe at ingest) but the pattern the team itself flagged in PayOrderHandler is missing here. Finding F9 (P3).
- **donation.record** (DonationRecordHandler.php): row keyed to the sync event (`client_event_id` column, line ~146); attaches to the exact card leg via `payment_index` (rows inserted in array order — resolveCardPayment 196-224); non-card leg → hard fail (89-95); pending-reconciliation tender → status 'pending', charity forward deferred to admin approval (97-112, 180-194). Forward runs AFTER commit, best-effort, and stamps `forwarded_at` only on charity 2xx.
- **charity-side dedup VERIFIED**: `POST /api/donations-pos-roundup` → `CharityTransactionsController::store_pos_roundup` computes `idempotency_key = 'pos_roundup:'.pos_reference` (charity-laravel-api/src/app/Http/Controllers/CharityTransactionsController.php:578-586) and returns the existing row on replay (622-633) — partial unique index on the shared idempotency_key column. So the crash-between-forward-and-stamp window cannot double-count the customer's money. Exactly-once end-to-end for donations.
- **shift.open / shift.close**: OpenShiftHandler enforces one open shift per device, plus (HH-2 `shared_shift: true`) one open SHARED shift per staff per branch, guards inside the write txn (61-88; note: "full serialization is deliberately not DB-enforced"). CloseShiftHandler computes expected cash + Z-report inside one txn (see §8 for the offline-sales window problem).

### 1.5 Mid-queue product/add-on delete fix (bf0bf72) — VERIFIED PRESENT
pos_api commit bf0bf72 "Offline orders survive a mid-queue product/add-on delete":
- `assertReferencesInTenant` resolves products and add-ons `withTrashed` (CreateOrderHandler.php:294-321: "an offline-queued order may land after the merchant deleted the menu item — the sale still happened and must settle"). Line resolution + snapshots also `withTrashed` (139-143, 160-166) so name/recipe snapshots stay faithful.
- **Residual strictness (deliberate per the commit, still a live stuck-sale vector)**: `customer_id` and `table_id` are checked with plain `Customer::query()` / `Table::query()` (CreateOrderHandler.php:323-333) — a customer or table soft-deleted/deleted while the order sits in an outbox makes order.create fail **permanently**. Commit message: "Customer/table references stay strict for now (deliberately out of scope)". Mitigated for customers by 50d9803 (device customer store revives soft-deleted phones). Finding F4.

---

## 2. pos_machine OrderOutbox

### 2.1 Persist-before-network — VERIFIED
- `OrderSyncRepository.enqueue()` builds the payload, writes the Drift row, THEN flushes (pos_machine/lib/data/order_sync_repository.dart:25-74; comment "The DB write happens BEFORE any network I/O"). Caller `_handleOrderCompleted` treats a throw as already-durable (staff_pos_screen.dart:432-449).
- Drift table `OrderOutbox`: PK orderUuid, eventsJson, orderNumber, createdAt, attempts, lastError, syncedAt (lib/data/db/tables.dart:237-249). `replaceConfig` never touches it (tables.dart:230-236).
- Empty-lines (demo-only) snapshots are skipped, not queued (order_sync_repository.dart:52-60).

### 2.2 client_event_id stability — VERIFIED (with nuances)
- Order batches: ids minted in `buildOrderSyncPayload` (order_sync_payload.dart:361-374, `gen()` per event) but the **full event array is serialized into eventsJson at enqueue time** and `flush()` re-sends `row.eventsJson` verbatim (order_sync_repository.dart:62-67, 154-167) → ids stable across every retry. Same for void (`enqueueVoid` persists the built event, 100-105) and hold.
- Re-hold: `enqueueHold` upserts row `uuid:hold` with a NEW id and explicitly resets syncedAt/attempts/lastError (110-144) — intentional (server upserts by uuid; hold moves no money).
- Void row key `uuid:void` never collides with the order row (82-108). `insertOnConflictUpdate` on a re-void does NOT reset syncedAt (companion omits it), so a second UI void of an already-synced void does not re-push. The residual hazard (new id after a push-without-ACK, then a second `enqueueVoid` replacing the un-ACKed row) requires the UI to re-void the same order while its first void is in flight — no such UI path found (single entry: staff_pos_screen.dart:861).

### 2.3 Flush loop, retry policy, ordering
- `flush()` (order_sync_repository.dart:150-209): pulls `pendingOutbox()` = syncedAt IS NULL **ordered by createdAt ascending** (app_database.dart:267-270); each row is its own HTTP batch; per-row try/catch so a bad row never blocks the rest.
- Success = `results` non-empty AND **every** status == 'processed' (175-180) — matches the server's duplicate-echo contract exactly.
- Rejection: `markOutboxAttempt` records attempts+lastError; first rejection per row → Sentry warning, later ones → breadcrumb only (181-199).
- **NO retry cap, NO backoff, NO parking, NO UI surfacing on the machine**: `watchPending()` exists (line 224) but `grep watchPending|pendingOutbox` across lib/ shows **zero consumers outside the repository/db files**. A permanently-rejected batch retries on every flush forever and is invisible to staff (Sentry-only). This is precisely the "known sharp edge" the handheld closed with c5857d6 — the machine never got the equivalent. Finding F2 (P1).
- Flush triggers: app start post-frame (staff_pos_screen.dart:249), reconnect (connectivity listener 336-352), and after every `enqueue*` call. **The 60s config poll does NOT flush the outbox** (259-271) — on an idle till that stayed "online", a transiently-failed row waits for the next sale/reconnect/restart. Also note: on reconnect, `syncConfig()` and `flush()` are fired concurrently unawaited (340-346) — see §7 shelf-stock ordering.
- Ordering guarantee "void after its order": void row created after the order row so oldest-first pushes create/pay first (order_sync_repository.dart:79-81). Two caveats, both self-healing: (a) Drift `dateTime()` stores whole seconds — same-second rows tie and order is unspecified; (b) rows are independent batches, so if the order row fails transiently the void row still goes up and fails "order not found for void" (VoidOrderHandler:76-78) until the create lands, then settles on a later flush. No money impact; permanent-create-failure keeps both rows as zombies (folds into F2).
- **Interleaving hazard (verified logic, low frequency)**: if order.pay fails transiently in the same flush run where the void row succeeds, the order goes VOID while still `open` (wasPaid=false — correct books: no stock/loyalty ever settled), but the create/pay row then fails "cannot pay a voided order" forever → permanent invisible zombie row on the machine (again folds into F2's missing dead-letter).
- No reentrancy guard on machine `flush()` (handheld has `_flushing`): two concurrent flushes re-push the same rows; server dedup makes this harmless (double-ACK, idempotent markOutboxSynced). Wasteful only.
- Synced rows are **never deleted** — the outbox grows forever (no delete/purge in app_database.dart outbox section, 260-284). P3 hygiene.

### 2.4 The frozen-GPS geofence trap — Finding F3 (P1)
`_handleOrderCompleted` captures GPS with a 5s timeout, falls back to last-known, and on total failure enqueues WITHOUT gps, with the comment "a fenced branch will reject it server-side and it stays queued **until a fix is obtained**" (staff_pos_screen.dart:381-399). That last clause is false: the payload (including the absent gps) is FROZEN in eventsJson at enqueue; `flush()` re-sends it verbatim forever (order_sync_repository.dart:154-167). Server: `CreateOrderHandler::enforceGeofence` and `PayOrderHandler::enforceGeofence` (PayOrderHandler.php:270-289) throw "a GPS fix is required at this geofenced branch" on every replay. The sale is permanently unsettleable — no revenue record, no stock deduction — and per F2 the machine surfaces nothing. Nothing re-enriches queued payloads with a fresh fix (no code path touches eventsJson after enqueue).

### 2.5 Other permanent-rejection vectors that hit the same capless retry
All verified server-side throw paths that a queued offline sale can hit forever:
- Loyalty redeem over-balance: ApplyLoyaltyRedeemAction is STRICT ("an over-balance spend throws — failing the pay event"; file doc + balance guard in WriteLoyaltyTransactionAction). Two offline devices redeeming the same cached balance → second one's order.pay permanently fails. The action's own doc calls reconciling this "a later refinement". (pos_api/src/app/Actions/Device/Sync/ApplyLoyaltyRedeemAction.php:30-80)
- Deleted customer/table (F4, §1.5).
- Any money-invariant drift (assertMoneyInvariant) or tenant-reference failure.
On the handheld these park visibly after 5 rejections; on the machine they are invisible.

---

## 3. Batch semantics (client side)

- One outbox row = one order = one push batch of 2-4 events (create, pay|deliver, 0-2 donation.record) — machine order_sync_payload.dart:361-414; handheld buildOrderEvents returns [create, pay] (order_sync_service.dart:399-457). Well under the 50 cap; no client chunking needed and none exists (each row is pushed as its own call, so a 200-order backlog = 200 sequential calls, never a >50 batch). VERIFIED no path builds a >50 events array.
- Partial batch failure: server processes events sequentially and independently; client marks the row synced only when ALL are processed. A batch with create=processed + pay=failed re-pushes whole; create dedupes (`duplicate:true, status:processed`), pay re-dispatches (failed-row retry). Converges. VERIFIED.
- `slider.display` telemetry is deliberately non-durable fire-and-forget (order_sync_repository.dart:211-222).

---

## 4. pos_handheld money outbox + parking (c5857d6)

pos_handheld/lib/services/order_sync_service.dart:
- Durable store = SharedPreferences key `order_outbox_v1` (line 169), JSON array of batches `{order_uuid, events, attempts, created_at, [rejections, last_error, stuck]}`. Persisted BEFORE network (enqueueCompletedOrder 866-873; enqueueDeliveryOrder 1103-1110; enqueueEvent 1163-1173), then `unawaited(flush())`.
- **What parks**: ANY outbox batch (money order batches, delivery batches, hold/void one-event batches) after `kMaxServerRejections = 5` **server rejections only** — "Network errors / offline never count — retrying those forever is correct" (175-206). Parked batches are skipped by flush but stay durable (1191-1194); `stuckCount` drives the RED drawer tile "N sales stuck" (main.dart drawer, ~3175-3190); dialog lists order/date/server error; "Retry all" → `retryStuck()` resets counters + flushes (215-227) — safe because ids are stable. Each parking fires a Sentry message with uuid in the message text (1244-1259).
- **Ops events deliberately bypass the outbox**: `pushOpsEvent` is inline-online because "the outbox has no dead-letter drop — a failed event would retry forever" (755-765); ops screens cache `_eventId ??= _newEventId()` so a retry of the SAME form submission reuses the id (ops_screens.dart:179, 315, 487, 642) → exactly-once for waste/expense/restock/count. VERIFIED.
- Void id is **deterministic**: `'order-void-$orderUuid'` (620) — "a retried void dedupes to the stored result rather than 'order already void'". Shift close likewise `'shift-close-$shiftUuid'` (shift_service.dart:62).
- Flush triggers: app start (main.dart:1056), every 60s config poll — which **drains the outbox FIRST** so the fetched shelf balances already include queued sales ("gating-review fix", main.dart:3184-3190), drawer tap (3169), after every enqueue.
- Order-log mirror: `synced:false` badge until the money batch's ACK flips it; flip failure keeps the batch queued so the badge cannot lie (1205-1229).
- Corrupt batch rows (`events` empty/malformed) are silently dropped (1200) — P3.

### 4.1 Finding F1 (P0): enqueue-during-flush erases the new sale's batch
The outbox is a single prefs value rewritten wholesale:
- `flush()` snapshots the list at entry (`_readOutbox()`, line 1183), pushes batches over the network (multi-second loop), and at the end writes back `remaining` — computed purely from its **stale snapshot** (`await _writeOutbox(remaining)`, line 1271). It never re-reads/merges.
- `enqueueCompletedOrder` / `enqueueDeliveryOrder` / `enqueueEvent` do read-append-write on the same key (866-873, 1103-1110, 1164-1171). Their trailing `unawaited(flush())` no-ops while a flush is running (`_flushing` guard, 1180-1181).
- Interleaving: flush reads [A]; during flush's network await a sale B completes and the outbox becomes [A,B]; flush finishes, writes remaining=[] (A synced) → **B is erased from the durable outbox without ever being pushed**. B's order-log row stays `synced:false` forever, but nothing re-enqueues from the log — the revenue record, inventory deduction, loyalty and commission for that sale silently never reach the server. The same lost-write race exists between two overlapping enqueues (both read-append-write).
- Window = the entire flush duration (per-batch network RTT × backlog size — tens of seconds when draining an offline backlog on reconnect, exactly when new sales are being rung). The machine is immune (Drift per-row updates, order_sync_repository.dart/app_database.dart).
- No mutex/queue serializes outbox writers; `_flushing` protects only flush-vs-flush. VERIFIED by reading all writers of `_kOutbox`.

---

## 5. Catalog sync (machine): full replace vs delta, staleness, price-change-mid-shift

- Full sync = `/device/config` → `replaceConfig` atomic cache replacement (pos_machine/lib/data/config_repository.dart:20-56). Runs at device activation + staff login (and as the fallback below). The outbox is untouched by design (tables.dart:233).
- Delta = `/device/config/delta?since=<cursor>` where cursor = the server's prior `generatedAt` (config_repository.dart:65-133; server: DeviceConfigController.php:18,48-50 — `Carbon::parse(validated('since'))`). Cursor is server-issued time, so device clock skew cannot corrupt delta correctness. Any delta failure self-heals to a full sync (129-132).
- **Deletion staleness window (documented, real)**: "Deltas don't signal a few deletions (taxes, branch_stock rows, a deactivated delivery provider) — those are healed by the full syncs that still run on device activation + staff login" (config_repository.dart:62-64). So e.g. a deleted tax persists on the till until the next staff login. P3, by design.
- Refresh cadence: Reverb-triggered debounced delta (3s; 700ms for slider edits) via `liveSyncProvider` (providers.dart:225-269) + a 60s safety-net delta poll (staff_pos_screen.dart:255-271) + on-reconnect sync (336-346). Worst-case staleness with Reverb down ≈ 60s; fully offline = until reconnect.
- **Reverb IS used** (charter question): machine subscribes to `private-branch.{id}` with device-token auth; ANY domain event (including its own echoes) triggers the debounced delta (providers.dart:225-269, started at staff_pos_screen.dart:251). Server broadcasts `DeviceSyncBroadcast` after each processed sync event (SyncEventDispatcher.php:104-121). The handheld has NO socket — 60s poll + 5s transfer-inbox poll only (transfer_inbox.dart:9-11 "the handheld has no live socket").
- **Price change mid-shift**: catalog emission → `applyCatalog` → `_applyDeliveryPricing()` **re-prices open cart lines from the live menu by product id** (pos_controller.dart:781-808: "Re-price open cart lines from the base catalog by id"). So an admin price edit reaches an open cart within seconds (Reverb) or ≤60s. The completed snapshot is then device-authoritative and the server trusts it (CreateOrderHandler doc: "does NOT re-run discount evaluation"). Consequence: totals can visibly change under a customer mid-order; conversely a fully-offline device sells at cached prices indefinitely and the server accepts them. Intended design; no rejection risk. (Held/parked drafts re-price on resume the same way; transfers re-price on the receiving till — staff_pos_screen.dart:765-769.)

---

## 6. Numbering across offline devices

- Sequential receipt numbers are **server-allocated only**: POST /device/orders/next-number → `AllocateOrderNumberAction` inside a txn with `lockForUpdate` on the counter row (DeviceOrderNumberController.php:14-23; action lines 58-84) — atomic, no collisions by construction.
- Devices call it at payment time with a **3s fuse**; on offline/timeout the order simply carries NO receipt_number and the receipt shows the device-local per-device order number (pos_controller.dart:2760-2774 "the fallback is the device-local number (receiptNumber stays '')"; wire: order_sync_payload.dart:260-263 "offline orders go up without one"; server treats it optional, CreateOrderHandler.php:118-121, 199-206).
- **Collision policy = collision-free by omission**: two offline devices can never mint the same official number because neither mints one. Cost: offline sales are permanently absent from the merchant's sequential series (a numbering GAP, not a collision), and the printed local number can duplicate across devices (display-only, never sent as receipt_number). INFERRED consequence, code-verified mechanics.

---

## 7. Stock effects of replay ordering (machine vs handheld parity)

- Machine locally decrements finite shelf stock after a sale (`consumeProductShelfStock`, app_database.dart:286-299, called at staff_pos_screen.dart:200) "until the next /device/config sync overwrites it with the server's authoritative balance".
- **Machine gap (F7, P2)**: the 60s config poll and the reconnect handler pull config WITHOUT draining the outbox first (staff_pos_screen.dart:259-271; reconnect fires syncConfig and flush concurrently, 340-346). Right after reconnect (or while a sale batch is rejected/queued), the server's balance — which excludes the queued sales — overwrites the local decrement, resurrecting shelf stock and re-enabling oversell of cooked/unit items. The handheld explicitly fixed this ordering: "Drain queued sales FIRST so the balance the poll fetches already includes them — otherwise a successful poll right after connectivity returns would resurrect shelf stock the outbox still holds a sale for (gating-review fix)" (pos_handheld/lib/main.dart:3184-3190, commit f02d437). The machine never received the same fix.

---

## 8. Clock skew: client_timestamp vs server_received_at

- Both stamps stored per event (IngestSyncEventsAction.php:87-93). No skew detection, no bound, no correction anywhere (grep found no consumer comparing them).
- Financially-relevant fields trusted from the device clock: `opened_at` (CreateOrderHandler.php:117), `paid_at` → `captured_at` on every payment row (PayOrderHandler.php:80, 147), `voided_at`, donation `occurred_at`, shift `opened_at`/`closed_at`.
- **Where it bites (F6, P2)**: CloseShiftHandler attributes cash and the whole Z-report **temporally**: `whereBetween('pos_payments.captured_at', [$shift->opened_at, $closedAt])` and `whereBetween('opened_at', $window)` (CloseShiftHandler.php:66-77, 143-210). Two failure modes:
  1. Device clock skew shifts payments outside the window → expected_cash misses them → phantom drawer variance.
  2. **Offline backlog at close (no clock skew needed)**: shift close is ONLINE-ONLY (machine ShiftService doc "Online-required", shift_service.dart:13-16; handheld identical) and **neither app flushes the outbox before closing** (machine shift_close_screen.dart:56-71 goes straight to `shiftService.close`; handheld flush call sites are only main.dart:1056/1081/3169). Sales still queued at close have no server payment rows yet, so expected_cash/variance/Z are frozen WITHOUT them; when the backlog lands later, its captured_at falls inside the already-closed window but the shift's stored figures never update. The drawer physically holds the cash → shift reports "over", and the Z under-reports sales. The device-local Z fallback (shift_close_screen.dart:75-84) partially masks this on the ticket while the server row stays wrong.
- Machine shift.close mints a RANDOM client_event_id per attempt (shift_payload.dart:76-94) — a retry after a lost ACK is a NEW event → server throws "shift already closed" (CloseShiftHandler.php:57-59) → cashier dead-end + local/server shift-state desync (recovered only via the GET /device/shift/current adoption flow, commit 77ee186). The handheld deliberately fixed this with `'shift-close-$shiftUuid'` (shift_service.dart:52-66 doc: "a close whose response was lost … instead of a dead-end 'shift already closed'"). F8 (P2, machine parity gap).

---

## 9. Cross-device: held orders, transfer, shared shifts

- **Held orders**: local store is the resume source on BOTH devices; the server `order.hold` mirror (durable outbox, key `uuid:hold`) is for cross-device VISIBILITY/audit only (machine order_sync_repository.dart:110-144; handheld held_order_store.dart:6-13 "Parked orders live here so Resume works offline; the server also gets an order.hold mirror … THIS store is the resume source"). Offline scope: holding + resuming work fully offline; the mirror queues. Cross-device *resumption* of a held order is not a feature — the online-only TRANSFER is the mechanism for moving a cart between devices. Server upsert semantics: re-hold replaces, final order.create (same uuid) flips held→open, terminal statuses block (CreateOrderHandler.php:55-97, purgeOrderChildren 214-228).
- **Order transfer is online-only by design — VERIFIED both apps**: machine pushes the `order.transfer` event inline with a modal barrier and inline ACK, never the outbox (order_sync_payload.dart:507-544 doc "Pushed ONLINE with an inline ACK (never the durable outbox)"; staff_pos_screen.dart:583-656); handheld identical (order_sync_service.dart:530-534). Server: TransferOrderHandler writes a held mirror + stamps target; target must be an active device at the same branch (39-66). Claim = `POST /device/transfers/{uuid}/claim` (online). Machine edge cases handled: claim raced by a tender parks the snapshot in memory and retries on the poll tick (`_claimedTransferPendingLoad`, staff_pos_screen.dart:737-846) — in-memory only, so an app restart between claim and load strands the claimed order server-side as held/owned-by-this-device with no local surface (P3, no money moves). Ambiguous send timeout: sender sees "failed" and keeps the cart while the server may have parked the mirror for the target — both sides converge on the SAME uuid, and the create-upsert terminal-status guard makes the second settlement fail loudly rather than double-record (worst case: one more permanently-failed outbox row on the loser, folding into F2).
- **Shared shifts (HH-2)**: both apps send `shared_shift: true` on shift.open (machine shift_payload.dart:66-70; handheld shift_service.dart:43-46). Server: one open shared shift per staff per branch; adoption via GET /device/shift/current probe; close attributes orders by staff-on-any-terminal plus staff-less orders on the opening device, tenant-scoped, keeping two coexisting shifts disjoint (OpenShiftHandler.php:24-33, 61-88; CloseShiftHandler.php:103-131). Sync aspect: shift events ride the same idempotent pipeline; both shift.open and shift.close are online-required on both devices (no outbox), so an offline day cannot open a drawer session at all — deliberate.

---

## 10. Replay double-record / money-loss scenario inventory (charter question)

Every scenario found where replay could double-record or lose money/stock:

| # | Scenario | Outcome | Verdict |
|---|---|---|---|
| 1 | Same batch re-pushed after lost ACK (any event) | Deduped on (device_id, client_event_id); duplicate ACK echoes processed | SAFE (IngestSyncEventsAction) |
| 2 | Handheld sale completed during an in-flight flush | **Batch erased from outbox — sale lost client-side, never reaches server** | **F1 (P0)** |
| 3 | Two concurrent order.pay, different ids | in-txn lock + status recheck → one consume | SAFE (PayOrderHandler:91-104) |
| 4 | Two concurrent order.void, different ids | in-txn lock + recheck → one reverse | SAFE (VoidOrderHandler:105-112) |
| 5 | order.deliver concurrent different ids | No in-txn lock+recheck → theoretical double consume | F9 (P3) |
| 6 | Donation forward retry / crash before forwarded_at stamp | charity dedupes on `pos_roundup:` + pos_reference | SAFE (charity controller 578-633) |
| 7 | Worker crash mid-handler | Event stranded `received`; never re-dispatched, no sweeper; sale never settles | **F5 (P1)** |
| 8 | Geofenced branch, no GPS at completion (offline) | Frozen payload rejected forever; machine invisible | **F3 (P1)** |
| 9 | Offline loyalty redeem races another device | Strict redeem fails order.pay forever | F2-class (P1 umbrella) |
| 10 | Product/add-on deleted mid-queue | FIXED by bf0bf72 (withTrashed) | SAFE |
| 11 | Customer/table deleted mid-queue | Permanent create failure (deliberately strict) | F4 (P2) |
| 12 | Machine permanently-rejected batch (any cause) | Capless invisible retry forever; no parking/no UI | **F2 (P1)** |
| 13 | Shift close with unsynced backlog | Wrong expected_cash/variance/Z, frozen forever | F6 (P2) |
| 14 | Config poll overwrites local shelf decrement (machine) | Shelf stock resurrected → oversell | F7 (P2) |
| 15 | Machine shift.close retry after lost ACK | New event id → "already closed" dead-end | F8 (P2) |
| 16 | In-batch duplicate ids, concurrent pushes | Unique-violation catch → duplicate ACK | SAFE |
| 17 | Voided-then-created zombie (pay-fail + void-success interleave) | Books correct; row zombies forever on machine | folds into F2 |
| 18 | Handheld corrupt outbox row | Silently dropped | P3 note |

---

## 11. Cannot-Verify / out-of-scope notes
- Runtime behaviour (actual Sentry delivery, actual Reverb prod config BROADCAST_CONNECTION) — static read only.
- pos_sync_events DDL (composite unique index migration) not opened directly; behaviour verified via the action's UniqueConstraintViolationException handling and its doc. verified:true for the mechanism, migration file not independently read.
- Whether any pos_admin sweep re-forwards unforwarded round-ups hourly (referenced in ForwardCharityDonationAction doc as "the admin reconciliation paths retry later") — pos_admin is another agent's charter; the charity-side idempotency that makes such a sweep safe IS verified.
