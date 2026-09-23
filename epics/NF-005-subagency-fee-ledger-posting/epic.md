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

## The sign convention — verified 2026-09-23

`ledger_entry_and_txn_creation` (`utils.py:1221`) branches on entry type. Read
directly, all three branches:

| Entry | Direction | Balance | Amount basis | Site |
|---|---|---|---|---|
| `SALE` | **DEBIT** | **−** | `ticket_total_amount_net` | `utils.py:1235-1256` |
| `VOID` | CREDIT | **+** | `ticket_total_amount_net` | `:1292-1314` |
| `REFUND` | CREDIT | **+** | **`ticket_refund_amount`** — a *different field*, set from `txn_ticket_refund_amount` at `utils.py:836`; non-zero on 920 of 4,846 rows | `:1355-1372` |
| `FEE` sale / reversal | DEBIT / CREDIT | − / + | recomputed from the snapshotted formula | `ledger_service.py:85`, `:174-178` |
| `COMMISSION` sale / reversal | CREDIT / DEBIT | + / − | recomputed | `ledger_service.py:113` |
| `TOP_UP` | CREDIT | **+** | paid-in amount | `mutations.py:6190-6200` |

**`balance` is the org's available funds with its parent.** A purchase consumes
them; a top-up, a void and a refund restore them; a fee consumes; a commission
adds. Conventional throughout.

**Correction.** An earlier version of this epic stated `SALE` as a CREDIT that
increases the balance, and built a "the parent collects from the traveller and
credits the agency" reading on top of it. That was wrong — it came from reading
the `VOID` branch by mistake. Both the table and that reading are retracted.

**Void and refund are not symmetrical, and that is deliberate.** A void returns
the exact amount debited. A refund returns the **provider's** refund figure,
which is not what was debited — an airline penalty stays with the airline. So the
agency's own fee and discount portion of the original debit is **not** returned
by the `REFUND` entry; only the `FEE`/`COMMISSION` reversals return it. That is
precisely why the reversal NF-004 migrates matters for balance correctness, and
it is a stronger argument for it than the epic currently makes.

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

**What `ticket_total_amount_net` is supposed to mean.** With the directions now
verified, a concrete symptom appears that must be explained before anything here
is designed.

An org's `net` is built from **its own** adjustment rows. For a mid-chain agency
those include the `SUB_AGENCY` fee **it charges its buyer**, and for a leaf agency
they include the `CUSTOMER` fee **it charges the traveller**. The `SALE` entry
then **debits** the org by that amount. So as the code stands, **an agency's
balance is reduced by fees it charges other people.**

Either `net` means something other than the plain reading, or this is a systemic
error in what the ledger has been moving. That is the same inversion already
visible in the naming — `fo_price_adjs_seller` is the org's *own* rules yet lands
in `*_net`, while `fo_price_adjs_supplier` is the *parent's* rules yet lands in
`*_sell` (`utils.py:813-821`) — but it now has a symptom attached rather than
being a stylistic doubt.

Two questions, both one sentence to answer:

1. Should an org's `SALE` debit be what it owes **its supplier** (`B+T` plus the
   parent's fee on it), rather than what it charges **its buyer**?
2. The **root** agency has no `OrgRelationship` where it is the `sub_agency`, so
   it has **no ledger account** and its row posts nothing. Is the root outside
   this ledger by design?

**The gap framing above depends on answer 1** and should be re-derived once it
lands.

## Relationship to other work

- **NF-004 / spec 011** does not wait on this. Its `charged` predicate is defined
  by **ledger entry type**, not by engine (**FR-005a**), so entries this epic
  introduces are reversed with no rework.
- **D5** is reframed by this: the BRE takes over engine #2 entirely — charge
  posting as well as reversal. NF-004 covers the reversal half only.
- Composes with the audit-durability cluster: a new posting path inherits the
  same write-once-ledger constraints.
