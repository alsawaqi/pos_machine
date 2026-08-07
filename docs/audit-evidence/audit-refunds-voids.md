# Audit: Voids, Refunds, Reversals, Comps (audit-refunds-voids)

Date: 2026-08-07. Read-only audit. All claims below are VERIFIED in code unless marked otherwise.
Repos: pos_api / pos_admin / pos_merchant (WSL, paths relative to each repo's root), pos_machine (`C:\src\projects\pos_machine`), pos_handheld (`C:\src\projects\pos_handheld`).

---

## 1. Requirements baseline (what the docs demand)

- **Void/item-void reason codes — MVP-critical**: `additions.txt:24` ("Void / item-void reason codes MVP-critical Phase 4 (catalog) + Phase 9 (POS)"); full spec `additions.txt:74-93`: "Every void (whole-order or **single-line**) must capture a reason from a configurable code list"; master list fields code, name AR/EN, affects_inventory, **affects_cogs**, requires_manager; "if requires_manager is true, manager PIN is required"; voids surface in Loss/Waste report by reason and staff.
- **Refunds deferred**: `additions.txt:50` ("Refunds and reversals (post-transaction) Phase 7+") and `additions.txt:161-163`: post-payment refund flow — full or partial — with reason code, manager approval, "(for card) Soft POS reversal call. Creates a new linked order with negative amounts so the audit trail and reporting net out cleanly."
- **Comps**: `additions.txt` "Comps and Manager Adjustments" section (page 3): manager-approved write-off of a line or whole order, reason coded, max_amount cap, always manager-approved.
- **Permissions**: `blueprint.txt:2387` "Who can approve refunds, voids: POS Manager for in-POS actions"; `blueprint.txt:1019` kiosk has "No void or refund — those require staff and happen on the Main POS". `spec.txt:444`: "Permissions control who may void or discount; the log records who actually did."
- Order status enum includes `refunded` from day one: `blueprint.txt:1666`.

---

## 2. VOID — server-side end-to-end (pos_api)

### 2.1 Entry point and dispatch
`order.void` arrives only via the offline sync push (`/device/sync/push`), dispatched in `pos_api/src/app/Actions/Device/Sync/SyncEventDispatcher.php:66` to `VoidOrderHandler`. There is no direct REST void endpoint.

### 2.2 VoidOrderHandler (`pos_api/src/app/Actions/Device/Sync/Handlers/VoidOrderHandler.php`)
- Scope: order matched by uuid **within the device's company + branch** (lines 69-77). Any device of the branch can void any of the branch's orders (cross-device void is deliberate, see machine P-F1 below).
- Idempotency: "already void" guard (78-80) is the SOLE idempotency mechanism; replayed void throws. Inside the txn the order is **re-read with `lockForUpdate()` and re-checked** (101-110) so two concurrent voids with different client_event_ids cannot double-reverse stock.
- Reason codes (Phase B, Additions §1.2): `void_reason_id` resolved **tenant-scoped** (90-98; unknown/foreign id fails the event); snapshot onto the order as `void_reason_id` + `void_reason_label` (117-123). `affects_inventory=TRUE` ⇒ inventory stays consumed (99, 130).
- `wasPaid` includes `STATUS_PENDING_VERIFICATION` (P-G7 delivery orders consumed inventory at intake) — line 115.
- Unwind, all inside ONE transaction (101-145):
  1. **Inventory** (130): `ConsumeInventoryAction::reverse()` — exact negation of consume.
  2. **Loyalty** (131, 155-196): for each EARN/REDEEM row of the order, appends an inverse `adjust` ledger row. Clawed-back earns are **clamped to the remaining balance** (173-178) — never forces the ledger negative, never fails the void. Redeems returned in full.
  3. **Round-up** (132, 204-220): flips `pos_roundup_donations` rows to `status='void'` and clears `roundup_amount`/`charity_transaction_id` breadcrumbs off the card payment. **Already-forwarded charity transactions are deliberately NOT reversed** (docblock 37-41: "refunding it is a manual charity-side op").
  4. **Commission** (133, 245-265): deletes the per-party `pos_sale_commissions` breakdown — but with the c076237 **ORDER-LEVEL claim guard**: if ANY row of the order is claimed by a payout (`payout_id`) or invoice (`invoice_id`), ALL rows survive (247-255), and the DELETE itself re-checks the claim columns (260-264) to survive READ COMMITTED races. History: 085d8f9 (full unwind), cdbcacf (payout claim guard), 6249f10 (invoice claim guard), c076237 (order-level guard + channel-split rows).
- **Payments intentionally untouched** (docblock 46-51): "A payment REFUND record ... is intentionally NOT written here: the void + these reversals ARE the books, and a real card refund needs a Soft POS terminal reversal, which is a separate flow." No such flow exists (see §5).
- Who-voided attribution: handler reads ONLY `order_uuid`, `voided_at`, `reason`, `void_reason_id`. The devices send `staff_id` / `authorized_by` (pos_machine `lib/services/order_sync_payload.dart:551-582`; pos_handheld `lib/services/order_sync_service.dart:614-630`) but the server **ignores and does not persist them** on the order — the payload survives only in the raw `pos_sync_events.payload_json` row.

### 2.3 Inventory reverse consumes the frozen snapshot (verified)
`pos_api/src/app/Actions/Device/Sync/ConsumeInventoryAction.php`:
- `consume()` = `apply(order, -1)`, `reverse()` = `apply(order, +1)` (33-43) — perfectly symmetric; the docblock line ~85 states "consume and reverse (sign applies last) — void symmetry holds."
- Reads each line's **frozen** `recipe_snapshot_json`, add-on `ingredient_snapshot_json`, `component_snapshot_json` (P-G2, frozen at create; live bulk read only as legacy fallback for pre-freeze rows, 55-70), and option-delta `consumption_snapshot_json` (PD3b). Product-unit stock (`pos_branch_product.stock_qty`) also reversed via `moveProductStock`. Append-only signed `pos_stock_movements` rows keep Σ(movements) == branch_stock.
- Contract tests: `pos_api/src/tests/Feature/DeviceSyncOrderTest.php:217` (`test_voiding_a_paid_order_reverses_the_stock`), `:778` (`test_voiding_a_paid_order_restores_branch_product_stock`); reasoned behavior in `DeviceSyncCompVoidReasonTest.php:388/413/431` (food-made keeps consumption / never-prepared restores / unknown-foreign reason fails).

### 2.4 Partial-item void — DOES NOT EXIST server-side
- `order.void` is whole-order only. `OrderItem` rows are all flipped to `STATUS_VOID` (`VoidOrderHandler.php:125`). No item-level void event type exists in `SyncEventDispatcher.php:61-70`.
- The additions doc requires single-line voids with reason capture (`additions.txt:75-76`). See finding F2.

### 2.5 Unpaid vs paid void
- Open/held (never-paid) orders: status flip only; reversals correctly skipped (129-133 `$wasPaid` gate). Machine's `discardHeldOrder` (pos_machine `lib/state/pos_controller.dart:2469-2487`) emits `order.void` for a mirrored held order ("an unpaid void has no inventory unwind").

---

## 3. VOID — who can void (permission gates)

### 3.1 pos_machine (main POS) — strongest gate
- Company policy: `positionCanCancelOrders()` (`lib/state/pos_controller.dart:303-308`; default allowlist `['manager']`, `:254-255`, synced from config `settings.cancel_order_positions`) — checked at `lib/screens/staff_pos_screen.dart:2052-2065` (v2 #14).
- Then the P-F1 manager-authorization gate for EVERY cancel: fingerprint first (offline-capable), manager-PIN fallback verified **server-side** by pos_api against `manager_approval_positions` (`staff_pos_screen.dart:2068-2079`, `2101-2123`; endpoint `pos_api/src/routes/api.php:67-74`, extra-throttled in the pos-login brute-force bucket).
- Void reason mandatory when the company configured any (`staff_pos_screen.dart:11626-11630`).
- Per-reason `requires_manager` flag is **not consulted** on the machine — the blanket manager gate is stronger than the spec requires, so compliant. The flag is shipped in config (`pos_api/src/app/Actions/Device/BuildDeviceConfigAction.php:847`) and stored (`pos_machine/lib/data/db/tables.dart:166`) but never branched on.

### 3.2 pos_handheld
- `_voidCurrentOrder` (`lib/main.dart:1544-1605`): reason sheet when reasons configured; manager authorization **only when the picked reason's `requiresManager` is true** (1581-1588) — exactly the additions-doc semantics. Void event durably enqueued with deterministic `client_event_id: 'order-void-$orderUuid'` (`lib/services/order_sync_service.dart:620`).
- Handheld can only void the CURRENT (unpaid/held/claimed) cart; the order-history screen has **no cancel affordance** (`lib/screens/order_history_screen.dart` — no void/cancel code). Paid-order voids are machine-only.

### 3.3 Server side — no authorization on the void event itself
- The sync push is `auth:pos_device` (device token) only. `VoidOrderHandler` performs no staff/position/manager validation and discards `staff_id`/`authorized_by`. Contrast: kitchen production **cancel** carries a manager PIN verified server-side (`pos_api/src/routes/api.php:132-140`). The manager gate for order voids is enforced purely device-side (offline-first tradeoff). See finding F5.

---

## 4. VOID — shift/cash and reports impact

### 4.1 Server shift close (`pos_api/src/app/Actions/Device/Sync/Handlers/CloseShiftHandler.php`)
- `expected_cash = opening_cash + Σ(cash tendered − change)` over `pos_payments` with `status='success'` in the window (66-77). **No order-status filter** — a paid-then-voided cash order's tender still counts toward expected cash (void never touches Payment rows). If the cashier returned the cash to the customer, the drawer reads SHORT with no explaining record; if not returned, the drawer is "right" but the Z's sales totals (paid-only) no longer tie to its tender totals. See finding F3.
- Z summary (`salesSummary`, 148-220): sales totals = `status='paid'` orders only (149-167); tender lines = success payments regardless of order status (169-183); voids surfaced separately as `void_count` / `void_total_baisas` (182-186, 214-215).

### 4.2 Device-local fallback Z (pos_machine `lib/services/shift_summary.dart`)
- Server summary is the source of truth; the local fallback **excludes fully-canceled orders from tender totals entirely** (158-162 `continue` before tender accumulation) — the opposite convention from the server's expected-cash math — and per its own header comment (line 8) "partial cancels are not netted". Voids printed as their own Z line (356-360, 445-450).

### 4.3 Reports
- Merchant Loss/Waste report: voids by reason label snapshot + by staff, `status='void'` scoped (`pos_merchant/src/app/Actions/Pos/Reports/LossWasteReportAction.php:203-244, 266-267`) — the Additions §1.2 surfacing requirement is met for whole-order voids.
- Merchant sales report: voids excluded from gross (paid-only); a `refunds_total`/`refund_count` section reads `status='refunded'` orders (`pos_merchant/src/app/Actions/Pos/Reports/SalesReportAction.php:86-116, 184, 207`) — **permanently zero** (nothing ever sets `refunded`; §5). Same for admin (`pos_admin/src/app/Actions/Admin/Reports/AdminSalesReportAction.php:56`).
- Device branch report nets voids out of ingredient consumption by summing signed movements (`pos_api/src/app/Actions/Device/BuildBranchReportAction.php:313-314`).
- Comp report joins `pos_orders.status='paid'` (`pos_merchant/src/app/Actions/Pos/Reports/CompReportAction.php:50-54`) so voided orders' comps don't pollute comp totals.
- Settlement integrity: voided orders' surviving commission rows are excluded from payout claiming (`pos_admin/src/app/Actions/Admin/Reconciliation/SettlementPendingAction.php:58-65` "A VOIDED order must never be claimed") and from invoice claiming (`pos_admin/src/app/Actions/Admin/Invoices/PendingCommissionInvoiceAction.php:40-47`).

---

## 5. REFUNDS — confirmed ABSENT everywhere (matches Phase 7+ deferral)

- `Order::STATUS_REFUNDED` exists (`pos_api/src/app/Models/Order.php:43`) and is **only ever read** (status filters in `CreateOrderHandler.php:87`, `DeliverOrderHandler.php:76`, `DeviceOrdersController.php:43`). Exhaustive grep across pos_api/pos_merchant/pos_admin: **no code path ever sets `status='refunded'`**; only report readers reference `OrderStatus::Refunded`.
- `WalletLedgerEntryType::RefundIn` (`pos_merchant/src/app/Enums/WalletLedgerEntryType.php`, "Phase 7+ order refund flows here instead of back-to-cash") has sign validation in `WriteWalletLedgerEntryAction.php:80-81` but **no caller anywhere writes it**.
- No refund endpoint, action, or UI exists in any repo (device or portal). The "negative linked order" mechanism from `additions.txt:161-163` is unimplemented.
- **What happens today when a paid order must be reversed**: the ONLY tool is the whole-order void (machine, manager-gated). Money side: nothing — the Payment rows stay `success`; cash return is unrecorded (drawer variance, F3); card money stays captured (no reversal, §6).
- Bank-reconciliation refund flagging from `blueprint.txt:497/1745` ("Mark reconciled or flag refund") is not implemented as a refund — the admin reject path exists but marks tenders `failed`, never `refunded` (§6.2).

## 6. CARD reversal path — ABSENT (device and server)

- pos_machine Mosambee service exposes only `prepareSession` / `payWithPreparedSession` / `loginAndPay` (`lib/services/mosambee_payment_service.dart:219-395`) — **no void/refund/reversal API**.
- pos_handheld states it in code: "a second card capture can't be safely aborted (**Mosambee has no reversal**), so we forbid it up front" (`lib/screens/payment_screen.dart:1973-1975` — max one card leg per split).
- `VoidOrderHandler` docblock 46-51 explicitly punts the Soft POS terminal reversal to "a separate flow" that does not exist. Voiding a card-paid order therefore leaves the customer charged; remediation is fully manual and nothing in any UI flags it.

### 6.2 Pending card charges (force-recorded Soft POS, P-F7) and their reversal story
- Ambiguous NFC-timeout charge → cashier prompt retry/record/cancel (`pos_machine/lib/state/pos_controller.dart:3581-3591`); force-record lands `status='pending_reconciliation'` (`PayOrderHandler.php:144-153`; `Payment.php:48`). Downstream money effects (commission split + charity round-up forwarding) are DEFERRED (`PayOrderHandler.php:185-200`); inventory + loyalty fire at pay ("points are clawed back by voids").
- Admin **reject** (money never arrived): `pos_admin/src/app/Actions/Admin/Reconciliation/RejectPendingReconciliationAction.php` — tenders → `failed`, audited; **"DELIBERATE SCOPE: this does NOT auto-void the order"** (23-28) — the sale must then be voided/re-charged manually through normal flows. The order remains `status='paid'` with a failed tender until someone voids it at the till.
- Admin **approve** (queue or bank-file match): `ApprovePendingReconciliationAction.php` / `ReconcilePaymentsAction.php` → shared `ReconcileDeferredEffectsAction`. **Neither checks order status** — see finding F1.

---

## 7. COMPS and GIFTS — implemented (Additions §1.2 + P-F5)

- Server: `CreateOrderHandler::writeComps` (`pos_api/src/app/Actions/Device/Sync/Handlers/CreateOrderHandler.php:460-538`): every non-gift comp requires a **tenant-valid** `comp_reason_id` (487-492), capped by the reason's `max_amount` (494-501); gift rows (`is_gift=true`) must NOT carry a reason and bypass caps (474-484); approver `staff_id` tenant-guarded as an audit-integrity FK (505-509); rows snapshot reason code/name; Σ(comp rows) must equal `comp_total_baisas` exactly (530-534); money invariant becomes subtotal − discount − comp + tax == grand_total (`DeviceSyncCompVoidReasonTest.php` docblock). Comp money never collected ⇒ excluded from the commission base; whole-order gift excluded from loyalty earn (`PayOrderHandler.php:109-118`).
- Reason catalog: `pos_comp_reasons` (pos_admin migration `2026_07_02_010000_add_void_comp_reasons_and_addon_constraints.php`), merchant CRUD (`pos_merchant/src/routes/web.php:976-993` area, `CompReasonsController`, `SaveCompReasonAction`, defaults via `EnsureDefaultOrderReasonsAction`), shipped in device config (`BuildDeviceConfigAction.php`).
- Devices: machine comp/gift flows manager-gated via the same P-F1 gate (`staff_pos_screen.dart:2101` docblock lists "comp, gift, cancel, reprints, approval-required discounts, reports"); handheld has `_appliedComp`.
- Reporting: `CompReportAction` (headline/by-reason/by-branch/by-approver, gifts split out), `DiscountedCompedProductsReportAction`.
- Contract tests: `DeviceSyncCompVoidReasonTest.php:151-349` (10 comp/gift tests incl. cap, tenant, sum-invariant, approver guards).
- Comp rows on void: untouched by `VoidOrderHandler` (no flag), but comp reports join `status='paid'` so no leakage (`CompReportAction.php:53`).

## 8. VOID REASON CODES — implemented with one documented deviation

- Schema: `pos_admin/src/database/migrations/2026_07_02_010000_add_void_comp_reasons_and_addon_constraints.php:87-104` — `pos_void_reasons` (company-scoped, code unique per company, `affects_inventory` default false, `requires_manager` default true, AR/EN names, sort, soft-deletes); `pos_orders` gains `void_reason_id` + `void_reason_label` snapshot (127-133); default codes from the additions doc are seeded per company (62, 215-237).
- **Deviation (documented)**: the doc's separate `affects_cogs` flag is "folded" into `affects_inventory` (migration docblock line 23) — no distinct COGS-only behavior exists.
- Device config ships the active set (`BuildDeviceConfigAction.php:847`); machine caches them in Drift (`lib/data/db/tables.dart:158-166`) and requires a pick when any exist; handheld likewise (`lib/models/catalog.dart:1127`).
- **Item-void reason capture**: required by the doc, structurally impossible today because item-void itself doesn't reach the server (F2). The machine dialog does force a reason for a partial cancel (`staff_pos_screen.dart:11626`) but then drops it — `cancelCompletedOrder` only threads `voidReason` into the full-order `onOrderVoided` call (`pos_controller.dart:2660-2669`), and the local `OrderCancellationRecord` has no reason field (`pos_controller.dart:2540-2551`).

---

## 9. FINDINGS

### F1 (P1) — Deferred money effects fire on ALREADY-VOIDED orders (commission rows written + void-flagged round-ups forwarded to charity)
`pos_admin/src/app/Actions/Admin/Reconciliation/ReconcileDeferredEffectsAction.php` never inspects `$order->status`:
- `recordCommission` (146-197) records a FULL commission split whenever the order has no `pos_sale_commissions` rows — which is exactly the state of a voided pending-tender order (the split was deferred at pay; the void's `reverseCommission` found nothing to delete).
- `forwardDonations` (205-235) selects `whereNull('forwarded_at')` **without a status filter** — the round-up rows the void flipped to `status='void'` (`VoidOrderHandler.php:204-220`) still have `forwarded_at=NULL`, so they are forwarded to the external charity app as `'success'`.

Trigger paths, both real: the daily approval queue lists orders purely by pending tenders with no void filter (`pos_admin/src/app/Http/Controllers/Api/Admin/PendingReconciliationController.php:55-59`), and the bank-file matcher sweeps matched payments regardless of order status (`ReconcilePaymentsAction.php:16-44` → same shared action). Scenario: order paid with force-recorded card charge → device voids it (inventory/loyalty unwound, donation flipped void) → charge actually arrived, admin approves or the bank-file match lands → a VOID sale now has live commission rows and its round-up is forwarded to charity. Containment: those commission rows can never be CLAIMED by a payout/invoice (`SettlementPendingAction.php:58-65`, `PendingCommissionInvoiceAction.php:40-47`), but they exist in `pos_sale_commissions` and will pollute any report/summary that aggregates the table without joining order status; the charity forward is external real money with no automated clawback. VERIFIED (code paths); the end-to-end race itself not executed (no DB access) — behavior follows directly from the queries.

### F2 (P1) — Partial (item-level) void is device-local fiction: server books never learn
pos_machine `lib/state/pos_controller.dart:2620-2676`: partial cancel updates only the LOCAL snapshot (`paymentStatus: 'Partially Canceled'`, cancellation records) — `onOrderVoided` (→ `order.void`) fires **only when `cancelFullOrder=true`** (2657-2669). No sync event exists for item void (`SyncEventDispatcher.php:61-70`). Consequences for a PAID order partially voided at the till: server order stays `paid` at full amounts; no inventory restoration for the removed items; no loyalty/commission/round-up adjustment; merchant reports and the shift Z keep the full sale; the reason the dialog forced the cashier to pick is discarded (2660-2669) and the local `OrderCancellationRecord` cannot store one (2540-2551). The local fallback Z doesn't net partial cancels either (`shift_summary.dart:8`). Violates `additions.txt:75-76` ("Every void (whole-order or single-line) must capture a reason") and leaves an unreconcilable device/server divergence. Server-history records are correctly restricted to full-order cancel (P-F1, `pos_controller.dart:2524-2536`), which shows the gap is known.

### F3 (P2) — Void of a paid order never reverses the tender; shift expected-cash counts voided orders' cash
`VoidOrderHandler` leaves `pos_payments` untouched by design (docblock 46-51). `CloseShiftHandler.php:66-77` sums cash payments `status='success'` with **no order-status join**, so a cash sale voided mid-shift still inflates `expected_cash`; if the cash was handed back to the customer (the normal reason to void a paid sale), the close shows an unexplained SHORT variance — there is no "cash returned" record type at all. The Z's paid-only sales totals (149-167) meanwhile exclude the voided order, so tenders ≠ sales + voids in any consistent way. The device-local fallback Z uses the OPPOSITE convention (excludes canceled orders' tenders entirely, `shift_summary.dart:158-162`), so offline fallback and server disagree about the same drawer. Root cause is the absent refund/reversal layer (Phase 7+), but the drawer math inconsistency is present today.

### F4 (P2) — Card-paid void leaves the customer charged with zero operator signal
No Soft POS reversal exists on machine (`mosambee_payment_service.dart:219-395` — pay-only API) or handheld (explicit comment `payment_screen.dart:1975`), and the server writes no refund record. Nothing in the machine cancel dialog warns that voiding a card-paid order does NOT return the customer's money, and nothing queues/flags the manual refund obligation anywhere (no report lists "voided card-paid orders needing refund"). Money outcome: books net to zero, acquirer keeps the capture, customer is out of pocket until a fully out-of-band manual process happens. Required by `additions.txt:161-163` only at Phase 7+, so this is a documented deferral — but the missing operator signal is a today-problem.

### F5 (P2) — No server-side authorization or attribution on order.void
Sync push is device-token auth only; `VoidOrderHandler` validates no staff/position/manager approval and **discards** `staff_id`/`authorized_by` from the payload (reads only 4 keys, lines 62-99; device senders: pos_machine `order_sync_payload.dart:551` "the server ignores keys it doesn't read", pos_handheld `order_sync_service.dart:614-630`). `pos_orders` has no voided_by column (migration `2026_07_02...php:127-133` adds only reason id/label). The per-reason `requires_manager` flag is server-shipped but server-unenforced. Contrast: kitchen production cancel verifies a manager PIN server-side (`routes/api.php:132-140`). Impact: a compromised/modified device (or replayed device token) can void any order of its branch with no manager involvement, and "who voided" is recoverable only by digging the raw `pos_sync_events.payload_json`. `spec.txt:444` expects the log to record who actually did it. Offline-first makes hard server enforcement genuinely impossible; persisting the claimed approver on the order and honoring requires_manager when the PIN path was used would close most of the gap.

### F6 (P2) — A void carrying a soft-deleted reason id fails permanently, leaving device and server disagreeing
`VoidReason` uses `SoftDeletes` (`pos_api/src/app/Models/VoidReason.php:8,18`) and `VoidOrderHandler.php:92-97` resolves with a scope-respecting `find()` → a reason deleted on the portal after the device queued the void makes the event throw "void reason not found" on every re-push, forever (no `withTrashed()`, unlike `CreateOrderHandler`'s product/add-on resolution at :142). The order stays paid/open server-side while the till shows it canceled. VERIFIED logic; the stuck-outbox consequence is INFERRED from the retry design (failed events are re-pushed: `DeviceSyncOrderTest.php:325`).

### F7 (P3) — reverseLoyalty clamp races an unlocked balance read
`VoidOrderHandler.php:164-178` clamps the earn clawback against `LoyaltyAccount` read WITHOUT a lock; `WriteLoyaltyTransactionAction` re-reads under `lockForUpdate` (:44) and throws if the (stale-clamped) delta drives the balance negative — failing the whole void txn. Self-healing: the device re-pushes and the next attempt re-clamps. Worst case is a delayed void, not corruption.

### F8 (P3) — DonationRecordHandler has no order-status guard
`pos_api/src/app/Actions/Device/Sync/Handlers/DonationRecordHandler.php` never checks the order isn't void (grep: no STATUS_VOID reference); a `donation.record` replay/late arrival after a void would insert a fresh donation row for a void order. Per-device FIFO outbox makes this improbable in practice; client_event_id idempotency blocks true replays.

### F9 (P3) — Handheld cannot void paid orders (parity gap, likely intentional HH-3 scope)
`pos_handheld/lib/screens/order_history_screen.dart` exposes reprint only; every void path targets the current unpaid/held cart (`main.dart:1544`). A paid-order mistake on handheld must be voided from a machine (or any branch device via server history on the machine). No evidence in docs that this is final scope. verified:true for the code fact, intent unverifiable.

---

## 10. Reversal-chain summary table

| Effect of a paid sale | Written at | Reversed on void? | Where |
|---|---|---|---|
| Order + items status | order.create/pay | YES (whole-order only) | VoidOrderHandler:117-125 |
| Ingredient/recipe stock (frozen snapshots) | order.pay | YES, unless reason affects_inventory | ConsumeInventoryAction::reverse |
| Product-unit stock | order.pay | YES (same path) | ConsumeInventoryAction::moveProductStock |
| Loyalty earn/redeem | order.pay | YES (inverse adjust, earn-clawback clamped) | VoidOrderHandler:155-196 |
| Round-up donation row | donation.record | YES (status→void + breadcrumbs cleared) | VoidOrderHandler:204-220 |
| Round-up already forwarded to charity | forward | NO — manual charity-side op (documented) | docblock:37-41 |
| Commission breakdown | order.pay (or admin reconcile) | YES if unclaimed; NO if any row payout/invoice-claimed (frozen statements, by design) | VoidOrderHandler:245-265 |
| Commission deferred (pending tender) | admin approve | **BUG: recorded even after void** | F1 |
| Payment/tender rows | order.pay | NO (by design; no refund layer) | F3/F4 |
| Cash in drawer / expected_cash | shift close | NO (voided cash still counted) | F3 |
| Card capture at acquirer | Soft POS | NO (no reversal API anywhere) | F4 |
| Comp rows | order.create | Not flagged; reports filter status=paid | §7 |
| Partial item void | — | NOT SYNCED AT ALL (local-only) | F2 |
| Refund (full/partial, post-payment) | — | ABSENT everywhere (Phase 7+; scaffolding: STATUS_REFUNDED, RefundIn enum, refunds_total report lines all dormant) | §5 |

## 11. Cannot-verify / out of scope

- Runtime behavior of the F1 race (needs DB/live system) — logic verified from queries only.
- Whether the handheld paid-void gap (F9) is intended final scope.
- Kitchen production cancel/disposition reversals (`CancelProductionAction`, `ApplyDispositionAction`) — adjacent reversal flows left to the inventory-audit charter.
- Kiosk surface: no kiosk repo present; blueprint says kiosk has no void/refund (blueprint.txt:1019).
