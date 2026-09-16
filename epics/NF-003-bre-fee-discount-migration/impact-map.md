# NF-003 — Impact map

State of the world as researched 2026-09-16, across all six repos. This records
**what exists now**, so leaf specs can be written against reality rather than
against the design docs, which are stale in several places.

## ⚠ Nothing in this epic is in version control

| Repo | BRE work | Branch | `specs/` tracked? |
|---|---|---|---|
| nf-ndc-adapter-rs | `nf_ndc/src/rules/` **17,533 lines untracked**; `graphql/schema.rs` modified-unstaged (all 8 frame call sites); `nf_db/src/bre_rule_{set,template}.rs` untracked | **none** — working-tree changes on `dev`, which receives unrelated merges | **no** — added to `.gitignore` |
| nf-ndc-adapter-generic | 2,875 insertions / 7 files; `bre_client.py` staged-new; `backend/ndc/tests/` untracked | `rules-engine-migration` | **no** — `.gitignore:174` |
| nf-ndc-connect-rules-engine | 68 dirty files; specs 019 + 020 and `merge/null_default.rs`, `audit/retention.rs` fully untracked | `dev-bre-foundation` | partial |
| nf-app-home | `src/routes/rules/`, `src/api/bre.ts`, `specs/`, `.specify/` — **0 files tracked** | on `staging-auth` (unrelated auth work) | no |
| nf-app-account | `src/components/RuleEditor/`, `src/routes/BusinessRules/`, `src/api/domains/` — **0 files tracked**. Legacy `src/routes/MasterRulesets/` **is** tracked | on `develop-auth` (unrelated auth work) | no |
| nf-app-workbench | none — no spec-kit, no BRE awareness | `develop` | n/a |

Sandeep is aware and will commit after review (2026-09-16).

## Per-repo state

### nf-ndc-connect-rules-engine — the BRE service

Three tables in `service/migration/src/`: `bre_rule_template`
(`id, rule_type, tenant_type, version, status, jdm JSONB, slot_manifest JSONB`;
unique on `(rule_type, tenant_type, version)`), `bre_rule_set`
(composite PK `(id, version)`; `org_id, rule_type, sub_type, applies_to,
effective_from/to, template_version INT, status, slot_data JSONB, is_default`),
and `bre_evaluation_log`.

- `template_version` is an **INT, not an FK** — the binding is
  (rule_type, template_version) → template.
- Templates have **no** `effective_from`/`effective_to`; applicability is
  `status`/`version` only. Date ranges live on the ruleset.
- Merge: `merge::algorithm::merge()` writes agency rows into the template graph's
  slot node. A slot absent from `slot_data` leaves the **template's own default
  rows** standing — never null.
- Two forms, deliberately split (`merge/null_default.rs`): *clean* (what
  authoring UIs display and round-trip) and *executable* (every free identifier
  rewritten `X` → `(X==null?0:X)`). Getting these backwards is the documented
  failure mode; `mergedJdm` GraphQL returns both.
- Cache key `tpl:v{n}+rs:{id}:{v}` → `composite_hash`. A cache hit does **zero**
  Postgres queries. Invalidation is by **deploy-time key-prefix bump**, not
  eviction — there is no targeted invalidation when a template is republished.
- **No allowed-variables or domain-restriction metadata exists here.** It rides
  inside the `jdm` JSONB as `nfCell` keys written by `nf-app-home`; the service
  stores it opaquely and enforces nothing. A direct GraphQL call bypasses all UI
  validation.
- Sub-type registry is hardcoded (`registry/sub_type.rs`) and spells
  `"Corporate Deal"` **with a space**, vs Rust's `DiscountCorporateDeal`.
- `winning_rule_id` is NULL under `collect` hit policy when aggregation cannot
  resolve to one row — never guessed. Relevant to NF-001.

**`service/openapi/bre-v1.yaml` is stale and actively misleading** — documents
`/v1/evaluate` (wrong path) with the superseded Feature-006 single-item payload.
Do not write leaf specs from it. The real contract is
`POST /v1/rules/evaluate`, `ruleVersions` XOR `ruleTypeLookups`, max 50 items,
free-form `context`.

### nf-ndc-adapter-rs

Rust is the **front door for every NDC surface**; most resolvers proxy the
*pricing* to Python and run the rules frame on the way out. `MessageSource`
encodes this: `RustAdapter` = priced in-house, `PythonProxy` = priced by Python.

Frame: chain resolve (`rules/chain.rs`) → pin resolution (`rules/resolve.rs:195`,
**at most 2 SQL queries** regardless of chain depth) → context extraction →
evaluate (`rules/evaluate.rs:65`) → reduce → inject (`rules/inject.rs:215`).

- BRE client `rules/rule_source.rs`: forwards the **caller's** bearer token, sends
  `ruleVersions` **only** (never `ruleTypeLookups`, which would destroy version
  pinning), batches at 50, correlates results **by position**, 3s timeout,
  **no retry by design**. BRE down → whole pricing request fails; no fallback to
  zero, and `read_amount` refuses to coerce a missing amount to zero.
- Resolution key is `{org_id}:{audience}:{scope_id}` (spec 006 widened it from
  `{org_id}:{audience}` so two subscriptions in one org resolve differently).
- **Rust writes no rows.** `content_fullfilmentorderspriceadjustments` exists as
  an entity but `nf_ndc/src/rules/` never references it.
- All flags default **off** (`env.rs:136-155`).
- NF-001 and NF-002 are **done and tested here** (specs 011, 012, 21/21 each) —
  the hub's impact maps for both list these as pending. Stale.

### nf-ndc-adapter-generic

**Python and the BRE share one database.** `BreRuleSet` / `BreEvaluationLog` are
`managed = False` Django views onto the BRE's tables, so ruleset *resolution* is
a local SQL query and only *evaluation* is HTTP. Not a pure service boundary.

- Ledger: `FullfilmentOrdersPriceAdjustments` (`models.py:1317`) already carries
  `adjustment_kind` + `adjustment_sub_kind` and `bre_evaluation_log_id`.
  `TicketOrgTransactions` (`models.py:1109`) **already has the six NF-001
  sub-types as columns**. Note the spellings: `Fullfilment` (triple-l), plural
  `TicketOrgTransactions`.
- **No feature flag exists.** Routing is structural, per surface.
- **The legacy engine is structurally dead, not merely superseded.**
  `available_master_rule()` filters `OrgMasterRuleSet` by ids that spec 004
  repointed at `bre_rule_set`, so it has matched nothing since. All three live
  call sites guard with `if master_rules:`, so the block is skipped silently.
- Ordering is load-bearing: `save_order()` → `apply_fee_discount_for_order()` →
  ticket-org projection → injection. Spec 009 T014 moved the projection into this
  ordering because it previously ran ~170ms early and recorded permanent zeros.
- Failures append to `response["error"]` as *warnings* on create/change
  specifically so a caller cannot retry and double-book.
- No caching in the Python BRE path, unlike Rust.
- **NF-002 has no leaf spec here** (no `010-fee-discount-tokens`), though
  adapter-rs has `012`.

### nf-app-home / nf-app-account

Inheritance is built and works: `stripTemplateRows` hands the agency a graph with
the template's rows removed plus a `slotManifest`; `extractSlotData` saves rows
only; `templateVersion` is sent verbatim, which is the pin.

- Domains implemented are **`airport`, `airline`, `country`** — there is no
  "nationality".
- Agency-tenant templates key on **plain rule category**, Platform-tenant on
  dotted `category.subType`. This asymmetry is recorded only in a code comment
  (`NewRuleSetPage.tsx:126-129`).
- `contract.ts` in home is **hand-copied** from account's `types.ts`; both files
  say so. Drift surface with no shared package.
- The `Persegment` incident is **half-fixed**: the nine tokens are now always
  available, but `addManualVariable` still validates identifier *syntax* only —
  its own comment says "nothing here checks a typed name against reality."
- Agency rulesets **never migrate** to a newer template version (home spec 004
  FR-009). The migrate action is spec'd in BRE docs, never built.

### nf-app-workbench

No spec-kit, no BRE awareness. `DiscountsFee.tsx` takes `any` and treats fees as a
string-keyed amount map; `FareCalculations.tsx:139-150` **re-sums client-side**.
NF-001's extra sub-type rows render with no code change — but a renamed or
duplicate key silently changes a displayed total.

## Work required by the scope decisions

Not yet a checklist — these become leaf specs once D4, G1 and G2 close.

- **D1** — retire or permanently disable Rust's `orderview_proxy` path
  (`schema.rs:1157`, `:1007`, `:710`); resolve Kyte first (G1).
- **D2** — reshop: either make rs `apply_orderreshop` real (currently
  `SectionPlaceholder("context")`, `mod.rs:1289`) or move generic's reshop
  interception off the dead legacy engine. Repo undecided.
- **D3** — cancellation: add `OrderCancelRQ` to
  `FEE_DISCOUNT_RECORDING_OPERATIONS`, reversing generic FR-011; resolve NF-002
  Q1 first (G2).
- **D4** — `transaction_type` column: BRE template schema or `nfCell` metadata
  (decides whether the backend can enforce it), `nf-app-home` authoring UI,
  `nf-app-account` rendering, and context plumbing in both adapters. Python
  already has `transaction_type` in context as a `"SALE"` literal
  (`content_rules.py:6987`) with `usecases` available to derive the real value;
  Rust passes a `"SALE"` literal by design (`context.rs:128`).
- **Money-correctness** — the four defects in `epic.md`, before final commit.
- **Retirement** — legacy `OrgMasterRuleSet` authoring is still live and writable
  while its evaluation is dead. Unspecced.
