# ADR-001 — Resolve Q4: a winner per (ruleType, subType)

**Status:** Accepted · **Date:** 2026-09-11 · **Epic:** NF-001
**Supersedes:** Q4 deferral of 2026-09-02 and the sub-type collapse of 2026-08-06

## Context

Two readings of fee/discount reduction have coexisted since 2026-08-06.

**The product documents** (*"Rules, Rules Engine and Evaluation"* 2026-07-30;
*"Discounts and Service Fees - OrderView"* 2026-07-28) reduce among rules sharing
the same Rule Type **and Rule Sub Type**, state twice that "multiple
discounts/service fees can be applied to a single order item or document", and
render `SUM(… Adjustment Sub Type = [Sub type])` as one entry per sub-type.

**The implementation** collapses across sub-types, yielding exactly one fee and
one discount per chain level. Rust annotates this "added 2026-08-06"; Python
mirrors it at `content_rules.py:7036` with a comment citing
`evaluate.rs:342-343` as the authority.

The two readings produce different customer totals: **1827** (per sub-type) vs
**1855** (collapsed) on the reference order.

Q4 recorded the conflict and deferred it — "proceed as built… **Needs
confirming**: that the documents are stale rather than the implementation wrong."
Research R13 offered a reconciling reading (all candidates recorded, one marked
`Applied` per rule type, only `Applied` counting toward the total) under which
the totals would not disagree at all. That reading was never confirmed, because
it turns on whether the documents' `SUM(…)` filters on `Applied`, which they do
not state.

## Decision

**The documents are correct. The implementation is wrong and changes.**

A winner is selected per `(ruleType, subType)`: `min` within each ServiceFee
sub-type, `max` within each Discount sub-type. Surviving winners are summed into
the level total. R13's `Applied`-filter reading is **not** adopted — it was a
reading, not a confirmation, and it preserved a total we are now changing anyway.

Reduction 1 (across rulesets within one slot) is unaffected and already correct
in both repos. Reduction 3 (across sub-types) is deleted.

## Rollout

**Forward-only. No flag, no backfill, no migration.**

This path is not serving production traffic. Next tickets and offers are
calculated under the new reduction; nothing already recorded is revisited. This
is what makes a money-affecting change cheap here, and the window will not stay
open — once real orders carry recorded amounts, any further change to reduction
semantics needs a backfill story and this ADR should not be cited as precedent.

## Consequences

- Customer totals change (1855 -> 1827 on the reference order). Intended.
- Up to 6 outcomes per level where there were 2. See `impact-map.md` for the
  downstream surface.
- Both repos change together, on the same fixtures. The surfaces differ — Rust
  prices the offer, Python records the order — but they must not disagree, or a
  customer sees one number quoted and another recorded.
- `nf-ndc-adapter-rs/specs/004-rule-evaluation` FR-003 must be amended: "at most
  one outcome per `(rule type, sub type)` per level" still holds, but the
  sentence that followed it into Reduction 3 does not.
- The two product documents are confirmed authoritative and need no edit.

## Corroboration (added 2026-09-11, after code triage)

Q4 framed the conflict as "documents vs implementation" and asked whether the
documents were stale. Triage of `nf-ndc-adapter-generic` found a third witness
that Q4 did not consider: **the legacy pre-BRE rule path.**

`offer_item_price_adjustment`, `reshop_offer_item_price_adjustment` and
`reprice_offer_item_price_adjustment` all resolve rules through
`available_master_rule`, and all three reduce **per sub-kind and sum**:

    for sub_kind, rule_value in value.items():
        max_discount = max(rule_value, key=lambda r: r["value"])
        total_discount = total_discount + max_discount["value"]

That is NF-001's semantics, and it predates the BRE path entirely.

So the documents were never stale. The behaviour they describe is what the system
did before BRE, what the legacy path still does today, and what
`get_rules` — the BRE ledger writer — is still written to do. The 2026-08-06
collapse is the only place that diverged, and it diverged in one function.

This removes the remaining doubt in Q4's "**Needs confirming**: that the documents
are stale rather than the implementation wrong." The implementation was wrong.
