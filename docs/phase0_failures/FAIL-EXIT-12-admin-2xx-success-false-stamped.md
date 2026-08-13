# Phase 0 Failure: EXIT-12 — a 2xx charity reply with body success:false is stamped forwarded (silent donation loss)

- Status: FAIL-PRODUCT (coverage-matrix flag F-5 CONFIRMED in code)
- First observed: 2026-08-13 (Asia/Muscat), T2 lane execution
- Repository/branch/SHA: pos_admin, main, `972a1a1`
- Scenario/test: EXIT-12 / `tests/Feature/Admin/Phase0Exit/CharityForwardAmbiguityTest::it a 2xx receiver reply whose body says success:false is not stamped forwarded` (kept failing at line 202)
- Command: `wsl -e bash -lc "cd .../pos_admin && docker compose exec -T pos_admin php artisan test tests/Feature/Admin/Phase0Exit"`
- Disposable environment identity: SQLite `:memory:` + `Http::fake` (pure code-path defect; no backend dependence)

## Expected
A receiver-side application refusal must leave the donation retriable: `forwarded_at` stays NULL so the hourly sweep (`forwarded_at IS NULL`) retries with the same stable `pos_reference` uuid.

## Actual
`ForwardCharityDonationAction::forwardPayload` (`app/Actions/Admin/Reconciliation/ForwardCharityDonationAction.php:129-139`) returns true on any `$response->successful()` (2xx) **without inspecting the JSON body**. A receiver reply of HTTP 200 `{success:false, message:'receiver validation failed'}` is treated as accepted; `ReconcileDeferredEffectsAction::forwardPreparedDonation` stamps `forwarded_at`, the API reports `donations_forwarded=1`, and the refused donation becomes **permanently invisible to the retry sweep** — the customer's round-up money never reaches charity and nothing ever retries or reports it. First failure: "Failed asserting that '2026-08-13 13:57:04' is null."

## Reproduction
Deterministic: `Http::fake` returning 200 with `success:false`; approve a pending reconciliation carrying a donation; observe `forwarded_at` stamped, zero receiver rows.

## Evidence
Failing test kept in place. Companion green test in the same file pins the working half: `ConnectionException`/timeout correctly leaves `forwarded_at` NULL and the sweep retries with the same uuid.

## Scope/impact
Silent, permanent loss of charity round-up money on any receiver-side validation refusal — with POS reporting it as forwarded. Money-integrity class; no operator surface would ever show it.

## Related exposure (same defect family, out of this test's scope)
pos_api's inline first-forward twin (its forward action header says "keep in sync" with the admin copy) likely shares the 2xx-only check — the implementation owner should fix and test both.

## Test-only changes
`tests/Feature/Admin/Phase0Exit/CharityForwardAmbiguityTest.php` (new file; no production change).

## Implementation owner requested
pos_admin (`ForwardCharityDonationAction::forwardPayload`): treat 2xx + `success:false` (and 2xx with malformed/absent success field, per owner's contract choice) as NOT forwarded; add the pos_api twin to scope. The receiver's replay contract (2xx + original row on duplicate `pos_reference`) is proven receiver-side and safe for retries.
