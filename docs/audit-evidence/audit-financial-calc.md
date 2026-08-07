# Audit: Financial Calculation Duplication & Consistency (audit-financial-calc)

Date: 2026-08-07. READ-ONLY audit across pos_machine (Dart), pos_handheld (Dart, separate repo),
pos_api (PHP), pos_merchant (PHP/SQL), pos_admin (PHP/SQL). All claims below are VERIFIED against
source unless explicitly tagged INFERRED / Cannot-Verify.

---

## 0. Answer to the key question

**There is NO single authoritative pricing model.** Pricing is *snapshot-authoritative on the
device*: pos_api explicitly **stores device-supplied totals as-is and does NOT recompute** them.

- `pos_api/src/app/Actions/Device/Sync/Handlers/CreateOrderHandler.php:36-42` (doc: "the money the
  device computed ... is trusted and frozen as-is — this handler validates the invariant but does
  NOT re-run discount evaluation") and `:108-113` (subtotal/discount/comp/tax/grand written straight
  from `*_baisas` payload via `Money::toOmr`).
- The ONLY money checks the server performs:
  1. Additive invariant `subtotal − discount − comp + tax == grand` with **±1 baisa tolerance** —
     `CreateOrderHandler.php:627-638` (`assertMoneyInvariant`).
  2. Comp rows must sum **exactly** to `comp_total_baisas` — `CreateOrderHandler.php:531-533`;
     per-reason cap `max_amount` enforced `:495-501`; gift/reason exclusivity `:479-484`.
  3. Σ(tender `amount_baisas`) == stored grand ±1 baisa — `PayOrderHandler.php:168-171`.
- NOT validated anywhere server-side (verified absent in CreateOrderHandler/PayOrderHandler):
  - Σ(`line_total_baisas`) vs `subtotal_baisas`;
  - `line_total_baisas` vs `qty × unit_price_baisas`;
  - Σ(`discounts[].amount_baisas`) vs `discount_total_baisas` (comps are checked, discounts are not
    — inconsistent strictness);
  - tax vs the company's configured `pos_taxes` rates;
  - discount amounts vs the referenced rule's definition (rule is only used for name/type snapshot,
    `CreateOrderHandler.php:390-437`).

Merchant/admin reports **read the stored totals** (they do not recompute from lines), so whatever
the device sent is what every report shows (see §7).

---

## 1. Rounding & unit conventions (calculation × location)

| Concern | pos_machine | pos_handheld | pos_api | DB |
|---|---|---|---|---|
| OMR rounding | `double.parse(v.toStringAsFixed(3))` — `lib/models/pos_models.dart:9-10` (`_roundStoredMoney`), `lib/state/pos_controller.dart:3950` (`_roundMoney`), `lib/models/pos_models.dart:147` (`_roundTax`) | identical: `lib/main.dart:575` (`_round3`), `lib/models/catalog.dart:644` | n/a (integer baisas) | decimal(12,3) OMR |
| OMR→baisas | `(omr * 1000).round()` — `lib/services/order_sync_payload.dart:24` | identical — `lib/services/order_sync_service.dart:14` | `Money::toBaisas = (int) round(omr*1000)` — `pos_api/src/app/Support/Money.php:24-27` | — |
| baisas→OMR | `/ 1000.0` at boundaries (e.g. `pos_models.dart:2143`, `1203`) | `/ 1000.0` (`order_history_screen.dart:621-625`) | `Money::toOmr = number_format(b/1000, 3)` — `Money.php:17-21` | — |
| Local money cache | integer baisas in Drift (`lib/data/db/tables.dart:54,64,141,181,293,388`) | int baisas in wire structs | — | — |

All three rounding helpers are the same "3dp via toStringAsFixed" function; devices do float OMR
math internally and convert once at the wire. VERIFIED consistent.

---

## 2. Subtotal

| Location | Formula | Evidence |
|---|---|---|
| pos_machine live cart | `rawSubtotal = Σ item.lineTotal` (unrounded float); `lineTotal = (product.price + Σ modifier.price) × qty` | `pos_machine/lib/state/pos_controller.dart:1070`; `lib/models/pos_models.dart:651-656` |
| pos_machine held draft | same | `lib/models/pos_models.dart:1550` |
| pos_handheld | `_rawSubtotal = Σ l.lineTotal`; `_subtotal = _rawSubtotal` | `pos_handheld/lib/main.dart:579-580` |
| machine wire | `subtotal_baisas = omrToBaisas(rawSubtotal)` — ONE rounding of the float sum | `lib/services/order_sync_payload.dart:264` |
| handheld wire | `subtotal_baisas = Σ (omrToBaisas(unitPrice) × qty)` — per-line integer sum | `lib/services/order_sync_service.dart:263-267` |
| pos_api | stored as sent | `CreateOrderHandler.php:108` |
| merchant reports | `SUM(subtotal)` = "gross_sales" | `pos_merchant/src/app/Actions/Pos/Reports/SalesReportAction.php:97` |
| admin reports | `SUM(subtotal)` | `pos_admin/src/app/Actions/Admin/Reports/AdminSalesReportAction.php:48` |

**Semantics: `subtotal` on the wire/DB is the RAW pre-discount subtotal** on both devices
(machine sends `snapshot.rawSubtotal`, not the post-discount `subtotal` getter). Reports treat
stored `subtotal` as gross sales — consistent.

Rounding-order difference (machine rounds the OMR sum once; handheld sums per-line baisas) is
FP-epsilon only because prices are 3dp and qty integer — no material divergence. VERIFIED both.

---

## 3. Discounts

### 3.1 pos_machine
- Order-level: fixed = value; percent = `rawSubtotal × value/100` — `pos_controller.dart:1072-1079`.
- Auto line discounts: **best single** product/category-scope rule per line by max amount
  (`lineDiscountFor`, `pos_controller.dart:1089-1126`); rule amount:
  `MerchantDiscount.amountFor` = `clamp(percent·base/100 or fixed, 0, base)` rounded 3dp —
  `pos_models.dart:902-908`.
- Auto order-scope: best qualifying `auto_apply` non-manager rule self-applies —
  `pos_controller.dart:1208-1233`.
- Combined `discountAmount = round3(clamp(orderLevel + lineDiscountTotal + offerDiscountTotal, 0, rawSubtotal))`
  — `pos_controller.dart:1083-1084`.
- `stackable` flag is cached in Drift (`lib/data/db/tables.dart:301`, parsed
  `lib/services/config_mapper.dart:517,941`, model `pos_models.dart:816`) but **never consulted in
  any pricing decision** — the machine's "best single rule" semantics ignore it.

### 3.2 pos_handheld
- **Order-scope, non-auto rules only.** Product/category-scope rules and `auto_apply` rules are
  DROPPED at catalog parse: `pos_handheld/lib/models/catalog.dart:224-230`
  (`if (scope != 'order' || status != 'active' || m['auto_apply'] == true) return null;`).
- Manual/rule amount: `amountFor = round3(clamp(percent·subtotal/100 or fixed, 0, subtotal))` —
  `pos_handheld/lib/main.dart:350-352`.
- `_postDiscount = clamp(raw − discount − offers, 0, ∞)` — `main.dart:632-634`.

### 3.3 Blueprint "shared evaluator" is dead code
- `pos_merchant/src/app/Actions/Pos/Discounts/EvaluateDiscounts.php` — pure baisas evaluator with
  **different semantics** (non-stackable-first ordering, multiple rules stack, percents compound on
  the running line subtotal, order rules apply after line discounts — `:60-88` doc + impl).
- Callers: only tests (`tests/Feature/Pos/EvaluateDiscountsTest.php`,
  `tests/Feature/Pos/DiscountsControllerTest.php`) and a comment in EvaluateLoyalty. **No
  production caller in pos_merchant, none in pos_api** (grep verified). Neither Flutter app ported
  it; both implement their own, different, semantics.

### 3.4 Wire + server
- Machine emits: order-level row = `discountAmount − lineDiscountSum − offerSum` (clamped ≥0), plus
  per-line rows (`line_index`), plus offer rows (`offer_id`) — `order_sync_payload.dart:179-217`.
- Handheld emits: offer rows keep full value; the manual slice absorbs the clamp
  (`manualEmit = min(manualBaisas, subtotal − offerBaisas)`) — `order_sync_service.dart:319-358`.
- Server stores rows as sent; resolves `discount_id` soft (falls back to sent label), `offer_id`
  HARD (foreign → whole event fails) — `CreateOrderHandler.php:382-442`.
- **Σ(discount rows) is never compared to `discount_total_baisas`.** Machine edge: when
  `orderLevel + lineSum + offerSum > rawSubtotal`, `discountAmount` clamps to `rawSubtotal` but the
  emitted line+offer rows keep full value ⇒ Σ(rows) > discount_total, silently accepted
  (`pos_controller.dart:1083-1084` + `order_sync_payload.dart:199-217`). Handheld has the analogous
  edge only when offers alone exceed the subtotal (`order_sync_service.dart:338-344`).
  DiscountReport/by_offer (SUM of `pos_order_discounts.amount`) will then disagree with the sales
  report's `SUM(discount_total)`.

### 3.5 Line discount column
- Devices never send `line_discount_baisas`; `pos_order_items.line_discount` is always 0
  (`CreateOrderHandler.php:150`; machine sends line discounts as discounts[] rows instead —
  `order_sync_payload.dart:164-176`). `pos_merchant/src/app/Models/OrderItem.php:21-22` doc claims
  `line_total = qty × unit_price − line_discount`, which is wrong for real device orders
  (`line_total = qty × unit_price`, discount rides pos_order_discounts).
  `pos_merchant .../DiscountedCompedProductsReportAction.php:32` explicitly avoids the column.

---

## 4. Tax

| Location | Formula | Evidence |
|---|---|---|
| pos_machine | exclusive, per-order, per-company-tax: each line `round3(base × rate/100)`, then `round3(Σ)`; base = `_taxedBase = round3(clamp(subtotal − compAmount, 0, ∞))` (post-discount, post-comp) | `pos_models.dart:147-161`; `pos_controller.dart:1325-1340` |
| pos_machine draft (held) | same rounding; base = post-discount (drafts carry no comps) | `pos_models.dart:1564-1578` |
| pos_handheld | identical ("pos_machine parity" comment): `taxTotalFor(taxes, base)`; base `= clamp(postDiscount − comp, 0, ∞)` | `catalog.dart:646-650`; `main.dart:662-667` |
| Delivery exemption | tax = 0 on delivery orders on both devices | machine `pos_controller.dart:1329-1338`, `pos_models.dart:1570-1572`; handheld `main.dart:571-573` |
| pos_api | stored as-is; **never recomputed** ("The server never recomputes tax — it only checks the additive invariant" — machine comment `pos_controller.dart:1329-1331`, matches server code) | `CreateOrderHandler.php:112` |
| reports | `SUM(tax_total)` | merchant `SalesReportAction.php:99`; admin `AdminSalesReportAction.php:50` |

Tax rounding is **per-tax-line then summed, per-order** (never per-cart-line). Machine and handheld
are formula-identical. VERIFIED.

**Divergence (pre-sync only):** handheld falls back to a mock 5% tax before the first catalog sync
(`main.dart:211` `_mockTaxes`, `:569`), while the machine's rule is "empty ⇒ no tax"
(`pos_models.dart:144-145`). Money-real only if a sale is possible before first config sync
(activation flow likely prevents it — Cannot-Verify the gating here).

---

## 5. Comps / gifts, grand total, split, change

### 5.1 Comp & gift write-offs
- Machine: gift value = line net of its auto line discount (`giftAmountFor`,
  `pos_controller.dart:1262-1266`); whole-order comp = `subtotal − gifts`; line comp = line net;
  total clamped to subtotal — `pos_controller.dart:1277-1303`.
- Handheld: same shape but line values use FULL `lineTotal` (no line-discount netting — consistent
  because the handheld has no line discounts) — `main.dart:636-660`.
- Wire (both): gift rows take face value capped to remaining budget; reasoned comp takes the
  remainder; Σ rows == comp_total exactly — machine `order_sync_payload.dart:219-254`, handheld
  `order_sync_service.dart:286-317`; server enforces `CreateOrderHandler.php:461-536`.

### 5.2 Grand total
- Machine: `total = round3(_taxedBase + tax)`; wire `grand_total_baisas = omrToBaisas(total)` —
  `pos_controller.dart:1340`, `order_sync_payload.dart:268`. The additive invariant holds within
  the server's ±1 tolerance (each aggregate converted independently).
- Handheld: `grand_total_baisas` is **derived in integer baisas** =
  `subtotal − discount − comp + tax`, so the invariant holds exactly by construction —
  `order_sync_service.dart:361-364`.

### 5.3 Split allocation
- Machine: equal share `round3(total / splitCount)`; last leg = `total − Σ paid bases` (remainder
  closes the drift); custom per-guest plan invalidated by cart nonce + plan-total match (±0.0005)
  — `pos_controller.dart:1398-1434`, plan application `:1818-1849`. Wire: last tender forced to
  `grandBaisas − acc` so Σ == grand exactly — `order_sync_payload.dart:286-302`.
- Handheld: cashier-built legs must sum exactly to the total before Continue
  (`payment_screen.dart:1963-1996, 2003-2004`); at most ONE card leg (`:1976`); builder's last leg
  absorbs rounding — `order_sync_service.dart:377-397`.

### 5.4 Change / cash tendered
- Machine: change is **display-only** — `_cashChangeAmount = round3(tendered − base)`
  (`staff_pos_screen.dart:3394-3401`); validation `tendered + 0.0005 < payableTotal` fails
  (`pos_controller.dart:2798-2803`). The wire tender carries NO `change_given_baisas`
  (`order_sync_payload.dart:295-311` — method/amount/status/card evidence only) ⇒
  `pos_payments.change_given` is NULL for every machine order.
- Handheld: `_changeDue = max(0, round3(tendered − total))` (`payment_screen.dart:387-389`) and it
  IS sent: `change_given_baisas` (`payment_screen.dart:454`; `order_sync_service.dart:394-395`),
  while `amount_baisas` remains the NET bill amount (doc `order_sync_service.dart:56-59`; enforced
  by the server's Σ(amount)==grand check).

### 5.5 FINDING — expected-cash double-subtraction (server vs handheld wire semantics)
`CloseShiftHandler` computes `net cash = SUM(amount) − SUM(change_given)`
(`pos_api .../CloseShiftHandler.php:66-77`, also tender summary `:171-183`). But
`PayOrderHandler.php:168-171` forces `amount` to be the NET amount (Σ == grand). For any handheld
cash order where change was given, cash is subtracted twice ⇒ `expected_cash` understated by the
change amount ⇒ every such shift shows a phantom OVER variance; the Z-report cash tender line is
equally understated. The pos_api contract tests only ever send `change_given_baisas: 0`
(e.g. `tests/Feature/DeviceSyncOrderTest.php:114`) or omit it (`DeviceSyncShiftTest.php:104-116`),
so the bug is untested. Machine orders are unaffected (no change on the wire) — which itself is a
machine/handheld wire divergence. The two server checks are mutually inconsistent: one demands net
amounts, the other assumes gross.

---

## 6. Offers (promotions) engine — machine vs handheld diff

Handheld's engine is a near-verbatim port ("ported VERBATIM from pos_machine" —
`pos_handheld/lib/services/offer_engine.dart:3-5`). Full `diff` shows only cosmetic changes
(OfferLine adapter, `_intSet` rename) **plus ONE deliberate semantic divergence**:

- **multi_buy at/under-price set**: machine consumes the set's units BEFORE checking the discount,
  then breaks — `pos_machine/lib/services/offer_engine.dart:213-227` (`u.consumed = true` for the
  set, then `if (discount > 0) ... else break`). Handheld breaks BEFORE consuming —
  `pos_handheld/lib/services/offer_engine.dart:229-235`, with the comment: *"Do NOT consume: leave
  the units for other offers (divergence from pos_machine, which consumes-then-breaks and so
  starves later offers of an at/under-price set — a real overcharge)."*
- Consequence: the same cart under the same offer list can price DIFFERENTLY on the two devices —
  when a multi-buy set's value ≤ the offer price, the machine burns those units so a later offer
  (bogo/cheapest-free/another multi-buy) cannot discount them; the handheld leaves them free.
  Machine total ≥ handheld total. The handheld author identified the machine behaviour as an
  overcharge but the machine was not fixed.
- Everything else (bogo cheapest-get, largest-remainder exact allocation `_allocateExactly`,
  spend_get thresholds in baisas, bundle re-validation) is byte-identical logic. VERIFIED by diff.

Offer applicability gating (`appliesAt`) is verbatim-equal across `pos_models.dart:966-988` and
`catalog.dart:353+`.

---

## 7. Merchant / admin reports — stored totals, and the comp hole

All revenue reports aggregate the STORED order columns (no recomputation from lines):
- merchant `SalesReportAction.php:95-101` (`SUM(subtotal/discount_total/tax_total/grand_total)`),
  `DashboardSummaryAction.php:134,167,214,269,296,324,461` (`SUM(grand_total)`),
  `ShiftReportAction.php:59-90` (reads `pos_shifts.expected_cash` as stored).
- admin `AdminSalesReportAction.php:46-51`, `SalesSummaryAction.php:49`.
- device-facing `pos_api .../BuildBranchReportAction.php:79-101` (SUM stored totals + comp rows).

### 7.1 FINDING — net_sales / net_profit ignore comp_total
- Devices define `grand = subtotal − discount − comp + tax` (CreateOrderHandler invariant), and
  comped/gifted food charges no tax and collects no money.
- Merchant: `net_sales = gross_sales − discount_total` (`SalesReportAction.php:114-115`);
  `net_profit = net_sales − commission − operating_expenses (+ recoverable purchase tax)`
  (`SalesReportAction.php:158-160`). `comp_total` appears NOWHERE in the file (grep verified).
- Admin: `net_sales = SUM(subtotal) − SUM(discount)` (`AdminSalesReportAction.php:76`).
- Consequence: for any order with comps/gifts, merchant net_sales and net_profit (and admin
  net_sales) are overstated by exactly the comp amount — money that was never collected. The
  Z-report does it right (comps its own deduction line — machine `shift_summary.dart:333-339`,
  server summary `CloseShiftHandler.php:161-171` returns comp separately), and BuildBranchReport
  surfaces comp separately, so the surfaces disagree with each other.

### 7.2 COGS
- Definition: Σ over paid order items of `recipe_snapshot_json` (frozen `{qty, unit_cost}` per ONE
  unit × line qty) + legacy add-on `ingredient_snapshot_json` — merchant
  `SalesReportAction.php` `cogs()` (lines ~555-585) + `Support/RecipeSnapshotCost.php:31-53`
  (integer baisas, rounded once per line). Per-product variant:
  `ProductPerformanceReportAction.php:203` (recipe snapshots only — add-on ingredient costs not
  even the legacy trio).
- Snapshots written by pos_api at create: `CreateOrderHandler.php:657-682` (`snapshotRecipe`;
  cooked/unit products deliberately freeze NO recipe — their cost reaches profit via the purchase
  expense, PD2/PD5, documented `:643-654` and `SalesReportAction.php:124-131`).
- **Gap**: PD3b add-on consumption lines (`consumption_snapshot_json`, carrying `unit_cost` —
  `CreateOrderHandler.php:761-800`) SUPERSEDE the legacy trio, and when they exist the legacy
  `ingredient_snapshot_json` is written NULL (`CreateOrderHandler.php:165-171`). The COGS readers
  (`RecipeSnapshotCost`) read ONLY `recipe_snapshot_json` + `ingredient_snapshot_json` — they never
  read `consumption_snapshot_json`. So the ingredient cost of any modern add-on option is
  **excluded from reported COGS**, while the stock ledger DOES move that stock with those costs
  (`ConsumeInventoryAction.php:140-148`). Reported COGS understates; gross_profit overstates;
  Inventory-consumption ledger and COGS disagree.
- No admin COGS implementation exists (grep: RecipeSnapshotCost only in pos_merchant).

### 7.3 Product performance revenue
- `revenue = SUM(pos_order_items.line_total)` — pre-discount, pre-comp, and INCLUDING add-on price
  deltas (device line_total includes modifiers) — `ProductPerformanceReportAction.php:82`. A linked
  add-on product's money also appears as `addon_revenue` (`:69`) — presentational double-listing
  across columns, and product "revenue" will never reconcile with net_sales. P3 presentational.

---

## 8. Commission split

- pos_api `RecordSaleCommissionAction` (`pos_api/src/app/Actions/Device/Sync/RecordSaleCommissionAction.php`):
  integer-baisas split; bank share charged on card money only (`:126-133`); collected =
  grand − gift tenders (`:82`); channel split card/cash_bank; each share `round(base × pct/100)`;
  merchant takes the exact per-channel remainder (`:141-155`); invariant Σ rows == collected.
  Deferred when any tender is `pending_reconciliation` (`PayOrderHandler.php:185-203`).
- pos_admin TWIN `pos_admin/src/app/Actions/Admin/Reconciliation/RecordSaleCommissionAction.php`
  — header admits: "TWIN of pos_api ... keep in sync. (The repos share the DB but not code; this
  duplication is the accepted cost.)" (`:15-20`). Full diff shows the two are currently
  **logically identical** (only enum-normalisation of `party_type` and inlined string constants).
  Caller `ReconcileDeferredEffectsAction.php:158-193` re-derives cardBaisas/giftBaisas from the
  now-confirmed payments the same way PayOrderHandler does. VERIFIED in-sync today; standing
  divergence risk is by-design and unguarded by any cross-repo test.
- Merchant-side consumption of the rows is settled-aware:
  `COALESCE(settled_amount, commission_amount)` — `SalesReportAction.php:485,510-511`.

---

## 9. Loyalty math

- Evaluator duplicated in TWO PHP repos: `pos_api/src/app/Actions/Pos/Loyalty/EvaluateLoyalty.php`
  is a port of `pos_merchant/src/app/Actions/Pos/Loyalty/EvaluateLoyalty.php` ("ported verbatim
  (logic-wise)" — pos_api `:11-17`). Full diff: logic identical (enum vs string match only).
- Earn (server-authoritative): points = `intdiv(subtotalBaisas × points_per_omr, 1000)` (floor);
  stamp = 1 per qualifying order (`EvaluateLoyalty.php:60-99` merchant / same in api).
  `points_per_omr` is cast `(int)` — a fractional configured rate (e.g. 0.5) would floor to 0
  (`EvaluateLoyalty.php` evaluateSpend first line). Devices parse it as double
  (machine `pos_models.dart:1133`, handheld `catalog.dart:274`) — display drift possible if the
  portal permits decimals (portal validation not examined — Cannot-Verify).
- **Earn base = `subtotal − discount_total` (comps NOT deducted)** —
  `ApplyLoyaltyEarnAction.php:59-64` (`$eligibleBaisas = max(0, subtotal − discount_total)`).
  The "fully gifted earns nothing" guard only checks gift TENDERS:
  `PayOrderHandler.php:211-213` (`if ($giftBaisas >= $grandBaisas && $grandBaisas > 0)`).
  Machine gifts/comps ride COMP rows, not gift tenders (`order_sync_payload.dart:219-254`), and a
  fully comped order has grand == 0, so the guard never fires ⇒ a customer earns FULL points/stamps
  on food that was 100% comped/gifted away (eligible = raw − discount > 0). Contradicts the stated
  intent in the same file ("no spend ⇒ no points").
- Redeem: strict server decrement (`ApplyLoyaltyRedeemAction.php:38-70`); its OMR value rides the
  order discount on both devices (machine `pos_controller.dart:1742-1792`; handheld
  `main.dart:2026-2046`), so redemption also reduces the tax base and the next earn base.
- Device redemption-value math is parity-equal:
  - machine points: blocks capped by balance ÷ redemption_points AND `rawSubtotal ÷ redemption_value`
    (`staff_pos_screen.dart:3113-3117`); value = blocks × redemption_value (`:3139-3140`).
  - handheld: same (`main.dart:2056-2064`, `2021`).
  - stamp reward: percent_off → pct × subtotal (machine clamps pct at 100
    `staff_pos_screen.dart:3029`; handheld doesn't clamp pct but clamps the value to subtotal
    `main.dart:2094,2109` — same effective cap); free_product → current catalog price, fallback
    reward_value (machine `:3030-3034`; handheld `:2096-2104`).

---

## 10. Charity round-up

- Machine only: `offeredTotal = round3(base.ceilToDouble())` (ceil to next whole OMR), amount =
  offered − base, offered only on card ('Credit Card') legs, ≥ 0.001 —
  `pos_controller.dart:1443-1461`. Per-leg on splits; cash legs never round (comment `:1452-1459`).
- Wire: tender amount stays the BASE; the round-up goes as its own `donation.record` with
  `payment_index` pointing at the card leg — `order_sync_payload.dart:376-414`. So
  `pos_payments.amount` excludes the round-up; the link back is
  `payments.roundup_amount`/`charity_transaction_id` (`DonationRecordHandler.php:154-160`).
- Server: validates the indexed leg IS a card tender (fails loud otherwise) —
  `DonationRecordHandler.php:88-97`; forwards to charity best-effort after commit, deferred while
  any tender is pending_reconciliation (`:99-207`).
- **pos_handheld has NO round-up at all** — grep over `pos_handheld/lib` finds round-up only in the
  Z-report display (`shift_report_screen.dart:208-210,497-499`). Machine offers it on every
  qualifying card sale. Same platform, device-dependent charity capture (also a Z-report line that
  can only be non-zero for machine sales).

---

## 11. Shift / Z-report summary duplication

- Server (authoritative): `CloseShiftHandler.php:146-227` — SUM of stored order columns + tender
  groups + comp rows + round-ups + branch expenses over the shift window/attribution.
- Machine offline fallback: `buildLocalShiftSummary` folds the device-local order log —
  `pos_machine/lib/services/shift_summary.dart:138-207`; visibly tagged 'local'; known legitimate
  divergences documented in the file header (`:4-9`).
- Machine's local tender lines use split `baseAmount` (pre-round-up) matching server tender
  semantics (`shift_summary.dart:171-183`).
- Handheld renders the server summary only (`shift_report_screen.dart`).
- Drawer math: expected = opening + net cash; variance = counted − expected — identical on machine
  print doc (`shift_summary.dart:376-379`) and server — EXCEPT the change_given flaw in §5.5.

---

## 12. Consolidated calculation × location matrix

| Calculation | pos_machine | pos_handheld | pos_api | pos_merchant | pos_admin |
|---|---|---|---|---|---|
| Subtotal | Σ line floats, round at wire (`pos_controller.dart:1070`) | Σ per-line int baisas (`order_sync_service.dart:263-267`) | stored as-is (`CreateOrderHandler.php:108`) | SUM(subtotal) (`SalesReportAction.php:97`) | SUM(subtotal) (`AdminSalesReportAction.php:48`) |
| Discount | order + best-line + offers, clamp raw (`pos_controller.dart:1072-1126`) | order-scope manual/rule + offers only (`catalog.dart:224-230`) | rows stored, Σ NOT checked (`CreateOrderHandler.php:382-442`) | SUM(discount_total); by-rule from rows (`DiscountReportAction`) | SUM(discount_total) |
| Tax | per-order, per-tax round3 then sum, on post-disc post-comp base (`pos_models.dart:147-161`) | identical (`catalog.dart:646-650`) | stored as-is | SUM(tax_total) | SUM(tax_total) |
| Grand | round3(base+tax) → baisas (`pos_controller.dart:1340`) | derived int: sub−disc−comp+tax (`order_sync_service.dart:363`) | invariant ±1 only (`CreateOrderHandler.php:627-638`) | SUM(grand_total) | SUM(grand_total) |
| Comp/gift | net-of-line-discount values (`pos_controller.dart:1262-1303`) | full lineTotal values (`main.dart:636-660`) | Σ rows == total EXACT + caps (`CreateOrderHandler.php:461-536`) | CompReport from rows; net_sales ignores | ignores |
| Split | equal/custom + remainder leg (`pos_controller.dart:1398-1434`) | manual legs, must sum exactly (`payment_screen.dart:1963-1996`) | Σ tenders == grand ±1 (`PayOrderHandler.php:168-171`) | — | — |
| Change | display only, not on wire (`staff_pos_screen.dart:3394-3401`) | on wire `change_given_baisas` (`order_sync_service.dart:394-395`) | stored; DOUBLE-COUNTED at shift close (`CloseShiftHandler.php:71-77`) | reads stored expected_cash | — |
| Commission | — | — | RecordSaleCommissionAction (device pay) | reads rows settled-aware | TWIN action (reconciliation approve) |
| Loyalty earn | names rule ids only | names rule ids only | EvaluateLoyalty on sub−disc (`ApplyLoyaltyEarnAction.php:59-64`) | EvaluateLoyalty original (unused for sales path) | — |
| Loyalty redeem value | blocks × redemption_value, cap raw subtotal (`staff_pos_screen.dart:3113-3140`) | identical (`main.dart:2050-2110`) | strict balance decrement only | — | — |
| Round-up | ceil to whole OMR, card-only (`pos_controller.dart:1443-1461`) | ABSENT | DonationRecordHandler | RoundUpDonationReport (rows) | reconciliation forward twin |
| COGS | — | — | freezes recipe/addon cost snapshots | RecipeSnapshotCost from snapshots (misses consumption_snapshot_json) | none |
| Offers | offer_engine.dart (consume-then-break multi_buy) | port, check-then-break multi_buy | rows stored, offer_id hard-validated | by_offer SUM(rows) | — |

---

## 13. Findings (ranked)

1. **P1 — Shift expected-cash double-subtracts change for handheld cash sales.**
   `CloseShiftHandler.php:66-77` computes `SUM(amount) − SUM(change_given)` while
   `PayOrderHandler.php:168-171` forces `amount` to be net-of-change (Σ == grand). Handheld sends
   `change_given_baisas > 0` on overpaid cash (`payment_screen.dart:454`,
   `order_sync_service.dart:394-395`); machine never sends it. Every handheld cash sale with change
   understates expected_cash / the Z-report cash tender by the change amount → phantom OVER
   variances, merchant Shift Report (reads stored `expected_cash`, `ShiftReportAction.php:59-90`)
   inherits it. Contract tests only ever use change 0. VERIFIED.

2. **P1 — multi_buy offer engine diverges machine vs handheld (same cart, different total).**
   Machine consumes an at/under-price set then breaks (`pos_machine/lib/services/offer_engine.dart:213-227`);
   handheld deliberately does not (`pos_handheld/lib/services/offer_engine.dart:229-235`, comment
   brands the machine behaviour "a real overcharge"). Later offers are starved of those units on
   machine only. VERIFIED by diff.

3. **P1 — Handheld ignores product/category-scope and auto-apply order discounts.**
   `pos_handheld/lib/models/catalog.dart:224-230` drops them at parse; machine auto-applies both
   (`pos_controller.dart:1089-1126, 1208-1233`). The same merchant rule set prices the same cart
   differently depending on which device rings it. VERIFIED.

4. **P1 — Merchant + admin net_sales/net_profit ignore comp_total.**
   `SalesReportAction.php:114-115,158-160` and `AdminSalesReportAction.php:76` compute
   net = subtotal − discount only, while grand (and cash actually collected) also subtracts comps
   (`CreateOrderHandler.php:627-638`). Comped/gifted revenue is reported as earned. Z-report and
   BuildBranchReport treat comps correctly ⇒ surfaces disagree. VERIFIED.

5. **P2 — Reported COGS misses PD3b add-on consumption costs.**
   `CreateOrderHandler.php:165-171` nulls the legacy `ingredient_snapshot_json` when
   `consumption_snapshot_json` supersedes it; `RecipeSnapshotCost` (merchant) reads only
   recipe + legacy fields; stock movements DO carry the superseding costs
   (`ConsumeInventoryAction.php:140-148`). COGS understated, gross_profit overstated. VERIFIED.

6. **P2 — Loyalty earn base ignores comps; "fully gifted earns nothing" guard covers gift tenders
   only.** `ApplyLoyaltyEarnAction.php:59-64` (sub − discount) + `PayOrderHandler.php:211-213`
   (grand>0 required); machine comp/gift rows leave grand at 0 ⇒ full points accrue on 100%
   comped orders, contradicting the documented intent. VERIFIED (policy call is the merchant's,
   but code contradicts its own comment).

7. **P2 — Server never validates Σ(lines) vs subtotal, line_total vs qty×unit, or Σ(discount rows)
   vs discount_total.** Comps get an exact-sum check; discounts do not
   (`CreateOrderHandler.php:382-442` vs `:461-536`). Machine's over-100%-discount clamp edge
   (`pos_controller.dart:1083-1084` + `order_sync_payload.dart:199-217`) produces Σ(rows) >
   discount_total that the server accepts, desyncing DiscountReport from SalesReport. VERIFIED
   (absence of checks + the emitting edge; not observed with production data).

8. **P2 — Blueprint "shared discount evaluator" is dead code; `stackable` is stored but never used
   on devices.** `pos_merchant .../EvaluateDiscounts.php` (stacking semantics) has no production
   callers; machine picks best-single-rule and ignores `stackable`
   (`pos_models.dart:816` parsed, zero pricing reads); handheld has no line rules at all. A
   merchant flagging rules stackable/non-stackable gets neither semantic at the till. VERIFIED.

9. **P2 — RecordSaleCommissionAction + EvaluateLoyalty are cross-repo duplicated ("keep in sync"
   twins).** pos_api vs pos_admin commission twins currently identical (full diff); pos_api vs
   pos_merchant loyalty evaluators identical. No shared package or cross-repo test guards them.
   VERIFIED equivalence today; the risk is structural.

10. **P2 — Handheld charges 5% mock tax before first catalog sync; machine charges none.**
    `main.dart:211,569` vs `pos_models.dart:144-145`. Impact depends on whether a sale can happen
    pre-sync (activation gating not audited). PARTIALLY VERIFIED.

11. **P3 — pos_payments.change_given is NULL for all machine cash sales** (wire never carries it,
    `order_sync_payload.dart:295-311`), so any change-based analysis is handheld-only; and
    `OrderItem.php:21-22` documents `line_total = qty × unit_price − line_discount` which devices
    do not honour (line_discount always 0). VERIFIED.

12. **P3 — ProductPerformance revenue is pre-discount/pre-comp line_total including add-on deltas,
    plus a separate addon_revenue column for linked products** (`ProductPerformanceReportAction.php:69,82`)
    — will not reconcile with net_sales; cross-column double-presentation. VERIFIED.

## Cannot-Verify / out of scope notes
- Whether the merchant portal permits fractional `points_per_omr` (server int-cast would floor it).
- Whether a handheld sale is reachable before the first catalog sync (mock 5% tax exposure).
- Runtime data was not inspected (no DB access) — all findings are code-path findings.
- Void/refund unwind symmetry, bank reconciliation matching, and charity forwarding amounts are in
  other agents' charters and were only touched where they intersect the money formulas.
