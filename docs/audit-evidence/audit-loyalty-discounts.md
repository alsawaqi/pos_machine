# Audit: Loyalty, Discounts, Offers (agent: audit-loyalty-discounts)

Date: 2026-08-07. Read-only audit across pos_api, pos_merchant, pos_admin (migrations), pos_machine, pos_handheld.
All claims below are VERIFIED in code unless explicitly marked INFERRED / Cannot-Verify.

---

## 1. LOYALTY

### 1.1 Rules model (schema)

- `pos_admin/src/database/migrations/2026_06_08_010000_create_pos_loyalty_rules_table.php` — `pos_loyalty_rules`: company_id, name, `type` (visit_based | spend_based), `config_json`, `validity_start`/`validity_end`, `status` (active|paused), soft deletes, index (company_id,status). Multi-rule: any number of concurrently active rules per company.
- Companion tables: `2026_06_08_010100_create_pos_loyalty_accounts_table.php` (per customer × rule, denormalised `point_balance` + `stamp_count`), `2026_06_08_010200_create_pos_loyalty_transactions_table.php` (append-only ledger with `balance_after_points/stamps` snapshots). Legacy single-config model dropped by `2026_06_08_010300_drop_legacy_loyalty_config_and_point_ledger.php`.
- Migration doc-comment (lines 17–27) *documents* a §5.8 restrictions surface inside config_json: `eligible_product_ids, eligible_category_ids, branch_scope_json, dayofweek_mask, time_start, time_end, max_redemption_per_order, customer_tag` and spend_based `expiry_days`. **VERIFIED ABSENT in code**: `grep expiry_days|eligible_product_ids|eligible_category_ids|max_redemption_per_order|customer_tag` over `pos_merchant/src/app` and `pos_api/src/app` returns zero hits. None of these restrictions is enforced anywhere (server or device).

### 1.2 EvaluateLoyalty pure function — server twins

- Original: `pos_merchant/src/app/Actions/Pos/Loyalty/EvaluateLoyalty.php:46` (static-only, no DB/clock). Port: `pos_api/src/app/Actions/Pos/Loyalty/EvaluateLoyalty.php:30`.
- Diff of the two class bodies shows they are **logic-identical**; only differences are enum-vs-string type match (pos_api matches `'visit_based'|'spend_based'` strings with a default no-op arm, pos_api/src/app/Actions/Pos/Loyalty/EvaluateLoyalty.php:44–48) and comments. Money math in int baisas (`toBaisas` at :116).
- Semantics (both): visit_based → 1 stamp per order with `subtotal >= min_order_value` (evaluateVisit :55); spend_based → `points = intdiv(subtotalBaisas * points_per_omr, 1000)` (evaluateSpend :87); eligibleRedemptions computed from post-earn balance with `threshold = max(min_redemption_points, redemption_points)`.

### 1.3 Is there a matching Dart port on device? **NO full port — split-brain by design**

- **Earn is never computed on device.** pos_machine names the earn rule ids on the pay event and the server accrues: `pos_machine/lib/screens/staff_pos_screen.dart:423–430` (`loyaltyRuleIds = customerId != null && paymentMethod != 'Gift' ? controller.effectiveEarnRuleIds : []`), `pos_machine/lib/state/pos_controller.dart:431–448` (`activeEarnRuleIds` = all active rules; P-F3 per-order picker override in `selectedEarnRuleIds`/`effectiveEarnRuleIds`). Handheld identical policy: `pos_handheld/lib/models/catalog.dart:968` (`earnRuleIds` = all rules — its parse already dropped non-active) + `pos_handheld/lib/main.dart:1148–1152`.
- **Redemption eligibility IS re-implemented on device** (partial re-implementation, not a shared library):
  - pos_machine: `lib/screens/staff_pos_screen.dart:2986–3000` (`_redeemable`: spend rule, `pts >= max(minRedemptionPoints, redemptionPoints)`), `:3004–3019` (`_redeemableStamp`), `:3021–3038` (`_stampRewardValue`: percent_off → % of rawSubtotal capped 100; free_product → catalog price fallback reward_value), `:3107–3150` (`_openRedeemDialog`: blocks capped by balance AND by subtotal/redemption_value).
  - pos_handheld: `lib/main.dart:2050–2087` (`_redeemableOptions` — same thresholds: `minPts = max(min_redemption_points, redemption_points)`, `maxBlocks = min(pts/rp, subtotal/rv)`), `:2089+` (`_stampRewardValue` same shape).
  - Device redemption math matches the server evaluator's `eligibleRedemptions` thresholds (compared by hand; consistent), but there is no single shared Dart module — machine (in-screen), handheld (in main.dart), server (PHP) are three copies. The blueprint's "shared via a small ported library" is only true for PHP↔PHP.
- Device `LoyaltyRule` model: `pos_machine/lib/models/pos_models.dart:1114–1156` (typed getters over config; visit_based reward_type percent_off/free_product), handheld `lib/models/catalog.dart:248–307` (`fromMap` filters `status != 'active'` and unknown types at parse; handheld does FULL config fetch each staff login — `pos_handheld/lib/services/config_repository.dart:12–16` — so stale-paused-rule concerns don't apply).

### 1.4 Earn at pay (server-authoritative)

- `pos_api/src/app/Actions/Device/Sync/Handlers/PayOrderHandler.php:82–83` reads `loyalty_rule_ids` (v2 #3 array, legacy single `loyalty_rule_id` accepted, de-duped positive ints — `earnRuleIds()` :248–265); `:205–220` loops `ApplyLoyaltyEarnAction::apply` per rule inside the pay DB transaction. Fully-gifted orders earn nothing: `if ($giftBaisas >= $grandBaisas && $grandBaisas > 0) $loyaltyRuleIds = []` (:211–213).
- `ApplyLoyaltyEarnAction` (`pos_api/src/app/Actions/Device/Sync/ApplyLoyaltyEarnAction.php`): best-effort (returns null on no customer / unknown / cross-tenant / non-active rule, :46); `firstOrCreate` account (:50); **earn base = post-discount goods subtotal**: `eligibleBaisas = max(0, subtotal − discount_total)` (:56). Note: comp_total is NOT subtracted — a comped (written-off) portion still earns points (policy observation, see finding F7).
- Ledger write: `pos_api/src/app/Actions/Pos/Loyalty/WriteLoyaltyTransactionAction.php` — `lockForUpdate` on the account (:44), balance-negative guards (:49, :52), append txn with balance_after snapshots + denormalised account update in one DB transaction. pos_merchant has the same writer for portal writes (`pos_merchant/src/app/Actions/Pos/Loyalty/WriteLoyaltyTransactionAction.php`, plus portal audit log).
- Loyalty earn deliberately still fires when a tender is `pending_reconciliation` (commissions deferred, loyalty not): PayOrderHandler.php:190–206 comment + `pos_admin/src/app/Actions/Admin/Reconciliation/ReconcileDeferredEffectsAction.php:27`.

### 1.5 Redemption mechanics — DISCOUNT, not tender

- On both devices a redemption's OMR value rides the single order-level **discount slot**, and the points/stamps spent ride the pay event as `loyalty_redeem {rule_id, points, stamps}`:
  - pos_machine: `lib/state/pos_controller.dart:1742–1786` (`applyLoyaltyRedemption` sets `discount = DiscountConfiguration(fixedAmount, valueOmr)`; `applyDiscount` at :1751–1762 conversely clears a pending redeem — the slot is exclusive: **an order-level rule/manual discount and a loyalty redemption cannot coexist**), wire at `lib/services/order_sync_payload.dart:318–326`.
  - pos_handheld: `lib/main.dart:369–373, 486–487, 2028+` (same slot-sharing: `_loyaltyRedeem` value rides `_discount`).
- Server: `pos_api/src/app/Actions/Device/Sync/ApplyLoyaltyRedeemAction.php` — STRICT (unlike earn): missing customer (:43), unknown/cross-tenant rule (:50), no account (:58) all throw → the whole pay event fails; negative deltas guarded non-negative by the writer. PayOrderHandler.php:222–232 invokes it.
- `Payment::METHODS` (`pos_api/src/app/Models/Payment.php:44`) includes a `'loyalty'` tender method and `pos_machine/lib/services/order_sync_payload.dart:50` maps a label containing "loyalty" to it, but no current device flow tenders loyalty — redemption is a discount. The method value looks vestigial.

### 1.6 Min thresholds

- Server evaluator: `threshold = max(min_redemption_points, redemption_points)` (pos_api EvaluateLoyalty.php:96–99). Devices apply the same gate (machine staff_pos_screen.dart:2993–2995; handheld main.dart:2060–2061). visit_based: `min_order_value` earn gate evaluated server-side at earn (EvaluateLoyalty evaluateVisit).
- **Server does NOT validate redemption against rule config** — ApplyLoyaltyRedeemAction only checks the account balance covers the spend; it never checks min_redemption_points, block alignment (points % redemption_points), or that the discount OMR the device granted matches `redemption_value × blocks`. The redemption's monetary value was already folded into discount_total at order.create and is trusted (§9.1.6 snapshot-authoritative). See finding F6.

### 1.7 Expiry — NOT implemented

- `expiry_days` appears only in the migration doc-comment (pos_loyalty_rules migration :23). No code in pos_merchant, pos_api, or either device references it; no scheduled job expires points/stamps. Points and stamps live forever. Rule-level `validity_start/validity_end` columns exist, ship to devices (BuildDeviceConfigAction mapLoyaltyRule :1248–1263), but are **enforced nowhere**: server earn checks only `status === 'active'` (ApplyLoyaltyEarnAction.php:46); pos_machine drops the window when building its model (`lib/services/config_mapper.dart:949–957` — no validity fields; `lib/models/pos_models.dart:1114` has none); handheld `LoyaltyRule.fromMap` (catalog.dart:291–307) likewise ignores it. A rule past validity_end keeps earning/redeeming until manually paused. Finding F4.

### 1.8 Manual adjustment

- `pos_merchant/src/app/Actions/Pos/Loyalty/AdjustLoyaltyAction.php` — portal adjust (points+stamps deltas) via the atomic writer, required reason, actor recorded; route `POST customers/{customer}/loyalty/adjust` (`pos_merchant/src/routes/web.php:724–725`), gated `loyalty.manage` (LoyaltyController::ensure, controller :322–327; PermissionCatalog key 'loyalty' at `pos_merchant/src/app/Support/PermissionCatalog.php:218–238`). Rule CRUD + pause/resume + delete: routes web.php:709–720, Actions Create/Update/Pause/Resume/DeleteLoyaltyRuleAction with audit-log writes (CreateLoyaltyRuleAction.php:70–77).
- Separate customer WALLET (store credit, not loyalty): TopUpWalletAction / AdjustWalletBalanceAction / WriteWalletLedgerEntryAction; routes web.php:728–734. Devices receive `wallet_balance_baisas` in the customer slice (BuildDeviceConfigAction mapCustomer :1267+) but no device tender path spends it (out of scope here; noted for the payments agent).

### 1.9 Reversal on void

- `pos_api/src/app/Actions/Device/Sync/Handlers/VoidOrderHandler.php:131` — paid orders only (`$wasPaid`); `reverseLoyalty` (:155–199): for every earn/redeem txn on the order, append an inverse `adjust` (type=ADJUST, reason 'reversed from void'); reversing a redeem restores points/stamps; reversing an earn claws back but is **clamped to the balance still on hand** (:174–180) so already-spent points never force the ledger negative. Row-locked + status re-check idempotency (:100–110).

### 1.10 Double-earn / double-redeem protection under offline replay

- Ingest layer: exactly-once on `(device_id, client_event_id)` UNIQUE — `pos_api/src/app/Actions/Device/IngestSyncEventsAction.php:17,28,53–112`; duplicate pushes ACK as duplicates without re-dispatch; FAILED events are retried on re-push (:68–75).
- In-handler race guard: PayOrderHandler re-reads + `lockForUpdate` + terminal-status re-check inside the txn (:85–103) — two pays with *different* client_event_ids serialise; loser throws 'order already paid'. Same pattern in VoidOrderHandler.
- Contract tests: `pos_api/src/tests/Feature/DeviceSyncLoyaltyTest.php` — `test_replaying_pay_does_not_earn_twice` (:223), `test_redeeming_more_than_the_balance_fails_the_pay` (:294), `test_redemption_decrements_the_balance` (:255), `test_earn_and_redeem_can_both_happen_in_one_pay` (:276), `test_multiple_earn_rules_all_accrue_in_one_pay` (:327), cross-tenant rule ignored (:208), legacy single id (:356). 13 tests total.
- **Residual gap (acknowledged in code)**: offline redeem is optimistic against the cached balance (config bundle snapshot, BuildDeviceConfigAction :317–325 "Volatile — refreshed on each full sync"). Two devices redeeming the same customer's points offline → second order's pay event fails server-side STRICTLY and **deterministically re-fails on every retry**: the customer already got the discount on-device, the order is stranded unpaid/uningested server-side (no inventory consume, no commission, no earn). ApplyLoyaltyRedeemAction doc-comment (:20–28) explicitly defers "reconciling an optimistic over-redeem". Finding F5.

### 1.11 Per-branch / per-product loyalty restrictions & spec 6.6 (stamps on specific products)

- **Not implemented anywhere** (see 1.1 grep). Loyalty rules are company-wide: no branch scoping, no product/category scoping of earn. The offline stamp/points earn base is always the whole post-discount subtotal.
- Spec status: `spec.txt:419–421` (Part 6.6) says the item-scoped-stamps model "the existing model supports" structurally, and `spec.txt:465` (Part 7.4) explicitly lists "Loyalty Stamps scoped to products, per Part 6.6" as a **Deferred feature**. So its absence is spec-consistent, not a build break.

### 1.12 Loyalty reporting

- Branch report aggregates points/stamps earned/redeemed: `pos_api/src/app/Actions/Device/BuildBranchReportAction.php:108–130`; device UI `pos_machine/lib/screens/branch_reports_screen.dart:483–488`, model `lib/models/branch_report.dart:73–105`. Merchant: CustomerReportAction / LoyaltyController transactions listing (web.php:726–727).

---

## 2. DISCOUNTS

### 2.1 Rule schema

- `pos_admin/src/database/migrations/2026_06_05_010000_create_pos_discounts_table.php` — `pos_discounts`: scope (product|category|order), amount_type (percent|fixed), amount decimal(12,3), validity window, `dayofweek_mask` (Sun=1..Sat=64, NULL=every day), time_start/time_end HH:MM:SS with midnight wrap, `branch_scope_json` (NULL=all), `stackable` bool, `requires_manager_approval` bool, status (active|paused|expired), soft deletes. Targets: `2026_06_05_010100_create_pos_discount_targets_table.php` (target_type product|category + target_id). `2026_07_09_010000_add_auto_apply_to_pos_discounts.php` adds `auto_apply` (P-F4).
- 'expired' exists only as an enum value (`pos_merchant/src/app/Enums/DiscountStatus.php`); nothing in pos_merchant/pos_api ever sets it (grep). Validity windows are the real expiry mechanism and ARE evaluated for discounts (unlike loyalty) — on-device.

### 2.2 Evaluators — the blueprint's "shared evaluator" requirement is NOT met for discounts

- Merchant pure evaluator: `pos_merchant/src/app/Actions/Pos/Discounts/EvaluateDiscounts.php:88` — full stacking semantics: sort non-stackable first then id asc; a non-stackable rule that fired on a line blocks further rules on that line; stacked percents compound against the current line subtotal; fixed capped at remaining; order-scope rules run after line discounts, capped so total ≤ subtotal; int-baisas math. **Only callers are its own tests** (`pos_merchant/src/tests/Feature/Pos/EvaluateDiscountsTest.php`, 20 invocations); zero production callers in pos_merchant, and pos_api has no copy at all.
- Device evaluator (what actually runs at sale time) is DIFFERENT logic: `pos_machine/lib/state/pos_controller.dart:1072–1126` — per line, **pick the single best (highest-amount) applicable product/category rule** (`lineDiscountFor` :1089–1122); one order-level discount slot; total = orderLevel + Σ line picks + offers, clamped to subtotal (:1083–1084). The `stackable` flag ships in config (BuildDeviceConfigAction mapDiscount :1114+, stored in Drift `config_mapper.dart:517`) but is **read by no device code** (grep `stackable` over pos_machine/lib + pos_handheld/lib: model/DB definitions only). Compounding/stacking of multiple line rules and multiple order rules is impossible on device.
- Server does not re-run any discount evaluation at ingest (CreateOrderHandler doc :36–38 "validates the invariant but does NOT re-run discount evaluation").
- Consequence: the tested stacking semantics are dead code; the shipping semantics are "best single rule per line + one order slot". Blueprint §13 Phase 6 exit ("both evaluators shared between server and Flutter device… identical results") is unfulfilled. Finding F2.

### 2.3 Applicability (happy-hour / schedule windows offline)

- 6-axis predicate implemented on-device and evaluated offline against the local clock: `pos_machine/lib/models/pos_models.dart:866–899` (`MerchantDiscount.appliesAt` — active, validity window, weekday mask with Dart-Mon=1 → server-Sun=0 conversion `now.weekday % 7` :879, time window with midnight wrap :883–894, branch scope :896–897). Mirrors `pos_merchant/src/app/Models/Discount.php:215` (`appliesAt`). Re-checked when the picker opens and when the payment page opens (`maybeAutoApplyOrderDiscount` doc :1204–1207). Works fully offline; trusts the device clock (inherent).

### 2.4 Preset vs custom + permission gates

- Preset rules: order-scope rules appear in the discount picker (`staff_pos_screen.dart:2880–2946`); rules with `requires_manager_approval` demand biometric manager auth on device (`_applyMerchantDiscount` :3158–3174 → `ManagerAuthorizationService.authenticateManagerApproval`, `lib/services/manager_authorization_service.dart:49–61`); auto-apply order rules never self-apply if they require approval (`pos_controller.dart:1220`). Handheld parity: `pos_handheld/lib/main.dart:1716–1736` (rule "manager-gated when the rule requires it").
- Custom/manual discount: free-entry percent (≤100) or fixed amount, **reason required** (P-F4) — `_DiscountDialog`, `staff_pos_screen.dart:13045–13100`; reason rides the wire and is capped at 160 chars server-side rather than rejected (CreateOrderHandler :414–418). **No manager gate and no cap (beyond clamp-to-subtotal) on manual discounts** — any signed-in cashier can apply up to 100% off with any reason text. Spec Part 7.1 pairs permissions+audit as go-live blockers; audit exists (order_discounts rows + by-staff report), the permission half doesn't on devices. Finding F8.
- Merchant portal CRUD gates: `discounts.view` / `discounts.manage` (DiscountsController::ensure :173–176; PermissionCatalog :239–253; routes web.php:736–755). Offers reuse the same keys (routes comment web.php:757–759 "Same permission keys as discounts"; OffersController :55–128 uses DiscountsView/DiscountsManage).

### 2.5 Who computes the amount; does the server validate?

- **The device computes all discount money.** Server order.create ingest is snapshot-authoritative: `pos_api/src/app/Actions/Device/Sync/Handlers/CreateOrderHandler.php` — validation rules :574–596 (`discount_total_baisas` int ≥ 0), money invariant `assertMoneyInvariant` :627–638 (`subtotal − discount − comp + tax == grand ± 1 baisa`), and `writeDiscounts` :382–445 records what the device applied. Tenant checks: a `discount_id` that doesn't resolve to a company rule is **soft-dropped to null** (payload name/type stand, :419–435); an `offer_id` that doesn't resolve tenant-wide **hard-fails the event** (:400–410, withTrashed for offline-queued orders). No magnitude/schedule/target validation of any discount row — a modified device could claim any discount (trust model per §9.1.6; INFERRED risk, not a code bug).
- Payment side cross-check: Σ tendered == grand_total ± 1 baisa (PayOrderHandler :169–172), so discounts directly reduce collected money.

### 2.6 Snapshotting on order lines

- `pos_admin/src/database/migrations/2026_06_10_010000_create_pos_order_discounts_table.php` — `pos_order_discounts`: order_id, nullable order_item_id (line vs order level), nullable discount_id (manual = null), **name_snapshot + amount_type_snapshot** frozen at sale, amount OMR, applied_at, company/branch denormalised; `2026_07_09_010100` adds `reason`; `2026_07_13_010100` adds `offer_id`. Written at order.create (CreateOrderHandler writeDiscounts); replays purge + rewrite children (`purgeOrderChildren` :222). Line linkage via `line_index → order_item id` map (:387, :421).
- Order header also snapshots the aggregate `discount_total`. Per-line: `pos_order_items.line_discount` (CreateOrderHandler :150).
- Contract tests: `pos_api/src/tests/Feature/DeviceOrderDiscountTest.php` (rule+manual rows :80, 160-char reason cap :123, unresolved id dropped :139, replay no duplication :176).
- Reporting: `pos_merchant/src/app/Actions/Pos/Reports/DiscountReportAction.php` (§5.11.7 — headline, by branch, by staff from pos_orders; by RULE from pos_order_discounts; discount % of gross watchdog) + DiscountedCompedProductsReportAction.

### 2.7 Device wire format

- pos_machine `lib/services/order_sync_payload.dart:130–217, 265–271`: order-level entry (with discount_id/amount_type/reason), auto line entries (with line_index + discount_id), offer entries (offer_id), all folded into `discount_total_baisas`; grand total derived to satisfy the server invariant. Handheld: `lib/services/order_sync_service.dart:319–364` — same, with explicit clamp policy "offers keep their full value and the manual slice absorbs" when combined > subtotal.
- P-G7: delivery-provider orders take no discounts, offers, or loyalty on either device (pos_controller.dart:1094, 1134, 1753, 1774; handheld main.dart:1719–1721, 1943).

---

## 3. OFFERS / PROMOS BEYOND DISCOUNTS — YES, five types (P-F9). No coupon codes / gift cards.

### 3.1 Schema + merchant CRUD

- `pos_admin/src/database/migrations/2026_07_13_010000_create_pos_offers_table.php` — `pos_offers`: type ∈ {bogo, bundle, multi_buy, cheapest_free, spend_get}, strict per-type `config` JSON (money int baisas), auto_apply (bundle forced false — always cashier-picked), same applicability axes as discounts (validity/dow mask/time window/branch scope/status), `max_per_order`, soft deletes.
- Strict config contract + tenant ownership of referenced product/category ids: `pos_merchant/src/app/Support/OfferConfig.php` (errors() + normalize() emit exactly the canonical keys the device engine expects). CRUD + pause/resume: routes web.php:757–775, Actions Update/Pause/DeleteOfferAction, gated under the discounts permission keys.
- Coupons, promo codes, gift cards: **do not exist** (gift cards listed as deferred Phase 7, spec.txt:469; a per-item "gift" is a comp write-off, not a promo — CreateOrderHandler writeComps :445+).

### 3.2 Device offer engines — pure, tested, but two diverging copies

- pos_machine `lib/services/offer_engine.dart` (433 lines): pure `evaluateOffers(cart, lineNet, offers, now, branchId)`; cart expands to units (gifted + bundle-owned lines excluded :113–123); offers evaluate in id order; per-offer `max_per_order` cap. bogo (:151–198, most-expensive units pay, cheapest get discounted, industry rule), multi_buy (:200–238), cheapest_free (:240–271), spend_get (:273–330, percent/fixed order-level or cheapest matching unit free), bundle (:332–402, cashier-picked instances re-validated for full group composition each evaluation; broken bundle = no discount). Baisas-exact largest-remainder allocation `_allocateExactly` (:406–432). Applied via `pos_controller.dart:1131–1159` (auto types + bundles; delivery-gated), frozen at snapshot :1476–1481.
- pos_handheld `lib/services/offer_engine.dart`: "ported VERBATIM" (header) against an `OfferLine` view. Comment-stripped diff shows algorithms identical **except one deliberate divergence**: in `_applyMultiBuy`, when a set's value is already at/below the offer price (discount ≤ 0), pos_machine marks the set consumed **before** breaking (offer_engine.dart:216–228 — consume loop precedes the `discount > 0` check), starving later offers of those units; the handheld breaks **before** consuming (`pos_handheld/lib/services/offer_engine.dart:229–238`) and its comment names the machine behaviour "a real overcharge". Same cart + same offers can price differently on the two POS surfaces, with pos_machine the wrong one. Finding F3.
- Both repos carry engine unit tests: `pos_machine/test/offer_engine_test.dart`, `pos_handheld/test/offer_engine_test.dart` (plus machine `discount_auto_apply_test.dart`, `line_discount_test.dart`, `merchant_discount_test.dart`, `loyalty_earn_picker_test.dart`, `loyalty_rule_test.dart`). Cannot-Verify: whether the two engine test suites cover the multi_buy consume-ordering edge (not read line-by-line).
- Offer applicability offline mirrors discounts: `pos_models.dart:967–988` (`Offer.appliesAt`); bundle stock-gating on finite-shelf picks `pos_controller.dart:1174–1189`.

### 3.3 Server-side offers handling

- Config bundle: offers ride verbatim with delta + soft-delete purge lists (`pos_api/src/app/Actions/Device/BuildDeviceConfigAction.php:242–249, 421, 655; mapOffer :1161–1181`). Order ingest: offer rows on `pos_order_discounts.offer_id`, hard tenant validation, name snapshot from the offer (CreateOrderHandler :372–435). Contract tests `pos_api/src/tests/Feature/DeviceOfferTest.php` (canonical shape :108, delta+deletes :157–184, snapshot :239, cross-tenant fail :261, unknown fail :280, soft-deleted resolves :294).
- The server has **no offers evaluator** at all (by design — "The DEVICE evaluates them; config rides verbatim", BuildDeviceConfigAction :242–245). No server-side check that a claimed offer application matches its config.

---

## 4. Cross-cutting verification notes

- Device config bundle slices for this charter: discounts + targets (:233–241), offers (:242–249), loyalty_rules (:307–316), per-customer loyalty balances (:317–325) with deleted.* purge lists (:654–658). Machine persists to Drift (`config_mapper.dart:497–590`) and rebuilds models (:926–957); machine keeps paused rules as rows with status (isActive gate), handheld drops them at parse (full-fetch model, safe).
- Live customer lookup carries fresh balances beyond the cache: `pos_api/src/app/Http/Controllers/Api/V1/Device/DeviceCustomersController.php:225–230`; machine falls back to cached balances offline (staff_pos_screen.dart:2472, 2428).
- Gift interplay: pure-gift orders earn no loyalty — machine gates client-side (staff_pos_screen.dart:428), server independently (PayOrderHandler :211–213), handheld both (main.dart via payment_screen.dart:759–767).

## 5. FINDINGS (severity-ordered)

- **F1 (P2, verified)** Loyalty rule §5.8 restrictions + `expiry_days` documented in the schema migration are implemented nowhere: no expiry, no branch/product/category scoping, no per-order redemption cap, on server or devices. (pos_admin migration 2026_06_08_010000 :17–27 vs zero grep hits in pos_merchant/pos_api app code.)
- **F2 (P2, verified)** Discount stacking semantics split-brain: pos_merchant `EvaluateDiscounts` (stackable-first compounding, tested) has no production caller; devices ship different "best single rule per line + one order slot" logic and ignore the `stackable` flag entirely; server never re-evaluates. Blueprint "identical offline/online evaluators" unmet. (EvaluateDiscounts.php:88 + tests only; pos_controller.dart:1072–1126; no `stackable` reads in either device.)
- **F3 (P2, verified)** Offer engines diverge on multi_buy: pos_machine consumes an at/under-price set before breaking (offer_engine.dart:216–228), starving later offers → overcharge; pos_handheld deliberately fixed it (its offer_engine.dart:229–238 comment calls the machine behaviour "a real overcharge"). Same cart prices differently per device; the fix was never back-ported.
- **F4 (P2, verified)** Loyalty rule `validity_start/validity_end` stored + shipped but enforced nowhere: server earn checks only status (ApplyLoyaltyEarnAction.php:46); both devices drop the fields from their models (config_mapper.dart:949–957; catalog.dart:291–307). Expired-window rules keep earning/redeeming until manually paused.
- **F5 (P2, verified)** Optimistic offline redeem has no reconciliation path: over-redeem (stale cached balance / two devices) strictly fails the pay event server-side and deterministically re-fails on every retry (ApplyLoyaltyRedeemAction.php:20–28 acknowledges; IngestSyncEventsAction retry loop :68–75) — order stranded unpaid server-side (no inventory/commission/earn) while paid on-device.
- **F6 (P3, verified)** Server does not validate redemption economics: no min-threshold, block-alignment, or value-vs-config check on `loyalty_redeem`; only balance coverage. Honest devices enforce it; the server trusts the discount value already on the order. (ApplyLoyaltyRedeemAction.php:37–75.)
- **F7 (P3, verified)** Loyalty earn base subtracts discounts but not comps: `eligible = subtotal − discount_total` (ApplyLoyaltyEarnAction.php:56); a heavily comped (written-off) order still earns full points on the comped portion; only 100%-gift orders are suppressed (PayOrderHandler :211–213).
- **F8 (P3, verified)** No permission gate on ad-hoc manual discounts at the till: any cashier can apply up to 100% off with only a free-text reason; manager auth applies only to rules flagged requires_manager_approval (staff_pos_screen.dart:3158–3209, 13045+; handheld main.dart:1716–1736). Spec 7.1 treats discount permissions + audit as paired go-live controls; only the audit half exists.
- **F9 (P3, verified)** `Payment::METHODS` includes an unused `'loyalty'` tender (Payment.php:44; mapPaymentMethod order_sync_payload.dart:50) while actual redemption is a discount — dead contract surface that could mislead future integrations.

## 6. Explicitly answered charter questions

| Question | Answer |
|---|---|
| EvaluateLoyalty pure fn on server | Yes, twin PHP copies (pos_merchant original, pos_api port), logic-identical (diff-verified) |
| Matching Dart port, identical? | No port. Earn: server-only (device names rule ids). Redemption eligibility re-implemented twice in Dart (machine + handheld), thresholds consistent by inspection, no shared module |
| Earn at pay | Yes, inside pay txn, post-discount subtotal, multi-rule (v2 #3), gift-suppressed |
| Redemption: tender or discount | Discount (order-level slot) + `loyalty_redeem` ledger debit on pay; strict server-side |
| Min thresholds | Enforced device-side + in evaluator; NOT re-validated server-side on redeem |
| Expiry | Not implemented (doc-comment only); rule validity windows also unenforced |
| Manual adjustment | Yes, merchant portal, atomic writer, reason+actor, audit-logged, loyalty.manage |
| Reversal on void | Yes, inverse ADJUST per txn, clamped to remaining balance, paid orders only |
| Double-earn/redeem under replay | (device_id, client_event_id) exactly-once + row locks + tests; residual optimistic-over-redeem gap (F5) |
| Per-branch/product loyalty restrictions | Absent (F1); spec 6.6 product-scoped stamps explicitly deferred (spec.txt:465) |
| Discount rule schema/evaluator/stacking | Schema full-featured; shipping evaluator is device-side best-single-rule; stackable flag dead (F2) |
| Preset vs custom + permission gates | Preset rules picker + manager-gated flag; custom free-entry with required reason, no permission gate (F8); portal CRUD gated discounts.view/manage |
| Who computes; server validation | Device computes; server validates money invariant + tenant refs only (snapshot-authoritative) |
| Discount snapshotting | pos_order_discounts with name/amount_type snapshots, line linkage, reason, offer_id; replay-safe |
| Happy-hour offline | Yes — full 6-axis predicate incl. midnight wrap evaluated on-device offline (machine+handheld+offers) |
| Offers beyond discounts | Yes: bogo, bundle, multi_buy, cheapest_free, spend_get; pure device engines; no coupons/gift cards |
| Loyalty stamps scoped to products | Does not exist; deferred per spec Part 7.4 |
