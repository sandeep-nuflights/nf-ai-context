# ADR-002 — Fan-out reduction follows the customer-favourable direction

**Status:** Accepted · **Date:** 2026-09-11 · **Epic:** NF-001
**Amends:** FR-004, `nf-ndc-adapter-rs/specs/004-rule-evaluation/spec.md:119`

## Context

When a billable unit's fare components disagree on cabin or booking class — leg 1
Business/J, leg 2 Economy/Y — `QualifierMode::FanOut` (`rules/context.rs:148`)
produces one evaluation context per `(cabin, rbd)` pair. One billable unit, one
ruleset, N amounts back, because the ruleset conditions on cabin.

`reduce_across_contexts` (`rules/evaluate.rs:261`) picks one amount per `RuleKind`
across those N. It currently takes **`max` for fees and discounts alike**
(`if amount > *existing_amount`).

FR-004 specifies this, and twice flags it as undecided rather than reasoned:

> Under fan-out… the system MUST take the maximum per `(rule type, sub type)`
> across those contexts. **Unchanged from the existing contract, and a separate
> question from FR-012.**

Both directions are internally coherent, which is why it survived review:

- **max/max** — "the journey's highest tier governs": a fare touching Business is
  a Business fare for both fee and discount, with amount as a proxy for tier.
- **min-fee/max-discount** — "customer-favourable everywhere", consistent with
  Reductions 1 and 3 and with the FR-012 principle stated everywhere else.

## Decision

**Fan-out reduction takes `min` for `ServiceFee` and `max` for `Discount`**, the
same customer-favourable direction as every other reduction in the system.

## Why now, and not before

Under the old model this was nearly unreachable: Reduction 3 collapsed everything
to one fee and one discount per level, so a wrong pick at Reduction 2 was usually
overwritten downstream. **Deleting Reduction 3 (ADR-001) exposes Reduction 2's
output directly to the ledger** — six outcomes survive where two did, each
carrying whatever Reduction 2 chose. ADR-001 is what makes this reachable, so it
is what makes it worth deciding.

It bites only when all three hold: `QualifierMode::FanOut` rather than `Arrays`,
a billable unit spanning multiple cabin/RBD, and a ruleset conditioning on cabin.
Narrow, but real, and now visible in recorded money.

## Consequences

- This is a **contract change**, not a bug fix. FR-004 says "unchanged from the
  existing contract"; that sentence is now false and the FR must be amended to
  say what changed and when — not quietly edited.
- **Rust-only. Verified 2026-09-11.** The Python BRE path has no fan-out axis:
  `content_rules.py:6869` builds one context per entry with scalar `"cabin"` and
  `"rbd"` and makes one `bre_evaluate` call, so it never holds two amounts for the
  same ruleset along this axis. Recorded as an exclusion in `impact-map.md`;
  `nf001-03` is a Rust-only fixture, not a parity fixture.
- No rollout concern beyond ADR-001's: forward-only, same window.

## Unrelated gap found while verifying (2026-09-11)

Rust fans out on **both** surfaces — `rules/context.rs:148` (OfferPrice) and
`rules/order_context.rs:406` (OrderView). Python's order path does not. The same
order surface therefore fans out in one implementation and not the other, and can
produce different amounts when one fare spans several cabins.

**Not caused by NF-001 and not fixed by it.** `nf-ndc-adapter-generic`'s 006
FR-013 removes Rust's order-side injection altogether, after which order-side is
Python-only (no fan-out) and OfferPrice is Rust-only (fan-out, per this ADR) — and
the divergence is moot. Recorded so it is not rediscovered as a defect in the
window before FR-013 lands.
