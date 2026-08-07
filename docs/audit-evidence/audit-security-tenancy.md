# Audit — Security & Multi-Tenancy (charter: audit-security-tenancy)

Read-only deep audit of the three Laravel backends (pos_admin, pos_merchant, pos_api) plus the
pos_api↔charity forwarding boundary. All evidence is `repo/relative/path:line`. WSL repos live under
`/home/abdallah644/projects/my-projects/pos/<repo>/src/...`; paths below are repo-relative to that `src/`.

pos_api HEAD at audit time: `f93e46d`. pos_admin routes verified against working tree.

---

## 1. The three auth planes

### 1a. Admin plane (pos_admin) — platform operator
- Login restricts the candidate pool to `platform_admin` rows BEFORE the password check, using
  `->validate()` not `->attempt()` so no session is minted until the type check passes.
  `pos_admin/app/Http/Controllers/Auth/AuthenticatedSessionController.php:67-80`.
  Scope: `pos_admin/app/Models/User.php:132-134` (`scopePlatformAdmin` → `where user_type=platform_admin`);
  re-check `isPlatformAdmin()` `:143-146`.
- TOTP 2FA: a confirmed-2FA account gets NO session/JWT from the password alone; a pending state is parked
  and only `TwoFactorChallengeController` converts it (`AuthenticatedSessionController.php:88-101`).
- Defence-in-depth re-check on the SPA/web routes: `EnsureUserIsAuthenticated.php:61-69` boots any
  non-platform_admin `web`-guard user out (logout + session invalidate). **Wired only to `routes/web.php:88`.**
- **GAP (C2, still open) — admin API data plane skips the isPlatformAdmin re-check.**
  `routes/admin.php:47` guards the entire `admin/api/v1/*` surface with `['auth','pos.admin.session','pos.tenant']`
  — the FRAMEWORK `auth` alias, NOT `EnsureUserIsAuthenticated`. `bootstrap/app.php:33-36` only aliases
  `pos.admin.session`/`pos.tenant`; `EnsureUserIsAuthenticated` is never registered for the API group.
  Worse, `SetTenantContext.php:36-40` ACTIVELY accommodates a merchant principal: when `user_type===Merchant`
  it pins the tenant to their `company_id` and sets the Spatie permission team to their company team.
  So the login-time gate is the only barrier on the API plane; the defence-in-depth net that catches a
  "session issued via some future back door" exists for /admin pages but not for the /admin/api data plane.
  Practical exploitability is gated by cookie isolation (distinct cookie names + `SESSION_DOMAIN=null`,
  verified in prod per the tenancy memory) so this is a defence-in-depth inconsistency, not a confirmed breach.

### 1b. Merchant plane (pos_merchant)
- Login critical rail: candidate restricted to `user_type==='merchant'` before password validate
  (`pos_merchant/app/Http/Controllers/Auth/AuthenticatedSessionController.php:59-69`) — mirror of the admin rail,
  prevents an admin credential (same hashed column) landing in the merchant portal.
- Tenant pin: `SetMerchantTenantContext` binds `MerchantTenantContext` to `$user->company_id`, `scoped()` not
  `singleton()` (no cross-request bleed). Global scope `BelongsToCompanyScope` (see §3).

### 1c. Device + staff-PIN plane (pos_api)
- Device guard: `AppServiceProvider.php:39-49` — `Auth::viaRequest('pos_device', …)` resolves the Bearer token
  straight off `pos_devices.device_token`, `whereNotIn('status',['blocked','inactive'])`. SoftDeletes excludes
  deleted rows. Revoked/decommissioned devices rejected at the guard (hardening item MEDIUM, closed `3db765c`).
- Staff PIN login: `StaffPosLoginController.php` + `Actions/Device/StaffLoginAction.php:35-52`.
  bcrypt `Hash::check` against ACTIVE staff scoped to `company_id AND branch_id` (§5.4.2 branch-bound);
  generic 401 `invalid_pin` (no existence oracle). Geofence fail-closed at sign-in
  (`StaffPosLoginController.php:47-73`) mirroring order.create.
- Manager PIN (comps/voids/gifts approval): `VerifyManagerPinAction.php:44-76` — ACTIVE staff of the device's
  company whose `position ∈ manager_approval_positions` (company setting, default `['manager']`), company-wide
  (roaming area manager) but local branch checked first; generic 401 for both wrong-PIN and wrong-position
  (no oracle). Kitchen-PIN walk-up on same brute-force bucket.

---

## 2. Device token issuance / revocation
- Pairing: `Actions/Device/PairDeviceAction.php` — kiosk_id + one-time activation token
  (`DeviceActivationToken::hash()` = SHA-256, `Models/DeviceActivationToken.php:` hash + `isUsable()`
  = unused ∧ unrevoked ∧ unexpired). Single-use: stamps `used_at` inside a DB transaction. Generic errors
  (no kiosk enumeration). Token minted as `'mdev_'.Str::random(60)`.
- Single-code activation: `Actions/Device/ActivateDeviceAction.php` — global lookup by token_hash, re-checks
  `isAssigned()` + not `blocked`/`inactive`, single-use, mints token in a transaction.
- **FINDING — device_token stored PLAINTEXT.** `pos_admin/database/migrations/2026_05_24_020000_add_blueprint_fields_to_pos_devices.php:76`
  (`string('device_token',80)->nullable()->unique()`); guard matches the raw column
  (`AppServiceProvider.php:44-46`); `Models/Device.php:31` fillable, no `encrypted`/hash cast. Because all POS
  apps + charity share ONE Postgres (`charity_db`), any read primitive (leaked backup, SQL-i in a sibling app,
  DBA overreach) yields live bearer credentials that fully impersonate any terminal. Blueprint hardening item
  "hash pos_api device_token at rest" is on the backlog and NOT done (tenancy memory backlog #6).
- Revocation path: admin `block`/decommission sets status → guard rejects immediately (verified §1c).
  No token rotation-on-suspicion mechanism beyond status flip.

## 3. Tenant scoping — verify the "manual discipline" claim
- **pos_api: CONFIRMED manual, no global scope.** Every device endpoint derives `company_id`/`branch_id` from
  the guard-resolved `$device`, never the request body. Sampled (all scope correctly):
  - `DeviceOrdersController.php:58-59, 98-102` (active/history: company+branch)
  - `DeviceCustomersController.php:41-53, 98, 127-150` (search/show/store: company)
  - `DeviceTransfersController.php:43-45` (inbox: company+branch+to_device), `:76-83` (claim: uuid re-checked
    against `order.company_id`+`branch_id` under `lockForUpdate`)
  - `DeviceKitchenController.php:47-53, 82-88, 140-142` (company+branch)
  - `DeviceShiftController.php:53-63` (company+branch+staff / device)
  - `DeviceBranchDevicesController.php:37-38`, `DeviceMessagesController.php:53-80` (company+branch+target)
  - `Actions/Device/BuildBranchReportAction.php:38-49` (`pos_orders.company_id`)
  - `Actions/Device/Production/{Start,Finish,Cancel}ProductionAction.php`, `ApplyDispositionAction.php`,
    `ComputeExpiringStockAction.php` — all base on `company_id`(+`branch_id`); uuid resolved under company
    (`CancelProductionAction.php:60-65`).
  - `AllocateOrderNumberAction.php:46-69` (company).
- **pos_merchant: has a GLOBAL scope now** (added Phase 2a). `app/Models/Scopes/BelongsToCompanyScope.php`
  reads `MerchantTenantContext->id()` and NO-OPs when unset (guests/auth/console/queue/route-binding);
  additive create-stamp; escape hatch `withoutGlobalScope(...)`. Applied via `Concerns/BelongsToCompany`.
  Exempted (correctly): `User`, `Company`, `AuditLog`, `Device` (read-only mirror) — confirmed the only
  company_id models without the trait are `AuditLog.php`, `Device.php`, `User.php`.
  Manual `refuseIfNotInTenant()` guards + `EnsureBranchScope` kept belt-and-braces. Raw report queries that
  bypass the ORM scope were sampled and all anchor `company_id` at the base:
  `Actions/Pos/Reports/StaffActivityReportAction.php:36-42` (`pos_orders.company_id=requiredId()`),
  `TableInsightsAction.php:87-134` (company+branch, joins transitively scoped via `whereIn(order_id, $paid)`).
- **pos_admin: opt-in TenantScope; null context = platform-wide** (correct for a platform operator). Only
  Device/Branch use `BelongsToCompany`; the rest are deliberately-unscoped admin mirrors.

## 4. Cross-tenant FK validation on order.create (the closed CRITICAL leak)
- **CONFIRMED CLOSED.** `Actions/Device/Sync/Handlers/CreateOrderHandler.php:72` calls
  `assertReferencesInTenant()` (`:279-347`): products (`:294`), add-ons (`:305-312`), customer (`:315-319`),
  table (`:322-326`), staff_id via `TenantReferenceGuard::assertStaffInTenant` (`:331`), joined tables
  (`:335-345`). `withTrashed()` on products/add-ons so an offline-queued order for a since-deleted menu item
  still settles (ownership still provable). A foreign ref throws → event acked `failed` (retryable), never
  silently snapshots another tenant's data.
- `TenantReferenceGuard.php` (`Actions/Device/Sync/TenantReferenceGuard.php:35-42`): `assertStaffInTenant`
  uses `PosStaff::withTrashed()->where(company_id)->whereKey($staffId)`.
- Tests (contract): `tests/Feature/DeviceSyncOrderTest.php` — `test_order_create_rejects_a_product_from_another_company:475`,
  `_addon_:495`, `_customer_:517`, `_table_:534`, `_staff_member_:551`, `_accepts_a_soft_deleted_staff_member:568`,
  `_rejects_a_joined_table_:631`, `_accepts_a_customer_from_the_same_company:704`,
  `test_idempotency_is_scoped_per_device_not_globally:720`.

## 5. Known open items (charter list)
- **VULN-4 (staff_id payload validation): now CLOSED**, not just in order.create. `assertStaffInTenant`
  present in `CreateOrderHandler.php:331,509`(comp approver), `OpenShiftHandler.php:50`, `ProductWasteHandler.php:69`,
  `StockCountHandler.php:74`, `ExpenseLogHandler.php:58`. Online production/disposition paths validate staff too
  (`StartProductionAction.php:62-66`, `ApplyDispositionAction.php:50-54`). Committed `c70f2cb` (Phase 4).
- **admin-API platform-admin re-check (C2): STILL OPEN** — see §1a. verified.
- **nightly tenant-integrity sampling job (§9.11.7): NOT BUILT.** grep for
  `TenantIntegrity|tenant-integrity|IntegritySampling|CrossTenant` across all three app trees = 0. verified absence.

## 6. PII encryption + shared APP_KEY
- Encrypted casts present: `pos_admin/app/Models/CompanyOwner.php:69-71` (civil_id, phone, email),
  `User.php:78,85-86` (phone, 2FA secret + recovery), `PosStaff.php:62` (phone). Mirror in pos_merchant
  (`User.php:74,81-82`, `PosStaff.php:72`).
- Shared-APP_KEY drift guard: `Concerns/DecryptsDefensively.php` — `fromEncryptedString` catches `DecryptException`,
  logs a breadcrumb, returns NULL instead of 500ing (pos_admin+pos_merchant share APP_KEY + `pos_users`; a
  `key:generate` would break every MAC — memory `shared_app_key`).
- **GAP — customer phone/plate stored PLAINTEXT.** `pos_api/app/Models/Customer.php:30-35` casts only
  `wallet_balance`; `pos_merchant/app/Models/Customer.php:57-70` casts wallet/DOB/tags — neither encrypts
  `phone`. This is structural: a UNIQUE `(company_id, phone)` constraint + plate `LIKE` search
  (`DeviceCustomersController.php:45-46`) require deterministic plaintext, and there is no blind-index column.
  Consumer PII (phone, vehicle plate, DOB, tags) therefore sits in cleartext in the shared DB. verified.

## 7. PIN hashing + throttling
- bcrypt via `Hash::check` (`StaffLoginAction.php:44`, `VerifyManagerPinAction.php:60`), stored `pin_hash`.
- Rate limiters (`AppServiceProvider.php:52-71`): `device-pair` 10/min per-IP + 20/min per-kiosk;
  `device-activate` route uses `throttle:30,1`; `pos-login` 10/min per-device (shared by login + verify-manager-pin
  + verify-kitchen-pin + production/disposition cancel — one combined PIN brute-force bucket);
  `device-api` 120/min per-device. Route wiring in `routes/api.php` confirms buckets.
- Admin login limiter 5/min (`config/pos_admin_auth.php:18`), 2FA challenge 5/min (`:22`).

## 8. Permission gates on sensitive POS actions
- Void/pay/hold/transfer are client-asserted sync events but the handler resolves the order under the device's
  own tenant, so cross-tenant is impossible: `VoidOrderHandler.php:69-72`, `PayOrderHandler.php:55-58`,
  `HoldOrderHandler.php:36`, `DeviceTransfersController.php:76-83` (all `where uuid + company_id + branch_id`,
  mutation under `lockForUpdate`). No IDOR on any `{uuid}` route.
- Comps/cancellations/gifts require a server-verified manager PIN (§1c). Kitchen/void/discount OPEN-gates are
  device-side (positions emitted in `/device/config`); a rooted device can void/comp/discount its OWN tenant's
  orders freely — accepted offline-first design risk (P3 note), never a cross-tenant issue.
- Admin Scalefusion control gated by `DevicePolicy::control` → `PlatformPermission::DevicesControl`
  (`DevicePolicy.php:112-114`); reads by `DevicesView` (`:39-41`).

## 9. Audit log coverage, immutability, hash chain (§9.13.5)
- Writer: `Actions/Security/WriteAuditLogAction` + `Data/Security/AuditLogData`. Call sites cover
  2FA enable/disable/confirm/challenge, advertiser/user/company/device/branch/settings mutations, device
  assign/decommission, reconciliation settle/mark/reject, Scalefusion control (`DeviceScalefusionController.php:164-179`).
- Immutability: `Models/AuditLog.php:17-26` — `UPDATED_AT=null` (append-only), `booted()` throws on
  `updating`/`deleting`. **BUT this is ORM-level only** — a raw `DB::table('pos_audit_logs')->update/delete`,
  a direct SQL statement, or any non-Eloquent access bypasses it entirely.
- **FINDING — no tamper-evident hash chain (blueprint §9.13.5).** Table schema
  `pos_admin/database/migrations/2026_05_12_160004_create_pos_admin_foundation_tables.php:90-106` has NO
  `hash`/`previous_hash`/`signature` column (grep = 0). There is no per-row hash of the prior row, so silent
  row deletion/reordering at the DB layer is undetectable. verified.

## 10. Secrets scan (locations only — NO values printed)
- No `.env` committed in any of the three repos (only `.env.example` tracked). verified via `git ls-files`.
- No hardcoded token/key/Bearer literals in `app/` (pattern scan = 0).
- Scalefusion token sourced from `config('services.scalefusion.token')` → env (`Services/ScalefusionService.php:225`).
  Charity/AWS/Slack/Postmark/Resend keys all `env()`-sourced (`pos_api/config/services.php:18-45`).
- **FINDING — hardcoded default super-admin password fallback.**
  `pos_admin/config/pos_admin_auth.php:37`: `env('POS_ADMIN_DEFAULT_PASSWORD', '<literal in repo>')`, consumed by
  `database/seeders/DefaultAdminUserSeeder.php:22-38` via `updateOrCreate(['email'], [...,'password'=>$password...])`
  and `syncRoles([SuperAdmin])`. If the seeder ever runs in an environment where the env var is unset, the
  platform SuperAdmin is created — or an existing one RESET — to a source-committed credential. The email default
  is also a literal (`:36`). verified. (Value intentionally not reproduced here.)

## 11. Scalefusion remote wipe / lock authorization
- Every control action funnels through `DeviceScalefusionController::control()` (`:157-190`):
  `authorize('control',$device)` → resolve kiosk_id → run → `WriteAuditLogAction` → relay. Route-model binding
  `{device:uuid}` under `pos.tenant`. Reboot/alarm/lock/unlock/clearAppData/broadcast + the generic `action`
  (screen_lock, shutdown, **factory_reset, delete_device, mark_as_lost, wipe_sd_card**) all gated by the SAME
  `DevicesControl` permission (`:106-128`). Authorized, audited, tenant-safe.
- **P3 observation:** destructive/irreversible actions (factory_reset, delete_device, wipe_sd_card) share one
  permission with benign ones (buzz, alarm) — no step-up / no separate elevated permission for a remote wipe.

## 12. Charity round-up forwarding trust boundary
- **FINDING — pos_api forwards money-shaped records to a PUBLIC, unauthenticated charity endpoint.**
  `pos_api/app/Actions/Device/Sync/ForwardCharityDonationAction.php:52-78` POSTs
  `{pos_device_id, pos_branch_id, organization_id, commission_profile_id, amount, status, terminal_id, bank_id,
  receipt}` to `<CHARITY_API_URL>/api/donations-pos-roundup` with `acceptJson()->asJson()` and **no bearer /
  no shared secret / no HMAC signature**. The receiving route
  `charity-laravel-api/src/routes/api.php:54` sits in a group whose only middleware is `throttle:120,1` —
  no `auth`, no signature check. Anyone able to reach the charity host can POST fabricated `charity_transaction`
  round-up rows (arbitrary org/device/branch/amount/status). The route comment claims "amounts still originate
  from the payment processor receipt" but nothing enforces that on the endpoint. This is a cross-service data /
  financial-reporting integrity gap. NB: charity-laravel-api is the charity ecosystem repo (overlaps the charity
  agent's charter); flagged here because the pos_api forwarding posture is in scope. Handler-side validation in
  `store_pos_roundup` not fully traced — see verified flags.

## 13. Ad-billing RE-AUDIT findings (2026-08-06) — status update
- The prior re-audit's ad-billing defects appear FIXED in pos_api `f93e46d`:
  - played_at forgery: `SliderDisplayHandler.php:resolvePlayedAt()` (`~:88-125`) now UTC-normalises and CLAMPS
    to server time when the reported time is >10min from receipt, so a device can no longer backdate billable
    screen-days.
  - slider gate drift: `:150-162` now gates on `MarketingSlider::liveAt($playedAt)->servedToDevice($device)`
    (status+window+targeting from the SAME shared scopes the config slice uses), plus a per-device daily play cap
    (`:175-186`) and write-once billing fields re-derived from the resolved row (`:190-205`).
- The cross-advertiser stored-XSS (marketing-api `ContentAssetController`) from that re-audit is in the
  marketing/ads surface (charity ecosystem repo) — NOT re-verified in this pass; cross-reference only.

---

## Positive verifications (no defect)
- Broadcast channel auth scopes a device to its own company/branch/device
  (`routes/channels.php` + `Broadcasting/CompanyChannel.php:20-22`, `BranchChannel.php:18-20`, DeviceChannel).
- Per-device idempotency: composite unique `(device_id, client_event_id)` (hardening `0067142`), tested.
- Activation/pairing tokens SHA-256, single-use, expiry+revoke enforced.
- Merchant↔merchant isolation held under both the 2026-07-11 and 2026-08-06 adversarial re-audits (34 agents);
  no cross-tenant read/write found in this pass either.

## Not fully verified (verified:false in summary)
- Charity `store_pos_roundup` handler-side ownership validation (§12) — route auth-absence verified, handler
  body not traced (charity repo / other charter).
- Whether `DefaultAdminUserSeeder` runs in the prod deploy pipeline (§10) — code path verified, deploy invocation not.
- Real-world exploitability of the C2 admin-API gap (§1a) depends on prod cookie/domain isolation, verified sound
  in the tenancy memory but not re-checked on the VPS in this pass.
