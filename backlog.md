# Backlog — BRE fee/discount rollout

Raw working backlog for the fee/discount rules-engine initiative. This is
**pre-epic** material: bugs, undecided questions, testing status, todos texted
in as they come up. It has none of the rigor of `epics/` — no frontmatter, no
shape classification, no fixtures. When an item here turns out to need a
parity gate, an ADR, or spans repos with a real coupling artifact, promote it
into `epics/NF-NNN-slug/` (see README.md) and replace its line below with a
pointer, same as the two rows already promoted.

Repo legend (per `repos.md`): platform admin = nf-app-home, agency admin =
nf-app-account, rust backend = nf-ndc-adapter-rs, python backend =
nf-ndc-adapter-generic, BRE = nf-ndc-connect-rules-engine.

## How to update this file

- Append new items under the right section as a checkbox line. Text them in
  as they come up — no need to pre-sort, just drop them under the closest
  section and re-triage later.
- Check items off (`[x]`) rather than deleting. History of what shipped is
  worth more than a clean file.
- Prefix with a date if the item is time-sensitive (`(2026-09-16)`).
- Before trusting an item's premise, check it against `repos.md`'s surface
  ownership table — that file is corrected against working trees; this one is
  not. Two known contradictions are flagged below; don't add a third silently.

## Already promoted to formal epics

- **The whole fee/discount rules-engine initiative** → [NF-003](epics/NF-003-bre-fee-discount-migration/epic.md) (draft, umbrella). NF-001 and NF-002 are subsets of it. Scope decisions D1–D4 live there; this backlog stays the raw feed.
- Sub-type-scoped max/min for fee/discount → [NF-001](epics/NF-001-subtype-scoped-aggregation/epic.md) (approved) — do not re-scope here.
- PerTicket / PerSegment / PerTktIssue context tokens → [NF-002](epics/NF-002-fee-discount-token-context/epic.md) (draft, blocked on Q1) — do not re-scope here.

## ✅ Reshop / Cancel contradiction — resolved 2026-09-16

The earlier warning here asked whether reshop and cancel were buildable given
that `repos.md` records **OrderReshop as broken on both sides silently** (rs
stub; generic's path calls a matcher that has matched nothing since spec 004)
and **Cancellation as excluded by design** (generic FR-011).

Sandeep decided both are **in scope** for NF-003 — D2 (reshop) and D3 (cancel).
So the FR-011 exclusion is a **decision reversal**, as suspected, not a gap to
implement around. Two consequences for the items below:

- Reshop items are net-new work, not fixes to a working path. Which repo
  implements it is still undecided (NF-003 §Open items).
- **Cancellation makes NF-002's Q1 a hard blocker.** REFUND is the only
  transaction type that prorates by unflown segments, so the flown-signal
  question must be settled against a live refund payload before any cancellation
  fee ships. Q4 and Q6 below are the same knot.

## P0 — Bugs / blockers

- [ ] Agency admin (nf-app-account) rules listing makes 8 requests — flagged important
- [ ] Loading a single rule needs 4 HTTP calls + autocomplete calls (airline/airport/etc.)
- [ ] Delete/deactivate ruleset in subscription window throws an error
- [ ] Republish a rule isn't immediately reflected in cache — **root cause found (2026-09-16)**: BRE caches the current-ruleset pointer `bre:cur:{rule_type}:{rule_set_id}` with a **300s TTL**, and the merged graph `bre:jdm4:{composite_hash}` for **7 days**. The merged entry is keyed by composite hash so a new version gets a new key correctly; the lag is the 5-minute pointer. There is **no targeted eviction on republish** — invalidation is a deploy-time key-prefix bump (`jdm2`→`jdm3`→`jdm4`). Fix is a real invalidation on `publishRuleSet`/`publishRuleTemplate`, not a TTL tweak.
- [ ] `'Customer'` → `'CUSTOMER'` casing bug in `applies_to` (agency admin)
- [ ] BRE failure handling decision: hard raise (throw, per anirudh) vs soft (skip SF/Disc, continue) — needs sign-off then implementation. **Note (2026-09-16): the two backends have already diverged, so this is a reconciliation, not a greenfield choice.** adapter-rs hard-fails by design — BRE down / non-2xx / unparseable → whole pricing request fails, no retry, and `read_amount` refuses to coerce a missing amount to zero. adapter-generic soft-fails — appends to `response["error"]`, classified as a *warning* on create/change specifically so a caller cannot retry and double-book. Whichever way Q3 lands, one of the two changes.
- [ ] Verify current state of "handle output variables not in context data" — scribbles mark it both done and pending; don't scope more work on an unverified assumption

## P1 — Core epic completion (fee/discount cascade)

- [x] Fee/discount calculation on Order Create / Order Change / Order Retrieval — unit-tested across 11 airlines as root agency
- [ ] Fix offerprice injection at rust for sub-agency cascade scenario
- [ ] Order lifecycle interception at python for: order retrieval (`Refresh order`), order change, reshop (`ndcOfferReshopQuoteQuery`), cancel (`ndcCancelReshopQuery`) — see contradiction note above
- [ ] Fee/discount calculation on Order Reshop and Order Cancel — see contradiction note above
- [ ] Split order handling (reshop/void — unresolved which path)
- [ ] Refund handling — open question: does BRE apply any charges on refund?
- [ ] Trace the winning rule per offerprice/orderprice/reshop execution + save evaluation log trace alongside the offer price + rule-id recording in FO (auditability of *applied/qualified rulesets* — context/version/jdm/output — is already done; per-execution winning-rule trace is not)
- [ ] Effective date — implement + verify in CRUD and live. **Premise check (2026-09-16): `bre_rule_template` has no `effective_from`/`effective_to` — they were removed, and a template's applicability is `status`/`version` only. The dates live on `bre_rule_set` (NULL = open-ended) and are applied by `resolve_published_ruleset()` (`models.py:2068`). So this item is ruleset-scoped only; there is nothing to implement template-side unless that removal is being reversed.**
- [x] `X-nf-active-org-short-code` evaluation header — **already implemented everywhere (verified 2026-09-16)**: both adapters send it alongside the bearer token (`rule_source.rs`, `bre_client.py:196-200`), and both frontends send it from `src/api/bre.ts`. Org scoping rides on this header, not on the token.
- [ ] Review gate: Shahid to review current create/change/retrieval common function — do before building reshop/cancel on top of it

## P2 — Rules engine correctness

- [ ] `applies_to` mandatory when saving a ruleset
- [ ] Default hit policy (Collect + aggregation) should actually work as the template default
- [ ] Context passed vs. output equation consistency check, incl. failure-case handling
- [ ] Active/Inactive flag for `bre_ruleset`
- [ ] Rule status in FO: applied vs qualified (performance vs value semantics)
- [ ] Default output column naming on template creation (e.g. service fee type → `service_fee` column)
- [ ] Decision: where do new BRE tables live — adapter-rs, bre, or python?
- [ ] Caveat: editing a ruleset in draft/published state without saving leaves the server testing a stale version — no fix identified yet, just a known trap

## P3 — Frontend / JDM editor UX

- [ ] JDM editor (platform admin) stays readable (metadata + fields) after publish, editable only after explicit "Edit" click
- [ ] Column filters for agency admin (show only cols configured relevant by platform admin)
- [ ] Add fee/discount to ticket models + ledger; check credit limit impact if needed
- [ ] Cancellation flow: void, refund (credit limit, partial refund, ledger) — see contradiction note above

## P4 — Infra / Ops

- [ ] Move BRE service to a sidecar
- [ ] Move subscription/rules cache from in-memory to Redis
- [ ] Persist BRE test log files to S3 + confirm retention/clearing policy (monthly/yearly)
- [ ] Standard timing logs for BRE (DETAILED / SUMMARIZED modes)
- [ ] Deployment docs + services/dependencies mapping

## P5 — Testing

- [ ] Unit tests: all airlines, 2-level subscription; local inventory; rust adapters at root + 2-level subscription
- [ ] Multi-chain subscription with different rules per level
- [ ] Multiple ruleset qualifiers for different pax types
- [ ] Rule management plane impact when publishing a new rule

### Airline coverage snapshot (dated — re-verify before relying on it)

Python proxy — done: Qatar, Turkish, Emirates, Etihad, Singapore, Saudia,
United, Nile Air, Riyadh (RX), Airlink, Ethiopian.
Python proxy — to test: Oman Air (blocked — "Route not supported by this
airline" backend error, mapping already done), Air India, Olympic.
Rust-side: testing not yet started/documented.

Order-create PNR evidence captured for RX, SV, QR, EK, EY, SQ, TK, WY, 4Z, NP,
UAD — still blank for ET, AI, OA.

## Deferred / parked

- [ ] Service fee/discount modeled as an undisclosed tax while cascading to sub-agency
- [ ] Advanced-edit toggle on JDM rules editor
- [ ] Migrating (editing) an already-published rule template — ties to the open question below

## Open questions (need an external decision, not code)

| # | Question | Owner |
|---|---|---|
| Q1 | Should every orderview be explicitly re-edited for SF/discount, including one already built from a saved orderview that already has SF/discount applied? Risk of double-applying. | anirudh |
| Q2 | If an order item is ticketed, should its base price stay untouched, with fee/discount updates confined to the ticketed section only? | anirudh |
| Q3 | Confirm BRE failure handling: hard-raise vs soft-skip. | anirudh |
| Q4 | Refund: does BRE apply any charges here? | anirudh |
| Q5 | What if we need to edit an already-published template (platform admin or agency admin)? **Partly answered 2026-09-16**: nf-app-home spec 004 implements it — first save after "Edit" sends `id: null` so BRE creates `version+1`, and `ruleType`/`tenantType` are locked because the template PK is `id` alone. The unanswered half is what happens to agencies: their rulesets are **pinned to `template_version` forever** and never migrate. A migrate action is spec'd in BRE's architecture doc but was never built. | product |
| Q6 | Persgement: with a mixed flown/unflown-segment offer item, how is the billable unit for the unflown portion identified? A faredetail is likely not 1:1 with a segment. | needs modeling |

## Reference notes (design/architecture, not todos)

**OfferPrice SF/Discount algorithm**: fetch all chain rules once and cache →
loop offer items → loop fare details → loop each subscription chain's rules
(max 3 service-fee, max 3 discount) → evaluate → inject → track running total
per offeritem/chain/faredetail combo. Airlines group fare details differently
(by PTC vs per-pax — EK/QR/TK differ) — extraction must handle that variance.

**Injection spec**: update `Faredetail→price→fee[]` (amount + DescText per
rule, min of multiple service-fee results), `Faredetail→price→discount[]` (max
of multiple discount results), recompute
`TotalAmount = Base + ΣFee + ΣSurcharge + ΣMarkup − ΣDiscount`; mirror into
`FarePriceType→Net` (add `Net` if missing, leave `Filed` untouched) and roll up
to `OfferItem→Price` and `PricedOffer→TotalPrice`. All amounts are unit price —
fee/discount are unit values too, multiplied by pax count only when totaling.

**Architecture**: `apply_service_fee_discount` intercepts the offerprice
response on `/ndc-connect` (from either rust or python-proxy), resolves org →
subscription chains → rule IDs (currently in-memory, planned move to Redis),
cascades level-by-level, re-injects, returns. One master dispatcher branches
into `apply_service_fee_discount_offerprice` / `_orderprice` / `_orderreshop`,
each with its own context-extraction logic.
