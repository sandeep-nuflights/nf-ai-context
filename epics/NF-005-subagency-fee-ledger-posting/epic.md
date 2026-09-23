---
epic: NF-005
parent: NF-003
title: Sub-agency fee/discount posting to the credit ledger
shape: solo
status: draft — design settled 2026-09-23
created: 2026-09-23
money-impact: yes
rollout: forward-only
blocked-by: []
not-affected: [nf-ndc-adapter-rs, nf-app-workbench, nf-app-home-v2]
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
| `COMMISSION` | as today | CREDIT |
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

## Remaining decisions

1. **Idempotency grain.** `_write_fee_entry` guards on
   `(content_type, object_id, entry_type)` — exactly one `FEE` row per charge.
   Six BRE sub-types need either a wider key or a summed entry. **Not reversible
   once rows exist.**
2. **A `DISCOUNT` entry type**, not reused `COMMISSION`. `EntryType` already
   carries nine variants.
3. **Cutover double-charge.** A relationship carrying both a configuration fee
   and a BRE `SUB_AGENCY` rule is debited twice for one commercial charge. Guard
   in code, not by process.
4. **Existing rows** — back-post, leave, or reconcile. Bears on F27: correcting
   the `SALE` basis changes credit headroom for every live sub-agency.
5. **Amount-basis comparison before cutover.** Configuration reads the *ticket*
   after ticketing; the BRE reads the *order pricing entry*. **F19** exists
   because those can disagree, so a migrated relationship could get a different
   fee for the same booking with nothing flagging it. Compare on a real order
   first.

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
  here are reversed with no rework.
- **D5** is reframed by this: the BRE takes over engine #2 entirely — charge
  posting as well as reversal. NF-004 covers the reversal half only.
- Composes with the audit-durability cluster: a new posting path inherits the
  same write-once-ledger constraints.
