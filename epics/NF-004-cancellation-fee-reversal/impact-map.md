# NF-004 — Impact map

State of the world as researched **2026-09-22**, six parallel working-tree passes
plus direct re-reads of the contested sites. Per the rot rule every line number
here is a dated snapshot — `git status` and open the file before acting.

Two passes disagreed on whether `CANCEL_PAID_ORDER` re-evaluates fee/discount.
**It does.** Re-verified directly: `mutations.py:37`, `content_state.py:146-158`,
and a whole-file check that `:2371` is the only `RQ` reassignment. Recorded here
because the wrong answer is the plausible-looking one.

## Working-tree state, 2026-09-22

| Repo | Branch | Relevant dirt |
|---|---|---|
| nf-ndc-adapter-generic | `rules-engine-migration` | Cancel-path files (`content_state.py`, `db_api.py`, `ledger_service.py`, `fee_engine.py`, `utils.py`, `models.py`) all **clean/committed**. Dirt is elsewhere — submodules, `reports_helper.py`, `CLAUDE.md`. |
| nf-ndc-adapter-rs | `dev` | `nf_ndc/src/rules/` untracked (~17.5k lines); `graphql/schema.rs`, `env.rs` modified-unstaged |
| nf-ndc-connect-rules-engine | `dev-bre-foundation` | ~68 dirty; `evaluate/handler.rs` modified, `audit/retention.rs` untracked |
| nf-app-workbench | `develop` | Relay artifacts + lockfile only — nothing hand-edited on the cancel flow |
| nf-app-home | `staging-auth` | `src/routes/rules/`, `src/api/bre.ts` untracked |
| nf-app-account | `develop-auth` | `RuleEditor/`, `BusinessRules/`, `api/domains/` untracked; `MasterRulesets.tsx` modified-tracked |

## Code sites by repo

### nf-ndc-adapter-generic — carries essentially all the work

**The seam to break (requirement: lift the reversal out).**

| Site | What it is |
|---|---|
| `content_state.py:146-150` | `FEE_DISCOUNT_RECORDING_OPERATIONS = {OrderCreateRQ, OrderChangeRQ, OrderRetrieveRQ}`; `:142-145` is the FR-011 comment asserting the absence of `OrderCancelRQ` *is* the enforcement |
| `content_state.py:153-158` | `_operation_records_fee_discount(RQ)` — request-type gate, **never usecase** |
| `content_state.py:3079` | the recording call; `:3080` calls `apply_fee_discount_for_order` |
| `content_state.py:3094` | `if not recording_outcome.has_failures:` — the gate that suppresses the reversal on a BRE failure |
| `content_state.py:3155` | `publish_ticket_transactions(...)` — the reversal's only trigger, nested two levels inside the above |
| `content_state.py:2364-2371` | the cancel usecase branch; `:2371` `RQ = OrderChangeRQ` for `CANCEL_ORDER_RETAIN` (see A5) |

**The reversal itself.**

| Site | What it is |
|---|---|
| `ledger_service.py:21` | `process_fee_commission_ledger()` — the reversal entry point |
| `ledger_service.py:49-54` | `txn_type` from `txn_coupon_status`; `is_reversal` |
| `ledger_service.py:71` | `build_token_context(ticket, txn_type)` — context rebuilt at reversal time |
| `ledger_service.py:92-96`, `:120-124` | the DEBIT↔CREDIT direction flip |
| `ledger_service.py:136-192` | `_write_fee_entry`; `:150-159` idempotency on `(content_type, object_id)`; `:161` `evaluate_formula` |
| `utils.py:1769-1794` | SALE-formula snapshot copy onto a VOID/REFUND `TicketOrgTransactions` row |
| `utils.py:1883`, `:1908`, `:1976` | `LedgerEntry.exists()` idempotency gates and the `process_fee_commission_ledger` call |
| `utils.py:623` | `create_ticket_org_tnx()`; `utils.py:1921` `publish_data()`; `utils.py:2182` `publish_ticket_transactions()` |

**The dispatch and its guards — D10.**

| Site | What it is | Move |
|---|---|---|
| `ledger_service.py:33-34` | `except OrgRelationshipConfig.DoesNotExist: return` — the legacy config is required before anything else happens | **Becomes fallback-path-only.** A BRE-pinned reversal must not need `fee_config` to exist. This guard is why dev shows zero reversals across 4,837 rows |
| `ledger_service.py:39-40` | `if not service_fee_enabled and not commission_enabled: return` | **Off the reversal branch entirely** (F20). Stays on SALE |
| `ledger_service.py:79-83` | per-kind fee enable gate | same |
| `ledger_service.py:107-111` | per-kind commission enable gate | same |
| `ledger_service.py:150-159` | `_write_fee_entry` idempotency key `(content_type, object_id, entry_type)` | **Unchanged — reused as the `charged` predicate.** The existence of that entry *is* the definition of "money moved" |
| `models.py:1159-1160` | `applied_service_fee_formula` / `applied_commission_formula` | **Unchanged — reused as the `legacy` predicate.** Test `IS NOT NULL`, never truthiness: `""` is a real stored value |
| `utils.py:1764-1766` | the write-once both-must-be-`None` guard that writes those columns | **Unchanged.** It is what makes the marker self-evidencing — the engine being discriminated for is the one that writes it |
| `utils.py:592-603` | the ten fields re-derived on every retrieve (F16) | **Unchanged, and must not be read by the dispatch.** Using these columns as `charged` would fire the anomaly path on effectively every row — 4,837 rows carry amounts, zero carry a FEE/COMMISSION `LedgerEntry` |

Net-new: the **reconciliation record** — one row per charge that could not be
reversed, carrying kind, amount at stake, ticket, seller org and reason. Written
on the anomaly arms only. Same structure **D7** defers and NF-003's
audit-durability cluster (E3+E14+E15+E16) needs; scope it once, not three times.

**The engine being replaced under D5.**

| Site | What it is |
|---|---|
| `fee_engine.py:176-232` | `build_token_context` — the legacy SALE/VOID/REFUND token table |
| `fee_engine.py:184` | `unflown_count` — coupon-status signal, `exclude(status__in=["B","Flown"])`. **Answers NF-002 Q1 for parity.** |
| `fee_engine.py:188-189` | `_aggregate_ticket_chain` — refund-after-exchange base/YQ/YR aggregation |
| `fee_engine.py:197-208` | SALE-on-reissue sector-designator set difference |
| `fee_engine.py:211-212` | **VOID and REFUND share the unflown branch — the D6/P8 contradiction** |
| `fee_engine.py:215-220` | `PerTicket` = `unflown/segment_count` on REFUND |
| `fee_engine.py:224-232` | the seven emitted tokens; `float()` cast loses the Decimal discipline |
| `fee_engine.py:235-242` | `evaluate_formula`; `:241` `places = 3 if OMR else 2` (F2) |
| `models.py:662` | `OrgRelationshipConfig.fee_config` — `service_fee_formula` / `commission_formula`, `*_enabled` |
| `content_rules.py:6121` | the in-code statement that commission is outside the rules engine |

**Ledger models (untouched under D7, listed because the gate asserts they stay
untouched).**

| Site | Note |
|---|---|
| `models.py:1319` | `FullfilmentOrdersPriceAdjustments` — `adjustment_amount` is **FloatField** despite Decimal parsing upstream; no `Meta`, no unique constraint; `:1375` `bre_evaluation_log_id` excluded from the idempotency comparison |
| `models.py:1111` | `TicketOrgTransactions` — all six NF-001 sub-type columns FloatField; `Meta.unique_together` at `:1163`; carries `applied_service_fee_formula` / `applied_commission_formula` |
| `content_rules.py:5263-5320` | `_write_price_adjustment_rows` — delete+recreate per chain level, multiset-gated on `_PRICE_ADJUSTMENT_COMPARISON_FIELDS` |
| `utils.py:2438` | refund reporting reads the **original positive** rows via `order__sub_status=REFUND` |

**Context and client.**

| Site | Note |
|---|---|
| `content_rules.py:6980-7012` | the evaluated context: `airline_code, origin, destination, cabin, rbd, passenger_type, travel_date, transaction_type, applies_to, base_fare, currency` + per-tax-code keys + `issue_date`. `:6993` is the hardcoded `"SALE"`. **`usecases` is not in this dict** — though it *is* available at `response_by_usecase():2220`, well before the context is built |
| `bre_client.py:203` | `POST {BRE_BASE_URL}/v1/rules/evaluate`; payload is `{ruleVersions, context}` — **no `reference`** (E15) |
| `bre_client.py:157` | `_OUTPUT_AMOUNT_KEYS = ("amount","service_fee","discount")` — see F10 |
| `db_api.py:2971-3146` | `update_order_status_cancelled()`; `:3085` is **F9's moved anchor**; `:3141-3146` sets `refund_indicator`; `:3074/:3108/:3117` call `update_tickets()` |
| `content_state.py:2972-2998` | the **other** `refund_indicator` derivation, from provider `differential_type_code` |
| `usages.py:43` / `inputs.py:1464-1472` | `CANCEL_PAID_ORDER` → `request.change_order_choice.accept_cancelled_offer`; `CANCEL_UNPAID_ORDER` → `cancel_unpaid_order` |

### nf-ndc-connect-rules-engine — small, but on the critical path

| Site | Note |
|---|---|
| `evaluate/handler.rs:75-90` | request: `rule_versions` XOR `rule_type_lookups`, `context`, `reference`. XOR enforced at runtime (~`:244-260`), not by serde |
| `evaluate/handler.rs:178-193` | item result: `composite_version`, `composite_hash`, `evaluation_log_id` (`:190`), `winning_rule` (`:192`) |
| `evaluate/handler.rs` ~`:680-758` | `resolve()` — **exact `composite_version` pin or "current published" only. No date-window resolution.** `effective_from`/`effective_to` never read at evaluate time |
| `governance.rs:36` | `Variable::from(context)` — untyped passthrough, so a new context key costs **zero** service change |
| `composite.rs:16` | the in-code note that `composite_version` "can arrive from an external caller (VOID/REFUND request)" — the intended reversal vehicle |
| `registry/sub_type.rs` | `ServiceFee: [Standard, Extra, Additional]`, `Discount: [Standard, "Corporate Deal", PLB]`, `Commission: [Standard, Extra]`. **No refund/cancel/void/penalty sub-type.** |
| `crates/nf-bre-core/src/store.rs`, `types.rs`, `lib.rs:16-24` | the **dead** date-aware `Selector::EffectiveOn`/`Selector::Version` path — callers are benches and its own tests only |
| `audit/retention.rs:296` + migration `:118-120` | collector index `WHERE coalesce(reference,'') = ''`. A reversal's audit row survives collection **only if `reference` is non-empty** |

No sign constraint exists anywhere — a decision table may return a negative
amount, and nothing clamps or `abs()`es it.

**Fixture correction required — F23.** `fixtures/master-corpus/mc-011-refund-proration.json`
and `mc-006-composite-version-reevaluation.json` re-derive proration inside the
output expression from `unflown_segment_count`, while the adapters send
`per_segment` **already prorated**. Both are authorable, so the corpus currently
demonstrates the double-counting pattern. They must be rewritten to consume
`per_segment` — carefully, because `mc-011` is also where **D6** is correctly
encoded ("only REFUND prorates — VOID uses the full Segment Count").

### nf-app-home / nf-app-account — D4 only, and it is cheap

| Site | Note |
|---|---|
| `OutputColumnConfig.tsx:51-60` | the nine tokens: `segment_count, unflown_segment_count, per_segment, per_ticket, per_tkt_issue, total_fare, base_fare, yq, yr` |
| `metadata/contract.ts:11` | `NF_CELL_KEY = "nfCell"`; `:46-90` the cell metadata; `:89` `DOMAIN_OPTIONS = [airport, airline, country]` |
| `RuleEditor/types.ts:354-403` | `resolveWidgetId` — an existing `static`/`oneOf` enum column. D4 reuses it; nothing net-new |
| `RuleEditor/resolveColumn.ts:105-158`, `:176-253` | three-tier graceful degrade for an unrecognised inherited column — adding `transaction_type` **cannot break existing agency screens** |
| `BusinessRules/Components/slotData.ts:17-28` | `extractSlotData` walks rules generically by `slotId` — column-agnostic |
| `codecs/output.ts:39-53` | output number codec `/^-?\d+(?:\.\d+)?$/` — **negatives are authorable**, no sign lock |
| `contract.ts:1-8` | hand-copied from account's `types.ts`; the relationship is documented **one-directionally** and has no automated check |

**No transaction-type / refund / void / cancel / reversal / penalty concept
exists in either UI today** — only an SCSS comment in `RuleGrid.scss:343`, `:1058`
using "transaction type" as a hypothetical example of a closed enum.

### nf-ndc-adapter-rs — excluded, recorded for completeness

`schema.rs:548` / `:492` / `:967` / `:959-964` (`todo!()`); `mod.rs:1289` (reshop
stub); `mod.rs:913` (`apply_orderview`, real but flag-off);
`context.rs:128`, `quote_context.rs:369`, `order_context.rs:386`, `:647`
(hardcoded `"SALE"`).

**Worth knowing, because it corroborates D6:** `context.rs:771-810` already
implements a real SALE/VOID/REFUND token table, and at `:785-803` **VOID takes
the full `segment_count` while REFUND prorates by `unflown/segment_count`** —
i.e. Rust agrees with NF-002 and disagrees with `fee_engine.py:211-212`. Its
VOID/REFUND arms are unit-tested (`:1210`, `:1226`) but unreachable, since both
live callers pass `"SALE"` (`:766-770`). So the contradiction P8 records is
**two implementations against one**, not a coin toss — which is why D6 goes the
way it does. It also means Rust becomes the reference the day OrderView is
enabled. `usecase.rs` defines
`CancelPaidOrder`/`CancelUnpaidOrder`/`CancelOrderRetain` and
`get_order_reshop_usecases`/`get_order_change_usecases` (`:324`, `:336`) are
**never called anywhere**. `order_context.rs` never sets `unflown_segment_count`
at all.

## Adopter checklist

Ticked only against code, never against a spec's own status field.

- [ ] **nf-ndc-adapter-generic** — lift the reversal out of the evaluation branch
- [ ] **nf-ndc-adapter-generic** — cancel usecases stop recording a new charge
- [x] **nf-ndc-adapter-generic** — new table `content_ticketorgruleapplication` (A2); unique constraint **verified in the DB**, `DecimalField` not `FloatField`. **No new column on `TicketOrgTransactions`** — A6 is option (a), no context snapshot, F19 accepted — verified in DB 2026-09-23 (local, migration `0182`), [spec 010](../../../nf-ndc-adapter-generic/specs/010-cancellation-rule-application-record/spec.md)
  - Also carries `transaction_type`, verbatim as sent to the BRE (Q1). Zero amounts get no row, enforced by a `CheckConstraint` (Q2). Only `Ticketed` charges project; `Void`/`Refunded` copy the sale's rows; every other status gets none (R14). A failure writing the rows rolls back only their savepoint: the charge and its ledger posting proceed, an ERROR is logged, and the charge has no rows, which D10 reports as an anomaly (R8). Three nullable in-transit columns on `content_fullfilmentorderspriceadjustments` (`composite_version`, `bre_transaction_type`, `bre_amount`), outside the comparison set.
- [x] **nf-ndc-adapter-generic** — copy the pin forward onto the reversal row from the sale row. **Done** — spec 010, `0d094b971`: `Ticketed` projects from the adjustment rows, `Void`/`Refunded` copy the sale's records verbatim, every other status gets none
- [ ] **production check** — `content_orgrelationshipconfig` count, `LedgerEntry` by `entry_type`, `TicketOrgTransactions` with a formula snapshot. **First action.**
- [ ] **nf-ndc-adapter-generic** — derive `transaction_type` from `usecases`, retire the `"SALE"` literal
- [ ] **nf-ndc-adapter-generic** — reversal calls the BRE with the pin + `transaction_type` + `reference`
- [ ] **nf-ndc-adapter-generic** — token parity incl. the exchange-chain and sector-delta cases
- [ ] **nf-ndc-adapter-generic** — dispatch on the three D10 predicates, per kind (FEE, COMMISSION separately); `charged` read from `LedgerEntry`, never from the amount columns
- [ ] **nf-ndc-adapter-generic** — move the two guards (`ledger_service.py:33-34` fallback-only; `:39-40`/`:79-83`/`:107-111` off the reversal branch). **Without this the dispatch is correct and never executes**
- [ ] **nf-ndc-adapter-generic** — reconciliation record + alert on the anomaly arms; the cancellation still completes
- [ ] **nf-ndc-adapter-generic** — the same predicate runnable as a scheduled sweep, not only at reversal time
- [ ] **nf-ndc-adapter-generic** — *conditional on the production check:* marker-gated `fee_engine.py` fallback, ignoring `fee_config.*_enabled`, reproducing F15/F16 deliberately. **Not built if the legacy cohort is empty**
- [ ] **nf-ndc-adapter-generic** — *cutover:* `fee_engine.py` has no caller on the primary cancel path
- [ ] **nf-ndc-adapter-generic** — *retirement:* no caller at all, proved by the D10 predicate returning zero `legacy`-marked rows still in cancellable life
- [ ] **nf-ndc-connect-rules-engine** — confirm the pinned-version reversal path needs no service change (expected: none)
- [ ] **nf-ndc-connect-rules-engine** — rewrite `mc-011` and `mc-006` to consume `per_segment` rather than re-deriving from `unflown_segment_count` (**F23**), preserving `mc-011`'s D6 encoding
- [ ] **nf-ndc-adapter-generic** — **NF-002's Python token derivation (A9)**. Blocks every proration case in 011; Python sends none of `per_segment`/`per_ticket`/`per_tkt_issue`/`segment_count`/`unflown_segment_count` today
- [ ] **nf-app-home** — author `transaction_type` on the template (D4)
- [ ] **nf-app-account** — verify inherited-enum rendering (expected: already works)
- [ ] **fixtures** — the parity corpus, which does not exist yet

## Blast radius

- **Money, on a live path.** Every ticketed cancellation posts through here.
- **Two ledgers, one of them accounting.** The reversal writes to
  `LedgerAccount.balance` under `select_for_update()`. Getting the direction or
  the amount wrong is an agency balance error, not a display error.
- **Idempotency cuts both ways.** One `LedgerEntry` per `TicketOrgTransactions`
  row means a wrong reversal **cannot be re-posted or corrected** by re-running.
- **No test net.** Requirement 5 exists because there is nothing to regress
  against today.
- **The dispatch decides whether money moves back.** A wrong predicate is not a
  wrong number — it is a reversal that silently does not happen, or one that runs
  through the wrong engine. The `charged`-from-columns mistake would additionally
  bury every genuine anomaly under thousands of false ones.
