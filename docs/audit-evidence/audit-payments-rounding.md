# Audit: Payments & Rounding (agent: audit-payments-rounding)

Date: 2026-08-07. READ-ONLY audit across pos_machine, pos_handheld, pos_api, pos_admin, pos_merchant, charity.
Legend: **VERIFIED** = read in code at the cited lines. **INFERRED** = derived from verified code, not directly testable here. **Cannot-Verify** = noted explicitly.

---

## 1. Money units & every baisas<->OMR conversion point

**The contract (VERIFIED):** integer baisas on the wire (1 OMR = 1000 baisas); DB stores `decimal(12,3)` OMR; conversion only at boundaries.

| App | Conversion point | Evidence |
|---|---|---|
| pos_api | `Money::toOmr(int $baisas): string` = `number_format($baisas/1000, 3)`; `Money::toBaisas` = `(int) round(omr*1000)` — the single boundary converter used by all sync handlers | pos_api/src/app/Support/Money.php:18-27 |
| pos_admin | Identical `Money` twin | pos_admin/src/app/Support/Money.php:21-27 |
| pos_merchant | NO shared Money class; inline `(int) round(x*1000)` / `number_format(x/1000,3)` in the delivery commission recorder | pos_merchant/src/app/Actions/Pos/Deliveries/RecordDeliveryCommissionAction.php:72-73,146 |
| pos_machine | `omrToBaisas(double omr) => (omr * 1000).round()` — used for every wire field | pos_machine/lib/services/order_sync_payload.dart:24 (uses at 149,158-159,170,194,206,225,234,264-268,286,293,388,396,451,459-460,470,476-479) |
| pos_machine | Mosambee charge amount = `(amountOmr * 1000).round().toString()` (baisas string into the SoftPOS intent) | pos_machine/lib/services/mosambee_payment_service.dart:253-258 |
| pos_machine | Inbound config/report: `/1000.0` (config_mapper.dart:260,754,757,832,879,933,964; models/branch_report.dart:7; models/pos_models.dart:2143,2162) | as cited |
| pos_handheld | `omrToBaisas` twin | pos_handheld/lib/services/order_sync_service.dart:14 |
| pos_handheld | Mosambee amount = `(amountOmr * 1000).round().toString()` | pos_handheld/lib/services/mosambee_payment_service.dart:149 |
| charity | Shares: `round(total*pct/100, 3)` OMR + remainder to largest share so Σ==total | charity-laravel-api/src/app/Services/CommissionShareCalculator.php:38-64 |

Device-side rounding helper: `_roundMoney(v) = double.parse(v.toStringAsFixed(3))` (pos_machine/lib/state/pos_controller.dart:3950); tax `_roundTax` same (pos_machine/lib/models/pos_models.dart:147).

## 2. Rounding order for tax and discounts (pos_machine, authoritative device)

VERIFIED chain (pos_controller.dart):
1. `rawSubtotal` = Σ cart lineTotals, unrounded fold (1070).
2. `discountAmount` = round3(orderLevel + lineDiscounts + offers), clamped to [0, rawSubtotal] (1072-1085). Percentage order discount = `rawSubtotal * pct/100` before the round (1076).
3. `subtotal` = round3(rawSubtotal − discountAmount) clamped ≥0 (1253-1255).
4. `compAmount` (gifts + manager comp) round3, clamped to subtotal (1277-1298).
5. `_taxedBase` = round3(subtotal − compAmount) (1325-1327). **Comped food is untaxed.** Delivery orders fully tax-exempt (1329-1338).
6. `tax` = Σ per-tax-line round3(base*rate/100), re-rounded (pos_models.dart:147-161) — per-line rounding, then sum.
7. `total` = round3(taxedBase + tax) (1340).

Server does **not** recompute tax/discounts; it validates the additive invariant only:
`subtotal − discount − comp + tax == grand` within **±1 baisa** — pos_api CreateOrderHandler.php:631-636. Comp rows must sum **exactly** to comp_total_baisas (CreateOrderHandler.php:530-532); **discount rows are NOT sum-validated** against discount_total_baisas (only per-row min:0; validate() at 573-618) — see finding F-9.

pos_handheld derives the grand **by construction** in integer baisas: `grand = subtotal − discount − comp + tax` (order_sync_service.dart:360-364), so its invariant holds exactly; the machine converts each independently-rounded double, relying on the ±1 tolerance.

## 3. Tender methods

Wire methods (pos_api Payment::METHODS): `cash, card, split_part, loyalty, gift, bank_pos` (pos_api/src/app/Models/Payment.php:44). Statuses: success / pending_reconciliation / failed (:46-50).

pos_machine label→wire mapping: 'bank' before 'card' so "Bank POS" never becomes SoftPOS card money; gift/loyalty/cash fallthrough (order_sync_payload.dart:42-52). Bank POS is record-only (no Mosambee launch) and deliberately excluded from the bank-commission base (pos_controller.dart:2835-2859; PayOrderHandler.php:154-162). Gift = zero collected, full-grand `gift` tender, excluded from commission base and (fully-gifted) loyalty earn (pos_controller.dart:2861-2882; PayOrderHandler.php:163-165,211-213; RecordSaleCommissionAction.php:88-93).

## 4. Split payments & the exact-sum rule

**Machine (Phase 3 f19b990) — VERIFIED:**
- Equal shares: `activePaymentBaseTotal` = round3(total/splitCount); the final leg takes round3(total − paidBases) clamped ≥0 (pos_controller.dart:1398-1434).
- Custom plan (`setSplitPlan`): amounts rounded to 3dp, each non-final ≥ 0.001, LAST share rewritten to exact remainder; rejected if remainder < 0.001; plan cleared on cart mutations via nonce (`_splitPlanNonce == orderUpdateNonce`) AND live-total match ±0.0005; re-planning blocked after a recorded leg (1824-1843, 1421-1431). Plan is transient (never persisted into drafts; cleared at 1813,1849,1978,1998,2449,3886).
- Mixed cash+card single-screen path `payMixedCashAndCard`: cash share + card base = total; card charged `payableTotal` (base + round-up when accepted); records synthetic 2-leg split (2962-3110).
- Wire: one tender per leg; **last leg forced to `grandBaisas − acc`** so Σ(amount_baisas) == grand_total_baisas exactly (order_sync_payload.dart:286-311).

**Handheld (HH-5) — VERIFIED:** split plan sheet in integer baisas; card leg settled LAST ("card captures are irreversible... a cancelled card aborts with ZERO money taken") (payment_screen.dart:646-653); last tender absorbs rounding (order_sync_service.dart:377-397).

**Server: ±1 baisa tolerance** on Σ(tendered) vs grand: `abs($tenderedBaisas − $grandBaisas) > 1` throws (PayOrderHandler.php:168-171). So the answer to the charter question: devices force exact equality; the server tolerates ±1 baisa.

Edge (F-10): PayOrderHandler validates each tender only for `method` validity + `amount_baisas` present (121-123) — **no integer/min:0 rule per tender**; a device bug emitting a negative last leg (e.g. mid-split cart shrink; controller-level clamps exist but cart mutation gating is UI-level: staff_pos_screen.dart:542,674,704,830) would be accepted as long as the sum matches.

## 5. Card charge flow (pos_machine) — what is invoked

**VERIFIED: Mosambee SoftPOS companion APK, driven by Android intents — not an in-process SDK.**
- Package `com.mosambee.dhofar.softpos`; intent actions `com.mosambee.softpos.login` / `com.mosambee.softpos.payment` via `startActivityForResult` (MosambeeBridge.kt:19-20,217-247,280-299; service constant appPackageName at mosambee_payment_service.dart:224).
- Login credential: userName = bank terminal id; password token = AES-CBC(hardcoded key, sha256(pin) XOR sha256(user)) — "Same AES key used by the working charity app integration" (MosambeeBridge.kt:24-26,572-610). Default terminal PIN `'1321'` compiled into the app; overridable per device via prefs `terminal_pin` (mosambee_payment_service.dart:225-233). (Flagged for the security agent — F-11.)
- Session pre-warm: separate login yields a single-use sessionId; **5-minute TTL** (5aea76b) so a stale session collapses into NO_SESSION → silent fresh login+pay instead of a scary failure dialog (MosambeeBridge.kt:38-57,126-176). Dart falls back to `loginAndPay` on NO_SESSION or a native BUSY (mosambee_payment_service.dart:299-353).
- Amount: integer-baisas string (`amount` extra). Cannot-Verify: Mosambee's expected unit (no SDK docs in repo) — but the charter commit caefd36 records a 4-tracer investigation concluding the integration is "fully wired and live-capable," and the identical convention is used by the working charity app integration (INFERRED correct).
- Payment always launches on the MAIN (staff) display; rear display keeps the branded overlay (MosambeeBridge.kt:290-299,516-527).
- Result classification (Kotlin): success = responseCode 0/00 or receipt result=success; canceled = RESULT_CANCELED + cancel-ish description; else failed (MosambeeBridge.kt:464-514). Dart re-derives from the JSON payload (mosambee_payment_service.dart:23-100).

**Handheld:** same bridge pattern (pos_handheld MosambeeBridge.kt), KOZEN hardware, same baisas-string amounts.

## 6. Unresolved-charge lifecycle (caefd36 + 5aea76b) — machine

VERIFIED, both fixes present in code:
- `neverReachedTerminal` = code MISSING_TERMINAL_ID | BAD_ARGS, or message contains "is not installed"/"was not found"/"unable to launch" → **excluded from isUncertain** → hard-failure path, no "Mark paid" offer (mosambee_payment_service.dart:87-100; pos_controller.dart:3508-3521; test/card_charge_classification_test.dart exists).
- Preflight: no terminal id ⇒ synthetic MISSING_TERMINAL_ID before launching the SoftPOS app (mosambee_payment_service.dart:299-313); localized actionable message (pos_controller.dart:3475-3482).
- The pending-recon prompt has **no auto-cancel timer**: "a timer must never answer a money question"; a 2-minute Timer only ESCALATES (danger flag + system alert sound); the completer waits for a human; order-reset paths complete it as cancel so it can't hang (pos_controller.dart:3527-3590).
- Retry loops back to a fresh terminal launch; Record returns `recordPending`; Cancel aborts (3493-3522).

**Residual gap (F-6):** a Mosambee **login failure** ("Payment login failed." — bridge stage=login, empty sessionId, MosambeeBridge.kt:352-380) does not match any neverReachedTerminal pattern → still `isUncertain` → the cashier is offered "Mark paid — pending reconciliation" for a charge where no payment intent was ever sent to the acquirer. Same class of defect caefd36 fixed, narrower trigger.

**Handheld twin NOT fixed (F-2):** `isUncertain => !isSuccess && !isCanceled` with the stale comment "Same semantics as pos_machine" (pos_handheld/lib/services/mosambee_payment_service.dart:47-50). Preflight covers only the missing-terminal case (payment_screen.dart:509-516). "Mosambee application is not installed." / "payment activity was not found." / "Unable to launch..." (emitted by its own bridge, MosambeeBridge.kt:218,262,271) and login failures all reach `_promptUncertain` and can be force-recorded as pending_reconciliation (payment_screen.dart:552-581, 600-607) — booking a card sale that provably never reached the bank; it then sits in the admin queue with no settlement row to match (the exact caefd36 scenario).

## 7. NFC-timeout pending_reconciliation path, end-to-end (VERIFIED)

1. Device: uncertain verdict → cashier picks Record → tender status `pending_reconciliation` rides the order.pay tender w/ Soft POS evidence (pos_controller.dart:2897-2918, 3035-3074; order_sync_payload.dart:54-69,285-311).
2. pos_api PayOrderHandler: payment row created with `pending_reconciliation=true`; **commission split DEFERRED** (`$hasPendingTender` skip at 185-203); inventory + loyalty still fire (goods left the shop). Order still flips PAID (173-176).
3. donation.record on such an order: pos_roundup_donations row created status='pending', **charity forward SKIPPED**, forwarded_at NULL (DonationRecordHandler.php:94-124,175-192).
4. pos_admin daily queue: GET /admin/api/v1/pending-reconciliation lists ORDERS with ≥1 pending tender captured on ?date (default today) with Soft POS evidence + round-up context (PendingReconciliationController.php:49-100).
5. Approve: every pending tender flipped via MarkPaymentReconciledAction (status success, pending cleared, reconciled_by/at, audit) then ReconcileDeferredEffectsAction (shared with the bank-file tool): commission recorded once (idempotent, recomputing cardBaisas/giftBaisas from stored tenders exactly like PayOrderHandler — ReconcileDeferredEffectsAction.php:146-196), unforwarded round-ups forwarded best-effort with status override 'success' (204-241). ApprovePendingReconciliationAction.php:50-87.
6. Reject: pending tenders → status 'failed', pending cleared; order NOT auto-voided; no commission, no charity forward (RejectPendingReconciliationAction.php:39-90). **But the donation row is left status='pending', forwarded_at NULL — see F-4.**
7. Bank-file route converges on the same actions (ReconcilePaymentsAction.php:38-77) + A2 actual bank-fee capture (`bank_fee` = gross − net floored at 0; BankReconciliationService.php:113-121).

## 8. Bank reconciliation matching — terminal_id/bank_id snapshot

**DONE, with device fallback retained for legacy rows (VERIFIED):**
- Snapshot at pay time: `'terminal_id' => $device->terminal_id, 'bank_id' => $device->bank_id, 'device_id' => $device->id` on every payment row (PayOrderHandler.php:140-143).
- Matcher prefers the payment's own columns: `$terminalId = $p->terminal_id ?: ($device->terminal_id ?? null)` (+ same for bank_id), device resolved via payment.device_id or order.device_id (BankReconciliationService.php:166-230, esp. 200-203; docblock 31-33).
- Match key = normalized terminal_id + auth code; amount tolerance `< 0.0005` OMR (`sameMoney`, :632-640); parsers: Bank Dhofar xlsx "Table 1", Oman Arab Bank csv (:232-283).

**F-1 (finding): the auto-match ignores `roundup_amount`.** The actual card capture for a round-up sale = base + round-up (`_runCardCharge(amount: payableTotal)` where payableTotal = ceil'd total when accepted — pos_controller.dart:1436-1447, 2888-2893, 3015-3020,3039), so the bank statement gross carries the round-up; but pos_payments.amount = the base tender only (payments Σ == grand_total; the donation rides pos_roundup_donations + payments.roundup_amount, DonationRecordHandler.php:154-158). loadCandidatePayments selects `amount` only — no roundup_amount anywhere in the service (grep verified). Every donation-carrying card charge therefore fails `sameMoney` and lands in `amount_mismatches` with amount_difference == the round-up (0.001–0.999 OMR). Systematic false mismatch on exactly the transactions the charity flow depends on.

## 9. Round-up donation on card legs only (f7930fd, cbd4431) — VERIFIED

- Gate: `canOfferCharityRoundUp` = not delivery AND `selectedPaymentMethod == 'Credit Card'` AND round-up ≥ 0.001 (pos_controller.dart:1449-1461). Offer = ceil to whole OMR (1443-1447). Customer/staff prompt; 2-min timeout cancels the PROMPT only (not a money answer — the sale just proceeds nowhere until re-tried) (3364-3397).
- Payload: one donation.record per rounding CARD leg with `payment_index` (leg's position in payments[]); stale round-up flag on a non-card leg skipped defensively; single-tender card sends its index (order_sync_payload.dart:376-414).
- Server: resolves payments-ordered-by-id[index]; **hard-fails if the addressed leg is not card** ("round-up payment_index does not address a card tender"); legacy no-index devices → latest card (DonationRecordHandler.php:77-92,197-223).
- Forward to charity: POST /api/donations-pos-roundup with `pos_reference` = donation uuid; charity dedupes on `idempotency_key = 'pos_roundup:'.pos_reference` (partial unique index) and returns the existing row on replay (pos_api ForwardCharityDonationAction.php:44-102; charity CharityTransactionsController.php:550-669). Charity share split: per-share round3 + remainder onto largest share ⇒ Σ(shares)==total (CommissionShareCalculator.php:38-64).
- Void: donations flipped to 'void', payment breadcrumbs cleared; an already-forwarded external charity_transaction deliberately not reversed (VoidOrderHandler.php:199-219).
- **Handheld has NO round-up at all** (grep 'donation|charity' in pos_handheld/lib = 0 hits) — round-up is a machine-only feature. (Parity gap, not a money bug.)

**F-4 (finding): the pos_admin retry sweep can forward round-ups for rejected/voided orders.** `RetryRoundupForwarding` eligibility = forwarded_at NULL + ≥10min old + linked payment NOT currently pending_reconciliation (RetryRoundupForwarding.php:44-70). It checks neither `donation.status` nor `payment.status`:
- After **Reject** (money never arrived): payment.status='failed', pending_reconciliation=**false** (RejectPendingReconciliationAction.php:59-64); donation stays status='pending', forwarded_at NULL → next sweep run forwards a donation for money the bank never received.
- After **Void** where the inline forward had failed: donation status='void', forwarded_at NULL, payment not pending → sweep forwards a voided donation.
**F-7 (mitigating + its own gap): the sweep is not scheduled anywhere** — pos_admin routes/console.php contains only the document-expiry job (grep across src for the signature/class: only the command file itself). So today the leak can only fire if ops run `donations:retry-roundup-forwarding` manually — and, conversely, legitimately failed forwards are never retried (the stated purpose of step 10 / commit 1dcda22 is unfulfilled).

## 10. Mixed-tender apportionment (pos_api c076237 / pos_admin ed40469 / pos_merchant 08b6db2)

**Problem it solves (VERIFIED from code + docblocks):** before channel-splitting, a mixed cash+card order produced whole-order commission rows; the payout (which pays merchants the card money the platform holds) claimed the whole-order merchant residual — paying the merchant cash he already had in the drawer ("the mixed-order leak", CreatePayoutAction docblock + RecordSaleCommissionAction.php:39-53).

**Mechanics (VERIFIED, pos_api RecordSaleCommissionAction.php:70-205):**
- collected = grand − gifts; cardSlice = min(cardBaisas, collected); cashSlice = remainder (87-100).
- Every row channel-stamped `card` | `cash_bank`. Bank (acquirer) rows + `applies_to='card'` rows bite cardSlice; `cash_bank` rows bite cashSlice; **'all' on a mixed order splits into one row per non-empty channel**; pure orders emit single channel-stamped rows identical to before (119-142).
- **Merchant residual computed PER CHANNEL as the exact remainder** ⇒ Σ(channel rows) == that channel's slice, Σ(all rows) == collected — commission rounding keeps the sum exact, confirmed: each non-merchant share `(int) round(base*pct/100)` (:107), merchant takes `slice − allocated` (:149-165). Negative-residual risk bounded by admin validation: per-channel share percents ≤ 100 (pos_admin UpsertMerchantCommissionProfileRequest.php:36 + channel-sum rule at :44-74).
- Deploy-window fallback if the shared `channel` column is missing (hasColumn, cached) (:193-205). Same fallback merchant-side (RecordDeliveryCommissionAction.php:128,143).
- Idempotent: one breakdown per order ever (:72-75); percents snapshot on rows.

**pos_admin consumption (VERIFIED):** payouts claim only channel='card' merchant residuals + legacy 'all' rows under the original pure-cash exclusion; voided orders excluded; reconcile-before-payout guard (unsettled bank rows block); payable = settled_amount ?? commission_amount (CreatePayoutAction.php:30-120). Invoices claim channel='cash_bank' platform/other rows + legacy pure-cash 'all' rows, verified-first (PendingCommissionInvoiceAction.php:30-66). Void keeps claimed orders' rows (order-level guard) so payout/invoice statements stay backed (VoidOrderHandler.php:221-266).

**pos_merchant twin (VERIFIED at commit + spot-checks):** 08b6db2 — delivery recorder stamps channels (provider money = merchant-held cash_bank; card-scoped rows land in the empty card channel) with exact-remainder residual (RecordDeliveryCommissionAction.php:72-118); reports count cash_bank residuals as REALISED immediately (SalesReportAction.php:511; PayoutBreakdownReportAction.php:191-194).

**Assessment: the apportionment design is correct** (channels partition collected money exactly; each document claims only its channel; legacy predicate preserved for pre-split rows).

## 11. Idempotency — duplicate charge / duplicate payment risk

**Server (VERIFIED):** exactly-once on (device_id, client_event_id) composite unique; duplicates ACK original state; FAILED events re-dispatched on re-push (transient-fault recovery); concurrent insert race handled via UniqueConstraintViolation → duplicate ACK (IngestSyncEventsAction.php:53-111). order.pay re-reads + `lockForUpdate` + re-checks status inside the txn so two DIFFERENT-id pays serialize and the loser throws 'order already paid' — exactly one inventory consume/commission record (PayOrderHandler.php:85-102). Void same pattern (VoidOrderHandler.php:101-110).

**Devices (VERIFIED):** payloads are built ONCE and persisted with their client_event_ids before any network I/O; retries resend the same ids. Machine: Drift outbox (order_sync_repository.dart:22-74,150-209 — flush marks synced only when every event 'processed'; transport failure re-pushes same batch). Handheld: prefs outbox `order_outbox_v1` (order_sync_service.dart:163-171, 806-873); server REJECTIONS (answered-and-refused) park a batch after 5 (kMaxServerRejections, never auto-dropped, manual retry un-parks; Sentry per batch) while network errors retry forever (186-206, 1179-1276).

**Card-leg duplicate risk:** Retry on an uncertain charge re-launches the terminal (pos_controller.dart:3510-3511; payment_screen.dart:572-573,608-609) — if the first attempt actually captured, retry double-charges the customer; this is a cashier decision presented as such (inherent to offline SoftPOS, no terminal-side inquiry API in evidence). NO_SESSION/BUSY fallbacks never double-send (no payment intent was launched).

**F-5 (finding, machine): post-charge durability window.** Order completion sequence: Mosambee success → `_finishCompletedOrder`: print receipt (awaited) → print kitchen ticket → save local history → `onOrderCompleted` (async fire-and-forget) → **GPS acquisition up to 5s** → outbox enqueue (pos_controller.dart:3200-3246; staff_pos_screen.dart:380-449). App kill/crash between the card capture and `enqueueOutbox` leaves a charged card with no outbox row; there is NO recovery path from local order history into the outbox (grep for re-enqueue/recover/backfill: none). The sale never reaches pos_api — worse than pending_reconciliation, it's invisible to the admin queue entirely (only the bank statement's db-missing bucket would catch it). The handheld has the same shape but a smaller window (no printing before enqueue; enqueue is the first await after charge — payment_screen.dart `_complete` → enqueueCompletedOrder persists before printing; VERIFIED order at order_sync_service.dart:866-873).

## 12. Shift-close money & change_given

- Server: expected_cash = opening + Σ(cash amount − change_given) over the shift window; variance = counted − expected (CloseShiftHandler.php:24-90).
- Machine: cash tender amount_baisas == grand (exact); **never emits change_given_baisas** (no occurrence in order_sync_payload.dart) → expected-cash math correct for machine sales.
- **F-3 (finding, handheld): change double-subtraction.** Handheld defines tender amount as **NET** ("cash overpayment rides changeGiven, not the amount" — order_sync_service.dart:56-75); single cash tender amount = grandBaisas (:381-397) AND emits `change_given_baisas` when change > 0 (:394-395; UI: payment_screen.dart:387-390,454-456). PayOrderHandler stores change_given (:131). CloseShiftHandler then computes net = SUM(amount) − SUM(change_given) — subtracting change from an already-net amount. Every handheld cash sale with change **understates expected_cash by the change amount**, producing a systematic positive variance (drawer "over") — or masking real shortages of the same size. The exact-sum tender rule proves amount must be net (gross would break Σ==grand), so the server's shift math is the wrong side.
- Machine Z-report: card tender lines use base amounts; round-up is a separate labeled line (shift_summary.dart:171-183,203,352-354,439-442) — the Mosambee terminal batch total = card base + round-ups, so ops must add the two lines when balancing the terminal (documented-behavior note, P3).

## 13. Frontend/backend/payment/accounting total divergence map

| Pair | Status | Evidence |
|---|---|---|
| Machine displayed total vs wire grand | Same value (`total` getter → omrToBaisas) | pos_controller.dart:1340; order_sync_payload.dart:268 |
| Wire grand vs Σ tenders | Forced exact device-side; ±1 server tolerance | order_sync_payload.dart:293; PayOrderHandler.php:169 |
| order totals invariant | ±1 baisa server check | CreateOrderHandler.php:631-636 |
| Charged card amount vs recorded tender | Machine single: identical (payableTotal both). Machine split last-card-leg & handheld: computed via different paths (screen double vs derived baisas) — ≤1 baisa drift possible → fails the 0.0005 recon tolerance (F-12, P3) | pos_controller.dart:2888; payment_screen.dart:525-527 vs order_sync_service.dart:363-364 |
| Charged card amount vs bank statement vs pos_payments.amount | **Diverges by the round-up on every donation sale** (F-1) | §8 |
| Commission rows vs collected money | Exact by construction (per-channel remainder) | RecordSaleCommissionAction.php:144-165 |
| Discount rows vs discount_total | NOT validated server-side (comp rows are) — report-vs-total drift possible (F-9) | CreateOrderHandler.php:530-532 (comps only) |
| Charity shares vs donation total | Exact (remainder distribution) | CommissionShareCalculator.php:51-64 |
| Machine Z-report vs server summary | Server-authoritative summary piggybacked on close; local fallback mirrors same math | CloseShiftHandler.php:94-99; shift_summary.dart:140-207 |
| Per-line receipt allocation on split receipts | round3(payableTotal * lineShare) display-only; may not sum to leg total | pos_controller.dart:3944-3950 |

## 14. Findings (ranked)

- **F-1 (P1)** Bank reconciliation auto-match breaks on every round-up card charge: statement gross includes the round-up; matcher compares payment.amount only (roundup_amount ignored everywhere in BankReconciliationService). pos_admin/src/app/Services/Admin/BankReconciliationService.php:124,172,216,632-640 + pos_machine pos_controller.dart:1436-1447,2888.
- **F-2 (P1)** Handheld still has the pre-caefd36 misclassification: `isUncertain = !success && !canceled` with no neverReachedTerminal exclusion; app-missing/activity-not-found/unable-to-launch/login-failed all offer "record as pending_reconciliation" → bookable revenue that provably never reached the acquirer. pos_handheld/lib/services/mosambee_payment_service.dart:50; lib/screens/payment_screen.dart:552-607.
- **F-3 (P1)** Handheld cash change double-subtraction in shift close: net tender amount + change_given both sent; server subtracts change again → expected_cash understated by total change given. pos_handheld/lib/services/order_sync_service.dart:56-75,381-397; pos_api CloseShiftHandler.php:65-76.
- **F-4 (P1, latent)** Round-up retry sweep would forward donations of REJECTED (money never arrived) and VOIDED orders — checks only forwarded_at NULL + payment not currently pending; ignores donation.status and payment.status='failed'. pos_admin RetryRoundupForwarding.php:46-70; RejectPendingReconciliationAction.php:59-64; pos_api VoidOrderHandler.php:205-219. Latent because of F-7.
- **F-5 (P2)** Machine post-charge crash window: card captured → print → save → async GPS (≤5s) → outbox enqueue; a crash in the window loses the sale server-side with no recovery path from local history. pos_controller.dart:3200-3246; staff_pos_screen.dart:380-449.
- **F-6 (P2)** Machine: Mosambee LOGIN failure still classified uncertain → force-record offered for a charge never sent to the bank. mosambee_payment_service.dart:87-100; MosambeeBridge.kt:352-380.
- **F-7 (P2)** `donations:retry-roundup-forwarding` is never scheduled (routes/console.php has only the document-expiry job) — failed charity forwards are never retried, defeating commit 1dcda22's purpose. pos_admin/src/routes/console.php:14-17.
- **F-8 (P2)** Round-up parity: handheld cannot offer round-up at all (feature absent) — card legs on handheld silently skip the charity program. pos_handheld/lib (no donation/charity references).
- **F-9 (P3)** Discount rows not sum-validated against discount_total_baisas (comps are exact-checked) → by-rule/by-offer reports can diverge from the order's discount total under device clamping. pos_api CreateOrderHandler.php:530-532 vs validate() 591-598.
- **F-10 (P3)** No per-tender min:0/integer validation in order.pay (negative leg accepted if the sum matches). PayOrderHandler.php:121-123.
- **F-11 (P3, hand to security agent)** Hardcoded default terminal PIN '1321', empty partnerId, and the AES password-token key baked into both APKs. pos_machine mosambee_payment_service.dart:225-226; MosambeeBridge.kt:24-26 (twin in pos_handheld).
- **F-12 (P3)** ≤1-baisa drift possible between the charged card amount and the recorded tender on handheld/split-last-leg paths; recon tolerance is <0.0005 OMR so a 1-baisa drift lands in amount_mismatches. order_sync_service.dart:363-397 vs payment_screen.dart:525; BankReconciliationService.php:632-640.
- **Note (P3)** Machine Z-report card line excludes round-ups (separate line) vs terminal batch totals. shift_summary.dart:171-203.

## 15. Explicit answers to charter questions

- **Exact-sum rule:** devices force Σ(legs)==grand exactly (last-leg remainder); server tolerates ±1 baisa (PayOrderHandler.php:169). Order money invariant also ±1 (CreateOrderHandler.php:635).
- **Card SDK:** Mosambee SoftPOS companion app (`com.mosambee.dhofar.softpos`) via login/payment intents; no Mosambee code in-process. Not SoftPOS-by-Sunmi, not a bundled AAR.
- **"rounding keeps sum exact" (commissions):** TRUE — per-channel merchant remainder (pos_api RecordSaleCommissionAction.php:144-165); charity shares also exact (CommissionShareCalculator.php:51-64).
- **terminal_id/bank_id snapshot:** DONE on pos_payments at pay time (PayOrderHandler.php:141-142); the admin matcher prefers the snapshot and falls back to the device only for legacy rows (BankReconciliationService.php:200-203).
- **Round-up on card legs only:** TRUE machine-side (gate + payload + server card-check); absent on handheld.
- **Mixed-tender apportionment:** correct by construction (channels partition collected money; payout=card channel, invoice=cash_bank channel; legacy predicates preserved).
