# Phase 0 Finding (T7 H6, revised): handheld card flow — no watchdog on an unresponsive SoftPOS; `<queries>` parity gap

- Status: **FAIL-PRODUCT (hardening)** — two product findings for the implementation owner; the
  original blocker itself was adjudicated as device-state, not product (see Diagnosis history)
- Discovered: 2026-08-15, T7 physical smoke, UMIDIGI G7 (Android 14), verified smoke APK
- Repository/branch/SHA: pos_handheld, main, `29730d3` (+ owner-confirmed toolchain deltas)
- Implementation owner: the project owner (explicitly confirmed the tester/implementer split in-session and requested these findings be recorded for them to fix)

## Finding 1 — no watchdog on a launched-but-unresponsive SoftPOS (indefinite spinner)

When the bridge launches the Mosambee activity and no `onActivityResult` ever arrives, the
payment flow **spins forever with no operator guidance**. Observed live: the Mosambee app on the
G7 was crash-looping (see history) — our bridge fired correctly
(`MosambeeBridge: Starting Mosambee login userName=10000421 chain=true`), the Login activity
started, died on resume, restarted, died again — and the POS spinner never resolved and never
offered a classified outcome. The operator had to back out manually.

**Requested hardening:** a launch watchdog — if a started SoftPOS activity delivers no result
within a bounded window (and/or its process is observed dead), surface a classified
**never-reached / "payment app not responding"** outcome (not force-recordable, no infinite
loop). The owner explicitly flagged "no continuous loop" as a requirement. Check pos_machine for
the same gap — its bridge shares the design.

## Finding 2 — `<queries>` parity gap with pos_machine (latent)

pos_machine's manifest declares `<package android:name="com.mosambee.dhofar.softpos"/>` plus
`<intent>` queries for `com.mosambee.softpos.login`/`.payment`; pos_handheld's `<queries>`
declares only Flutter PROCESS_TEXT + KOZEN service packages. Adjudicated NOT tonight's blocker
(raw activity starts are exempt from visibility filtering — the launch demonstrably fired), but
any resolve/preflight-based check (`resolveActivity`, `queryIntentActivities`, package-presence
probes) will wrongly report Mosambee absent on Android 11+. Align the handheld manifest with the
machine's declarations.

## Diagnosis history (kept for honesty)

1. First hypothesis (missing `<queries>` blocks the launch) was **refuted live**: the bridge log
   + system `ActivityTaskManager` records prove the Login activity launched without the declaration.
2. True immediate cause of the session blocker: the G7's Mosambee install was **corrupted**
   (`SQLiteException: Unable to resume activity`, broken `databases/` dir, isolated service
   failures → crash-loop). Operator cleared Mosambee's storage + re-provisioned → bridge worked
   end-to-end immediately: intent → SoftPOS → acquirer dispatch → genuine failed response →
   reconciliation prompt → order 12 recorded `pending_reconciliation` with the bank verdict on
   the tender. Classified **environment/device-state**, not product.
3. What remains product-side is Findings 1–2 above.

## H6 final classification

**PASS (with notes)** — the real bridge was exercised end-to-end on the handheld (tap → dispatch
→ genuine acquirer response → safe ambiguous-path handling; no-round-up rule held; commission
deferral held; zero false records). Approved authorization NOT demonstrated (bank test card
declines — same limitation as machine S7; pending working approval media from the bank).
