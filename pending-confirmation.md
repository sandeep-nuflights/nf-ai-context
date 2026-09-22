# Pending confirmation

Findings from research that would change the recorded architecture **if true**,
but which have not been confirmed by Sandeep.

**Nothing moves from this file into `repos.md`, an epic, or an impact map without
his explicit confirmation.** That is the rule in `CLAUDE.md`; this file is where
a finding waits in the meantime, so it is neither written as fact nor lost.

> **Adding an entry:** what was observed, where (with an anchor), why it matters,
> and what would be recorded if confirmed. Date it.
>
> **Clearing an entry:** on confirmation, write the fact into its proper home and
> **delete the entry here**. This file is a queue, not a log — a confirmed item
> left behind becomes a second, competing copy of the truth.

**Also awaiting confirmation, held elsewhere:** the 2026-09-18 defect sweep
produced ten code-verified **corrections to this repo's recorded architecture**
(spec levels, Python's ledger semantics, Rust's decimal/currency handling, the
true scope of NF-001/NF-002 in adapter-rs, and several guarantees that are
stronger than assumed). They live in
[`epics/NF-003-bre-fee-discount-migration/open-defects.md`](epics/NF-003-bre-fee-discount-migration/open-defects.md)
§F rather than being duplicated here, and the affected claims in `repos.md` /
`impact-map.md` / `epic.md` are deliberately **left as-is** until confirmed.

---

## P1 — Is the Kyte fast path OrderCreate or OrderRetrieve?

*Raised 2026-09-16.*

**Observed:** research traced the Kyte `orderview_rust` fast path as the
**OrderRetrieve** branch — `nf-ndc-adapter-rs/nf_ndc/src/graphql/schema.rs:639`,
flag `orderview_rust`, `MessageSource::RustAdapter`, never calling Python.

**Sandeep said:** "Kyte for order create and other python currently handling
operations."

**Why it matters:** it changes what Kyte needs. OrderCreate must write ledger
rows (`FullfilmentOrdersPriceAdjustments`) and `TicketOrgTransactions` — and Rust
writes no rows at all, so Kyte would be a *persisted* surface on the repo that has
no persistence path. OrderRetrieve re-evaluates and re-records in Python today,
which is a materially different problem. NF-003's G1 resolution is written
assuming order create; if it is retrieve, G1 needs rewording.

**If confirmed:** record the true Kyte surface(s) in `repos.md`'s ownership table
and reword NF-003 §G1.

## P2 — Does template metadata actually ride inside the `jdm` JSONB?

*Raised 2026-09-16.*

**Observed:** the BRE service has **no** allowed-variables or domain-restriction
columns — `grep` over `service/src/` returns zero hits, and `SlotDeclaration` is
three fields. But `nf-app-home` demonstrably authors that metadata under an
`NF_CELL_KEY = "nfCell"` convention (`metadata/contract.ts:11`).

**Inference, not verification:** the metadata is embedded in the graph cells and
therefore lands inside `bre_rule_template.jdm`, which the service stores opaquely.
Nobody traced a single value end to end from the home UI into a stored row.

**Why it matters:** it decides whether backend enforcement of allowed variables
and domain restrictions is a **schema change** or a **validation change**, which
is a direct input to D4 (`transaction_type` as a template column).

**If confirmed:** record in NF-003's impact map as the mechanism, and note that
any BRE-side enforcement means parsing `jdm`, not reading a column.

## P3 — Is Python's OfferPrice evaluation dead code, or merely unreached?

*Raised 2026-09-16.*

**Observed:** `nf-ndc-adapter-generic/backend/ndc/content_state.py:2912-2917`
returns the OfferPrice response unmodified; Rust evaluates and overwrites. But
`inject_updated_offer_price` (`content_rules.py:501`) still exists.

**Why it matters:** if it is genuinely unreachable it is a retirement task; if
some path still reaches it, two engines can write the same surface.

**If confirmed dead:** add to NF-003's retirement scope alongside the legacy
`OrgMasterRuleSet` authoring surface.

## P4 — Can an OrderQuote ever quote a refund?

*Raised 2026-09-16, inherited from NF-002's impact map.*

**Observed:** NF-002 assumes not, and on that basis adapter-rs passes a `"SALE"`
literal rather than threading `transaction_type` through `FrameDeps`
(`context.rs:128`, `quote_context.rs:369`).

**Why it matters:** if an OrderQuote *can* quote a refund, Rust needs the
threading after all, and D4's context plumbing grows. This assumption is load
-bearing for two epics.

**If confirmed false:** NF-002's adopter checklist item on threading becomes
required, not conditional.

## P6 — Are `Invalidated` / `Archived` a half-built deactivation design, or vestigial?

*Raised 2026-09-16.*

**Observed:** the BRE's GraphQL `RuleStatus` enum has **four** variants —
`Draft, Published, Invalidated, Archived`
(`service/src/graphql/common.rs:37-42`) — but only `"draft"` and `"published"`
are ever written anywhere in the service. `guard_not_published` (`:9-18`) treats
`invalidated` as immutable alongside `published`, but **not** `archived`, so an
archived record would be editable in place. The `From<&str>` impl also falls
through `_ => RuleStatus::Archived`, so any unrecognised status string silently
becomes Archived.

**Corrected 2026-09-18** — the observation above is wrong in one place. The
reachable `bre_rule_set` lifecycle is `draft` → `published` → **`invalidated`**:
draft at `graphql/rule_set.rs:540`/`:563`, published at `:675`, and `invalidated`
**is** written, on a publish race, at `:651`. So `invalidated` is live, not
unwritten. `Archived` remains genuinely dead — never written by any path, only
the `From<&str>` fall-through display value. Templates only ever carry
`draft`/`published` (`graphql/template.rs:233`, `:274`).

**What this leaves open:** only the *intent* question. The code question is
settled — a status-based deactivation would have to be designed onto `archived`
(unwritten) or a new state, since `invalidated` already means "lost a publish
race" rather than "deliberately switched off". Whether that lifecycle was
designed or accreted is still Sandeep's to answer.

**Why it matters:** it decides the cost of adding ruleset deactivation. If these
were an intended lifecycle, a status-based deactivate reuses an enum the API
already exposes and needs no new column in either adapter's entity definition —
substantially cheaper than adding `is_active`. If they are vestigial, the
fall-through is a latent bug worth fixing regardless.

**If confirmed intentional:** record the intended lifecycle in NF-003 and design
deactivation onto `archived`. **If vestigial:** fix the `_ =>` fall-through to be
explicit and treat deactivation as a fresh design.

## P5 — Is `"discount"` the right BRE output key?

*Raised 2026-09-16.*

**Observed:** `nf-ndc-adapter-generic/backend/ndc/bre_client.py:157` tries
`("amount", "service_fee", "discount")` in order, and its own comment flags
`discount` as **assumed, never confirmed against a live response**. A
discount-kind rule whose output key differs would silently return `None` — a
missing amount, not an error.

**Why it matters:** listed as a money-correctness defect in NF-003, but the fix
depends on what the key actually is. Needs one live response, or the answer from
whoever authored the template's output column.

**Sharpened 2026-09-22 — the question was under-framed.** The authoring UI
enforces **no output-key convention at all**: the output column id is whatever
the platform admin types, and both `extractSlotData` and `stripTemplateRows` are
column-id-agnostic (`codecs/output.ts:39-53`, `slotData.ts:17-28`). So the
fallback tuple is not guessing against a contract with one unverified member — it
is guessing against arbitrary template-defined field ids. A live response would
answer "what did *this* template call it", not "what is the key". Logged as
**F10** in `open-defects.md`.

**If confirmed:** this stops being a lookup question and becomes a design one —
either the BRE contract names the output key, or the adapters read it from
`slot_manifest`. Either way it is a live bug, not a hardening task.

## P7 — Does BRE fee/discount evaluation actually re-run on a ticketed order's cancellation?

*Raised 2026-09-18. **Answered in code 2026-09-22: yes.** Awaiting Sandeep's
confirmation of the `repos.md` correction only.*

**Code answer (verified 2026-09-22, read directly, not via an agent):**
`_operation_records_fee_discount(RQ)` (`content_state.py:153-158`) gates on the
**request type and never the usecase**. The workbench's cancel enters as
`ndcOrderChange` → `make_request(rq, OrderChangeRQ, OrderViewRS)`
(`mutations.py:37`), so `RQ == OrderChangeRQ` and the recording branch is taken
at `content_state.py:3079`. The whole file contains exactly **one** `RQ`
reassignment (`:2371`) and it only *adds* `CANCEL_ORDER_RETAIN` into the same
bucket — nothing ever reassigns `RQ` away from `OrderChangeRQ`. Combined with
F3's hardcoded `"SALE"` (`content_rules.py:6993`), **every ticketed cancellation
is priced as a sale today.**

One of the 2026-09-22 research passes reported the opposite (that
`CANCEL_PAID_ORDER` stays excluded and only `CANCEL_ORDER_RETAIN` records). That
is wrong; it is recorded here because it is the plausible-looking answer.

**What still needs Sandeep:** the `repos.md` ownership-table correction —
splitting the Cancellation row into `OrderCancelRQ` (genuinely excluded, FR-011)
and `OrderChangeRQ`-carried cancel (**not** excluded, and the only path the
workbench uses). The table is deliberately left as-is until then.
[NF-004](epics/NF-004-cancellation-fee-reversal/epic.md) carries the verified
detail meanwhile.

*Original entry follows.*

**Observed:** `repos.md`'s surface-ownership table records "Cancellation |
neither evaluates | — persists | Excluded by design (generic FR-011)". That's
true for the standalone `ndcOrderCancel`/`OrderCancelRQ` mutation —
`FEE_DISCOUNT_RECORDING_OPERATIONS = {OrderCreateRQ, OrderChangeRQ,
OrderRetrieveRQ}` (`nf-ndc-adapter-generic/backend/ndc/content_state.py:146-150`)
deliberately omits `OrderCancelRQ`, per an inline FR-011 comment. But the
workbench's actual ticketed-cancel path (Cancel Order button on a ticketed
order) never sends `OrderCancelRQ` — it sends `OrderChangeRQ` with
`changeOrderChoice.acceptCancelledOffer` (usecase `CANCEL_PAID_ORDER`), which
**is** in that set. `apply_fee_discount_for_order()` is called at
`content_state.py:3058-3064` on this path, so BRE evaluation genuinely re-runs.
`content_rules.py:25-28`'s docstring argues cancellation "does not touch
fulfilment pricing" and any re-record is a no-op of the sale-time adjustment —
but that reasoning assumes cancel only ever arrives as `OrderCancelRQ`. Nobody
has traced whether the `OrderChangeRQ`/`CANCEL_PAID_ORDER` re-evaluation can
produce a different (wrong) adjustment row rather than reproducing the
original one.

**Why it matters:** overlaps F3 in NF-003's `open-defects.md` (`transaction_type`
hardcoded `"SALE"` on `OrderChangeRQ`, including this path) — same request
class. D4's `transaction_type` template column would need to account for
`CANCEL_PAID_ORDER`, not just partial refund/downgrade OrderChange. If BRE
evaluation on a ticketed cancel can diverge from the sale-time amount, this is
a live money-correctness defect, not just a mislabeling.

**If confirmed:** correct `repos.md`'s Cancellation row to distinguish
`OrderCancelRQ` (genuinely excluded) from `OrderChangeRQ`-carried cancel
(`CANCEL_PAID_ORDER`, not excluded), and fold the latter into F3 / D4's scope.

## P9 — "Once ticketed, the price won't change" — **BLOCKING**

**Promoted from parked to blocking, 2026-09-22.** NF-004 took **A6 as option (a)**
— pin the ruleset, snapshot no context, accept **F19** (Sandeep). Option (b)
existed precisely to make this invariant irrelevant; without it, the invariant
must actually hold for any reversal amount to be trustworthy. The two "Why it
matters" / "does NOT decide" paragraphs below were written while A6 was still
open — the conclusion that P9 "affects only A6" now reads as *affects every
reversal amount*, because A6 went the way that depends on it.

Note also the rebuild-on-demand route was examined and rejected:
`Ticket.ticket_doc_source` retains the raw JSON, but `update_tickets()` rewrites
it (`db_api.py:1443`), so rebuilding the context reproduces F19 rather than
avoiding it.

**The cheap guard below is now the recommended mitigation regardless of how P9
resolves** — snapshot the ticketing-time base fare, compare at reversal, log on
mismatch. It is the only thing that makes the accepted defect detectable.


*Raised 2026-09-22 by Sandeep while scoping
[NF-004](epics/NF-004-cancellation-fee-reversal/epic.md).*

**Claimed:** "once ticketed price won't change, if a reissue happens it will be in
a new ticket, and other scenarios won't affect the price."

**Why it matters:** it is the load-bearing assumption for NF-004 **A6** — whether
the reversal must snapshot the ticketing-time *token context* (base fare, YQ/YR)
or may re-read the ticket live. If it holds, pinning the ruleset alone suffices
and **F19** drops from live to latent. If it does not, F19 is a live money defect
and A6 must take option (b).

**Two independent sources contradict it, and one supports it.**

*Against — this repo's own code.* `content_rules.py:60-87` quotes the product doc
("fees/discounts are evaluated *each time an OrderView is provided by provider's
NDC response*") and records that a freeze-at-ticketing boundary was **proposed and
reverted**: "a proposal to add one (006 Q2/FR-014) was reverted on finding this
text." The same docstring states "a retrieve of a ticketed order WILL rewrite the
recorded amounts if the provider's base fare has moved. That is the documented
intent, not an oversight." Live code matches: `update_tickets()` rewrites
`ticket_base_fare_amount` / `ticket_tax_details` under the TICKETED branch
(`db_api.py:1067`, `:2255-2261`, `:2340-2346`).

*Against — IATA/NDC industry research (web, 2026-09-22).* Classic BSP/ATPCO does
enforce document-level immutability — every price change, including involuntary
ones, reissues with a new ticket number and an "issued in exchange for"
reference. **NDC does not carry that boundary over:** the Order is the persistent
mutable source of truth, repricing a ticketed Order via OrderChange is a designed
operation rather than an edge case, and IATA's ONE Order direction explicitly
phases out separate e-ticket/EMD records in favour of one mutable Order. The
invariant is sound for the classic model and is the specific assumption the NDC
model breaks.

*For.* In the classic model the invariant is exactly right, and for a structural
reason. If NuFlights' actual airline partners behave classically on these
connections, it may hold in practice regardless of what the standard permits.

**Unresolved in the research** (flag before relying on either): BSP/IROE currency
restatement of an already-issued ticket — neither confirmed nor ruled out;
retroactive tax restatement — general practice is not to restate, but no primary
IATA text was retrieved; primary resolution text (735d, 850m, 830d) was not
fetched, so several findings rest on secondary sources.

**Second-order trap found while checking:** an EMD-A (associated ancillary) is a
separate document but is *linked to a flight coupon*. The base ticket record is
untouched, yet anything computing "ticket total" as ticket + associated EMDs
changes silently. Worth checking `ticket_total_amount_*` in the projection.

**Note what this does NOT decide.** The invariant covers *price*, not *rules*.
Four of the 17 price-adjustment comparison fields — `rule`, `rule_expression`,
`ruleset_applied_to`, `adjustment_amount` — are ruleset-derived, so a republish,
an `effective_to` lapse or a mapping change rewrites a whole chain level with the
provider price completely static, issuing fresh `bre_evaluation_log_id`s. That is
exactly the class of event the pin exists to survive, so **P9 does not affect
NF-004's pin-storage decision either way.** It affects only A6.

**If confirmed:** record the invariant with a named owner, resolve
A6 as option (a) (pin the ruleset only), and downgrade F19 to latent-guarded-by-
invariant rather than closing it. **Add the cheap guard regardless** — snapshot
the ticketing-time base fare and compare at reversal time, logging on mismatch.
It changes no behaviour and converts a silent divergence into a detectable one.

**If refuted:** A6 takes option (b), F19 stands as live, and the reversal must
derive from a frozen token snapshot rather than the live ticket.
