# Phase 0 Failure: EXIT-05 — order.pay with loyalty EARN context settles anonymously after customer hard-delete

- Status: FAIL-PRODUCT
- First observed: 2026-08-13 (Asia/Muscat), T2 lane execution
- Repository/branch/SHA: pos_api, main, `07f92c4`
- Scenario/test: EXIT-05 / `tests/Feature/Phase0Exit/DeletedCustomerReplayTest::test_pay_with_earn_context_never_settles_anonymously_after_a_hard_delete` (kept failing at line 283)
- Command: `wsl -e bash -lc "cd .../pos_api && docker compose exec -T pos_api php artisan test tests/Feature/Phase0Exit"`
- Disposable environment identity: SQLite `:memory:` in the pos_api container (production FK actions mirrored manually; see caveat)

## Expected
EXIT-05: a queued sale whose customer was deleted before replay is "never discarded/falsely processed". The contract disjunction: fail visibly for operator action OR process with the promised attribution — never the silent middle.

## Actual
An `order.pay` carrying `loyalty_rule_id` (earn context) for an order whose customer was hard-deleted (customer_id NULLed by the production FK `pos_orders.customer_id → nullOnDelete`, migration `2026_06_04_010000`) settles as an **anonymous walk-in sale**: ACK `processed`, payment written, `ApplyLoyaltyEarnAction` silently no-ops on the NULL customer_id. No error, no review flag; the promised earn vanishes. First failure: "Failed asserting that null is not null" on the attribution assertion.

## Reproduction
Deterministic: create order with customer, hard-delete the customer, push order.pay with a valid earn rule. Contrast: the loyalty **redeem** variant fails visibly and parks ("cannot redeem loyalty without a customer on the order") — the earn path lacks the equivalent guard.

## Evidence
Failing test kept in place (other four EXIT-05 variants in the same file are green and pin the working contracts). Root cause read-only: `PayOrderHandler` passes only `order->customer_id`; nothing detects that earn context on the pay implies a vanished customer.

## Scope/impact
Loyalty integrity: a customer's promised earn silently disappears; the sale is misattributed as walk-in. Low money risk (payment itself is correct) but violates "never falsely processed" and produces no review evidence.

## Test-only changes
`tests/Feature/Phase0Exit/DeletedCustomerReplayTest.php` (new file; no production change).

## Implementation owner requested
pos_api (`app/Actions/Device/Sync/Handlers/PayOrderHandler.php` / `ApplyLoyaltyEarnAction`): mirror the redeem guard — earn context with a NULL order customer should fail the event visibly (parkable) or write explicit review evidence. SQLite caveat: the test mirrors production FK actions manually (test schema has no FKs); the integrated PG harness re-proves under real FKs.
