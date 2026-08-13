# Phase 0 Failure: EXIT-07 — machine GPS-held fenced sale is durable but operator-INVISIBLE

- Status: FAIL-PRODUCT (with an explicit owner-clarification alternative, below)
- First observed: 2026-08-13 (Asia/Muscat), T2 lane execution
- Repository/branch/SHA: pos_machine, main, product code `2b480d6` (docs HEAD `95acf02`)
- Scenario/test: EXIT-07 / `test/phase0_exit/w_m5_exit07_gps_held_visibility_test.dart` (kept failing at line 149)
- Command: `flutter test test/phase0_exit/w_m5_exit07_gps_held_visibility_test.dart` (Flutter 3.44.9)
- Disposable environment identity: in-memory Drift DB + fake Dio adapter + fake GeolocatorPlatform (pure local test)

## Expected
"No valid fenced GPS fix: the supported client outcome stays durable **and visible**, never silently lost" (FULL_TESTING handoff §9 EXIT-07; architecture: "durable and visible on the device — either still queued and retrying, or parked at the rejection cap").

## Actual
A fenced-branch batch with no obtainable GPS fix is held by `_flushOnce` with no request, no attempt, no rejection (proven: requestCount 0, attempts 0, serverRejections 0, row durable). The ONLY operator surfaces for outbox batches are `stuckOrderSyncProvider → OrderSyncRepository.watchStuck()` (filters `serverRejections >= 5`) feeding the settings-screen stuck tile and the staff-POS gear badge. A GPS hold never increments rejections, so the batch can never satisfy `isStuck` and appears on NO surface. Durability assertions pass; the visibility assertion fails.

## Reproduction
Deterministic, 100%: enqueue a fenced-branch money batch with gps omitted; fake locator returns no fix; flush; observe zero attempts and zero surface consumers of `watchPending()` in lib/ (only `watchStuck` is consumed — `providers.dart:260`, `settings_screen.dart`, `staff_pos_screen.dart:4909`).

## Evidence
Failing test file kept in place; first-failure output embedded in the test's failure message. Read-only grep evidence: no lib/ consumer of `watchPending()` unfiltered.

## Scope/impact
A till at a fenced branch with location services broken can accumulate durable, permanently invisible unsold-to-server sales — printed receipts and taken money with no server record and nobody looking. This is exactly the "sales can strand permanently with nobody looking" class MC-001 was created to close; the GPS-hold path was left out of the operator surface.

## Test-only changes
`test/phase0_exit/w_m5_exit07_gps_held_visibility_test.dart` (new file; no production change).

## Implementation owner requested
pos_machine (`lib/data/order_sync_repository.dart` surface providers / settings screen). Candidate fixes: widen the stuck surface to include GPS-held batches (e.g. an "awaiting GPS" tile), or a distinct held-sales badge. ALTERNATIVE: if the owner rules that "still queued and retrying" is acceptable as-is without a surface, record that decision explicitly and this failure converts to an owner-accepted clarification — the testing agent does not make that call.
