---
epic: NF-005
parent: NF-003
title: Sub-agency fee/discount posting to the credit ledger
shape: solo
status: stub — scoped 2026-09-23, not designed
created: 2026-09-23
money-impact: yes
rollout: forward-only
blocked-by: [net-vs-sell-semantics]
not-affected: [nf-ndc-adapter-rs, nf-app-workbench, nf-app-home-v2]
---

# Sub-agency fee/discount posting to the credit ledger

**Stub.** Scoped out of NF-004 on 2026-09-23 because it is **new build on the
sale path**, not parity on the cancellation path. Recorded now so the ask is not
lost and so NF-004 can proceed without it.

## Requirement

A fee or discount whose `applies_to` is **SUB_AGENCY** is a commercial amount
between two organisations — the parent charging the child. It must post as its
own **ledger entry** on the sub-agency's credit account.

A fee or discount whose `applies_to` is **CUSTOMER** is part of the price the
traveller pays. It stays **in the net** and posts no separate entry. That is
correct today and does not change.

Sandeep, 2026-09-23.

## Why this is new build, not a migration

Three engines, and only one of them has ever posted a fee to the ledger:

| Engine | Calculates | Posts a ledger entry | Reverses |
|---|---|---|---|
| **#1** legacy ruleset (`OrgMasterRuleSet`) | **inert** — `available_master_rule()` resolves against `OrgMasterRuleSet`, which *"stopped matching when 004-repoint-ruleset-fk pointed them at `bre_rule_set`, so that m2m has been empty for every order written since"* (`content_rules.py:4877-4880`). Still called at six sites; returns nothing. | never did | n/a |
| **#2** fee/commission config (`OrgRelationshipConfig`) | yes | **yes — the only one.** `EntryType.FEE` and `EntryType.COMMISSION` are created at `ledger_service.py:85` and `:113` and **nowhere else** in the codebase. | yes |
| **BRE** | yes | **no** — output lands in adjustment rows and the projected columns | no |

The BRE replaced **#1's calculation**. Nothing has replaced **#2's posting**. So a
BRE-calculated sub-agency fee reaching the ledger has no predecessor to be
faithful to — it is a feature being built, and it cannot be covered by NF-004's
mirror gate.

## The double-count this must resolve

A SUB_AGENCY adjustment row belongs to the org that **owns the rule** — the
parent. That is why the supplier-side lookup finds it by parent sequence number
rather than by seller org (`utils.py:709-713`).

| | Where a parent's SUB_AGENCY fee lands today |
|---|---|
| The **child's** row | `*_sell` only — **not** in the child's ledger movement |
| The **parent's** row | its own `fo_price_adjs_seller` → `ticket_total_amount_net` → **in the parent's ledger movement** (`utils.py:1256`, `:1285`) |

So posting it as an entry is **additive on the child's account** but **double-counts
on the parent's**. The amount must first be excluded from the rule-owning org's
`ticket_total_amount_net` — in **both** the creation path (`utils.py:702-704`,
`:821`) and the sync path, which recomputes it on every retrieve from
`doc_adjustments` filtered on `(order, seller_organization_id,
provider_document_id)` with **no `applies_to` filter** (`utils.py:530-542`, `:608`).

## What this epic must decide

1. **Excluding SUB_AGENCY amounts from the owner's net** — both write paths, and
   what happens to rows already written.
2. **A `DISCOUNT` entry type.** A sub-agency discount is not a commission;
   reusing `COMMISSION` would corrupt anything grouping by entry type.
   `EntryType` already carries nine variants, so adding one is cheap.
3. **Whether #2's config fee is switched off** as the BRE takes the role, and how
   an org holding both is handled during cutover.
4. **Direction and sign** per kind — a fee debits the child, a commission credits
   it. A discount's direction is unstated anywhere.
5. **Existing rows.** Whether historical sub-agency amounts are back-posted, left
   alone, or reconciled.

## Blocked by

**`net` vs `sell` semantics are inverted from their ordinary meaning and must be
confirmed before any of this is designed.** For a given org's row,
`fo_price_adjs_seller` is that org's **own** rules and `fo_price_adjs_supplier` is
the **parent's** SUB_AGENCY rules — yet the assignment is
`ticket_*_sell = *_supplier` and `ticket_*_net = *_seller` (`utils.py:813-821`).
By the ordinary reading, *sell* is what the org charges and *net* is what it pays
its supplier, which is the opposite. The ledger posts `net`
(`utils.py:1256`, `:1285`), so which of the two readings is correct decides
**what the ledger has been moving all along**. Nothing should be built on top of
this until it is settled.

## Relationship to other work

- **NF-004 / spec 011** does not wait on this. Its `charged` predicate is defined
  as *"a `LedgerEntry` of that entry type against this charge"* — deliberately
  posting-model-agnostic, so new entry types are picked up with no rework.
- **D5** is reframed by this: the BRE takes over engine #2 **entirely**, charge
  posting as well as reversal. NF-004 covers the reversal half only.
- Composes with the audit-durability cluster, since a new posting path inherits
  the same write-once-ledger constraints.
