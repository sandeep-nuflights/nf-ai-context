---
epic: NF-004
parent: NF-003
title: Cancellation fee/commission reversal on the BRE
shape: mirror
status: approved 2026-09-22 — A6 option (a), F19 accepted
created: 2026-09-22
parity:
  group: cancellation-reversal
  members: [nf-ndc-adapter-generic, nf-ndc-connect-rules-engine]
  fixtures: ./fixtures
  surfaces:
    nf-ndc-adapter-generic: [OrderChange/acceptCancelledOffer, OrderCancel]
not-affected: [nf-app-workbench, nf-app-home-v2, nf-ndc-adapter-rs]
money-impact: yes
rollout: forward-only
blocked-by: [production-check, D4-detail]   # P9 confirmed 2026-09-23 -> NF-003 I1
leaf-specs:
  nf-ndc-adapter-generic:
    - 010-cancellation-rule-application-record  # drafted 2026-09-22; additive only
    - 011-cancellation-reversal-on-bre          # blocked on D4, P9, production-check;
                                               # carries F11 and the D10 guard moves
branch-note: |
  Leaf work rides `rules-engine-migration` in nf-ndc-adapter-generic rather than
  `epic/NF-004-cancellation-fee-reversal` (Sandeep, 2026-09-22). NF-004 builds
  directly on the unmerged BRE work there; a separate epic branch would fork it.
  A deliberate departure from the hub's one-branch-name convention.
---

# Cancellation fee/commission reversal on the BRE

## Requirement

Bring the **cancellation path** onto the BRE, matching current behaviour.

Two halves, and they are not symmetrical:

- **No fee/discount is newly charged on a cancellation.** Not on VOID, not on
  REFUND.
- **The reversal of the already-charged fee and commission is reproduced**, and
  under **D5** it moves onto the BRE rather than staying on the legacy formula
  engine.

### What "skip" means — confirmed 2026-09-22

> **Skip** means *no new charge from the agency to the customer is priced on a
> cancel*. It does **not** mean *no BRE call happens*. The reversal is itself a
> BRE evaluation — of the **original rule**, re-run under
> `transaction_type = VOID|REFUND` and pinned to the charge-time ruleset version.

**A cancellation charge may be introduced later**, which makes **D8** a design
constraint rather than a scoping note.

### Why re-evaluation and not direct reversal

Considered and rejected: reverse the stored amount instead of re-running the
rules. It fails because the reversal context legitimately differs from the sale
context in more than a scalar ratio — `BaseFare`/`YQ`/`YR` are chain-aggregated
on refund-after-exchange (`_aggregate_ticket_chain`, `fee_engine.py:188-189`),
`PerSegment` becomes unflown, `PerTicket` becomes `unflown/segment_count`. The
formula grammar is pure arithmetic (`_math_eval` accepts only `ast.Num` and
`ast.BinOp`; `+ - * / %` between values, `fee_engine.py:21-27`, `:38-63`) — narrow,
but `/` and `%` still admit non-linear forms, so scaling a stored amount is not a
general equivalent.

Where they agree and differ, for the record:

| Case | Direct reversal vs re-evaluation |
|---|---|
| Full void/refund, nothing flown, no reissue | identical |
| Partial refund (some coupons flown) | diverges — re-evaluation prorates |
| Refund after exchange/reissue | diverges — re-evaluation aggregates the chain |
| Fully flown, refunded | diverges — re-evaluation posts nothing (`amount <= 0`) |

## What happens today — verified 2026-09-22

Six parallel working-tree research passes plus direct re-reads of every contested
site, then a read-only query pass against the local development database. Per the
rot rule, every anchor here is a dated snapshot — re-verify before acting.

### The flow is entirely Python-priced

| Step | `nf-ndc-adapter-rs` | `nf-ndc-adapter-generic` |
|---|---|---|
| `iataOrderRetrieve` | `schema.rs:548`; proxy branch `:658-724`, gated `NF_RULES_ORDERVIEW_PROXY` (**default off**) | prices, records |
| `iataOrderReshop` | `schema.rs:492`, always proxy. `apply_orderreshop` is a **verified stub** — `NotApplicable(SectionPlaceholder("context"))` at `mod.rs:1289`; `schema.rs:539-542` `debug_assert!`s it never alters the response | resolves `Usecase.CANCEL_QUOTE`; sets `refund_indicator` from provider `differential_type_code` (`content_state.py:2972-2998`) |
| `iataOrderChange` + `acceptCancelledOffer` | `schema.rs:967`, always proxy, shares `NF_RULES_ORDERVIEW_PROXY` (**default off**) | **evaluates BRE, writes ledger, posts the reversal** |

`iata_order_cancel` is `todo!()` in Rust (`schema.rs:959-964`). `refund_indicator`
is a pass-through scalar there — copied 1:1 in the Python→Rust map, never read.

**There is no separate refund request.** VOID and REFUND are the same mutation
with the same variable shape; the frontend takes `offer[0]` blindly
(`ndcOrderCancel.ts:538-543`, `:593-598`) and `isVoidCancellation` /
`isRefundCancellation` (`Cancellation.tsx:1148-1149`) are **display-only**. The
distinction is derived server-side from coupon status. Only `isRetain` diverges
into a different mutation.

### Cancel re-evaluates fee/discount today, as a SALE

`_operation_records_fee_discount(RQ)` (`content_state.py:146-158`) gates on
**request type, never usecase**. The workbench cancel enters as `ndcOrderChange`
→ `make_request(rq, OrderChangeRQ, OrderViewRS)` (`mutations.py:37`), so
`RQ == OrderChangeRQ` and the branch is taken. The file contains exactly **one**
`RQ` reassignment (`:2371`), which only *adds* `CANCEL_ORDER_RETAIN` into the same
bucket — nothing ever reassigns `RQ` away.

With `transaction_type` hardcoded `"SALE"` (`content_rules.py:6993`), **every
cancellation is priced as a sale today**. This closes **P7** and is the live form
of **F3**.

### The reversal is not where the record implies

**No BRE ledger row is ever reversed.** `FullfilmentOrdersPriceAdjustments`
(`models.py:1319`) and `TicketOrgTransactions` (`models.py:1111`) are written once
and never negated, deleted or flagged on cancel. `RuleStatus` has no
REVERSED/VOIDED variant. Refund reporting reads the **original positive rows**
(`utils.py:2438`).

The reversal lives in a different ledger, driven by a different engine:

| | Mechanism |
|---|---|
| Trigger | `txn_type` from `ticket_transaction.txn_coupon_status` (`ledger_service.py:49-54`) |
| Form | **New** `LedgerEntry`+`LedgerTransaction` pair with the direction **flipped**: fee DEBIT→CREDIT, commission CREDIT→DEBIT (`:92-96`, `:120-124`) |
| Amount | **Not negated.** Same positive value on the opposite side of `ledger_account.balance` (`_write_fee_entry`, `:136-192`) |
| Derivation | **Recomputed** — `evaluate_formula(formula, build_token_context(ticket, txn_type), currency)` (`:161`) |
| Guard | `if amount <= 0: return` (`:162-163`) — a zero result posts **nothing, silently** |
| Idempotency | One entry per `(content_type, object_id, entry_type)` (`:150-159`) — never rewritten, therefore never correctable |

**The engine underneath is not the one NF-003 replaces.** Commission is outside
the rules engine (`content_rules.py:6121`). The reversal runs on
`OrgRelationshipConfig.fee_config` (`models.py:662-685`) — a **OneToOne** carrying
exactly one `service_fee_formula` and one `commission_formula`, with **no rule
types and no sub-types**. `ledger_service.py` reads only `applied_service_fee_formula`
(`:62`) and `applied_commission_formula` (`:63`) and **never touches the six
sub-type columns**.

> **Consequence worth stating plainly: the sub-type multiplicity is created by
> D5, not inherited.** Legacy never faced it.

### The reversal is nested inside the BRE evaluation branch — F11

```
content_state.py:3079   if _operation_records_fee_discount(RQ):
             :3094       if not recording_outcome.has_failures:
             :3155         publish_ticket_transactions(...)
                             → create_ticket_org_tnx (utils.py:623)
                             → publish_data           (utils.py:1921)
                             → process_fee_commission_ledger (ledger_service.py:21)
```

A BRE failure on a cancel **silently suppresses the reversal**, and removing this
path from the recording set would delete the reversal with it. The row this epic
hangs its design off is created inside the branch this epic restructures — the two
changes must be designed together, not sequenced.

### The reshop step is read-only, but the confirm depends on it

`ndcCancelReshopQuery` resolves to `Usecase.CANCEL_QUOTE` and is **read-only
against the database** — structurally, not merely by predicate: the reshop branch
`return`s at `content_state.py:3006-3008`, *before* the `if RS == OrderViewRS`
block at `:3011-3012` that contains `save_order`, `apply_fee_discount_for_order`
and `publish_ticket_transactions`.

It does write **Redis**, and the confirm hard-depends on it: key
`{trx_id}:{airline_designator}:OrderReshopRS`, TTL `CACHE_EXPIRE` (default
**1800s**). `cancel_paid_request` (`layer_inputs.py:1213+`) reads it with the
confirm's **own** `trx_id`, sums the price differential and sets
`payment_functions[0].payment_processing_details.amount` on the outgoing request.
A miss, expiry or `trxId` mismatch produces an explicit
`NFE-NDC-CACHE-ACCESS-ERROR` (`layer_inputs.py:1250-1261`) — **it fails loudly
rather than sending a zero.**

The quoted differential is therefore **never persisted** — it exists only in that
30-minute cache. 31 minutes after a cancellation you cannot reconstruct what was
quoted.

### How the reversal row is actually built

There is **no reversal-specific construction**. The same `create_ticket_org_tnx()`
(`utils.py:623-836`, a pure `.create()` at `:796`) builds it. What makes it a
reversal row is only its parent `TicketTransactions.txn_coupon_status`.

Order on the cancel `OrderChangeRQ`:

| # | Site | What happens |
|---|---|---|
| 1 | `content_state.py:2486` | `update_order_status_cancelled()` — order CANCELLED, `sub_status` VOID/REFUND; `update_tickets()` touches **`Ticket`** only |
| 2 | `content_state.py:2797`/`:2819` | `save_order()` → `update_order()` → `create_ticket_tnx()` creates a **new** Void/Refunded `TicketTransactions` row (`utils.py:872`) |
| 3 | `content_state.py:3080` | `apply_fee_discount_for_order()` — **re-evaluates and rewrites adjustment rows**; calls `sync_ticket_org_transactions_from_ledger` (`content_rules.py:4643`) |
| 4 | `content_state.py:3155` | `publish_ticket_transactions` → `publish_data` → `.get()` misses → `create_ticket_org_tnx()` creates the reversal row |

The money columns come from `get_ticket_price_adj(seller_ticket_price_adjs)` where
`seller_ticket_price_adjs = fo_price_adjs_seller.filter(provider_document_id=...)`
(`utils.py:699-701`) — **filtered by document only, no coupon-status or lifecycle
filter.** So the reversal row is stamped with the *current* adjustment rows, which
step 3 has just re-evaluated as a SALE.

`txn_ticket_refund_charge` is **never set** (`utils.py:823`, commented out).
`applied_*_formula` is copied from the sale row (`utils.py:1770-1794`) — the one
genuinely reversal-aware path.

`sync` skips the reversal row on the cancel request (the row does not exist yet →
`DoesNotExist` → `skipped "no_org_record"`, `utils.py:565-574`, a branch that
explicitly "Never creates") but **catches it on any later retrieve**, when
`.order_by("-created_at").first()` selects it.

### What the database says — local dev, read-only, 2026-09-22

| Observation | Result |
|---|---|
| Sale vs reversal row (PNR `7CMB5W`, a VOID) | six sub-type columns and all net/sell amounts **byte-identical**; `txn_ticket_refund_charge`, `txn_ticket_commission_amount`, `ticket_refund_amount` all zero on both; `applied_*_formula` NULL on both |
| Adjustment rows for that document | 6, all timestamped at ticketing, **none at the Void timestamp** — the cancel re-evaluated and the multiset matched, so nothing was rewritten |
| Rulesets per document | **one distinct ruleset and one evaluation log per `(kind, sub_type, level)`** — 18 rows/18 rulesets across 3 chain levels, 12/12 across 2, 6/6, 4/4, 2/2. Never shared. |
| Ticketed→Refunded pairs | **230**, of which **0** carry any fee or discount |
| Ticketed→Void pairs | 117, of which **3** carry any fee or discount |
| Why the refunds are zero | 185 of their adjustment rows have `rule IS NULL` — **no ruleset was ever resolved**; they predate the BRE work. Not the silent-zero defect. |
| `content_orgrelationshipconfig` rows | **0** |
| `TicketOrgTransactions` rows / with a formula snapshot | 4,837 / **0** |
| `LedgerEntry` with `entry_type` FEE or COMMISSION | **0** |

**The reversal row is a verbatim duplicate of the sale row's fee/discount
figures** — confirming the code reading, and meaning nothing on it describes the
reversal.

## Scope decisions

D1–D4 are NF-003's. D5–D9 were taken while scoping this sub-epic.

| # | Decision | Consequence |
|---|---|---|
| **D5** | **The reversal migrates to the BRE.** `fee_engine.py` + `fee_config` are not left standing as a second permanent fee engine. | Commission enters BRE scope for the first time — supported, since the registry already carries `Commission: [Standard, Extra]`. Creates the sub-type multiplicity legacy never had. |
| **D6** | **`[Per Segment]` on VOID takes the full segment count**, per NF-002's table. Confirmed 2026-09-22; `fee_engine.py:211-212` is a defect (**F15**). Corroborated by `context.rs:785-803`. | The VOID parity fixture is generated from corrected behaviour, never from legacy output. |
| **D7** | **Sale-time ledger rows stay untouched on cancel.** A durable BRE-side trace of the reversal is deferred. | Refund reporting keeps reading the original positive rows. |
| **D8** | **The skip is an authoring outcome, not a code exclusion.** "No charge on VOID/REFUND" holds because no rule is authored for those transaction types. | Opposes how `FEE_DISCOUNT_RECORDING_OPERATIONS` encodes policy today, where FR-011 states that a request type's *absence from a Python set* is the enforcement. Makes D4's `transaction_type` column load-bearing. |
| **D9** | *(proposed, narrowed)* **What was charged is immutable, and everything that reverses it derives from the same frozen snapshot** — formula, ruleset version and the enable flag. **The token context is excluded**: A6 was taken as option (a), so tokens are rebuilt live and F19 is accepted. | The pattern behind **F16, F19, F20** and the `_net`/`_sell` split: something frozen beside something live on one money path, with nothing reconciling them. Stating it once gives the leaf specs a rule to be checked against. |
| **D10** | **The reversal dispatches on evidence, per kind, and never blocks the cancellation.** Which path reverses a charge — BRE, legacy fallback, or an unreconcilable record — is decided from three predicates read off data that already exists, not from a cutover date or a version flag. | Makes the legacy-charged cohort a first-class case rather than an exception. Splits DoD 5 into cutover and retirement. Requires the two guards at `ledger_service.py:33-34` and `:39-40` to move, or the new path inherits exactly the condition that yields zero reversals today. |

## The design — A2 and A6 resolved

### Why not the transitive route

Dereferencing `FullfilmentOrdersPriceAdjustments.bre_evaluation_log_id` was
investigated and **does not hold**. Reaching the rows is not the problem (`fo` is
a `FullfilmentOrdersII`, the FK matches, and `create_ticket_org_tnx` already
queries it that way at `utils.py:1810-1812`). Four things break it:

1. **Commission has no adjustment row.** `RuleType` is `DISCOUNT`/`FEE` only
   (`choices.py:693-694`); `_bre_rule_type_and_sub_type` returns `(None, None)`
   for Commission and the caller skips (`content_rules.py:6116-6132`). The pin
   covers at most half a reversal — and D5 is what would fix it. Circular.
2. **The pointer is guaranteed stale on any ticketed order.**
   `bre_evaluation_log_id` is excluded from `_PRICE_ADJUSTMENT_COMPARISON_FIELDS`
   (`content_rules.py:5200-5216`), and the write is delete+recreate of *every* row
   at a chain level. `provider_document_id` **is** compared and necessarily goes
   from absent (`OrderViewBooked`, per Order Item) to the ticket number
   (`OrderViewTicketed`, per Fare Document). The module docstring states the
   intent (`content_rules.py:60-87`): evaluation happens on every create, change
   **and** retrieve, with **no** freeze-at-ticketing boundary — a proposal to add
   one (006 Q2/FR-014) was reverted.
3. **There is no single row to dereference** — N adjustment rows fold into 1
   projection row (`get_ticket_price_adj`, `utils.py:4063`), and the data confirms
   a *different ruleset per sub-type*. Some rows also carry a null
   `bre_evaluation_log_id` entirely.
4. **Retention.** Collectable rows are `WHERE coalesce(reference,'')=''`, deleted
   (not archived) after `EVALUATION_LOG_RETENTION_AGE_HOURS` (default 24). E15
   means no adapter sends `reference`; safe today only because
   `EVALUATION_LOG_RETENTION_ENABLED` defaults false.
   **`reference` is committed but not implemented** — treat as scheduled to close.
   Objections 1 and 3 are structural and unaffected either way.

### What legacy does, and why it is the template

The formula snapshot is **write-once**: the guard at `utils.py:1764-1766` requires
both formula fields to be `None`, and once either is set — even to `""` — it never
re-enters. No later retrieve can disturb it. That immutability is exactly the
property a pin needs and the property `bre_evaluation_log_id` lacks.

### The pin is necessary but not sufficient — F19, and A6

Pinning freezes **which rule applies**, not **what it is applied to**. The fee
ledger is write-once (`utils.py:1988`, `ledger_service.py:150-159`) while the
reversal's token context is rebuilt live from the ticket record
(`fee_engine.py:183-193`) — and `update_tickets()` refreshes
`ticket_base_fare_amount` and `ticket_tax_details` on a post-ticketing retrieve
(`db_api.py:1315`, writes at `:2255-2261`, `:2340-2346`, reached from
`update_order()`'s TICKETED branch at `:1067`).

**A6 is resolved as option (a): pin the ruleset only. No charge-time context is
snapshotted, and F19 is knowingly carried forward** (Sandeep, 2026-09-22).

The snapshot was designed and then dropped. Recorded because the reasoning is not
recoverable from the outcome:

- The raw provider JSON *is* retained — `Ticket.ticket_doc_source` is a non-null
  `JSONField` (`models.py:1017`) — and the context builder
  (`content_rules.py:6981-7003`) is a pure function of it, so a context can be
  rebuilt on demand without storing one.
- **But the rebuilt context is the current one, not the charge-time one.**
  `ticket_doc_source` is itself rewritten inside `update_tickets()` (assignment
  at `db_api.py:1443`, function at `:1315`) — the same function that rewrites
  `ticket_base_fare_amount` and `ticket_tax_details` at `:2255-2261`. The stored
  JSON mirrors the provider's latest word; it is not a record of what was charged
  against. **Rebuilding therefore reproduces F19, it does not avoid it.**
- The decision stands anyway: carrying a pre-existing defect forward unchanged is
  consistent with a transitional mirror, whose gate is parity rather than
  correctness — and per the risk section this path has never been observed to run
  at all.

**Consequence: the decision rests on NF-003's I1.** Option (b) existed precisely
to make the "once ticketed, the price won't change" invariant irrelevant. Without
the snapshot that invariant must actually hold — and it was confirmed on
2026-09-23 (Sandeep) and recorded as **I1**. A6 option (a) is therefore sound,
and F19 drops from live to **latent, guarded by I1**.

**But the guard is a business fact, not a code constraint.** `update_tickets()`
still rewrites the base fare on a post-ticketing retrieve; nothing prevents
divergence, and if I1 ever stops holding the reversal diverges silently, with no
error and no test. NF-004 therefore carries the cheap detector: snapshot the
ticketing-time base fare (one number, not a context blob), compare at reversal,
log on mismatch. It changes no behaviour and converts an unguarded assumption
into a monitored one.

**F19 is accepted, not closed.** It stays live in `open-defects.md` with NF-004
recorded as the epic that chose to carry it. Closing it is a separate piece of
work and should be scoped with the audit-durability cluster.

### The record

**One structure**, written once, at the moment the formula snapshot is taken
today. `TicketOrgTransactions` gains no new column — A6 option (a).

A second structure — the reconciliation record for a charge that cannot be
reversed — is written only on the anomaly path; see **D10**.

**`TicketOrgRuleApplication` → `content_ticketorgruleapplication`.** One row per
rule application:

| Column | Note |
|---|---|
| `ticket_org_transaction` | FK, CASCADE |
| `adjustment_kind`, `adjustment_sub_kind` | same enums as `FullfilmentOrdersPriceAdjustments` |
| `composite_version` | TEXT NOT NULL — the operational pin |
| `rule_set_id`, `rule_set_version`, `template_version` | decomposed; `rule_set_id` indexed |
| `amount` | **`DecimalField`, not `FloatField`**, at least 3 decimal places |
| `currency` | |
| `bre_evaluation_log_id` | nullable — audit pointer only, never depended on |
| `created_at` | |
| **UNIQUE** `(ticket_org_transaction, adjustment_kind, adjustment_sub_kind)` | **in a migration, and verified present in the database** |

Grain: **ticket lifecycle event × seller org × kind × sub-type**. The FK already
scopes the chain level, because one seller org is one level. Six rows per charge
in the common case, eight once commission joins under D5. The sale row set
explains the charge; the reversal row set explains the reversal.

`composite_version` is `tpl:v{templateVersion}+rs:{ruleSetId}:{ruleSetVersion}`
(`composite.rs:6-13`), and the BRE's own comment anticipates this use: the string
"can arrive from an external caller (VOID/REFUND request), not just one this
service generated itself" (`composite.rs:15-17`).

`amount` is not optional — it is the only immutable per-sub-type record of what
was charged (the adjustment rows are delete+recreate, the projection columns are
live), and it makes the reversal self-checking: re-evaluating the pinned ruleset
under SALE tokens should reproduce it.

**Rationale for a table rather than columns** is in
[`decisions/ADR-001-rule-application-table.md`](decisions/ADR-001-rule-application-table.md).
In short: a pin is a record of about six fields, not a scalar, so columns would
mean ~40 new fields on a record that already has ~40 and would widen again with
every new sub-type; and "which charges used this ruleset version?" is a one-query
question on a table and an awkward multi-column search otherwise. The data settles
the grain: one ruleset per sub-type, up to 18 per document across three levels.

### Copy, don't derive

The reversal-side pin must be **copied from the sale row**, never derived from the
adjustment rows present at reversal time. By step 4 those have already been
re-evaluated on the same request, so deriving from them captures the cancel-time
evaluation rather than the charge. This is the trap legacy already falls into for
its money columns. The reversal row's basis records **the pin it used** (copied)
and **the tokens it evaluated on** (fresh — those legitimately differ; that is the
proration).

## Reversal dispatch — D10

Not every charge that reaches a cancellation was made by the BRE. Because the
config engine is being *replaced*, tickets charged under
`OrgRelationshipConfig.fee_config` will still be cancelled after cutover, and
they carry no row in `content_ticketorgruleapplication`. The base rule — *no pin
rows means nothing to reverse* — is right but under-determined: **no rows** covers
both "nothing was ever charged" and "charged by the engine we just replaced".

Backfill is not possible and not required: the BRE work is unmerged and has never
run outside local working trees, so there is no cohort of BRE-charged tickets
missing a pin. The cohort that exists is **legacy-charged**.

### The discriminator already exists

`applied_service_fee_formula` / `applied_commission_formula`
(`models.py:1159-1160`) are written by the config engine at the moment it charges,
write-once (`utils.py:1764-1766`). A non-null formula is therefore a **positive,
self-evidencing marker** that the legacy engine charged this row.

Preferred over the two alternatives on principle, not convenience:

| Rejected | Why |
|---|---|
| A **cutover date** | Infers provenance from a clock. Wrong the moment there are two deploys, a rollback, or regions cut over at different times. |
| A **version flag** on the row | New state that must be kept correct, can be wrong, and duplicates what the data already says. |

The formula marker cannot drift, because the engine that writes it is the engine
being discriminated for.

### The three predicates

Evaluated **per kind ∈ {FEE, COMMISSION}** — the two have separate formula
markers, separate enable flags and separate ledger entries, and may dispatch
differently on the same row.

| | Definition | Trap |
|---|---|---|
| **`charged`** | A `LedgerEntry` of that `entry_type` exists for `(content_type=TicketOrgTransactions, object_id=row.id)` — the key `_write_fee_entry` already guards on (`ledger_service.py:150-159`). | **Never the amount columns** — see below. |
| **`pin`** | ≥1 row in `content_ticketorgruleapplication` for this `ticket_org_tnx` and that kind. | Grain is `(kind, sub_type)`, so "has a pin" is ≥1 row, not exactly one. |
| **`legacy`** | `applied_*_formula IS NOT NULL`. | **`IS NOT NULL`, not truthiness.** `""` is a real stored value — `ledger_service.py:62-63` does `or ""`, and the write-once guard requires *both* to be `None` to re-enter. `if formula:` misclassifies those rows as anomalies. |

**`charged` must be read from the ledger, not from the amount columns.** The
columns are rewritten live on every retrieve (**F16**, `utils.py:592-603`) while
the ledger is write-once (`utils.py:1988`, `ledger_service.py:150-159`), so a row
can carry a non-zero fee and never have had an entry posted. That is the current
dataset, not an edge case: **4,837 `TicketOrgTransactions` rows, zero FEE or
COMMISSION `LedgerEntry` rows.** Reading the columns would fire the anomaly check
on effectively every row on day one.

### The table

| `charged` | `pin` | `legacy` | Action |
|---|---|---|---|
| no | — | — | **no-op.** Nothing moved; nothing to reverse. |
| yes | yes | — | **BRE reversal.** Re-evaluate against the pinned `composite_version` and the frozen basis. |
| yes | no | **yes** | **Legacy fallback.** `fee_engine.py` with the frozen formula. Built only if the production check shows this cohort is non-empty. |
| yes | no | no | **Anomaly.** Money moved and neither engine left a trace. Durable reconciliation record + alert; the cancellation still completes. |
| no | yes | — | **Anomaly, low severity.** Pinned but never posted — the **F20** shape. Reconcile, do not block. |

`legacy` is consulted only when `pin` is absent, so it costs nothing on the
normal path.

### What "anomaly" means — and what it must not mean

A cancellation is the customer's right; the ledger is our bookkeeping. Two
rejected options and the one taken:

| Option | Verdict |
|---|---|
| Hard-fail the cancellation | **No.** Puts a provenance problem about a months-old fee in front of a customer exercising a right. |
| Complete, skip the reversal, log | **No.** That is **F20** — the silent skip that strands a residue on `LedgerAccount.balance` with nothing anywhere saying so. The defect this epic complains about. |
| Complete, write a **durable reconciliation record**, alert | **Taken.** What could not be reversed, why, the amount at stake, the ticket and org. Not blocking, not silent. |

That record is the same structure **D7** defers ("a durable BRE-side trace of the
reversal") and composes with NF-003's audit-durability cluster
(E3+E14+E15+E16) — one build, three purposes, rather than a bespoke error table.

**Run the predicate proactively, not only at reversal.** At reversal time the
customer is already cancelling. The same query on a schedule finds every
charged-without-pin-without-legacy row *before* anyone touches it, converting a
runtime surprise into a workable backlog.

### Whether the fallback is needed at all

One count decides it, and it is already in the production check: **`TicketOrgTransactions`
rows with a non-null formula snapshot.** That number *is* the legacy cohort size.

In local dev it is **0 of 4,837**, with `content_orgrelationshipconfig` empty. If
production matches, **the fallback is dead code and is not built** — only the
anomaly path is. If production is configured and posting, the count sets how long
the fallback must live. This makes the production check the most load-bearing of
the three, and it is read-only.

If it is needed, keep `fee_engine.py` on a narrow marker-gated path rather than
reverting to direct reversal from stored amounts — direct reversal skips
cancel-time proration, so a part-flown refund would reverse a materially
different amount than was charged. Two deliberate carve-outs:

- **It ignores `fee_config.*_enabled`.** Money was taken; a flag flipped
  afterwards cannot keep it. Same principle as **D9**'s enable-flag consequence.
- **It reproduces legacy including F15 and F16, deliberately.** Its job is to
  close out a cohort charged under those rules, not to be correct by the new
  standard. Reversing "correctly" would reverse a different amount than was
  charged — worse than reproducing a known defect.

### Two guards that must move

Both sit in the first fifteen lines of `process_fee_commission_ledger`, and both
are why the reversal is unreachable in dev today:

1. **`except OrgRelationshipConfig.DoesNotExist: return`** (`ledger_service.py:33-34`)
   — `fee_config` is the *legacy* config. A BRE-pinned reversal must not require
   it to exist. Becomes fallback-path-only.
2. **`if not service_fee_enabled and not commission_enabled: return`**
   (`:39-40`) and the per-kind gates at `:79-83`, `:107-111` — **F20**. These must
   not gate the reversal branch at all. They stay on the SALE branch, where they
   belong.

Without both moves the dispatch table is correct and never executes.


## What D5 requires

1. ~~**Record the pin** at charge time — the one structure above. No context
   snapshot: A6 is option (a).~~ **Done 2026-09-23** — spec 010 in
   `nf-ndc-adapter-generic`, `0d094b971`. The pin, transaction type and exact
   Decimal amount ride onto the adjustment row as three nullable columns
   *outside* the comparison set (010's R3), then project at
   `create_ticket_org_tnx` in their own savepoint: a projection failure is
   logged and the charge and its ledger posting still proceed.
2. **Thread `transaction_type` (D4) into the reversal context.** Free on the BRE
   side: `context` is free-form `serde_json::Value` into `Variable::from`
   (`governance.rs:36`). Free on the frontends: an existing `static`/`oneOf` select
   column covers the enum, and `nf-app-account` degrades an unrecognised inherited
   column to a raw editor rather than breaking.
3. **Lift the reversal out of the evaluation branch** (F11) so a BRE failure
   cannot suppress it — designed together with the row-creation move.
4. **Reconcile the token vocabularies.** Legacy emits seven (`BaseFare`, `YQ`,
   `YR`, `FirstIssue`, `ReIssue`, `PerTicket`, `PerSegment`,
   `fee_engine.py:224-232`); BRE authoring offers nine (`OutputColumnConfig.tsx:51-60`).
   Legacy's "flown" signal is coupon status —
   `exclude(status__in=["B","Flown"])` (`fee_engine.py:184`) — which **answers
   NF-002's Q1 for parity purposes**. Beware `_get_unflown_segment_count` and
   `_parse_segment_count` (`fee_engine.py:116-129`), two **dead** contradictory
   implementations (**F18**).
5. **Find a representation for two behaviours a decision table cannot express:**
   refund-after-exchange chain aggregation (`fee_engine.py:188-189`) and
   SALE-on-reissue sector set difference (`:197-208`). Likely extraction-side
   tokens rather than decision-table logic — a design call, not a foregone one.
6. **Build the parity fixtures first.** See the risk below: they cannot be
   captured from observed behaviour.
7. **Implement the reversal dispatch (D10)** — the three predicates, the
   reconciliation record, and the two guard moves in
   `process_fee_commission_ledger`. The legacy fallback within it is built
   only on evidence from the production check.
8. **Add the I1 detector.** Snapshot the ticketing-time base fare and compare it
   at reversal, logging on mismatch. **I1 is a business fact with no code
   enforcement** — `update_tickets()` still rewrites the base fare on a
   post-ticketing retrieve. This is what makes a breach of it visible rather
   than a silently wrong reversal. One number, not a context blob; it does not
   reopen A6.

## Risk — the mechanism may never have run

In the local development database, `content_orgrelationshipconfig` has **zero
rows**, so `process_fee_commission_ledger` returns at its first guard
(`ledger_service.py:35-36`) on every call; there are **zero** FEE or COMMISSION
ledger entries across 4,837 `TicketOrgTransactions` rows; and **no automated test
covers the reversal** (**N9**).

Combined with the corpus findings — 230 refund pairs with no fee or discount, only
3 void pairs with any — **there is no observed instance of a fee or commission
reversal, of either kind.** Everything recorded here is read from code.

**First action on this epic: run the same read-only counts against production.**
If production matches, NF-004 is not migrating a working feature but implementing
an intended one — a materially different task, and the parity gate cannot be built
by capturing legacy behaviour. If production is configured and posting, this
environment is simply unconfigured and fixtures can be captured from real
behaviour.

`CX6YYW` is the shape worth building a deliberate test case from — five documents
each carrying Ticketed + Exchanged-Reissued + Refunded, exercising both the
exchange-chain aggregation and unflown proration.

## Exclusions — recorded so a gap is not misread as drift

| Excluded | Reason |
|---|---|
| `nf-app-workbench` changes | The cancel flow needs none to deliver this. Its display gap (F12) and blind `offer[0]` pick (F13) are real but separate. |
| `nf-ndc-adapter-rs` changes | Every Rust frame on this path is off by default or a verified stub. Cancellation is Python-owned by evidence, not preference. |
| `nf-app-home-v2` | No BRE authoring surface exists there. |
| Negating or deleting sale-time ledger rows | **D7** — matching legacy. |
| Direct reversal from stored amounts | Rejected — see "Why re-evaluation". |
| Persisting the quoted cancellation differential | Out of scope, but note it currently survives only 30 minutes in Redis. |

## Open questions

| # | Question | Blocks |
|---|---|---|
| **A3** | D4 detailed design — still pending. | Requirement 2 |
| **A4** | Does a **partial** cancellation exist as a distinct shape? No partial-specific branch was found in `update_order_status_cancelled()`; `REMOVE_FREE_SERVICES` shares the full-cancel branch. | Fixture coverage |
| **A5** | `CANCEL_ORDER_RETAIN` reassigns `RQ = OrderChangeRQ` (`content_state.py:2371`) specifically so it *does* record. Intended? Does retain reverse, partially reverse, or keep the fee? | Retain behaviour |
| **A7** | Should the reversal's tokens be extracted from the **cancel response** or the **tables**? NF-002 is classified split-source on exactly this axis and does not settle Python's side. | Requirement 4 |
| **A8** | The confirm is **not replayable** — its correctness depends on a 30-minute Redis entry keyed by a client-supplied `trxId`. Pre-existing, but NF-004 puts a ledger write on that path. Decision or inheritance? | Resilience |

Resolved: **A1** → D8. **A2** → the record above. **A6** → **option (a)**, F19
accepted. **P8** → D6. **P9** → confirmed 2026-09-23, recorded as NF-003 **I1**.

## Deferred

A durable BRE-side trace of the reversal (D7) — composes with NF-003's
audit-durability cluster (E3+E14+E15+E16) and should be scoped with it.

## Parity gate

Conformance fixtures over `(txn_type, ticket shape)`:

- `SALE` — first issue, and reissue (the sector-delta case)
- `VOID` — no coupon flown, and at least one flown (**the D6/F15 case**)
- `REFUND` — no coupon flown, partially flown, fully flown, refund-after-exchange
- Rounding — at least one 3-decimal and one **zero**-decimal currency. Legacy
  hardcodes `places = 3 if currency_code == "OMR" else 2` (`fee_engine.py:241`);
  `LedgerTransaction.amount` is `decimal_places=2`, truncating the third decimal
  the engine deliberately computes; and the cancel amount forwarded to the
  provider is `round(amount, 2)` (`layer_inputs.py:1306`). Fixtures pin the
  *intended* behaviour, not legacy's.

**This is a transitional mirror.** The gate exists to retire the legacy side, and
is satisfied when `fee_engine.py` has no caller on the cancel path.

**Caveat:** per the risk above, these fixtures are derived from code intent, not
captured behaviour — and D6/F15 shows code intent can itself be wrong. They need
explicit sign-off as *correct*, not merely as *matching*.

## Definition of done

1. The reversal no longer sits inside `if _operation_records_fee_discount(RQ)` /
   `if not recording_outcome.has_failures:` — a BRE failure cannot suppress it.
2. No cancellation evaluates a new fee/discount charge; `transaction_type` carries
   `VOID`/`REFUND` truthfully on every cancel path.
3. Reversal amounts come from the BRE, pinned to the charge-time
   `composite_version`, and match the fixtures in every row. Tokens are rebuilt
   live — A6 option (a), with F19 accepted.
4. Sale-time `FullfilmentOrdersPriceAdjustments` / `TicketOrgTransactions` rows are
   byte-identical before and after a cancellation (D7).
5. **Cutover:** `fee_engine.py` has no caller on the primary cancel path — the
   only remaining caller is the marker-gated fallback (D10).
   **Retirement:** no caller at all, gated on the legacy cohort being empty.
   The D10 predicate proves it: zero `legacy`-marked rows still in cancellable
   life. If the production check shows an empty cohort, the two stages collapse
   into one.
6. ~~The unique constraint on `content_ticketorgruleapplication` is **verified
   present in the database**, not merely declared (see F17).~~ **Done 2026-09-23**
   — `uniq_ticketorgruleapplication_charge_kind_subkind` confirmed in
   `pg_constraint` (local), alongside `CHECK (amount <> 0)`. Spec 010,
   `0d094b971`.
