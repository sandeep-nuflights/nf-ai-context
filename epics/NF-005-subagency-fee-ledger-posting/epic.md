---
epic: NF-005
parent: NF-003
title: Sub-agency fee/discount posting to the credit ledger
shape: solo
status: stub — scoped 2026-09-23, not designed
created: 2026-09-23
money-impact: yes
rollout: forward-only
blocked-by: [settlement-model-confirmation]
not-affected: [nf-ndc-adapter-rs, nf-app-workbench, nf-app-home-v2]
---

# Sub-agency fee/discount posting to the credit ledger

**Stub.** Split out of NF-004 on 2026-09-23 because it is **new build on the sale
path**, not parity on the cancellation path.

## The gap

**An org is credited a sub-agency fee that its buyer is never debited.**

On a chained sale, each org's `ticket_total_amount_net` is computed from **its
own** adjustment rows (`utils.py:530-542`, `:608`, `:702-704`), and a
`SUB_AGENCY` rule belongs to the org that **authored** it — the seller. So a
seller's SALE credit already contains the fee it charges its buyer. But on the
**buyer's** row that same amount reaches only `*_sell`, a reported column
(`utils.py:709-713`, `:813`) — it never becomes a ledger movement.

The only thing that has ever debited the buyer is the **configuration engine**,
and only for amounts *it* computed: `EntryType.FEE` and `EntryType.COMMISSION`
are created at `ledger_service.py:85` and `:113` and **nowhere else in the
codebase**.

So for any sub-agency fee authored as a rule rather than as configuration, the
seller is credited and the buyer pays nothing. **This epic posts the missing
debit.** It is a correction, not a re-plumbing.

## Correction to an earlier reading

An earlier draft of this epic claimed the amount must first be **removed** from
the seller's net to avoid a double count, and that the customer-facing fee should
come out of the ledger amount. **Both were wrong** and are retracted. Under the
settlement reading below, the seller's net is *supposed* to include what it
charges its buyer, and the customer fee is *supposed* to be in the credit. The
defect is the absent debit, nothing else. Recorded because the wrong version was
briefly the plan of record.

## The sign convention, anchored

`_write_fee_entry` (`ledger_service.py:174-178`): **DEBIT → `balance -= amount`,
CREDIT → `balance += amount`.** A top-up is a **CREDIT that increases** the
balance (`mutations.py:6190-6200`), which fixes the meaning: `balance` is **funds
the org holds with its parent**.

| Entry | Direction on sale | Balance | Amount | Site |
|---|---|---|---|---|
| `SALE` | CREDIT | **+** | `ticket_total_amount_net` | `utils.py:1714-1725` |
| `FEE` | DEBIT | **−** | recomputed from the snapshotted formula | `ledger_service.py:85` |
| `COMMISSION` | CREDIT | **+** | recomputed from the snapshotted formula | `ledger_service.py:113` |
| `CC_PAYMENT` | DEBIT | **−** | same net | only when the org used its own card |

All land on one account — the `LedgerAccount` of the `OrgRelationship` whose
`sub_agency` is that row's seller org (`ledger_service.py:42`,
`utils.py:1758-1760`). On a reversal the directions flip and the amount is
**recomputed**, never negated.

**Read as "the parent settles with the sub-agency", every direction fits:** the
sale credits the org with what its buyer owes it, including its own fee; the fee
debit is what its own supplier charges it; commission credits what it earned; a
card payment cancels the sale credit when the org paid the airline directly.

## Requirement

- `applies_to = SUB_AGENCY` — a commercial amount between two organisations. It
  MUST post its own ledger entry, debiting the buyer, mirroring what the
  configuration engine does for its own amounts.
- `applies_to = CUSTOMER` — part of the traveller's price. It stays **in the
  net** and posts no separate entry. Correct today; unchanged.

## Why this is new build, not a migration

| Engine | Calculates | Posts a ledger entry |
|---|---|---|
| **#1** legacy ruleset (`OrgMasterRuleSet`) | **inert** — `available_master_rule()` resolves against a table the spec-004 FK repoint emptied; *"that m2m has been empty for every order written since"* (`content_rules.py:4877-4880`). Still called at six sites (**F25**). | never did |
| **#2** fee/commission config | yes | **yes — the only one** |
| **BRE** | yes | **no** |

The BRE replaced **#1's calculation**. Nothing replaced **#2's posting**. A
BRE-calculated sub-agency fee reaching the ledger therefore has no predecessor to
be faithful to, and cannot be covered by NF-004's mirror gate.

## What this epic must decide

1. **Double-charging during cutover.** An org relationship carrying *both* a
   configuration fee and a BRE `SUB_AGENCY` rule would be debited twice. Which
   wins, and when the configuration is switched off.
2. **A `DISCOUNT` entry type.** A sub-agency discount is not a commission;
   reusing `COMMISSION` corrupts anything grouping by entry type. `EntryType`
   already carries nine variants, so adding one is cheap.
3. **Direction per kind.** Fee debits the buyer, commission credits it. A
   sub-agency discount's direction is stated nowhere.
4. **Existing rows** — back-post, leave, or reconcile.
5. **Idempotency at the new grain.** `_write_fee_entry` guards on
   `(content_type, object_id, entry_type)`, which permits exactly one FEE entry
   per charge. Per-sub-type BRE amounts need either a wider key or a summed
   entry, and that choice is not reversible afterwards.

## Blocked by

**Confirmation of the settlement model.** Every direction above is *inferred*
from balance arithmetic; nothing states it. Two specific questions:

- Is `balance` funds the org holds with its parent, such that a sale credits the
  org with what its buyer owes it? The arithmetic says yes; no document does.
- The **root** agency has no `OrgRelationship` where it is the `sub_agency`, so
  it has **no ledger account** and its row posts nothing. Its sub-agency fee is
  therefore credited nowhere. Is the root outside this ledger by design?

Both are one sentence from whoever owns the accounting model, and nothing here
should be designed before they are answered.

## Relationship to other work

- **NF-004 / spec 011** does not wait on this. Its `charged` predicate is defined
  by **ledger entry type**, not by engine (**FR-005a**), so entries this epic
  introduces are reversed with no rework.
- **D5** is reframed by this: the BRE takes over engine #2 entirely — charge
  posting as well as reversal. NF-004 covers the reversal half only.
- Composes with the audit-durability cluster: a new posting path inherits the
  same write-once-ledger constraints.
