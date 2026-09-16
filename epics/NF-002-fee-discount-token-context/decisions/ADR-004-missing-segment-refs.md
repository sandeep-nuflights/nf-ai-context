# ADR-004 — A fare component with no segment reference is an error, never zero

**Status:** Accepted · **Date:** 2026-09-14 · **Epic:** NF-002

## Context

The itinerary counter (ADR-002) counts distinct `pax_segment_ref_id` across a
fare detail's components. **That field is not always present.**

`resolve_component_origin_destination` (`rules/context.rs:486`) documents a
Farelogix-shaped payload carrying no segment reference on the fare component at
all, and falls back to the offer-level journey association:
`priced_offer.journey_overview.journey_price_class[*].pax_journey_ref_id` →
`origin_dest`. The fallback is verified against real traversal code, not guessed.

A naive counter on that shape returns **0 segments**, which makes
`per_segment = 0`, which makes any per-segment fee `0.00`. No error. No log.
Indistinguishable from "no rule matched".

The fallback is also **not uniformly available**. `order_context.rs:369` and
`:625` both pass `journey_overview: None` deliberately, because
`OrderedOrderType` has no such field — an order item has nothing to fall back to.

## Decision

**Zero segments is an extraction error, on every surface.** `AppError::RulesExtraction`
in Rust, an entry in `extraction_errors` in Python — the same channel each repo
already uses when a required value cannot be resolved.

Where a fallback exists, try it first:

| Surface | Primary | Fallback | If both fail |
|---|---|---|---|
| OfferPrice (rs) | component `pax_segment_ref_id` | `journey_overview` → `pax_journey` → segments | error |
| OrderQuote (rs) | component `pax_segment_ref_id` | same — `quote_context.rs:304` already passes a journey overview | error |
| Order item (generic) | component `pax_segment_ref_id` | **none available** | error |

This follows the rule `rules/context.rs:13` already states for this module, and
applies it to a value the module did not previously carry.

## Why not "fall back to 1"

Because it is plausible. A silently-fabricated `per_segment = 1` on a 4-segment
itinerary underbills by 75% and looks like a correctly applied fee in every log
and every ledger row. An error is loud, attributable to one fare detail, and — on
both existing paths — already handled: Python's
`evaluate_bre_rules_for_order` skips that entry and records a `RecordingFailure`
rather than failing the order (`content_rules.py:6800`, research R7), and Rust's
caller turns the error into "skip this unit, continue".

The cost of erroring is one unpriced fare detail, reported. The cost of
fabricating is an unbounded number of underbilled ones, unreported.

## Consequences

- Python's order-item surface has no fallback, so a Farelogix-shaped order item
  will error where the equivalent OfferPrice call succeeds. That asymmetry is
  real and is a property of the wire types, not of this decision — record it in
  generic's leaf spec rather than closing it by fabricating a count.
- `extract_travel_date` (`rules/context.rs:~620`) already tolerates a component
  with no refs (`continue`) and errors only when **no** component had any. The
  segment counter should share that shape — same traversal, same tolerance, same
  failure point — rather than inventing a second policy over the same field.
- A fixture for the Farelogix shape is required in `./fixtures`, or this decision
  is untested on the only payload shape that triggers it.
