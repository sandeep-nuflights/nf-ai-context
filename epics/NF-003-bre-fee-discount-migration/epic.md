---
epic: NF-003
title: Service fee & discount migration to GoRules ZEN rulesets
shape: program
status: draft — scope decided 2026-09-16, specs not yet written
created: 2026-09-16
contains: [NF-001, NF-002, NF-004]
parity:
  group: fee-discount
  members: [nf-ndc-adapter-generic, nf-ndc-adapter-rs]
not-affected: []
money-impact: yes
rollout: forward-only
---

# Service fee & discount migration to GoRules ZEN rulesets

## Requirement

Replace the legacy service fee / discount implementation — hardcoded if-else
branches driven by `OrgMasterRuleSet` — with **GoRules ZEN decision tables**
evaluated through the standalone BRE service, for more performant and flexible
fee/discount calculation.

NF-001 and NF-002 are **subsets of this epic**, not siblings of it.

Not to be confused with the Django→Rust stack migration. That one moves *where
code runs*; this one moves *how rules are expressed*. They interact only because
the stack migration decides which repo owns a surface.

## Two implementation strategies, split by table dependency

- **Response-only** — the surface needs no NuFlights table. Evaluate, then
  **intercept the outgoing response and inject** the amounts.
- **Persisted** — the surface has model dependencies and must write rows:
  `FullfilmentOrdersPriceAdjustments` (the fee/discount ledger, FK `order`) and
  `TicketOrgTransactions` (per-(ticket, seller org) back-office record). Response
  injection alone is insufficient, which is why Python needs its own BRE
  integration rather than only proxying.

## Management plane

1. Platform admin authors a **template** in `nf-app-home` — a GoRules graph →
   `bre_rule_template` (`jdm` JSONB + `slot_manifest`).
2. Agency admin **inherits** it in `nf-app-account` and fills only the exposed
   decision table → `bre_rule_set.slot_data`. The agency saves **rows, never a
   graph** (`extractSlotData`); the template's own rows are stripped on handoff
   (`stripTemplateRows`).
3. At evaluation the rows are merged into the template's graph at the named slot
   node, cached as a complete graph
   (`bre:jdm4:{composite_hash}`, 7-day TTL), and evaluated.
4. Response-only surfaces inject the result; persisted surfaces write tables.

`bre_rule_set` replaces `OrgMasterRuleSet`. An agency ruleset is **pinned to
`template_version` permanently** — there is no migration path to a newer
template version, by design.

## Scope decisions (2026-09-16)

| # | Decision | Consequence |
|---|---|---|
| **D1** | **Python owns OrderCreate / OrderChange / OrderRetrieve evaluation.** Rust's interception exists but is not used by the frontend. | Rust's `orderview_proxy` path stays off and becomes a retirement candidate. **But see Gap G1 — Kyte.** |
| **D2** | **Reshop is in scope.** | Currently returns zero silently on both sides. Net-new work; no leaf spec exists in either repo. |
| **D3** | **Cancellation is in scope.** | Contradicts generic FR-011, which excludes it by design. **Escalates NF-002 Q1 to a hard blocker — see G2.** |
| **D4** | **`transaction_type` becomes a rule-template column** — enum `SALE` / `VOID` / `REFUND`, authored in `nf-app-home`; BRE-evaluate callers pass it in the context. | Gives platform admins the "this fee applies on REFUND only" expressiveness the authoring UI lacks today. Detailed design pending from Sandeep. |

## Scope decisions (2026-09-22) — cancellation

Taken while scoping **[NF-004](../NF-004-cancellation-fee-reversal/epic.md)**,
which executes them. They extend D1–D4 rather than replacing anything.

| # | Decision | Consequence |
|---|---|---|
| **D5** | **The cancellation reversal migrates to the BRE too.** The legacy formula engine (`fee_engine.py` + `OrgRelationshipConfig.fee_config`) is not left standing as a second permanent fee engine. | Commission enters BRE scope for the first time — previously excluded in-code (`content_rules.py:6121`). Requires a SALE-time `composite_version` pin that nothing records today. See NF-004. |
| **D6** | **`[Per Segment]` on VOID takes the full segment count**, per NF-002's table — `fee_engine.py:211-212`, which uses the unflown count for VOID and REFUND alike, is therefore a defect. Corroborated by `nf-ndc-adapter-rs` (`context.rs:785-803`). **Confirmed 2026-09-22 and written into NF-002 as the single source;** the legacy divergence is logged as **F15**. | NF-004's VOID parity fixture is generated from the corrected behaviour, never from legacy output. |
| **D8** | ~~The skip is an authoring outcome, not a code exclusion.~~ **Restated 2026-09-23.** **Evaluating a ruleset on a cancellation charges nothing.** A charge exists only where code posts an evaluation result as a new charge, and no such code exists on the cancellation path — so "no charge on VOID/REFUND" holds because **the feature does not exist**, neither by authoring nor by exclusion. The **reversal** evaluates the **pinned** ruleset with the **recorded** `transaction_type` and posts the opposite direction; proration arrives in the token *values*, not the type. A **cancellation charge** would need a **published** evaluation plus posting code. `transaction_type` is authored **mandatory** — no blank cells, so no row matches a type it does not name. | The original reading assumed a decision table is a policy; it is a calculator. Matching a row yields an amount, not a charge. **D4's column is therefore not load-bearing for NF-004** and stops blocking spec 011 — it becomes load-bearing when cancellation charging is built. The pinned-vs-published split is structural, so an author cannot get it wrong. **F3** — the accidental SALE-typed re-evaluation on the cancel path — is closed on its own merits. |
| **D7** | **Sale-time ledger rows stay untouched on cancel**, matching legacy exactly. A durable BRE-side trace of the reversal is **deferred** to a later sub-epic and should be scoped with the audit-durability cluster. | Refund reporting keeps reading the original positive rows (`utils.py:2438`). |

**D3 is narrowed by these.** It put cancellation in scope without distinguishing
*charging* from *reversing*; NF-004 draws that line — no new charge on a cancel,
the reversal reproduced and migrated.

**G2 is downgraded, not closed.** With nothing newly charged on VOID/REFUND, the
unflown tokens are not read by the BRE on the cancel path, so NF-002's Q1 stops
gating cancellation. But the *reversal* still prorates by them (D5), so Q1
survives as a parity question against `fee_engine.py:184` — which answers it in
legacy's own terms: "flown" is **coupon status**,
`exclude(status__in=["B","Flown"])`.

## Confirmed domain invariants

Facts about the business, not about the code. Recorded here because more than one
sub-epic depends on them and because they are **not** derivable from the
codebase — in each case below the code permits what the invariant forbids.

| # | Invariant | Confirmed |
|---|---|---|
| **I1** | **A ticket document's price does not change after issuing/ticketing.** A price change is carried by a *new* document (re-issue), never by amending an issued one. | Sandeep, 2026-09-23 |
| **I2** | **A document issued under a ruleset version stays on that version.** If a document was ticketed under ruleset v2 and the ruleset is later republished to v3, retrieving that order must still evaluate it at v2. Only documents issued *after* the republish use v3. | Sandeep, 2026-09-23 |

**I1's standing against the code.** Three sources contradicted it while it was
parked as P9, and confirming it inverts what each one means:

- `update_tickets()` rewrites `ticket_base_fare_amount`, `ticket_tax_details` and
  `ticket_doc_source` on a post-ticketing retrieve (`db_api.py:1315`, `:1443`,
  `:2255-2261`). Under I1 those rewrites are no-ops in practice — the provider
  returns the same figures — so the code is **permissive where the data is not**.
- `content_rules.py:60-87` asserts the opposite in prose ("a retrieve of a
  ticketed order WILL rewrite the recorded amounts if the provider's base fare
  has moved. That is the documented intent, not an oversight"), and records that
  a freeze-at-ticketing boundary was proposed and reverted (006 Q2/FR-014). That
  docstring is now a **stale source** — see `stale-sources.md`.
- IATA/NDC permits repricing a ticketed Order. I1 is a statement about how
  NuFlights' actual carrier connections behave, not about what the standard
  allows. It holds because the partners behave classically, and it would need
  revisiting if that changed.

**What I1 does and does not cover.** It covers **price**, not **rules** — that is
**I2**'s job, and the two are independent.

**I2 is violated by the code today, and that is the difference between them.**
`resolve_published_ruleset` resolves to whatever is currently published on every
evaluation (`content_rules.py:7234-7238`), and evaluation runs on every retrieve
with no ticketing boundary. So a republish re-prices already-issued documents.
Where I1 is a rule the code *permits* breaking and the data never does, I2 is a
rule the system **breaks itself**, on a schedule set by whoever republishes a
ruleset. Logged as **F22**; the fix belongs in the order retrieval logic and
should be scoped with the audit-durability cluster (E3+E14+E15+E16), which shares
its root. **Not NF-004 scope.**

**Consequence: F19 drops from live to latent.** The reversal rebuilding its token
context from the live ticket is safe *because of I1*, not because the code
prevents divergence. That makes I1 load-bearing: if it ever stops holding, F19
becomes live again silently, with no test and no error to catch it. The guard in
NF-004 exists for exactly that reason.

## Gaps these decisions open

### G1 — Kyte `orderview_rust` fast path — RESOLVED 2026-09-16

`repos.md` records the Kyte fast path (`schema.rs:639`) as adapter-rs owned, and
it **never calls Python**, so D1 ("Python owns OrderView evaluation") left it
with no evaluator.

**Resolution: Kyte is in scope and not yet implemented.** Kyte serves order
create; the other order operations are the ones Python currently handles. So D1
describes where the *existing* Python-handled operations live — it is not a claim
that every order surface routes through Python. Kyte needs its own fee/discount
implementation, and it is the one order surface that cannot inherit Python's.

This closes NF-002's Q2 in the affirmative: the exclusion of rs OrderView does
leave a hole, and the hole gets filled rather than accepted.

### G2 — D3 makes NF-002's Q1 blocking

`[Per Segment]`, `[Per Ticket]` and `[Per Tkt Issue]` prorate by **unflown
segments on REFUND** — and only on REFUND. NF-002 Q1 asks which coupon signal
means "flown" (`coupon_status_code` vs
`current_coupon_flight_info_ref.flown_airline_pax_segment_ref`); the two can
disagree, and Python carries two non-overlapping status vocabularies besides.

While cancellation was out of scope, Q1 bit nothing — every in-scope surface was
pre-ticket, so `unflown_segment_count == segment_count` definitionally. **D3
removes that shelter.** Q1 must be resolved against a live refund payload before
any cancellation fee ships. Getting it wrong is silent: a wrong unflown count
produces a plausible number, not an error.

## Surface map

See `repos.md` for the full corrected table. Summary of where each surface must
land under D1–D3:

| Surface | Today | Target |
|---|---|---|
| OfferPrice | rs evaluates + injects; Python retired | unchanged |
| OrderQuote (reshop quote) | rs evaluates + injects | unchanged |
| OrderCreate / Change / Retrieve | **both** evaluate; generic persists | **generic only** (D1) |
| Kyte `orderview_rust` | rs evaluates + injects | **undecided — G1** |
| OrderReshop | **broken both sides, silent zero** | in scope (D2) |
| Ticketing | generic, as a granularity switch inside OrderView | unchanged |
| Cancellation | excluded by design | **in scope (D3)** — net-new |

## Open defects

**[open-defects.md](open-defects.md)** — the full defect inventory, researched
2026-09-18 across all six leaf working trees: 7 security/tenant-isolation items,
14 management-plane, 16 evaluation-plane, 8 functional, 8 non-functional, each
with a stable ID, a code anchor, a confirmed/suspected tag and a status column to
work through one at a time. It also carries ten **corrections to this repo's
record** that are code-verified but not yet applied, pending Sandeep's
confirmation.

Two clusters there are **independent of this migration** and need no D4/G1/G2
resolution first — the security cluster (§A) and the audit-durability composite
(E3+E14+E15+E16). Both are candidates for their own sub-epic rather than being
sequenced behind NF-003.

The four items below are superseded in part by that file — see its
"Relationship to `epic.md`" section for the mapping.

## Money-correctness fixes required before final commit

Carried per Sandeep's instruction 2026-09-16. None is a design question; all are
defects to close.

1. **`Decimal` → `FloatField` precision loss.** `bre_client.py` parses with
   `parse_float=decimal.Decimal`, then writes to float columns at
   `FullfilmentOrdersPriceAdjustments.adjustment_amount` and every
   `TicketOrgTransactions` money column (`models.py:1117-1124`).
2. **The `"discount"` output key is unverified** against a live BRE response —
   `bre_client.py:151-157` tries `("amount", "service_fee", "discount")` and its
   own comment flags `discount` as assumed. A discount rule could silently
   return `None`.
3. **`reference` must be sent on every evaluate call.** The BRE retention
   collector's index is `WHERE coalesce(reference,'') = ''`, so unreferenced
   audit rows are structurally inside the collection scan. Omitting it means
   losing the audit trail.
4. **`resolve_published_ruleset` (Python) vs `collapse_and_pin` (Rust)** is an
   unguarded parity surface — same job, two implementations, no fixtures.
5. **`ActivateIncentiveRule` is missing its global-ID decode.**
   `mutations.py:5516-5520` passes the raw Relay global ID straight into
   `OrgRelationshipRule.objects.get(id=...)` — no `Node.gid2id()` unwrap. Its
   sibling `DeleteIncentiveRule` does this correctly at `mutations.py:5549`. The
   frontend sends the ID Relay's own convention requires
   (`nf-app-account/src/routes/subscriptions/components/SubscriptionList.tsx:731`),
   so this isn't a frontend bug — the toggle 500s with `"OrgRelationshipRuleType@
   <uuid>" is not a valid UUID`. Confirmed live 2026-09-16 from an actual
   agency-admin error. **The activate/deactivate control for a subscription's
   ruleset mapping is currently broken outright**, not merely silent.
6. **Removing a subscription's ruleset mapping degrades silently, with no
   warning anywhere.** Confirmed general, not reshop-specific: both
   `available_master_rule()` (`content_rules.py:485-495`) and
   `rebuild_hop_rule_set_ids()` → `get_rules()` (`content_rules.py:7229`) treat
   an empty `is_active=True` queryset as a no-op — return `None` / skip the BRE
   block — never an exception, never a fallback ruleset. The removal UI in
   `nf-app-account` (`SubscriptionList.tsx:727-741`,
   `EditShareSubscriptionOverlay.tsx:167-180`) has no confirmation dialog and no
   fee/discount-impact warning; where `ConfirmationModal` exists in the same file
   it's wired to unrelated cascade-fee toggles only (`SubscriptionList.tsx:3427-
   3436`). Net effect: an admin can zero an agency's fees/discounts with one
   unconfirmed click and no error surfaces anywhere in the stack.

**Items 5 and 6 will be fixed together in their own sub-epic** — not yet
numbered (Sandeep, 2026-09-16). Item 5 is a straight bug fix inside
`nf-ndc-adapter-generic`; item 6 needs a cross-repo decision (guard at write
time in the backend vs. warn at removal time in `nf-app-account`, or both) so it
stays hub-planned rather than a leaf-repo-only fix.

## Open items

- ~~D4 detailed design — pending from Sandeep.~~ **Settled 2026-09-23**: `transaction_type` is a
  decision-table **input column** inside the ruleset graph (the engine matches on it, so the rule
  enforces it, not the UI), authored in `nf-app-home`, rendered properly in `nf-app-account` — the
  raw-editor fallback is not sufficient — and **mandatory, with no blank cells**, since a blank cell
  matches any value. A ruleset is **not** tied to a transaction type; it stays generic per kind and
  sub-type, and its decision table carries rows for whichever types apply. See D8 (restated) for why
  this does not, by itself, create a cancellation charge.
- G1 — Kyte ownership.
- G2 — NF-002 Q1, needs a live refund payload.
- Which repo implements reshop under D2 (rs `apply_orderreshop` stub vs generic's
  dead legacy path).
- Legacy `OrgMasterRuleSet` **authoring** surface is still live and writable
  (admin, `mutations.py:4717-5380`) while its evaluation path is dead. Retirement
  is unspecced.
- Items 5 & 6 above (broken `ActivateIncentiveRule`; silent-zero + no-warning on
  ruleset removal) need a sub-epic number and a leaf-spec home once Sandeep
  scopes it.
- NF-001 / NF-002 impact maps carry stale unticked boxes — the Rust work is done
  and tested. Needs a sweep.

## Definition of done

Not yet drawn. Requires D4, G1 and G2 resolved first.
