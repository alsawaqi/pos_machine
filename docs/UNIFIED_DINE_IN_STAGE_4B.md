# Unified Dine-In clients — stage 4B

Implemented 2026-09-12 on codex/qr003-unified-staff.
This is a local, intermediate client stage, NOT a completed unified-flow rollout.

## Parent and dependency

Till parent: 95d7f0d653ddfc523e08f5c12ac5ee96e4881667.
API prerequisite (unchanged here): 76a00afd1badca4631897c63f07d1fee9edb5662.
Final commit/ahead counts are in the shared
documentation/QR-003_UNIFIED_DINE_IN_CLIENT_HANDBACK.md.

## Built

- The existing floor plan opens the canonical shared table bill for a current
  QR seating. An older local occupied/paid record cannot hide that shared bill.
  Primary/joined table identity, frozen items, all customer/staff rounds,
  reference, totals, holds and cancellations are displayed without cart import.
- Separate QR Tables navigation is removed for every mode and old toggle value.
  Settings shows Table orders are in Dine-In instead of the fallback toggle.
  Stored preference, legacy screen/controller and old money-panel tests remain.
- Staff additions reuse the Quick Orders product/modifier/quantity/note picker.
  Only the NEW price-free lines go to the existing canonical table-round endpoint.
  Live is required for these new append controls. No second order.create.
- Confirm/reject chooses the existing endpoint by customer/staff round origin.
  Pending review blocks payment. Clear is offered only for bill-less occupied
  seating and uses the existing server guard. QR reopen uses its existing route.
- Proceed to pay calls the stage-3 normal guarded payment page, not the former
  QR Cash/Card popup. No claim/tender/replay/recovery/pay implementation changes.
- Ten-second detail refresh only while the view is visible/foreground; suspended
  under picker and checkout. No automatic Off polling added. A table long-press
  provides an explicit read path in Off; normal local/empty table behavior remains.
- EN/AR shared component and RTL tests; five lib/dine_in files match handheld.
- The existing kitchen print-claim controller prints a newly accepted round.
  Server kitchen_printed_at suppresses repeats. A printer failure retains the
  acknowledged order and exposes PRINT-only retry, never another submission.
  Existing qr_round_printing.dart, printer adapter and claim protocol are unchanged.

## Durable additions and money safety

New separate dine_in_requests.db v1, NOT the sync outbox or an existing DB migration.
One immutable request per server/company/branch/device scope; insert before POST.
Canonical seating/bill UUIDs, primary/selected table, request ID and exact payload
persist through unknown responses and restart. Only explicit same-ID retry;
fresh canonical read refuses a changed party. New requests never reuse the old
bill's client prices or GPS. Wrong/malformed acknowledgement retains the journal.
Fresh documented bill_unpaid/bill_terminal no-write verdicts alone can release a
NEW request. A refusal after uncertainty cannot discard a possibly applied round.
Normal QR checkout also refuses an unresolved table journal.
Active/local/pending draft table IDs, including primary/joined members, are read
only. They block conflicting shared actions; no silent cart migration or rollback.

## Existing test expectation changes

The owner's latest request supersedes T7's temporary legacy-tab requirement.

test/legacy_qr_tab_toggle_test.dart:
- Switch visible/toggling persists true then false -> switch absent, Dine-In
  information present, previously unset preference remains null/false.
- Six mode/toggle navigation combinations: off-or-enabled legacy tab -> absent.
  The legacy screen is absent and the stored toggle retains its original value.
  Therefore the old tap/open/back steps are replaced, not silently skipped.
- Three Settings-return cases: visibility followed toggle -> always absent even
  when a test writes the old saved preference. No board call is made.
- Default/persistence unit assertions and all test case counts remain unchanged.

test/dining_floor_plan_occupancy_test.dart:
- occupied + current live QR: local/customer=false -> sheet/customer=true.
- older local paid + current live QR: paid/customer=false -> sheet/customer=true.
- Six station/staff_till/handheld x open/billing cases with an older local
  session: customer occupancy false -> true. Off remains false.
- Closed-seating expectations and cart immutability assertions are unchanged.
- Original 27 QR Tables tests and money-panel/host tests are untouched.

## Boundary requiring the next stage

Legacy staff-created/local/parked table drafts are preserved and BLOCK conflicting
shared actions. This stage does NOT reconcile or migrate them.
Staff-only bills are not coerced into QR claim eligibility; they retain the
existing staff checkout. Full cross-device staff-first/local-draft reconciliation
needs the next integration step. Arrival bell/visual deduplication, independent
stack/device/printing/payment verification and rollout still remain.
Do not install this intermediate stage alone.

## Verification

Parent baseline: 1028 passed / 3 skipped / 0 failed (stage-3 committed evidence).
Clean candidate tree: 3767f8e3ab519cdb0e24e16be4b573b69daf9c33.
Clean export: unified-machine-stage4-final-r3.

    No issues found! (ran in 15.0s)
    01:09 +1068 ~3: All tests passed!
    ANALYZE_EXIT=0 TEST_EXIT=0

Delta +40 passed, same three existing skips. Shared focused suite: 40 passed.
New coverage includes immutable persistence, lost acknowledgement, restart,
wrong bill/new seating, joined local conflicts, no client money/GPS, polling
lifecycle, EN/AR normal-pay callback and print-only retry after acknowledgement.
Before commit, one formatter-only line wrap was applied to the new print guard.
Final committed-HEAD rerun is recorded in the shared handback.

One intermediate candidate had two missing print-model imports and an if-block
lint warning: machine 873 passed / 3 skipped / 14 load failures. Corrected the
imports/braces; no test assertion was changed to fix these failures.
A broadened occupancy draft initially matched closed seatings; the unchanged
closed-seating test caught it. The implementation retains open/billing filtering.
Initial new-test relative-import lint issues were corrected to package imports.

Harness: unified-staff-flutter-check.ps1 in the shared artifact directory.
Clean git archive, pub get --offline, committed analysis_options restored before
analyze --no-pub and test --no-pub --reporter expanded. New tests use in-process
HTTP fakes and SQLite :memory:, no backend/device.
Baseline Drift multiple-database debug warnings remain; they were present before
this stage and no skip hides them. New files pass the non-mutating Dart format
check. Existing large-file formatting is preserved outside scoped edits.
No generated files, dependency/lockfile/PHP changes. Pint: not applicable.

## Evidence

Native fixture renders: unified-dine-in-screens/dine-in-{480,1200}-{en,ar}.png
in the shared artifact directory. Rendered shared component with evidence-only
local fonts, not device screenshots or proof of live stack/printing.

## Anything in this implementation instruction that is wrong

No contradictory owner instruction was implemented around. Earlier stage sizing
underestimated staff/parked-draft reconciliation. It remains explicitly unfinished,
not hidden by importing customer lines or weakening payment safeguards.
No push/fetch, main-checkout modification, shared DB/stack, APK/device, real payment
or real printer operation was performed.
