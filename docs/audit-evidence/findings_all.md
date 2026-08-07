# WF1 consolidated findings

## F1 [P0] Handheld outbox lost-write race: a sale enqueued during an in-flight flush is silently erased  _(agent: audit-offline-sync, verified: True)_
The handheld money outbox is one SharedPreferences value rewritten wholesale. flush() snapshots the batch list at entry, spends seconds pushing over the network, then writes back 'remaining' computed from that stale snapshot without re-reading. Any enqueue (completed order, delivery, hold/void) that lands during the flush window appends to the prefs list, but flush's final _writeOutbox(remaining) overwrites it - the new batch is deleted before ever being pushed. Its trailing flush() call no-ops because of the _flushing guard. The order-log row stays synced:false forever with no re-enqueue path: revenue, inventory deduction, loyalty and commission for that sale never reach the server. Window = entire flush duration (largest exactly when draining an offline backlog on reconnect while new sales are rung). Two overlapping enqueues race the same way. pos_machine is immune (per-row Drift updates).

- Evidence: pos_handheld/lib/services/order_sync_service.dart:1179-1276 (flush snapshot at 1183, blind write-back at 1271, _flushing guard at 1180-1181); enqueue writers at 866-873, 1103-1110, 1164-1171
- Risk: Permanent silent loss of a completed sale's money/stock record while the customer was charged; drawer and Z-report desync; unrecoverable without manual re-keying.

## F2 [P0] PLACEHOLDER-NONE  _(agent: audit-reporting, verified: True)_
No P0 found in reporting charter; listed to be removed if schema disallows. Reporting reads never mutate money; worst issues are misstatement, not corruption.

- Evidence: n/a
- Risk: none

## F3 [P1] Money/gating logic duplicated by hand across pos_handheld and pos_machine  _(agent: map-pos_handheld, verified: True)_
All pricing-relevant logic (offer engine, tax rounding, discount/comp clamping, stock gating, receipt totals, sync payload invariants) exists in two codebases synced only by manual parity ports. Drift already exists in both directions (round-up donations machine-only; outbox parking handheld-only) and machine-side money fixes (caefd36, 5aea76b) have no propagation path.

- Evidence: pos_handheld/lib/services/offer_engine.dart:3-5 ('ported VERBATIM'); commit f02d437; pos_handheld/lib/models/catalog.dart:646-650,731-825 vs pos_machine equivalents; diffs: pos_api_service 1024 ln, session_service 424 ln, mosambee 556 ln
- Risk: The two POS surfaces can charge or report different totals for the same merchant config after any single-sided change

## F4 [P1] Step-10 hourly retry sweep is never scheduled — failed forwards on settled orders retry never  _(agent: map-charity, verified: True)_
RetryRoundupForwarding (donations:retry-roundup-forwarding) exists and is documented as the hourly sweep, but no Schedule::command registration exists (routes/console.php registers only ScanExpiringCompanyDocumentsJob) and no schedule:run runner/cron/supervisor exists in any docker compose or ops file across the pos repos. A round-up whose inline forward failed on a fully-settled order (never touched by the reconciliation path) keeps forwarded_at NULL forever and the donation never reaches the charity system. Host-level crontab outside the repos cannot be ruled out.

- Evidence: pos_admin/src/app/Console/Commands/RetryRoundupForwarding.php:15-48; pos_admin/src/routes/console.php:14-17; pos_admin/docker-compose.prod.yml (no schedule:run; grep verified)
- Risk: Customer-donated money recorded in pos_roundup_donations but permanently absent from charity_transactions after any transient charity outage.

## F5 [P1] Mixed-tender commission double-pay leak admitted in schema; legacy rows uncorrected  _(agent: audit-db-schema, verified: True)_
The channel migration's docblock states the confirmed leak: a mixed card+cash order recorded one whole-order merchant-residual row in pos_sale_commissions; payouts claimed it whole and paid the merchant the cash slice the platform never held. The new 'channel' column (card/cash_bank/'all') is explicitly 'step one'; every pre-existing row defaults to channel='all' and no backfill or correction migration exists for payouts already issued against mixed orders.

- Evidence: pos_admin/src/database/migrations/2026_08_06_010000_add_channel_to_pos_sale_commissions.php (docblock: 'the confirmed leak this migration is step one of fixing'); pos_admin/.../2026_07_01_010100_add_payout_id_to_pos_sale_commissions.php

## F6 [P1] pos_machine has no dead-letter, no cap and no UI for permanently-rejected outbox batches (the gap c5857d6 closed only on the handheld)  _(agent: audit-offline-sync, verified: True)_
Machine flush() retries every pending row on every run with no rejection cap, no backoff and no parking. watchPending() exists but has zero consumers anywhere in lib/ - no pending badge, no stuck tile, no lastError surfacing; only a single first-rejection Sentry warning. Every permanent server rejection (strict loyalty over-redeem after an offline race between two devices, deleted customer/table, money-invariant drift, voided-order pay interleave, geofence failures) becomes an invisible zombie row hammering the server forever while the sale never settles server-side. The handheld commit c5857d6 explicitly called this 'the audit's known sharp edge' and fixed it there only.

- Evidence: pos_machine/lib/data/order_sync_repository.dart:150-209,224 (capless loop, unconsumed watchPending); app_database.dart:267-284 (no attempts cap, no purge); grep across lib/ shows no watchPending/pendingOutbox consumer; contrast pos_handheld/lib/services/order_sync_service.dart:175-227
- Risk: Real sales permanently unrecorded (no revenue, no stock deduction) with zero operator visibility on the primary POS.

## F7 [P1] Frozen-GPS geofence trap: an offline order enqueued without a fix at a fenced branch is rejected forever, not 'until a fix is obtained'  _(agent: audit-offline-sync, verified: True)_
_handleOrderCompleted falls back to enqueueing without gps when no fix is available, with a comment claiming the order 'stays queued until a fix is obtained'. But the payload is frozen into eventsJson at enqueue and flush() re-sends it verbatim; nothing ever re-enriches a queued payload with a fresh fix. CreateOrderHandler/PayOrderHandler fail closed on every replay ('a GPS fix is required at this geofenced branch'), so the sale is permanently unsettleable and, per the missing machine surfacing, invisible.

- Evidence: pos_machine/lib/screens/staff_pos_screen.dart:381-399 (fallback + wrong comment); order_sync_repository.dart:154-167 (verbatim re-push); pos_api PayOrderHandler.php:270-289 and CreateOrderHandler geofence enforcement
- Risk: Any GPS hiccup at a fenced branch converts a real sale into a permanently rejected batch: lost revenue record and stock never deducted.

## F8 [P1] Server events stranded at ack_status='received' by a worker crash can never settle and have no sweeper  _(agent: audit-offline-sync, verified: True)_
The SyncEvent row insert commits before the handler runs its own transaction. A worker kill/OOM/hard-timeout during the handler leaves the row 'received'. Ingest re-dispatches only 'failed' rows; 'received' rows just ACK duplicate/received forever. No console command or scheduled sweeper re-dispatches stale received rows (routes/console.php has only the default inspire command). The device retries forever (machine invisibly; handheld parks it as stuck after 5) but no retry can ever settle the sale - only manual DB surgery can.

- Evidence: pos_api/src/app/Actions/Device/IngestSyncEventsAction.php:66-101 (insert-then-dispatch, failed-only re-dispatch); SyncEventDispatcher.php:83-101; grep STATUS_RECEIVED shows no other consumer; pos_api/src/routes/console.php
- Risk: A crash at the wrong moment permanently strands a money event in a state neither client nor server will ever retry.

## F9 [P1] Deferred money effects fire on already-voided orders: commission rows written and void-flagged round-ups forwarded to charity  _(agent: audit-refunds-voids, verified: True)_
ReconcileDeferredEffectsAction never checks order status. A force-recorded (pending_reconciliation) card sale that the device later voids has no commission rows (deferred at pay, nothing for the void to delete) and its round-up rows are status='void' but forwarded_at=NULL. When the admin approves the charge (queue lists by pending tender with no void filter, PendingReconciliationController.php:55-59) or the bank-file matcher sweeps it (ReconcilePaymentsAction), recordCommission writes a full commission split for the VOID order and forwardDonations (filters only whereNull forwarded_at, no status check) forwards the voided donation to the external charity app as 'success'. Payout/invoice claiming excludes void orders so the rows can't be settled, but they pollute pos_sale_commissions aggregates and the charity forward is real external money with no clawback.

- Evidence: pos_admin/src/app/Actions/Admin/Reconciliation/ReconcileDeferredEffectsAction.php:80-97,146-152,205-213; pos_admin/src/app/Http/Controllers/Api/Admin/PendingReconciliationController.php:55-59; pos_api/src/app/Actions/Device/Sync/Handlers/VoidOrderHandler.php:204-220; containment: SettlementPendingAction.php:58-65, PendingCommissionInvoiceAction.php:40-47

## F10 [P1] Partial item void is device-local only — server books never learn, reason discarded  _(agent: audit-refunds-voids, verified: True)_
pos_machine's cancelCompletedOrder emits order.void only when cancelFullOrder=true; a partial (item) cancel just rewrites the local snapshot to 'Partially Canceled'. No sync event type exists for item void. For a PAID order: server keeps full amounts, no inventory restore for removed items, no loyalty/commission/round-up adjustment, merchant reports and Z unchanged. The dialog forces a void reason for partial cancels then drops it (OrderCancellationRecord has no reason field). Violates additions.txt:75-76 which requires reason capture for whole-order AND single-line voids.

- Evidence: pos_machine/lib/state/pos_controller.dart:2620-2676 (onOrderVoided only under cancelFullOrder), 2540-2551; pos_api/src/app/Actions/Device/Sync/SyncEventDispatcher.php:61-70 (no item-void event); pos_machine/lib/services/shift_summary.dart:8 ('partial cancels are not netted'); additions.txt:75-76

## F11 [P1] Strict loyalty redeem inside the pay transaction can permanently strand a till-collected sale  _(agent: audit-sales-flow, verified: True)_
ApplyLoyaltyRedeemAction throws on no-account/unknown-rule/over-balance and runs inside PayOrderHandler's transaction, so the whole order.pay rolls back (no payment rows, no inventory, order stays open) although the discount was already granted and cash/card taken at the till. The failure is deterministic (points spent on another device or clawed back by a void), so every offline replay re-fails: the machine retries forever with no operator surface beyond lastError; the handheld at least parks it as a red stuck sale after 5 rejections. The code comment admits reconciliation is 'a later refinement'.

- Evidence: pos_api/src/app/Actions/Device/Sync/ApplyLoyaltyRedeemAction.php:35-71; pos_api/src/app/Actions/Pos/Loyalty/WriteLoyaltyTransactionAction.php:48-53; pos_api/src/app/Actions/Device/Sync/Handlers/PayOrderHandler.php:224-231; pos_machine/lib/data/order_sync_repository.dart:150-208; pos_handheld/lib/services/order_sync_service.dart:186-206
- Risk: Real revenue permanently missing from server books (no payment, no inventory deduction, no commission); customer loyalty balance desync

## F12 [P1] Item-level cancellation of a PAID order is local-only on pos_machine — server books never adjusted  _(agent: audit-sales-flow, verified: True)_
cancelCompletedOrder with itemIndexes writes cancellation records into the device-local snapshot ('Partially Canceled') and local storage only; only full-order cancels emit order.void. No wire event for partial cancel/refund exists in pos_api (dispatcher handles whole-order void only). Server revenue, inventory, commission and all merchant/admin reports keep the full amounts while the till's own history shows the cancellation and a computed refund amount.

- Evidence: pos_machine/lib/state/pos_controller.dart:2604-2677 (partial path, no onOrderVoided), :2657-2670 (full-order-only void), :3931-3948 (local refund amount); pos_api/src/app/Actions/Device/Sync/SyncEventDispatcher.php:60-76 (no partial event type)
- Risk: Money divergence between device records and every server report; refunds given at the till are invisible to the platform

## F13 [P1] Handheld cash change is double-subtracted from expected cash (systematic false SHORT variance)  _(agent: audit-shifts-cash, verified: True)_
The handheld sends cash tenders with amount_baisas = NET amount applied to the bill (builder forces sum == grand_total, required by PayOrderHandler's tendered==grand check) AND separately sends change_given_baisas when the customer over-tenders. CloseShiftHandler then computes net cash = SUM(amount) - SUM(change_given), subtracting change from an amount that never contained it. Every over-tendered handheld cash sale understates expected cash (and the Z cash tender line) by exactly the change given, so the drawer reads SHORT at close. pos_machine is unaffected (never sends change_given). No pos_api test exercises change_given (DeviceSyncShiftTest::payCashEvent omits it).

- Evidence: pos_handheld/lib/services/order_sync_service.dart:60-75 (amountBaisas documented as NET, 'cash overpayment rides changeGiven, not the amount'), :377-397 (tender build adds change_given_baisas when change>0); pos_handheld/lib/screens/payment_screen.dart:453-457 (changeGiven: _changeDue); pos_api/src/app/Actions/Device/Sync/Handlers/CloseShiftHandler.php cash query (SUM(amount) - SUM(change_given)); pos_api/src/tests/Feature/DeviceSyncShiftTest.php:105-117 (no change_given coverage)
- Risk: Every handheld cash sale with change produces a false cash-short variance against the cashier; merchants chasing phantom shortages, cashier disputes

## F14 [P1] Machine drawer inheritance orphans a second cashier's sales from all shift attribution under shared shifts  _(agent: audit-shifts-cash, verified: True)_
pos_machine keeps the open shift across staff logout ('the next cashier inherits the drawer') and its startup gate skips the per-staff server probe whenever any local shift exists, so cashier B walks into the POS under A's shared shift without opening their own. Orders always carry the logged-in cashier's staff_id. The shared-shift close attributes only (a) the shift staff's orders and (b) staff-less orders on the opening device - B's orders match neither leg. B's cash physically enters A's drawer but is excluded from A's expected cash and Z (variance reads OVER; B's sales appear in no Z) unless B independently holds their own shift. The handheld does this correctly (probes per staff at every login). Additions §1.2's 'shared drawer configurable per branch' does not exist; shared_shift:true is hardcoded in both apps.

- Evidence: pos_machine/lib/services/session_service.dart:244-248 (clearStaff keeps shift); pos_machine/lib/screens/staff_startup_gate.dart:29-35; pos_machine/lib/screens/staff_pos_screen.dart:402,437 (staff_id = logged-in cashier); pos_api CloseShiftHandler::orderBelongsToShift; contrast pos_handheld/lib/screens/staff_login_screen.dart:157-192; pos_machine/lib/services/shift_payload.dart:70 and pos_handheld/lib/services/shift_service.dart:46 (hardcoded shared_shift)
- Risk: Cash sold by a second cashier on an inherited machine escapes every shift's drawer math and Z-report - unexplained OVER variances and unreported sales per shift

## F15 [P1] Bank reconciliation auto-match fails on every round-up card charge (roundup_amount ignored)  _(agent: audit-payments-rounding, verified: True)_
The Mosambee capture for a round-up sale is base+round-up (pos_controller charges payableTotal = ceil'd total), so the bank statement gross includes the donation; but pos_payments.amount stores only the base tender (tenders must sum to grand_total) with the round-up in payments.roundup_amount. BankReconciliationService matches statement gross against payment.amount alone with a <0.0005 OMR tolerance and never reads roundup_amount, so every donation-carrying charge lands in amount_mismatches with amount_difference == the round-up (up to 0.999 OMR), forcing manual handling of exactly the transactions the charity flow depends on and inviting wrong reject decisions.

- Evidence: pos_machine/lib/state/pos_controller.dart:1436-1447,2888-2893; pos_machine/lib/services/order_sync_payload.dart:286-311; pos_api/src/app/Actions/Device/Sync/Handlers/DonationRecordHandler.php:154-158; pos_admin/src/app/Services/Admin/BankReconciliationService.php:124,166-230,632-640 (no roundup reference anywhere in the service)
- Risk: Systematic false mismatches in the card-money control; round-up sales may be mis-flagged as not-arrived or wrong-amount, and the mismatch queue noise can mask real discrepancies.

## F16 [P1] pos_handheld can force-record card charges that provably never reached the bank (pre-caefd36 classification)  _(agent: audit-payments-rounding, verified: True)_
Handheld MosambeePaymentResult.isUncertain is still `!isSuccess && !isCanceled` with no neverReachedTerminal exclusion (stale comment claims 'Same semantics as pos_machine'). Its own bridge emits 'Mosambee application is not installed.', 'payment activity was not found.', 'Unable to launch...', and login failures — all reach _promptUncertain, which offers 'record as pending_reconciliation'. Only the missing-terminal-id case is preflighted. One tap books a paid card sale for money the acquirer never saw; it then sits in the admin reconciliation queue with no settlement row to ever match — the exact defect pos_machine fixed in caefd36.

- Evidence: pos_handheld/lib/services/mosambee_payment_service.dart:47-50; pos_handheld/lib/screens/payment_screen.dart:509-516,552-607; pos_handheld/android/app/src/main/kotlin/com/example/pos_handheld/MosambeeBridge.kt:218,262,271; contrast pos_machine/lib/services/mosambee_payment_service.dart:87-100
- Risk: Invented revenue on handheld terminals: fully-booked card sales with no bank transaction, unresolvable in reconciliation.

## F17 [P1] Handheld cash change is double-subtracted in shift close (expected_cash understated)  _(agent: audit-payments-rounding, verified: True)_
The handheld defines tender amount_baisas as the NET amount applied to the bill ('cash overpayment rides changeGiven, not the amount') and its single cash tender is forced to grandBaisas, while also emitting change_given_baisas. pos_api CloseShiftHandler computes net cash = SUM(amount) − SUM(change_given), subtracting change from an already-net amount. Every handheld cash sale with change understates expected_cash by the change amount, producing systematic 'over' variances (or masking equal-size shortages). The exact-sum tender rule proves amount must be net, so the server-side shift math is the incorrect side. pos_machine is unaffected (it never sends change_given).

- Evidence: pos_handheld/lib/services/order_sync_service.dart:56-75,381-397 (amount=net + change_given emitted); pos_handheld/lib/screens/payment_screen.dart:387-390,454-456; pos_api/src/app/Actions/Device/Sync/Handlers/CloseShiftHandler.php:65-76
- Risk: Wrong drawer variance on every shared shift containing handheld cash-with-change sales; cash-control reports systematically incorrect.

## F18 [P1] Round-up retry sweep would forward donations of REJECTED and VOIDED orders to charity (latent — sweep unscheduled)  _(agent: audit-payments-rounding, verified: True)_
pos_admin RetryRoundupForwarding eligibility checks only forwarded_at IS NULL + age ≥10min + linked payment not CURRENTLY pending_reconciliation. RejectPendingReconciliationAction flips pending tenders to status='failed' with pending_reconciliation=false and leaves the donation row status='pending'/forwarded_at NULL — the next sweep run would forward a charity donation for money the bank never received. Likewise VoidOrderHandler.reverseRoundup sets donation status='void' but the sweep ignores status, so a voided order whose inline forward had failed gets forwarded. Currently latent only because the command is not scheduled anywhere (see P2 finding).

- Evidence: pos_admin/src/app/Console/Commands/RetryRoundupForwarding.php:46-70; pos_admin/src/app/Actions/Admin/Reconciliation/RejectPendingReconciliationAction.php:59-64; pos_api/src/app/Actions/Device/Sync/Handlers/VoidOrderHandler.php:205-219
- Risk: Charity ledger records transactions for money that never arrived (rejected charges) or refunded sales (voids) the moment the sweep is ever run manually or scheduled.

## F19 [P1] Shift expected-cash double-subtracts change on handheld cash sales  _(agent: audit-financial-calc, verified: True)_
CloseShiftHandler computes net cash = SUM(amount) − SUM(change_given), but PayOrderHandler forces tender amount to be NET of change (Σ amounts must equal grand). The handheld sends change_given_baisas>0 on overpaid cash while its amount is already net, so every such sale understates expected_cash and the Z-report cash tender by the change amount, producing phantom OVER variances; merchant Shift Report inherits the stored value. Machine orders are unaffected (never send change), making the two devices' drawer math inconsistent. Contract tests only ever send change 0, so this is untested.

- Evidence: pos_api/src/app/Actions/Device/Sync/Handlers/CloseShiftHandler.php:66-77,171-183; pos_api/src/app/Actions/Device/Sync/Handlers/PayOrderHandler.php:168-171; pos_handheld/lib/screens/payment_screen.dart:387-389,454; pos_handheld/lib/services/order_sync_service.dart:56-59,394-395; pos_api/src/tests/Feature/DeviceSyncShiftTest.php:104-116
- Risk: Every handheld cash sale with change corrupts shift reconciliation (false over-variance) and understates cash tender totals

## F20 [P1] multi_buy offer pricing diverges between machine and handheld (machine overcharges)  _(agent: audit-financial-calc, verified: True)_
The machine's _applyMultiBuy marks the selected units consumed BEFORE checking the discount and then breaks, so an at/under-price set permanently starves later offers of those units; the handheld's port deliberately breaks BEFORE consuming, with an in-code comment calling the machine behaviour 'a real overcharge'. The same cart with the same offer list can therefore total differently depending on which device rings it (machine ≥ handheld). The rest of the engine is byte-identical logic.

- Evidence: pos_machine/lib/services/offer_engine.dart:200-238 (consume at 215-217, break at 224-227); pos_handheld/lib/services/offer_engine.dart:229-241
- Risk: Device-dependent customer pricing; machine customers can be overcharged relative to handheld for identical carts

## F21 [P1] Handheld ignores product/category-scope and auto-apply order discounts  _(agent: audit-financial-calc, verified: True)_
pos_handheld drops non-order-scope and auto_apply discount rules at catalog parse (returns null), so targeted product/category promotions and self-applying order rules that the machine auto-applies per line/order simply never fire on the handheld — the same merchant rule set prices the same cart differently per device, with the handheld charging full price.

- Evidence: pos_handheld/lib/models/catalog.dart:224-230 vs pos_machine/lib/state/pos_controller.dart:1089-1126 (line rules), 1208-1233 (auto order rules)
- Risk: Customer-visible price divergence between the two POS surfaces of the same branch; merchant promotions silently not honoured on handheld

## F22 [P1] Merchant and admin net_sales/net_profit ignore comp_total  _(agent: audit-financial-calc, verified: True)_
Devices define grand = subtotal − discount − comp + tax (comped/gifted food collects no money and no tax), but merchant SalesReportAction computes net_sales = gross − discount and folds it into net_profit, and admin AdminSalesReportAction does the same; comp_total appears nowhere in either. Comped/gifted revenue is thus reported as earned, overstating net sales and net profit by exactly the comp amount, while the Z-report and the device branch report deduct comps correctly — the surfaces disagree.

- Evidence: pos_merchant/src/app/Actions/Pos/Reports/SalesReportAction.php:96-101,114-115,158-160 (no comp reference in file); pos_admin/src/app/Actions/Admin/Reports/AdminSalesReportAction.php:76; contrast pos_api/src/app/Actions/Device/Sync/Handlers/CloseShiftHandler.php:161-171 and CreateOrderHandler.php:627-638
- Risk: Overstated merchant revenue/profit reporting for any company using comps or gifted items

## F23 [P1] All report date windows use UTC day boundaries; Oman business days are UTC+4  _(agent: audit-reporting, verified: True)_
Every merchant/admin/device report and dashboard parses bare YYYY-MM-DD dates into UTC startOfDay/endOfDay while orders are stored in UTC from devices in a UTC+4 market. Midnight-04:00 local sales land on the previous day's report; hour-of-day heatmaps are rotated 4 hours; day-close totals cannot match shift/drawer reality.

- Evidence: pos_merchant/src/app/Data/Reports/ReportFilter.php:67-68; pos_merchant/src/config/app.php:68; pos_machine/lib/services/order_sync_payload.dart:104,269; pos_admin/src/app/Http/Controllers/Api/Admin/SalesReportController.php:37-39; pos_api/src/app/Actions/Device/BuildBranchReportAction.php:42-43
- Risk: Systemic daily misattribution of revenue across every reporting surface; merchants reconciling against drawers/shifts will see persistent mismatches

## F24 [P1] Sales report never subtracts comps: net_sales/gross_profit/net_profit overstated  _(agent: audit-reporting, verified: True)_
Server invariant is grand_total = subtotal - discount - comp + tax, so comped money is never collected; but the Sales report computes net_sales = SUM(subtotal) - SUM(discount_total) and net_profit from that, with no comp_total term anywhere in the headline. Comping merchants see profit inflated by the full comp value.

- Evidence: pos_api/src/app/Actions/Device/Sync/Handlers/CreateOrderHandler.php:631-636; pos_merchant/src/app/Actions/Pos/Reports/SalesReportAction.php:115,122,159-160,179-214 (no comp key)
- Risk: Merchant P&L overstates realized revenue and profit; business decisions and tax-adjacent figures based on wrong nets

## F25 [P1] Pending-reconciliation card sales reported as finalized 100%-merchant income  _(agent: audit-reporting, verified: True)_
PayOrderHandler marks the order paid but defers commission-ledger recording when any tender is pending_reconciliation. SalesReportAction's commissionSettlement treats paid orders with no ledger rows as no-profile sales: full grand_total flows into merchant_net AND finalized_net with zero commission. Unconfirmed card money shows as realized cash-in-hand; figures silently restate after admin approval. Orders list contradicts this (shows the same orders as not finalized).

- Evidence: pos_api/src/app/Actions/Device/Sync/Handlers/PayOrderHandler.php:118-205; pos_merchant/src/app/Actions/Pos/Reports/SalesReportAction.php:523-544; pos_merchant/src/app/Actions/Pos/Reports/Support/SaleCommissionStatus.php:194-209
- Risk: Merchant sees possibly-never-collected card money as realized income; commission_total and net_profit understate during reconciliation window

## F26 [P2] Sync processing and broadcast run inline in the HTTP request (no queue)  _(agent: map-pos_api, verified: True)_
IngestSyncEventsAction dispatches every handler synchronously inside the push request, and DeviceSyncBroadcast is ShouldBroadcastNow. A device replaying an hours-long offline backlog runs order create/pay/void, inventory, commission, loyalty, and charity HTTP forwards all within one request against a 120/min limiter and PHP request timeout. Documented as deliberate (no queue worker in the container), but large backlogs risk timeouts mid-batch (per-event ACKs mitigate: already-settled events dedupe on retry).

- Evidence: pos_api/src/app/Actions/Device/IngestSyncEventsAction.php:97; pos_api/src/app/Events/DeviceSyncBroadcast.php:34
- Risk: Slow/timed-out sync pushes on large offline backlogs; charity HTTP forward adds up to 8s per donation event to the request.

## F27 [P2] Events stamped 'failed' are only retried if the device re-pushes; unknown event types are silently accepted  _(agent: map-pos_api, verified: True)_
A failed handler leaves ack_status=failed and relies on the device re-pushing the same client_event_id to retry; there is no server-side retry job or alerting. Separately, an event_type with no handler returns silently and the row stays 'received' forever — a typo'd or future event type from a device is accepted and never processed, with no failure signal beyond status='received' in the ACK.

- Evidence: pos_api/src/app/Actions/Device/IngestSyncEventsAction.php:59-75; pos_api/src/app/Actions/Device/Sync/SyncEventDispatcher.php:81-83
- Risk: Permanently stranded events (unsettled sales/inventory) if a device stops re-pushing or sends an unrecognized type.

## F28 [P2] pos_machine outbox lacks the parked/dead-letter handling handheld has  _(agent: map-pos_handheld, verified: True)_
Handheld parks repeatedly-refused batches after 5 server rejections, surfaces them red with manual retry and Sentry paging; pos_machine's order_sync_repository has no stuck/park/rejection mechanism, so a permanently-rejected machine batch retries forever silently.

- Evidence: pos_handheld/lib/services/order_sync_service.dart:186-227 vs pos_machine/lib/data/order_sync_repository.dart (grep 'stuck|park|rejection' — no dead-letter hits)
- Risk: Machine revenue records the server keeps refusing hammer forever with no operator surfacing

## F29 [P2] Mock catalog is sellable on an enrolled-but-unsynced device  _(agent: map-pos_handheld, verified: True)_
Products, categories and a 5% mock tax fall back to hard-coded mocks whenever the synced catalog is null — including a real activated device whose first config fetch failed; a mock cart line is even pre-seeded under the same catalog-null condition despite the comment claiming 'a real POS starts empty'. Sales against mock product ids would be server-rejected into a parked batch after cash was taken.

- Evidence: pos_handheld/lib/main.dart:545-569 (mock fallback), :211 (_mockTaxes 5%), :213+ (mock ids 1,2,...), :1047-1052 (demo cart seed guarded only by catalogStore.value == null)
- Risk: Real cash sales recorded against fictitious products/prices; parked unsyncable revenue

## F30 [P2] Charity round-up not offered on handheld card payments  _(agent: map-pos_handheld, verified: True)_
pos_machine records donation.record per rounding card leg (commit cbd4431); pos_handheld has zero donation code paths — only displays the server's round_up_baisas in the Z report.

- Evidence: grep 'donation|round-up' over pos_handheld/lib → only shift_report_screen.dart:208-210,497-499 (display); no payment-screen hits
- Risk: Charity round-up revenue silently unavailable on the handheld surface

## F31 [P2] Retry sweep passes null status — replayed settled round-ups can be filed as 'fail' at charity  _(agent: map-charity, verified: True)_
RetryRoundupForwarding forwards with status=null; charity's resolvePosRoundupStatus then falls back to receipt['status']==='success' else 'fail'. The stored bank_response often lacks a top-level status (the exact mis-filing the inline path was fixed for per DonationRecordHandler docblock), so a sweep-retried donation lands at charity as status 'fail' while pos_roundup_donations says 'success'. ReconcileDeferredEffectsAction correctly passes 'success'; the sweep should pass the donation's status.

- Evidence: pos_admin/src/app/Console/Commands/RetryRoundupForwarding.php:83-90; charity-laravel-api/src/app/Http/Controllers/CharityTransactionsController.php:1080-1093; pos_api/src/app/Actions/Device/Sync/Handlers/DonationRecordHandler.php:118-124
- Risk: Charity reporting undercounts successful donations; currently latent because of the P1 (sweep never runs).

## F32 [P2] Charity POS round-up endpoint is public and unauthenticated, honoring caller-supplied status/amount  _(agent: map-charity, verified: True)_
POST /api/donations-pos-roundup sits in the public throttle:120,1 group with no token/shared secret. store_pos_roundup trusts explicit status ('success' honored over receipt), arbitrary amount, pos_device_id and organization_id, creating charity_transactions + shares rows. Fabricated posts can inflate charity dashboards and per-organization share ledgers. Rate limiting is the only defense; no gateway allowlist verified.

- Evidence: charity-laravel-api/src/routes/api.php:46-55; charity-laravel-api/src/app/Http/Controllers/CharityTransactionsController.php:554-579,1080-1093
- Risk: Donation-record pollution / misattributed charity shares by any internet client.

## F33 [P2] Charity round-up retry sweep is never scheduled in-repo  _(agent: map-pos_admin, verified: True)_
Commit 1dcda22 added the 'hourly retry sweep' command donations:retry-roundup-forwarding (src/app/Console/Commands/RetryRoundupForwarding.php), but src/routes/console.php schedules only ScanExpiringCompanyDocumentsJob (dailyAt 02:00), and docker-compose.prod.yml defines no scheduler/cron/schedule:run service (only php-fpm, nginx, redis, one-shot migrate/deploy). Nothing in the repo runs schedule:run at all, so even the daily document scan has no visible runner. If no host crontab exists (unverifiable), failed charity forwards sit unforwarded forever — the exact bug the command was written to fix.

- Evidence: pos_admin/src/routes/console.php:14-17; pos_admin/src/app/Console/Commands/RetryRoundupForwarding.php:36-38; pos_admin/docker-compose.prod.yml:25-198 (no scheduler service; greps for schedule/cron/supervisord in docker/prod return nothing)
- Risk: Customer donations whose first forward failed are permanently stranded (forwarded_at stays NULL); daily document-expiry scan may also never run.

## F34 [P2] Money-path logic maintained as hand-synced twins with pos_api  _(agent: map-pos_admin, verified: True)_
RecordSaleCommissionAction and ForwardCharityDonationAction each carry a 'TWIN of pos_api ... keep in sync' doc-block; the deferred-approval path (admin) and the device-sync path (pos_api) must produce byte-identical money effects, but nothing enforces the sync — a change on one side silently diverges commission splits or charity forwards between the two entry paths.

- Evidence: pos_admin/src/app/Actions/Admin/Reconciliation/RecordSaleCommissionAction.php:15-19; pos_admin/src/app/Actions/Admin/Reconciliation/ForwardCharityDonationAction.php:13-17
- Risk: Silent divergence of commission math between admin-approved and device-recorded sales; documented as accepted cost, but no drift detection exists.

## F35 [P2] Manager fingerprint gate accepts any device-enrolled fingerprint  _(agent: map-pos_machine, verified: True)_
'Register manager' is one successful BiometricPrompt that sets a SharedPreferences bool; every later manager approval (cancel/comp/gift/discount/reprint/X-report) passes for ANY fingerprint enrolled in Android settings — no binding to a manager identity. The server-verified manager-PIN fallback exists but is explicitly online-only ('PIN approval needs a connection — use the fingerprint instead'), so offline manager gates reduce to device-enrolled biometrics. Mitigation depends on MDM locking fingerprint enrollment, which could not be verified here.

- Evidence: pos_machine/lib/services/manager_authorization_service.dart:23-35; pos_machine/android/app/src/main/kotlin/com/example/pos_machine/ManagerBiometricBridge.kt:56-81; pos_machine/lib/l10n/app_en.arb:1483
- Risk: A cashier who enrolls their own finger on the terminal can self-approve voids, comps, gifts and discounts while offline — unaudited write-offs.

## F36 [P2] Cleartext HTTP enabled in the release manifest  _(agent: map-pos_machine, verified: True)_
android:usesCleartextTraffic="true" sits in the MAIN manifest (added for dev in commit 82d60ae), so release builds also allow plain http. Combined with the operator-editable server base URL in Settings, a production terminal can be pointed at an http:// endpoint and will transmit the device Bearer token, staff PINs and order data unencrypted. Default release URL is https, so this is an exposure surface, not an active leak.

- Evidence: pos_machine/android/app/src/main/AndroidManifest.xml:21; pos_machine/lib/core/api_config.dart:17-30; pos_machine/lib/providers/providers.dart:158-172
- Risk: Credential/order interception if a terminal is (mis)configured to an http URL on a hostile network.

## F37 [P2] Customer-display touch is delivered to the staff POS (NP521 firmware bug)  _(agent: map-pos_machine, verified: True)_
On the Sunmi T3 PRO with the 10.1" USB customer display, the customer panel's digitizer stays associated to displayId=0: taps on the customer screen activate whatever is under the same coordinates on the operator screen. setScreenTpSwitch is received by com.sunmi.usbscreen but ignored. This breaks the charity round-up accept/decline (the one customer-facing input) and lets customers trigger arbitrary staff-POS actions. A complete support ticket with adb/dumpsys evidence is prepared in-repo; fix requires Sunmi firmware/SDK.

- Evidence: pos_machine/docs/sunmi-support-customer-display-touch.md (whole file); pos_machine/lib/screens/customer_display_screen.dart:1858
- Risk: Customers can unknowingly operate the staff POS; round-up consent cannot be safely collected on the rear screen on this hardware.

## F38 [P2] Delivery confirmation re-stamps pos_orders.opened_at - deliberate history rewrite  _(agent: audit-db-schema, verified: True)_
Per the delivery-lifecycle migration doc, revenue is dated to confirmation by re-stamping the order's opened_at when provider money is confirmed; every opened_at-windowed aggregate (sales reports, branch target windows) silently shifts, and the original sale moment survives only in delivery_punched_at. This is the one place the otherwise-strict snapshot/immutability model is intentionally broken.

- Evidence: pos_admin/src/database/migrations/2026_07_20_010000_add_delivery_lifecycle_fields.php:40-44

## F39 [P2] client_event_id globally unique on pos_orders and pos_roundup_donations despite the sync_events cross-tenant fix  _(agent: audit-db-schema, verified: True)_
2026_06_22 re-scoped pos_sync_events idempotency to (device_id, client_event_id) explicitly because a global unique let one tenant's device suppress another's event and read back its order id. The identical global-unique pattern remains on pos_orders.client_event_id and pos_roundup_donations.client_event_id, exposing the same cross-tenant collision class at row level (exact impact depends on pos_api's unique-violation handling - other charter).

- Evidence: pos_admin/.../2026_06_22_010000_scope_sync_events_idempotency_per_device.php (rationale); 2026_06_04_010000_create_pos_orders_table.php (client_event_id ->unique); 2026_06_18_010000_create_pos_roundup_donations_table.php (client_event_id ->unique)

## F40 [P2] Soft-delete + hard unique collision across ~13 tables blocks re-creating deleted entities  _(agent: audit-db-schema, verified: True)_
Only pos_products (sku/barcode) and pos_staff (staff_code) use pgsql partial uniques excluding deleted_at. pos_customers (company,phone), pos_ingredients/suppliers/product_categories/addon_groups/taxes/delivery_providers (company,name), pos_floors/pos_tables labels, void/comp reason codes, and expense-category keys all pair softDeletes with hard uniques that include trashed rows: soft-delete then re-create with the same natural key fails with a DB unique violation.

- Evidence: pos_admin/.../2026_06_01_010000_create_pos_customers_table.php (hard unique company+phone with softDeletes) vs 2026_05_27_040100_create_pos_products_table.php (partial unique WHERE deleted_at IS NULL)

## F41 [P2] No shift linkage anywhere: orders/payments carry no shift_id  _(agent: audit-db-schema, verified: True)_
grep across all 153 migrations finds zero shift_id columns outside pos_shifts. expected_cash/variance and per-shift money attribution must be reconstructed via (device/staff, time-window) joins; with HH-2 shared shifts spanning devices (is_shared, 2026_08_01) there is no referential anchor tying a payment to its owning shift.

- Evidence: pos_admin/.../2026_06_04_020100_create_pos_shifts_table.php (doc: ShiftAction computes expected from 'orders linked to this shift' - no link column exists); 2026_08_01_010000_add_shared_flag_to_pos_shifts.php

## F42 [P2] Admitted historical ledger-conservation holes never reconciled  _(agent: audit-db-schema, verified: True)_
Two migrations fix forward but leave drifted history: (a) legacy fulfilled restock requests (resolution NULL) credited branch stock with no central debit; (b) orders sold before component_snapshot_json restocked the LIVE component set on void, silently drifting pos_branch_product and the product ledger. No backfill/reconciliation migration corrects the affected balances.

- Evidence: pos_admin/.../2026_08_05_010100_add_resolution_to_pos_restock_requests.php ('legacy rows, which credited the branch without debiting anything'); 2026_08_05_010000_add_component_snapshot_to_pos_order_items.php ('silently drifting pos_branch_product stock and the product ledger')

## F43 [P2] Charity-DB coexistence rests on unenforced migration ordering plus cross-app FK coupling  _(agent: audit-db-schema, verified: True)_
Nine hasTable-guarded stubs create charity/marketing-owned tables (banks, commission_profiles, organizations, geo set, advertisers, content_assets) when absent; the 'charity migrates first' assumption is comment-only, and pos_admin-first on a fresh shared DB would make charity's own CREATE TABLE migrations fail. Real restrictOnDelete FKs from pos_devices into charity banks/organizations/commission_profiles also make charity-side deletes fail while POS references exist.

- Evidence: pos_admin/.../2026_05_25_015000_ensure_commission_profiles_stub.php; 2026_05_26_010000_ensure_banks_stub.php; 2026_06_27_000000_add_organization_id_to_pos_devices.php (restrictOnDelete)

## F44 [P2] GRN receiving never updates ingredient cost — COGS snapshots go stale  _(agent: audit-inventory, verified: True)_
Only the piece-purchase form (RecordPurchaseAction.php:219-229) implements Additions 2.4 step 4 (default_unit_cost = total_paid/units, loose-batch ratio update). The newer GRN pipeline (CreatePurchaseReceiptAction -> ReceiveAndDistributeIngredientStockAction -> ReceiveIngredientStockAction) knows the paid cost and quantity but stamps the OLD default_unit_cost on the movement and updates nothing (ReceiveIngredientStockAction.php:105-115). Grep confirms no other writer of default_unit_cost. Product cost_price is likewise only manual (UpdateProductAction/ImportProductsAction). Merchants using GRN exclusively sell against permanently stale ingredient costs: recipe snapshots at order create (CreateOrderHandler snapshotRecipe) freeze the stale cost into COGS, waste valuations, and variance money figures. No average-cost model exists anywhere (last-purchase-wins is the documented choice; the gap is the GRN path skipping it).

- Evidence: pos_merchant/src/app/Actions/Pos/Inventory/ReceiveIngredientStockAction.php:105-115; RecordPurchaseAction.php:219-229; pos_api/src/app/Actions/Device/Sync/Handlers/CreateOrderHandler.php:657-682
- Risk: Silently wrong food-cost, waste-cost and margin reporting for GRN-using merchants; the two purchase entry paths produce divergent cost states for identical purchases.

## F45 [P2] Day-end count reconciles against apply-time balance; queued offline sales double-deplete  _(agent: audit-inventory, verified: True)_
StockCountHandler computes expected = current pos_branch_stock at the moment the stock.count event is processed (StockCountHandler.php:134-138). The machine submits the count directly without first flushing its own OrderOutbox (stock_count_screen.dart:84-96; flush lives in order_sync_repository.dart:150 and is only triggered from staff_pos_screen timers/reconnect), and sales queued on OTHER offline devices (handheld) can land after the count. Those sales were already reflected in the physical count, so the sequence writes a reconciliation_variance waste for them AND replays their sale consumption afterwards — the branch balance ends up counted-minus-late-sales (double depletion) and waste is over-blamed. Mechanics fully verified; the loss scenario is timing-dependent (inferred).

- Evidence: pos_api/src/app/Actions/Device/Sync/Handlers/StockCountHandler.php:134-138; pos_machine/lib/screens/stock_count_screen.dart:84-96; pos_machine/lib/data/order_sync_repository.dart:150
- Risk: Stock silently understates and the variance/waste report over-reports on any day a count is submitted while sale events are still queued anywhere.

## F46 [P2] pos_machine offer engine overcharges on multi_buy edge; handheld fixed it, divergence never back-ported  _(agent: audit-loyalty-discounts, verified: True)_
In _applyMultiBuy, when a matching set's value is already at/below the offer price (discount <= 0), pos_machine marks the set's units consumed BEFORE breaking, starving later offers of those units; pos_handheld deliberately breaks before consuming and its code comment explicitly calls the machine behaviour 'a real overcharge'. The same cart + offers can price differently on the two POS surfaces, with pos_machine the incorrect one.

- Evidence: pos_machine/lib/services/offer_engine.dart:213-228 (consume loop precedes discount>0 check); pos_handheld/lib/services/offer_engine.dart:229-238 (comment: 'divergence from pos_machine... a real overcharge')
- Risk: Customer overcharge / cross-device price inconsistency for stacked promotions

## F47 [P2] Discount stacking evaluator is dead code; devices ship different semantics and ignore the stackable flag  _(agent: audit-loyalty-discounts, verified: True)_
pos_merchant EvaluateDiscounts implements the blueprint's stacking semantics (non-stackable-first, compounding percents) and is thoroughly tested, but its only callers are its own tests. Devices apply the single best product/category rule per line plus one order-level slot; no device code reads 'stackable' though it ships in the config bundle and is stored in Drift. Server never re-evaluates. The blueprint's 'both evaluators shared between server and device, identical results' exit criterion is unmet; a merchant configuring stackable rules gets silently different behaviour.

- Evidence: pos_merchant/src/app/Actions/Pos/Discounts/EvaluateDiscounts.php:88 (callers: only src/tests/Feature/Pos/EvaluateDiscountsTest.php); pos_machine/lib/state/pos_controller.dart:1072-1126; grep 'stackable' over pos_machine/lib + pos_handheld/lib matches only model/DB definitions
- Risk: Merchant-configured stacking intent silently ignored; offline/online parity requirement unfulfilled

## F48 [P2] Loyalty rule validity windows and all documented restrictions/expiry are enforced nowhere  _(agent: audit-loyalty-discounts, verified: True)_
pos_loyalty_rules stores validity_start/validity_end and its migration documents §5.8 restrictions (eligible_product_ids, eligible_category_ids, branch_scope_json, dow/time windows, max_redemption_per_order, customer_tag) plus spend-based expiry_days. None of it is implemented: server earn checks only status=='active'; both devices drop validity fields when building their LoyaltyRule models; zero references to any restriction key or expiry in pos_merchant/pos_api app code; no scheduled expiry job. Points/stamps never expire and a rule past validity_end keeps earning/redeeming until manually paused.

- Evidence: pos_admin/src/database/migrations/2026_06_08_010000_create_pos_loyalty_rules_table.php:17-27,53-55; pos_api/src/app/Actions/Device/Sync/ApplyLoyaltyEarnAction.php:46; pos_machine/lib/services/config_mapper.dart:949-957; pos_handheld/lib/models/catalog.dart:291-307; grep expiry_days|eligible_product_ids|max_redemption_per_order|customer_tag over pos_merchant/src/app + pos_api/src/app = 0 hits
- Risk: Unbounded loyalty liability; time-limited campaigns keep paying out past their end date

## F49 [P2] Offline over-redeem strands the order in a deterministic pay-fail retry loop with no reconciliation path  _(agent: audit-loyalty-discounts, verified: True)_
Devices redeem optimistically against cached balances (config-bundle snapshot). If the balance is stale (e.g. two devices redeem the same points offline), the strict server-side redeem throws, failing the whole order.pay event; the ingest layer re-dispatches FAILED events on every re-push, so it re-fails forever. The customer already received the discount on-device and the order stays paid locally but unpaid server-side (no inventory consumption, no commission, no earn). The code comment explicitly defers 'reconciling an optimistic over-redeem'.

- Evidence: pos_api/src/app/Actions/Device/Sync/ApplyLoyaltyRedeemAction.php:20-28 (strictness + deferral note); pos_api/src/app/Actions/Device/IngestSyncEventsAction.php:68-75 (failed events retried); pos_api/src/app/Actions/Device/BuildDeviceConfigAction.php:317-325 (balances 'volatile', offline redeem against cache)
- Risk: Books desync: device-paid order never settles server-side; silent revenue/inventory/commission gap until manually noticed

## F50 [P2] Shift close never drains the outbox first: expected cash, variance and the Z-report are frozen without queued offline sales  _(agent: audit-offline-sync, verified: True)_
Shift close is online-only on both apps and computes expected_cash + the Z summary temporally from server-side payment rows (captured_at between opened_at and closed_at). Neither app flushes the order outbox before closing, so sales still queued offline have no payment rows at close; when the backlog lands later its captured_at falls inside the already-closed window but the shift's stored expected_cash/variance/summary never update. The drawer reads 'over' and the Z under-reports. Device clock skew shifts attribution the same way (no skew check exists anywhere).

- Evidence: pos_api CloseShiftHandler.php:66-77,143-210 (temporal attribution); pos_machine/lib/screens/shift_close_screen.dart:56-71 (no flush before close); pos_machine/lib/services/shift_service.dart:13-16 (online-required); handheld flush call sites only at main.dart:1056,1081,3169
- Risk: Wrong cash-reconciliation records (false overs/shorts) whenever a shift closes with a sync backlog - the exact post-outage moment it is most likely.

## F51 [P2] Machine config poll resurrects locally-decremented shelf stock while sales are queued (handheld got the ordering fix, machine did not)  _(agent: audit-offline-sync, verified: True)_
The machine decrements finite shelf stock locally after each sale and lets /device/config overwrite it with the server balance. Its 60s poll and reconnect handler pull config without draining the outbox first (reconnect even fires syncConfig and flush concurrently unawaited), so a poll landing while sales are still queued restores shelf counts the queued sales already consumed, re-enabling oversell of cooked/unit items. The handheld explicitly drains the outbox before its config poll for exactly this reason ('gating-review fix').

- Evidence: pos_machine/lib/screens/staff_pos_screen.dart:259-271 (poll without flush), 336-352 (concurrent unordered syncConfig+flush); app_database.dart:286-299 (local decrement, config overwrite); contrast pos_handheld/lib/main.dart:3178-3195
- Risk: Overselling sold-out cooked/unit items right after reconnect; stock ledger and reality drift.

## F52 [P2] Machine mints fresh client_event_ids per retry for inline money-adjacent events: shift.close dead-end and double-expense risk (handheld uses stable ids)  _(agent: audit-offline-sync, verified: True)_
Machine shift.close builds a new random client_event_id per attempt, so a retry after a lost ACK gets 'shift already closed' and a local/server shift desync (handheld deliberately uses deterministic 'shift-close-$shiftUuid'). Machine expense.log/restock.request are pushed inline with a fresh uuid per service call, so a cashier resubmitting after an ambiguous timeout records the expense twice (handheld ops screens cache _eventId ??= _newEventId() per form for exactly-once).

- Evidence: pos_machine/lib/services/shift_payload.dart:76-94 and expense_restock_payload.dart (gen() per call) + expense_restock_service.dart:30-78 (inline pushSync); contrast pos_handheld/lib/services/shift_service.dart:52-66 and ops_screens.dart:179,315,487,642
- Risk: Duplicate petty-cash expense records on retry; shift-close retries dead-end with the local shift stuck open.

## F53 [P2] Customer/table deleted while an order sits in the outbox still permanently fails order.create (deliberate residue of bf0bf72)  _(agent: audit-offline-sync, verified: True)_
bf0bf72 made products/add-ons withTrashed, but assertReferencesInTenant still resolves customer_id and table_id strictly (no withTrashed), so a soft-deleted customer or removed table turns a queued offline sale into a permanent rejection - parked-but-visible on the handheld, invisible forever on the machine. The commit marks this deliberately out of scope; the device customer store's soft-delete revival (50d9803) reduces but does not eliminate the customer leg.

- Evidence: pos_api/src/app/Actions/Device/Sync/Handlers/CreateOrderHandler.php:323-333; commit bf0bf72 message ('Customer/table references stay strict for now')
- Risk: A routine merchant cleanup (deleting a customer or table) can strand real offline sales permanently.

## F54 [P2] Void never reverses the tender: expected_cash counts voided orders' cash; cash returned to customer is unrecordable  _(agent: audit-refunds-voids, verified: True)_
VoidOrderHandler intentionally leaves pos_payments untouched, and CloseShiftHandler's expected-cash and tender queries sum success payments with no order-status join. A cash sale voided mid-shift still inflates expected_cash; returning the cash to the customer produces an unexplained drawer shortage since no refund/cash-out record type exists. The device-local fallback Z excludes canceled orders' tenders entirely — the opposite convention — so offline fallback and server disagree about the same drawer.

- Evidence: pos_api/src/app/Actions/Device/Sync/Handlers/VoidOrderHandler.php:46-51 (docblock); pos_api/src/app/Actions/Device/Sync/Handlers/CloseShiftHandler.php:66-77,169-183; pos_machine/lib/services/shift_summary.dart:158-162

## F55 [P2] Card-paid void leaves customer charged with zero operator signal or tracking  _(agent: audit-refunds-voids, verified: True)_
No Soft POS reversal API exists (machine or handheld) and the void writes no refund obligation anywhere. The machine cancel dialog does not warn that voiding a card-paid order does not return the customer's money, and no report or queue lists voided card-paid orders needing manual refund. Books net to zero while the acquirer keeps the capture. Phase 7+ deferral covers the reversal itself, but the missing warning/tracking is a today-problem.

- Evidence: pos_machine/lib/services/mosambee_payment_service.dart:219-395 (pay-only API); pos_handheld/lib/screens/payment_screen.dart:1975; pos_api VoidOrderHandler.php:46-51; additions.txt:161-163

## F56 [P2] No server-side authorization or persisted attribution on order.void  _(agent: audit-refunds-voids, verified: True)_
Sync push is device-token auth; VoidOrderHandler validates no staff/position/manager approval and discards the staff_id/authorized_by the devices send (survives only in raw pos_sync_events payload_json). pos_orders has no voided_by column. Per-reason requires_manager is shipped in config but server-unenforced. Contrast: kitchen production cancel verifies a manager PIN server-side. spec.txt:444 expects the log to record who actually voided. Offline-first limits hard enforcement, but the approver could be persisted.

- Evidence: pos_api/src/app/Actions/Device/Sync/Handlers/VoidOrderHandler.php:60-99; pos_machine/lib/services/order_sync_payload.dart:551-582; pos_admin migration 2026_07_02...php:127-133 (only reason id/label added); pos_api/src/routes/api.php:132-140 (kitchen contrast); spec.txt:444

## F57 [P2] Void carrying a soft-deleted reason id fails permanently; device and server disagree forever  _(agent: audit-refunds-voids, verified: True)_
VoidReason uses SoftDeletes and VoidOrderHandler resolves the picked reason with a scope-respecting find() (no withTrashed, unlike CreateOrderHandler's product resolution). A reason deleted on the portal after a device queued an offline void makes the event throw on every re-push; the order stays paid/open server-side while the till shows it canceled. Stuck-retry consequence inferred from the failed-event re-push design.

- Evidence: pos_api/src/app/Models/VoidReason.php:8; pos_api/src/app/Actions/Device/Sync/Handlers/VoidOrderHandler.php:92-97; contrast CreateOrderHandler.php:142 (withTrashed); retry design: pos_api/src/tests/Feature/DeviceSyncOrderTest.php:325

## F58 [P2] order.deliver lacks the in-transaction lock/status re-check that pay/void have — concurrent duplicates can double-consume inventory  _(agent: audit-sales-flow, verified: True)_
DeliverOrderHandler checks 'already settled' outside the transaction and consumes inventory inside it without lockForUpdate + re-check. PayOrderHandler and VoidOrderHandler explicitly defend this exact race (two events with different client_event_ids, or concurrent re-dispatch of a failed copy). Two concurrent order.deliver events for the same order can both pass the guard and both run consume().

- Evidence: pos_api/src/app/Actions/Device/Sync/Handlers/DeliverOrderHandler.php:76-137 (guard :76-78 outside txn, no lock in txn) vs PayOrderHandler.php:86-102 and VoidOrderHandler.php:104-110
- Risk: Double inventory deduction on delivery orders under concurrency

## F59 [P2] Pay tenders accept negative/unvalidated amounts; create-side line/discount sums unchecked  _(agent: audit-sales-flow, verified: True)_
PayOrderHandler validates only isset(method, amount_baisas)+method whitelist — no min:0/integer rule (comps require min:1). A tender set like [cash +10.000, card −5.000] balances the grand invariant, writes a negative payment row, drives the card-channel base negative and skews the commission channel split. change_given_baisas also unvalidated. Create-side, sum-of-lines vs subtotal and sum-of-discount-rows vs discount_total are never checked. Snapshot-trust is documented design, but the cheap sign/sum hardening is absent.

- Evidence: pos_api/src/app/Actions/Device/Sync/Handlers/PayOrderHandler.php:120-125,160-171; RecordSaleCommissionAction.php:96-141; CreateOrderHandler.php:567-638 (no line/discount sum rules), :613 (comps min:1 contrast)
- Risk: A compromised device token can fabricate money shapes that corrupt commission/channel accounting while passing all invariants

## F60 [P2] Machine completion runs GPS wait + customer API call BEFORE the durable outbox write — crash window loses the server push  _(agent: audit-sales-flow, verified: True)_
_handleOrderCompleted awaits Geolocator (≤5s + fallback) and a saveCustomer network call before OrderSyncRepository.enqueue persists the batch. A crash/kill in that window leaves the sale saved in local history but never queued for sync, and nothing reconciles local history back into the outbox. The handheld persists the batch immediately on enqueue.

- Evidence: pos_machine/lib/screens/staff_pos_screen.dart:361-449 (GPS :381-399, saveCustomer :408-421, enqueue :433-445); pos_machine/lib/data/order_sync_repository.dart:22-24 (durability begins only at enqueue); pos_machine/lib/state/pos_controller.dart:3226 (local save)
- Risk: Sale exists on-device but never reaches server books after a crash at the wrong moment

## F61 [P2] Cross-device held-order resume is server-ready but no client calls GET /device/orders/active  _(agent: audit-sales-flow, verified: True)_
The server exposes /device/orders/active for resume/pay of held mirrors and code comments on both sides promise cross-device resume, but exhaustive grep shows neither pos_machine nor pos_handheld ever calls it (they use only next-number, history, transfers). Held mirrors are write-only; abandoned ones accumulate as 'held' rows server-side indefinitely; the machine even drops a resumed-then-cleared cart's uuid on the promise the mirror stays resumable elsewhere — which no client implements.

- Evidence: pos_api/src/routes/api.php:100; pos_api/src/app/Http/Controllers/Api/V1/Device/DeviceOrdersController.php:19-70; pos_api HoldOrderHandler.php:20-21; pos_machine/lib/state/pos_controller.dart:3865-3868; grep 'orders/active' over pos_machine/lib and pos_handheld/lib = zero call sites
- Risk: Blueprint §6.7 cross-device hold/resume incomplete; unbounded stale held rows pollute the branch's active list

## F62 [P2] Voided paid cash orders remain inside expected cash; no refund event exists  _(agent: audit-shifts-cash, verified: True)_
The close's cash sum filters payment status/attribution/time but not order status, and VoidOrderHandler deliberately writes no refund or negative payment (payments stay success). A paid-then-voided cash sale (machine supports cancelling completed orders and emits order.void) still counts into expected cash, so if the cash was returned to the customer the drawer reads falsely SHORT. There is no order.refund event type at all, so spec 7.1's 'explain the difference' has no mechanism for refund-shaped drawer differences.

- Evidence: pos_api/src/app/Actions/Device/Sync/Handlers/CloseShiftHandler.php (cash query, no order-status filter); pos_api/src/app/Actions/Device/Sync/Handlers/VoidOrderHandler.php (doc: 'A payment REFUND record ... intentionally NOT written'); pos_api/src/app/Actions/Device/Sync/SyncEventDispatcher.php:60-70 (no refund handler); pos_machine/lib/data/order_sync_repository.dart:76-108 (enqueueVoid)
- Risk: In-shift cash refunds on voided sales surface as cashier shortages; drawer reconciliation unreliable at any merchant that returns cash on voids

## F63 [P2] Shift close never drains or blocks on the pending offline order outbox  _(agent: audit-shifts-cash, verified: True)_
Both apps push shift.close directly over HTTP with no outbox flush and no pending-row guard beforehand. Sales completed offline can still sit in the durable outbox when the close settles; the server computes expected cash and the Z without them, the late events then land inside the already-closed window, and stored expected/variance/Z are never recomputed. Only manual merchant same-day reopen + re-close recovers.

- Evidence: pos_machine/lib/screens/shift_close_screen.dart:56-115 (no outbox reference); pos_machine/lib/screens/staff_pos_screen.dart:5237-5261 (_closeShiftThenLogout), :249,:345 (flush only at init/reconnect); pos_handheld/lib/screens/shift_report_screen.dart:79-105 (_startClose); pos_handheld/lib/services/order_sync_service.dart:767-873 (outbox, no drain-before-close)
- Risk: Closes after offline stretches report understated expected cash (false OVER) and understated Z totals that are permanently frozen

## F64 [P2] No branch-level end-of-day close/day lock; machine can keep selling under a shift closed from another terminal  _(agent: audit-shifts-cash, verified: True)_
EOD (spec 7.1 go-live blocker) exists only as per-staff/device shift close plus the merchant Shift Report - there is no business-day entity, no all-shifts-closed check, no day lock, and only cash is reconciled against a count (card/online totals are informational in the Z; card recon is the separate bank queue). Additionally, when the handheld closes a shared shift, the machine's local record only heals at its own close attempt - the live-sync handler ignores shift.close for state and the gate never re-probes - so a machine can ring sales under a closed shift; those sales fall after closed_at and are orphaned from every Z.

- Evidence: grep for day-close concepts across pos_api/pos_merchant app code (no hits beyond unrelated files); pos_machine/lib/providers/providers.dart:254-268 (live event -> config sync only); pos_machine/lib/screens/staff_startup_gate.dart:29-35 (no re-probe when local shift exists); pos_machine/lib/screens/shift_close_screen.dart:116-125 (heal only at close)
- Risk: Spec 7.1 blocker only partially satisfied; post-close sales escape all shift reporting

## F65 [P2] Spec's 'events tagged with shift_id' not implemented; expenses/restocks/waste have no shift linkage  _(agent: audit-shifts-cash, verified: True)_
No table in the entire schema carries shift_id (verified by migration grep). Order/payment attribution at close is temporal + staff/device identity, which works for the drawer, but pos_expenses (company/branch/staff/logged_at only), restock requests, waste and stock counts cannot be attributed to a shift except by branch+time heuristics. The merchant ShiftReportAction's own header admits per-shift card sales / top products (spec'd fields) are a follow-up.

- Evidence: grep shift_id over pos_admin/src/database/migrations/*.php (zero rows); pos_admin/src/database/migrations/2026_06_07_010000_create_pos_expenses_table.php:46-96 (no shift_id/device_id); pos_merchant/src/app/Actions/Pos/Reports/ShiftReportAction.php header doc; additions.txt:115-116
- Risk: Additions §1.2 shift-report drill-downs (sales by staff, comps, top products, per-shift expenses) cannot be built accurately without schema work

## F66 [P2] Petty-cash expenses never reduce expected drawer cash  _(agent: audit-shifts-cash, verified: True)_
Expenses are deliberately 'informational only - never in the drawer math' (documented on both server and machine). Blueprint 5.10 explicitly includes on-the-spot 'supplier cash payment' - money that typically leaves the till - so every such payment from the drawer surfaces as an unexplained SHORT variance while the expense prints one line above it on the same Z. No paid-from-drawer flag exists to distinguish.

- Evidence: pos_api/src/app/Actions/Device/Sync/Handlers/CloseShiftHandler.php (salesSummary doc); pos_machine/lib/services/shift_summary.dart:66-67,453-458; blueprint.txt:777-783
- Risk: Polluted variance figures at merchants using till cash for expenses; documented design decision, but operationally misleading

## F67 [P2] pos_machine post-charge crash window: captured card money can vanish with no server record and no recovery  _(agent: audit-payments-rounding, verified: True)_
After a successful Mosambee capture, completion runs: print receipt (awaited) → print kitchen ticket → save local history → fire-and-forget handler that first acquires GPS (up to 5s timeout) and only then persists the outbox row. An app kill/crash anywhere in that window leaves a charged card with no outbox entry; there is no mechanism to re-enqueue from local order history (grep for recovery paths: none). Unlike the pending_reconciliation flow, the sale is entirely invisible to pos_api and the admin queue — only the bank statement's db-missing bucket could surface it.

- Evidence: pos_machine/lib/state/pos_controller.dart:3200-3246 (ordering); pos_machine/lib/screens/staff_pos_screen.dart:380-449 (GPS before enqueue); pos_machine/lib/data/order_sync_repository.dart:22-24 (durability begins only at enqueue)
- Risk: Rare but unrecoverable: captured card money with no recorded sale server-side.

## F68 [P2] pos_machine: Mosambee LOGIN failure still classified uncertain — force-record offered for a charge never sent  _(agent: audit-payments-rounding, verified: True)_
A login-stage failure (bridge returns stage=login/status=failed 'Payment login failed.') matches none of neverReachedTerminal's patterns (code MISSING_TERMINAL_ID/BAD_ARGS or not-installed/not-found/unable-to-launch messages), so it is classified isUncertain and the cashier is offered 'Mark paid — pending reconciliation' even though no payment intent was ever sent to the acquirer. Same defect class caefd36 fixed, narrower trigger.

- Evidence: pos_machine/android/app/src/main/kotlin/com/example/pos_machine/MosambeeBridge.kt:352-380 (login failure payload); pos_machine/lib/services/mosambee_payment_service.dart:87-100 (patterns); pos_machine/lib/state/pos_controller.dart:3508-3515
- Risk: A failed-login card attempt can be booked as a pending card sale with no bank transaction behind it.

## F69 [P2] Charity round-up retry sweep is never scheduled — failed forwards sit unforwarded forever  _(agent: audit-payments-rounding, verified: True)_
donations:retry-roundup-forwarding (commit 1dcda22, 'hourly retry sweep') exists but is not registered in pos_admin's scheduler; routes/console.php contains only the document-expiry job, and no other reference to the command exists in src or deploy files searched. Inline forwards are deliberately best-effort, so any charity-app outage leaves pos_roundup_donations rows with forwarded_at NULL and nothing ever retries them (only the pending-recon approval path retries its own subset).

- Evidence: pos_admin/src/routes/console.php:14-17 (only ScanExpiringCompanyDocumentsJob); pos_admin/src/app/Console/Commands/RetryRoundupForwarding.php:33-35 (command exists); repo-wide grep for the signature found no scheduler/cron reference
- Risk: Customer donations recorded in POS never reach the charity ledger after a transient outage; per-branch charity reporting under-counts.

## F70 [P2] Round-up parity gap: pos_handheld has no charity round-up at all  _(agent: audit-payments-rounding, verified: True)_
The round-up feature (prompt, gate, donation.record emission) exists only in pos_machine. pos_handheld/lib contains zero donation/charity references, so card sales on handhelds never offer the round-up — a silent program coverage gap rather than a money bug.

- Evidence: grep 'donation|charity' over pos_handheld/lib returns no files; pos_machine round-up at lib/state/pos_controller.dart:1443-1461 and lib/services/order_sync_payload.dart:376-414
- Risk: Charity program silently absent on an entire device class; merchants may believe it is running fleet-wide.

## F71 [P2] t  _(agent: x, verified: True)_
d

- Evidence: e:1
- Risk: r

## F72 [P2] Reported COGS misses PD3b add-on consumption costs  _(agent: audit-financial-calc, verified: True)_
CreateOrderHandler writes ingredient_snapshot_json = NULL whenever the newer consumption_snapshot_json supersedes it, but the merchant COGS readers (RecipeSnapshotCost via SalesReportAction::cogs and ProductPerformanceReportAction) read only recipe_snapshot_json + the legacy ingredient_snapshot_json — never consumption_snapshot_json — while ConsumeInventoryAction DOES consume stock with those frozen unit costs. COGS/gross_profit therefore exclude the ingredient cost of every modern add-on option and disagree with the stock ledger.

- Evidence: pos_api/src/app/Actions/Device/Sync/Handlers/CreateOrderHandler.php:162-171,761-800; pos_merchant/src/app/Actions/Pos/Reports/Support/RecipeSnapshotCost.php:31-53; pos_merchant/src/app/Actions/Pos/Reports/SalesReportAction.php (cogs(), ~555-585); pos_api/src/app/Actions/Device/Sync/ConsumeInventoryAction.php:140-148
- Risk: Understated COGS and overstated gross profit for merchants using add-on stock-usage lines

## F73 [P2] Loyalty earn accrues full points on fully comped/gifted orders  _(agent: audit-financial-calc, verified: True)_
Earn base is subtotal − discount_total with comps never deducted, and the 'fully gifted earns nothing' guard only checks gift TENDERS with grand>0. Machine gifts/comps ride comp rows (grand becomes 0, single 0-amount cash tender), so the guard never fires and a customer earns full points/stamps on 100% written-off food — contradicting the documented intent in the same handler.

- Evidence: pos_api/src/app/Actions/Device/Sync/ApplyLoyaltyEarnAction.php:59-64; pos_api/src/app/Actions/Device/Sync/Handlers/PayOrderHandler.php:205-213; pos_machine/lib/services/order_sync_payload.dart:219-254
- Risk: Loyalty liability created by write-offs; code contradicts its own stated policy

## F74 [P2] No server check that discount rows sum to discount_total (comps are checked; discounts are not)  _(agent: audit-financial-calc, verified: True)_
CreateOrderHandler enforces Σ(comp rows)==comp_total exactly but never compares Σ(discounts[].amount_baisas) to discount_total_baisas, nor Σ(line_total) to subtotal, nor line_total to qty×unit_price. The machine's own clamp edge (order+line+offer discounts exceeding the subtotal) emits rows summing to more than discount_total, which the server accepts — desyncing the by-rule/by-offer discount reports (SUM of rows) from the sales report (stored discount_total).

- Evidence: pos_api/src/app/Actions/Device/Sync/Handlers/CreateOrderHandler.php:382-442 (no sum check) vs :461-536 (comps checked); pos_machine/lib/state/pos_controller.dart:1083-1084; pos_machine/lib/services/order_sync_payload.dart:199-217
- Risk: Internal report inconsistency and an unvalidated wire surface for buggy/compromised devices within the snapshot-authoritative design

## F75 [P2] Blueprint shared discount evaluator is dead code; stackable flag never used at the till  _(agent: audit-financial-calc, verified: True)_
pos_merchant's EvaluateDiscounts (baisas, non-stackable-first, stacking/compounding semantics) has no production callers — only tests. The machine implements different semantics (best single rule per line, single order-discount slot) and caches the stackable flag in Drift without ever reading it in pricing; the handheld supports no line rules at all. A merchant configuring stackable/non-stackable rules gets neither semantic on any device.

- Evidence: pos_merchant/src/app/Actions/Pos/Discounts/EvaluateDiscounts.php:60-88; grep: callers only tests/Feature/Pos/EvaluateDiscountsTest.php + DiscountsControllerTest.php; pos_machine/lib/models/pos_models.dart:816 + lib/data/db/tables.dart:301 (stored, zero pricing reads); pos_machine/lib/state/pos_controller.dart:1101-1112
- Risk: Spec/implementation drift: merchant-visible rule options silently ignored; three divergent discount semantics exist across the platform

## F76 [P2] Cross-repo 'keep in sync' twins for commission split and loyalty evaluation  _(agent: audit-financial-calc, verified: True)_
RecordSaleCommissionAction exists in both pos_api (device pay path) and pos_admin (reconciliation approval path) with an explicit 'TWIN — keep in sync' header; EvaluateLoyalty exists in both pos_merchant and pos_api ('ported verbatim'). Full diffs show both pairs are currently logically identical (enum/constant cosmetics only), but no shared package or cross-repo test guards them — any future edit to one side silently forks the money math.

- Evidence: pos_api/src/app/Actions/Device/Sync/RecordSaleCommissionAction.php vs pos_admin/src/app/Actions/Admin/Reconciliation/RecordSaleCommissionAction.php:15-20 (twin header; diff verified equivalent); pos_api/src/app/Actions/Pos/Loyalty/EvaluateLoyalty.php:11-17 vs pos_merchant/src/app/Actions/Pos/Loyalty/EvaluateLoyalty.php (diff verified equivalent); caller parity pos_admin ReconcileDeferredEffectsAction.php:158-193
- Risk: Structural duplication of settlement-critical money math with no drift guard

## F77 [P2] Handheld charges a mock 5% tax before first catalog sync; machine charges none  _(agent: audit-financial-calc, verified: False)_
The handheld falls back to a hardcoded 5% TaxInfo whenever no catalog has synced, while the machine's rule is 'no configured taxes ⇒ no tax'. If a sale is reachable on a freshly-activated handheld before its first config sync, it would charge tax the merchant never configured. Whether activation gating makes this unreachable was not verified.

- Evidence: pos_handheld/lib/main.dart:210-211,569 vs pos_machine/lib/models/pos_models.dart:142-145
- Risk: Possible incorrect tax charged during the activation window; unverified reachability

## F78 [P2] Loss/Waste 'shortfall' counts transfers-out and production consumption as unexplained loss  _(agent: audit-reporting, verified: True)_
total_depletion sums ALL negative branch movements (TransferOut, ProductionConsumption included) vs sales-only theoretical, so branch transfers and kitchen batches read as loss/theft signal. The newer PortionVariance report's docblock explicitly calls this 'the bug this avoids' — yet the buggy section still ships in Loss/Waste.

- Evidence: pos_merchant/src/app/Actions/Pos/Reports/LossWasteReportAction.php:123-141; pos_merchant/src/app/Actions/Pos/Reports/PortionVarianceReportAction.php:43-45; pos_merchant/src/app/Enums/StockMovementType.php (signed convention)
- Risk: False loss/theft alarms at transfer- or production-heavy branches; two reports contradict on the same variance

## F79 [P2] Inventory Consumption (and dashboard top-ingredients) counts manual adjustments as consumption  _(agent: audit-reporting, verified: True)_
CONSUMPTION_TYPES still includes Adjustment (self-described Phase-7 stand-in) though Phase-8 sale consumption is live. Manual adjust-downs inflate consumed, consumption_per_day, days_of_stock and trigger the >20% anomaly (theft) flag.

- Evidence: pos_merchant/src/app/Actions/Pos/Reports/InventoryConsumptionReportAction.php:38-47,149-159; pos_merchant/src/app/Actions/Pos/Reports/DashboardSummaryAction.php:61-65
- Risk: Distorted stock forecasting and false anomaly flags from routine corrections

## F80 [P2] COGS/margin excludes cooked and unit products and physical-item component costs  _(agent: audit-reporting, verified: True)_
COGS reads only recipe_snapshot_json + addon ingredient snapshots; pos_api writes NULL recipe snapshots for stock_mode cooked/unit, and component_snapshot_json carries no cost and is never read by reports. Cooked/bought-in products show zero COGS (100% margin) in Sales headline and Product Performance.

- Evidence: pos_merchant/src/app/Actions/Pos/Reports/SalesReportAction.php:556-582; pos_api/src/app/Actions/Device/Sync/Handlers/CreateOrderHandler.php:657-661; pos_admin/src/database/migrations/2026_08_05_010000_add_component_snapshot_to_pos_order_items.php; pos_merchant/src/app/Actions/Pos/Reports/ProductPerformanceReportAction.php:87-107
- Risk: Overstated gross margins for production/bought-in merchants; per-product margin ranking wrong

## F81 [P2] Orders viewers' money totals banner includes voided and unpaid orders by default  _(agent: audit-reporting, verified: True)_
Merchant OrdersListAction and admin OrdersController sum grand_total over the whole filtered set excluding only pending_verification; the UI default status filter is null, so voids and open/held orders count into the period money total.

- Evidence: pos_merchant/src/app/Actions/Pos/Reports/OrdersListAction.php:59-69; pos_merchant/src/resources/js/Pages/Merchant/Orders/Index.vue:29; pos_admin/src/app/Http/Controllers/Api/Admin/OrdersController.php:65-70
- Risk: Headline money figure misreads as revenue and never reconciles with the Sales report

## F82 [P2] Device branch report tender mix has no payment-status filter  _(agent: audit-reporting, verified: True)_
byMethod sums pos_payments for paid orders with no status predicate, unlike every merchant breakdown (status='success'). Failed retried legs double-appear and pending_reconciliation legs count as collected, breaking the report's own sums-to-gross claim.

- Evidence: pos_api/src/app/Actions/Device/BuildBranchReportAction.php:186-199 vs pos_merchant/src/app/Actions/Pos/Reports/SalesReportAction.php:369
- Risk: Device Reports screen tender mix disagrees with gross and with the merchant portal

## F83 [P2] Refund reporting is status-based and re-dated to opened_at (latent restatement bug)  _(agent: audit-reporting, verified: True)_
Refunded orders vanish retroactively from past gross_sales (live-status query) while refunds_total is windowed on the order's opened_at, not the refund date; a gross-minus-refunds reading double-subtracts. Currently latent: no pos_api code path writes STATUS_REFUNDED yet, and the behavior is asserted in tests as intended.

- Evidence: pos_merchant/src/app/Actions/Pos/Reports/SalesReportAction.php:73-92; pos_admin migration 2026_06_04_010000_create_pos_orders_table.php:123-130 (no refunded_at); pos_merchant/src/tests/Feature/Pos/SalesReportTest.php:146-163; pos_api grep shows no refund writer
- Risk: When refunds ship, historical reports silently restate and period nets double-count refunds

## F84 [P3] Order pricing is device-authoritative by design  _(agent: map-pos_api, verified: True)_
CreateOrderHandler trusts the device-computed money (subtotal/discount/tax/totals, per-line prices) and freezes it, validating invariants but not re-running discount/price evaluation (documented as blueprint section 9.1.6 snapshot-authoritative). This is a deliberate offline-first design, but it means server-side defenses against a compromised or buggy device rest on the invariant checks alone. Flagged for the cross-cutting security review; not a defect against spec.

- Evidence: pos_api/src/app/Actions/Device/Sync/Handlers/CreateOrderHandler.php:1-15 (class docblock)
- Risk: A hostile device with a valid token can post self-priced sales within invariant limits.

## F85 [P3] QR ordering, KDS, print agent, and waiter screen have no backend support in pos_api  _(agent: map-pos_api, verified: True)_
Explicit absence check per charter: no routes, controllers, or actions for customer QR ordering, kitchen display tickets (bump/recall/stations), a print agent, or a waiter surface. Present primitives that future work could build on: tables[].qr_token in the config bundle, the branch.{id} Reverb channel documented as the future 'POS / handheld / KDS feed', and kitchen PRODUCTION endpoints (batch cooking), which are not a KDS.

- Evidence: pos_api/src/routes/api.php:44-156 (full endpoint inventory); pos_api/src/app/Actions/Device/BuildDeviceConfigAction.php:757; pos_api/src/routes/channels.php:24
- Risk: Any roadmap item assuming these surfaces exist server-side will require new pos_api endpoints and contract tests.

## F86 [P3] Sentry ships disabled (empty production DSN)  _(agent: map-pos_handheld, verified: True)_
Telemetry is fully wired (device-identity tags, error scrubbing, outbox-parking pages) but _productionDsn is empty so nothing initializes until an owner creates the project or bakes SENTRY_DSN.

- Evidence: pos_handheld/lib/core/telemetry.dart:30; commit 5b3ef7d
- Risk: The parked-revenue Sentry page (the P2 mitigation) is a no-op in production today

## F87 [P3] Outbox is one SharedPreferences JSON blob; corrupt JSON silently discards all queued revenue  _(agent: map-pos_handheld, verified: True)_
The whole outbox list is rewritten per mutation; a jsonDecode failure or non-List returns [] which drops every queued batch, and write failures are swallowed.

- Evidence: pos_handheld/lib/services/order_sync_service.dart:769-795 (_readOutbox catch → [], _writeOutbox swallow)
- Risk: A single corrupted prefs string loses all pending offline sales without any signal

## F88 [P3] Shared default Mosambee terminal PIN '1321'; server-null clears a cached real PIN back to it  _(agent: map-pos_handheld, verified: True)_
Deliberate pos_machine parity, but a misconfigured device falls back to a shared default credential for SoftPOS auth.

- Evidence: pos_handheld/docs/INTEGRATION_CONTRACTS.md:83-88; test/terminal_pin_test.dart
- Risk: Terminal auth downgraded to a known default on admin misconfiguration

## F89 [P3] Coarse git history for a payments device  _(agent: map-pos_handheld, verified: True)_
Only 9 commits total; two named 'new' and one mega-commit contains the entire API + hardware integration, unlike pos_machine's granular history.

- Evidence: git log: 495d532, 9566c8b ('new'), a96c8b... 'Handheld POS: full API integration + KOZEN hardware bridges + CI'
- Risk: Weak change traceability/auditability

## F90 [P3] Promised charity-side UNION of pos_roundup_donations is not implemented  _(agent: map-charity, verified: True)_
Design docblocks say charity reporting 'UNIONs this table later', but no reference to pos_roundup_donations exists anywhere in charity-laravel-api or nuxt-dashboard. Charity visibility of POS round-ups depends entirely on HTTP forwarding succeeding, which amplifies the P1 gap. pos_admin has its own AdminRoundUpReportAction over the POS table.

- Evidence: pos_api/src/app/Actions/Device/Sync/Handlers/DonationRecordHandler.php:30-34; pos_admin/src/database/migrations/2026_06_18_010000_create_pos_roundup_donations_table.php (docblock); grep of charity-laravel-api/src and nuxt-dashboard: zero hits

## F91 [P3] Forwarder is duplicated as documented twins in pos_api and pos_admin  _(agent: map-charity, verified: True)_
pos_admin's ForwardCharityDonationAction is an explicit 'TWIN ... keep in sync' copy of pos_api's; diff today shows only comment differences. Accepted cost per docblock, but a drift risk for the payload contract (e.g. pos_reference/status semantics).

- Evidence: pos_admin/src/app/Actions/Admin/Reconciliation/ForwardCharityDonationAction.php:13-17 vs pos_api/src/app/Actions/Device/Sync/ForwardCharityDonationAction.php:258-334

## F92 [P3] SavedViews API is backend-only (no UI consumer)  _(agent: map-pos_merchant, verified: True)_
SavedViews CRUD routes and controller exist but no Vue code references them; grep for savedViews/saved-views across resources/js returns zero hits. Dead or future surface.

- Evidence: pos_merchant/src/routes/web.php:814-820; pos_merchant/src/app/Http/Controllers/Pos/SavedViewsController.php; grep of src/resources/js (no matches)

## F93 [P3] DeliveryProviders CRUD has no discovered management UI  _(agent: map-pos_merchant, verified: False)_
Provider create/update/delete endpoints exist, but the frontend api client (lib/api/deliveryProviders.ts) is imported only by Catalogue/ProductWizard.vue:83 and Catalogue/Index.vue:62 for per-product delivery prices; Deliveries/Index.vue imports only api/deliveries. Providers may be managed via pos_admin (not confirmed, outside charter).

- Evidence: pos_merchant/src/routes/web.php:903-909; src/resources/js/Pages/Merchant/Catalogue/ProductWizard.vue:83; src/resources/js/Pages/Merchant/Deliveries/Index.vue:34-40
- Risk: Merchants may be unable to onboard a new delivery channel from the portal

## F94 [P3] POS Settings hub misnamed as OrderCancellation  _(agent: map-pos_merchant, verified: True)_
Settings/OrderCancellation.vue (route /settings/order-cancellation) is the whole POS Settings hub containing order-cancellation positions, manager approval, reports positions, and kitchen positions sections — naming obscures the surface.

- Evidence: pos_merchant/src/resources/js/Pages/Merchant/Settings/OrderCancellation.vue:173,241,312,470; router.ts:361-363

## F95 [P3] Tenant global scope is intentionally no-op when unpinned  _(agent: map-pos_merchant, verified: True)_
BelongsToCompanyScope returns without filtering when MerchantTenantContext has no company (guests, console, queue, pre-binding). This is documented and compensated by pin-before-binding (Phase 2b commit 8563b27) and a scope-coverage test, but any new code path that queries company-owned models before the tenant is pinned silently sees all tenants.

- Evidence: pos_merchant/src/app/Models/Scopes/BelongsToCompanyScope.php (apply(): early return on null company); tests/Feature/TenantScopeCoverageTest.php

## F96 [P3] Repo state contradicts charter: clean tree, 2 unpushed commits  _(agent: map-pos_admin, verified: True)_
Expected ~150 dirty/untracked files; git status is clean, 216 commits total, main ahead of origin/main by 2 (ed4cd58 ad-billing device-proof, 33ca794 advertiser page copy). The previously-dirty work appears to have been committed but not pushed.

- Evidence: git status / git log --oneline in pos_admin (WSL) at audit time
- Risk: Unpushed ad-billing commits exist only on the local WSL clone.

## F97 [P3] Bank reconciliation supports exactly two banks, hardcoded  _(agent: map-pos_admin, verified: True)_
resolveBankConfig recognizes bank_id 2/name~dhofar (xlsx 'Table 1') and bank_id 1/name~'oman arab'/'oab' (CSV); any other bank throws 'parser is not configured'. Adding a bank requires a code change; the failure mode is safe (validation error, no bad matches).

- Evidence: pos_admin/src/app/Services/Admin/BankReconciliationService.php:232-286
- Risk: Onboarding a merchant on a third acquiring bank blocks reconciliation until a parser is written.

## F98 [P3] Payout / commission-invoice / ad-billing actions may skip audit logging  _(agent: map-pos_admin, verified: False)_
Grep for WriteAuditLogAction call sites (40 files) shows none under Actions/Admin/Payouts, Actions/Admin/Invoices, or Actions/Admin/AdBilling — mark-paid/void/create money events in those modules do not appear to write audit rows. Not fully traced (they might log through another mechanism), hence unverified at the 'definitely unaudited' level.

- Evidence: grep -rln WriteAuditLogAction src/app — no hits in pos_admin/src/app/Actions/Admin/{Payouts,Invoices,AdBilling}/
- Risk: Money-moving admin actions (mark payout/invoice paid, void) lack an audit trail.

## F99 [P3] Printed receipt hardcodes the label 'Tax (5%)'  _(agent: map-pos_machine, verified: True)_
The receipt prints row('Tax (5%)', money(order.tax)) — the amount is the dynamic company-tax total (multiple taxes, any rate, zero on delivery), but the label always claims 5%. Since commit 9f4a/9f1a603 taxes are config-driven, so any merchant with a non-5% or multi-tax setup prints a misleading (potentially compliance-relevant) tax label; tax-exempt delivery orders print 'Tax (5%) 0.000 OMR'.

- Evidence: pos_machine/lib/services/sunmi_receipt_service.dart:159; pos_machine/lib/state/pos_controller.dart:739-741,1338
- Risk: Incorrect tax rate stated on customer fiscal receipts.

## F100 [P3] Delta sync cannot remove deleted taxes / branch-stock rows / deactivated delivery providers  _(agent: map-pos_machine, verified: True)_
Self-documented in ConfigRepository: deltas carry no deleted-ids for taxes, branch_stock, or deactivated delivery providers; healing happens only on the FULL syncs run at device activation and staff login. The 60-second poll and Reverb-triggered syncs are delta-preferring, so a long-lived logged-in terminal keeps applying a deleted tax (or offering a deactivated provider) until the next re-login.

- Evidence: pos_machine/lib/data/config_repository.dart:62-64,65-133; pos_machine/lib/screens/staff_pos_screen.dart:259
- Risk: Stale taxes/providers applied to sales for up to a full shift after an admin removes them.

## F101 [P3] Kotlin package and MethodChannel namespaces still com.example.* after the applicationId rename  _(agent: map-pos_machine, verified: True)_
Release applicationId is net.mithqal.pos.machine, but native code lives in com.example.pos_machine and channels are named com.example.mosambee / com.example.manager_biometrics. Internal-only, no functional risk; cleanup/consistency item flagged during release hardening.

- Evidence: pos_machine/android/app/build.gradle.kts:49; pos_machine/android/app/src/main/kotlin/com/example/pos_machine/MainActivity.kt:1; pos_machine/lib/services/mosambee_payment_service.dart:220
- Risk: Cosmetic; potential confusion in crash reports and future refactors.

## F102 [P3] Test-suite pass state not re-verified  _(agent: map-pos_machine, verified: False)_
48 test files exist covering money-critical paths (card charge classification, charity gate, split plans, sync payloads, delta sync, offers, shifts). Per persistent memory there is a known baseline of 17 failures in charity-flow + widget tests; the suite was not re-run in this read-only audit, so the current state is unconfirmed.

- Evidence: pos_machine/test/ (48 files); user memory note flutter-test-baseline.md
- Risk: Regressions could hide inside the known-failure baseline.

## F103 [P3] Test-mirror drift: bank_fee missing from both mirrors, is_shared missing from merchant mirror  _(agent: audit-db-schema, verified: True)_
pos_payments.bank_fee (prod 2026_08_02) is absent from BOTH pos_api and pos_merchant test schemas; pos_shifts.is_shared (prod 2026_08_01) is absent from pos_merchant's mirror (present in pos_api's). Both mirrors otherwise track admin-written columns for shape parity (settled_amount, invoice_id, channel, applies_to verified present), so these are oversights that let tests run against a stale shape.

- Evidence: pos_api/src/database/migrations/0000_00_00_000000_create_test_schema.php (pos_payments block lacks bank_fee); pos_merchant/src/database/migrations/0000_00_00_000000_create_test_schema.php (pos_shifts block lacks is_shared; no bank_fee hit)

## F104 [P3] pos_marketing_impressions replay guard bypassed by NULL client_event_id, now feeding ad billing  _(agent: audit-db-schema, verified: True)_
The unique(device_id, client_event_id) replay guard has both columns nullable; Postgres treats NULLs as distinct so NULL-event rows are freely duplicable, and impressions now meter advertiser invoices (pos_ad_invoices).

- Evidence: pos_admin/.../2026_06_29_120000_create_pos_marketing_impressions_table.php (nullable uuid client_event_id + unique pair); 2026_08_06_010100_create_pos_ad_rate_cards_table.php (billing metered from impressions)

## F105 [P3] pos_loyalty_transactions.order_id never wired: no FK, no index  _(agent: audit-db-schema, verified: True)_
The create migration promises 'Phase 8 wires this to pos_orders'; no later migration touches the column. Order-to-loyalty lookbacks scan, and orphan order ids are possible.

- Evidence: pos_admin/.../2026_06_08_010200_create_pos_loyalty_transactions_table.php (unsignedBigInteger order_id, nullable + unconstrained; grep of all 153 migrations shows no later ALTER)

## F106 [P3] pos_company_settings ownership contradiction inside pos_admin's own chain  _(agent: audit-db-schema, verified: True)_
2026_06_29_010000 (pos_admin) creates the table unconditionally and documents it as admin-owned schema; 2026_08_04_010000 (also pos_admin) declares it 'OWNED by pos_merchant - the merchant portal created it' and guards with hasTable (a permanent no-op in pos_admin). The ownership record for this shared table is self-contradictory.

- Evidence: pos_admin/.../2026_06_29_010000_create_pos_company_settings_table.php vs 2026_08_04_010000_create_pos_company_settings_table_if_missing.php (contradictory docblocks)

## F107 [P3] Ledger append-only and snapshot immutability are application-convention only  _(agent: audit-db-schema, verified: True)_
No triggers, rules, CHECK constraints, or column privileges exist anywhere in the 153 migrations; any code bug or manual SQL can UPDATE/DELETE ledger rows (pos_stock_movements, pos_product_stock_movements, pos_loyalty_transactions, pos_customer_wallet_ledger, pos_sale_commissions) that the money model treats as immutable. pos_payments.captured_at also defaults to server-now (useCurrent), so offline tenders are money-dated at sync time unless pos_api always overwrites it (behavior not verified - other charter).

- Evidence: All create-table migrations in pos_admin/src/database/migrations (zero CREATE TRIGGER/RULE/CHECK statements); 2026_06_04_020000_create_pos_payments_table.php (captured_at useCurrent)

## F108 [P3] Transfer and waste overdraw checks are TOCTOU (no lock, pre-transaction)  _(agent: audit-inventory, verified: True)_
TransferStockAction reads the source branch balance before DB::transaction with no lockForUpdate (check :89-100, txn at :102); RecordWasteAction same pattern (:106-116 vs :122). A concurrent sale (which may legally drive stock negative) or a second transfer invalidates the check, letting the source go negative despite the explicit refuse-overdraw intent. Ledger invariant is unaffected (writes are blind increments). Contrast: AllocateRestockRequestAction and the production actions correctly lock rows before checking.

- Evidence: pos_merchant/src/app/Actions/Pos/Inventory/TransferStockAction.php:89-102; RecordWasteAction.php:106-122; correct pattern at AllocateRestockRequestAction.php:159-166
- Risk: Policy violation only (negative balances where the code promises none); confusing merchant-facing errors of omission.

## F109 [P3] No GRN void/correction flow  _(agent: audit-inventory, verified: True)_
Purchase-receipt routes are index/store/show/recordPayment only. A mis-entered GRN (wrong qty/cost/branch) has no reversal document: stock must be hand-adjusted per item, and the automatically booked expenses, tax amounts and AP payable rows have no linked unwind at all.

- Evidence: pos_merchant/src/routes/web.php:569-577; CreatePurchaseReceiptAction.php:100-161
- Risk: Entry mistakes permanently distort expenses/AP unless manually corrected in multiple places; stock and money corrections can diverge.

## F110 [P3] Day-end counts are not blind  _(agent: audit-inventory, verified: True)_
Both count surfaces display the on-book balance beside the entry field (machine: stock_count_screen.dart lists each ingredient with its balance; merchant Inventory page likewise). Staff can copy the expected number to zero out variance, defeating the single most important food-cost control the Additions doc builds the model around (2.8/2.11).

- Evidence: pos_machine/lib/screens/stock_count_screen.dart:13-14,124,160-171; pos_merchant SubmitStockCountAction.php:22-47 (no blind mode anywhere)
- Risk: Shrinkage/theft hides inside clean counts; the Portion Variance report loses its truth signal.

## F111 [P3] No negative-stock anomaly flagging found (Additions 2.6 expects it)  _(agent: audit-inventory, verified: False)_
Additions 2.6 states offline-replayed negative balances are 'permitted and flagged as anomalies'. Negative balances are permitted (sale path), and low-stock badges exist via min_stock_threshold, but greps over the merchant Inventory UI, dashboard and report actions found no dedicated negative-balance anomaly flag/badge/report filter. Absence not exhaustively provable.

- Evidence: greps over pos_merchant/src/resources/js/Pages/Merchant/Inventory/Index.vue and src/app/Actions/Pos/Reports (only variance-negative hits); ConsumeInventoryAction.php:26-28
- Risk: A branch running on a stale/negative book balance is invisible until someone counts.

## F112 [P3] Offline ingredient-mode oversell unbounded; ingredient balances never depleted locally  _(agent: audit-inventory, verified: True)_
Both devices deplete unit/cooked shelf counts locally after each sale (clamped at 0), but ingredientBalances used for ingredient-mode gating are only ever replaced on config sync (machine pos_controller.dart:250,705 — no other mutation; handheld identical). A device offline for hours keeps selling recipe products against a frozen balance with no warning; consistent with the negative-stock policy but silent. Additionally the gate checks one unit's requirement, not the cart quantity (pos_controller.dart:855-861).

- Evidence: pos_machine/lib/state/pos_controller.dart:250,705,848-865; pos_machine/lib/data/app_database.dart:286-305; pos_handheld/lib/main.dart:707-737
- Risk: Deep negative ingredient balances after offline stretches; front-of-house sells items the kitchen cannot make.

## F113 [P3] Pre-Phase-A restock fulfilments created stock from nothing; never backfilled  _(agent: audit-inventory, verified: True)_
Before the 2026-07-28 Phase A change, restock fulfilment credited the requesting branch with no debit anywhere (acknowledged verbatim in the action docblock and the resolution-column migration: 'Before Phase A, fulfilment credited the branch with no debit anywhere — stock appeared from nothing'; legacy rows keep resolution NULL). No corrective backfill exists, so historical inflow totals and any opening-balance math spanning that era overstate stock.

- Evidence: pos_merchant/src/app/Actions/Pos/Inventory/AllocateRestockRequestAction.php:28-31; pos_admin/src/database/migrations/2026_08_05_010100_add_resolution_to_pos_restock_requests.php:24-26
- Risk: Historical ledger/report distortion only; current flows are conserved.

## F114 [P3] Server never validates redemption economics, only balance coverage  _(agent: audit-loyalty-discounts, verified: True)_
ApplyLoyaltyRedeemAction checks the account balance covers the points/stamps spent, but never that the redemption meets min_redemption_points, aligns to redemption_points blocks, or that the discount OMR granted on the order matches redemption_value x blocks. The monetary value was folded into discount_total at order.create and is trusted snapshot-authoritatively, so a tampered device could redeem 1 point for an arbitrary discount.

- Evidence: pos_api/src/app/Actions/Device/Sync/ApplyLoyaltyRedeemAction.php:37-75 (no config checks); pos_api/src/app/Actions/Device/Sync/Handlers/CreateOrderHandler.php:36-38,627-638 (snapshot-authoritative, invariant only)
- Risk: Device-trust hole: loyalty value redemption unverifiable server-side (consistent with the documented §9.1.6 trust model, but wider than the discount case because a ledger debit legitimises it)

## F115 [P3] Loyalty earn base ignores comps: written-off portions still earn points  _(agent: audit-loyalty-discounts, verified: True)_
Earn eligible amount = subtotal - discount_total; comp_total is not subtracted. A mostly-comped order earns full points on the comped portion even though the money was written off. Only a 100%-gift-tender order is suppressed (server and both devices).

- Evidence: pos_api/src/app/Actions/Device/Sync/ApplyLoyaltyEarnAction.php:56; pos_api/src/app/Actions/Device/Sync/Handlers/PayOrderHandler.php:211-213 (gift-only suppression)
- Risk: Minor loyalty over-accrual on comped sales; policy inconsistency with the gift rule

## F116 [P3] No permission gate on ad-hoc manual discounts at the till  _(agent: audit-loyalty-discounts, verified: True)_
Any signed-in cashier can apply a custom discount up to 100% (percent capped at 100; fixed amount only clamped to subtotal) with just a free-text reason. Manager biometric approval applies only to catalogue rules flagged requires_manager_approval. Spec Part 7.1 pairs discount permissions with the audit log as go-live controls; only the audit half (reason + by-staff reporting) exists on devices. Same on the handheld.

- Evidence: pos_machine/lib/screens/staff_pos_screen.dart:3158-3209 (manager gate only for flagged rules), :13045-13100 (_DiscountDialog free entry, reason required); pos_handheld/lib/main.dart:1716-1736; spec.txt:444-445 (Part 7.1 audit-log/permissions pairing)
- Risk: Discount abuse deterred only by after-the-fact reporting, not prevented

## F117 [P3] Vestigial 'loyalty' payment method in the API contract  _(agent: audit-loyalty-discounts, verified: True)_
Payment::METHODS includes 'loyalty' and pos_machine maps any payment label containing 'loyalty' to it, but no current flow tenders loyalty - redemption is implemented as a discount plus a loyalty_redeem ledger debit. Dead contract surface that could mislead future integrations into double-counting redemption as tender.

- Evidence: pos_api/src/app/Models/Payment.php:44; pos_machine/lib/services/order_sync_payload.dart:41-52
- Risk: Contract ambiguity; low direct impact

## F118 [P3] order.deliver lacks the in-txn lockForUpdate + status re-check that pay/void have; plus minor hygiene items  _(agent: audit-offline-sync, verified: True)_
DeliverOrderHandler checks the terminal status unlocked and then consumes inventory inside the txn without re-reading under lock - the exact concurrent-different-id race the team documented and fixed in PayOrderHandler/VoidOrderHandler. Exposure is narrow (one deliver event per outbox row; same-id races dedupe at ingest). Related hygiene: machine outbox rows are never deleted after sync (unbounded growth); Drift createdAt is whole-second so same-second rows have unspecified flush order (self-healing); handheld silently drops corrupt outbox rows (order_sync_service.dart:1200); machine flush has no reentrancy guard (harmless, server dedups).

- Evidence: pos_api DeliverOrderHandler.php:76-80,109-138 (no lock) vs PayOrderHandler.php:91-104; pos_machine app_database.dart:260-284 (no purge); tables.dart:242 (second-precision createdAt)
- Risk: Theoretical double inventory consumption on a concurrent deliver replay; slow unbounded local DB growth.

## F119 [P3] reverseLoyalty clamps against an unlocked balance read — race fails the whole void, self-healing on retry  _(agent: audit-refunds-voids, verified: True)_
The earn-clawback clamp reads LoyaltyAccount without a lock; WriteLoyaltyTransactionAction re-reads under lockForUpdate and throws if a concurrently-spent balance makes the stale-clamped delta go negative, rolling back the void transaction. Device re-push re-clamps, so worst case is a delayed void.

- Evidence: pos_api/src/app/Actions/Device/Sync/Handlers/VoidOrderHandler.php:164-178; pos_api/src/app/Actions/Pos/Loyalty/WriteLoyaltyTransactionAction.php:44-54

## F120 [P3] Handheld cannot void paid orders; DonationRecordHandler lacks an order-void guard  _(agent: audit-refunds-voids, verified: True)_
pos_handheld's order history screen exposes reprint only — paid-order voids are machine-only (parity gap, intent unverified). Separately, DonationRecordHandler never checks the order isn't void, so a late/replayed donation.record after a void would insert a pending donation for a void order (improbable under per-device FIFO outbox; client_event_id blocks true replays).

- Evidence: pos_handheld/lib/screens/order_history_screen.dart (no cancel affordance); pos_handheld/lib/main.dart:1544-1605 (current-cart void only); pos_api/src/app/Actions/Device/Sync/Handlers/DonationRecordHandler.php (no STATUS_VOID reference)

## F121 [P3] Machine void events mint fresh client_event_ids — a duplicate void loops as a permanent outbox failure  _(agent: audit-sales-flow, verified: True)_
buildOrderVoidEvent generates a new uuid per build and the uuid:void outbox row is upserted; a second void of an already-voided order (race with another terminal) yields a new event id the server answers 'order already void' → failed → retried forever (machine has no stuck parking). Handheld uses deterministic 'order-void-$orderUuid' which dedupes to the original result. UI guards make occurrence rare.

- Evidence: pos_machine/lib/services/order_sync_payload.dart:553-582; pos_machine/lib/data/order_sync_repository.dart:100-105; pos_api VoidOrderHandler.php:78-80; pos_handheld/lib/services/order_sync_service.dart:612-631
- Risk: Noisy permanent retry loop and a forever-pending badge for an already-settled void

## F122 [P3] Merchant and admin orders-list money banners include voided/refunded orders' grand_total  _(agent: audit-sales-flow, verified: True)_
Both totals queries exclude only pending_verification from the summed grand_total; with no status filter, void and refunded rows are summed into a banner that reads as money. Consistent with visible rows but financially misleading next to reports that count paid-only.

- Evidence: pos_merchant/src/app/Actions/Pos/Reports/OrdersListAction.php:65-69; pos_admin/src/app/Http/Controllers/Api/Admin/OrdersController.php:68-72; contrast SalesReportAction.php:78-81 (paid-only)
- Risk: Operators/merchants read inflated totals including cancelled sales

## F123 [P3] Discount rows never validated against discount_total; machine clamping can make rows exceed the header  _(agent: audit-sales-flow, verified: True)_
writeDiscounts has no sum check (comps enforce exact equality). The machine clamps the combined discount to rawSubtotal while line/offer rows keep full values and only the order-level slice clamps ≥0 — when stacked discounts exceed the subtotal, the audit rows sum above discount_total_baisas, so by-rule/by-offer report totals can exceed the headline discount figure.

- Evidence: pos_api CreateOrderHandler.php:382-442 (no sum check) vs :531-535 (comps exact); pos_machine/lib/state/pos_controller.dart:1083-1084; pos_machine/lib/services/order_sync_payload.dart:199-217
- Risk: Discount reports can disagree with sales-report headline discounts

## F124 [P3] Dead vocabulary: 'kitchen' status, 'car' order type, and 'refunded' status have no producers  _(agent: audit-sales-flow, verified: True)_
STATUS_KITCHEN appears only in ACTIVE/CLAIMABLE filter lists — no handler writes it. 'car' is in Order::TYPES but the machine maps everything unrecognised to 'quick' and the handheld's wire enum has no car (drive-up rides plate_number). 'refunded' is filtered everywhere but no pos_api code path ever sets it (VoidOrderHandler deliberately writes no refund records).

- Evidence: pos_api/src/app/Models/Order.php:31,43,46; DeviceOrdersController.php:34; DeviceTransfersController.php:31; pos_machine/lib/services/order_sync_payload.dart:27-39; pos_handheld/lib/main.dart:167-172; VoidOrderHandler.php:44-51
- Risk: Misleading schema vocabulary for report consumers; refunds_total in SalesReport is permanently zero

## F125 [P3] Machine close retry loses the reconciliation result (handheld already fixed this)  _(agent: audit-shifts-cash, verified: True)_
The machine mints a fresh client_event_id per close attempt, so a close whose response was lost in flight, then retried, hits 'shift already closed' and silently heals - the cashier never sees expected/variance/Z and no Z auto-print happens (the server did store the counted cash). The handheld derives the close id from the shift uuid ('shift-close-$uuid') so a retry dedupes and returns the stored reconciliation; the machine should adopt the same scheme.

- Evidence: pos_machine/lib/services/shift_payload.dart:82 (gen() per attempt); pos_machine/lib/screens/shift_close_screen.dart:116-125 (silent heal); pos_handheld/lib/services/shift_service.dart:51-71 (deterministic id + rationale)
- Risk: Occasional lost Z-report/variance display on flaky networks; data intact server-side

## F126 [P3] Minor spec gaps: shift notes, expense receipt photos, tips, cash denominations  _(agent: audit-shifts-cash, verified: True)_
pos_shifts.note exists but neither device offers the spec'd optional open/close note; pos_expenses.receipt_photo_path is accepted on the wire but neither device captures photos; tips-at-shift-close is unimplemented (consistent with its later-phase priority in additions); no cash-denomination rounding exists in either app and no spec requirement was found (5% VAT can produce 1-baisa-precision totals physical coinage cannot tender - unspecified behavior, machine takes cash at exact total with no change UI).

- Evidence: pos_admin/src/database/migrations/2026_06_04_020100_create_pos_shifts_table.php (note column); pos_machine/lib/services/shift_payload.dart:46-94 (no note field); grep receipt_photo over both device repos (zero hits); additions.txt:196-199 (tips, later phase); grep denom/rounding over pos_machine/lib (round-up copy only)
- Risk: UX/completeness gaps, not money corruption

## F127 [P3] Discount rows are not sum-validated against discount_total_baisas (comps are)  _(agent: audit-payments-rounding, verified: True)_
CreateOrderHandler exact-checks Σ(comp rows)==comp_total_baisas but performs no equivalent check for discounts; rows are only individually min:0. Device-side clamping (combined discount clamped to rawSubtotal; order-level slice clamped ≥0) can make Σ(discount rows) ≠ discount_total_baisas, so by-rule/by-offer reports built from rows can diverge from order totals.

- Evidence: pos_api/src/app/Actions/Device/Sync/Handlers/CreateOrderHandler.php:530-532 (comps exact) vs 591-598 (discounts per-row only); pos_machine/lib/services/order_sync_payload.dart:185-217 (clamped derivation)
- Risk: Report-level discount attribution can drift from the order's booked discount total.

## F128 [P3] order.pay tender amounts have no min:0/integer validation; negative legs would be accepted  _(agent: audit-payments-rounding, verified: True)_
PayOrderHandler checks each tender only for a valid method and presence of amount_baisas; a device bug emitting a negative last leg (the wire forces last = grand − Σ(previous), and cart-edit locking during an active split is UI-level only) would be stored as a negative payment while still passing the Σ==grand check.

- Evidence: pos_api/src/app/Actions/Device/Sync/Handlers/PayOrderHandler.php:120-131; pos_machine/lib/services/order_sync_payload.dart:288-302; UI gating at pos_machine/lib/screens/staff_pos_screen.dart:542,674,704,830
- Risk: Corrupt tender rows (negative amounts) possible from a buggy or hostile device; reports and reconciliation would silently absorb them.

## F129 [P3] Hardcoded default terminal PIN '1321' and AES password-token key baked into both APKs  _(agent: audit-payments-rounding, verified: True)_
MosambeePaymentService ships defaultTerminalPin '1321' (used when no per-device PIN is cached) and the bridge embeds the AES key used to build the Mosambee login password token ('same AES key used by the working charity app integration'). Present identically in pos_machine and pos_handheld. Flagged for the security agent's charter; listed here because it is the card-charge credential path.

- Evidence: pos_machine/lib/services/mosambee_payment_service.dart:224-233; pos_machine/android/app/src/main/kotlin/com/example/pos_machine/MosambeeBridge.kt:24-26 (twin files in pos_handheld)
- Risk: Anyone with the APK can derive login tokens for any terminal id still on the default PIN.

## F130 [P3] Sub-baisa drift between charged card amount and recorded tender can trip the 0.0005 recon tolerance  _(agent: audit-payments-rounding, verified: True)_
The handheld charges the screen-computed double total while the wire grand is re-derived from independently-rounded baisas components (and on the machine, a split's last card leg absorbs rounding); a 1-baisa divergence is possible, and BankReconciliationService's sameMoney tolerance (<0.0005 OMR) treats a 0.001 difference as a mismatch. Rare edge; surfaces as occasional spurious amount_mismatches.

- Evidence: pos_handheld/lib/screens/payment_screen.dart:525-527 (charges _total) vs lib/services/order_sync_service.dart:360-397 (derived grand + last-leg absorb); pos_admin/src/app/Services/Admin/BankReconciliationService.php:632-640
- Risk: Occasional manual reconciliation work for legitimate charges.

## F131 [P3] change_given is NULL for all machine orders and OrderItem line_total doc is wrong  _(agent: audit-financial-calc, verified: True)_
The machine wire never carries change_given (display-only), so pos_payments.change_given is populated only by handheld sales — any change-based analysis is device-skewed. pos_merchant's OrderItem model documents line_total = qty × unit_price − line_discount, but devices always send line_total gross with line_discount 0 (line discounts ride pos_order_discounts rows).

- Evidence: pos_machine/lib/services/order_sync_payload.dart:295-311; pos_machine/lib/screens/staff_pos_screen.dart:3394-3401; pos_merchant/src/app/Models/OrderItem.php:21-22; pos_api/src/app/Actions/Device/Sync/Handlers/CreateOrderHandler.php:150
- Risk: Misleading schema docs and asymmetric data quality between device types

## F132 [P3] ProductPerformance revenue is pre-discount/pre-comp and double-presents add-on money  _(agent: audit-financial-calc, verified: True)_
Per-product revenue = SUM(line_total) which is gross of all discounts/comps and already includes add-on price deltas in the parent line, while linked add-on products also get a separate addon_revenue column (price_delta × qty) — so product revenue never reconciles with net_sales and add-on money appears under two products across columns.

- Evidence: pos_merchant/src/app/Actions/Pos/Reports/ProductPerformanceReportAction.php:54-70,82
- Risk: Presentational: product-level figures cannot be reconciled against headline sales

## F133 [P3] gross_sales defined differently in merchant vs admin portals  _(agent: audit-reporting, verified: True)_
Merchant gross = SUM(subtotal) pre-discount/tax; admin gross = SUM(grand_total). Same window yields different 'gross' across portals; avg_ticket bases also differ.

- Evidence: pos_merchant/src/app/Actions/Pos/Reports/SalesReportAction.php:97 vs pos_admin/src/app/Actions/Admin/Reports/AdminSalesReportAction.php:47,75,82
- Risk: Cross-portal reconciliation confusion

## F134 [P3] Finalized/pending income logic diverges across three surfaces  _(agent: audit-reporting, verified: True)_
Sales headline realised test (payout-paid OR channel=cash_bank) lacks the legacy pure-cash EXISTS fallback that payout by_month has; orders list marks no-ledger orders is_finalized=false while the Sales headline counts them finalized; mixed-channel per-order status folds to one value via MAX(payout_id).

- Evidence: pos_merchant/src/app/Actions/Pos/Reports/SalesReportAction.php:509-512,543-544; PayoutBreakdownReportAction.php:193-198; Support/SaleCommissionStatus.php:60-124,194-209
- Risk: Same order shows contradictory realised/pending status across pages

## F135 [P3] Admin settlement 'merchant_payable' includes cash-channel residuals platform never pays  _(agent: audit-reporting, verified: True)_
Headline sums merchant residual over both channels while payouts claim card-channel only; label overstates platform liability by merchant-held drawer cash. Legacy 'all'-channel rows also render on both invoice and payout statement breakdowns.

- Evidence: pos_admin/src/app/Actions/Admin/Reports/AdminSettlementReportAction.php:166-172; pos_merchant/.../PayoutBranchLinesAction.php:45; CommissionInvoiceBranchLinesAction.php:44
- Risk: Operator misreads payable liability

## F136 [P3] Product Performance internal inconsistencies  _(agent: audit-reporting, verified: True)_
top_addons.attach_revenue not scaled by parent qty while per-product addon_revenue is; slow_movers cannot show zero-sale products; revenue basis (line_total) differs from dashboard's qty*unit_price_snapshot; live product names used instead of snapshots.

- Evidence: pos_merchant/src/app/Actions/Pos/Reports/ProductPerformanceReportAction.php:66-70,77-84,134-145,155-159; DashboardSummaryAction.php:241-245
- Risk: Self-inconsistent report and dashboard mismatch

## F137 [P3] Recipe & Cost report ignores its window and reads live prices; snapshot-average column missing  _(agent: audit-reporting, verified: True)_
Uses today's default_unit_cost only, ignores branch/date filter while echoing the window in the payload; docblock-promised average actual snapshotted cost is an unshipped stub.

- Evidence: pos_merchant/src/app/Actions/Pos/Reports/RecipeCostReportAction.php:17-18,37-57,77-85
- Risk: Apparent cost history rewrites on any price edit

## F138 [P3] Restock report attributes purchases to live primary_supplier_id  _(agent: audit-reporting, verified: False)_
Supplier breakdown keys on the ingredient's CURRENT primary supplier; reassignment re-attributes historical spend. Movement rows carry no supplier snapshot (inferred from report design).

- Evidence: pos_merchant/src/app/Actions/Pos/Reports/RestockPurchasingReportAction.php:57,81-98
- Risk: Historical purchase-by-supplier drifts after master-data edits

## F139 [P3] Customer report loyalty block ignores branch scope (P-G5)  _(agent: audit-reporting, verified: True)_
Points issued/redeemed/liability are company-wide with no branch filter while the rest of the payload is branch-clamped; branch-restricted users read company-wide loyalty totals.

- Evidence: pos_merchant/src/app/Actions/Pos/Reports/CustomerReportAction.php:113-130
- Risk: Mild scope leak + inconsistent payload

## F140 [P3] Pending-approval expenses reduce net_profit immediately  _(agent: audit-reporting, verified: True)_
Every non-rejected expense (including pending) counts at logged_at; later rejection silently restates past net_profit.

- Evidence: pos_merchant/src/app/Actions/Pos/Reports/SalesReportAction.php:133-140
- Risk: Net profit flickers with approval workflow

## F141 [P3] Perf: PHP-side snapshot scans and company-wide cohort scan on hot report paths  _(agent: audit-reporting, verified: True)_
Sales COGS and Product Performance load every order-item row of the window into PHP to decode JSON snapshots (runs twice for exports); Customer report loads first-order times for every customer of the company regardless of window. No report caching.

- Evidence: pos_merchant/src/app/Actions/Pos/Reports/SalesReportAction.php:556-582; ProductPerformanceReportAction.php:191-207; CustomerReportAction.php:79-106
- Risk: Slow/memory-heavy requests on large tenants and long windows

