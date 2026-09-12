# Same-bill draft recovery — machine integration

Implemented on codex/qr003-unified-staff from parent
576e39173893e41bac988f0df83c0a23824e1865 after the owner's explicit integration
approval. Server prerequisite: 88d1daf3650b899491aeaaef20d8cf129d2c49d7.
No installation, live database, live stack, APK, fetch or push is part of this work.

## Deliberate limits

Dine-In has a separate **Recover this bill draft** action, also reachable after
ordinary detail refuses a legacy local conflict. Live mode is required and
rechecked. The review shows the untouched local snapshot, the complete proven
owned acknowledged subset, and supported unsent local additions separately.

Recovery requires an open `qr_web` shared bill. A staff-only canonical bill is
preserved: its existing local checkout must not be retired until a separate
staff-only checkout review supplies a safe canonical payment path. This feature
does not broaden payment methods or claims. Legacy drafts require an exact
original frozen-line multiset and zero delta. Staff drafts require complete
accepted immutable own-round/outbox evidence, exact line identity and no
cancellation, unresolved, rejected or merged history. Unsupported or ambiguous
differences retain every original copy. No server line becomes a CartItem.

## Durable protocol and storage

The device-scoped gateway uses GET/POST `/device/tables/{id}/draft-recovery` and
`same_bill_recovery_v1`. A SHA-256 hash identifies the canonical raw snapshot.
The immutable intent is committed before POST; retries keep the same UUID,
preview token, hash and event set. Only an exact archive-authorized ACK permits
retirement. An unapplied stale preview unlocks only on the exact retained
`draft_recovery_final_no_write` intent proof; generic errors never release it.

`mithqal_orders.db` v8 -> v9 adds `draft_recovery_journal` and an auxiliary
retirement table without modifying existing data. In one transaction, the exact
related-row set and original raw values are compared, original held/table rows
are retired, and the original snapshot, ACK and raw unsent slices remain in the
journal. Original rows, round/cancel ledger and outbox evidence are retained in
the archive forever. The actual outbox and round/cancel tables are not deleted
or edited by recovery. No generic table-clear hook is invoked.

Retirement fences are derived from validated retained journal originals, not
solely from the auxiliary table. Old bill UUID or exact seating/occupied-time
generation cannot return to a payable draft. A reused display reference with a
different UUID and new generation remains allowed. Missing durable identity,
unknown states, corrupt terminal payloads and missing expected schemas fail
closed. Coordinator cache refresh evicts only the exact retired generation.

## Additions and admission

Supported unsent slices remain `delta_ready` after archive. **Send saved
additions** is explicit: it saves an immutable price-free DineInRequest before
network activity, checks the current same open bill/seating, and correlates the
ACK with the persisted staff round's ID, number and client_request_id before
unlocking. Accepted, pending-review and subsequently rejected recorded rounds
are recorded once, never re-entered with a new ID. Unknown/mismatched outcomes
retain the saved request. No acknowledged baseline is resent or printed;
canonical round print retry remains available for newly recorded additions.

Normal cart, held/dining storage, tender and order API writes are fenced while
recovery is unresolved. Only its exact saved delta request can use the recovery
gateway's append port. All outbox preparation/flush/mutation work shares a queue;
recovery admission occupies that queue and refuses all pending rows, including
parked and GPS-blocked work. Completed/held/void/transfer callbacks reserve a
synchronous preparation counter before GPS or other pre-outbox awaits.
Recovery also requires all scopes of checkout, Dine-In and quick-order journals
to be clear. Combine and recovery exclude each other inside their shared local
database transactions. No network activity occurs in the archive transaction.

## Verification

Checks use clean immutable git-archive exports, offline dependency resolution,
static analysis, formatting and the complete synthetic Flutter suite. Original
assertions and skips remain; older pure controller tests now explicitly inject
the existing in-memory FakeOrderStorage instead of relying on an uninitialized
production store. Historical SQL fixtures add the expected recovery schema
explicitly; production does not bypass a missing schema. Crypto 3.0.7 is promoted
from transitive to direct dependency with no version/digest change. No generated
files are changed. Formatting was applied to edited integration files as well as
new modules; existing test fixture changes contain no removed assertions.

Final tested code tree: `4afa96aed2d9465bb2dda1c4bdb5b194f51f9cc5`.
Clean export/log label: `draft-recovery-machine-integrated-4afa96a-final`.

    No issues found! (ran in 12.9s)
    01:14 +1286 ~3: All tests passed!
    Formatted 30 files (0 changed) in 1.58 seconds.

That is +170 passing tests versus the original 1116/3 parent and +118 versus
the 1168/3 core checkpoint. The three original skips remain unchanged.
The final candidate validates every older combine-journal row during recovery
admission (including foreign scopes, unknown states and corrupt terminal
payloads), every expected recovery column even on an empty table, and overlapping
joined local copies both during loading and transactional CAS. A failed initial
read can return to settings only when no unresolved attempt has been loaded;
leaving never releases a durable business guard. New tests cover these edges.

Only this verification note is updated after the exact code/test tree above;
root records the final metadata tree and verifies lib/test/dependency equality.

The root review records final tree/commit IDs and literal test totals in the
shared handback. Client commit and rollout require that review; this note does
not claim device or live-data validation.
