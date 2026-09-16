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

**If confirmed:** close the NF-003 money-correctness item; if wrong, it is a live
bug, not a hardening task.
