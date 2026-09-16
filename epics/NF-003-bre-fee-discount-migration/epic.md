---
epic: NF-003
title: Service fee & discount migration to GoRules ZEN rulesets
shape: program
status: draft — scope decided 2026-09-16, specs not yet written
created: 2026-09-16
contains: [NF-001, NF-002]
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

## Open items

- D4 detailed design — pending from Sandeep.
- G1 — Kyte ownership.
- G2 — NF-002 Q1, needs a live refund payload.
- Which repo implements reshop under D2 (rs `apply_orderreshop` stub vs generic's
  dead legacy path).
- Legacy `OrgMasterRuleSet` **authoring** surface is still live and writable
  (admin, `mutations.py:4717-5380`) while its evaluation path is dead. Retirement
  is unspecced.
- NF-001 / NF-002 impact maps carry stale unticked boxes — the Rust work is done
  and tested. Needs a sweep.

## Definition of done

Not yet drawn. Requires D4, G1 and G2 resolved first.
