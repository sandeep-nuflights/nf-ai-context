---
epic: NF-002
parent: NF-003
title: Per-ticket / per-segment token context for fee & discount formulas
shape: mirror
status: draft
created: 2026-09-14
implements: "F - Commission and Service Fee Integration" §6.3 token table
  (restated at nf-ndc-connect-rules-engine/docs/nf-bre-requirements-summary.md:163-165)
resolves: D3, D4 (nf-ndc-adapter-rs/docs/rules-engine/orderview-injection-analysis.md:437-438)
parity:
  group: fee-discount-tokens
  members: [nf-ndc-adapter-generic, nf-ndc-adapter-rs]
  fixtures: ./fixtures
  surfaces:
    nf-ndc-adapter-rs:      [OfferPrice, OrderQuote]
    nf-ndc-adapter-generic: [OrderCreate, OrderChange, OrderRetrieve]
not-affected: [nf-ndc-connect-rules-engine, nf-app-home, nf-app-account, nf-app-workbench]
money-impact: yes        # no existing amount moves; each new token is a direct
                         # multiplier the moment one ruleset references it
rollout: additive        # see ADR-001 §Rollout
blocked-by: Q1           # flown/unflown signal — needs live refund data
---

# Per-ticket / per-segment token context

## Blocking NF-004 — confirmed 2026-09-23

NF-002's **Python side blocks all of NF-004's spec 011.** Verified by grep across
`content_rules.py`, `content_state.py` and `bre_client.py`: **none** of
`per_segment`, `per_ticket`, `per_tkt_issue`, `segment_count` or
`unflown_segment_count` is sent. The Python evaluation context
(`content_rules.py:6981-7003`) stops at `base_fare`, `currency`, the per-tax-code
keys and `issue_date`.

Rust sends all five (`context.rs:149-150`, `:177-181`). **NF-004 is Python-owned
by evidence**, so a reversal cannot prorate — and today a `[Per Segment]` rule on
a Python-priced order references a variable that never arrives, which in ZEN is
null, which is a **silent zero rather than an error**.

This reclassifies NF-002 from a parallel sub-epic to a **prerequisite**. Recorded
as NF-004's **A9**.

## Requirement

Service fee and commission formulas are written over pre-defined tokens. Three of
them — `[Per Segment]`, `[Per Ticket]`, `[Per Tkt Issue]` — are not in any
evaluation context either adapter sends today, so any ruleset using one evaluates
against an absent key.

The tokens, per transaction type:

| Token | SALE | VOID | REFUND |
|---|---|---|---|
| `[Base Fare]` | base fare | base fare | base fare |
| `[YQ]` / `[YR]` | tax component, default `0` | same | same |
| `[Total Fare]` | base + all taxes | same | same |
| `[Per Segment]` | `[Segment Count]` | `[Segment Count]` | `[Unflown Segment Count]` |
| `[Per Ticket]` | `1` | `1` | `[Unflown] / [Segment Count]`, max precision |
| `[Per Tkt Issue]` | `1` if first issue else `0` | same | `[Unflown] / [Segment Count]` if first issue else `0` |

`[Base Fare]`, `[YQ]` and `[YR]` already ship on every surface. `[Total Fare]` and
the bottom three do not. This epic adds them.

**Note the asymmetry the model is built around:** on `REFUND` — and only on
`REFUND` — the segment and ticket tokens prorate by unflown segments. `VOID` takes
the **full** Segment Count. `mc-011`'s own metadata records that the build plan got
this backwards once already.

> **Contested and confirmed, 2026-09-22.** While scoping NF-004 the legacy
> engine was found to disagree: `nf-ndc-adapter-generic/backend/content/fee_engine.py:211-212`
> puts VOID and REFUND in **one branch**, both prorating by the unflown count.
> `nf-ndc-adapter-rs` (`context.rs:785-803`) agrees with this table — full count
> on VOID. **Sandeep confirmed this table is correct**, so `fee_engine.py:211-212`
> is a live defect, not the reference behaviour (logged as **F15** in NF-003's
> `open-defects.md`). This table is the single source; do not re-derive the
> asymmetry from legacy output.
>
> It bites only when a coupon has already flown at void time — otherwise
> `unflown == segment_count` and the two agree. Silent when wrong: a plausible
> number, not an error.

## Two sources, not one

The single fact that shapes this epic:

> **Segment count has two structurally different origins, and which one applies
> depends on whether a ticket exists yet — not on which endpoint you are in.**

- **Itinerary source** (pre-ticket) — distinct `pax_segment_ref_id` across
  `fare_detail.fare_component[*]`.
- **Coupon source** (post-ticket) — `Σ` over `ticket_doc_info.ticket[*].coupon[*]`.

They are not the same number and may legitimately disagree: a reissue changes
coupons without changing the itinerary's component structure. Pre-ticket,
`[Unflown Segment Count]` equals `[Segment Count]` definitionally — nothing can
have flown before the sale. See ADR-002.

## Why now

Two independent unblocks landed at once.

**`transaction_type` becomes caller-supplied.** Every token above is
transaction-scoped, and `OrderViewRs` carries no transaction discriminator —
extraction genuinely cannot discover it (analysis doc §7). D4 asked where it
comes from; the answer is that the caller knows which use case it is (OrderCreate
and OrderChange are SALE; a cancel is VOID or REFUND depending on the void time
limit) and passes it in. This is a decision, not a discovery, and it is now made.

In practice it varies **only on the Python side** — both in-scope rs surfaces are
definitionally sales. See `impact-map.md` §"Where `transaction_type` actually
varies".

**The BRE contract does not need to change.** `service/src/evaluate/handler.rs:80`
types the context as free-form `serde_json::Value`, so new keys are additive with
no version bump, no new endpoint and no coordination with ruleset authors beyond
telling them the tokens exist.

What is left is extraction — which is the half that can silently produce a wrong
*number* rather than a wrong *match*. Q1 below is the reason this is `draft` and
not `approved`.

## Token contract

Five new keys, snake_case, JSON numbers. See ADR-001 for the full rationale.

    segment_count            int    raw input, already consumed by live fixtures
    unflown_segment_count    int    raw input, already consumed by live fixtures
    per_segment              number derived per the table above
    per_ticket               number derived per the table above
    per_tkt_issue            number derived per the table above
    total_fare               number base + all taxes

`segment_count` and `unflown_segment_count` are **not** new names to choose —
they are already a live contract. `fixtures/002-corpus/commission_per_segment.json`
and `fixtures/master-corpus/mc-011-refund-proration.json` both read those exact
keys off the context today. Do not rename them.

The derived three are added *on top* so a ruleset author writes `per_segment * 2.25`
instead of reimplementing the REFUND conditional in every JDM — which is precisely
what mc-011 does inline today, and precisely the duplication that turns one
misreading of the table into N wrong rulesets.

### Display name vs. context key (ADR-006)

The six keys above are the wire contract — what a formula's variable lookup must
match, character for character. They are not what a human is shown. Display name,
standardised across `nf-app-home`'s template builder and `nf-app-account`'s
ruleset editor, is PascalCase, no spaces, no abbreviation:

    SegmentCount    UnflownSegmentCount    PerSegment
    PerTicket       PerTicketIssue         TotalFare

This was not decided speculatively: a live ruleset (`org=T-EK`,
`ruleset_id=851822da-5ba2-4571-a1b9-5fb90bac8e82`) authored `Persegment*10`.
The typo entered via `nf-app-home`'s free-text "Additional variables" box
(validated only against identifier syntax, not against real `nf_ndc` context
keys), from where it rode into `nf-app-account`'s ruleset editor as an
already-"valid" allow-list entry — that editor's own allow-list check was
working correctly throughout; it trusted a poisoned list. The result: a
decision-table output cell defaults a missing/mismatched identifier to `0` by
design (`nf-ndc-connect-rules-engine`'s `null_default.rs`), so the typo produced
a plausible wrong number, not an error. ADR-001 predicted exactly this failure
mode under its own Consequences ("an unadvertised token is an unused token").
ADR-006 ships two code changes — these six tokens are now unconditionally
available (not merely suggested) in every output column's variable list in
`nf-app-home`, and rendered with the PascalCase labels above once used in
`nf-app-account` — plus records that fixing the already-live ruleset (both its
template's allow-list and its own formula text) remains a manual, per-ruleset
content action, not something either code change performs automatically.

## Scope boundaries

- **nf-ndc-connect-rules-engine is not affected.** Context is free-form JSON;
  derivation is caller-side. No BRE change, no contract bump. `mc-011` keeps
  working unchanged and gains a simpler equivalent it may be rewritten against
  later — that rewrite is not in this epic.
- **nf-ndc-adapter-rs OrderView is excluded** — per the same surface ownership
  NF-001 records: Python owns OrderCreate/Change/Retrieve, and Rust's order-side
  injection is being removed under generic/006 FR-013. **But see Q2** — the Kyte
  `orderview_rust` fast path never calls Python, so this exclusion leaves a hole
  that must be recorded rather than assumed away.
- **nf-ndc-adapter-rs OrderReshop is excluded** — `apply_orderreshop`
  (`rules/mod.rs:1256`) is still a stub returning
  `SectionPlaceholder("context")`. There is no context to enhance. OrderQuote,
  which shares the same response type, is real and **is** in scope.
- **The legacy Master-Rulesets token engine is out of scope.**
  `nf-ndc-adapter-generic/backend/content/fee_engine.py` already implements this
  table for the pre-BRE path and disagrees with it in three places — see Q3. This
  epic does not change it; it records the divergence so it is not mistaken for
  the reference implementation.

## Open questions

| # | Question | Blocks | Owner |
|---|---|---|---|
| **Q1** | Which coupon signal means "flown" — `coupon_status_code`, or `current_coupon_flight_info_ref.flown_airline_pax_segment_ref`? | `unflown_segment_count` on every REFUND | needs live refund payload |
| **Q2** | Does the Kyte `orderview_rust` fast path need these tokens, given it never reaches Python? | whether rs OrderView stays excluded | product / whoever owns Kyte |
| **Q3** | Is `fee_engine.py`'s reading or §6.3's reading authoritative where they disagree? | nothing in this epic; two engines will price the same ticket differently | product |

Q1 is the blocker. It is the only input to a money multiplier that this epic
cannot settle from the code, and getting it wrong is silent: a wrong unflown count
produces a plausible number, not an error.

## Definition of done

Every box in `impact-map.md` is ticked, Q1 is resolved and recorded as an ADR, and
both repos produce identical token values on `./fixtures`.
