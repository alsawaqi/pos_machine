# MITHQAL 2.0 — Independent Full-Testing AI Handoff

- **Prepared:** 2026-08-13
- **Audience:** A separate AI model assigned to Phase 0 verification
- **Mission:** Independently build the remaining test-only exit infrastructure, execute the complete validation program, and issue an evidence-backed pass/fail report
- **Production-code authority:** None; product defects return to the implementation agent
- **Deployment authority:** None

---

## 1. Copy-paste assignment for the testing AI

Use this block as the opening request in the separate testing task:

> You are the independent MITHQAL 2.0 Phase 0 validation agent. Read `C:\src\projects\pos_machine\docs\MITHQAL_2.0_FULL_TESTING_AI_HANDOFF.md` completely, then read the authority documents it names. Your job is to implement only test/harness/report code, execute every required automated suite and integrated exit scenario, coordinate the physical-device checklist with a human hardware operator, and produce reproducible evidence. Do not edit production application code, migrations, production configuration or deployment files. If you discover a product defect, preserve the failure, create the failure handoff described in this document, and stop that scenario until the implementation agent supplies a fix. Never push, deploy, migrate a live database, enable the production sweeper, or call a real payment/charity service.

The testing AI must not infer broader authority from words such as “complete,” “full,” “continue,” or “do not stop.” Full testing means full verification inside the boundaries below, not permission to mutate production systems.

---

## 2. Outcome expected from this assignment

The testing AI owns the evidence required to answer these questions:

1. Does every completed Phase 0 regression still pass in its owning repository?
2. Do machine, handheld, API, admin, merchant and the charity receiver behave correctly together under the adversarial exit scenarios?
3. Can the complete automated gate pass twice in fresh isolated environments with identical authoritative effect counts?
4. Are all full repository suites, builds and applicable static checks free of new regressions?
5. Do the physical Sunmi POS and Android handheld smoke checks pass, or is any item explicitly blocked with evidence?
6. Is there enough evidence for the human owner—not the testing AI—to sign off Phase 0?

The testing AI does **not** implement `CORE-001`, deploy Phase 0, or mark Phase 0 accepted on the owner's behalf.

---

## 3. Required reading and source order

Read in this order:

1. [MITHQAL_2.0_PHASE_0_HANDOFF.md](MITHQAL_2.0_PHASE_0_HANDOFF.md)
2. [MITHQAL_2.0_START_HERE.md](MITHQAL_2.0_START_HERE.md)
3. [MITHQAL_2.0_ARCHITECTURE.md](MITHQAL_2.0_ARCHITECTURE.md), especially the ground rules, Phase 0 exit condition and Phase 1 boundary
4. [MITHQAL_2.0_SYSTEM_AUDIT.md](MITHQAL_2.0_SYSTEM_AUDIT.md) and `docs/audit-evidence/`
5. `pos_api/docs/runbooks/stranded-sync-event-sweeper-cutover.md`, for understanding only; do not perform the live cutover
6. [sunmi-support-customer-display-touch.md](sunmi-support-customer-display-touch.md)

When facts conflict:

1. Follow a newer explicit owner decision.
2. Use the architecture for intended behavior and safety rules.
3. Use current code/tests/commits for implemented status.
4. Treat old audit findings as historical until current code confirms them.

The Phase 0 progress counters in the older documents are stale. All ten implementation items are locally committed; do not redo them merely because an old heading says “3 of 10.”

---

## 4. Responsibility split

| Work | Independent testing AI | Implementation AI | Human owner/operator |
|---|---|---|---|
| Coverage inventory and test plan | Owns | Reviews only when asked | May clarify acceptance intent |
| Test fixtures, barriers, test drivers and exit runner | Owns test-only implementation | May expose a safe test seam only after a documented request | No coding required |
| Repository regression/full-suite execution | Owns | Does not self-certify its own fix | Reviews report |
| Integrated `EXIT-01`…`EXIT-16` execution | Owns | Supports failures only | Reviews report |
| Product/application defect fix | Forbidden | Owns | Approves scope if it expands behavior |
| Test/harness defect fix | Owns, without weakening assertions | May review | — |
| Physical hardware actions | Coordinates and records | May support debugging | Owns taps, cables, credentials and devices |
| Failure classification and evidence | Owns initial classification | Responds with fix commit/evidence | Resolves disputed requirements |
| Revalidation after a product fix | Owns independently | Must not substitute its own green result | Reviews final result |
| Production migration/deployment/cutover | Forbidden | Forbidden unless separately authorized | Sole authority |
| Phase 0 sign-off | Recommends pass/fail only | No unilateral sign-off | Owns final acceptance |
| `CORE-001` implementation | Forbidden in this assignment | Begins only after owner sign-off | Authorizes start |

### Mapping to the main TODO list

| Main TODO | Owner for this plan | Classification |
|---:|---|---|
| 1 | Testing AI | Test planning |
| 2 | Testing AI | Baseline execution |
| 3–9 | Testing AI | Test-only/harness implementation |
| 10–11 | Testing AI | Automated execution and full validation |
| 12 | Implementation AI | Production defect fixes; testing AI supplies and later reruns the failing regression |
| 13 | Testing AI | Evidence report |
| 14 | Testing AI + human hardware operator | Physical smoke coordination/execution |
| 15 | Human owner | Acceptance |
| 16 | Implementation AI after sign-off | New product implementation |

---

## 5. Allowed and forbidden changes

### Testing AI may create or edit

Only test-specific paths are authorized:

```text
pos_machine/test/phase0_exit/
pos_machine/tool/phase0_exit.ps1
pos_machine/tool/phase0_exit_manifest.json
pos_machine/tool/phase0_exit/                     # test-only Compose, preflight and runner helpers
pos_machine/docs/PHASE_0_EXIT_GATE.md
pos_machine/docs/PHASE_0_EXIT_REPORT.md
pos_machine/docs/PHASE_0_EXIT_COVERAGE_MATRIX.md
pos_machine/docs/phase0_failures/FAIL-*.md

pos_handheld/test/phase0_exit/
pos_api/src/tests/Feature/Phase0Exit/
pos_admin/src/tests/Feature/Admin/Phase0Exit/
pos_merchant/src/tests/Feature/Phase0Exit/        # only if a portal/schema assertion is needed
charity/charity-laravel-api/src/tests/Feature/   # receiver idempotency contract only

ignored build/phase0_exit/<run-id>/ artifacts
```

Existing test files may be changed only to add coverage or correct a demonstrated test/harness defect. Never weaken an assertion merely to make current product behavior pass.

The testing AI may create local, test-only commits if that is useful for reproducibility. It must stage exact paths, preserve unrelated changes and never push.

It may start and stop reviewed isolated local test services, and create/remove only uniquely named disposable databases, schemas, Redis namespaces or containers that it created and positively identified.

### Testing AI must not edit

Unless the owner explicitly creates a separate implementation task, do not edit:

- Device production code under `lib/` or Android bridge code.
- API/admin/merchant production code under `app/`, `routes/`, production `config/` or frontend source.
- Any production migration or test-schema mirror to change behavior.
- Production Compose files, deployment scripts, live `.env` files or scheduler configuration.
- Dependency manifests or lockfiles without explicit approval.
- Charity receiver production code.
- Existing Phase 0 commits through reset, amend or history rewriting.
- Existing test exclusions or assertions merely to obtain green output.
- Arbitrary sleeps to simulate races; use deterministic barriers and frozen clocks.

If a safe deterministic test is impossible without a production seam, write a short **testability request** explaining the required seam, why existing public behavior is insufficient, and the narrowest non-behavioral change. Send it to the implementation agent; do not add the seam yourself.

---

## 6. Absolute safety rules

1. Never use the live shared `charity_db`.
2. Never run `migrate:fresh`, rollback, destructive SQL or schema-reset commands against a non-disposable database.
3. Abort unless `APP_ENV=testing` and the resolved database/Redis identities match a versioned allowlist explicitly supplied/approved by the human owner. The testing AI may validate the allowlist but may not approve its own target.
4. Print sanitized database/Redis target identity before setup; never print credentials.
5. Never call a real bank/acquirer or production charity endpoint.
6. Never enable `SYNC_STRANDED_SWEEP_ENABLED` in production or alter the production cutover floor.
7. Never deploy or push.
8. Run WSL repositories through `wsl -e bash -lc`; do not operate on their UNC worktrees with Windows Git/tooling.
9. Keep wire money in integer baisas and database money in OMR decimals; tests may not reinterpret units.
10. Redact tokens, PINs, customer PII, exact GPS, credentials and full sensitive payloads from retained artifacts.
11. Preserve unrelated dirty/untracked files. At handoff, machine had a modified `.codex_inspect/SunmiFingerprintDemo` submodule and untracked `.agents/` and `skills-lock.json`.
12. A rerun that passes after an unexplained failure is not a pass; classify it as flaky/nondeterministic and preserve both outcomes.
13. Establish one active writer per repository. The testing and implementation agents must explicitly hand write ownership back and forth before either edits the same repository.
14. Remove only uniquely named disposable resources created by the testing run and only after positively validating their identity. If cleanup scope is uncertain, stop and report it instead of deleting.
15. Apply an unconditional denylist including database name `charity_db`, production/staging-live domains not expressly approved for testing, production Redis and every owner-listed production endpoint. An allowlist match never overrides a denylist match.

### Stop and escalate immediately when

- A database, Redis host or external endpoint might be production.
- Production credentials, real customer data or sensitive card data appear.
- Repository state differs unexpectedly or another agent is editing the same files.
- Testing requires a production/application, migration, dependency or production-configuration change.
- The expected result conflicts with an architecture invariant or newer owner decision.
- Physical testing would require a real charge, an unapproved card or unsafe customer-display interaction.
- Cleanup cannot positively identify the exact disposable resource.

An ordinary product test failure does not stop the whole independent run. Preserve it, continue scenarios whose isolation is guaranteed, and return the defect through Section 11.

---

## 7. Initial repository state to verify, not assume

| Repository | Absolute root | Baseline before this testing-handoff commit | Baseline relation to `origin/main` |
|---|---|---|---:|
| `pos_machine` | `C:\src\projects\pos_machine` | Documentation commit `4b81272` after implementation HEAD `2b480d6` | ahead 8 before this testing-handoff commit |
| `pos_handheld` | `C:\src\projects\pos_handheld` | `52678b2` | ahead 2 |
| `pos_api` | `/home/abdallah644/projects/my-projects/pos/pos_api` | `07f92c4` | ahead 9 |
| `pos_admin` | `/home/abdallah644/projects/my-projects/pos/pos_admin` | `972a1a1` | ahead 5 |
| `pos_merchant` | `/home/abdallah644/projects/my-projects/pos/pos_merchant` | `c3b0cdf` | ahead 3 |
| Charity receiver | `/home/abdallah644/projects/my-projects/charity/charity-laravel-api` | Record current state | Record current state |

After this file is locally committed, `pos_machine` should be one documentation commit beyond `4b81272` (ahead 9 at preparation time). Resolve the exact current documentation SHA rather than embedding a self-referential commit ID: `git log -1 -- docs/MITHQAL_2.0_FULL_TESTING_AI_HANDOFF.md`.

Before any test or edit, record for every repository:

```text
absolute root
branch
HEAD SHA
origin/main relationship
git status --short
runtime versions
```

If a repository moved, do not reset it to these SHAs. Record the new state, inspect intervening commits and determine whether this handoff still applies.

---

## 8. Required execution phases

### T0 — Read-only inventory

1. Read all authority documents.
2. Record repository state and runtimes.
3. Map every completed Phase 0 item to its owning regression tests.
4. Map `EXIT-01`…`EXIT-16` to existing coverage and missing test-only work.
5. Produce `pos_machine/docs/PHASE_0_EXIT_COVERAGE_MATRIX.md` before implementing the harness.

### T1 — Baseline capture

1. Run the current full suites before adding test-only code.
2. Capture the two known machine test exclusions separately and record exact signatures.
3. Record inherited static-analysis debt separately from product/test failures.
4. Do not call an existing failure “pre-existing” without evidence from this baseline.

### T2 — Test-only infrastructure implementation

Build only what is missing:

- Deterministic fixtures and stable UUIDs.
- Frozen clocks.
- Explicit concurrency barriers rather than sleeps.
- Machine and handheld exit drivers using real payload builders where practical.
- API/admin/charity authoritative assertions.
- A parameterized `phase0_exit.ps1` orchestrator and manifest.
- Sanitized Markdown/JSON/JUnit artifacts.

Commit test-only infrastructure separately from result reports so another model can inspect it before execution.

### T3 — Mandatory Phase 0 regression pack

Run the owning regressions for all ten Phase 0 items. The pack must explicitly include:

- HH-001 handheld outbox concurrency.
- HH-002 card result/force-record classification on both devices.
- API-003 cash/change accounting.
- MC-001 machine parking/operator surface.
- MC-002 geofence re-enrichment.
- MC-003 cross-staff/shared-shift behavior in machine and API.
- API-001 loyalty clamp, review marker, replay and void restoration.
- API-002 atomic dispatch, recovery, floor quarantine and schedule gate.
- ADM-001 terminal void/deferred effects.
- ADM-003/ADM-002 retry eligibility, scheduling and worker configuration.

Minimum focused regression inventory to verify and expand where the coverage matrix requires:

| Repository | Phase 0 regression files |
|---|---|
| Handheld | `outbox_race_test.dart`, `outbox_stuck_test.dart`, `mosambee_classification_test.dart` |
| Machine | `card_charge_classification_test.dart`, `order_sync_parking_regression_test.dart`, `stuck_sales_surface_test.dart`, `order_sync_geofence_reenrichment_test.dart`, `shift_reconciliation_test.dart`, plus relevant startup/widget coverage |
| API | `DeviceSyncShiftTest.php`, `DeviceCurrentShiftTest.php`, `DeviceSyncLoyaltyTest.php`, `DeviceSyncStrandedEventTest.php`, `DeviceSyncDonationTest.php`, `DeviceSyncExpenseRestockTest.php`, `DeviceSyncSliderTest.php`, `DeviceSyncSliderBillingIntegrityTest.php` |
| Admin | `PendingReconciliationTest.php`, `ForwardCharityDonationActionTest.php`, `RetryRoundupForwardingTest.php`, `SchedulerTest.php`, `RoundupDonationTableTest.php`, `LoyaltyShortfallReviewSchemaTest.php`, `ScanExpiringCompanyDocumentsJobTest.php` |
| Merchant | `LoyaltyShortfallReviewTest.php`, `RoundupDonationSchemaTest.php` |

### T4 — Integrated adversarial exit scenarios

Execute every scenario in Section 9. Continue running independent scenarios after one fails so the final report shows the complete failure set.

### T5 — Repeatability run

Run the complete automated gate twice using two fresh disposable schemas/databases or unique run namespaces. Do not reuse the first run's stable IDs except inside intentional replay tests within that run. Both runs must have identical expected effect counts.

### T6 — Repository-wide validation

After the integrated gate:

- Run every repository's full tests.
- Run Flutter analysis/builds.
- Run backend formatting and applicable static analysis/build checks.
- Run the charity receiver idempotency contract.
- Compare with T1 baseline and identify every new difference.

### T7 — Physical-device smoke

The AI coordinates and records; a human with the devices performs physical actions. A missing device, credential or bank test terminal is `BLOCKED-HARDWARE`, not a simulated pass.

### T8 — Final independent report

Produce the report template in Section 13, clearly distinguishing automated-gate status, physical-smoke status and overall Phase 0 recommendation.

---

## 9. Integrated exit scenarios

| ID | Clients/surfaces | Scenario | Required result |
|---|---|---|---|
| `EXIT-01` | Machine | Offline backlog plus sales enqueued while flushing | No original/concurrent outbox row is lost; each event is processed or visibly actionable |
| `EXIT-02` | Handheld | Same backlog/concurrent-enqueue race | No SharedPreferences read-modify-write loss; all batches remain durable |
| `EXIT-03` | Both payload builders + API | Response-loss replay of event/order batch | Stored ACK; no duplicate order/payment/stock/loyalty/commission/donation effect |
| `EXIT-04` | Both payload builders + API | Loyalty request exceeds locked current balance | Paid sale persists; debit clamps; review evidence is exact and idempotent |
| `EXIT-05` | Both devices + API | Customer deleted before queued replay | Never discarded/falsely processed; rejection parks and is visible for manual action |
| `EXIT-06` | Machine + API | Fenced queued order gets a fresh GPS fix | Payload re-enriches and processes once |
| `EXIT-07` | Both devices + API | No valid fenced GPS fix | Supported client outcome stays durable and visible, never silently lost |
| `EXIT-08` | Both devices + API | Shift closes while sales remain queued | Sales survive and later process or remain visibly actionable |
| `EXIT-09` | API | Worker stops after ingest while event remains `received` | Eligible post-cutover event recovers exactly once |
| `EXIT-10` | API | Ambiguous historical row at/below floor | Remains quarantined and is never automatically replayed |
| `EXIT-11` | API + admin | Reconciliation approval races void | Void is terminal; no new commission or successful donation forward |
| `EXIT-12` | API + admin + charity contract | Charity forwarding fails after local settlement | Local commit persists; stable UUID retry produces one receiver transaction/share set |
| `EXIT-13` | Both devices | Repeated transport failures | Retry continues and rejection counter is unchanged |
| `EXIT-14` | Both devices | Same deterministic rejection five times | Batch parks at cap and is visible; automatic retry stops |
| `EXIT-15` | API | Tenant-scoped client-ID collision | Every event and financial effect remains scoped to authenticated tenant/device |
| `EXIT-16` | Machine + handheld concurrently | Same-branch sales hit shared customer/stock state at a barrier | Both streams settle without loss, duplicate effects, overdraw or staff/tenant leakage |

A scenario may legitimately produce zero server orders when it tests rejection/quarantine. In that case, prove the outbox/event remains visible and actionable.

---

## 10. Reproducible command matrix

Record the exact command, start/end time, exit code, runtime version, repository SHA and artifact path for every invocation.

Important boundary: the current API/admin/merchant/charity PHPUnit configurations use SQLite `:memory:`; the POS backends also use array cache and synchronous queue behavior in tests. These commands are necessary repository baselines, but they cannot prove PostgreSQL row-locking, Redis dispatch locks, worker interruption, scheduler recovery or cross-repository concurrency. T4/T5 must use the new explicitly disposable PostgreSQL/Redis integrated harness. Never equate a green Composer baseline with a green `EXIT-01`…`EXIT-16` gate.

Before `docker compose exec`, run `docker compose config --services` and `docker compose ps`. A stopped local development service is setup work; start/build only the reviewed local service definition or use a reviewed one-shot `run` form. Do not silently fall back to an incompatible host PHP.

### Sunmi machine app — Windows PowerShell

Machine CI pins Flutter `3.44.0`. Use that version for CI parity or record the runtime mismatch before interpreting any difference. Handheld CI follows stable but its package requires Dart `^3.12.2`.

```powershell
Set-Location C:\src\projects\pos_machine
flutter --version
git status --short
flutter pub get
git status --short
flutter analyze --no-pub
flutter test
flutter build apk --debug
```

Machine CI currently also runs a subset excluding `widget_test.dart` and `pos_controller_charity_flow_test.dart`. Run the full suite first and preserve both exact failures, then reproduce the committed CI subset:

```powershell
$tests = Get-ChildItem test -Filter *_test.dart |
  Where-Object { $_.Name -notin @('widget_test.dart', 'pos_controller_charity_flow_test.dart') } |
  ForEach-Object { $_.FullName }
flutter test $tests
```

The exclusions are historical evidence, not permission to ignore a new signature. The debug APK is build evidence only; physical smoke needs a staging-configured/signed build with its own recorded identity.

### Android handheld — Windows PowerShell

```powershell
Set-Location C:\src\projects\pos_handheld
flutter --version
git status --short
flutter pub get
git status --short
flutter analyze
flutter test
flutter build apk --debug
```

For both Flutter repositories, compare the `git status --short` snapshots before and after `flutter pub get`. If the command changes `pubspec.lock`, a manifest or another tracked dependency file, stop and report dependency/setup drift. Do not retain or commit that change as part of testing, and do not continue interpreting results until the owner confirms the intended locked dependency state.

### API — PowerShell invoking WSL/container

```powershell
wsl -e bash -lc "cd /home/abdallah644/projects/my-projects/pos/pos_api && docker compose exec -T pos_api composer test"
wsl -e bash -lc "cd /home/abdallah644/projects/my-projects/pos/pos_api && docker compose exec -T pos_api vendor/bin/pint --test"
```

### Admin — PowerShell invoking WSL/container

`SchedulerTest` requires the production Compose file mounted at the path expected in the test container:

```powershell
wsl -e bash -lc "cd /home/abdallah644/projects/my-projects/pos/pos_admin && docker compose run --rm --no-deps -T -v /home/abdallah644/projects/my-projects/pos/pos_admin/docker-compose.prod.yml:/var/www/docker-compose.prod.yml:ro pos_admin composer test"
wsl -e bash -lc "cd /home/abdallah644/projects/my-projects/pos/pos_admin && docker compose exec -T pos_admin composer analyse"
wsl -e bash -lc "cd /home/abdallah644/projects/my-projects/pos/pos_admin && docker compose exec -T pos_admin vendor/bin/pint --test"
wsl -e bash -lc "cd /home/abdallah644/projects/my-projects/pos/pos_admin && docker compose run --rm --no-deps -T vite sh -lc 'npm ci && npm run build:check'"
```

The full admin PHPStan result has inherited Eloquent/model-annotation debt. Compare the normalized diagnostic set—not only the historical count of 566—with the captured baseline. Any new diagnostic fails validation; do not claim inherited debt is green or fixed.

### Merchant — PowerShell invoking WSL/container

```powershell
wsl -e bash -lc "cd /home/abdallah644/projects/my-projects/pos/pos_merchant && docker compose exec -T pos_merchant composer test"
wsl -e bash -lc "cd /home/abdallah644/projects/my-projects/pos/pos_merchant && docker compose exec -T pos_merchant vendor/bin/pint --test"
wsl -e bash -lc "cd /home/abdallah644/projects/my-projects/pos/pos_merchant && docker compose run --rm --no-deps -T vite sh -lc 'npm ci && npm run build:check'"
```

### Charity receiver — PowerShell invoking WSL/container

```powershell
wsl -e bash -lc "cd /home/abdallah644/projects/my-projects/charity/charity-laravel-api && docker compose run --rm --no-deps -T charity-api-app composer test"
wsl -e bash -lc "cd /home/abdallah644/projects/my-projects/charity/charity-laravel-api && docker compose run --rm --no-deps -T artisan php vendor/bin/pint --test"
```

If the charity one-shot lacks its test dependencies or SQLite extension, classify that as environment/setup evidence rather than a product failure. Confirm service names before running; do not silently change commands or use an incompatible host PHP.

For the environment report also capture `flutter doctor -v`, Java version, `adb devices -l`, Docker/Compose versions, and PHP/Node versions from inside the actual containers. Hash every physical-test APK and record its absolute output path, application version/build ID and source SHA.

---

## 11. Failure handling and return to the implementation AI

### Failure status vocabulary

Use exactly these statuses:

| Status | Meaning |
|---|---|
| `PASS` | Required assertions executed and passed with retained evidence |
| `FAIL-PRODUCT` | Current production behavior violates the defined expectation |
| `FAIL-TEST` | A harness/fixture/assertion defect has been proven; repair it and invalidate the affected complete run |
| `BLOCKED-INFRA` | Required disposable service/runtime cannot be made available without new authority |
| `BLOCKED-HARDWARE` | Physical device, credential, firmware or bank test terminal is unavailable |
| `NOT-RUN` | Required work has not executed; never summarize this as pass |
| `FLAKY` | Initial classification for unexplained pass/fail variation; it blocks sign-off until evidence proves a product or harness cause |

### On a suspected product failure

1. Preserve the first failure output and artifacts.
2. Confirm the environment preflight passed.
3. Run the smallest deterministic reproduction without changing production code.
4. If it passes after previously failing, mark `FLAKY`; do not erase the original failure.
5. Add or preserve a failing regression only in an authorized test path.
6. Create `pos_machine/docs/phase0_failures/FAIL-<scenario>-<short-name>.md` using the template below.
7. Send the failure package to the implementation AI and stop only the dependent scenario chain. Continue independent scenarios.

### Failure handoff template

```markdown
# Phase 0 Failure: <ID and title>

- Status: FAIL-PRODUCT | FLAKY | BLOCKED-INFRA | BLOCKED-HARDWARE
- First observed: <ISO timestamp Asia/Muscat>
- Repository/branch/SHA: <values>
- Scenario/test: <ID and exact test name>
- Command: <exact sanitized command>
- Disposable environment identity: <sanitized DB/Redis/run namespace>

## Expected
<contract expectation>

## Actual
<first failing assertion, status/result and exact counts>

## Reproduction
<minimal deterministic steps and frequency>

## Evidence
<artifact paths, redacted logs, screenshots>

## Scope/impact
<money, stock, sale durability, visibility, tenant or reporting impact>

## Test-only changes
<files/commit, or none>

## Implementation owner requested
<repository/component; no production patch proposed as completed work>
```

### After the implementation AI supplies a fix

After write ownership transfers, the implementation AI may edit production code or an explicitly approved testability seam only. It must not modify the testing AI's failing regression, fixture, harness, barrier or expected result. If it disputes the test, return the dispute to the testing AI and human owner before either side changes the measurement.

The testing AI independently:

1. Records the new fix SHA and inspects the diff for scope.
2. Runs the exact failing regression.
3. Runs the owning targeted suite.
4. Runs any interaction scenarios affected by the fix.
5. Reruns the full repository suite.
6. Reruns both fresh-environment exit gates before changing the failure to `PASS`.

The implementation AI's own green test output is supporting evidence, not independent acceptance.

### Evidence invalidation and restart rules

- Any `BLOCKED-INFRA`, `FAIL-TEST` or `FLAKY` result during a complete final run invalidates that entire run; after repair, restart the complete gate in a fresh namespace.
- Any change to product code, dependencies, fixture data, mock behavior, assertions, payload adapters, concurrency barriers, runner orchestration or test database schema invalidates all earlier complete-run evidence.
- The two accepted final runs must be consecutive, complete and clean, using one frozen set of product and test-harness SHAs.
- A report-only spelling/layout correction does not invalidate evidence, but it must not change an expectation, classification or count.
- If device-affecting code, build configuration or dependencies change after physical testing, rebuild the APK, record its new SHA-256, and repeat every affected physical check. Every physical result must identify the final source SHA and APK hash.

---

## 12. Physical-device boundary

The AI cannot claim a physical test based on an emulator or code inspection. A human operator must perform the actions while the testing AI supplies steps, records IDs and correlates backend evidence.

Prerequisites:

- Sunmi T3 PRO, integrated printer and actual optional rear display.
- Supported Android handheld and printer hardware.
- Signed/testable APKs with build IDs and staging API URL.
- Staging activation/device/branch/staff credentials.
- GPS permissions and a controlled geofence case.
- Bank-provided test terminal/credentials or an approved non-charging mode that still exercises the real device-to-acquirer bridge. A mock UI, force-record path or bypass is not equivalent; if the actual bridge cannot be tested, mark the card check `BLOCKED-HARDWARE` and the overall result `NOT-READY` even if an owner accepts the business risk.
- Mock/staging charity endpoint.

ADB boundaries:

- The testing AI may use read-only inventory/log commands such as `adb devices`, `getprop`, `dumpsys` and scoped log capture, with the human operator aware.
- APK installation, uninstall, app-data clearing, device-shell mutation, settings/config changes, payment-terminal actions and device reset require the human operator's explicit approval and direct supervision.
- The testing AI must record every approved mutation and restoration action; it may not factory-reset or destructively alter a device on its own authority.

Required smoke evidence:

| Surface | Checks |
|---|---|
| Sunmi POS | Login/config, shift, normal sale, offline cash, reconnect, shared-shift handover, parked-sale detail/manual retry, real bridge in approved non-charging mode, receipt/printer and safe rear-display behavior |
| Handheld | Login/config, normal/offline sale, enqueue during reconnect, GPS/geofence, parked batch/manual retry, real bridge in approved non-charging mode and printer |
| Backend/admin/charity | Match order/event UUIDs to payment, stock, loyalty, commission/donation, exception and receiver-idempotency evidence |

The Sunmi T3 PRO/NP521 touch-routing defect is known: customer-panel taps reach operator display 0. Do not expose the round-up touch prompt to a customer on affected firmware. Record the firmware limitation and verify the safe disabled/non-interactive behavior; do not mark the touch interaction passed.

---

## 13. Evidence and final report

### Artifact layout

```text
build/phase0_exit/<run-id>/
  environment.json
  repository-state.json
  coverage-matrix.md
  command-results.json
  command-stdout-stderr-redacted/
  junit/
  logs-redacted/
  scenario-results.json
  effect-counts.json
  screenshots-redacted/
  artifact-manifest.sha256

docs/PHASE_0_EXIT_REPORT.md
docs/phase0_failures/FAIL-*.md
```

Keep raw secrets outside retained artifacts. Where raw logs are temporarily necessary, protect them, create a redacted copy, then remove the raw copy when no longer needed.

Each command record must include the exact sanitized command, stdout/stderr artifact, exit code and duration. Runtime evidence must include `flutter doctor -v`, Java/ADB device inventory, Docker/Compose versions and PHP/Node versions from inside the containers actually used. Each APK record must include its path, version/build ID, source SHA and SHA-256.

### Final report structure

```markdown
# MITHQAL 2.0 Phase 0 Exit Report

## Decision
Automated gate: PASS | FAIL | BLOCKED
Physical smoke: PASS | FAIL | BLOCKED | NOT-RUN
Overall recommendation: READY-FOR-OWNER-SIGNOFF | NOT-READY

## Tested state
Repository roots, branches, SHAs, dirty state, runtimes, disposable targets

## Coverage
All ten Phase 0 items and EXIT-01…EXIT-16

## Baseline comparison
Existing failures/debt versus new differences

## Automated run 1
Scenario statuses, commands, counts, artifacts

## Automated run 2
Fresh environment, scenario statuses, identical-count comparison

## Full repository validation
Tests, analyze/static checks, builds and formatter results

## Physical smoke
Build/device/API identifiers, order/event IDs, evidence and blockers

## Failures and residuals
Every FAIL/BLOCKED/FLAKY/NOT-RUN item; no hidden omissions

## Recommendation
Evidence-backed recommendation; human owner retains acceptance authority
```

### Required per-scenario evidence block

Copy this block for every `EXIT-*` scenario in both complete runs:

```markdown
### <EXIT-NN> — <title>

| Field | Value |
|---|---|
| Run ID / deterministic seed |  |
| Result classification |  |
| Candidate and test-harness SHAs |  |
| Disposable namespace |  |
| Exact command / exit code |  |
| Start/end UTC |  |
| Artifact path |  |

Expected: <declared before execution>

Actual: <observed without speculation>

| Authoritative effect | Before | Expected delta | Actual delta | Final | Pass |
|---|---:|---:|---:|---:|---|
| Device outbox / parked rows |  |  |  |  |  |
| API received / failed / processed events |  |  |  |  |  |
| Orders / payments |  |  |  |  |  |
| Stock movements |  |  |  |  |  |
| Loyalty ledger / reviews |  |  |  |  |  |
| Commission rows |  |  |  |  |  |
| Local donation / receiver result sets |  |  |  |  |  |

Stable-ID replay check: <stored ACK and exact-once evidence>

Visibility check: <processed ACK or exact operator surface>

Decision rationale: <why this classification follows from evidence>
```

### Required two-run comparison

| Measurement | Run 1 | Run 2 | Match |
|---|---:|---:|---|
| Scenarios executed/passed |  |  |  |
| Orders / payments |  |  |  |
| Stock movements |  |  |  |
| Loyalty ledger / review rows |  |  |  |
| Commission rows |  |  |  |
| Local donations / receiver sets |  |  |  |
| Final visibly unresolved rows |  |  |  |
| Unexpected stranded rows |  |  |  |
| Duplicate effects |  |  |  |

Only explicitly normalized timestamps, run namespaces and intentionally different fixture UUIDs may differ. Explain every difference.

### Independent tester declaration

The report must state that the tester:

- Executed every represented command rather than copying historical counts.
- Preserved first failures and remediation history.
- Did not weaken assertions or edit production behavior.
- Used disposable infrastructure and approved mocks/staging services only.
- Did not deploy, push, migrate production or enable the production sweeper.
- Used the same frozen candidate/test-harness SHAs for both final runs.
- Redacted and hashed the shareable evidence package.

The physical report also requires a named human operator's dated confirmation. If the test was not performed or confirmation is absent, classify it `NOT-RUN`. Use `BLOCKED-HARDWARE` only when a required device, credential, firmware capability or test terminal is actually unavailable.

### Required physical-operator confirmation

```markdown
## Physical operator confirmation

- Operator name: <full name>
- Date/time and timezone: <ISO timestamp>
- Machine device/firmware ID: <sanitized value>
- Handheld device/firmware ID: <sanitized value>
- Machine APK version/build ID/SHA-256: <values>
- Handheld APK version/build ID/SHA-256: <values>
- Scenarios personally performed: <IDs>
- Result: PASS | FAIL | NOT-RUN | BLOCKED-HARDWARE
- Evidence references: <photos/screenshots/log bundle>
- Confirmation: I performed the listed physical actions on the identified staging devices and confirm that this record matches what I observed.
```

### Required owner decision

```markdown
## Phase 0 owner decision

- Owner name: <full name>
- Date/time and timezone: <ISO timestamp>
- Exit-report path and SHA-256: <values>
- Decision: ACCEPT-TECHNICAL-PASS | RETURN-FOR-REMEDIATION | ACCEPT-BUSINESS-RISK-NOT-READY
- Decision/reference notes: <ticket, approval or rationale>
- CORE-001 authorization: YES | NO
```

Business-risk acceptance never rewrites a technical `FAIL`, `BLOCKED-*`, `NOT-RUN` or overall `NOT-READY` result into `PASS`.

### Sign-off rules

The testing AI may recommend `READY-FOR-OWNER-SIGNOFF` only when:

1. All ten Phase 0 regression groups pass.
2. `EXIT-01`…`EXIT-16` pass twice in fresh isolated runs.
3. No required item is `FAIL`, `FLAKY`, `BLOCKED` or `NOT-RUN`.
4. Full suites/builds/static checks show no new regression against baseline.
5. Physical smoke passes, including recorded safe handling of known hardware limitations.
6. Artifact redaction and repository state are complete.

If automated testing passes but physical hardware is unavailable, report **automated gate PASS, physical smoke BLOCKED, overall NOT-READY**. Do not collapse separate statuses into a partial pass.

Only the human owner marks Phase 0 complete and authorizes `CORE-001`.

---

## 14. Completion checklist for the testing AI

- [ ] Authority documents read completely.
- [ ] Repository state and runtimes recorded.
- [ ] Disposable DB/Redis preflight passed.
- [ ] Coverage matrix covers all ten items and `EXIT-01`…`EXIT-16`.
- [ ] Baselines captured before test-only changes.
- [ ] Test-only harness/runner implemented and reviewed.
- [ ] Mandatory Phase 0 regression pack passed.
- [ ] Integrated automated gate run 1 completed.
- [ ] Integrated automated gate run 2 completed in a fresh namespace.
- [ ] Effect counts compared and identical where required.
- [ ] Full repository suites/builds/static checks completed.
- [ ] Charity receiver idempotency contract completed.
- [ ] Every failure has a failure handoff and no production fix was made by the testing AI.
- [ ] Physical smoke completed with a human operator, or accurately classified `NOT-RUN`/`BLOCKED-HARDWARE` with overall `NOT-READY`.
- [ ] Artifacts redacted and linked.
- [ ] `PHASE_0_EXIT_REPORT.md` issued with separate automated/physical/overall status.
- [ ] No push, deployment, live migration or sweeper activation occurred.

---

## 15. Final instruction

Independence is intentional. The testing AI builds and operates the measurement system, preserves failures and verifies fixes; it does not modify the product it is judging. The implementation AI owns product changes. The human owner owns acceptance and every action against production.
