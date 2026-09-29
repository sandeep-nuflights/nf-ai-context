---
epic: NF-005
also-governs: NF-004
title: What each stage writes, per cascade state, on the sale and refund paths
status: reference — settled 2026-09-25, narrowed to cascade-only 2026-09-28
---

# Data flow — values by table, stage and cascade state

The contract both leaf specs implement. Read with the epic's "Cascade — the
two-column model" section for *why*; this file is *what lands where*.

> **Scope narrowed 2026-09-28 (Sandeep, after a meeting).** Disclosing is **out
> of this epic**. The ledger **always itemises** — `SALE` plus `FEE`/`DISCOUNT`
> lines — in both cascade states. What was the four-cell matrix is now two
> columns. The four-cell model is preserved in the epic's Retractions section,
> because it is the reasoning that produced the settlement rule and the rule
> outlives it unchanged.

**Running example.** Chain A (root) -> B -> C -> customer. Airline base 1000,
tax 500. Fees: A->B 5% of base, B->C 10%, C->customer 20%. Cancellation penalty
200.

| | A->B | B->C | C->cust | B owes A | C owes B | customer |
|---|---|---|---|---|---|---|
| **cascade ON** | 50 | **105** | **231** | 1550 | **1655** | **1886** |
| **cascade OFF** | 50 | 100 | 200 | 1550 | 1600 | 1700 |

Cascade ON is the legacy behaviour and the only state ever run in production.

**Cascade acts in stage 1 and nowhere else.** It changes `provider_base_amount`,
and every later figure follows arithmetically. **No stage after stage 1 branches
on the flag** — stages 2, 3 and 4 carry whatever stage 1 resolved. This is the
single most important property of the design: the ledger needs no cascade logic,
no chain walk and no configuration read.

---

## Stage 1 — `FullfilmentOrdersPriceAdjustments`

One row per (level, document, pax, `adjustment_kind`, `adjustment_sub_kind`).
`seller_organization` is the org **applying** the rules, not receiving them.

| column | what it holds | cascade ON | cascade OFF | owner |
|---|---|---|---|---|
| `subscription_sequence_no` | chain level; 0 = root applying its SUB_AGENCY rules | 0,1,2 | 0,1,2 | prod |
| `ruleset_applied_to` | `SUB_AGENCY` (inter-agency) or `CUSTOMER` | seq 0,1 = SUB_AGENCY; seq 2 = CUSTOMER | same | prod |
| **`provider_base_amount`** | **the rule-input base** — what the rules compute on. **The only column cascade touches.** | 1000 / **1050** / **1155** (compounds) | 1000 / 1000 / 1000 | **prod — meaning fixed** |
| `provider_tax_amount` | tax; **never cascades in either state** | 500 / 500 / 500 | same | **prod — meaning fixed** |
| `adjustment_amount`, `adjustment_base_amount` | this level's own charge | 50 / **105** / **231** | 50 / 100 / 200 | ours |
| `adjustment_tax_amount` | **0 in both states** — reserved for undisclosed-tax, deferred | 0 | 0 | ours |
| `cascade_fee`, `cascade_discount` | the setting **as applied**, not as currently configured. Written per row by `get_rules()` (spec 013) | true | false | ours |
| `composite_version` | the pin; already written at **every** level | present | present | ours |
| `bre_amount` | the exact `Decimal` amount | see **F28-fix** | same | ours |

**The mechanism, in one place.** `get_order_items_price_adj()`
(`utils.py:4795-4804`) adds the previous level's `adjustment_amount` into
`provider_base_amount` when the flag is on:

```
provider_base(n) = airline_base + ( cascade_fee(n-1)      ? fee(n-1)  : 0 )
                                - ( cascade_discount(n-1) ? disc(n-1) : 0 )
```

Two independent booleans, so a mixed chain falls out for free: A->B off with
B->C on leaves A's fee at B, which is what "not passed to the next buyer" means.

**Refund path:** identical rows re-derived from the refund base. On a *full*
cancellation the base is unchanged, so every amount reproduces the sale exactly.
On a *partial* the refundable base is lower and the amounts genuinely differ.
**Open: whether the refund persists rows at all** (epic ambiguity 3).

---

## Stage 2 — `TicketOrgTransactions`

One row per org per ticket transaction. A refund creates a **second** row
(`txn_coupon_status = 'Refunded'` beside `'Ticketed'`) — verified on live data,
which is what lets the reversal carry its own entries without touching the sale
row.

`*_sell` is the **buy** side (what this org owes its supplier); `*_net` is the
**sell** side (what it charges its buyer). The names are inverted against their
contents — see **F27**.

The two halves come from **different row sets** in `create_ticket_org_tnx()`:

- `*_sell` <- `supplier_fo_price_adjs` — the **supplier's** rows (`utils.py:832-835`)
- `*_net`  <- `seller_ticket_price_adjs` — **this org's own** rows (`utils.py:836-839`)

and both bases are fee-inclusive: `get_ticket_price_adj()` returns
`provider_base + (fees - discounts)`.

**Cascade ON**

| org | `base_sell` | `fee_sell` | `disc_sell` | `total_sell` | `base_net` | `fee_net` | `total_net` |
|---|---|---|---|---|---|---|---|
| A (root) | 1000 | 0 | 0 | 1500 | 1050 | 50 | 1550 |
| B | 1050 | 50 | 0 | 1550 | **1155** | **105** | **1655** |
| C | **1155** | **105** | 0 | **1655** | **1386** | **231** | **1886** |

**Cascade OFF**

| org | `base_sell` | `fee_sell` | `disc_sell` | `total_sell` | `base_net` | `fee_net` | `total_net` |
|---|---|---|---|---|---|---|---|
| A (root) | 1000 | 0 | 0 | 1500 | 1050 | 50 | 1550 |
| B | 1050 | 50 | 0 | 1550 | 1100 | 100 | 1600 |
| C | 1100 | 100 | 0 | 1600 | 1200 | 200 | 1700 |

`ticket_refund_amount` holds the airline's refund figure — the **input** to the
chain, not the credited amount (**F30**: zero on all 20 entries in dev).

The six per-sub-type columns (`ticket_standard_service_fee` and friends) split
`fee_net`/`disc_net` by sub-kind and must sum to them with no residual
(invariant I12).

**No cascade flag is read at this stage**, and no column is added. The figures
arrive already resolved.

### Two assertions that come free from these tables

1. **`total_net(n-1) == total_sell(n)`** — holds in **both** cascade states,
   because both sides read the same adjustment rows through the same function.
   A break here means the supplier/seller row scoping is wrong.
2. **`base_net(n-1) == provider_base_amount(n)` (stage 1)** — holds **only when
   cascade is on**, and must *not* hold when it is off. This is the cascade
   itself, visible as a column match across stages, and it is a far better test
   than comparing fee amounts: it asserts the mechanism rather than its output.

---

## Stage 3 — `TicketOrgRuleApplication`

Write-once, one row per (charge, `adjustment_kind`, `adjustment_sub_kind`).

| column | what it holds |
|---|---|
| `ticket_org_transaction` | **the org's own row** |
| `adjustment_kind`, `adjustment_sub_kind` | from the adjustment row |
| `composite_version`, `rule_set_id`, `rule_set_version`, `template_version` | the pin, decomposed |
| `amount` | `bre_amount` — on a refund row, **the re-evaluated amount, never a copy of the sale's** |
| `currency` | the order evaluation currency |
| `transaction_type` | the **rule-match** type — always `SALE`, including on a reversal |
| `cascade_fee`, `cascade_discount` | projected from the adjustment row, so the reversal reproduces what was applied rather than what is configured now |
| `bre_evaluation_log_id` | soft reference into the BRE's own log |

**Two structural facts the implementation must respect:**

1. **Off by one level.** An org's rule applications record its *own* charges,
   while the ledger entries on the same row are its *supplier's*. The pin needed
   to reverse B's charge sits on **A's** row. Reversal walks to the parent.
2. **`transaction_type` is two concepts.** The **context** type (`REFUND`/`VOID`)
   drives `per_segment` / `per_ticket` / `per_ticket_issue` derivation; the
   **rule-match** type (always `SALE`) decides which decision-table row matches.
   They are one hardcoded string today (`content_rules.py:7029` -> `:7156`). If
   they stay one field, the first person to "fix" cancellation by setting it to
   `REFUND` silently changes row matching. This column stores the **rule-match**
   type.

---

## Stage 4 — `LedgerEntry` / `LedgerTransaction`

`pricing_source = RULES`. Root orgs get no account and no entries
(`utils.py:1880-1884`). `ruleset_applied_to = CUSTOMER` rows never reach the
ledger — which falls out of the existing `SUB_AGENCY` filter, not from a special
case.

**One rule, both cascade states, no flag read.**

### Sale

```
SALE = total_sell - fee_sell + disc_sell   (DEBIT)
FEE  = fee_sell    (DEBIT)
DISCOUNT = disc_sell   (CREDIT)
```

### Refund / void

**Textually identical, credited instead of debited**, on the **refund row**:

```
REFUND = total_sell - fee_sell + disc_sell   (CREDIT)
FEE    = fee_sell    (CREDIT)
DISCOUNT = disc_sell   (DEBIT)
```

`VOID` uses the same shape with `entry_type = VOID`.

> **Corrected 2026-09-28.** This file and NF-004 previously recorded
> `REFUND = total_sell - fee_sell`, dropping `+ disc_sell`. That credits
> `total_sell - disc_sell` against a debit of `total_sell`, leaving `disc_sell`
> as a **permanent residue** on every account that received a discount — and
> only on those accounts. It contradicted **T2** below, which is how it was
> caught. The refund formula is the sale formula; there is no second formula.

### Worked — B and C

| cascade | account | sale | full cancellation | net on this document |
|---|---|---|---|---|
| ON | B | SALE 1500 + FEE 50 | REFUND 1500 + FEE 50 | 0 |
| | C | SALE **1550** + FEE **105** | REFUND **1550** + FEE **105** | 0 |
| OFF | B | SALE 1500 + FEE 50 | REFUND 1500 + FEE 50 | 0 |
| | C | SALE 1500 + FEE 100 | REFUND 1500 + FEE 100 | 0 |

Note C's `SALE` under cascade ON: **1550 is B's own `total_sell`**. C is debited
its supplier's cost and the two agencies' books meet. Under cascade OFF it is
1500, the airline total, because A's fee genuinely stopped at B.

That contrast **is F29**. 012 posted `airline_supplier_price()` — a flat 1500 —
in both. Cascade-off makes that right by coincidence; cascade-on under-debits C
by exactly A's fee, inherited in C's price but never in C's ledger.

### The two invariants

> **1. `SALE + FEE - DISCOUNT == ticket_total_amount_sell`, in both cascade
> states.**
>
> **2. A full cancellation unwinds the document to zero at every level.**
> Nothing retained, nothing lost — which is D8 exactly, and why the *refund
> charge* is a missing capability rather than an optional extra.

### The airline penalty is not here

It is issued as a separate **`Y`-type EMD** and settles through the ordinary
sale path — `utils.py:2821` filters exactly that, and `Y` documents post `SALE`
entries and only `SALE` (186 documents in the corpus). No penalty entry type is
needed, and none should be added. See NF-004 "Entry types".

---

## Acceptance tests this contract implies

| | test |
|---|---|
| **T1** | For every posted charge: `SALE + FEE - DISCOUNT == ticket_total_amount_sell`. |
| **T2** | A full cancellation with no penalty nets every account to zero, at every level. Catches drift in the pin, the context reconstruction, the cascade flags and the rounding in one assertion. |
| **T3** | ~~Disclosed vs undisclosed shape~~ — **withdrawn 2026-09-28** with the disclosing scope. Replaced by **T3'**. |
| **T3'** | `base_net(n-1) == provider_base_amount(n)` when `cascade_fee(n-1)` is true, and **not** when it is false. Asserts the cascade mechanism at its only point of action, rather than asserting a fee amount downstream of it. |
| **T4** | ~~Re-deriving `total_sell` by the carry recurrence~~ — **withdrawn 2026-09-28.** The carry recurrence existed only for case 4 (cascade on + disclosed), which leaves with the disclosing scope. `total_sell`'s derivation therefore never changes, and there is no window to capture a baseline before. |
| **T5** | A partial cancellation prorates a %-of-base fee, prorates a per-segment fee by unflown segments, and returns a per-ticket fee **in full** — three behaviours, asserted separately so none is adopted by accident. |
