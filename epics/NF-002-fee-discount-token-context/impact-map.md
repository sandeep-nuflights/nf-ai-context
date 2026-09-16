# NF-002 — Impact map

## Surface matrix

Which counter each evaluation surface needs, and why. This table is the epic —
everything below is consequence.

| Surface | Extractor | Ticket? | `segment_count` from | `unflown` | `previous_ticket_number` |
|---|---|---|---|---|---|
| **OfferPrice** (rs) | `rules/context.rs:58` `extract_all` | no | itinerary | `= segment_count` | none → first issue |
| **OrderQuote** (rs) | `rules/quote_context.rs:304` `extract_all_for_quote_item` | no | itinerary | `= segment_count` | none → first issue |
| **OrderCreate/Change/Retrieve — order item** (generic) | `content_rules.py:6241` `_cascaded_pricing_for_order_item` | no | itinerary | `= segment_count` | none → first issue |
| **OrderCreate/Change/Retrieve — ticket doc** (generic) | `content_rules.py:6409` `_cascaded_pricing_for_ticket_docs` | **yes** | **coupons** | coupon status (**Q1**) | `original_issue_info.ticket_number` |
| OrderView S1/S2 (rs) | `rules/order_context.rs:326` / `:566` | — | *excluded* — Q2 | — | — |
| OrderReshop (rs) | `rules/mod.rs:1256` | — | *n/a* — stub | — | — |

**One itinerary counter serves three of the four in-scope surfaces.** Only the
ticket-document surface needs the coupon counter, and that surface is Python's.
So: the *derivation* is mirrored across both repos; the *sources* are split.

## Code sites

| Repo | Site | Change | ADR |
|---|---|---|---|
| nf-ndc-adapter-rs | `rules/context.rs:58` `extract_all` | New `extract_segment_count(components)` helper; insert 6 keys **inside `build_shared` at `:131`**, never the per-pair arm | 001, 002 |
| nf-ndc-adapter-rs | `rules/context.rs:128` `let transaction_type = "SALE"` | **Stays a literal** — see below. Passed as an argument to the derivation, not threaded from the caller | 001 |
| nf-ndc-adapter-rs | `rules/quote_context.rs:369` / `:372` | Same as `context.rs`, reusing its helper rather than a second copy | 001, 002 |
| nf-ndc-adapter-rs | `rules/order_context.rs:386` / `:647` | **No change** — excluded, Q2 | — |
| nf-ndc-adapter-generic | `content_rules.py:6241` `_cascaded_pricing_for_order_item` | Itinerary counter; add `segment_count`/`unflown_segment_count`/`previous_ticket_number` to the entry dict | 002 |
| nf-ndc-adapter-generic | `content_rules.py:6453` (coupon loop in `_cascaded_pricing_for_ticket_docs`) | Coupon counter **in the loop that already runs there** for the `exchanged` flag | 002, 003 |
| nf-ndc-adapter-generic | `content_rules.py:6976` the one `context = {...}` literal | New `_build_fee_discount_token_context(entry, txn_type)`, called here | 001 |
| nf-ndc-adapter-generic | `content_rules.py:6987` `"transaction_type": "SALE"` | Derived from `usecases`, already a parameter of `evaluate_bre_rules_for_order` | 001 |

### Why "a common function" is already half-built on the Python side

All three of OrderCreate, OrderChange and OrderRetrieve enter through
`apply_fee_discount_for_order` → `evaluate_bre_rules_for_order`, and that function
builds its context in **exactly one place**, the literal at `content_rules.py:6976`.
There is no third path to unify. The work is one helper plus one call site.

What cannot live in that helper is the counting: the ticket document and the
order item are only in scope inside the two `_cascaded_pricing_*` builders. So
those produce the two raw counts, and the helper — which is downstream of
`transaction_type` — does the derivation. Splitting it the other way puts the
transaction-type switch in two places instead of one.

### Ordering constraint

`per_segment` / `per_ticket` / `per_tkt_issue` are derived **using**
`transaction_type`. Derivation must therefore sit downstream of wherever the
caller-supplied value lands. Count upstream, derive downstream, in both repos.

### Where `transaction_type` actually varies — Python only

The caller supplies it (epic §"Why now"), but on the two **in-scope rs surfaces
there is only one value it can take**: OfferPrice is pre-order pricing and
OrderQuote is a reshop *quote* — both are sales in progress, and neither can be a
VOID or a REFUND. Threading a parameter through `FrameDeps` to deliver a constant
is churn that buys nothing today.

So on the rs side: the derivation **takes `transaction_type` as an argument** — so
the switch exists and is tested — but the argument is the existing `"SALE"`
literal. If Q2 brings rs OrderView into scope, that literal is the one thing that
has to change, and the derivation underneath it is already correct.

Python is where it genuinely varies: OrderCreate and OrderChange are SALE, a
cancel is VOID or REFUND depending on the void time limit, and `usecases` —
already a parameter of `evaluate_bre_rules_for_order` — carries
`CANCEL_PAID_ORDER` / `CANCEL_UNPAID_ORDER` / `CANCEL_ORDER_RETAIN` /
`CANCEL_ORDER` (`backend/ndc/usages.py:43`). **The usecase→transaction-type
mapping is a Python-side design question this epic does not settle** — it belongs
in `nf-ndc-adapter-generic`'s own leaf spec, not here, because no other repo
depends on how it is spelled.

*Assumption to confirm:* that an OrderQuote can never quote a refund. If it can,
rs needs the threading after all.

## Fan-out interaction (rs only)

`QualifierMode::FanOut` emits one context per `(cabin, rbd)` pair. All six new
keys are **fare-detail scoped**, not pair-scoped — they must go in the
`build_shared` closure so every fanned-out context carries identical values.
Putting them in the per-pair arm would make `per_segment` vary by cabin, which is
meaningless and would then be reduced across contexts by `reduce_across_contexts`
(`rules/evaluate.rs:261`) as though the difference meant something.

## Open decisions

| # | Decision | Status | Why it blocks |
|---|---|---|---|
| Q1 | Flown signal: `coupon_status_code` vs `flown_airline_pax_segment_ref` | **OPEN — blocking** | Directly multiplies money on every REFUND |
| Q2 | Kyte `orderview_rust` fast path | **OPEN** | Determines whether rs OrderView stays excluded |
| Q3 | `fee_engine.py` vs §6.3 where they disagree | **OPEN — non-blocking** | Two engines, same ticket, different money |
| — | Token key names and raw-vs-derived | Decided | ADR-001 |
| — | Two count sources, one per surface | Decided | ADR-002 |
| — | First-issue test | Decided | ADR-003 |
| — | Fare component with no segment refs | Decided | ADR-004 |
| — | UI display-name convention (`nf-app-home`/`nf-app-account`) | Decided | ADR-006 |

### Q1 — the blocking one

`CouponType` carries **both** candidate signals (`coupon_type.rs:34` and `:39`),
and they can disagree. This is D3 from
`nf-ndc-adapter-rs/docs/rules-engine/orderview-injection-analysis.md:437`, where it
is already flagged as "directly multiplies money on refunds" — still open.

Python makes it worse by carrying two non-overlapping status vocabularies:

| Source | Vocabulary | Site |
|---|---|---|
| NDC payload | `T` (ticketed), `E` (exchanged), `RF` (refunded) | `inventory/mutations.py:1111`, `:1345`; `content_rules.py:6455` |
| Legacy `Ticket` model | `B` / `Flown`; `O` / `OPEN` | `content/fee_engine.py:184`, `:129` |

Neither set contains the other. One canonical flown-status set has to be agreed
against a real refund payload before either counter ships.

### Q2 — the hole the OrderView exclusion leaves

`repos.md` records the Kyte `orderview_rust` fast path as **adapter-rs owned** and
notes it "never calls Python". The scope decision for this epic excludes rs
OrderView on the grounds that Python owns that surface — which holds for the proxy
path and does **not** hold for Kyte. If a Kyte order needs per-segment fees, no
in-scope code will produce them.

Recorded rather than resolved. This is the same class of gap ADR-002 of NF-001
recorded about fan-out divergence: not caused by this epic, not fixed by it, and
worth naming so it is not rediscovered as a defect.

## Downstream blast radius

Smaller than NF-001's, because this is additive.

- **No existing amount changes.** An evaluation context gaining keys no ruleset
  reads produces byte-identical outcomes. The money moves the first time a
  ruleset references a new token — which is a ruleset-authoring event, not a
  deploy event.
- **`_log_fee_discount_evaluation_failure` logs the full context**
  (`content_rules.py:6745`). Six more keys per entry in every failure log. Not a
  problem; worth knowing before someone reads it as noise.
- **BRE audit records store the context verbatim** (`service/src/audit/record.rs:25`).
  Same, on the storage side.
- **Ruleset authors need to be told the tokens exist.** No UI change — the editor
  takes free-form context — but an unadvertised token is an unused token.

## Exclusions

| Repo | Scope | Reason |
|---|---|---|
| nf-ndc-connect-rules-engine | all | context is free-form JSON; derivation is caller-side |
| nf-ndc-adapter-rs | OrderView S1 + S2 | Python owns OrderCreate/Change/Retrieve (generic/006 FR-013). **Q2 qualifies this** |
| nf-ndc-adapter-rs | OrderReshop | `apply_orderreshop` is a stub — no context exists to enhance |
| nf-ndc-adapter-generic | `fee_engine.py` | legacy Master-Rulesets engine, not the BRE path. Q3 records the divergence |
| nf-ndc-adapter-generic | fan-out | no fan-out axis — verified under NF-001, unchanged here |
| nf-app-workbench | all | no UI surface for these tokens |
| nf-app-home / -account | template/ruleset authoring UI only (variable picker naming, ADR-006) | not excluded — see ADR-006; no other UI change in either app |

## Adopter checklist

Mirror epic: one token table, two implementations, neither upstream. Not done
until every box is ticked.

- [ ] **Q1 resolved** against a live refund payload, recorded as `ADR-005`
- [ ] **rs** — `extract_segment_count` helper in `context.rs`, itinerary source (ADR-002)
- [ ] **rs** — six keys in `build_shared`, `context.rs:131` — **not** the per-pair arm
- [ ] **rs** — derivation takes `transaction_type` as an argument and is tested on all
      three values, even though both in-scope surfaces pass `"SALE"`
- [ ] **rs** — OrderQuote reuses the `context.rs` helper rather than a second copy
- [ ] **rs** — confirm an OrderQuote can never quote a refund; if it can, thread
      `transaction_type` through `FrameDeps` after all
- [ ] **generic** — itinerary counter in `_cascaded_pricing_for_order_item`
- [ ] **generic** — coupon counter in the existing loop at `content_rules.py:6453`
- [ ] **generic** — `_build_fee_discount_token_context` helper + its one call site
- [ ] **generic** — usecase→transaction-type mapping designed in generic's own leaf
      spec, then `transaction_type` derived from `usecases`, replacing the literal at
      `content_rules.py:6987`; the comment above it citing rs's "definitionally a
      sale" reasoning becomes wrong and must go, not be left to mislead
- [ ] **both** — first-issue test per ADR-003, **not** bare absence
- [ ] **both** — zero segments is an error, never a zero token (ADR-004)
- [ ] **both** — `./fixtures` pass identically, 0 discrepancies
- [ ] **docs** — `orderview-injection-analysis.md` D3/D4 rows updated to point at
      the Q1 resolution ADR / ADR-001 rather than staying open
- [X] **nf-app-home** — `OutputColumnConfig.tsx`'s `ALWAYS_AVAILABLE_TOKENS`
      unconditionally includes exactly nine names — the six NF-002 tokens plus
      `base_fare`/`yq`/`yr` — in every output column's `availableVariables`,
      on every template, no per-template "Additional variables" step
      required, and **untagged**, same as a real input-column field — `custom`
      stays reserved for a genuinely ad-hoc typed name (ADR-006 — triggered by
      a live incident, `org=T-EK`, `ruleset_id=851822da-5ba2-4571-a1b9-5fb90bac8e82`,
      where a free-typed `Persegment` silently evaluated to `0`, not an error;
      extended after `base_fare`/`yq`/`yr` were found to disappear from a real
      template's picker entirely once unchecked-and-saved, since they were
      only ever opt-in). No broader "known key" catalog and no separate
      `builtin` tag — both were tried and reverted as unrequested scope.
      Test coverage added directly (`OutputColumnConfig.test.tsx`, 7 tests).
- [X] **nf-app-account** — `expressionDisplay.ts`'s `humanizeField` renders
      these six tokens with the decided PascalCase labels once they're on a
      template's `allowedVariables` (ADR-006); its own allow-list validation
      (`codecs/expression.ts`) needed no change — it was already correct.
- [ ] **content, not code** — the live `AdditionalContextVars` ruleset
      (`851822da-...`) needs two manual fixes, neither automatic: check the
      now-always-available `per_segment` checkbox for that output column and
      save in `nf-app-home`; fix the ruleset's own formula text from
      `Persegment*10` to `per_segment*10` in `nf-app-account` (ADR-006)
