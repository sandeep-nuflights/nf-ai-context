# Current focus

**A pointer, not a record.** Detail lives in the epic docs; this file only says
where work currently stands so a new session can pick up without rereading
everything. Keep it short — a long one stops getting maintained.

**Update it at the end of any session that moves the work.**

---

**Active program:** [NF-003 — BRE fee/discount migration](epics/NF-003-bre-fee-discount-migration/epic.md)
**Active sub-epic:** [NF-004 — cancellation fee/commission reversal](epics/NF-004-cancellation-fee-reversal/epic.md)
— drafted 2026-09-22, **awaiting Sandeep's approval** (working-agreement step 4).
NF-001 is complete in both adapters; NF-002 is Rust-complete and Python-unstarted
(no leaf spec in `nf-ndc-adapter-generic`).

**Last updated:** 2026-09-22

## Where we are

Cross-repo research pass completed over all six leaf repos — surface ownership,
management plane, BRE contract, and per-repo spec status are mapped in NF-003's
`impact-map.md`. Scope decisions **D1–D4** are settled; **G1** (Kyte) is resolved
in principle but rests on an unconfirmed premise (see below).

Two new confirmed defects this session, logged as NF-003 epic.md items 5-6:
`ActivateIncentiveRule` (backend, `nf-ndc-adapter-generic`) is broken outright —
missing global-ID decode, 500s on the agency-admin activate/deactivate toggle —
and separately, removing a subscription's ruleset mapping degrades pricing to
silent zero fees/discounts with no warning anywhere in the stack (confirmed
general, not just the known reshop bug). **Sandeep wants these fixed together in
their own sub-epic** — not yet numbered.

A full defect sweep followed on **2026-09-18** (four parallel repo research
passes) and is written up as NF-003's
**[open-defects.md](epics/NF-003-bre-fee-discount-migration/open-defects.md)** —
53 items with stable IDs and a status column, to be worked one at a time, plus
ten code-verified **corrections to this repo's own record** that are deliberately
not yet applied (they need Sandeep's confirmation first; see that file's §F).

Headlines from it: a **cross-tenant isolation cluster** (§A, 7 items — worst is
`AddCustomerIncentiveRule` letting one agency attach another's ruleset, plus a
`merged_jdm` path that reads any org's merged decision table); the **audit trail
for a charged fee is not durable** (E3+E14+E15+E16 compose — every retrieve
re-prices and rewrites the ledger row, its evaluation-log pointer goes stale, and
`reference` is never sent so the log itself is collectable); **resolution is
implemented three times with three different semantics** (E1, with the BRE's own
date-aware+rounding implementation sitting dead with zero callers, E2); and
**currency is unowned end to end** (F1/F2 — authored unitless, returned untagged,
three different rounding behaviours, JPY/KRW rounding to 2 decimals).

The hub itself was set up on 2026-09-16: `CLAUDE.md`, `stale-sources.md`,
`pending-confirmation.md`, the program/sub-epic two-tier model, and git init.

**Not yet started:** any leaf spec for NF-003. Nothing has been written to a leaf
repo.

## 2026-09-22 — NF-004 drafted

Six parallel repo passes over the cancellation flow, then direct re-reads of the
contested sites. Written up as
**[NF-004](epics/NF-004-cancellation-fee-reversal/epic.md)** + its impact map.

What the research changed:

- **P7 is answered in code: yes, a ticketed cancel re-evaluates fee/discount
  today, and prices it as a SALE.** The gate is request-type-only
  (`content_state.py:153-158`); the workbench never sends `OrderCancelRQ`, so
  FR-011's exclusion protects nothing on the real path. Two research passes
  disagreed on this — the answer was verified by hand.
- **The reversal is not where the record implied.** No BRE ledger row is ever
  reversed. The reversal is a DEBIT↔CREDIT direction flip on a *separate*
  accounting ledger (`ledger_service.py:21`), with the amount **recomputed** from
  a SALE-time-snapshotted formula via `fee_engine.py` — an engine separate from
  both `OrgMasterRuleSet` and the BRE. Commission was never in the rules engine
  at all (`content_rules.py:6121`).
- **The reversal is nested inside the BRE evaluation branch** — so a BRE failure
  suppresses it, and removing cancel from the recording set would delete it.
  Logged as **F11**; it is the constraint NF-004 is built around.
- New defects logged: **F10–F14, N9**. **F9's anchor moved** to `db_api.py:3085`.

Three decisions taken (Sandeep, 2026-09-22), recorded as **D5–D7** in NF-003:
the reversal migrates to the BRE too; VOID takes the full segment count per
NF-002 (**parked as P8**, not written into NF-002 as fact); sale-time ledger rows
stay untouched, with a durable reversal trace deferred to a later sub-epic.

**G2 is downgraded, not closed** — nothing is newly charged on VOID/REFUND, so
NF-002's Q1 no longer gates cancellation; it survives as a parity question, and
`fee_engine.py:184` answers it in legacy's own terms ("flown" = coupon status).

**A1, D6 and the A2 analysis closed later the same day.** A1 became **D8** (the
skip is an authoring outcome, not a code exclusion — a cancellation charge may be
added later). D6 confirmed; P8 cleared into NF-002; legacy's divergence logged as
**F15**. A2 researched across both adapters and the BRE: the transitive
`bre_evaluation_log_id` route **does not hold** — commission has no adjustment row
at all, the pointer is guaranteed rewritten at ticketing, N adjustment rows fold
into 1 projection row, and the log row is retention-collectable. Full analysis in
NF-004 §"A2 — the pin", with a recommendation to snapshot onto
`TicketOrgTransactions` under legacy's own write-once guard. Two further defects
logged: **F16** (sub-type amounts live, formula frozen, reversal uses the frozen
one) and **F17** (`unique_together` never existed — also a correction to
`open-defects.md` §G).

Later the same day: **F19** and **F20** found (the charge is frozen while its
inputs — tokens and the `*_enabled` flags — are read live, so a reversal can
silently diverge from or never post against its charge). **E15 marked
committed-but-not-implemented** — Sandeep will send `reference` for all
model-dependent data. The "once ticketed, price won't change" invariant is
parked as **P9**: this repo's own code and IATA/NDC research both contradict it
(classic ticketing freezes at the document; NDC's mutable Order does not), but it
affects only **A6**, not the pin-storage decision.

**NF-004 is now fully drafted (2026-09-22).** A2 and A6 are resolved: a single
write-once `content_ticketorgruleapplication` child table, pinned per
`(kind, sub_type)` — the grain confirmed against real data, which shows one
ruleset per sub-type (18 per document across 3 chain levels). The scalar-vs-map
question is settled by that data; the transitive `bre_evaluation_log_id` route is
rejected on four verified grounds. Rationale to share is in NF-004's
`decisions/ADR-001-rule-application-table.md`. Further defects logged: **F15–F20**.

**P9 confirmed 2026-09-23 (Sandeep): a ticket document's price does not change
after issuing/ticketing; a change is carried by a new document.** Recorded as
NF-003 **I1** and removed from `pending-confirmation.md`. It unblocks NF-004 and
drops **F19 from live to latent** — but it is a *business* fact with no code
enforcement (`update_tickets()` still rewrites the base fare on retrieve), so
NF-004 gains requirement 8, a detector that logs on mismatch. The
`content_rules.py:60-87` docstring, which asserts the opposite, is logged in
`stale-sources.md`.

**I2 confirmed 2026-09-23 (Sandeep): a document issued under ruleset v2 stays on
v2 — a republish to v3 applies only to documents issued after it.** The code does
the opposite: `resolve_published_ruleset` re-resolves to currently-published on
every evaluation, and evaluation runs on every retrieve. Logged as **F22**, to be
fixed in the order retrieval logic and scoped with the audit-durability cluster,
**not** NF-004. It narrows **010's R1** — once issued documents are pinned, their
pin cannot go stale, so the comparison-set question applies to unissued items
only.

**A6 taken as option (a) — no charge-time context snapshot, F19 knowingly carried
forward** (Sandeep, 2026-09-22). A `charge_basis`/`context_data` JSONB was designed
and dropped: the raw JSON *is* retained on `Ticket.ticket_doc_source` and the
context builder is a pure function of it, **but that JSON is itself rewritten by
`update_tickets()` (`db_api.py:1443`)** — so rebuilding reproduces F19 rather than
avoiding it. `TicketOrgTransactions` therefore gains no new column. **P9 is
promoted from parked to blocking** as a direct consequence: without a snapshot,
the "price won't change after ticketing" invariant has to actually hold.

**D10 added** — the reversal dispatches per kind on three predicates (`charged`
from `LedgerEntry` **never** from the amount columns, `pin`, `legacy` from the
write-once formula marker), with a durable reconciliation record on the anomaly
arms and the legacy `fee_engine.py` fallback built only if the production check
shows a non-empty legacy cohort. Two guards in `process_fee_commission_ledger`
must move or the dispatch never executes.

**A read-only pass over the local dev database found no observed instance of a
fee/commission reversal of any kind** — `content_orgrelationshipconfig` is empty,
so the reversal exits at its first guard every time, and there are zero FEE or
COMMISSION ledger entries across 4,837 rows. Recorded as NF-004's headline risk.

## 2026-09-23 — spec 010 shipped

**NF-004 requirement 1 is done.** `nf-ndc-adapter-generic`, commit `0d094b971` on
`rules-engine-migration`: `content_ticketorgruleapplication`, one write-once row
per (charge, kind, sub-type), holding the rules-service pin verbatim plus the
exact Decimal amount, currency and transaction type. `Ticketed` charges project
from the adjustment rows; `Void`/`Refunded` copy the sale's records verbatim;
every other status gets none.

**DoD item 6 is closed against the real schema** — not just the model.
`uniq_ticketorgruleapplication_charge_kind_subkind` is present in `pg_constraint`
locally, with `CHECK (amount <> 0)` beside it, and the model carries a single
`Meta` with `constraints` rather than the `unique_together` that F17 showed
silently vanishing on the neighbouring model.

Two implementation choices worth carrying forward into 011: the projection runs
in **its own savepoint**, so a failure to record leaves the charge and its ledger
posting intact (D10 then sees charged-without-pin and reconciles); and the three
new adjustment-row columns sit **outside** `_PRICE_ADJUSTMENT_COMPARISON_FIELDS`
(010's R3), whose residual stale-pin window I2/F22 narrows to provenance only.

**Spec `specs/` in that repo is still untracked** — the code is committed, the
spec-kit artifacts are not.

## 2026-09-23 — D8 restated, D4 settled, 011's blockers down to two

**D8 restated.** A decision table is a calculator, not a policy: matching a row
yields an amount, not a charge. No code posts an evaluation result as a new
charge on the cancellation path, so "no charge on VOID/REFUND" holds because the
feature **does not exist** — neither by authoring nor by exclusion, which is what
the original D8 claimed on both counts. The reversal evaluates the **pinned**
ruleset with the **recorded** `transaction_type`; a cancellation charge would
need a **published** evaluation plus posting code. Pinned-vs-published is the
structural discriminator, so an author cannot get it wrong.

**D4 settled and released.** `transaction_type` is a decision-table input column,
authored in `nf-app-home`, rendered properly in `nf-app-account`, and
**mandatory — no blank cells** (Sandeep). A blank cell matches any value, which
is what made the original D8 unenforceable. Mandatory authoring is only safe
because proration is **adapter-side**: the reversal replays the recorded type and
proration arrives in the token *values*, so a `SALE`-only row still matches on a
refund. **A3 closed; D4 no longer blocks 011.**

**Verified, against a claim that went the other way:** the legacy reversal does
**not** post a negated entry. `ledger_service.py:71` rebuilds the token context
and both `_write_fee_entry` calls pass `formula` + `context`, not an amount —
`is_reversal` changes only the DEBIT↔CREDIT direction and the description. Legacy
already gives back less than it charged on a part-flown refund. That is the
assumption NF-004's re-evaluation design rests on.

**F24 logged** — conjunction tickets charge only when the formula is
segment-based, decided by `"segment" in formula.lower()` (`ledger_service.py:67-68`).
No BRE equivalent exists, and the intent behind the rule is recorded nowhere.

**011's blockers are now two: A9 (NF-002's Python tokens) and the production
check.**

## The plan — agreed 2026-09-23

Ordered by dependency, not by size. **2 and 3 can start today.**

| # | Work | Blocked on | Where |
|---|---|---|---|
| ~~**1**~~ | ~~Answer the settlement question~~ **CLOSED 2026-09-23 (Sandeep): an org's `SALE` debit is what it owes its *supplier*, never what it charges its *buyer*.** An agency's own markup is its own money and must not consume its credit limit. The root-agency question closed too — roots are excluded by explicit code (`utils.py:1880-1884`), by design. | — | NF-005 unblocked, now **draft** |
| **2** | **Production check** — five read-only counts | nothing | `epics/NF-004-.../checks/production-check.sql` |
| **3** | **NF-002's Python token derivation (A9)** | nothing | `nf-ndc-adapter-generic` |
| **4** | **NF-005** — two halves: post the missing inter-agency debit for BRE `SUB_AGENCY` amounts, **and** correct the `SALE` debit to the provider price (**F27**). At ticketing. | nothing — design settled | **spec 012 drafted 2026-09-23**; Q1 (movement grain) is the irreversible one |
| **5** | **NF-004 spec 011** — the reversal | 3 for every proration case; 4 only for reversing BRE-posted amounts | `specs/011-...` (drafted) |

**Posting happens at ticketing, not order create.** That is where the
configuration engine posts, where the `SALE` debit is written, and where spec
010 records the pin — one moment, one transaction. An unticketed order is not a
sale.

**011 is not wholly downstream of NF-005.** The F11 lift, the two guard moves,
the D10 dispatch, the reconciliation record and the sweep depend on neither, and
reversing **configuration-charged** amounts works today because those entries
already exist. Only reversing **BRE-posted** amounts waits on NF-005 — and needs
no change when it lands, because FR-005a pins the `charged` check to ledger
entry type rather than to engine.

**3 is the long pole.** It is a token-derivation implementation, and every
proration case in 011 is untestable without it. **1 is the cheapest and unblocks
the most** — it is a question, not work, and it has now appeared in three forms:
the `net`/`sell` naming doubt, the double-count worry, and a concrete symptom.

## Next step

**NF-004 is approved (2026-09-22).** Leaf spec **010** is drafted in
`nf-ndc-adapter-generic` on `rules-engine-migration` — spec.md, plan.md,
data-model.md written, `tasks.md` not yet, nothing committed there. 010 is
strictly additive: it records which rules priced a charge and changes no amount.
Two decisions are open inside it — **R1** (whether the pin joins the
price-adjustment comparison set; it is the one place 010 touches existing
behaviour, and excluding it allows a silently stale pin) and **Q2** (zero-amount
matches — recommendation reversed to *no*, matching `content_rules.py:7085`).
**R2 is a recorded gap**: commission cannot be pinned until D5, since it is not
BRE-evaluated at all.

Spec **011** carries the reversal itself — the D10 dispatch, F11, the guard moves,
fixtures — and is blocked on **D4** and the **production check**.

The **production check** remains NF-004's first action: three read-only counts.
If production matches dev, this is not a working feature being migrated but an
intended one being implemented, which changes the parity gate — fixtures cannot
be captured, only agreed. It also sizes the legacy cohort and so decides whether
D10's fallback arm is built at all.

Otherwise the next move is Sandeep's — every open thread needs his input, and he
is working through `open-defects.md` item by item.

Two clusters there do **not** depend on D4/G1/G2 and can proceed independently of
the migration: the security cluster (§A) and the audit-durability composite. Both
were flagged as candidates for their own sub-epic rather than being sequenced
behind NF-003.

When D4's details arrive, the work is its cross-repo shape: `transaction_type` as
a rule-template column, and what it touches across all six repos. Note F3 in
`open-defects.md` is the concrete defect D4 closes — `OrderChangeRQ` is in the
recording set but still evaluates as `"SALE"`, so a partial refund or downgrade
is priced as a sale.

## Waiting on Sandeep

- **010 R1** — does the pin join `_PRICE_ADJUSTMENT_COMPARISON_FIELDS`? Narrowed
  by I2/F22 to unissued items only; still open for those.
- **D9** — still *(proposed, narrowed)*; never explicitly signed off.
- **P7's `repos.md` correction** — splitting the Cancellation row into
  `OrderCancelRQ` (excluded) vs `OrderChangeRQ`-carried cancel (not excluded).
  The table is deliberately left as-is until confirmed.
- **D4 detailed design** — the `transaction_type` template column
  (enum `SALE` / `VOID` / `REFUND`). The keystone: it unblocks cancellation and
  reshop, and touches every repo.
- **P1 in `pending-confirmation.md`** — is the Kyte fast path OrderCreate or
  OrderRetrieve? Changes NF-003 §G1 and whether Kyte needs a persistence path.
- **P6 in `pending-confirmation.md`** — are the BRE's unused `Invalidated` /
  `Archived` status variants an intended lifecycle or vestigial? Decides whether
  ruleset deactivation is cheap (reuse the status enum, predicate-only change in
  both adapters) or needs a new column.
- The other four items in `pending-confirmation.md`.
- **Glossary** — Sandeep will supply the domain terms directly rather than
  answering a generated question list. Record as `glossary.md` when it arrives.
  Until then, treat domain semantics as a known blind spot: Claude can say what a
  change *breaks*, but not reliably what it *should be*.

## Standing context

- **The leaf repos carry large amounts of uncommitted work** — the BRE
  implementation exists mostly in working trees, and `nf-ndc-adapter-rs` has no
  feature branch at all. Sandeep is aware and committing after review. Until
  then, treat every snapshot in this repo as dated and re-verify before acting.
- Leaf `specs/` directories are currently gitignored in several repos. Sandeep
  has said these will be brought into git, which step 6 of the working agreement
  depends on.
