# Phase 0 Failure: EXIT-11 — approval action misses a void committed after candidate hydration

- Status: **REFUTED / FAIL-TEST — adjudicated 2026-08-13 on real PostgreSQL** (see Adjudication below; no product change required)
- First observed: 2026-08-13 (Asia/Muscat), T2 lane execution
- Repository/branch/SHA: pos_admin, main, `972a1a1`
- Scenario/test: EXIT-11 / `tests/Feature/Admin/Phase0Exit/MidFlightVoidRaceTest::it approval racing a mid-flight void stays terminal` (kept failing at line 146)
- Command: `wsl -e bash -lc "cd .../pos_admin && docker compose exec -T pos_admin php artisan test tests/Feature/Admin/Phase0Exit"`
- Disposable environment identity: SQLite `:memory:` in the pos_admin container (single-process deterministic interleave via `eloquent.retrieved` hook — the exact technique the repo's own RetryRoundupForwardingTest uses)

## Expected
EXIT-11: "reconciliation approval races void → void is terminal; no new commission and no successful donation forward."

## Actual
An `order.void` (order + donation) committed immediately AFTER `ApprovePendingReconciliationAction` hydrated its order candidate is MISSED: the action checks `isVoid()` only on the already-hydrated model (`app/Actions/Admin/Reconciliation/ApprovePendingReconciliationAction.php:60-66`) and never revalidates. Observed on the voided sale: pending tender flipped to success, **3 `pos_sale_commissions` rows minted** (0.100/0.150/4.750 on 5.000), `payment.reconciled` + `order.reconciliation_approved` audits written. Two sub-contracts held even in the race: zero charity HTTP, donation status never overwritten (`queueDonations` re-reads fresh and excludes void). First failure: "Failed asserting that 3 is identical to 0."

## Reproduction
Deterministic in-process: `eloquent.retrieved` hook voids order+donation after candidate hydration, before the tender flip. Contrast tests in the same file prove the bank-file path (`ReconcilePaymentsAction`) re-reads orders fresh under `lockForUpdate` and its void guard WINS under the identical technique — the approval path lacks that revalidation.

## Adjudication caveat (why "pending")
On production PG, `SELECT … FOR UPDATE` makes hydration+lock atomic and order.void reportedly takes the same order lock first, so this exact interleaving may be unreachable outside SQLite. The integrated harness (EXIT-11 W-X: device-originated void through pos_api racing an in-flight admin approval on two real PG connections) decides live-defect vs. defense-in-depth-only. Either way the code-level asymmetry vs. the bank-file path is real.

## Scope/impact
If live: permanent phantom commission rows on a voided sale (the only deleter already ran) and a tender flipped to success on refunded money — the exact ADM-001 class. Contained: donation never forwarded; payout/invoice claiming still excludes void orders.

## Test-only changes
`tests/Feature/Admin/Phase0Exit/MidFlightVoidRaceTest.php` (new file; no production change).

## Implementation owner requested
~~pos_admin (`ApprovePendingReconciliationAction`): re-read the order under `lockForUpdate`~~ — WITHDRAWN by the adjudication below. No implementation work required.

## Adjudication (2026-08-13, integrated gate run `shakeb`, disposable PG 16)

**The interleaving is unreachable on PostgreSQL; the SQLite test manufactured it.** Code facts
(cited by the read-only recon): `ApprovePendingReconciliationAction` hydrates the order at
lines 57–63 **inside `DB::transaction` under `lockForUpdate`** — there is no pre-transaction
hydration — and re-checks `isVoid()` on the locked row (:65); `VoidOrderHandler` locks the same
`pos_orders` row (:107) with a terminal-status re-check. SQLite ignores `FOR UPDATE` and runs
the hook's "concurrent" void inside the approval's own transaction — an ordering PG forbids.

**Empirical confirmation** (`exit11_void_vs_approval.ps1`): deterministic void-then-approve →
zero commissions/no flip/no forward; approve-then-void → void unwinds (commissions deleted,
donation voided); concurrent barrage of 10 orders (`approve_recon.php` behind a DB barrier vs
10 real `order.void` pushes at a runspace gate) → terminal-void invariant held on **all 12**
orders in its stronger form (every order ended void with 0 commission rows).

**Disposition:** the original assertion in `MidFlightVoidRaceTest` (approval leg) pinned the
impossible interleaving and was repaired on 2026-08-13 to assert what the layer genuinely
proves (post-decision forward guard: voided donation never forwarded/overwritten, zero charity
HTTP — which held even under the manufactured interleave). The bank-file leg races for real on
both engines and keeps its full battery. Per handoff §11 evidence-invalidation rules, complete-run
evidence predating this repair is invalidated; T4/T5 runs start fresh.
