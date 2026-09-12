# Unified staff flow — protected staff table checkout (4C5)

Server prerequisite: pos_api bdd875bb89b8cf825e790eb30dcfd20402a94a75.
This is local implementation, not a deployment or device-test report.

Dine-In can open the existing normal payment page for a staff-only canonical
bill only when the server advertises checkout_policy=staff_table_claim_v1.
The source remains main_pos or handheld; QR identity is never invented.
Unknown/older policies, wrong table identity or a missing seating cannot enable
the path. Existing pending-round, local-copy, background and offline gates stay.

The immutable checkout parser accepts this explicit staff capability while
retaining UUID, claimed amount, deadline and frozen-money comparisons. The
existing coordinator, normal payment layout, revalidation before tender and
each physical bank/card leg, capture evidence, standalone order.pay, exact retry,
cancel/release and manager-recovery behavior are unchanged. No bill enters the
cart and no local pricing, order.create, GPS or item payload is added to payment.

Staff-only draft recovery is now enabled only with the same server capability.
Before the recovery POST the existing durable guard fences the original copy.
Only the exact receipt and unchanged raw local record set authorize archival.
An owning-device requirement on the server prevents another device from claiming
until the original draft has been reconciled. Lost replies retain the same
request; old-server responses keep the original payable copy intact.

Proven unsent additions are retained after archival and require an explicit
separate price-free round send on the same supported bill/seating. Legacy
unproven extra quantities remain blocked.

EN refusal: Recover the original table draft on its owning device first.
No payment was started.
AR refusal: استعد مسودة الطاولة الأصلية على جهازها أولاً. لم تبدأ أي عملية دفع.

New tests cover both staff sources, all tenders, old-server refusal, pending/
local/linked-table guards, normal payment page wiring, replay failures, lost ACK,
uncertain capture and exact local retirement. Existing test bodies/assertions
and skip markers are unchanged. New test-fixture corrections (map typing and
the physical-leg replay count) did not change application behavior.

No migration, generated file, dependency, schema, polling, notification, printer,
APK, device, stack or real payment changes. No fetch or push. Final immutable
export counts, commits and limitations are in the shared
QR-003_UNIFIED_STAFF_TABLE_CHECKOUT_HANDBACK.md.
