# ADR-002 — Segment count has two sources, chosen by whether a ticket exists

**Status:** Accepted · **Date:** 2026-09-14 · **Epic:** NF-002

## Context

"How do I count segments?" looks like one question with one answer per endpoint.
It is not. Reading the four in-scope extractors against the wire types shows two
structurally different origins, available at different times.

**Itinerary source.** `fare_detail.fare_component[*].pax_segment_ref_id` — the
same references `extract_travel_date` (`rules/context.rs:~620`) already walks to
find the earliest departure. Available on every surface that has a fare detail,
which is all of them.

**Coupon source.** `ticket_doc_info.ticket[*].coupon[*]` —
`TicketDocInfoType.ticket` is `Option<Vec<TicketType>>` and `TicketType.coupon` is
a plain `Vec<CouponType>` (`ticket_doc_info_type.rs:68`, `ticket_type.rs:22`).
Available only once a ticket has been issued.

These do not agree in general. A reissue changes coupons without changing the
itinerary's fare-component structure, and §6.3 is explicit that its
`[Segment Count]` means **"segment coupons in tickets"** — coupons, not legs.

## Decision

**Count from coupons wherever a ticket exists; count from the itinerary
otherwise.** The selector is the presence of a ticket document, not the endpoint.

| Surface | Ticket? | Source |
|---|---|---|
| OfferPrice (rs) | no | itinerary |
| OrderQuote (rs) | no | itinerary |
| OrderCreate/Change/Retrieve — order item (generic) | no | itinerary |
| OrderCreate/Change/Retrieve — ticket doc (generic) | yes | coupons |

Three of four use the itinerary source, so it is written **once** as a shared
helper in `rules/context.rs` and reused by `quote_context.rs`, exactly as base
fare, taxes, PTC, cabin/RBD and travel date already are. The coupon source exists
only in Python, because the only in-scope ticketed surface is Python's.

### Pre-ticket, unflown equals total

On every itinerary-source surface, `unflown_segment_count == segment_count`
definitionally — nothing can have flown before the sale. This is not a default or
a fallback; it is the only value that can be correct.

**Consequence worth asserting rather than assuming:** with `transaction_type` now
caller-supplied, a REFUND arriving on OfferPrice or OrderQuote would compute
`per_ticket = 1` and `per_segment = segment_count`. Either that cannot happen, in
which case assert it, or it can, in which case the pre-ticket surfaces are wrong
for it. Do not let this be decided by accident.

### Segments, not journeys

The itinerary counter counts **distinct `pax_segment_ref_id`** — flight segments.
It does **not** count `origin_dest` / `pax_journey` entries, which are O&Ds: a
round trip with one connection each way is 4 segments but 2 journeys.

This matters because the legacy engine disagrees.
`fee_engine.py:116` `_parse_segment_count` reads `txn_iternarty_od_segment_count`
and takes `split(",")[0]` — an **O&D** count. On the itinerary above, the legacy
engine yields 2 where this epic yields 4, and a `[Per Segment] * 2.25` commission
differs by a factor of two. Recorded as epic Q3; not resolved here.

### Conjunction tickets

`TicketDocInfoType` is documented as "a group of **1 to 4** Tickets for a single
Origin Destination and a single Passenger", and `ticket` is a `Vec` — an itinerary
over 4 coupons spans multiple booklets. `segment_count` is the sum across all
booklets, per
`nf-ndc-adapter-rs/docs/rules-engine/orderview-injection-analysis.md:270`.

`TicketType.primary_doc_ind` exists for identifying the lead booklet and **nothing
in either codebase reads it today**. It becomes relevant to ADR-003's first-issue
comparison; see that ADR.

## Consequences

- One new helper in `rules/context.rs`, used by two rs surfaces; one new counter
  in Python's `_cascaded_pricing_for_order_item`; one in the coupon loop that
  already runs at `content_rules.py:6453` for the `exchanged` flag.
- The coupon counter's unflown half is **blocked on Q1** — which coupon signal
  means "flown". The total half is not blocked and can land first.
- Parity fixtures must cover both sources, including a case where they disagree,
  or the split silently becomes "whichever the test happened to exercise".
