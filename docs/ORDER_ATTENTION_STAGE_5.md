# Order attention notifications — Stage 5

Implemented 2026-09-12 on codex/qr003-unified-staff. Local only; not installed.

## Contract

- An app-wide foreground listener polls GET /device/order-attention every five
  seconds, with one request in flight. It starts only after a staff POS surface
  is mounted and an authenticated device/staff scope exists. It remains mounted
  across quick-order, Dine-In and normal-payment routes. Pause/dispose stops it.
- Quick alerts identify QR-web counter-held bills with all six charge fields
  null. Table alerts identify customer pending-confirmation rounds from the
  operational board. Staff/accepted/rejected rounds are not incoming alerts.
- First successful snapshot per server/company/branch/device is shown silently.
  Subsequent unseen identities are remembered before a single bell per batch.
  Reordering, repeated responses, disappearing/reappearing IDs, ordinary restart,
  staff changes and reconnect do not ring a remembered arrival again.
- Ledger keys are hashes of the existing device scope; stored values contain
  only version and arrival IDs, not tokens, phones, money or staff identity.
  SharedPreferences writes are best-effort persistence, not an atomic transaction
  with a physical speaker. A process/power failure at that boundary cannot promise
  exactly-once audible delivery. Clearing app storage loses the ledger and is NOT
  an operational instruction (other POS data must be preserved).
- Invalid/unsupported snapshots retain a stale warning; corrupt/full/failed
  storage suppresses audio rather than resetting history. A 50,000-ID guard
  shows a storage warning instead of silently evicting old IDs.
- The reserved top bar shows quick/round counts, new-arrival text, connection or
  audio problems, and an explicitly activated test-sound button. No navigation,
  cart mutation, claim, payment, print or outbox write is attached to an alert.
- Android plays the configured notification tone via a small native channel,
  stops after two seconds/onPause, and never changes system volume or bypasses
  DND. Missing bridge/tone/volume does not hide the visual alert.
- No background Android service, OS notification permission, new dependency,
  migration, generated file, payment/coordinator change or device work.

## Copy

EN: Staff attention: QR quick {count} · Table rounds {count}
AR: بانتظار الموظف: طلبات QR السريعة {count} · جولات الطاولات {count}
EN/AR new: New order / طلب جديد
EN/AR test button: Test notification sound / اختبار صوت التنبيه
EN failure: Alerts not updating — check connection
EN failure: Alert storage unavailable — sound paused
EN failure: Sound unavailable — check device volume
Arabic equivalents live next to the English strings and are widget-tested RTL.

## Checks

The new test/order_attention_test.dart contains 26 tests. It covers durable
deduplication, failures, late callbacks/scope changes, background pause, concurrent
consumers, authenticated read-only transport, native registration, a pushed
payment/form route with zero pay invocations and unchanged text, and Arabic
screen-reader/360x640 layout. Every pre-existing test/assertion/skip is unchanged.

Results are recorded in the shared
documentation/QR-003_UNIFIED_ORDER_NOTIFICATIONS_HANDBACK.md, including immutable
tested trees, full suite deltas, analyzer, formatting and Kotlin compiler output.

Clean-export full-suite tree: ab925df0aa289a66ee3bd5712facf0c2f0891622.
Literal result: 01:54 +1366 ~3: All tests passed!
Analyzer: No issues found! Exit 0. New Dart files: 4 formatted, 0 changed.
Android bridge: Kotlin 2.2.20 / JDK 17 / Android 36 / cached Flutter embedding,
compiler exit 0 (bridge only, no APK and no physical audibility claim).
Existing test assertions/skips are unchanged; this increment adds 26 tests.

## Staff note

After independent verification and an approved debug rollout, keep the staff app
open and signed in. A new waiting counter quick order or customer round rings once
per device. Open QR Quick Orders or Dine-In to handle it normally; a notification
never confirms or charges it. Use the sound-test button on the notification bar
to check device volume. A silent first load is intentional; the bar still shows
waiting work. Report connection/storage/sound warnings; do not clear app data.
