# map-charity — Charity ecosystem integration audit

Read-only audit. All paths repo-relative; repos:
- `charity` = `\\wsl.localhost\ubuntu\home\abdallah644\projects\my-projects\charity`
- `pos_api` / `pos_admin` = under `...\pos\`
- `pos_machine` = `C:\src\projects\pos_machine`

## 1. Shallow map of the charity ecosystem (VERIFIED by directory listing)

| Subproject | Contents |
|---|---|
| `charity/charity-laravel-api` | Laravel API (src/, docker, docker-compose[.prod].yml). Hosts donation endpoints incl. the POS round-up receiver. |
| `charity/charity-db` | Docker-only project: `postgres:16-alpine` container `chariyt-db` on network `charity_net`, plus pgadmin (`charity-db/docker-compose.yml:1-40`). This is THE shared live Postgres for both charity and pos_* schemas. |
| `charity/charity-login` | Separate Laravel app (login/SSO), own src/docker. Not traced (out of charter depth). |
| `charity/charity-turn` | coturn TURN server (DEPLOY.md, coturn/, compose). Unrelated to donations. |
| `charity/marketing-api` | Separate Laravel app, own src/docker. Not traced. |
| `charity/nuxt-dashboard` | Nuxt dashboard (nuxt-app/). Reads charity data; no reference to `pos_roundup_donations` found (see §6). |
| `charity/deployment` | nginx gateway + `docker-compose.gateway.yml`. |

All prod compose files (charity-laravel-api, pos_api, pos_admin) join the external network `charity_net` (`pos_api/docker-compose.prod.yml:208-209` `charity_net: external: true`; `charity-laravel-api/docker-compose.prod.yml:16-17`). One Postgres, one network — the coexistence premise is real.

## 2. End-to-end round-up flow (VERIFIED, execution-chain)

### 2a. pos_machine — prompt + event emission
- Offer gate: `pos_machine/lib/state/pos_controller.dart:1449-1461` `canOfferCharityRoundUp` — card only (`selectedPaymentMethod == 'Credit Card'`), never delivery orders (P-G7), amount = ceil-to-OMR remainder `>= 0.001` (`:1443-1447` `offeredCharityRoundUpTotal/Amount`).
- Prompt: `_promptForCharityRoundUp()` `pos_controller.dart:3364-3397` — customer-display prompt, 2-minute timeout, `_activeCharityRoundUpPromptId` guards stale customer responses (`:3399-3414`).
- Sync payload: `pos_machine/lib/services/order_sync_payload.dart:376-414` — one `donation.record` event per accepted card leg, payload `{order_uuid, amount_baisas, payment_index, occurred_at}`; split path filters `payments[i]['method']=='card'` defensively (`:385-401`); single-payment path picks first card index. Events ride the same offline OrderOutbox push (`order.create`, `order.pay`, then `donation.record`) with stable `client_event_id`s (`lib/data/db/tables.dart:235`, `lib/services/pos_api_service.dart:214`).

### 2b. pos_api — writer of `pos_roundup_donations`
- Dispatch: `pos_api/src/app/Actions/Device/Sync/SyncEventDispatcher.php:71` maps `'donation.record' => DonationRecordHandler`.
- `pos_api/src/app/Actions/Device/Sync/Handlers/DonationRecordHandler.php`:
  - Validates payload (`:50-61`), resolves order scoped to device company+branch (`:67-74`).
  - Resolves the CARD payment by `payment_uuid` → `payment_index` (positional, payments inserted in array order by PayOrderHandler) → legacy latest-card fallback (`:197-223`). Throws if the addressed leg is not card (`:87-92`) — round-up can never be mis-attributed to cash.
  - P-F7 pending-reconciliation gate: `$orderHasPendingTender` (`:101-105`) — if the linked payment OR any tender on the order is `pending_reconciliation`, status = `'pending'` and forwarding is skipped.
  - Receipt: reuses the card payment's `bank_response` (device doesn't resend it), fallback to payload receipt (`:114-116`).
  - Status: `'pending'` if pending tender else `'success'` (`:124`); amount `Money::toOmr(amount_baisas)` (`:125`) — baisas→OMR at the boundary per ground rules.
  - DB transaction (`:127-166`): creates `RoundupDonation` row (uuid, company/branch/device/order/payment ids, bank_id/terminal/commission_profile snapshot from device, branch geo snapshot, `client_event_id`, `occurred_at`) and back-links the card payment (`roundup_amount`, `charity_transaction_id` → pos_roundup_donations.id, `:155-158`).
  - AFTER commit, best-effort forward via `ForwardCharityDonationAction` only when no pending tender (`:178-192`); success stamps `forwarded_at`. Crash between forward-success and stamp is safe: charity dedupes on `pos_reference` (see 2d).
- Model: `pos_api/src/app/Models/RoundupDonation.php:352` table `pos_roundup_donations`, casts `amount decimal:3`, `forwarded_at datetime` (`:359-372`).
- Idempotency POS-side: `client_event_id` unique on the table (migration §3) + the generic sync-event dedupe on `client_event_id` per device.

### 2c. pos_api → charity HTTP forward
`pos_api/src/app/Actions/Device/Sync/ForwardCharityDonationAction.php:268-334`:
- POST `{CHARITY_API_URL}/api/donations-pos-roundup`, timeout `CHARITY_API_TIMEOUT` default 8s (`pos_api/src/config/services.php:43-46`).
- Body: `pos_device_id`, `pos_branch_id`, `pos_branch_name`, `commission_profile_id` (device's CHARITY commission profile), `organization_id`, `amount` (OMR string), `receipt`, `status`, `terminal_id`, `bank_id`, `pos_reference` (= pos_roundup_donations.uuid, the dedupe key), branch geo (country/region/district/city ids share the charity geo id-space) (`:285-314`).
- Never throws; returns bool; unset `CHARITY_API_URL` ⇒ false (`:276-279`). Non-2xx logged info; exception logged warning (`:316-333`).

### 2d. charity-laravel-api — receiver (where charity's donations table is actually written)
- Route: `charity-laravel-api/src/routes/api.php:54` `POST /donations-pos-roundup` → `CharityTransactionsController::store_pos_roundup`, in the PUBLIC `throttle:120,1` group (`:49-55`) alongside `/donations`, `/donations-dhofar`, `/donations-bank-nizwa`. NO auth.
- `charity-laravel-api/src/app/Http/Controllers/CharityTransactionsController.php:550-706` `store_pos_roundup`:
  - Validates (`:554-579`), `pos_reference` max 64.
  - Idempotency key `'pos_roundup:'.pos_reference` (`:584-586`), namespaced so it can't collide with dhofar receipt keys; replay check inside the transaction (`:625-634`) returns the existing row; a race loser is caught via unique-violation on `idempotency_key` and answered 200 idempotent (`:685-700`).
  - Status: `resolvePosRoundupStatus` (`:1080-1093`) — explicit `status` from pos_api wins (normalized); else `receipt['status']==='success'` ⇒ 'success'; **else 'fail'**.
  - Writes `charity_transactions` via `CharityTransactions::create` (`:636-660`): `device_id = null` (a POS round-up has no charity device), `pos_device_id`/`pos_branch_id`/`pos_branch_name`, `commission_profile_id`, `organization_id`, `total_amount`, `bank_response`, `status`, geo, `terminal_id`, `idempotency_key`.
  - Writes `charity_transaction_shares` via shared `CommissionShareCalculator::compute` (`:662-673`) — snapshots percentage + recipient organization, distributes rounding remainder so SUM(shares) == total (per code comment).
  - Model `created` hook fires `CharityTransactionCreated` broadcast (per docblocks in both forwarders and controller `:547-548`).

### 2e. Retry / failure semantics
Three paths clear `forwarded_at IS NULL`:
1. **Inline** (2c) at donation.record time — only when no pending tender.
2. **pos_admin reconciliation** — `pos_admin/src/app/Actions/Admin/Reconciliation/ReconcileDeferredEffectsAction.php:204-241` `forwardDonations`: for each approved order, forwards every donation with `forwarded_at IS NULL`, passing explicit status `'success'` (`:223-231` — "the admin approval confirms the money arrived"), stamps `forwarded_at` + local `status='success'` (`:233-234`). Called AFTER the flip transaction from `ApprovePendingReconciliationAction.php:75-86` (best-effort, never rolls back settlement) and from the bank-file commit path (per docblock `:25-40`). Uses pos_admin's twin `ForwardCharityDonationAction` (`pos_admin/src/app/Actions/Admin/Reconciliation/ForwardCharityDonationAction.php:13-17` — explicit "TWIN of pos_api ... keep in sync", accepted duplication).
3. **Step-10 hourly sweep** — `pos_admin/src/app/Console/Commands/RetryRoundupForwarding.php` (`donations:retry-roundup-forwarding`, limit 200/run): eligibility `forwarded_at IS NULL` AND payment not `pending_reconciliation` (defers those to the approval flow, `:63-70`) AND row ≥10 min old (`:48` — never race the in-flight inline attempt). Safe because charity dedupes on `pos_reference` (`:29-31`).

## 3. Schema ownership / shared-DB coexistence rules (VERIFIED)

- **pos_admin owns the whole `pos_*` schema**: `pos_admin/src/database/migrations/2026_06_18_010000_create_pos_roundup_donations_table.php` creates `pos_roundup_donations` (uuid unique, company/branch/device/order/payment ids indexed no-FK — deliberate, docblock lines 23-27; `client_event_id` unique; `amount decimal(12,3)`; status default 'pending'; `pos_roundup_status_index`). `2026_07_11_010000_add_forwarded_at_to_pos_roundup_donations.php` adds `forwarded_at` and **backfills history to `created_at`** so pre-P-F7 rows are never re-forwarded (duplicate prevention, lines in `up()`).
- **pos_api writes** `pos_roundup_donations` but owns no schema (only test-mirror `pos_api/src/database/migrations/0000_00_00_000000_create_test_schema.php`).
- **charity-laravel-api owns the charity tables** and added the POS integration columns via its OWN additive migrations: `2026_06_08_000001_add_pos_link_to_charity_transactions.php:27-29` (`pos_device_id`, `pos_branch_id`, index — "soft pointers into the pos_* schema, same id-space"), `2026_06_18_100002_add_idempotency_key_to_charity_transactions_table.php:23-30` (nullable `idempotency_key` + **partial unique index** `WHERE idempotency_key IS NOT NULL` on Postgres), `2026_07_01_120000_add_pos_branch_name_to_charity_transactions.php`.
- Design rationale for the separate POS table: `charity_transactions.device_id` + `country_id` are NOT NULL and assume a CHARITY device — so pos writes its own mirror-shaped table and forwards a real `charity_transactions` row over HTTP instead of cross-writing charity's table (DonationRecordHandler docblock `:26-38`; create-migration docblock).
- Additive-migration rule stated at `pos_admin/docker-compose.prod.yml:9` ("Migration safety (shared DB): migrate --force is ADDITIVE").
- Cross-schema access is DB-level only for reads; the write path between systems is HTTP (`/api/donations-pos-roundup`), not SQL — no app writes the other side's tables. VERIFIED by grep: no `charity_transactions` writes in pos_api/pos_admin, no `pos_roundup_donations` references anywhere in charity-laravel-api or nuxt-dashboard.

## 4. FINDINGS

### F1 (P1) — The "hourly retry sweep" is never scheduled anywhere in-repo
`RetryRoundupForwarding` exists and its docblock calls it "the hourly retry sweep" (`pos_admin/src/app/Console/Commands/RetryRoundupForwarding.php:15-19`), but:
- `pos_admin/src/routes/console.php:14-17` registers only `ScanExpiringCompanyDocumentsJob` (dailyAt 02:00). No `Schedule::command('donations:retry-roundup-forwarding')` anywhere in `src/` (grep over all non-vendor PHP).
- No `schedule:run` runner, cron, or supervisor entry in `docker-compose.prod.yml` / `docker/prod/*` (grep: only the one-shot `php artisan migrate --force` container and an `artisan` utility container whose CMD is bare `php artisan`).
- Repo-wide grep across all pos repos for `schedule:run|crontab|retry-roundup` in md/yml/sh: only `pos_admin/ops/backup/charity-db-backup.sh:43` (unrelated).
Consequence: a round-up whose inline forward failed (charity outage/network) on a fully-settled order (no pending tender, so the reconciliation path never touches it) sits with `forwarded_at NULL` forever — the customer's donated money never reaches the charity system. Note the same gap means the ScanExpiringCompanyDocuments schedule also never fires. Cannot verify a host-level crontab outside the repos (verified:true for "not in repo", the operational reality is inferred).

### F2 (P2) — Sweep retries can mis-file a settled round-up as 'fail' at charity
`RetryRoundupForwarding.php:83-90` passes `null` as the explicit status (comment `:80-82` says "status from the recorded receipt"). Charity's `resolvePosRoundupStatus` (`CharityTransactionsController.php:1080-1093`) then falls back to `receipt['status']==='success'`, else **'fail'**. The inline path was changed precisely because receipt-derived status "mis-filed every forwarded round-up as 'fail'" (DonationRecordHandler docblock `:118-124`) — the device never resends the receipt and the stored `bank_response` may lack a top-level `status`. A sweep-retried donation whose `bank_response` has no `status: success` key is created at charity with status 'fail' while `pos_roundup_donations.status` is 'success'. Fix would be passing `$donation->status` (or 'success') like `ReconcileDeferredEffectsAction:229` does. Severity P2 (reporting mis-file, no money loss; also currently moot because of F1).

### F3 (P2) — Charity round-up ingestion endpoint is public and unauthenticated
`charity-laravel-api/src/routes/api.php:49-55`: `/donations-pos-roundup` sits in the public `throttle:120,1` group with no auth token/shared secret; `store_pos_roundup` trusts caller-supplied `status` ('success' honored first, `:1082-1085`), arbitrary `amount`, `pos_device_id`, `organization_id`. Anyone on the internet (endpoint fronted by the deployment gateway) can create `charity_transactions` rows marked success with fabricated amounts and org attributions, polluting charity dashboards/share ledgers (shares are computed and persisted per request, `:662-673`). Route comment acknowledges rate limiting as "defense-in-depth" but the "amounts still originate from the payment processor receipt" claim does not hold for this endpoint since explicit `status` overrides the receipt. No IP allowlist found in `deployment/nginx` (not exhaustively verified — gateway config not fully read: verified partially).

### F4 (P3) — "Charity reporting UNIONs this table later" is not implemented
The design docblocks (DonationRecordHandler `:33`, pos_admin create-migration docblock) say charity reporting can UNION `pos_roundup_donations` later. Grep over `charity-laravel-api/src` and `nuxt-dashboard` finds zero references to `pos_roundup_donations`. Charity-side visibility of POS round-ups therefore depends 100% on successful HTTP forwarding — which sharpens F1's impact. pos_admin has its own report (`pos_admin/src/app/Actions/Admin/Reports/AdminRoundUpReportAction.php`) reading the POS table.

### F5 (P3) — Duplicated forwarder twins (accepted, documented)
`pos_admin/.../ForwardCharityDonationAction.php` vs `pos_api/.../ForwardCharityDonationAction.php` are code twins ("keep in sync" docblock, pos_admin `:13-17`); diff shows only comment differences today. Drift risk only; documented as accepted cost.

## 5. Cannot-verify / inferred
- Whether a host crontab or external scheduler runs `schedule:run` or the sweep command in production (nothing in any repo; F1 marked accordingly).
- Live DB state (which migrations actually applied) — no DB access, read-only audit.
- Whether the deployment nginx gateway restricts `/api/donations-pos-roundup` by source (gateway configs not exhaustively read).
- `CharityTransactionCreated` broadcast behavior taken from docblocks; the model hook itself was not read.
