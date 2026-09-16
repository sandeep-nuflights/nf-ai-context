# ADR-001 — Send both the raw counts and the derived tokens

**Status:** Accepted · **Date:** 2026-09-14 · **Epic:** NF-002

## Context

The §6.3 token table defines three transaction-scoped tokens over two raw inputs.
There are two ways to put that on the wire, and they are not equivalent.

**Raw only** — the adapter sends `segment_count` and `unflown_segment_count`; each
ruleset's JDM applies the transaction-type switch itself. This is what exists
today: `fixtures/master-corpus/mc-011-refund-proration.json` contains, inline in
an expression node,

    formula_type == 'PER_SEGMENT'
      ? (transaction_type == 'REFUND' ? unflown_segment_count : segment_count) * rate
      : base_fare * rate

**Derived only** — the adapter sends `per_segment` / `per_ticket` / `per_tkt_issue`
already resolved, and the raw counts never leave the adapter.

## Decision

**Both.** Six keys, snake_case, JSON numbers:

    segment_count            unflown_segment_count
    per_segment              per_ticket              per_tkt_issue
    total_fare

### Why the raw pair stays

`segment_count` and `unflown_segment_count` are not names being chosen here —
they are **already a live contract**. Two fixtures in the rules-engine repo read
those exact keys off the evaluation context today
(`fixtures/002-corpus/commission_per_segment.json`,
`fixtures/master-corpus/mc-011-refund-proration.json`). Dropping them to ship
"derived only" breaks working rulesets for no gain.

### Why the derived three are added anyway

The mc-011 expression above is the table's REFUND row, hand-transcribed into one
ruleset. Every ruleset using a per-segment formula needs the same transcription.
That is N copies of a rule that changed at least once during authoring — mc-011's
own metadata records the correction:

> build-plan MC-011 labels this 'SALE -> VOID'; per requirements-summary.md §6.3
> only REFUND prorates — VOID uses the full Segment Count.

Deriving once in the adapter means one implementation, two repos, covered by
shared fixtures. A ruleset author writes `per_segment * 2.25` and cannot get the
VOID row wrong, because there is no VOID row to get wrong.

### Why `total_fare` is in scope

`[Total Fare]` is in the table and neither adapter sends it. The BRE cannot derive
it either: tax keys are **dynamic per provider** (real captures show Amadeus with
`F6/ZR/G4/PZ/QA/R9/IN` and no `YQ` at all, against Farelogix's `GB/UB/ZR/YQ` —
`nf-ndc-adapter-rs/rules/types.rs:110`), so there is no generic sum a JDM can
write. The adapter already holds the full tax list at the moment it builds the
context. One line there; impossible downstream.

### Types

**JSON numbers, never strings.** `content_rules.py:6990` records this hitting
production on 2026-08-05: the engine does arithmetic directly on context values
(`base_fare*0.019`), a JSON string silently yields an empty result rather than an
error, and the failure is indistinguishable from "no rule matched".

`per_ticket` and `per_tkt_issue` are integers on SALE and VOID, and a ratio on
REFUND. Sending the raw pair alongside is what makes "maximum precision" reachable:
Rust's `amount_to_json` (`rules/context.rs`) degrades a non-integer `BigDecimal`
to `f64`, so `2/3` ships as a binary float. A ruleset needing exact division can
divide the two integers inside ZEN instead. Sending only the ratio forecloses that.

## Rollout

**Additive. No flag, no backfill, no migration.**

Context is free-form `serde_json::Value` at the BRE boundary
(`service/src/evaluate/handler.rs:80`). A context gaining keys no ruleset reads
produces byte-identical outcomes, so this ships dark and the money moves the first
time a ruleset references a new token — a ruleset-authoring event, not a deploy.

That is a genuinely different risk profile from NF-001's forward-only rollout, and
it is worth naming: **NF-002 cannot be rolled back by reverting the adapters** once
a ruleset depends on a token. The reversible window closes on ruleset authoring,
not on deploy.

## Consequences

- Six more keys in every evaluation context: in BRE audit records
  (`service/src/audit/record.rs:25`) and in every
  `_log_fee_discount_evaluation_failure` line (`content_rules.py:6745`).
- mc-011 keeps working unchanged, and gains a simpler equivalent it may be
  rewritten against later. That rewrite is not in this epic.
- Ruleset authors must be told the tokens exist. No UI change — the editor takes
  free-form context — but an unadvertised token is an unused token.
