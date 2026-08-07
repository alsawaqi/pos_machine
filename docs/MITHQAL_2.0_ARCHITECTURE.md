# MITHQAL 2.0 — Architecture & Implementation Plan

## Context

You asked for an architecture plan you can code from, covering what is missing and what must be fixed, reconciled across the three blueprint PDFs. The prior deliverables did not meet that: the phased roadmap lived in a hidden `~/.claude/plans/` path, and the architecture content was buried in §29–§34 of a 1,555-line audit report. Neither was a standalone, design-level document.

**This plan produces that document** — `pos_machine/docs/MITHQAL_2.0_ARCHITECTURE.md`, committed alongside the code — at the depth where an engineer or AI agent implements directly: exact tables and columns, endpoints and sync-event payloads, which files change in each of the six apps, what each piece reuses, and how it stays backward-compatible with APKs already in the field.

**Decisions already locked with you:**
- **Extend the existing catalog model.** The Aug spec's unified `items`/`item_components` migration is formally superseded; combos become a bounded extension. Migrating a live catalog with frozen order snapshots is multi-week work whose only near-term payoff is combos.
- **Scope through go-live.** Phase 7+ features stay deferred exactly as the blueprints defer them (gift cards, tips, packaging charges, kitchen priority, delivery integrations, order-ahead, reservations, house accounts, table transfer/merge, menu time-windows, expiry alerts, training mode, menu-import template, product-scoped stamps, customer tablet — superseded by QR).
- **Overlapping discounts keep biggest-wins.** When two rules match the same item, the shared core picks the single largest — matching what every till already charges — rather than the blueprint's compounding stack. This formally supersedes the blueprint a second time (after the item model); record it so nobody later "fixes" the code back toward the document. The `stackable` flag is deprecated: shipped in config for contract compatibility, ignored by the core, hidden in the merchant UI, column retained per the additive-only rule.
- **One promotion per item, and a capped total.** *A margin-protection decision that DOES change live pricing — the only one in this plan.* Today a single item can take a line discount **and** an offer **and** a share of an order-level discount, all three stacking, with the sole guard being that the cart cannot go negative — so the system will hand over a free item if rules line up. The core enforces: **per item, the larger of (line discount, offer) — never both**; an order-level discount still applies on top, because that is an authority decision rather than a promotion; and a **per-merchant ceiling on total reduction (default 50%) requiring a manager PIN to exceed**, audited. See MARGIN-001 in Phase 1.
- **Coding is paused** at Phase 0 item 3 of 10 until you have reviewed this.

## What is already committed (do not re-plan)

| Item | Commit | Effect |
|---|---|---|
| Full audit + 22 evidence files | `pos_machine 5c64315` | The evidence base this plan rests on |
| **HH-001** (P0) | `pos_handheld 28fbb3f` | A sale rung during a sync flush can no longer be erased |
| **HH-002** (P1) | `pos_handheld 52678b2`, `pos_machine e539886` | Card failures that never left the device can no longer be force-recorded |
| **API-003** (P1) | `pos_api 32d4fff` | Shift expected-cash no longer double-subtracts change |

## Ground rules (violating these loses work or corrupts shared data)

- **Migrations are additive only and owned solely by `pos_admin`** (`src/database/migrations`). The `charity_db` instance is shared with a live charity product. Never drop or rename an existing column; never `migrate:fresh`/rollback.
- **Money**: integer **baisas** on the wire, `decimal(12,3)` OMR in the DB (ingredient `unit_cost` is `decimal(12,6)`); convert only at boundaries via `Money::toBaisas/toOmr`.
- **The device contract is `pos_api/src/tests/Feature/Device*Test.php`** (437 tests). Deployed APKs stay in the field after a backend deploy, so changes are additive — new event types or new optional fields, never reinterpreting an existing one. Where a payload's meaning must change, gate on app version.
- **Test-mirror schemas** (`pos_api` and `pos_merchant` `0000_00_00_000000_create_test_schema.php`) must be updated in the same change as any production column.
- **Ledgers**: `WriteStockMovementAction` and `WriteProductStockMovementAction` are the only writers, append-only.
- **Git**: local commits on `main`, never push unless asked. WSL repos via `wsl -e bash -lc`.

## Sequencing (why this order)

```
Phase 0  money integrity ──┐
                           ├─► Phase 3 go-live blockers ──► PILOT
Phase 1  stabilization ────┘         (VAT, EOD, audit chain, print jobs)
   │
   └─► Phase 2 complete the half-built ──► Phase 4 missing features
```

The critical path to a defensible pilot is **Phase 0 → Phase 3**. Everything else is value, not permission. Two ordering traps that are easy to get wrong:

1. **ADM-003 strictly before ADM-002.** Scheduling the charity round-up sweep before fixing its eligibility filter would forward donations for *rejected and voided* sales to the external charity ledger — real money moved for sales that never happened.
2. **CORE-001 before HH-004 and any new pricing feature.** Every offer type or discount scope added before the shared pricing core doubles the hand-synced surface that already produced nine separate audit findings.

## Phase 0 — remaining money-integrity fixes (7 of 10)

Each is surgical and independently shippable. All were adversarially re-verified against source.

### MC-001 — machine dead-letter + operator surfacing
`pos_machine/lib/data/order_sync_repository.dart:150-209`, `lib/data/db/app_database.dart:263-284`.
Today `flush()` retries every rejected row forever with no cap, no backoff, no parking — and `watchPending()` has **zero consumers anywhere in `lib/`**, so a permanently-rejected sale is invisible. Port the handheld pattern (`pos_handheld/lib/services/order_sync_service.dart:175-227`, commit `c5857d6`): count *server rejections* separately from transport failures (offline retry-forever stays correct), park after 5, surface a red drawer badge + stuck-sales tile + manual retry, and page Sentry on park.

### MC-002 — geofence payload re-enrichment
`pos_machine/lib/screens/staff_pos_screen.dart:381-399`, `lib/data/order_sync_repository.dart:154-167`.
An order enqueued without a GPS fix at a fenced branch is frozen into `eventsJson` and re-sent verbatim forever; the server fails closed on every replay. The code comment claims it "stays queued until a fix is obtained" — nothing ever re-enriches it. On flush, if a pending create/pay payload lacks GPS and the cached branch is fenced, acquire a fresh fix and patch the decoded events before pushing. Fix the comment either way.

### MC-003 — shared-shift orphaning
`pos_machine/lib/services/session_service.dart:244-248`, `lib/screens/staff_startup_gate.dart:29-35`; server side `pos_api/.../DeviceShiftController.php:61-65`, `CloseShiftHandler.php:110-128`.
The machine keeps the open shift across logout and skips the per-staff probe when any local shift exists, so cashier B sells under A's shift; the close attributes only the shift staff's orders plus staff-less orders on the opening device, and B's match neither. Verification established this is **platform-sanctioned, not machine-only**: `/device/shift/current` hands the device's open shift to any staff, pinned by a contract test. Fix: probe per staff at every login; if the local shift's staff differs and the cashier holds no shift, force close-drawer-or-open-float; gate the server's device fallback for `is_shared` shifts; add a contract test for a staff member ringing cash while holding no shift. Superseded properly by **DB-001** (`shift_id`), which makes attribution referential instead of temporal.

### API-001 — loyalty redeem must not roll back the sale
`pos_api/src/app/Actions/Device/Sync/ApplyLoyaltyRedeemAction.php:26-59`, `Handlers/PayOrderHandler.php:85,224-231`.
A strict redeem throws *inside* the pay transaction, rolling back payments, the paid flip, inventory, commission and earn — for a sale whose discount was already granted and whose cash was already taken. The failure is deterministic, so every replay re-fails. Catch it inside `PayOrderHandler`, settle the sale, clamp the redemption to the available balance, and record the shortfall as a flagged ADJUST for merchant review.

### API-002 — stranded-event sweeper
`pos_api/src/app/Actions/Device/IngestSyncEventsAction.php:60-99`, `Sync/SyncEventDispatcher.php:81-97`.
The `pos_sync_events` row commits *before* the handler runs, and ingest re-dispatches only `failed` rows — so a worker killed mid-handler leaves the event at `received` forever, retryable by neither side. Add a scheduled command re-dispatching `received` rows older than a threshold that have a registered handler (the age guard prevents racing a live request; handler-less types stay `received` by design). Separately, reject unknown `event_type` explicitly instead of silently ACKing it.

### ADM-001 — void guard on deferred effects
`pos_admin/src/app/Actions/Admin/Reconciliation/ReconcileDeferredEffectsAction.php:77-233`, `Http/Controllers/Api/Admin/PendingReconciliationController.php:54-63`.
Approving a pending card charge on a since-voided order writes a full commission split for a void sale and forwards a void-flagged donation to the charity app as `success`, overwriting the local void marker. Branch on `order.status === 'void'`: skip commission entirely, add `where('status','!=','void')` to the donation forward, badge voided orders in the queue and route them to a refund/exception flow rather than approve.

### ADM-003 → ADM-002 — charity sweep (order matters)
`pos_admin/src/app/Console/Commands/RetryRoundupForwarding.php:46-97`, `routes/console.php`, `docker-compose.prod.yml`.
**First** restrict sweep eligibility to `status = 'success'`, have `RejectPendingReconciliationAction` mark linked donations rejected, and pass the donation's real status instead of `null` (today it defaults to `fail` at the charity end). **Then** register the command hourly and add a scheduler service — nothing in the repo runs `schedule:run` at all today, so even the daily document-expiry scan never fires.

**Phase 0 exit test:** a scripted adversarial run — offline backlog + concurrent sales + forced rejections (loyalty over-redeem, deleted customer, no-GPS at a fenced branch) + a shift closed mid-backlog — loses no sale and strands nothing invisibly, on either device. Keep it as a regression suite.

## Phase 1 — architecture stabilization

### CORE-001 — the shared pricing core (`mithqal_pricing`)
The centrepiece. Nine separate audit findings are one root cause: two Flutter apps compute the same money from hand-ported code, and every new offer type or discount scope doubles that surface.

**Package**: `mithqal_pricing`, pure Dart (`sdk: ^3.11.0` — the floor of both apps), **no Flutter dependency** so `dart test` runs in CI without an emulator. New sibling repo `C:\src\projects\mithqal_pricing`. Because the two apps are separate repos, a bare path dependency breaks CI checkouts — use a **git dependency pinned to a tag** (the tag *is* the pricing version) with a gitignored `pubspec_overrides.yaml` path override for day-to-day dev.

Layout: `money.dart` (int-baisas helpers + the largest-remainder `allocateBaisas`, today duplicated as `_allocateExactly` in both engines), `line_totals.dart`, `discounts.dart`, `offer_engine.dart`, `comps.dart`, `taxes.dart`, `totals.dart` (the `priceOrder()` orchestrator), `split.dart`, `combo.dart`, plus `goldens/*.json` and `tool/checksum.dart`.

**Internal money is integer baisas.** Both apps currently do 3-dp double math with `toStringAsFixed(3)` at each step; the core converts once at its boundary and keeps everything integral, so the invariant `subtotal − discount − comp + tax == grand` holds **exactly** (0 baisa, tighter than the server's ±1 tolerance).

**The one discount semantic — DECIDED (biggest-wins).** Two distinct problems live here and only the second was ever a choice:

*Problem 1 — the handheld ignores targeted discounts. Not a decision; a bug.* `pos_handheld/lib/models/catalog.dart` `DiscountRule.fromMap` returns null for any rule that is not order-scope, so **every** product- and category-scoped promotion is discarded at parse — no overlap required, a single rule is enough. A merchant running "Coffee 10% off" is honoured on the till and charged full price on the handheld. Fixed as part of core adoption (step 3 below).

*Problem 2 — two rules matching the same item. Decided: keep biggest-wins.* The core adopts the **pos_machine** semantic as platform law: best single product/category rule per line; exactly one order slot (manual discount *or* order-scope rule *or* loyalty redemption, mutually exclusive); offers evaluate after line rules on line nets, one offer per unit; total clamped at raw subtotal. `stackable` is **deprecated** — core ignores it, config keeps emitting it (additive contract), pos_merchant hides the toggle, the column stays.

*Why not the blueprint's stacking evaluator:* it would reprice live carts. Worked example — a 2.000 coffee matched by both "Coffee 10%" and "Happy hour 20% drinks": biggest-wins charges 1.600 (what tills charge today), stacking charges 1.440. Rolling out stacking cuts merchant margin on every overlapping cart the day the APK ships, with no merchant action. `EvaluateDiscounts.php` has also never run in production, so the machine's behaviour — months of real receipts — is the de-facto contract.

**multi_buy fix in the core**: when a candidate set's discount computes ≤ 0, break **without** consuming the units (the handheld's behaviour, whose comment correctly calls the machine's consume-then-break "a real overcharge"). Pinned by golden `multi_buy_at_price_leaves_units_for_bogo`.

### MARGIN-001 — one promotion per item + a capped total
**The only deliberate live-pricing change in this plan.** Today `discountAmount = orderLevelDiscount + lineDiscountTotal + offerDiscountTotal`, clamped only at `rawSubtotal` (`pos_controller.dart:1072-1085`, whose comment states the stacking outright), and offers are computed on `lineNet = lineTotal − lineDiscount` — i.e. a discount and an offer are *designed* to both hit the same item. Worked case: a 2.000 coffee with a 10% line rule (0.200), a multi-buy offer (0.500) and a manager's 15% order discount (0.300) loses 1.000 — half price — and nothing caps it short of free.

**The rule the core enforces:**
1. **Per item: `max(lineDiscount, offerAllocation)`, never the sum.** Both are promotions; a customer gets the better one. Implemented in `totals.dart` after the offer engine returns, by comparing each line's discount row against its offer allocation and dropping the smaller — so `DiscountRow`s stay one-per-line-per-reason and `pos_order_discounts` still reconciles to `discount_total`.
2. **Order-level discount applies on top**, unchanged — staff/goodwill/manager reductions are an authority decision, not a promotion. Blocking them would push staff to void lines instead, which is worse and less auditable.
3. **Ceiling on total reduction**: new company setting `max_discount_percent` (default 50). `priceOrder()` returns `capExceeded` + the capped amount; the device requires a manager PIN to proceed, reusing `manager_authorization_service.dart` (machine) / the per-reason manager gate (handheld), and stamps the approver. Comps and gifts are **out of scope of the cap** — a 100% write-off keeps going through the existing comp flow, which already demands a reason and manager approval and reports separately from revenue.

**This changes prices**, so it needs the same care as a release: quantify first. Before shipping, run a read-only query over recent orders recomputing each under the new rule to count how many carts would have been cheaper and by how much — that number tells you whether this is a quiet fix or a customer-visible change needing merchant comms. Goldens: `promo_line_discount_beats_offer`, `promo_offer_beats_line_discount`, `promo_order_discount_still_stacks`, `cap_blocks_without_manager`, `cap_excludes_comps`.

*Open:* whether the cap counts the order-level discount only, or the promotional reductions too — recommend **total**, since the ceiling exists to stop a free cart however it got there.

**PHP counterpart — validator, not authority.** `pos_api/src/app/Support/Pricing/` ports the same engine in int baisas and runs in **warn mode only** after `assertMoneyInvariant`: recompute from the payload plus live rules, record `pricing_check` in the event result and log a warning on mismatch — never throw. Gated by a `pricing_enforcement` setting (`off|warn`, default `warn`; a `strict` value is reserved but not implemented). Devices send an optional `pricing_engine: 1`; the validator only compares when present, so old APKs and in-flight offline orders are never flagged. Pricing stays device-authoritative — this buys observability, not control.

**Golden vectors — the CI asset.** One JSON per case in the pricing repo (canonical). `pos_api` vendors a copy plus a `goldens.sha256` emitted by `tool/checksum.dart`, with a test asserting the vendored files match the checksum for the pinned engine version. The Flutter apps don't vendor — they consume the package and keep a thin smoke test proving their own `config_mapper.dart` / `catalog.dart` produce faithful core inputs. Mandatory coverage: every offer type × maxPerOrder × overlap; the multi_buy fix; bundle broken/intact; gift + order-discount clamp interplay; full-order comp with a gifted line; two taxes where round-then-sum ≠ sum-then-round; delivery exemption; discount clamp at raw subtotal; allocation exactness; equal and custom splits; the combo cases.

**Adoption order (no big-bang):** (1) build the package seeded from the machine's engine, goldens capturing *today's* behaviour, then add the multi_buy-fix vector as a deliberate, flagged change; (2) machine — `offer_engine.dart` becomes an export shim, controller getters delegate to one memoized `priceOrder()` keyed on the existing update nonce, `order_sync_payload.dart` consumes `PriceResult` rows instead of re-deriving them; (3) handheld — adopt the package **and fix `catalog.dart` `DiscountRule.fromMap`** so it stops discarding product/category-scope and auto-apply rules (this is HH-004, and after the core it is adoption rather than a port); (4) pos_api validator; (5) pos_merchant deletes `EvaluateDiscounts.php` and hides the toggle. No APK gate — the wire format is unchanged.

⚠ *Verify before deleting:* re-run a scoped grep for `EvaluateDiscounts` callers; the design agent's ripgrep timed out once and the "zero callers" claim, while consistent with the audit, was not exhaustively re-confirmed.

### DB-001 — `shift_id` linkage (unlocks EOD-001)
No `shift_id` exists in 153 migrations; shift money is attributed by time window plus staff/device identity, which is what orphans a second cashier's sales (MC-003).

**Migration `2026_08_09_010600`**: nullable `shift_id` FK + index on `pos_orders`, `pos_payments` (separate from the order's — a dine-in opened in shift A can be paid in shift B) and `pos_expenses`.

**Wire (additive, uuid-keyed).** Devices know the shift *uuid*, not the server id, so `order.create` gains `order.shift_uuid`, `order.pay` and `expense.log` gain top-level `shift_uuid`. Handlers resolve uuid + company + branch; a foreign uuid **fails the event** (consistent with `assertReferencesInTenant`); an absent field resolves to NULL (old APK). **Accept a `closed` shift** — an offline replay legitimately lands after its shift closed, and the sale still belongs to it. That is precisely the orphan being fixed.

**Migrating `CloseShiftHandler` from temporal to referential** without breaking a mixed fleet — a two-generation predicate:
```php
$scope->where('pos_orders.shift_id', $shift->id)              // new APKs: referential
      ->orWhere(fn ($legacy) => $legacy
          ->whereNull('pos_orders.shift_id')                   // old APKs: temporal
          -> /* existing shared/device predicate verbatim */);
```
The `whereNull` guard is what prevents double-counting during the transition: an order referentially owned by shift B can never also match shift A's temporal leg. Extract this into `App\Support\ShiftAttribution` shared by `CloseShiftHandler` and EOD's preview so the two cannot drift.

**Backfill is a command, not a migration** (per the migration rules): `php artisan pos:backfill-shift-ids {--company=} {--dry-run}`. Per closed shift, match NULL-shift orders by the legacy predicate within the window; an order matching **more than one** shift is left NULL and **reported, never guessed**. Payments follow their order, else the window-matching shift on the same device. `--dry-run` prints counts and the ambiguity list for operator approval; idempotent and chunked.

**Verification — the orphan regression test:** two shared shifts (cashiers A and B) at one branch, B rings a staff-less order on A's opening device; with `shift_uuid` sent, A's close excludes it and B's includes it. That case double-counts or orphans today. Plus a mixed-generation close counting one referential and one legacy order exactly once each, and both test-mirror schemas updated in the same PR.

### Remaining stabilization
- **API-004 wire hardening**: tender sign/range (`min:0` integer — today `[cash +10, card −5]` balances the invariant and skews the commission channel split), Σ(discount rows) vs `discount_total`, Σ(line totals) vs subtotal, and `lockForUpdate` + status re-check in `DeliverOrderHandler` (copy the pay/void pattern — concurrent delivers can double-consume today).
- **API-005**: move sync processing to a queue worker so a long offline backlog cannot time out mid-batch; the HTTP push only enqueues.
- **SEC-001** device-token hashing (add hash column → dual-read one release → re-issue → drop plaintext). **SEC-002** authenticate and sign the charity forward, and reject unauthenticated posts at the charity endpoint.
- **COM-001** legacy commission backfill: split `channel='all'` rows per channel from tender slices, dry-run-report first. Until it runs, exclude legacy `all` rows on mixed orders from payout claiming — the leak is **still live** for pre-fix rows, pinned by an existing test.
- **CORE-003** cross-repo drift guard for the PHP twins (`RecordSaleCommissionAction` pos_api↔pos_admin, `EvaluateLoyalty` pos_api↔pos_merchant) — currently identical but guarded by nothing.



## Phase 2 — complete the half-built

### Reporting truth (RPT-001…004)
- **RPT-001 business-timezone dates.** Every merchant, admin and device report snaps bare `YYYY-MM-DD` to **UTC** days while Oman runs UTC+4, so midnight–04:00 sales land on the previous day and hour-of-day charts are rotated four hours. Fix once in the shared `BusinessDay` support introduced by EOD-001 (per-company IANA timezone, default `Asia/Muscat`), applied in `ReportFilter::fromArray`, the admin `parseBoundary`, and `BuildBranchReportAction`; bucket day/hour via `AT TIME ZONE`. Storage stays UTC. *(The codebase already knows this — `CreateAdInvoiceAction` documents "Muscat is UTC+4, so the day boundary falls at 04:00 local" — but only for ad billing.)*
- **RPT-002 comps.** `net_sales = SUM(subtotal) − SUM(discount_total)` with **no comp term**, though the server invariant proves comped food collects no money. Subtract `comp_total` in both merchant and admin sales reports and expose it as a headline key; the Z-report and device branch report already deduct it, so today the till and the portal disagree about the same day.
- **RPT-003 pending money.** Paid orders whose card tender is `pending_reconciliation` have their commission deferred, and the report treats "no ledger rows" as a no-profile sale — flowing the full total into both `merchant_net` and `finalized_net` with zero commission. Route them to `pending_net` and give `SaleCommissionStatus` a distinct state so the orders list and the sales report stop contradicting each other.
- **RPT-004 report-specific**: Loss/Waste must exclude transfers-out and production consumption (the newer variance report's docblock already calls this "the bug this avoids" while the buggy version still ships); drop `Adjustment` from consumption types (routine corrections currently trigger the >20% theft anomaly flag); COGS must read `consumption_snapshot_json` and value cooked/unit products (they show 100% margin today); orders-viewer money totals default to paid-only.

### Other Phase 2 items
- **PAY-001** bank reconciliation matches `amount + COALESCE(roundup_amount, 0)` — every round-up card charge currently lands in `amount_mismatches` because the capture includes the donation but `pos_payments.amount` does not.
- **VOID-001** new `order.item_void` sync event: line ids + reason + refund amount, with proportional inventory / loyalty / commission / round-up unwind server-side; the device's partial-cancel path emits it and persists the reason it already forces the cashier to pick and then discards. **VOID-002** a tender-reversal / cash-out record type so voided cash leaves expected cash and card-paid voids are trackable.
- **LOY-001** loyalty expiry, rule validity windows and the documented restrictions (none are implemented); exclude comps from the earn base so write-offs stop earning points.
- **Device parity**: HH-004 (handheld discount scopes — becomes core adoption after CORE-001), MC-004 (multi_buy, fixed in the core), HH-005 (Sentry DSN so the parked-revenue paging stops being a no-op, remove the mock-catalog fallback for activated devices, add round-up), MC-005 (durable outbox write before GPS/customer call + re-enqueue from local history), MC-006 (deterministic event ids for shift.close/expense/restock), INV-003 (drain the outbox before config polls — the machine currently resurrects shelf stock queued sales already consumed).
- **SEC-003**: bind the manager fingerprint gate to an identity (any device-enrolled finger currently passes offline manager approvals), remove `usesCleartextTraffic` from the release manifest, remove the hardcoded default super-admin password, wire `EnsureUserIsAuthenticated` into the admin API group.
- **UI-001** ingredient branch-transfer front end — the backend `pos_branch_transfers` exists with no way to use it.



### INV-001 — GRN receiving must update ingredient cost
**The defect:** `RecordPurchaseAction:219-229` (the piece-purchase form) sets `default_unit_cost = total/units` and last-batch-wins `units_per_piece`. `ReceiveIngredientStockAction` (the GRN path) does **neither**, and snapshots its movement at the *stale* `default_unit_cost` (line 110). GRN-only merchants therefore freeze months-old costs into every COGS snapshot, waste valuation and variance figure.

**Fix — one shared implementation so the drift cannot recur:**
- Extract **`ApplyPurchaseCostToIngredientAction`**: given (ingredient, units, totalPaid, pieces?, isLoose) → set `default_unit_cost = number_format(total/units, 3)` when paid > 0, and `units_per_piece` last-batch-wins for loose batches. `RecordPurchaseAction` delegates to it; `ReceiveIngredientStockAction` calls it too.
- `ReceiveIngredientStockAction` additionally: snapshot the movement at the **batch** cost (`cost/qty`), not `default_unit_cost`; write a `pos_ingredient_purchases` row (`branch_id` NULL for central, `stock_movement_id` linked) so GRN purchases appear in the same per-ingredient purchase history as piece purchases.
- `CreatePurchaseReceiptAction::writeLine` threads `pieces` and computes `unit_price = line_cost/quantity`, stored on the line — this is also what supplier returns later reverse at.

**Migration `2026_08_08_030000`**: `pos_ingredient_purchases.branch_id` → nullable (central receipts); + `purchase_receipt_line_id` FK nullable.

**Price creep** (Aug spec 5.2): baseline = effective `pos_supplier_item_prices.unit_price` → else latest `pos_ingredient_purchases.unit_cost` for (ingredient, supplier) → else latest for the ingredient. Store `price_variance_pct` on the receipt line; flag beyond `price_creep_tolerance_pct` (company setting, default 5). Surfaces on GRN show/index and the supplier scorecard.

**No pos_api change** — it reads `default_unit_cost` when freezing snapshots (`CreateOrderHandler::snapshotRecipe:674`) and picks up the fresher value automatically.

**Backward compatibility:** existing receipts keep NULL `unit_price` and fall back to `line_cost/quantity`. Historical COGS snapshots are frozen and untouched. ⚠ **Release note required**: after deploy the first GRN moves `default_unit_cost`, so recipe costs and future snapshots shift for merchants whose costs have been frozen for months. That is the defect being fixed, but it will look like a change.

**Verification:** byte-compare final ingredient state after a GRN against an equivalent `RecordPurchaseAction` call (the "identical cost state" test); movement `unit_cost_at_time == X/Q`, not the pre-receipt cost; loose line rewrites `units_per_piece`, fixed-pieces line does not; zero-cost line changes nothing (free samples).

### INV-002 — count reconciliation against a timestamp
Ships with CNT-001's server half (see Phase 4) but is a **defect fix and needs no APK change**, so it can ship in this phase. Both `SubmitStockCountAction` (portal) and `StockCountHandler` (pos_api) compute expected from the *current* balance at apply time, so a sale landing after the count double-depletes and over-blames waste. Replace with:

```
expected(counted_at) = current balance
                     − Σ movements WHERE branch/ingredient match AND occurred_at > counted_at
```

`StockCountHandler` **already parses `counted_at`** (falling back to `client_timestamp`), and both apps already send it — so deployed devices get the fix for free. Indexes `(branch_id, occurred_at)` and `(ingredient_id, occurred_at)` already exist.

*Honest residual:* an offline sale with `occurred_at < counted_at` that syncs after the count still double-counts. Inherent to offline; mitigate by draining the outbox before counting (pairs with MC-001/INV-003).


## Phase 3 — go-live blockers

Build order within the phase: **DB-001 → VAT-001 (start Flutter early, longest APK lead time) → EOD-001 (consumes DB-001) → PRT-001 (independent)**. AUD-001 runs alongside.

### VAT-001 — Oman VAT-compliant tax invoices
**Verified starting point:** `pos_companies` already carries `legal_name`, `legal_name_ar`, `vat_number`, `cr_number` — but **pos_api never reads them** (zero hits for `vat_number` in `pos_api/src/app`). The machine hardcodes `row('Tax (5%)', …)` at `sunmi_receipt_service.dart:159`; the handheld has no i18n at all.

**Data model**
- `2026_08_09_010000_create_pos_order_taxes_table.php` — per-rate breakdown frozen at sale (a queryable table, not a JSON blob, so a future VAT-return report can roll it up): `order_id`, `company_id`, `branch_id`, `tax_id` (nullable, `pos_taxes` soft-deletes), `name_snapshot`, `name_ar_snapshot`, `rate_percent` decimal(5,2), `base_amount`, `amount` decimal(12,3). Indexes `(order_id)`, `(company_id, created_at)`.
- `2026_08_09_010100_add_tax_invoice_fields_to_pos_orders.php` — `tax_invoice_number` varchar(40) nullable + **non-unique** index `(company_id, tax_invoice_number)`, `tax_invoice_issued_at`.

**Do not overload `receipt_number`**: it is nullable offline and daily-resettable by merchant policy, so numbers legitimately repeat across days — both disqualify it as the legal invoice number.

**Numbering — the load-bearing decision.** Every printed receipt needs a number *including fully-offline sales*, so a server allocator cannot work. Use a **per-device series** `INV-{device_id}-{seq}`, counter persisted in Drift, with `/device/config` `meta.next_tax_invoice_seq` = `MAX(seq for this device) + 1` so a wiped/re-paired device cannot reuse numbers; device takes `max(local, server)` at each sync. Non-unique index means a lost counter can never brick sync; a weekly duplicate/gap report surfaces anomalies. ⚠ *Per-register (not company-wide) sequencing needs legal sign-off — see open decisions.*

**Server:** `BuildDeviceConfigAction` gains an always-emitted `company` slice (name, legal names AR/EN, vat_number, cr_number) as the **authoritative** identity — the merchant-typed `branch.receipt_template.vat_number` becomes a fallback. `CreateOrderHandler` accepts optional `order.tax_invoice_number` and `taxes[]` `{tax_id, name, name_ar, rate_percent, base_baisas, amount_baisas}`; asserts `Σ amount == tax_total_baisas ±1` beside the existing invariant; tenant-guards `tax_id` **softly** (unresolvable → NULL FK, snapshot stands — the `discount_id` precedent, *not* the hard `offer_id` rule, so an offline order never fails over a deleted tax); writes `pos_order_taxes` inside the existing transaction and adds them to `purgeOrderChildren()` so hold→finalize replaces them.

**Clients:** machine — replace the hardcoded tax row with one row per `order.taxLines` (the getter already exists at `pos_models.dart:1575`); add the `TAX INVOICE / فاتورة ضريبية` header, legal name AR+EN, VAT No., invoice number, bilingual labels (Arabic already renders — `businessNameAr` prints today); **freeze `taxLines` into `OrderSnapshot`** (today they are recomputed from live company taxes, so a reprint after a tax change would print different numbers); reprints pass `isCopy` and print `COPY #n — نسخة`. Handheld — `kozen_printer_service.dart` already takes a config-driven `taxLabel`; extend to a list plus the invoice header, using fixed bilingual constants rather than introducing an i18n framework.

**Backward compatibility:** all fields optional; old APKs keep working (just non-compliant, the status quo). Deploy order: backend accepts → APKs send and print.

**Verification:** taxes rows persisted and the sum invariant enforced; deleted `tax_id` still settles; payload without taxes still settles (old-APK); hold→create upsert replaces tax rows; receipt golden tests EN/AR, multi-tax, and **zero-tax delivery printing no tax line at all** (kills today's "Tax (5%) 0.000").

**Open decisions:** (1) per-device vs per-branch series — recommend per-device, needs compliance sign-off; (2) tax-inclusive display — recommend keeping the exclusive engine and deferring; (3) simplified vs full invoice above 500 OMR — recommend simplified always for now, flag for sign-off.

### EOD-001 — branch end-of-day close + day lock
**Verified starting point:** `CloseShiftHandler` reconciles **cash only**; card/online are informational. No business-day entity exists in 153 migrations.

**Data model**
- `2026_08_09_010200_create_pos_business_days_table.php`: `company_id`, `branch_id`, `business_date` date, `status` (open/closed), `opened_at`, `closed_at`, `closed_by_pos_staff_id`, `closed_by_portal_user_id`, expected/counted/variance triplets for **cash and card**, `online_total`, `other_total`, `late_capture_total`, `summary_json`, `note`. **Unique `(branch_id, business_date)`**; indexes `(company_id, business_date)`, `(branch_id, status)`.
- `2026_08_09_010300_add_business_day_links.php`: `pos_shifts.business_day_id` + `force_closed`; `pos_orders.business_day_id` + `is_late_capture`; `pos_payments.business_day_id`.
- Business date derives from a `pos_company_settings` key `business_day` = `{"timezone":"Asia/Muscat","cutoff":"04:00"}`. New `App\Support\BusinessDay` (pos_api) + a pos_merchant twin — **this also becomes the seat for the RPT-001 timezone fix**, so the UTC-day defect gets solved once, in one place.

**Day lock with the offline-replay exception (the hard requirement).** A sale replayed from a device that was offline must never be lost. So the lock is asymmetric: `order.create`/`order.pay` for a closed day are **not rejected** — they stamp the branch's current *open* day with `is_late_capture = true`, keeping original timestamps, and the merchant report shows a "late-captured (belongs to {date})" line. Hard rejection is reserved for genuinely new activity: `shift.open` into a closed date (error `business_day_closed`), and portal mutations of rows in a closed day.

**Server:** `OpenShiftHandler`, `CreateOrderHandler`, `PayOrderHandler`, `ExpenseLogHandler` stamp the day (materialized lazily via `insertOrIgnore` on the unique — the `AllocateOrderNumberAction` pattern). New online-only endpoints: `GET /device/eod/preview` (open shifts + running cash/card/online totals) and `POST /device/eod/close` (throttled on the `pos-login` bucket since it carries a manager PIN) → `CloseBusinessDayAction`: verify PIN, `lockForUpdate` the day, **precondition zero open shifts** except those explicitly listed in `force_close_shift_uuids` (closed with `force_closed = true`), compute expected cash from shift sums and card totals from `pos_payments`, freeze `summary_json`, flip closed. Result shaped like `shift.close` so the device prints a Day-Z with the existing line builders. pos_merchant gets `ListBusinessDaysAction`, `ShowBusinessDayAction`, `ReopenBusinessDayAction` (permission-gated, audited).

**Clients:** machine gets `eod_close_screen.dart` offered after the last shift closes, printing via the existing `printTicketLines()` entry point and gated by `manager_authorization_service.dart`. Handheld needs nothing in v1 — its shifts appear in preview and can be force-closed.

**Backward compatibility:** all links nullable; days materialize lazily so branches that never run EOD behave exactly as today. Old APKs lack the button.

**Verification:** happy path with cash+card variances; precondition failure with an open shift; force-close stamps the flag; `shift.open` into a closed date rejected; **order replayed after close lands on the open day with `is_late_capture` and original `opened_at`**; cutoff boundary (23:59 vs 03:59 same business date); second-branch isolation.

**Open decisions:** (1) counted card source — recommend a manual keyed settlement total (matches Mosambee reality), nullable; (2) reopen authority — recommend merchant portal, audited; (3) `pos_expenses.business_day_id` now or derive — recommend derive; (4) cutoff default 04:00 Asia/Muscat, merchant-overridable.

### PRT-001 — print-job domain (printer failover)
**Verified starting point:** printing is fail-safe fire-and-forget; the Reverb branch channel exists but carries only delta-sync nudges; **neither Flutter app ever calls `/device/heartbeat`** — the endpoint is server-side-only dead code today, so "printer status in the heartbeat" requires adding the heartbeat loop itself.

**Data model** — `2026_08_09_010400_create_pos_print_jobs_table.php`: `company_id`, `branch_id`, `target_device_id` (nullable = any claimer at the branch — **this is the future print-agent seat**), `printer_role` (receipt/kitchen/report; KDS-001 later adds `station_id` here), `job_type`, `order_id`, `payload_json` (self-contained styled lines so any device can print it), `status` (queued/claimed/printed/failed/cancelled), `attempts`/`max_attempts`, `available_at` (backoff gate), `claimed_by_device_id`, `claimed_at`/`printed_at`/`failed_at`, `last_error`, `origin`, `is_reprint`/`reprint_of_job_id`. Indexes `(branch_id, status, available_at)`, `(company_id, created_at)`, `(order_id)`. Plus `2026_08_09_010500` adding `last_printer_status` + `last_printer_status_at` to `pos_devices`.

**Two producers, one consumer contract.** *(A) Device-originated* — printing stays local-first (the network never enters the print path); a new sync event `print.job.report` upserts the row so the portal can see "branch X has failed 6 receipts since 12:40", sending `payload_lines` only on failure so another device can reprint. *(B) Server-originated* — `CreatePrintJobAction` writes `queued` and broadcasts `print.job.created` on the existing branch channel. Since pos_api runs **no queue worker**, retries are pull-shaped: `GET /device/print-jobs/pending`, `POST …/claim` (atomic `lockForUpdate`, loser gets 409), `POST …/ack` (printed, or re-queue with backoff 2s/10s/30s, or park `failed` at max attempts), `POST …/reprint` (clones with `is_reprint` — also the audit trail that a VAT invoice was reprinted).

**Clients:** machine — `sunmi_receipt_service` returns a structured result instead of a bare bool; a new local print-job queue in Drift (additive schema step v27→v28) retries 3× with backoff then parks and reports; **a red banner driven by a stream the UI actually consumes** (pointedly unlike the orphaned `watchPending()` MC-001 fixes) with one-tap reprint. Add the missing 60s heartbeat loop sending GPS/battery/app_version/printer_status. Handheld follows the same pattern over `kozen_printer_service.dart` — but **after HH-001**, whose outbox race would otherwise swallow print reports. *Unverified:* whether `sunmi_printer_plus ^4.1.1` exposes paper-out state; if not, status degrades to ok/error/unavailable inferred from the last print.

**Verification:** claim race (two devices, one 409); ack-fail re-queues with a future `available_at`; third failure parks; reprint clones; tenant isolation on claim; `print.job.report` upsert idempotent on re-push; heartbeat persists printer status.

**Open decisions:** (1) backoff on-device (recommended — no server scheduler exists) vs moving expiry sweeping to the scheduler ADM-002 adds anyway; (2) payload as styled lines (recommended, replayable anywhere) vs order-ref only; (3) prune printed jobs after ~30 days.

### AUD-001 — audit-log tamper evidence + tenant sampler
`pos_audit_logs` is ORM-immutable (`booted()` throws on update/delete) but has **no hash chain**, so silent row deletion at the DB layer is undetectable. Add `hash` + `previous_hash` columns and a nightly job computing the rolling chain (blueprint §9.13.5), plus the nightly tenant-integrity sampler (§9.11.7) that asserts random rows are visible only to their owning tenant. Both need the scheduler service ADM-002 introduces.


## Phase 4 — missing blueprint features

Order: **PO-001 → SUP-001 → CNT-001 → VAR-001** (inventory chain), and **COMBO-001 → KDS-001 → QR-001** (channel chain, all downstream of CORE-001). Migration sequence matters: `010000` supplier catalogue → `010100` POs (FK supplier items) → `010200` receipt links → `020000` returns/credits (FK receipts) → `030000` batches → `040000` counting → `050000` yield.

### PO-001 — purchase orders + partial receiving
`pos_purchase_orders` (company, supplier, `destination_branch_id` nullable = central, per-company `po_number`, status draft/open/partially_received/closed/cancelled, `expected_at` feeding on-time scoring, frozen `ordered_total`) and `pos_purchase_order_lines` (item XOR ingredient/product, `supplier_item_id`, snapshots, `qty_ordered`, `unit_price` decimal(12,6), **`qty_received` running total**, **`qty_rejected`**, status open/partial/received/short_closed/cancelled, `short_close_reason`). Outstanding is **computed** (`ordered − received`), never stored, so it cannot drift. Receipt tables gain nullable `purchase_order_id` / `purchase_order_line_id` plus `pieces_received`, `unit_price`, `qty_rejected`, `rejection_reason`, `over_delivery`, `over_delivery_approved_by_user_id`, `price_variance_pct`, `ingredient_purchase_id`.

**`ReceivePurchaseOrderAction` — the door flow**, one transaction: lock the PO and lines; **`qty_received` is required and never pre-filled** (the spec's central rule — a pre-filled confirm books stock that does not exist); when outstanding remains, a `decision: backorder | short_close` is **required**, so the choice is forced at the door in one tap rather than accumulating half-open POs; over-delivery beyond `po_over_delivery_tolerance_pct` (default 5, company setting) needs manager approval, within tolerance passes flagged; GRN lines are built from **accepted quantity only** and delegate to the existing `CreatePurchaseReceiptAction`, so **stock still enters exclusively through the existing receive pipeline — no new ledger writer**. Rejected quantity writes **no stock movement and no waste**; it raises a supplier credit note (`origin = door_rejection`) in the same transaction.

Supplier fill-rate is computed (`Σ received / Σ ordered` over terminal lines), never stored. **The no-PO path is untouched** — `purchase-receipts.store` keeps working with `purchase_order_id` NULL, and the chef-with-cash `RecordPurchaseAction` is not modified at all.

*Open:* `po_number` via a dedicated counter row (recommended, mirroring the order-number pattern) vs `MAX+1`; over-delivery gate as `inventory.manage` + manager re-auth (recommended) vs a new permission.

### SUP-001 — supplier returns, credit notes, catalogue, scorecard
**A return is not waste.** New `StockMovementType::SupplierReturn` (the column is a plain string — no migration needed for the enum case). `CreateSupplierReturnAction` writes negative movements through `WriteStockMovementAction` at the **original received cost** — resolution order: the receipt line's `unit_price` → latest batch cost for (ingredient, supplier) → `default_unit_cost` flagged as a fallback — and writes **no waste record**. Must also add `->where('movement_type','!=','supplier_return')` to `LossWasteReportAction`, or returns inflate its already-overstated shortfall.

`pos_supplier_credit_notes` carries the chain `raised → accepted → received → reconciled` with `origin` (return / door_rejection / price_correction / manual), so **credits are creatable without a return** (supplier billed the wrong price), plus the "outstanding credits owed to us, by supplier" report the spec calls found money. `pos_supplier_items` + `pos_supplier_item_prices` (effective-dated) give per-kilogram comparison across suppliers, and `pos_suppliers` gains `lead_time_days` + `delivery_days` so par-level reordering can respect them. The scorecard (fill rate, on-time, rejection rate, price creep, return rate, outstanding credits) is assembled entirely from data the other features already capture — no new writes.

*Open:* P&L effect of a received refund credit — recommend v1 books nothing (the cash model already expensed the purchase; the credits report carries the receivable).

### CNT-001 — blind counting
`pos_ingredients` gains `count_frequency` (daily/weekly/monthly), `storage_area`, `count_sort_order`; `pos_stock_counts` gains `count_scope` and `is_blind` (recording whether expected was actually hidden — evidence for the integrity report). Company settings: `blind_stock_counts`, `count_backdate_limit_hours`.

Hide the expected quantity at **entry** on the portal and both devices (keep it in the post-submission **review** view — blind applies to counting, not auditing); order the list by `storage_area` then `count_sort_order` (walking order roughly doubles counting speed); tier the schedule by value; add a `GET .../stock-counts/due` endpoint computing what is due per tier. New `CountIntegrityReportAction` flags recorders whose figures match theoretical perfectly — genuine counting is never that clean.

The **timestamp reconciliation half ships in Phase 2** (INV-002) because it needs no APK change. Devices must keep receiving `branch_stock` in config regardless of blind mode — sold-out gating depends on it; blind is strictly display suppression. Old APKs keep showing the balance (unenforceable there), which is why `is_blind` records reality per count.

*Open:* default `blind_stock_counts` on for new companies, off for existing until the merchant opts in — avoid surprising field staff mid-rollout.

### VAR-001 — yield factors + the honest variance report
`pos_ingredients.yield_factor` decimal(6,4) default 1.0000 and `variance_tolerance_pct` (nullable → company default 2.0).

**Where yield applies is the load-bearing decision. Phase 1: report-level gross-up only** — `theoretical_gross = theoretical_net / yield_factor`, with ledger, snapshots, COGS and balances untouched. Zero risk to the frozen-snapshot contract, zero APK impact, fully reversible. **Phase 2 (optional, behind `yield_in_consumption`)**: gross up the quantity in `CreateOrderHandler::snapshotRecipe` — server-side, so still no APK change — which makes book depletion match physical usage and stops counts booking trim as variance waste. ⚠ The report must not gross up twice: gate both on the same key. Recommend shipping phase 1 and deciding after a month of data.

`IngredientVarianceReportAction` computes per (branch, ingredient) from signed movement sums with frozen `unit_cost_at_time` for money, modelled on the existing portion-variance bucket discipline and **fixing what Loss/Waste gets wrong**: transfers and production get their own columns and are never loss. `expected_close = opening + received ± transfers − theoretical − production − yield_loss − waste − supplier_return`, versus counted; every bucket reported in quantity **and OMR**, sorted by cost of variance, flagged only past tolerance. Headline test: yield 0.8 with a matching physical count must read **zero unexplained** — the false-variance case the spec calls the largest source of noise.

*Open:* fix `LossWasteReportAction`'s depletion bucket now (changes numbers merchants watch) vs deprecate its shortfall section in favour of the new report — recommend deprecate-and-point, remove one release later.

### COMBO-001 — combos as a bounded extension
`pos_products` gains `is_combo`, `combo_price_mode` (`fixed` | `sum_discount` | `component_override`), `combo_discount_percent`. `fixed` mode reuses `base_price` — no new money column, so menus, config and reports read it unchanged. `pos_combo_slots` (label, qty, `is_substitutable`, `default_product_id`) + `pos_combo_slot_options` (`price_delta` for upgrades, `override_price` for the third mode). `pos_order_items` gains `combo_key` + `combo_product_id`; `pos_order_discounts` gains `combo_product_id` for the allocation rows.

**The device explodes slots into real order lines** at their normal price snapshots, tagged with a `combo_key` — reusing the proven `bundleKey` mechanics (no merging, atomic removal, excluded from offer units). The combo's price advantage is allocated across those lines with the core's largest-remainder allocator as `pos_order_discounts` rows, so **per-component margin reporting keeps working** and the discount is auditable. Consumption needs **zero changes**: each component is a real line with its own frozen snapshots — which also **dissolves the Aug spec's open question** about where a modifier's stock impact attaches inside a combo (it attaches to the component it modifies, because that component is a real line).

**Capability gating for old APKs**: the device sends `?caps=combo,kds` on config; non-capable devices don't receive combo products and get them purged in deltas (the existing `is_internal` precedent). Otherwise an old APK would sell the combo tile as a plain product with no components.

*Open:* charge `price_delta` on default options too — recommend no, deltas only on substitutions.

### KDS-001 — stations, routing, waiter screen
`pos_kitchen_stations` (per branch, `is_default`) + `pos_category_station_routes` (unique per branch+category — categories are company-wide but routing must be per-branch). **No route row means the default station**, so single-kitchen merchants configure nothing. `pos_order_tickets` (per station, new → preparing → done, `fired_unpaid`) + `pos_order_ticket_items`; `pos_orders` gains `ready_at` / `collected_at`.

Ticket state lives on **tickets**, deliberately not on the never-written `kitchen` order status, so old APK status handling is untouched. `CreateOrderTicketsAction` groups items by product → category → route (fallback default) and broadcasts per ticket. Gated by `kds_mode` (`off` default — zero change for existing merchants; `screens`; `screens_and_paper`, which keeps POS paper printing alongside screens as the spec requires).

**Screens are web pages on existing plumbing**: a slim SPA served by pos_api, activating as a **real device row via the existing single-code activation**, authenticating with the normal device token, and subscribing to the existing `private-branch.{id}` channel — whose own code comment already calls it "the main POS / handheld / KDS feed". No new auth system, no drivers, no ESC/POS. When every ticket of an order reaches `done`, stamp `ready_at` and broadcast `order.ready`; the pass/waiter screen renders the **union of all stations' items under the one parent order**, and `collect` stamps `collected_at`.

*Open:* station-attached printers under `screens_and_paper` — recommend no; paper stays POS-printed, since station printers reintroduce exactly the driver burden KDS exists to avoid. Single-step recall (`done → preparing`) — recommend yes, clearing `ready_at`.

### QR-001 — QR ordering + drive-up
**Where it lives (decision):** a public API in **pos_api**, with the customer SPA served from the same repo at `/m/*`. QR orders must land in the existing order lifecycle, and pos_api already owns it — handlers, tenant guards, snapshots, Reverb, and public throttled endpoints. pos_merchant is a session/CSRF back-office; bolting a public surface there widens its attack surface and couples deploys. A separate service is overhead against the same DB with no isolation gain.

**Auth without a device token:** the QR encodes `/m/t/{qr_token}` (existing `pos_tables.qr_token`) or `/m/b/{qr_token}` (new `pos_branches.qr_token`). The SPA exchanges it for a **signed, short-lived capability token** sealing `{company, branch, table?, service, exp}` — no account, no PII, revoked implicitly by regenerating the QR (the table action already exists; add the branch twin).

**Server-authoritative pricing** — this is why the PHP engine from CORE-001 exists beyond validation: the customer's browser is not a trusted device, so `CreateQrOrderAction` prices the cart itself, then builds the exact `order.create` block and calls `CreateOrderHandler::writeOrder` through a lazily-created **virtual device row per branch** (`pos_devices.is_virtual`), reusing validation, tenant guards and snapshot freezing wholesale rather than duplicating them. `source = customer_qr`; `order_type = dine_in` or **`car`** — the first real writer of that reserved type.

**Holding and deliberate release:** QR orders land `held` (old APKs already render held orders in actives). `POST /device/orders/{uuid}/release` flips to `open`, fires tickets and broadcasts. A **paid** order skips holding and fires immediately; releasing while unpaid sets `fired_unpaid`, which shows an UNPAID badge on the KDS card and waiter screen until payment lands — so food is not handed over before money is collected.

**Drive-up:** arrive-then-order only (no scheduling fields exist anywhere). The geofence is a **soft prank filter, not a security control** — check distance at roughly 4× the branch radius when the browser grants location, and **allow when it does not**, stamping `geo_unverified`. Reuse the haversine math but explicitly **not** the fail-closed policy. One optional free-text `car_description` ("silver Hyundai, near the entrance"), 120 chars, no plate, no dropdowns — shown on the POS actives card, kitchen ticket and waiter screen.

*Open:* offers/discounts on the QR menu in v1 — recommend no, add in v1.1 once the PHP engine has offer parity; auto-void unreleased QR orders after ~30 minutes — recommend yes.



## Companion documents

- **`MITHQAL_2.0_SYSTEM_AUDIT.md`** — what is true today: the 99-requirement gap analysis against all three blueprints, 141 verified findings, per-flow correctness audits, health scores.
- **`docs/audit-evidence/`** — the 22 per-domain evidence files with `file:line` citations, the consolidated findings register, and the adversarial verification verdicts.

The audit answers *what is true today*; this document answers *what to build and how*.

## Verification

- **Golden-vector CI** (Phase 1): one JSON fixture set of carts asserted identically by the Dart package, the PHP validator, and both apps — any pricing divergence fails in all three repos.
- **Contract tests** for every server change, specifically the cases that let real defects through: `change_given` non-zero, a negative tender, discount rows not summing to `discount_total`, concurrent `order.deliver`, an unknown event type, a soft-deleted void reason, a staff member ringing with no shift.
- **Money reconciliation test**: one seeded mixed day (cash, card, split, comps, voids, pending-reconciliation, delivery, round-ups) asserting the Z report, merchant sales report, admin report, commission ledger and device branch report all agree. Today they would not.
- **Adversarial review** on every Phase 0/1 money change — it found two blockers in HH-001's first cut and three in HH-002's, including one where I had spotted the risk and wrongly dismissed it.
- **Pricing-impact dry run before MARGIN-001 ships**: recompute a window of recent orders under the new one-promo-per-item rule and report how many carts change and by how much. It is the only change in this plan that moves live prices, so it ships on evidence, not assumption.
