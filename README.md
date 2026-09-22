# nf-ai-context

Cross-repo coordination layer for NuFlights. Each repo keeps its own spec-kit and
its own `specs/NNN-slug/`; this repo holds only what spans them.

    epics/NF-NNN-slug/
      epic.md          requirement, shape, scope boundaries
      impact-map.md    code sites, adopter checklist, blast radius, exclusions
      decisions/       ADRs — one per decision, not one per epic
      fixtures/        parity artifacts where two implementations must agree

## Epic shapes

The artifact that holds an epic together differs by shape. Classify first.

| Shape | Coupling artifact | Gate |
|---|---|---|
| **cascade** | schema (OpenAPI / GraphQL SDL) | consumers build against a frozen schema + mocks |
| **fan-out** | core version + adopter checklist | no core release until every adopter has adapted |
| **mirror** | conformance fixtures | identical results across implementations, 0 discrepancies |
| **solo** | recorded exclusion | reason logged so a gap is not misread as drift |

A mirror may be **split-surface**: the same rule applied by different repos to
different surfaces, rather than the same code written twice. NF-001 is one.

It may also be **split-source**: one derivation mirrored in both repos, fed by
inputs each repo reads from a different place. NF-002 is one — both derive the
same token table, but only one repo ever holds a ticket to count coupons from.
The parity gate is on the derived values, not on the extraction beneath them.

## Conventions

- Per-repo spec numbering stays sequential and uncorrelated across repos. The
  `epic:` field in each leaf spec's frontmatter is the join key, not the number.
- One branch name across every repo in an epic: `epic/NF-NNN-slug`.
- Contract changes go back to the hub. Never patch a shared contract inside a
  leaf repo.

## Epics

| ID | Title | Shape | Status |
|---|---|---|---|
| [NF-003](epics/NF-003-bre-fee-discount-migration/epic.md) | Service fee & discount migration to GoRules ZEN | **program** | draft — scope decided, specs pending |
| ├ [NF-001](epics/NF-001-subtype-scoped-aggregation/epic.md) | Sub-type-scoped fee/discount aggregation | mirror (split-surface) | approved |
| ├ [NF-002](epics/NF-002-fee-discount-token-context/epic.md) | Per-ticket / per-segment token context | mirror (split-source) | draft — blocked on Q1 |
| └ [NF-004](epics/NF-004-cancellation-fee-reversal/epic.md) | Cancellation fee/commission reversal on the BRE | mirror (transitional) | **approved** — spec 010 in progress |

**NF-003 is a `program`** — it contains NF-001, NF-002 and NF-004 rather than
sitting beside them. A program has no single coupling artifact of its own; each sub-epic
carries its own gate. The relationship is declared in frontmatter (`contains:`
and `parent:`), never by number order or directory nesting — NF-003 is the parent
despite the higher number because its children were numbered first.

## Backlog

[backlog.md](backlog.md) holds pre-epic material — bugs, open questions, testing
status, todos — for the same fee/discount initiative. It has no frontmatter or
shape classification; items graduate into a numbered epic above once they need
a real parity gate or cross-repo coupling artifact.
