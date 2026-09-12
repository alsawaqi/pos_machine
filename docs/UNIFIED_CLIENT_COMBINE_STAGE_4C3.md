# Stage 4C3 — approved manager combine on the original device

Implemented 2026-09-12 on codex/qr003-unified-staff, unpushed.
Parent: ccf28a2e94e717029b3e858fb0d2152819e8ed5c.
Server prerequisite committed FIRST: eaf7fe53e20b62b8482420d453a5fe27a51a02c2
(parent 6a80685ab7cd21d05c90aba6877689af3c6bdf24).

## Scope and safety

Dine-In offers Review local bill combine / recovery, including when the
ordinary table detail fails closed because two bills conflict. Manager sees
both frozen bills, their references, items, notes, add-ons, discounts, taxes
and combined amount. Only the original owning device may combine; the API
refuses either bill's transfer history. No automatic combine, tender or print.

The local source must be uniquely identifiable, equal to the server source,
and free of active cart/payment, pending order/table work, shared-round ledger
or payment history. Unsupported local discount attribution, fractional/gift/
bundle/unlinked lines and disagreeing copies are retained and refused. This
is deliberately not same-bill draft/delta reconciliation.

One immutable intent is saved BEFORE POST: scope, UUIDs, preview signature,
original raw local rows and later the validated ACK. The PIN is ephemeral,
obscured and cleared; it is never journaled. Retry uses the identical request,
not a new preview. Wrong/missing ACK identity, money, references, seating,
round/event/approver or status cannot authorize local deletion.

Pending/confirmed recovery blocks legacy use and QR checkout on this device.
Machine also guards floor open/clear/move/join and held-order operations;
handheld guards held-store mutations/resume and ordinary payment dispatch.
This temporary fail-closed recovery gate is not a general offline-sale policy:
without an unresolved combine, ordinary offline sales retain their old path.

Exact server ACK is persisted before local retirement. In ONE transaction,
the complete related-row set and each original raw row are compared, then
only those local rows are removed and the journal marked done. Original rows
and ACK stay archived in that database. No table-clear server action, outbox
row deletion, repricing, payment, stock action or kitchen-print call is used.
Restart after a lost reply retries the same intent. Restart after a persisted
ACK completes local retirement without re-sending or asking for another PIN.
Changed copies/disk faults keep confirmed recovery and all remaining copies.

An unapplied expired preview can be released only by an exact authenticated
combine_final_no_write proof with the existing combine_preview_stale refusal.
No local timer, generic refusal, missing row or network failure unlocks it.
Release preserves the original local bill. A committed request always replays.
Device/token/scope changes fail closed; restore the original scope to recover.

## Storage and untouched boundaries

mithqal_orders.db v7 -> v8; bill_combine_journal lives beside the original held/table rows.
The additive journal has a unique active-intent index; old rows are retained.
No Drift/generated files, dependencies, ARBs, server migrations, config keys,
sync types, or journal event types were added. Existing QR money controller,
claim/revalidation/recovery, line pricing, inventory and print logic remain.
The old tests keep every assertion and skip; machine storage fakes gain only
the new no-op interface method. The separately approved API cross-device
assertion change is documented in its server prerequisite.

## Literal clean-candidate checks

Candidate tree: e033675ba6d9f08e3e43892e266801ee15432d35.
Clean git archive, offline dependency restore, committed analysis_options.yaml
restored before analysis. No device, APK or application install.

    No issues found! (ran in 12.9s)
    01:22 +1116 ~3: All tests passed!
    Formatted 13 files (0 changed) in 0.06 seconds.

Delta: 1068 passed / 3 skipped / 0 failed -> 1116 passed / 3 skipped / 0 failed (+48 passing tests); skip count unchanged, zero failures.
Formatting check covers six new combine modules, DineInScreen and six new
combine test files. Existing legacy integration-file formatting is preserved.
Final exact-commit checks and cross-repo SHAs are in the shared handback:
documentation/QR-003_UNIFIED_CLIENT_COMBINE_HANDBACK.md in the parent POS workspace.

## Regression matrix (all passing)

- Frozen preview, no mutation; original rows match without cart reconstruction.
- Save before POST, double-tap one request, exact ACK archive, no persisted PIN.
- Lost reply/restart exact replay; eleven independently mismatched ACK fields.
- Refused pending work; local change before approval; extra/missing/changed
  row after ACK; transaction rollback/restart; insertion failure sends nothing.
- Exact expired-unapplied proof vs generic/mismatched refusal; background ACK.
- Old server policy and invalid PIN refused; cross-scope pending gate.
- HTTP authentication/payload, 409 proof preservation, 500 refusal, scope gate.
- EN/AR manager UI; Back/restart safety; recovery reachable after detail refusal;
  unsent staff items cannot combine or pay.
- Direct cash/card guards before charge or enqueue; machine mixed/floor guards.
- Schema addition retains old rows; local ledger/history/multiple-source checks;
  handheld strict corrupt/pending outbox admission.

## Staff note and remaining work

Use this only for two genuine bills belonging to the same party. Return to the
original device, sync pending work, park/close active editing, then review both
bills in Dine-In and obtain manager approval. Afterwards use the retained QR
reference. If uncertain, retry saved recovery; never clear app data or charge
the old bill. Transferred, discounted/unprovable and same-bill draft cases
remain blocked rather than guessed.

No rollout claimed. Same-bill local delta reconciliation and order-arrival
notifications remain separate stages, then independent combined verification
and an explicitly approved coordinated debug rollout.

## Anything in this implementation instruction that is wrong

The previous cross-device combine assumption was unsafe for offline/external
legacy tenders. The owner explicitly approved the local-owner/no-transfer
restriction and its assertion change. That item is resolved here. No new
instruction conflict was found. Real-device/stack behaviour is not claimed
from these isolated automated tests.
