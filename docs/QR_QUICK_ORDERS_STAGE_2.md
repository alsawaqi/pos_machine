# QR Quick Orders — unified staff flow, stage 2

This is a local implementation stage, not an installed rollout or the complete
unified workflow. Requires pos_api a06f719739c58813dd361ccb70b48578f7de9558.
Do not deploy this client alone against an older server.

## Implemented

- Separate QR Quick Orders navigation. The ordinary Held Orders store/callbacks
  remain local staff orders; no QR server snapshot is written there or to a cart.
- Branch pending list, reference, server total, age, charge/session state and
  phone tail only. Five-second reads while this screen is visible/foreground;
  paused beneath the editor or settlement route. No automatic mutation retry.
- Review original lines read-only; add new catalogue items with quantities,
  required modifiers and notes to the SAME order UUID. Outbound lines contain
  only product_id, qty, addon_ids and notes. No client money or GPS fields.
- Explicit existing to-counter action before editing station-routed bills.
  Server charge/stock/availability refusals never roll back a local table/cart.
- Durable SQLite request journal qr_quick_requests.db, separate from all sales
  databases. Scope is server URL + company + branch + device. Insert commits
  before POST; a pending payload is never overwritten. This is not a sync outbox.
- A lost/invalid response blocks new additions/payment on that bill until the
  original request is acknowledged. Retry sends the exact saved ID/payload,
  including after restart or if the bill no longer appears in the pending list.
  Storage corruption/failure blocks writes; never discard the journal to fix it.
- Device-token or server/device-scope changes fence the gateway. Only deliberate
  documented no-write refusals on a fresh request clear it. Refusals AFTER an
  uncertain attempt retain the journal for reconciliation.
- EN/AR copy with a screen language switch, narrow/wide widget coverage. The
  two lib/qr_quick directories are identical; catalogue/navigation adapters differ.

## Payment boundary / remaining work

The POS machine temporarily opens the EXISTING QrPendingSheet from Proceed to pay.
Its claim-before-tender, replay, frozen amount, release, recovery, standalone pay
and route-exit protections are untouched. No new payment/sync implementation here.

The handheld has no equivalent guarded settlement layer at its parent commit.
Its QR payment action is deliberately disabled with a visible explanation. Do not
route QR bills through resumeHeldOrder or the normal unguarded local-cart checkout.

The NEXT stage integrates the normal payment page and its supported tenders with
the QR reservation/recovery contract on both devices. Separate later stages unify
Dine-In, remove QR Tables navigation and add the deduplicated arrival bell.
Do not claim those stages complete, or install this partial build on devices.

## Verification

New tests: qr_quick_controller_test, qr_quick_gateway_test, qr_quick_screen_test,
qr_quick_catalogue_test. 48 focused tests passed on each client. All DB writes in
these new tests use SQLite :memory:. HTTP adapter tests use an in-process fake,
not a server. Existing payment/QR-table tests and skip markers are preserved.

Optional native rendered evidence:
QR_QUICK_SCREENSHOT_DIR=<existing directory> flutter test --no-pub test/qr_quick_screen_test.dart
The evidence helper loads local Tahoma/MaterialIcons fonts only when requested.
No generated application file, dependency update or existing database migration.

Full-suite pins/counts, local commit IDs and evidence paths are in the workspace
pos/documentation/QR-003_UNIFIED_STAFF_FLOW_PROGRESS.md stage 2 record.
