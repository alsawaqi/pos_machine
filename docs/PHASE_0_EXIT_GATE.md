# MITHQAL 2.0 — Phase 0 Exit Gate (test-only harness)

- **Prepared by:** independent Phase 0 testing agent, 2026-08-13
- **Authority:** `MITHQAL_2.0_FULL_TESTING_AI_HANDOFF.md`; coverage map in `PHASE_0_EXIT_COVERAGE_MATRIX.md`
- **Status:** infrastructure stage — scenario runners land in the next T2 iteration; `-Scenarios` fails loudly until then.

## What this is

Two mandatory layers (a green layer 2 never excuses skipping layer 1):

1. **Regression pack** — the owning regressions of all ten Phase 0 items plus the new
   `phase0_exit` unit drivers in each repo (see `tool/phase0_exit_manifest.json` → `regressionPack`).
2. **Integrated adversarial gate** — `EXIT-01`…`EXIT-16` against DISPOSABLE local
   PostgreSQL 16 + Redis 8 (matching production versions), real device payload builders,
   deterministic fixtures, run twice in fresh namespaces with identical effect counts.

## Safety model (owner-approved allowlist, 2026-08-13)

- Everything runs in compose project **`phase0exit`**; every container is labeled
  `mithqal.phase0exit=disposable`; PG data is on **tmpfs** (dies with the container).
- Databases are named `phase0_exit_*` only. No service publishes a port except the harness
  API at **127.0.0.1:58000**.
- `tool/phase0_exit/preflight.ps1` refuses to run any stage unless every resolved identity
  matches `tool/phase0_exit/allowlist.json`; the denylist (`charity_db`, `*.mithqal.net`,
  the dev/prod Redis and DB containers) always wins. `APP_ENV=testing` is forced by the
  compose runner environment; the throwaway `APP_KEY` is generated per run and never persisted.
- Teardown drops only the run's own `phase0_exit_<runid>` database after re-running
  preflight; `-Down` additionally removes the labeled project containers + anonymous volumes.
- Never touched, ever: live `charity_db`, production endpoints, production Redis, real
  bank/acquirer, the production sweeper flag or floor.

## Usage

```powershell
# from C:\src\projects\pos_machine\tool
.\phase0_exit.ps1 -RunId run1 -Setup      # infra + preflight + db + migrations + API server
.\phase0_exit.ps1 -RunId run1 -Scenarios  # integrated gate (not yet implemented — exits 2)
.\phase0_exit.ps1 -RunId run1 -Teardown   # drop run DB;  add -Down to remove containers
```

Artifacts land in `build/phase0_exit/<run-id>/` (gitignored) per handoff §13.

## Known modeling decisions (recorded, not hidden)

- **EXIT-09**: the stranded `received` state is seeded physically on the real PG rather than
  produced by SIGKILLing a live php worker — the runbook defines recovery purely over the
  `received` state, which is identical however the worker died. What the integrated gate adds
  over the SQLite tests: real PG rows, two genuinely concurrent sweeper processes, real Redis
  `Cache::lock` contention, exactly-once settlement.
- **EXIT-12**: full pos_admin→receiver loop requires the charity runner (wired in the
  scenario iteration); until then the receiver side is proven by the charity repo's own
  contract tests (`CharityPosRoundupTest` + the new Phase 0 strengthening test).
- The dev-container vite rule from the T1 incident: re-validation runs never execute
  `npm ci` against live-mounted node_modules (see `build/phase0_exit/t1-baseline/BASELINE_NOTES.md`).
