# Release signing — one-time setup (pos_machine)

Identical scaffold to pos_handheld (see its docs/RELEASE_SIGNING.md for
the full runbook): gradle picks up a real keystore automatically when
`android/key.properties` exists, and falls back to debug keys when it
doesn't.

**Recommended: reuse the SAME keystore for both apps.** One
`keytool -genkey` (already described in the handheld runbook), one file
to back up, one set of passwords in the password manager. Copy the same
`key.properties` into this repo's `android/` folder and build:

```bash
flutter build apk --release
```

ApiConfig already defaults release builds to production
(https://posapi.mithqal.net/api/v1).

Same warnings apply:
- a debug-signed install cannot be upgraded in place by a properly
  signed one (devices need one uninstall/reinstall — the Drift cache
  and outbox are wiped; sync everything first);
- `applicationId` is still `com.example.pos_machine` and freezes at the
  first real install — decide the final id in the same
  uninstall/reinstall window;
- losing the keystore or its passwords means no in-place updates, ever.
