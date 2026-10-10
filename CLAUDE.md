# pos_machine — MITHQAL counter till

Flutter app for the Sunmi T3 counter till (`net.mithqal.pos.machine`, device `TV07P58G40097`).
Uses the Sunmi printer (`sunmi_printer_plus`), Sunmi fingerprint aar (`android/app/libs`), a customer
display (`flutter_presentation_display`), and Mosambee SoftPOS for card payments.

## Stack

- Dart SDK `^3.11.4`, **Riverpod 3** (`ProviderScope` in `lib/main.dart`), **Drift** (`lib/data/db/app_database.dart`) + sqflite.
- Codegen (after changing Drift tables or other annotated code):
  `dart run build_runner build --delete-conflicting-outputs`
- Localization: `lib/l10n/app_en.arb` + `app_ar.arb` → `flutter gen-l10n` (class `L10n`). Add every string to **both** files.
- Layout: `lib/` by feature (`dine_in`, `qr_quick`, `kitchen`, `tenancy`, `order_workspace`, …) plus `core/`, `data/`, `providers/`, `services/`, `screens/`.
- Git dependencies: `mithqal_pricing` (tag `v0.4.0`), `mithqal_softpos` (pinned commit), `mithqal_kitchen_core` / `mithqal_kitchen_android` (from `C:/src/projects/pos_kds`, pinned commit).
  Local `pubspec_overrides.yaml` points these at sibling folders — gitignored, never commit it.

## Commands

```bash
flutter analyze
flutter test                                   # one known env-only failure: softpos_bridge_core_hash_test
flutter run -d TV07P58G40097                   # debug; first: adb -s TV07P58G40097 reverse tcp:8088 tcp:8088
```

- API base URL (`lib/core/api_config.dart`): `--dart-define=POS_API_BASE_URL=...`; release defaults to production, debug to `http://localhost:8088/api/v1`.
- Release signing: see `documentation/pos_machine/docs/RELEASE_SIGNING.md`. Same keystore as pos_handheld. A debug-signed install can't be upgraded in place.

## App rules

- Device auth: one-time activation code → `mdev_` bearer token in secure storage. A **bare 401** means revoked (re-pair);
  a 401/422 **with `errors[]`** is an app error — never re-pair on it.
- Sync: `POST /device/sync/push`, ≤ 50 events per batch; each `client_event_id` is a UUIDv4 that **stays the same across retries**.
- Never auto-reprint a `sent_unconfirmed` kitchen ticket.

## Hard rules (owner)

- **Never push, deploy, or publish an APK** unless the owner asks for that exact step. Production is read-only.
- **Commit locally only, and only when asked.** Stage specific files; never `git add -A`, `git reset --hard`, `git clean`, or force-checkout — HEAD is not the complete state and dirty trees are normal.
- **Never type PINs, passwords, or card details**; never print secrets, codes from dumps, or keystore contents; never suggest real card/bank payments.
- **Never weaken, skip, or delete tests** to get a green run. Do only the task you were given; if code and spec disagree, trust the code and report it.
- **Never commit `pubspec_overrides.yaml` or `android/key.properties`.** `key.properties` may exist only during a release build — delete it afterwards.
- **Devices:** every `adb` command names its serial (`adb -s <serial>`). Install with `adb install -r` only — never uninstall or clear data (that wipes the offline outbox).
  Serials: T3 till `TV07P58G40097` · handheld `0320840990319645` · customer tablet `LF3925CR00245` (pos_customer **only**) · KDS `H10125007106` · payment station `0620741070356857` · leave BM-12WTN `H6525006734` alone.
- **Money is integer baisas** (1 OMR = 1000) everywhere on the wire. Never floats.
- **The device contract only grows.** Old APKs stay in the field: add fields, never change the meaning of existing ones.
- The owner is non-technical: one action at a time, plain language.

## System context

Part of MITHQAL POS. Backend: the Laravel apps in
`\\wsl.localhost\ubuntu\home\abdallah644\projects\my-projects\pos` (see its `CLAUDE.md`); devices talk to **pos_api** only.
Docs: `...\pos\documentation\` — before starting, read the newest `SESSION_HANDOFF_*.md` and the last ~20 entries of
`LAUNCH_SHARED_WORKLOG.md` (append-only; log STARTED/DONE entries).
Flutter SDK: `C:\src\flutter`. The Dart MCP server (dart-flutter plugin) can analyze, test, and hot reload — after editing
`lib/**/*.dart` in a running app, hot reload (or hot restart for `main()`/`initState`/global state changes).
