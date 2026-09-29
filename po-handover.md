# Handover to the Product Owner — and to the PO's Claude agent

**Written 2026-09-29.** No code, no implementation detail, and no commercial
amounts. Everything here is about what the system is meant to do and where it
currently does not do it.

## Why there is no scope document to hand you

Service fees and discounts were already half-built in the legacy system. The work
started as a replacement for that half-built feature, and the missing pieces were
only discovered by building — which is why the specifications came first and the
scope document is being written now, in the other order.

This hub repository was itself created **mid-implementation**, to coordinate work
that had already spread across five repositories. So it does not contain the
original plan. What it contains is the record of what was found, decided and
corrected along the way — and that record is the useful thing, because most of
the gap between "expected" and "implemented" is written down in it already.

Two documents carry that, and everything below is a guide to reading them:

- **`epics/NF-003-bre-fee-discount-migration/open-defects.md`** — what is known to
  be wrong today. 28 open items, each with how it was found.
- **`CURRENT.md`** — where the work stands right now and what is waiting on a
  decision.

---

## 1. The seven repositories and how they relate

The system is not a chain. The rules engine is a standalone service, and the two
backends are **peers** that both call it. A change to the engine therefore
affects both backends at once, rather than passing through one to the other.

```
        ┌──────────────────────────────┐
        │  nf-ndc-connect-rules-engine │   decides the fee / discount
        └───────────┬──────────┬───────┘
                    │          │
       ┌────────────▼──┐   ┌───▼──────────────┐
       │ adapter-rs    │   │ adapter-generic  │   the two backends
       │ (new, Rust)   │   │ (legacy, Python) │
       └───────┬───────┘   └────────┬─────────┘
               └────────┬───────────┘
                        │
    ┌───────────┬───────▼────────┬──────────────┐
    │ app-home  │  app-account   │  workbench   │   what people see
    └───────────┴────────────────┴──────────────┘
```

| Repository | What it is, in business terms |
|---|---|
| **nf-ndc-connect-rules-engine** | The rules engine. Holds the rule tables, decides what fee or discount applies to a transaction, and keeps the audit trail of why. |
| **nf-ndc-adapter-rs** | The newer backend, in Rust. Handles pricing and quoting — everything up to the point of booking. It is the front door for every customer-facing request. |
| **nf-ndc-adapter-generic** | The older backend, in Python. Handles orders, ticketing, the credit ledger between agencies, and cancellations. The money actually lands here. |
| **nf-app-home** | The internal admin application. Where NuFlights staff author the **rule templates** — the structure a rule takes. |
| **nf-app-account** | The agency-facing application. Where an agency fills in its **own values** inside a template that staff published, then tests and publishes it. |
| **nf-app-workbench** | The search and booking application. Displays fees and discounts to the agent. |
| **nf-app-home-v2** | A next-generation replacement for nf-app-home. Not part of this work. |

### Two things about this map that matter to scope

**There are two migrations running at once, and they are often confused.** One is
the move from the Python backend to the Rust backend, surface by surface. The
other is the move from hard-coded fee logic to the rules engine. This work is the
second one; it inherits the split created by the first. That is why the same
capability sometimes has a specification in both backends — they are two halves
of one rule, not the same work done twice.

**One boundary is unresolved.** For creating, changing and retrieving an order,
both backends currently contain the ability to apply fees. The Rust side is
switched off by default, so nothing conflicts today — but which side owns it is
an open decision, not a settled one. Worth knowing before a scope document
implies a clean split.

### Where the written work lives

Each repository keeps its own numbered specifications under `specs/`. Roughly:

| Repository | Specs | What they cover |
|---|---|---|
| nf-ndc-adapter-generic | 12 | Orders, ticketing, the agency credit ledger, cancellation and reversal |
| nf-ndc-adapter-rs | 12 | Pricing, quoting, chain resolution, rounding, rule tokens |
| nf-ndc-connect-rules-engine | 18 | The engine itself. **Most are infrastructure** — deployment, caching, logging. Only 008, 009, 010, 019 and 020 describe things a business reader would recognise as capabilities. |
| nf-app-home | 5 | Template authoring, publishing, editing, rule-matching behaviour |
| nf-app-account | 3 | Agency ruleset authoring, publishing, completeness checks |

---

## 2. Reading those specifications safely

Three rules, because the documents will otherwise mislead you:

1. **Ignore each spec's `Status:` field.** It was never maintained and is
   effectively inverted — most shipped features still say `Draft`, and the ones
   marked `Implemented` are the least documented.
2. **A ticked task is not evidence that something works.** Roughly one completed
   task in nine records what actually landed. The rest are just ticks. Where the
   notes do exist — mainly in the two frontend applications — they are excellent,
   and record reversals and changes of plan honestly.
3. **Read the top of a specification before the body.** Several were amended in
   place, and the note at the top sometimes withdraws what the rest of the
   document still describes at length. Three specifically:
   - the Python audit-trail spec (007) describes a design that was **reverted**;
   - the Python ledger spec (012) is marked **superseded**, but its requirements
     still read as current;
   - the Python chain-completeness spec (013) describes a *disclosing* capability
     that was **removed from scope** at the 2026-09-28 meeting.

Two files are unusable rather than misleading: `nf-ndc-adapter-rs`'s spec 003 is
corrupted and enormous — skip it — and a completion claim for a "Feature 016"
rule-management screen in the rules engine describes work that is not in that
repository. That capability was genuinely built, but in nf-app-home and
nf-app-account. Count it once, there.

---

## 3. Outstanding defects that affect functionality

Grouped by what a business reader would care about. Identifiers in brackets are
for looking up the detail in `open-defects.md`. Everything here is **open as of
2026-09-29**.

### Cancellation, refunds and reversals — the live epic

This is where the current work sits, and it carries the most open items.

- **Every transaction is recorded as a sale**, including an order change that
  carries a refund or downgrade. Nothing marks or buckets it as a refund. `[F3]`
- **If the rules engine fails during a cancellation, the reversal is silently
  skipped** — it sits inside the engine's own branch, so a failure suppresses it
  with no error. `[F11]`
- **A void reverses less than was charged** when a flight has already been flown
  at the time of the void. It should reverse the full amount. `[F15]`
- **Turning a fee off between ticketing and cancellation strands the charge** —
  the reversal then never posts at all. `[F20]`
- **Whether a cancellation is a void or a refund is decided twice**, from two
  different inputs, with nothing reconciling them — and one of the two has a
  logic fault that makes it take the refund path regardless. `[F9, F14]`
- **The cancellation screen never shows the agent what is about to be reversed.**
  The figures are fetched but not displayed. `[F12]`
- **The cancel confirmation takes the first offer returned without checking it is
  the right one** — void and refund use the same request shape. `[F13]`
- **A refund paid on the sub-agency's own card credits the balance twice.** `[F26]`
- **Every refund in the development database credits nothing.** This needs
  checking against production before it is treated as real. `[F30]`

### Reissues and exchanges

- **A reissue's fee is filed against the superseded ticket, not the new one**, so
  the live ticket's ledger row shows nothing. `[F21]`
- **A reissue cannot be distinguished from a first issue** on one of the pricing
  surfaces, so a reissue-specific fee cannot be expressed there. `[F4]`
- **A reissued document would be charged a per-issue fee it should not be** — the
  system always reports a document as a first issue. Not yet reachable in
  production. `[F35]`
- **Republishing a rule re-prices documents that were already issued**, so a
  ticket issued under one version gets re-evaluated against a newer one on the
  next retrieval. A fix is planned. `[F22]`
- **On a ticket record, the amounts update but the formula is frozen** — and the
  reversal uses the frozen one, so the two can disagree. `[F16, F19]`

### Multi-agency chains and the credit ledger

- **Every sub-agency's credit limit is consumed by the fees it charges its own
  customers**, rather than by what it owes its supplier. `[F27]`
- **The sale posted to the ledger is wrong at every level below the first** in a
  resale chain. `[F29]`
- **The record of which rule priced a charge is lost below the top level**, which
  blocks reversal at those levels. A fix is scoped. `[F28]`
- **The ticket total can vary depending on row order**, and does not record
  whether it was properly derived or merely defaulted. `[F32, F33]`
- **When the chain lookup finds no match, the ledger falls through with an
  unresolved result** rather than reporting it. `[F31]`

### Rules that silently do nothing

This family matters more than its size suggests: each produces a plausible number
or a silent zero rather than an error, so nothing alerts anyone.

- **The legacy rule engine has evaluated nothing since one of the early
  specifications repointed it** — yet six places still call it, and its authoring
  screen is still live and writable. **Rules authored there can never fire.** `[F25]`
- **Reshop fee and discount is currently zero, with no error**, on both backends.
- **There is no naming convention for a rule's output**, so the system falls back
  to guessing at a column name that nobody is required to use. `[F10]`
- **The engine's own worked-example corpus teaches a pattern that double-counts**
  on refunds. `[F23]`
- **Conjunction tickets are handled by matching text inside the old formula**, and
  the new engine has no equivalent — there are no formula strings to match. `[F24]`
- **"Unflown" has two contradictory definitions** in the same file, one live and
  one dead; reviving the wrong one would give a different answer. `[F18, F36]`
- **One sub-type name is hard-coded in four separate places** across four
  repositories, so renaming it breaks matching silently in at least one. `[F6]`
- **The two backends break ties differently** when more than one rule matches. `[F5]`

### Currency and rounding

- **No currency travels with the amount.** The agency authors a bare number, the
  engine returns it untagged, and the backend applies it without checking it is
  denominated in the order's currency. `[F1]`
- **Three different rounding behaviours exist across the stack**, and currencies
  with no decimal places are rounded to two — a visibly wrong figure. `[F2]`
- **What the ledger stores is not exactly what the engine computed**, and the gap
  widens with each level of a resale chain. Harmless today; untested under
  reversal. `[F34]`
- **The booking screen shows fee and discount figures with no currency at all**,
  always to two decimal places. `[F8]`
- **The discount breakdown on that screen corrupts** if a discount's name contains
  a space or a colon, displaying a meaningless value with no error. `[F7]`

### When the rules engine is unavailable

- **The two backends behave in opposite ways during the same outage.** One fails
  the request outright — the customer sees an error, no money is lost. The other
  lets the order book **without any fees applied**. The same incident therefore
  produces either an availability problem or a revenue loss, depending on which
  path the request took. This is a business decision waiting to be made, not
  merely a defect. `[N1]`

### Data integrity

- **A uniqueness rule that the system appears to declare on ticket transactions
  has never actually existed**, so duplicates are possible. `[F17]`

---

## 4. What is deliberately not in that list

`open-defects.md` also holds items that are real but outside a functional scope
document — security and tenant isolation, rule-authoring internals, and
performance. They are tracked; they are simply not scope questions.

It also has a section, **"Checked and clean"**, recording what was investigated
and found *correct*. That is worth as much to a reconciliation as the defects:
it marks where no work is needed.

Two things the PO should know are unfinished rather than defective:

- The **template metadata authoring** screen in nf-app-home — which lets staff
  declare how an agency may fill in each column — **has not been started.** Its
  consumer in nf-app-account is already built and has only ever been tested
  against fixed sample data. The two halves have never met.
- One engine capability — **treating an absent optional charge as zero** instead
  of producing a wrong result — is **blocked**, not merely incomplete. It affects
  money correctness.

---

## 5. Glossary

| Term | In plain language |
|---|---|
| **BRE / the rules engine** | The new system that decides fees and discounts |
| **Template** | The structure of a rule, defined by NuFlights staff — which columns exist |
| **RuleSet** | An agency's own values filled into that structure |
| **Rule type / sub-type** | What kind of charge — a service fee or a discount, and which variety |
| **Published / draft** | Whether a ruleset is live or still being edited |
| **Chain / chain level** | The resale path from the originating agency down to the customer |
| **Cascade** | Whether each level's charge is folded into the next level's cost base |
| **Credit ledger** | The running account between two organisations |
| **Void / refund / reissue** | Cancel before travel · cancel after payment · re-ticket a changed booking |
| **Flown / unflown** | Flight legs already travelled versus still to come — a refund is worked out against these |
| **Pin** | A record of exactly which rule version priced a charge, so a reversal can reuse it |
| **Parity** | The requirement that both backends produce identical results for the same rule |

---

## 6. Brief for the PO's Claude agent

Paste this, with the path to this repository.

> You are helping a Product Owner write a scope document for NuFlights' service
> fee and discount work, and reconcile the intended scope against what exists.
> Work at a business level. The PO does not want implementation detail, file
> names, or code.
>
> **Read `po-handover.md` in the `nf-ai-context` repository in full before
> opening anything else.** It explains how the repositories relate, which
> documents are reliable, and what is currently known to be broken. Where your
> own reading of a specification disagrees with it, follow the handover and say
> that you found a disagreement.
>
> Then:
> 1. `epics/NF-003-bre-fee-discount-migration/open-defects.md` — what is wrong
>    today, and the "Checked and clean" section for what was verified correct.
> 2. `CURRENT.md` — where the work stands and what awaits a decision.
> 3. Only then, individual `spec.md` files for the capabilities in question —
>    the `Input` line, User Stories, and the `FR-` and `SC-` sections. Nothing
>    else in those folders.
>
> **Do not** judge whether something is built from a specification's `Status:`
> field or by counting ticked boxes — both are unreliable here, and the handover
> explains why. If you cannot establish whether something works, say so plainly
> rather than inferring it.
>
> **Never reproduce a money amount, fare, fee, or commercial figure** from any
> file, even where one appears in an example — write "an amount". Do not include
> anything concerning individual employees.
>
> Skip `nf-ndc-adapter-rs/specs/003-ruleset-resolution/spec.md`; the file is
> corrupted and will exhaust your context.

---

**A caution on dates.** Everything here about what exists is a snapshot taken on
2026-09-29 against working trees that change daily. Capability and relationships
are durable; status is not. When an item in §3 is fixed, delete it rather than
leaving the warning standing.
