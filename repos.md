# Repo map

| Repo | Role | Stack | spec-kit | Constitution |
|---|---|---|---|---|
| nf-app-home | Platform admin | frontend | yes | ⚠ template |
| nf-app-home-v2 | Platform admin (next) | frontend | no | — |
| nf-app-account | Agency admin | frontend | yes | ⚠ template |
| nf-app-workbench | Search & booking | frontend | **no** | — |
| nf-ndc-adapter-generic | Legacy backend | Python/Django | yes | ⚠ template |
| nf-ndc-adapter-rs | New backend | Rust | yes | ⚠ template |
| nf-ndc-connect-rules-engine | Business rules (ZEN) | Rust + Python | yes | ✅ 243 lines |

## Dependency shape

Not a line. `nf-ndc-connect-rules-engine` is a standalone service; both adapters
are **peer clients** calling its REST/GraphQL endpoints with their own native HTTP
clients. A rules-engine change fans out to both adapters rather than cascading
through one.

    rules-engine ──┬──> adapter-generic (Django) ──┐
                   └──> adapter-rs (Rust) ─────────┴──> app-home / app-account / workbench

## Surface ownership

Corrected 2026-09-16 against both adapters' working trees. The earlier version of
this table was wrong in two places and is preserved only in git history.

**Rust is the front door for every NDC surface.** All six resolvers live in
`nf-ndc-adapter-rs/nf_ndc/src/graphql/schema.rs`; most proxy the *pricing* to
Python and map the result back, then run the Rust rules frame on the way out.
"Python owns a surface" therefore never means Python is the entry point.

| Surface | Evaluates + injects | Persists to tables | Note |
|---|---|---|---|
| OfferPrice | **adapter-rs**, both branches | — | Python evaluation retired (`content_state.py:2912`); Python's fee nodes are dummies Rust overwrites (`schema.rs:390`) |
| OrderCreate / OrderChange / OrderRetrieve | **both** ⚠ | **adapter-generic** | Collision zone — see below |
| Kyte fast path (`orderview_rust`) | **adapter-rs** | — | Never calls Python |
| OrderQuote (reshop quote) | **adapter-rs** | — | `apply_orderquote`, real |
| OrderReshop | **neither** ⚠ | — | rs `apply_orderreshop` is a stub; generic's interception runs the dead legacy engine |
| Ticketing | **adapter-generic** | **adapter-generic** | Not a separate surface — a granularity switch inside OrderView |
| Cancellation | **neither** | — | Excluded by design (generic FR-011) |

⚠ **OrderCreate/Change/Retrieve is a collision zone, not clean ownership.**
adapter-rs evaluates and injects on all three (`schema.rs:1157`, `:1007`, `:710`)
behind the `orderview_proxy` flag; adapter-generic independently evaluates and
writes the ledger. Rust's flags all default **off** (`env.rs:136-155`), so nothing
collides today — but this is an unmade decision, not a resolved split. The
"Rust injection being removed per FR-013" claim in the earlier table was not
verified against Rust's code, where the injection is present and tested.

⚠ **OrderReshop is broken on both sides, silently.** Rust returns
`SectionPlaceholder("context")` (`mod.rs:1289`). Python's reshop path calls
`available_master_rule`, which has matched nothing since spec 004 repointed
`OrgRelationshipRule.rule_set` at `bre_rule_set` — so reshop fee/discount is
currently **zero, with no error**.

## Known gaps

- Five of six constitutions are unedited spec-kit placeholders. Only
  `nf-ndc-connect-rules-engine` has a real one — use it as the base for a shared
  constitution.
- `nf-app-workbench` has no spec-kit and appears once across all specs, despite
  being a primary frontend.
- `fixtures/master-corpus/` lives inside nf-ndc-connect-rules-engine and is
  referenced by relative path from 15 files. It is the de facto cross-repo parity
  corpus but cannot be consumed by the adapters as-is.
