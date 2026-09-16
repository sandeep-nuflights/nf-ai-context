---
epic: NF-001
parent: NF-003
title: Sub-type-scoped fee/discount aggregation
shape: mirror
status: approved
created: 2026-09-11
resolves: Q4 (nf-ndc-adapter-generic/specs/006-standardize-fee-discount/spec.md:157)
amends: FR-004 (nf-ndc-adapter-rs/specs/004-rule-evaluation/spec.md:119)
parity:
  group: fee-discount-reduction
  members: [nf-ndc-adapter-generic, nf-ndc-adapter-rs]
  fixtures: ./fixtures
  surfaces:
    nf-ndc-adapter-rs:      [OfferPrice, OrderReshop, Kyte orderview_rust fast path]
    nf-ndc-adapter-generic: [OrderCreate, OrderChange, OrderRetrieve]
not-affected: [nf-ndc-connect-rules-engine, nf-app-home, nf-app-account, nf-app-workbench]
money-impact: yes        # reference order 1855 -> 1827
rollout: forward-only    # see ADR-001 §Rollout
---

# Sub-type-scoped fee/discount aggregation

## Requirement

A winner is selected per `(ruleType, subType)` — not per `ruleType`.

    SERVICEFEE / {STANDARD, EXTRA, ADDITIONAL}   -> min(amount) within each sub-type
    DISCOUNT   / {STANDARD, PLB, CORPORATE_DEAL} -> max(amount) within each sub-type

Multiple rulesets may match one `(type, sub-type)` slot; that slot still yields
exactly one winner. What changes is that **sub-types no longer compete with each
other**. Every surviving winner is summed into the level's total.

## Why now

Q4 was deferred "proceed as built" on 2026-09-02 pending business confirmation.
The product documents — *"Rules, Rules Engine and Evaluation"* (2026-07-30) and
*"Discounts and Service Fees - OrderView"* (2026-07-28) — reduce among rules
sharing the same Rule Type **and Rule Sub Type**. The collapse across sub-types
postdates both (Rust annotates it "added 2026-08-06") and was treated as
superseding them.

This epic is that confirmation, resolved **in favour of the product documents**.
The documents were right; the implementation diverged. See ADR-001.

## Reduction model

| # | Axis | Direction | Status |
|---|------|-----------|--------|
| 1 | across rulesets, within one `(type, sub-type)` | min fee / max discount | **keep** |
| 2 | across fan-out contexts (cabin/RBD of same ruleset) | max (both) -> **min fee / max discount** | **change** (ADR-002) |
| 3 | across sub-types, within one ruleType | min fee / max discount | **delete** (ADR-001) |
| 4 | across chain levels | sum | **keep** |

Net effect per level: up to 3 fee + 3 discount outcomes, where there was 1 + 1.

## Scope boundaries

- **nf-ndc-connect-rules-engine is not affected.** The BRE returns per-ruleset
  results; all cross-ruleset reduction is caller-side. No BRE change, no new
  endpoint, no contract version bump.
- **nf-app-home `005-hit-policy-aggregation-toggle` is a different layer.**
  ZEN's Collect hit policy plus aggregation node reduces **rows within one
  ruleset**. This epic reduces **across rulesets**. Both use min/max on the same
  rule types, which makes them easy to confuse. They compose; they do not
  overlap. Do not merge them.
- **Q5 (tie-break divergence) stays accepted as-is.** Ties remain possible across
  rulesets inside a single slot. The amount is identical either way; only
  recorded provenance differs.

## Definition of done

The epic is done when every box in `impact-map.md` is ticked and both repos
produce identical results on `./fixtures`.
