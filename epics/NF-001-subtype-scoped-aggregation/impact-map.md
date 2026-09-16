# NF-001 — Impact map

## Code sites

| Repo | Site | Change | ADR |
|---|---|---|---|
| nf-ndc-adapter-rs | `nf_ndc/src/rules/evaluate.rs:305` `reduce_across_sub_types` | **Delete** fn, its call at ~line 200, and both `tracing::warn!` blocks | 001 |
| nf-ndc-adapter-rs | `nf_ndc/src/rules/evaluate.rs:261` `reduce_across_contexts` | Split direction: `min` for `ServiceFee`, `max` for `Discount` | 002 |
| nf-ndc-adapter-rs | `nf_ndc/src/rules/evaluate.rs:210` `reduce_across_rulesets` | **No change** — already groups by `RuleKind` = `(ruleType, subType)` | — |
| nf-ndc-adapter-generic | `backend/ndc/content_rules.py:7036-7048` (`evaluate_bre_rules_for_order`) | Group candidates by `sub_type`, select winner within each group | 001 |

**Python is a one-site change.** See the triage below for why.

`RuleKind` is a six-variant enum that already *is* the `(ruleType, subType)` pair
(`ServiceFeeStandard`, `ServiceFeeExtra`, `ServiceFeeAdditional`, `DiscountStandard`,
`DiscountCorporateDeal`, `DiscountPlb`). On the Python side
`discounts[dict_key][sub_type]` is already keyed by sub-type. **Both codebases
already carry the dimension the collapse was discarding** — which is why this
reversal is structurally cheap and why the risk sits entirely in the totals.

## Triage of the other min/max sites (2026-09-11)

All four were checked. **None needs changing.**

| Site | Function | Rule source | Verdict |
|---|---|---|---|
| 7165 / 7223 | `get_rules` (7078) | BRE | **In BRE path, but already correct** |
| 1218 / 1226 | `offer_item_price_adjustment` (1179) | `available_master_rule` | Legacy — out of scope |
| 3977 / 3985 | `reshop_offer_item_price_adjustment` (3936) | `available_master_rule` | Legacy — out of scope |
| 4073 / 4081 | `reprice_offer_item_price_adjustment` (4032) | `available_master_rule` | Legacy — out of scope |

### 7165 / 7223 — already correct, do not touch

`get_rules` iterates `for sub_kind, rule_value in value.items()` and emits one
ledger `field_set` per sub-kind, carrying `"adjustment_sub_kind": sub_kind` and
`rule_status: APPLIED`. It takes `max` within each discount sub-kind and `min`
within each fee sub-kind — **exactly NF-001's semantics, already.**

The only reason it emits a single row today is that
`evaluate_bre_rules_for_order` puts **one** key into `discounts[dict_key]` /
`fees[dict_key]` — the single cross-sub-type winner. Fix site 7036 and this loop
produces one APPLIED row per sub-type by construction, with correct
`adjustment_sub_kind` and correct `bre_evaluation_log_id` provenance on each.

This is the single most important finding of the triage: **the Python ledger
writer never needed changing. One upstream site was starving it.**

### 1218 / 1226, 3977 / 3985, 4073 / 4081 — legacy, excluded

All three resolve rules through `available_master_rule` +
`validate_rule_with_{priced_offer,reshop_priced_offer,reprice_priced_offer}` —
the pre-BRE engine. Excluded per the instruction to fix only BRE-path code.

Worth recording: all three **already** reduce per sub-kind and sum
(`total_discount += max(...)` per `sub_kind`). The legacy implementation has
always matched the product documents. It is the BRE path that diverged on
2026-08-06. Corroborates ADR-001 — see that ADR's Corroboration section.

## Adopter checklist

Fan-out: one decision, two repos, neither upstream. The epic is not done until
every box is ticked.

- [ ] **rs** — Reduction 3 deleted, call site updated
- [ ] **rs** — Reduction 2 direction split (ADR-002) — Rust-only. **One edit** at
      `evaluate.rs:261`, reached by four call paths in `rules/mod.rs` (778 OfferPrice,
      1072 OrderView order-item, 1198 OrderView document, 1466 Reshop quote). Acceptance
      must cover all four, not just OfferPrice.
- [ ] **rs** — `specs/004-rule-evaluation` FR-003/FR-004 amended, not silently contradicted
- [ ] **generic** — per-sub-type grouping at `content_rules.py:7036`
- [ ] **generic** — confirm `get_rules` now emits one APPLIED row per sub-type (no code change; assert it)
- [ ] **generic** — Q4 row in `006-standardize-fee-discount/spec.md:157` flipped to Resolved, linked to ADR-001
- [ ] **both** — `./fixtures` pass identically, 0 discrepancies
- [ ] **both** — long Q4 comment blocks replaced with an ADR pointer (they become wrong on merge)
- [ ] **docs** — the two product documents confirmed authoritative and left as-is

## Downstream blast radius

Up to 6 outcomes per level where there were 2. Everything that assumed "one fee,
one discount per level" needs checking in both repos:

- PriceAdjustment ledger row count per level (Python: now driven entirely by how
  many sub-type keys site 7036 populates)
- level-total summation — `update_seller_prices` (py); `rules/inject.rs` (rs) **checked
  2026-09-11: already multi-outcome.** `apply_to_fare_detail` iterates
  `for outcome in outcomes` and accumulates rather than taking one, and its label
  machinery (`adjustment_label(sub_type, …)`, `accumulate_discount_label` keyed by
  `sub_type`, `append_discount`, `sum_fee`) is sub-type aware throughout. No change
  expected from deleting Reduction 3 — but assert it, do not assume it.
- `backend/content/utils.py`: `get_adjustment_aggregate`, `get_ticket_price_adj`,
  `get_order_items_price_adj`
- GraphQL OrderView adjustment arrays — consumers are **nf-app-workbench** and
  **nf-app-account**; neither needs a code change, but both will render more rows
- audit trail: T037 (recording rejected candidates as QUALIFIED) becomes more
  valuable, not less — `get_rules` already writes `rule_status: APPLIED`, so the
  QUALIFIED counterpart is the only missing half

## Exclusions

| Repo | Scope | Reason |
|---|---|---|
| nf-ndc-connect-rules-engine | all | cross-ruleset reduction is caller-side; BRE unchanged |
| nf-app-home | hit-policy aggregation | different layer (within-ruleset rows, not across rulesets) |
| nf-ndc-adapter-generic | `offer_item_price_adjustment`, `reshop_…`, `reprice_…` | legacy `available_master_rule` path, not BRE; already per-sub-type anyway |
| nf-ndc-adapter-generic | fan-out reduction (ADR-002) | **no fan-out axis** — verified 2026-09-11: `content_rules.py:6869` sends one context per entry with scalar `cabin`/`rbd`. Rust-only change. |
| nf-ndc-adapter-generic | OfferPrice | Python OfferPrice evaluation was retired; Rust owns this surface |
| nf-ndc-adapter-rs | OrderCreate/Change/Retrieve injection | being removed per generic/006 FR-013; Python owns this surface |
