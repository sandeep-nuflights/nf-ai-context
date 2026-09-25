---
epic: NF-005
also-governs: NF-004
title: What each stage writes, per cascade/disclosing cell, on the sale and refund paths
status: reference — settled 2026-09-25
---

# Data flow — values by table, stage and cell

The contract both leaf specs implement. Read with the epic's "Cascade x
disclosing" section for *why*; this file is *what lands where*.

**Running example.** Chain A (root) -> B -> C -> customer. Airline base 1000,
tax 500. Fees: A->B 5% of base, B->C 10%, C->customer 20%. Cancellation penalty
200.

| cell | A->B | B->C | C->cust | B owes | C owes | customer |
|---|---|---|---|---|---|---|
| **1** cascade on + undisclosed | 50 | 105 | 231 | 1550 | 1655 | 1886 |
| **2** cascade off + undisclosed | 50 | 100 | 200 | 1550 | 1600 | 1700 |
| **3** cascade off + disclosed | 50 | 100 | 200 | 1550 | 1600 | 1700 |
| **4** cascade on + disclosed | 50 | 100 | 200 | 1550 | 1650 | 1850 |

Case 1 is the only cell ever run in production. Case 4 is deferred (see epic).

---

## Stage 1 — `FullfilmentOrdersPriceAdjustments`

One row per (level, document, pax, `adjustment_kind`, `adjustment_sub_kind`).
`seller_organization` is the org **applying** the rules, not receiving them.

| column | what it holds | case 1 | cases 2-4 | owner |
|---|---|---|---|---|
| `subscription_sequence_no` | chain level; 0 = root applying its SUB_AGENCY rules | 0,1,2 | 0,1,2 | prod |
| `ruleset_applied_to` | `SUB_AGENCY` (inter-agency) or `CUSTOMER` | seq 0,1 = SUB_AGENCY; seq 2 = CUSTOMER | same | prod |
| **`provider_base_amount`** | **the rule-input base** — what the rules compute on | 1000 / 1050 / 1155 (compounds) | 1000 / 1000 / 1000 | **prod — meaning fixed** |
| `provider_tax_amount` | tax; **never cascades in any cell** | 500 / 500 / 500 | same | **prod — meaning fixed** |
| `adjustment_amount`, `adjustment_base_amount` | this level's own charge | 50 / 105 / 231 | 50 / 100 / 200 | ours |
| `adjustment_tax_amount` | **0 in every cell** — reserved for undisclosed-tax, deferred | 0 | 0 | ours |
| `cascade_fee`, `cascade_discount` | **NEW WRITE** (columns exist, NULL on every BRE row today) — the setting **as applied**, not as currently configured | true | 2,3 false · 4 true | ours |
| `disclosing` | **NEW COLUMN** — as applied | false | 2 false · 3,4 true | new, additive |
| `composite_version` | the pin; already written at **every** level | present | present | ours |
| `bre_amount` | the exact `Decimal` amount | NULL below root today (**F28**) | same | ours |

**The rule-input base is derived, never stored separately:**

```
rule_input = provider_base_amount   if (cascade on AND undisclosed)   # case 1 only
           = airline base           otherwise                          # from the ticket document
```

**Refund path:** identical rows re-derived from the refund base. On a *full*
cancellation the base is unchanged, so every amount reproduces the sale exactly.
On a *partial* the refundable base is lower and the amounts genuinely differ
(500 / 525 / 577.50 -> fees 25 / 52.50 / 115.50). **Open: whether the refund
persists rows at all** (epic ambiguity 3).

---

## Stage 2 — `TicketOrgTransactions`

One row per org per ticket transaction. A refund creates a **second** row
(`txn_coupon_status = 'Refunded'` beside `'Ticketed'`) — verified on live data,
which is what lets the reversal carry its own entries without touching the sale
row.

`*_sell` is the **buy** side (what this org owes its supplier); `*_net` is the
**sell** side (what it charges its buyer). The names are inverted against their
contents — see **F27**.

| column | what it holds | B | C (case 1) | C (cases 2,3) | C (case 4) | owner |
|---|---|---|---|---|---|---|
| `ticket_base_amount_sell` | airline base + carry | 1050 | 1155 | 1100 | 1150 | **prod — meaning fixed** |
| `ticket_total_amount_sell` | airline total + carry | 1550 | 1655 | 1600 | 1650 | **prod — meaning fixed** |
| `ticket_service_fee_sell` | the **immediate** supplier's fee only | 50 | 105 | 100 | 100 | ours |
| `ticket_discount_sell` | the immediate supplier's discount only | 0 | 0 | 0 | 0 | ours |
| `ticket_base_amount_net`, `ticket_total_amount_net` | this org's own sell price — unchanged | | | | | **prod — meaning fixed** |
| `ticket_service_fee_net`, `ticket_discount_net` | this org's own charge | | | | | ours |
| `ticket_refund_amount` | the airline's refund figure, the **input** to the chain — not the credited amount (**F30**: zero on all 20 entries in dev) | | | | | prod |

**The derivation — this is the only stage that reads a cascade flag:**

```
carry_fee(n)  = fee(n-1)  + ( cascade_fee(n-1)      ? carry_fee(n-1)  : 0 )
carry_disc(n) = disc(n-1) + ( cascade_discount(n-1) ? carry_disc(n-1) : 0 )
total_sell(n) = airline_total + carry_fee(n) - carry_disc(n)
base_sell(n)  = airline_base  + carry_fee(n) - carry_disc(n)
```

Two accumulators, because `cascade_fee` and `cascade_discount` are independent
booleans. The immediate supplier's charge always counts; anything above it
counts only while each level's **recorded** flag is on — so a mixed chain
(A->B off, B->C on) correctly gives C 1600.

Provably equivalent to today's parent-row formula wherever the fee compounds,
so it cannot disturb any existing row. Verified on booking 17657619260540:
2780 - 146.70 - 133.497 = 2499.803, matching the recorded value.

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
| `cascade_fee`, `cascade_discount`, `disclosing` | **NEW** — projected from the adjustment row, so the reversal reproduces what was applied rather than what is configured now |
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

**Blocking defect.** `project_rule_applications` (`utils.py:898`) filters on
`composite_version__isnull=False` **and** `bre_amount__isnull=False`, so only the
root projects — 6 rows for NF APEX, **zero** for NF APEX SUB and NF APEX SUB2.
Until the filter is split, nothing below the root has rule applications and no
reversal can be exercised at all.

---

## Stage 4 — `LedgerEntry` / `LedgerTransaction`

`pricing_source = RULES`. Root orgs get no account and no entries
(`utils.py:1880-1884`). `applies_to = CUSTOMER` rows never reach the ledger —
which falls out of the existing `SUB_AGENCY` filter, not from a special case.

### Sale

```
disclosed:    SALE = total_sell - fee_sell + disc_sell  (DEBIT)
              FEE  = fee_sell   (DEBIT)      DISCOUNT = disc_sell  (CREDIT)
undisclosed:  SALE = total_sell  (DEBIT)
```

### Refund / void

Identical, sign-flipped, on the **refund row**:

```
disclosed:    REFUND = total_sell - fee_sell + disc_sell  (CREDIT)
              FEE    = fee_sell   (CREDIT)   DISCOUNT = disc_sell  (DEBIT)
undisclosed:  REFUND = total_sell  (CREDIT)
```

`VOID` uses the same shape with `entry_type = VOID`.

### Worked — B and C

| cell | account | sale | full cancellation | net on this document |
|---|---|---|---|---|
| 1 | B | SALE 1550 | REFUND 1550 | 0 |
| | C | SALE 1655 | REFUND 1655 | 0 |
| 2 | B | SALE 1550 | REFUND 1550 | 0 |
| | C | SALE 1600 | REFUND 1600 | 0 |
| 3 | B | SALE 1500 + FEE 50 | REFUND 1500 + FEE 50 | 0 |
| | C | SALE 1500 + FEE 100 | REFUND 1500 + FEE 100 | 0 |
| 4 | B | SALE 1500 + FEE 50 | REFUND 1500 + FEE 50 | 0 |
| | C | SALE 1550 + FEE 100 | REFUND 1550 + FEE 100 | 0 |

### The two invariants

> **1. `SALE + FEE - DISCOUNT == ticket_total_amount_sell`, in every cell.**
>
> **2. A full cancellation unwinds the document to zero at every level, in every
> cell.** Nothing retained, nothing lost — which is D8 exactly, and why the
> *refund charge* is a missing capability rather than an optional extra.

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
| **T3** | Switching a relationship from disclosed to undisclosed changes the ledger **shape** but not the **total** — when cascade is off. When cascade is on it changes both, by design (1886 vs 1850). |
| **T4** | Re-deriving `total_sell` by the carry recurrence reproduces every existing recorded value. Run before the derivation changes, not after. |
| **T5** | A partial cancellation prorates a %-of-base fee, prorates a per-segment fee by unflown segments, and returns a per-ticket fee **in full** — three behaviours, asserted separately so none is adopted by accident. |
