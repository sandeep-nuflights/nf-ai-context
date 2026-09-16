# NF-002 token fixtures

**Adapter-level** fixtures, not BRE fixtures — same posture as NF-001's. They do
not follow the `templateJdm` / `ruleSetSlotData` shape of
`nf-ndc-connect-rules-engine/fixtures/master-corpus/`, because they exercise
nothing the BRE does.

What they pin is the step **before** the BRE is called: given a ticket or an
itinerary and a transaction type, what six numbers go into the evaluation context?
That derivation is written twice — Rust (`rules/context.rs`) and Python
(`ndc/content_rules.py`) — so it is stated once here and asserted in both.

Where NF-001's fixtures assert a *reduction over amounts the BRE returned*, these
assert *inputs the BRE never sees the provenance of*. A wrong value here is
invisible downstream: the BRE multiplies whatever it is given and returns a
plausible number.

## Shape

```jsonc
{
  "testLabel": "...",
  "note": "...",
  "given": {
    "source": "itinerary" | "coupons",   // ADR-002 selector
    "transaction_type": "SALE" | "VOID" | "REFUND",
    // itinerary source:
    "fare_components": [ { "pax_segment_ref_id": [...] } ],
    "previous_ticket_number": null,
    // coupon source:
    "tickets": [ { "ticket_number": "...", "coupons": [ {...} ] } ],
    "original_issue_ticket_number": "..." | null
  },
  "expect": { "segment_count": n, "unflown_segment_count": n,
              "per_segment": n, "per_ticket": n, "per_tkt_issue": n }
}
```

Two variants on `expect`:

- `expectBySurface` — when the *same* input has different correct answers on
  different surfaces. Only `nf002-06` needs this, and the reason is a wire-type
  asymmetry, not a disagreement (ADR-004).
- `null` with a `status: "blocked"` — an expectation that cannot be written yet.
  `nf002-08` is the only one. It is a fixture precisely so the gap fails a run
  instead of being forgotten.

**Ratios are written as decimal strings**, not JSON floats, so the fixture states
the exact value rather than whichever float the serialiser chose. §6.3 says
"maximum precision"; `0.333333333333333333` in `nf002-04` is deliberate and is the
reason ADR-001 keeps the raw integer pair on the wire alongside the ratio. How
each repo compares against it is that repo's business — but neither may round the
fixture to make a test pass.

## Running

Both repos read these from the epic folder. Neither merges alone: the gate is
identical values across implementations, 0 discrepancies.

| Fixture | Asserts | Surfaces |
|---|---|---|
| `nf002-01` | SALE pre-ticket: full values, unflown == total | itinerary (all) |
| `nf002-02` | **VOID does not prorate** — full Segment Count with 2 coupons flown | coupons (generic) |
| `nf002-03` | REFUND prorates — same ticket as 02, different answer | coupons (generic) |
| `nf002-04` | REFUND of a reissue — `per_ticket` vs `per_tkt_issue` diverge | coupons (generic) |
| `nf002-05` | **NF self-referential `original_issue_info`** (ADR-003) | coupons (generic) |
| `nf002-06` | No `pax_segment_ref_id` — fallback where it exists, error where it doesn't (ADR-004) | itinerary (all) |
| `nf002-07` | Conjunction booklets summed. **Provisional** — no real payload yet | coupons (generic) |
| `nf002-08` | Flown signals disagree. **Blocked on Q1** — expectations unfilled | coupons (generic) |

`nf002-02` and `nf002-03` are a **pair** and should be read together: identical
ticket, identical coupon states, one field different, and `per_segment` goes from
4 to 2. Splitting them across test files loses the point.

`nf002-05` is the one most likely to be dropped as redundant by someone
implementing from the IATA reading alone. It is not redundant — it is the only
fixture that fails if the first-issue test is written as bare absence, and it
fails on *every NF-issued ticket in production*.
