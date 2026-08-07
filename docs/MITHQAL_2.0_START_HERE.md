# MITHQAL 2.0 — Start Here

Entry point for the platform documentation. If you are picking this system up — human or AI agent — read this page first, then the two documents below in order.

## The platform in one paragraph

MITHQAL 2.0 is a multi-vendor POS/ERP for restaurants and cafés in Oman. It is **six projects over one shared PostgreSQL database** (`charity_db`, shared with a live charity product): `pos_admin` (platform operator portal — **owns every `pos_*` migration**), `pos_merchant` (merchant portal), `pos_api` (the device contract — the only backend the tills talk to), `pos_machine` (main Flutter POS), `pos_handheld` (handheld Flutter POS — a **separate codebase**, not a build flavour), plus the charity system it forwards round-up donations to. Money is integer **baisas** on the wire and `decimal(12,3)` OMR in the database.

## The two documents

| Read | Document | Answers |
|---|---|---|
| **1st** | **`MITHQAL_2.0_SYSTEM_AUDIT.md`** | *What is true today.* Full source audit against all three blueprint PDFs: architecture, a 99-requirement gap analysis, 141 verified findings, per-flow correctness audits, database and security analysis, health scores, and a final go/no-go verdict. **Start with its ⚠ Status block, then §1 Executive Summary and §8 Correctness Audit.** |
| **2nd** | **`MITHQAL_2.0_ARCHITECTURE.md`** | *What to build, and how.* Five phased build plan at implementation depth — exact tables and columns, endpoints and sync-event payloads, which files change in each app, what each piece reuses, backward compatibility with APKs already in the field, and the tests to add. **This supersedes §31–§34 and §39 of the audit.** |

Supporting: **`audit-evidence/`** holds the 22 per-domain evidence files with `file:line` citations behind every claim, the consolidated findings register, and the adversarial verification verdicts. Go there when you want proof of a specific finding.

## How the blueprints were reconciled

Three PDFs describe an evolving specification, not three separate specs:

1. **Blueprint v2.0** (23 May 2026, 62 pp) — the master spec: 5 surfaces, 12 phases, schema, APIs, cross-cutting systems.
2. **Feature Additions** (June 2026, 9 pp) — 18 restaurant features (6 MVP-critical) plus the authoritative unit-of-measure ingredient model.
3. **Architecture & Feature Specification** (3 Aug 2026, 15 pp) — **newest, wins on conflict**. Adds QR ordering, KDS, print agent, drive-up, receiving/counting/variance operations, and names the go-live blockers.

Merge rule applied throughout: **newest overrides older conflicting requirements; unique non-conflicting requirements from older documents are retained.** Supersessions are recorded explicitly in the audit's §4 (Blueprint Evolution).

## Where the system stands

- **Verdict: YES, AFTER CRITICAL FIXES.** The transactional core is trustworthy — exactly-once sync, single-transaction settlement under row locks, frozen snapshots, append-only ledgers, multi-tenancy that held under adversarial testing. The failures are at the edges.
- **Phase 0 (money integrity): 3 of 10 done.** HH-001, HH-002 and API-003 are committed (see the audit's Status block). Seven remain, starting with MC-001.
- **Two go-live blockers unmet:** Oman VAT-compliant tax invoices, and a branch end-of-day close. Both are designed in the architecture document's Phase 3.
- **Nothing is pushed.** All commits are local on `main`, per project convention.

## Decisions already locked (do not silently reverse)

Four calls were made with the system owner. Each is recorded with its reasoning in the architecture document's Context section, because a future reader comparing code against the blueprints will otherwise "fix" them back:

1. **Extend the existing catalog model** — the Aug spec's unified `items`/`item_components` migration is formally superseded; combos become a bounded extension instead.
2. **Scope through go-live** — Phase 7+ features stay deferred exactly as the blueprints defer them.
3. **Overlapping discounts keep biggest-wins** — not the blueprint's compounding stack, because that would silently reprice every merchant.
4. **One promotion per item, with a capped total** — the one change in the plan that *does* move live prices, and it ships on measured evidence rather than assumption.

## If you are here to write code

Read the architecture document's **Ground rules** section before touching anything. The three that bite hardest:

- Migrations are **additive only** and live **only** in `pos_admin`. The database is shared with a live charity product.
- The device contract is `pos_api/src/tests/Feature/Device*Test.php` (437 tests). APKs stay in the field after a backend deploy, so changes are additive — never reinterpret an existing field.
- Money is integer baisas on the wire; convert only at boundaries.
