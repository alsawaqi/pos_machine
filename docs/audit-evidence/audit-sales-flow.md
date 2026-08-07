# Audit: Full Sales Flow (device cart → server settlement → viewers/reports)

Agent: audit-sales-flow · Date: 2026-08-07 · READ-ONLY audit.
Sources examined directly: `pos_machine` (C:\src\projects\pos_machine), `pos_handheld` (C:\src\projects\pos_handheld), and scratchpad mirrors of `pos_api/src`, `pos_merchant/src`, `pos_admin/src` (copied verbatim from WSL — line numbers cited are identical to the repo files; repo-relative paths given below).

Legend: [V] = VERIFIED in code. [I] = INFERRED (stated, plausible, not fully traced). [CV] = cannot verify.

---

## 1. End-to-end execution chain (machine, happy path)

### 1.1 Cart build (pos_machine)
- Cart items: `PosController._cart` (List<CartItem>); `rawSubtotal = Σ item.lineTotal` — `pos_machine/lib/state/pos_controller.dart:1070`; `CartItem.lineTotal = unitPrice * qty` — `pos_machine/lib/models/pos_models.dart:656`. [V]
- Add-ons ride each cart item as `modifiers`; per-line notes as `raw['notes']` — serialized in `_snapshotItem` `pos_controller.dart:1237-1251` and `item.toMap()` `pos_models.dart:727`. [V]
- Discounts: order-level (`discountAmount`, fixed/percent, clamped to rawSubtotal) `pos_controller.dart:1072-1085`; auto per-line product/category discounts `lineDiscountFor` `:1089-1122`; offer engine (`appliedOffers`, pure recompute per read) `:1131-1155`; auto-apply order rule `maybeAutoApplyOrderDiscount` `:1208-1233`.
- Comps/gifts: `compAmount` (manager comp + per-line gifts, derived live) `:1277-1298`; gifts `giftAmountFor` `:1262-1266`.
- Tax: `_taxedBase = subtotal − compAmount`; `tax = taxTotalFor(_taxedBase)`; delivery orders are tax-exempt (`_isTaxExempt`) `:1325-1340`. `total = _taxedBase + tax` `:1340`. Money is double OMR, rounded via `_roundMoney` (3 dp) `:3950`. [V]
- Delivery-provider orders are exempt from discounts/offers/comps/gifts/tax (P-G7 gates at `:1094, :1134, :1171, :1211, :1310, :1348`). [V]

### 1.2 Completion → snapshot → print → save → push
`_finishCompletedOrder` `pos_controller.dart:3200-3247`: [V]
1. `_assignFinalOrderNumber()`;
2. snapshot stamped with server order uuid (`_activeServerOrderUuid` if resumed from hold, else fresh `uuidV4()`) `:3209-3210`;
3. receipt printed (`SunmiReceiptService.printReceipt`, failure is non-fatal, staff alert only) `:3212-3217`; kitchen ticket `:3218-3225`;
4. local save `_saveCompletedOrder` `:3226` (Drift order history);
5. `onOrderCompleted?.call(snapshot)` `:3229` → screen bridge;
6. dine-in table freed / marked paid `_markActiveDiningTablePaid` `:3230-3232, 3818-3855`;
7. local shelf-stock decrement `_consumeShelfStockFromCart()` `:3236` (persisted clamped at 0, `lib/data/db/app_database.dart:291-305`).

Screen bridge `_handleOrderCompleted` `pos_machine/lib/screens/staff_pos_screen.dart:361-449`: captures phone/plate/provider/cardCharge/joined tables synchronously; awaits GPS (≤5 s + last-known fallback) `:381-399`; resolves/creates customer via API (`saveCustomer`, best-effort) `:408-421`; computes loyalty earn rule ids `:427-430`; then `OrderSyncRepository.enqueue(...)` `:433-445`. [V]

### 1.3 Outbox (durable, offline-first)
`pos_machine/lib/data/order_sync_repository.dart`:
- `enqueue` builds the payload ONCE (stable client_event_ids), persists `eventsJson` to Drift `order_outbox` keyed by order uuid BEFORE network I/O `:25-74`, then `flush()`.
- `flush()` `:150-209`: pushes each pending row via `POST /device/sync/push` (`lib/services/pos_api_service.dart:213-221`); marks synced only when EVERY event ACKs `status == 'processed'` `:175-180`; otherwise records attempt + lastError and retries forever (first rejection → Sentry message `:187-199`). Network failure = retry with the SAME event ids `:201-205`. No retry cap, no parking. [V]
- Hold mirror rows keyed `uuid:hold` (PK upsert resets syncedAt/attempts) `:118-144`; void rows keyed `uuid:void` `:82-108`. `enqueueOutbox` = `insertOnConflictUpdate` `lib/data/db/app_database.dart:263-264`. [V]

### 1.4 Wire payload (machine)
`pos_machine/lib/services/order_sync_payload.dart` `buildOrderSyncPayload` `:87-417`: [V]
- Events: `order.create` + (`order.pay` XOR `order.deliver`) + 0..n `donation.record` `:361-414`. Machine only pushes create at COMPLETION (create+pay ride one batch); an open order is otherwise invisible server-side until held/transferred/paid.
- Money integer baisas (`omrToBaisas = (omr*1000).round()` `:24`).
- order block `:256-280`: uuid, order_type (`mapOrderType` `:27-39`; `quick_order`→`quick`; machine never emits `car`), source `main_pos`, receipt_number (P-F8, optional), subtotal/discount/comp/tax/grand in baisas, opened_at, lines[] (product_id, qty, unit_price, line_total, notes, addons[{add_on_id, price_delta_baisas}]), discounts[] (order-level + line + offers with offer_id/line_index) `:179-217`, comps[] (gift rows first, capped to budget; reasoned comp takes remainder — rows sum EXACTLY to comp_total) `:219-254`, gps, staff_id, table_id, joined_table_ids, customer_id, plate_number, note.
- pay event `:313-334`: order_uuid, paid_at, payments[] (split: last leg absorbs rounding so Σ==grand `:288-302`; card tenders carry softpos_reference/auth_code/bank_response + status success|pending_reconciliation `_applyCardCharge` `:57-69`), gps, loyalty_rule_ids, loyalty_redeem{rule_id, points, stamps}.
- delivery event `:347-359` when `orderType==delivery && deliveryReference set` `:344-345` (deliberately NOT conditioned on provider id — a missing provider must fail server-side rather than fall through to a phantom cash pay `:336-343`).
- donation.record per rounding CARD leg with `payment_index` addressing the exact tender `:376-414`.
- hold event `buildOrderHoldEvent` `:426-505` (order.create's shape, status held, no GPS); transfer = hold + `target_device_id` `:515-544`; void `buildOrderVoidEvent` `:553-582` (order_uuid, void_reason_id, reason, staff_id — client_event_id minted fresh per build).

### 1.5 Server ingestion (pos_api)
- Route: `POST /api/v1/device/sync/push` `pos_api/src/routes/api.php:96`, guard `auth:pos_device` + per-device throttle `:60`; unassigned device → 409 (`SyncPushController` `pos_api/src/app/Http/Controllers/Api/V1/Device/SyncPushController.php:35-40`). [V]
- `IngestSyncEventsAction` `pos_api/src/app/Actions/Device/IngestSyncEventsAction.php:47-128`: EXACTLY-ONCE on (device_id, client_event_id) UNIQUE; duplicate → ACK original row's state; FAILED rows are RE-DISPATCHED on re-push `:68-75`; concurrent insert race → UniqueConstraintViolation caught → duplicate ACK `:101-111`. Inserts independent (no outer txn) `:24-28`. [V]
- `SyncEventDispatcher` `pos_api/src/app/Actions/Device/Sync/SyncEventDispatcher.php:58-114`: routes 14 event types; handler in try/catch → stamps `processed` (+result_json) or `failed` (+error); after settle, best-effort branch broadcast (Reverb) outside the try `:99-113`. Unknown types stay `received` (note: machine's flush treats non-processed as failure and retries — a truly unknown type would loop forever, but both devices only emit known types). [V]

### 1.6 order.create → DB writes
`CreateOrderHandler` `pos_api/src/app/Actions/Device/Sync/Handlers/CreateOrderHandler.php`:
- Validation `:567-622` (uuid, type/source whitelists, money ints ≥0, lines min 1, receipt ≤24 chars, discounts/comps shapes).
- Money invariant: `subtotal − discount − comp + tax == grand ± 1 baisa` `:627-638`. **The server does NOT recompute pricing** — it does NOT check Σ line_total == subtotal, unit_price×qty == line_total, Σ discount rows == discount_total, or prices vs catalogue. Snapshot-authoritative by design (§9.1.6, header comment `:36-42`). Comp rows MUST sum exactly to comp_total `:531-535`. [V]
- Tenant guard `assertReferencesInTenant` `:279-344`: products/add-ons (withTrashed), customer, table, staff (`TenantReferenceGuard::assertStaffInTenant`), joined tables — all must belong to device.company_id; offers hard-fail if foreign `:400-409`; discount_id soft-drops to null `:391-394, 425-428`.
- Geofence: fail-closed on create for fenced branches (GPS required) `:545-562`; skipped for holds/transfers (`HoldOrderHandler.php:22-27`).
- UPSERT-BY-UUID in one txn with `lockForUpdate` `:77-134`: cross-tenant uuid squat → fail `:79-85`; terminal statuses (paid / pending_verification / void / refunded) block the upsert `:86-92`; NON-terminal (open/held/kitchen) row → `purgeOrderChildren` (items, addons, discounts, comps, joined tables) + full rewrite `:124-127, 215-227`. **This is the whole “order edit” story: while non-terminal, a re-push replaces items wholesale; after terminal, immutable.**
- Line writes `:137-179`: OrderItem with product_name/unit_price/line_discount/line_total snapshots, `recipe_snapshot_json` (`snapshotRecipe` `:657-682` — null for cooked/unit products: production/purchase already carries cost), `component_snapshot_json` (`snapshotComponents` `:695-705`, [] vs null legacy), notes, status open. Add-ons `:159-177`: name/price snapshots + `ingredient_snapshot_json` XOR `consumption_snapshot_json` (PD3b `:761-800`) + product-as-add-on freeze (`snapshotAddonProduct` `:717-749`).
- Discounts `writeDiscounts` `:382-442`: per-row audit incl. offer_id (hard tenant check), line_index → order_item map, reason capped 160.
- Comps `writeComps` `:461-536`: gift XOR reason exclusivity, reason cap (max_amount) enforced, approver staff tenant-checked `:508-509`.
- Joined tables `writeJoinedTables` `:238-265`: extra tables minus primary; ignored when no primary table.
- Result: order_id/uuid/status created|updated. [V]

### 1.7 order.pay → payments, inventory, commissions, loyalty
`PayOrderHandler` `pos_api/src/app/Actions/Device/Sync/Handlers/PayOrderHandler.php`:
- Resolve order scoped company+branch `:55-59` ("an order cannot be paid from another branch" — tested `pos_api/src/tests/Feature/DeviceSyncOrderTest.php:455`).
- Status guards (unlocked) `:64-74`, then geofence fail-closed `:79, 276-289`.
- **DOUBLE-PAY DEFENSE**: inside `DB::transaction`, re-read with `lockForUpdate` + re-check terminal status `:85-102` — two concurrent pays with different client_event_ids serialize; loser sees PAID and throws. Test: `test_a_second_distinct_id_pay_does_not_double_deduct` `DeviceSyncOrderTest.php:271`. Same-id replays deduped upstream (`test_replaying_create_and_pay_settles_exactly_once` `:242`). **An order cannot be paid twice.** [V]
- Tenders `:120-166`: one `pos_payments` row per tender (uuid, method, amount, change_given, softpos evidence, status, pending_reconciliation flag, device/terminal/bank snapshot, bank_response, captured_at). Method whitelist `Payment::METHODS = [cash, card, split_part, loyalty, gift, bank_pos]` (`pos_api/src/app/Models/Payment.php:44`). **No min:0/integer validation on amount_baisas or change_given** `:121-124` — a negative tender is accepted as long as Σ==grand (see finding F4).
- Tender-sum invariant: `|Σ tendered − grand| ≤ 1 baisa` `:168-171`.
- Flip: `status=paid, closed_at=capturedAt` `:173-176`.
- Inventory: `ConsumeInventoryAction->consume($order)` INSIDE the same txn `:178`.
- Commission: `RecordSaleCommissionAction->record(...)` `:193-203`; **DEFERRED when any tender is pending_reconciliation** (P-F7) — recorded later by pos_admin `ApprovePendingReconciliationAction` (twin) — inventory + loyalty still fire (goods left the shop) `:184-192`.
- Loyalty earn: per named rule (multi-program v2#3) `:211-221`; fully-gifted order earns nothing `:211-213`. Redeem `:224-231` — STRICT (see finding F1).
- Atomicity: the WHOLE handler (payments+flip+inventory+commission+loyalty) is ONE transaction `:85-244`; any throw → `failed` event, everything rolled back; re-push re-dispatches (`test_a_failed_pay_event_is_retried_on_re_push` `DeviceSyncOrderTest.php:325`; `test_a_broken_money_invariant_fails_only_that_event` `:418`). **Partial failure mid-pay cannot half-settle.** [V]

### 1.8 Inventory consumption detail
`ConsumeInventoryAction` `pos_api/src/app/Actions/Device/Sync/ConsumeInventoryAction.php`:
- `consume` = apply(−1), `reverse` = apply(+1) `:33-42`; caller's txn wraps it `:22-25`.
- Per line: product-unit shelf move (`moveProductStock` `:364-404` — pos_branch_product.stock_qty atomic SQL increment, only when unit-tracked; + product ledger row `pos_product_stock_movements`), merged ingredient/component plan (`mergeItemConsumption` `:228-297` — frozen recipe + frozen/live components + PD3b option deltas, clamped ≥0, 3 dp rounding), signed `pos_stock_movements` rows + `pos_branch_stock` atomic increment (`move` `:299-346`; lost-update fix documented `:324-343`). Negative stock intentionally allowed `:26-29`.
- Add-ons: legacy single-ingredient trio (skipped when PD3b lines exist `:139-142`), product-as-add-on by frozen stock_mode `:161-201`.
- Ledger invariant Σ(movements) == branch_stock (fractional-qty test `DeviceSyncOrderTest.php:293`). [V]

### 1.9 Commission breakdown
`RecordSaleCommissionAction` `pos_api/src/app/Actions/Device/Sync/RecordSaleCommissionAction.php:70-192`:
- Idempotent: one breakdown per order ever `:72-75`.
- Base = COLLECTED = grand − gifted `:87-91`; fully-gifted → no rows. Channel split card vs cash_bank `:96-141`; bank (acquirer) share only on 'card' money (bank_pos excluded — device maps “bank” labels first, `order_sync_payload.dart:44-51`); merchant takes exact per-channel remainder `:149-165` so Σ rows == collected to the baisa. Profile + percents snapshotted per row. `channel` column deploy-fallback `:200-205`. Commission is charged on the tax-inclusive collected amount (business decision). [V]

### 1.10 Loyalty
- Earn: `ApplyLoyaltyEarnAction` `pos_api/src/app/Actions/Device/Sync/ApplyLoyaltyEarnAction.php:35-78` — best-effort (null on unknown/paused rule or no customer); accrues on post-discount subtotal `:56`; account firstOrCreate.
- Redeem: `ApplyLoyaltyRedeemAction.php:35-71` — STRICT: no customer / unknown rule / no account / over-balance THROWS → fails the whole pay event (comment `:23-27` admits reconciling optimistic over-redeems is "a later refinement"). Ledger writer locks the account and forbids negative balances `WriteLoyaltyTransactionAction.php:42-53`. See finding F1.

### 1.11 Round-up donation
`DonationRecordHandler` `pos_api/src/app/Actions/Device/Sync/Handlers/DonationRecordHandler.php:46-224`: order resolved tenant-scoped; the donation attaches to the exact card leg via `payment_index` (rows inserted in array order) `:77-92, 197-223`; non-card leg → hard fail `:87-92`. Writes `pos_roundup_donations` + breadcrumbs on the payment (roundup_amount, charity_transaction_id) `:127-166`; forwards to the charity app AFTER commit, best-effort, stamping forwarded_at `:168-193`; **deferred when the order has any pending_reconciliation tender** (admin approval forwards it) `:94-105, 178`. [V]

### 1.12 Pending-reconciliation (force-recorded card) settlement
- Device: cashier force-records an ambiguous Soft POS charge → tender status `pending_reconciliation` (`pos_controller.dart:2916, 3036, 3113-3124`).
- Server: payment row flagged `PayOrderHandler.php:135, 150-152`; commission deferred `:193-203`; donation forwarding deferred.
- Admin twin: `pos_admin/src/app/Actions/Admin/Reconciliation/ApprovePendingReconciliationAction.php:50-87` — flips pending tenders (MarkPaymentReconciledAction) per order in a txn, then `ReconcileDeferredEffectsAction` records the commission split (idempotent) + forwards unforwarded donations (best-effort, outside the flip txn). [V]

### 1.13 Delivery-provider lifecycle (P-G7)
- Machine: `completeDeliveryOrder` `pos_controller.dart:2684+` (provider frozen at punch; reference required); payload emits create+deliver (no pay) `order_sync_payload.dart:344-374`. Delivery orders carry no tax/discount/offer/comp/loyalty/round-up (device gates + server design `DeliverOrderHandler.php:33-37`).
- Server: `DeliverOrderHandler.php:51-137` — requires delivery-type order, tenant provider; geofence fail-closed `:94-96`; freezes provider name/commission% and expected payout (grand − cut) `:100-123`; status → `pending_verification` (closed_at NOT set — revenue dated at confirmation); **inventory consumed at punch inside the txn** `:125-127`.
- Merchant confirm: `pos_merchant/src/app/Actions/Pos/Deliveries/ConfirmDeliveryOrdersAction.php:54-144` — per order, lockForUpdate re-check under txn `:85-96`, status → paid, **opened_at + closed_at RE-DATED to confirmation** `:103-114` (punch moment preserved in delivery_punched_at), received/variance recorded, audit row; delivery commission recorded AFTER the flip (idempotent) `:133-137`.
- Void of a pending_verification order unwinds inventory like a paid one (`VoidOrderHandler.php:111-115`).
- pending_verification cannot be paid at the till (`PayOrderHandler.php:67-71,100-102`) nor upserted over (`CreateOrderHandler.php:86-92`). [V]

### 1.14 Void / cancellation
`VoidOrderHandler` `pos_api/src/app/Actions/Device/Sync/Handlers/VoidOrderHandler.php:60-145`:
- Company+branch scoped; already-void throws (sole idempotency); lockForUpdate + re-check in txn `:104-110`.
- Unwind when wasPaid (incl. pending_verification): inventory reverse (SKIPPED when void reason has affects_inventory=true — the food was made) `:89-99, 130`; loyalty inverse `adjust` rows with clawback clamped to remaining balance `:155-196`; round-up rows → void + payment breadcrumbs cleared (forwarded charity txns NOT reversed — manual charity-side op) `:204-220`; commission rows deleted UNLESS any row of the order is claimed by a payout/invoice (order-level guard; delete re-checks claim columns) `:245-265`. Items → status void `:125`. All in one txn. Tests cover reverse/claims (`DeviceSyncOrderTest.php:217, 983, 1020`). [V]

### 1.15 Held orders / transfer / dine-in / to-go
- Hold: machine holds locally (`_orderStorage` held records) + mirrors via `order.hold` (status=held, upsert-by-uuid, no geofence) `HoldOrderHandler.php:34-38`; re-hold replaces mirror; resume keeps uuid so the final create flips held→open `pos_controller.dart:2378-2379, 2436`; discard emits order.void `pos_controller.dart:2474-2486`.
- Transfer: send = `order.transfer` (held mirror + target stamp; target must be an active device at the SAME company+branch, not self) `TransferOrderHandler.php:38-78`; receive = `GET /device/transfers/incoming` + atomic `POST /device/transfers/{uuid}/claim` under row lock (claimable = open/held/kitchen; ownership reassigned; joined tables included HH-8) `DeviceTransfersController.php:31-142`. Machine pushes transfer ONLINE inline (not the outbox) `order_sync_payload.dart:507-514`.
- Dine-in: table sessions are device-local (`DiningTableSession`, head + linked seats) `pos_controller.dart:3722-3855`; server records table_id + `pos_order_tables` joined rows at create `CreateOrderHandler.php:238-265`; paid head frees linked seats `:3833-3851`. Server has no table-occupancy state of its own (derived from active orders). [I on merchant floor view — TableInsightsAction exists, not traced.]
- To-go: an order_type value only (`to_go`), no special lifecycle. [V]

### 1.16 Order/receipt numbering
- Server-authoritative sequential receipt number: `POST /device/orders/next-number` → `AllocateOrderNumberAction` `pos_api/src/app/Actions/Device/AllocateOrderNumberAction.php:44-105` — insertOrIgnore + SELECT FOR UPDATE + increment; per company/branch/day per merchant setting; crash can leak a number, never reuse `:34-36`. Devices fall back to a local counter offline; order.create's receipt_number is optional `CreateOrderHandler.php:118-121, 203-208`. [V]

### 1.17 Viewers & reports
- Device: `GET /device/orders/active` (open/held/kitchen) + `/history` (paid/pending_verification/void/refunded, paginated, opened_at-windowed) `DeviceOrdersController.php:34-119`. Branch report counts STATUS_PAID only `pos_api/src/app/Actions/Device/BuildBranchReportAction.php:51`.
- Merchant: `GET /api/orders` → `OrdersListAction` `pos_merchant/src/app/Actions/Pos/Reports/OrdersListAction.php:35-120` (tenant + branch-scope, status filter, totals over whole filtered set; pending_verification excluded from the banner unless filtered `:60-69`; per-order commission status + tender chips). Detail `OrderDetailAction` (items+addons+discount/comp/gift rows+payments+delivery block+commission). Reports cluster: 15+ actions (`ReportsController.php:53-70`), Sales report counts status=paid only (+refunded separately) `SalesReportAction.php:73-121`; COGS from frozen recipe snapshots; expenses cash-model (PD5) `:124-140`.
- Admin: `GET /admin/api/v1/orders` — platform-wide, company/status/date filters, totals banner excludes pending_verification unless filtered `pos_admin/src/app/Http/Controllers/Api/Admin/OrdersController.php:58-91`; sales summary drill `:41-56`. [V]

---

## 2. Handheld sales path & asymmetries

`pos_handheld/lib/services/order_sync_service.dart`:
- `buildOrderEvents` `:235-458` — **money consistency BY CONSTRUCTION**: subtotal = Σ(unit_baisas × qty) computed in integer baisas `:262-284`; grand DERIVED = subtotal − discount − comp + tax `:360-364`; last tender absorbs rounding `:377-397`. The machine instead converts independently-rounded doubles and leans on the server's ±1 tolerance.
- Comp/gift rows sum exactly (gift first, reasoned remainder) `:286-317`; offers clamped with the manual slice absorbing `:319-358`; source `handheld` `:408`.
- Durable outbox = SharedPreferences JSON `order_outbox_v1`, persisted BEFORE network `:766-873`; local order log mirrored after `:875-915`.
- **Stuck-batch parking**: server rejections (not network errors) count; after 5 the batch parks RED in the drawer for manual retry (`kMaxServerRejections`, `applyServerRejection`, `retryStuck`) `:180-227`. The machine has NO parking — it retries forever with only lastError/Sentry (`order_sync_repository.dart:150-208`).
- Void event id is DETERMINISTIC `order-void-$orderUuid` `:612-631` (replays dedupe); the machine mints a fresh uuid per build (`order_sync_payload.dart:564`).
- Hold/transfer parity `:471-604` (order block minus payment; transfer pushed inline).
- Delivery parity: create+deliver `:952-1066`.
- Handheld has NO charity round-up (`donation.record` absent) and no rear-display; order types quick/to_go/delivery/dine_in (`main.dart:167-172`); plate rides drive-up orders as plate_number.
- Handheld claim-transfer completes against the server's held uuid `:834-837`.
- Neither device sends order_type `car`; `Order::TYPES` includes it (`pos_api/src/app/Models/Order.php:46`) — server-only vocabulary. `STATUS_KITCHEN` is never written by any handler (only appears in ACTIVE/CLAIMABLE lists). [V]

---

## 3. Answers to the key charter questions

1. **Does the server recompute/validate totals or trust the device?** Trusts the device (snapshot-authoritative, §9.1.6). Validates only: header additive invariant ±1 baisa (`CreateOrderHandler.php:627-638`), comp rows == comp_total exactly (`:531-535`), tender sum == grand ±1 (`PayOrderHandler.php:168-171`), tenant identity of every reference, geofence. Does NOT validate: Σ line_total == subtotal; qty×unit_price == line_total; Σ discount rows == discount_total; prices against catalogue; tender amounts ≥ 0. [V]
2. **Partial failure mid-pay?** Impossible to half-settle: payments + status flip + inventory + commission + loyalty run in ONE transaction; a throw stamps the event `failed` and rolls everything back; failed events re-dispatch on re-push (`SyncEventDispatcher.php:82-97`, `IngestSyncEventsAction.php:68-75`). [V]
3. **Can an order be paid twice?** No: unique client_event_id dedupe + in-txn lockForUpdate/status re-check (`PayOrderHandler.php:85-102`); tests at `DeviceSyncOrderTest.php:242, 271`. `order.deliver` lacks the equivalent in-txn recheck (finding F3).
4. **Statuses** — open, held, kitchen (dead), paid, pending_verification, void, refunded (`Order.php:27-43`). Filtering: device active=open/held/kitchen, history=paid/pv/void/refunded; sales reports = paid (+refunded); admin/merchant list banners exclude only pending_verification (voids included — finding F8); branch report = paid only. `refunded` is defined + filtered everywhere but no code path in pos_api ever SETS it (no refund flow; VoidOrderHandler deliberately writes no refund rows `:44-51`). [V]

---

## 4. Findings

### F1 [P1] Strict loyalty redeem inside the pay transaction can permanently strand a real, till-collected sale
- `pos_api/src/app/Actions/Device/Sync/ApplyLoyaltyRedeemAction.php:35-59` throws on no-customer / unknown rule / no account; `pos_api/src/app/Actions/Pos/Loyalty/WriteLoyaltyTransactionAction.php:48-53` throws on over-balance. Called inside `PayOrderHandler.php:224-231` → the WHOLE order.pay fails and rolls back (no payment rows, no inventory, order stays open) although the discount was already granted and the money physically taken at the till.
- The failure is deterministic (balance spent on another device meanwhile, or clawed back by a void), so every re-push re-fails: machine retries forever (`pos_machine/lib/data/order_sync_repository.dart:150-208`, no parking); handheld parks it as a red "stuck sale" after 5 rejections (`pos_handheld/lib/services/order_sync_service.dart:186-206`). Server books permanently miss the sale. The code comment acknowledges the reconciliation path is "a later refinement" (`ApplyLoyaltyRedeemAction.php:23-27`). VERIFIED (code path; no runtime repro).

### F2 [P1] Item-level cancellation of a PAID order is local-only on the machine — server books never see it
- `pos_machine/lib/state/pos_controller.dart:2604-2677`: partial cancels write `OrderCancellationRecord`s into the LOCAL snapshot ('Partially Canceled') and update local storage only. Only `cancelFullOrder` emits `order.void` (`:2657-2670`). There is no wire event for a partial cancel/refund anywhere in pos_api (dispatcher handles whole-order `order.void` only, `SyncEventDispatcher.php:60-76`).
- Result: server revenue, inventory, commissions and merchant/admin reports keep the full amounts while the device's local history/Z-view shows a partial cancellation and its amount (`_snapshotItemCancellationAmount` `:3931-3948`). Money divergence between the till's own record and every server report. VERIFIED.

### F3 [P2] `order.deliver` lacks the in-transaction lock + status re-check that order.pay/void have — concurrent duplicates can double-consume inventory
- `DeliverOrderHandler.php:76-137`: the "already settled" guard `:76-78` runs OUTSIDE the txn and the txn body updates + consumes without `lockForUpdate`/re-check. `PayOrderHandler.php:86-102` and `VoidOrderHandler.php:104-110` explicitly defend this exact race. Two order.deliver events with different client_event_ids (double punch, or a concurrent re-push re-dispatching a `failed` copy) can both pass the guard → `consume()` twice. VERIFIED (code asymmetry; race not reproduced).

### F4 [P2] Device money is fully trusted; pay tenders accept negative/non-validated amounts
- `PayOrderHandler.php:120-125` validates only `isset(method, amount_baisas)` + method whitelist — no `min:0`/integer rule (contrast comps `min:1` `CreateOrderHandler.php:613`). A tender list like [cash +10.000, card −5.000] balances the grand invariant, writes a negative payment row, drives `cardBaisas` negative and skews the channel split bases (`RecordSaleCommissionAction.php:96-141`). Likewise `change_given_baisas` unvalidated.
- Create-side: no check that Σ lines == subtotal or Σ discount rows == discount_total (see §3.1) — a rogue-but-authenticated device can under/over-report at will. Snapshot-trust is a DOCUMENTED design decision (`CreateOrderHandler.php:36-42`), so this finding is about the missing cheap hardening (sign/sum checks), not the architecture. VERIFIED.

### F5 [P2] Machine completion: GPS wait + customer API call happen BEFORE the durable outbox write — crash window loses the server push
- `staff_pos_screen.dart:361-449`: `_handleOrderCompleted` awaits `Geolocator.getCurrentPosition` (≤5 s + fallback) `:381-399` and `saveCustomer` (network, unbounded by outbox) `:408-421` BEFORE `OrderSyncRepository.enqueue` performs its "DB write before any network I/O" (`order_sync_repository.dart:22-24`). A crash/kill in that window leaves the sale saved locally (`pos_controller.dart:3226`) but never queued; nothing reconciles local history back into the outbox. The handheld persists the batch immediately in `enqueueCompletedOrder` (`order_sync_service.dart:866-873`) but computes GPS earlier in its own flow ([I] its pre-enqueue window not fully traced). VERIFIED for the machine.

### F6 [P2] Cross-device held-order resume is server-ready but no client consumes it
- Server: `GET /device/orders/active` returns held mirrors "resume / pay" (`routes/api.php:100`, `DeviceOrdersController.php:19-70`); `HoldOrderHandler.php:20-21` says "so other devices can resume it"; the machine even documents a dropped cart's mirror as "resumable/discardable from the held list of any branch terminal" (`pos_controller.dart:3865-3868`).
- Reality: `grep orders/active` over both device repos → zero call sites (`pos_machine/lib/services/pos_api_service.dart`, `pos_handheld/lib/services/pos_api_service.dart` expose only next-number / history / transfers). Held resume is local-store only; abandoned mirrors accumulate server-side as `held` forever (they do surface in transfers only when addressed). VERIFIED (absence by exhaustive grep).

### F7 [P3] Machine void event ids are not deterministic; futile-retry loop possible
- `order_sync_payload.dart:553-582` mints a fresh client_event_id per build; the outbox row `uuid:void` is upserted (`order_sync_repository.dart:100-105`, `app_database.dart:263-264`). A second void of an already-voided order (race with another terminal voiding the same uuid) produces a NEW event id → server throws 'order already void' (`VoidOrderHandler.php:78-80`) → row failed → machine retries forever. The handheld's deterministic `order-void-$orderUuid` (`order_sync_service.dart:620`) avoids this. UI guards (`isFullyCanceled`/`isServerTerminal` `pos_controller.dart:2521`) make it rare. VERIFIED (code); occurrence likelihood low.

### F8 [P3] Merchant + admin orders-list money banners include VOIDED/REFUNDED orders' grand_total
- `pos_merchant/src/app/Actions/Pos/Reports/OrdersListAction.php:65-69` and `pos_admin/src/app/Http/Controllers/Api/Admin/OrdersController.php:68-72` exclude only pending_verification from the totals sum; with no status filter the banner adds void/refunded rows' grand_total into a figure that reads as money. Consistent-with-rows but financially misleading. VERIFIED.

### F9 [P3] Discount rows are not validated to sum to discount_total (comps are) — machine clamping can make rows exceed the header
- Server: `writeDiscounts` has no sum check (`CreateOrderHandler.php:382-442`) while `writeComps` enforces exact equality `:531-535`. Machine: `discountAmount` clamps the COMBINED discount to rawSubtotal (`pos_controller.dart:1083-1084`) while the payload's line/offer rows keep full values and only the order-level slice is clamped ≥0 (`order_sync_payload.dart:199-217`) — when order-level + line + offers exceed the subtotal, Σ rows > discount_total_baisas. By-rule/by-offer report totals can then exceed the headline discount figure. VERIFIED (arithmetic path); no runtime repro.

### F10 [P3] Dead vocabulary: `kitchen` status and `car` order type are never produced
- `Order::STATUS_KITCHEN` (`Order.php:31`) appears only in ACTIVE/CLAIMABLE filters (`DeviceOrdersController.php:34`, `DeviceTransfersController.php:31`); no handler writes it. `car` ∈ `Order::TYPES` (`Order.php:46`) but machine maps everything else to quick (`order_sync_payload.dart:27-39`) and handheld's wire enum has no car (`main.dart:167-172`); drive-up rides `plate_number`. `refunded` similarly has no producer in pos_api. Harmless today; misleading for report consumers. VERIFIED.

### Informational (verified, by-design)
- Delivery confirmation RE-DATES `opened_at` to the confirmation moment (`ConfirmDeliveryOrdersAction.php:103-114`) — device history windows and daily reports shift the sale to confirmation day (punch preserved in delivery_punched_at). Deliberate ("revenue when money received").
- Commission is applied to the tax-inclusive collected amount (`RecordSaleCommissionAction.php:87-100`).
- Machine flush has no concurrency guard (enqueue + connectivity listener can flush concurrently) — safe because server dedupes; worst case a transient "not settled (statuses: received)" attempt (`order_sync_repository.dart:175-199`, `IngestSyncEventsAction.php:59-81`).
- Void reason `affects_inventory=true` keeps stock consumed (loss shows in Loss/Waste) `VoidOrderHandler.php:89-99`.
- Payout/invoice-claimed commission rows survive voids at ORDER granularity `VoidOrderHandler.php:245-265`.
- Machine order.create is only pushed at completion (with pay/deliver); open orders live only on-device until held/transferred — a bystander device's "active" view of the branch is holds+transfers, not live carts.
- Contract tests are extensive: `pos_api/src/tests/Feature/DeviceSyncOrderTest.php` (36 tests: exactly-once, double-pay, tenant guards, joined tables, gift tender, void unwind incl. claims), plus DeviceSyncHoldOrder/DeliverOrder/Donation/Loyalty/Commission/OrderTransfer tests. [V]
