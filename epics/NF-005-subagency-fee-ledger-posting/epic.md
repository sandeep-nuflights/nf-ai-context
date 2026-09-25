---
epic: NF-005
parent: NF-003
title: Sub-agency fee/discount posting to the credit ledger
shape: solo
status: implemented 2026-09-24 — **F29 open**: the shipped SALE basis is wrong below the first chain level; cascade x disclosing model recorded 2026-09-25
created: 2026-09-23
money-impact: yes
rollout: forward-only
blocked-by: []
leaf-specs:
  nf-ndc-adapter-generic:
    - 012-subagency-fee-ledger-posting   # drafted 2026-09-23, implemented 2026-09-24
not-affected: [nf-ndc-adapter-rs, nf-app-workbench, nf-app-home-v2]
follow-up-needed:
  - BRE-evaluated commission (no leaf spec yet) — see Implementation record
---

# Sub-agency fee/discount posting to the credit ledger

Split out of NF-004 on 2026-09-23: this is **new build on the sale path**, not
parity on the cancellation path, so it cannot sit under NF-004's mirror gate.

## The principle — settlement question closed 2026-09-23

> **An org's `SALE` debit is what it owes its *supplier* — never what it charges
> its *buyer*.**

The credit ledger measures exposure between two organisations. An agency's own
markup on the traveller is its own money: it is collected from the customer,
never passes to the parent, and must not consume the agency's credit limit.

This closes the question the epic was blocked on. It was previously answered the
other way — see **Retractions**.

## What the ledger should carry

Per chain level that has an account:

| Entry | Amount | Direction |
|---|---|---|
| `SALE` | **provider price only** — airline base + tax | DEBIT |
| `FEE` | the **supplier's** `SUB_AGENCY` fee on this org | DEBIT |
| `DISCOUNT` *(new type)* | the supplier's `SUB_AGENCY` discount | CREDIT |
| `COMMISSION` | ~~as today~~ **superseded, see Implementation record — retired from config, not replaced; never posts on a new sale** | CREDIT |
| the org's **own** `CUSTOMER` fee/discount | — | **never posted** |

Every inter-agency amount is its own entry. This is also the shape the
configuration engine already has: its fee was always separate, never folded into
the sale.

**Posting happens at ticketing**, in the same transaction as the `SALE` debit and
spec 010's pin — not at order create. An unticketed order is not a sale.

## Worked cases

Illustrative figures: provider price **1100**; customer fee **50**; sub-agency
fees **20** (Root→SA1) and **30** (SA1→SA2).

### 1. Root → Customer

**Nothing posts, today and under this design.** Verified: the whole posting block
sits inside `if fo.shared_subscription:` (`utils.py:1879`), and a root org's row
hits an explicit early return at `:1880-1884`. Root collects from the traveller
directly; there is no counterparty to settle with.

### 2. Root → SA (fee) → Customer (fee)

| Entry | Today | This design |
|---|---|---|
| `SALE` on SA | DEBIT **1150** | DEBIT **1100** |
| `FEE` on SA | missing unless configuration-driven | DEBIT **20** |

SA collects 1150, owes 1120, keeps **30** — its own 50 less Root's 20.

### 3. Root → SA1 (fee) → SA2 (fee) → Customer (fee)

| | A(SA1 with Root) | A(SA2 with SA1) |
|---|---|---|
| `SALE` today | DEBIT 1100 **+ SA1's own `SUB_AGENCY` row** | DEBIT **1150** |
| `SALE` here | DEBIT **1100** | DEBIT **1100** |
| `FEE` here | DEBIT **20** | DEBIT **30** |

SA2 collects 1150, owes 1130, keeps 20. SA1 receives 1130, owes 1120, keeps 10.
Root receives 1120, pays the airline 1100, keeps 20. **Every level's margin is
its own fee minus its supplier's fee**, all the way up.

**The provider price is debited once per hop, and that is correct** — each hop is
a separate obligation in a chain of back-to-back sales, with its own account.
Confirmed in data: 122 tickets carry `SALE` entries, **14 on more than one seller
org**, up to **3** levels on one ticket.

## The two defects this closes

**1. The `SALE` debit carries the wrong figure.** `ticket_total_amount_net` is
built from the org's **own** adjustment rows —
`base + (own fees − own discounts)`, then `+ tax` (`utils.py:4290`, `:4340`) —
and the ledger posts it verbatim (`:1256`). That is the **sell** price. So every
sub-agency's credit limit is consumed by its own customer fees, on every ticket:
in case 2, 1150 of credit used where 1120 is owed. The more an agency charges its
customers, the less it can sell. Logged as **F27**.

The column names are inverted against their contents: `*_net` holds own-rules
figures (the sell price), `*_sell` holds supplier-rules figures (the cost). The
ledger posts the wrong one of the two.

**2. A sub-agency fee authored as a rule never reaches the ledger.**
`EntryType.FEE` and `EntryType.COMMISSION` are created at `ledger_service.py:85`
and `:113` and **nowhere else**, from configuration only. A BRE `SUB_AGENCY` rule
produces an adjustment row owned by the **seller**, which inflates the seller's
own `net` and debits nobody. One transfer, wrong payer.

The configuration engine never had this problem **structurally**: its fee is a
formula on the relationship and never becomes an adjustment row, so it cannot
pollute anyone's `net`. This design restores that separation by rule rather than
by accident.

## Why this is new build, not a migration

| Engine | Calculates | Posts a ledger entry |
|---|---|---|
| **#1** legacy ruleset (`OrgMasterRuleSet`) | **inert** since spec 004 repointed the FKs — *"that m2m has been empty for every order written since"* (`content_rules.py:4877-4880`); still called at six sites (**F25**) | never did |
| **#2** fee/commission configuration | yes | **yes — the only one** |
| **BRE** | yes | **no** |

The BRE replaced #1's calculation. Nothing replaced #2's posting.

**It mimics the configuration engine structurally, not substantively.** Same
account, same directions, same moment, same reversal mechanics — but config has
one fee and one commission per relationship with no sub-types, no discount
concept in the ledger at all, a different amount basis (ticket-derived tokens
versus the order-level evaluation context), a different control surface
(`*_enabled` flags versus ruleset mapping), and the conjunction-ticket rule
(**F24**). **So it cannot be parity-gated against configuration output**, which
is why this epic is `solo` and not `mirror`.

## Leaf spec

`nf-ndc-adapter-generic/specs/012-subagency-fee-ledger-posting/spec.md`, drafted
2026-09-23 — five user stories, 14 requirements, eight success criteria. Its
four open questions are decisions 1-3 and 5 below, restated at spec altitude.

## Implementation record (2026-09-24)

Shipped by `nf-ndc-adapter-generic` PR for spec 012, same day as the design
above was settled. All five "Remaining decisions" below are now resolved —
kept as a record of what was open, not as open items.

**No switch, no phased rollout.** The plan going in (a `LEDGER_SUPPLIER_BASIS`
env flag, "Release A" guard then "Release B" cutover) was **replaced mid-build,
by explicit instruction**: retire the old basis and configuration-based fee
outright, unconditionally, the same day. There is no flag and no old code path
left for fee/sale-basis — a rollback means redeploying old code, not flipping a
setting.

**Commission: retired from configuration, NOT replaced.** This is a deliberate
scope cut made mid-build, not an oversight — the epic's own principle
("**it mimics the configuration engine structurally, not substantively**")
turned out to include commission, and BRE-evaluated commission is real, unbuilt
work: the rules service supports Commission rulesets (`Standard`/`Extra`
sub-types) but the adapter's own evaluation path
(`content_rules.py`'s `_BRE_RULE_TYPE_TO_LEGACY`, `bre_client.py`'s
`_OUTPUT_AMOUNT_KEYS`, the DISCOUNT/FEE candidate bucketing) has never been
extended to it. Concretely, since 2026-09-24: **no commission posts on any new
sale, on any relationship, until a future epic builds BRE commission
evaluation.** A relationship that used to earn commission via configuration
earns none now. This is a live, ongoing revenue gap, not a one-time cutover
cost — **flag this to whoever owns agency commercial relationships**, and see
`follow-up-needed` above for the epic this needs.

A **reversal-only remnant** of the old commission (and fee) code stays alive
in `ledger_service.py` for exactly one purpose: a ticket that was actually
charged the old way, before 2026-09-24, still reverses correctly on a later
void/refund, using the same configured formula it was charged with
(distinguished from a new, rules-sourced charge by the `pricing_source` column
now on `LedgerEntry`, added for this).

**Also deleted, same PR:** the dead pre-BRE rule engine —
`validate_rule()`/`validate_order_item()`/`apply_rule_on_order_items()`/
`apply_rule_on_ticket_docs()` in `content_rules.py`, confirmed to have zero
live callers anywhere in `backend/` (the F25 six call sites are all
`available_master_rule()`, a *different*, still-live function this deletion
did **not** touch — see below). **Not deleted**, and out of scope for this
PR: `OrgMasterRuleSet` the model, `available_master_rule()`, and its six live
call sites (`content_rules.py:1205,3964,4060,4988,5018,5059`) — the model is
still written to by live GraphQL mutations and has a live admin surface and a
real M2M field on `FullFilmentOrdersSellerSubscriptions`; retiring it is a
separate, materially larger change (mutations, admin, GraphQL type all need
rework) that F25 already tracked and this PR did not take on.

**A live production risk, confirmed on real local data, not just fixtures:**
the airline-price SALE basis needs a `Net`-typed `fareDetail` entry on the
ticket document, and **raises rather than silently falling back** when one
isn't there (deliberate — a silent fallback to the sell price would
reintroduce F27). Running the new `ledger_basis_report` management command
against local data found **3 real tickets** in a 30-day window with no `Net`
entry. Whether that is a normal, expected shape for some ticket/fare type, or
a defect, is **unresolved and needs investigation** before this is trusted in
a higher environment — it is not yet known whether this raises on any live
ticketing traffic today.

### Remaining decisions (resolved 2026-09-24)

1. **Idempotency grain — resolved: one row per (charge, entry type).** Enforced
   by a database `UniqueConstraint` on `LedgerEntry`, not application code alone
   (verified in `pg_constraint`, not just the Django model — a neighbouring
   model once lost a `unique_together` to a duplicate `class Meta` silently).
   The BRE sub-type breakdown is not lost — it stays on the adjustment rows,
   which remain the source of every FEE/DISCOUNT movement.
2. **A `DISCOUNT` entry type — done.** Added, with a `pricing_source`
   (`CONFIG`/`RULES`) column alongside it.
3. **Cutover double-charge — resolved by retiring configuration outright**,
   not by a guard that runs indefinitely. (An interim posting-time guard was
   built and shipped first, then made moot by the full retirement the same
   day — see the commit history on the leaf spec's `ledger_service.py`.)
4. **Existing rows — reconcile by report only.** `ledger_basis_report`
   explains the difference per account for historical tickets; nothing is
   back-posted.
5. **Amount-basis comparison before cutover — not done as a hard gate.**
   There was no cutover gate in the end (see "No switch" above). The report
   surfaces the difference after the fact, for whoever needs to explain a
   balance change; it was not used to block anything before this shipped.

## Cascade x disclosing - the four-cell model (2026-09-25)

Recorded after the shipped implementation was found to sit in none of the four
cells (**F29**). The sale path is settled here; the cancellation path follows in
NF-004.

### Two settings, not one

| | what it controls | where it lives |
|---|---|---|
| **Cascade** | does the supplier's fee/discount carry forward to the *next* buyer in the chain | `SharedSubscription.cascade_supplier_fee` / `cascade_supplier_discount` (`models.py:1930-1931`), honoured by the BRE path at `content_rules.py:5577-5586`, `:5664-5670`, `:5766-5776`, `:5847-5850`, `:6007-6016`, `:6091-6095` |
| **Disclosing** | is the fee shown to the buyer as its own ledger line, or folded into the sale amount | **does not exist** - new setting |

They are independent, and **compounding is not a third axis** - it falls out of
disclosure. An undisclosed fee literally *is* base fare, so a downstream
"% of base fare" rule picks it up and compounds. A disclosed fee is a line item,
so it does not. One cascade, two mechanisms.

### The four cells

Chain A (root) -> B -> C -> customer. Airline base 1000, tax 500.
A->B 5% of base, B->C 10%, C->customer 20%.

| case | A->B | B->C | C->cust | B owes A | C owes B | customer |
|---|---|---|---|---|---|---|
| 1 cascade on + undisclosed | 50 | **105** | **231** | 1550 | 1655 | 1886 |
| 2 cascade off + undisclosed | 50 | 100 | 200 | 1550 | 1600 | 1700 |
| 3 cascade off + disclosed | 50 | 100 | 200 | 1550 | 1600 | 1700 |
| 4 cascade on + disclosed | 50 | 100 | 200 | 1550 | **1650** | 1850 |

**Case 1 is the legacy behaviour** and the only cell ever run in production -
the legacy rules engine folded the fee into `base_fare` and never posted a
ledger line, so it was permanently undisclosed; the configuration engine posted
a line and never touched the price, so it was permanently disclosed and
cascade-off. **Disclosed + cascade-on (case 4) has no precedent**, so the parity
gate has no baseline for it - it must be verified against the identity below,
not against recorded history.

**Disclosure changes money when cascade is on** (1886 vs 1850). It is a
commercial renegotiation, not a display preference, and cannot be flipped once
tickets exist.

### The settlement rule - no cascade logic in the ledger

```
disclosed:    SALE = total_sell - fee_sell + disc_sell ;  FEE = fee_sell ;  DISCOUNT = disc_sell
undisclosed:  SALE = total_sell
```

One flag read. The cascade never reaches the ledger, because the pricing pass
has already resolved it into `total_sell` by the time settlement runs. The
invariant that holds in all four cells:

> **SALE + FEE - DISCOUNT == `ticket_total_amount_sell`**

Itemisation is of the **immediate relationship only** (decided 2026-09-25):
C sees `SALE 1550 + FEE 100`, not `SALE 1500 + FEE 150`. C has a contract with
B, not with A; what B paid upstream is B's business, and the alternative
discloses the whole chain's margin to the last buyer.

### The corrected `total_sell` derivation

`provider_base_amount` is the **rule-input** base, not the settlement base -
verified on booking 17657619260540, where seq 1's adjustments are exactly
0.910x seq 0's, the same ratio as 1483.30/1630. Under compounding the two
coincide, which is why nothing had broken. Under cases 2-4 they diverge, and
under case 4 the existing parent-row formula cannot see the grandparent's fee at
all: it is in neither the parent's `provider_base` (no compounding) nor the
parent's `adjustment_amount` (not the parent's charge).

```
carry_fee(n)  = fee(n-1)  + ( cascade_fee(n-1)      ? carry_fee(n-1)  : 0 )
carry_disc(n) = disc(n-1) + ( cascade_discount(n-1) ? carry_disc(n-1) : 0 )
total_sell(n) = airline_total + carry_fee(n) - carry_disc(n)
```

The immediate supplier's charge always counts; anything above it counts only
while each level's **recorded** cascade flag is on. Two accumulators, because the
two flags are independent booleans.

| | carry(B) | `total_sell(B)` | carry(C) | `total_sell(C)` |
|---|---|---|---|---|
| case 1 | 50 | 1550 | 105 + 50 = 155 | **1655** |
| case 2 / 3 | 50 | 1550 | 100 + 0 = 100 | **1600** |
| case 4 | 50 | 1550 | 100 + 50 = 150 | **1650** |

A mixed chain falls out for free: A->B off with B->C on gives C 1600, because
A's fee stops at B - which is what "not passed on to the next buyer" means.

**This changes no production field's meaning.** `ticket_total_amount_sell`
already means "what my supplier charged me"; for C in case 4 that *is* 1650. The
derivation is being completed, not redefined. And it cannot disturb existing
data, because for cases 1-3 the new and old formulas are provably equivalent -
when the fee compounds, `provider_base` already contains the history. Verified:

| org (booking 17657619260540) | parent-row formula | airline + carry |
|---|---|---|
| NF APEX SUB | 2633.30 | 2780 + (102.69 - 249.39) = 2633.30 |
| NF APEX SUB2 | 2499.803 | 2780 - 146.70 - 133.497 = 2499.803 |

`ticket_base_amount_sell` changes derivation the same way and is equally
equivalent (1630 - 280.197 = 1349.803).

### Field ownership - what may and may not change

Established from row counts by year, 2026-09-25:

| field | 2024 | 2025 | 2026 | verdict |
|---|---|---|---|---|
| `provider_base_amount`, `provider_tax_amount` | 646 | 2165 | 1693 | **production - meaning fixed** |
| `ticket_total_amount_sell` / `_net` | 429/428 | 2738/2737 | 1513/1512 | **production - meaning fixed** |
| `ticket_base_amount_sell` | 423 | 2546 | 1467 | **production - meaning fixed** |
| `adjustment_amount`, `adjustment_base_amount` | 0 | 0 | 366 | ours |
| `adjustment_tax_amount` | 0 | 0 | 0 | ours |
| `ticket_service_fee_sell` / `ticket_discount_sell` | 0 | 0 | 10 | ours |
| `cascade_fee` / `cascade_discount` | 0 | 20 | 10 | ours |

A field being "ours" means no production reader depends on it. A production
field's *computation* may still be corrected where the corrected value is what
the field always claimed to mean and no existing row changes.

### The pipeline, stage by stage

Column-by-column values per stage and per cell are in
[`data-flow.md`](./data-flow.md) — the contract both leaf specs implement.


| stage | what carries the model |
|---|---|
| **1. `FullfilmentOrdersPriceAdjustments`** | `provider_base_amount` = rule-input base (unchanged meaning). Rule input = `provider_base` when cascade-on **and** undisclosed (case 1 only), else the airline base from the ticket document - derived, never stored. Newly written: `cascade_fee`/`cascade_discount` (two keys, two dicts at `content_rules.py:7345`, `:7398`) and the new disclosing flag. |
| **2. `TicketOrgTransactions`** | `total_sell` / `base_sell` from the carry recurrence above; `fee_sell` / `disc_sell` = the immediate supplier's charge. **This is the only stage that reads a cascade flag.** |
| **3. `TicketOrgRuleApplication`** | pin + amount per (kind, sub-kind), write-once, plus both flags projected. **Off by one level:** an org's rule applications record its *own* charges, while the ledger entries on the same row are its *supplier's*. The pin needed to reverse B's charge sits on **A's** row - reversal must walk to the parent. |
| **4. Ledger** | the settlement rule above. Two lines, one flag, no cascade, no chain walk. |

### Deferred

- **Case 4 (cascade on + disclosed)** - buildable via the carry recurrence, but
  it has never run and nothing depends on it. Defer until the disclosing setting
  exists. **The carry recurrence belongs to this deferral, not to Phase 1**
  (refined 2026-09-25): cases 1-3 are served by the existing parent-row
  derivation, so nothing needs the recurrence until case 4 does. The cost of
  deferring is that case 4 then changes a derivation after tickets exist under
  the old one — the trade recorded here so it is made knowingly.
- **Undisclosed tax (fee carried as an undisclosed tax rather than base fare)** -
  deferred for a specific reason, not merely because it is unconfirmed: **tax
  carries a full-refundability rule that the reversal's proration cannot
  honour.** A fee sitting in tax would be contractually refundable in full while
  a part-flown refund re-evaluates it prorated. Base-fare undisclosing has no
  such rule attached and prorates without contradiction.
- **The refund charge** (a cancellation-time fee, as opposed to reversing the
  sale-time one) - still not built; see NF-004 D8.

### Phase 1 implemented, uncommitted — 2026-09-25

`ledger_sale_amount()`'s SALE branch now returns
`total_sell - fee_sell + disc_sell` behind two guards. Code complete, tests
written, **tests not run** (Django `TestCase` creates a database; database
access on this work is read-only). Verified by a no-DB unit exercise and by
read-only SELECTs against live ticket 17657619260540: NF APEX SUB2's new SALE
differs from the posted figure by exactly the over-debit, and NF APEX SUB's is
**identical** — the compatibility case confirmed on real rows, which is the
evidence that this generalises the old rule rather than replacing it.

**The guard nearly shipped a regression, and the finding outlasts the fix.**
The first brief keyed the guard on `ticket_total_amount_sell` alone. But
`create_ticket_org_tnx()` pre-seeds that column with the ticket's own
`ticket_price_amount` **before** the supplier branches run (`utils.py:~784`),
and overwrites it only when the airline price parses. So on a document with no
parseable `Net` fare the column holds a plausible default that is *not* what the
org owes its supplier — and the guard would have posted it. Measured on the dev
database: **2946 rows** where 012 refused would have begun posting, and in a
1200-row sample **1197** carried exactly `ticket_price_amount`.

That is the "plausible fallback" this design exists to refuse, arrived at by
specifying the guard against the wrong column. The fix keeps 012's refusal
(`airline_supplier_price(...) is None`) as an **independent** condition, on the
reasoning that *a document whose pricing cannot be parsed is a refuse-to-post
condition in its own right, regardless of which figure we would then post* — and
it is level-independent, since it is the same document at every level. Net
effect: **zero rows change behaviour on the guard axis in either direction**.

Recorded as **F33**, because the underlying defect stands: `total_sell` does not
say whether it was derived or defaulted, and 012 was protected only by accident.
**F32** was raised in the same pass — `get_ticket_price_adj()` reads
`provider_base_amount` off the first row of an *unordered* queryset while
`get_adjustment_aggregate()` takes `Max()` of the same column, and Phase 1 makes
a live credit-account debit depend on which answer wins.

**Not committed.** `utils.py` carries Phase 1, spec 013's partial
implementation and other sessions' work simultaneously, so it cannot be staged
wholesale — see the leaf repo's
`specs/013-rule-application-completeness/handover.md` §3b for the grep tags that
separate them.

### Open questions

| | question | why it blocks |
|---|---|---|
| ~~Q1~~ | ~~Grain of the disclosing setting~~ | **Resolved 2026-09-25 (Sandeep): per subscription**, on `SharedSubscription` alongside `cascade_supplier_fee`/`cascade_supplier_discount`. Keeps the matrix square and lets a seller disclose to one partner and not another. |
| ~~Q2~~ | ~~Freeze the settlement chain~~ | **Resolved 2026-09-25 (Sandeep)**, and split in two — see NF-004 "Freezing the reversal". **Q2a:** the reversal's account comes from the original `SALE` `LedgerTransaction.account_id`. **Q2b:** the re-pricing walks the ticket's recorded `TicketOrgTransactions` levels. |
| ~~Q3~~ | ~~Disclosing needs new columns — acceptable exception to "no new columns"?~~ | **Resolved 2026-09-25 (Sandeep): yes, the disclosing setting can be added because it is purely additive.** Three places, all new and nullable, none changing an existing field's meaning: `SharedSubscription` (the live setting), `FullfilmentOrdersPriceAdjustments` (the record of what was applied, frozen per row), and `TicketOrgRuleApplication` (projected write-once, for the reversal). The setting cannot be read live at reversal time, because under cascade-on disclosure changes the money. |
| **Q4** | Both flags must be **excluded from `_PRICE_ADJUSTMENT_COMPARISON_FIELDS`**, and NULL disclosing on historical rows must read as **undisclosed**. | Including them rewrites every row on a config change (the T030 regression); everything in production is case 1. |

### Plan

| phase | work |
|---|---|
| **0 - unblock** | Fix the rule-application projection: project when `composite_version` exists, regardless of `bre_amount` (**F28**). Nothing below the root has rule applications today, so every later phase is untestable. Write `cascade_fee`/`cascade_discount` on the BRE path. *No behaviour change.* |
| **1 - close F29** | **Narrower than first planned (2026-09-25).** The ledger reads `SALE = total_sell - fee_sell + disc_sell` instead of `airline_supplier_price()`. That is **one branch of one function** — `ledger_sale_amount()`'s SALE arm (`utils.py:1269`). The carry recurrence is **not** needed here: `total_sell` as currently derived is already correct for cases 1-3, and case 4 is deferred, so Phase 1 changes no production field's computation — only which already-correct field the ledger reads. `airline_supplier_price()` itself stays: its second call site (`utils.py:820`, the root's `*_sell` from the ticket document) is correct. Closes **F29** and **F27**. |
| **2 - disclosing** | Add the setting (`SharedSubscription`), the per-row record (`FullfilmentOrdersPriceAdjustments`) and its projection (`TicketOrgRuleApplication`) — all additive, approved 2026-09-25. Implement the undisclosed shape. Default: NULL reads as undisclosed, since everything in production is case 1. |
| **3 - reversal** | NF-004 / spec 011. |

## Retractions

Recorded because each was briefly the plan of record.

- **"Remove the amount from the seller's net to avoid a double count"** — written,
  then retracted, now **reinstated** with a reason that needs no interpretation
  of the ledger: the configuration fee never enters the adjustment table, so
  `net` was never meant to carry inter-agency fees.
- **"`SALE` is a CREDIT that increases the balance."** Wrong — it is a DEBIT
  (`utils.py:1235-1256`); read from the `VOID` branch by mistake. The "parent
  collects from the traveller and credits the agency" reading built on it is
  withdrawn.
- **"The `SALE` debit is deliberately what the org charges its buyer."** Wrong.
  The configuration engine's internal coherence did not establish that the
  customer fee belonged in the debit. Closed the other way above.

## Relationship to other work

- **NF-004 / spec 011** does not wait on this. Its `charged` predicate is defined
  by **ledger entry type**, not by engine (**FR-005a**), so entries introduced
  here are reversed with no rework. **Now concrete, not hypothetical**: spec 011
  must reverse `FEE`, `DISCOUNT` and (still, for old charges) `COMMISSION` by
  entry type — this feature posts no reversal of its own `RULES`-sourced
  movements at all (only a `CONFIG`-sourced historical remnant), so spec 011 is
  the *only* thing that will ever reverse a new-style `FEE`/`DISCOUNT`.
- **D5** is reframed by this: the BRE takes over engine #2 entirely for **fee
  and discount** — but **not commission**, which this PR retired from
  configuration without replacing (see Implementation record). NF-004 covers
  the reversal half of fee/discount only; commission reversal for the
  historical remnant is unaffected (still config-formula-based).
- **A commission epic is now needed and does not exist yet** (`follow-up-needed`
  above). It would extend the BRE evaluation path
  (`content_rules.py`/`bre_client.py`) to Commission rulesets — confirmed
  supported by the rules service already — and post `COMMISSION` from rules the
  same way `FEE`/`DISCOUNT` now do. Until it lands, commission is a live
  revenue gap on every relationship that used to earn it via configuration.
- Composes with the audit-durability cluster: a new posting path inherits the
  same write-once-ledger constraints.
