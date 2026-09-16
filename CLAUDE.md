# nf-ai-context — working instructions

Cross-repo coordination hub for NuFlights. **This repo holds no application code.**
It holds what spans repos: epic requirements, cross-repo impact, decisions, and
parity fixtures. Each leaf repo keeps its own spec-kit and its own
`specs/NNN-slug/`.

This is a **multi-epic** hub. More than one epic can be in flight. Never assume
the epic you last read about is the one being asked about.

## Orient yourself first

Read in this order. Stop when you have what the task needs.

0. **`CURRENT.md`** — which program and sub-epic are active, where the work
   stands, what is waiting on the user. Always read this first; it is what makes
   a cold session resumable. **Update it at the end of any session that moves the
   work** — that upkeep is part of the job, not optional.
1. `README.md` — epic shapes, conventions, the epic index.
2. `repos.md` — the repo map, dependency shape, surface ownership. **Corrected
   against working trees; trust it over any leaf repo's own account.**
3. `stale-sources.md` — **files that will actively mislead you.** Read before
   building anything from a checked-in spec or contract.
4. `epics/NF-NNN-slug/epic.md` — the epic in question, then its `impact-map.md`.
   If it is a sub-epic, read its **program** first; if it is a program, its
   sub-epics carry the detail.
5. `pending-confirmation.md` — findings that would change the architecture if
   true but are **not yet confirmed**. Never treat one as fact.

If the user names no epic, ask which one rather than guessing. The epic index in
`README.md` is the list.

## Programs and sub-epics

Two tiers, one numbering sequence:

- A **program** spans a whole initiative and contains sub-epics. It carries the
  scope decisions and the cross-repo code-site index.
- A **sub-epic** is a single coupled change with its own parity gate and its own
  leaf specs.

Both live flat in `epics/NF-NNN-slug/` and both use `epic/NF-NNN-slug` as their
branch name. The relationship is declared in frontmatter — `contains:` on the
program, `parent:` on the sub-epic — **not** by directory nesting or number
order. Numbers are IDs, not a hierarchy: NF-003 is the parent of NF-001 and
NF-002 because those were numbered first.

**Collision risk lives between programs, not within them.** Sub-epics of one
program share a domain and are expected to touch the same files. Two *programs*
touching the same file is the real hazard — so when planning a new program, check
its code sites against every other live program's impact map before designing.

## Two migrations — do not conflate them

1. **Stack migration** — Django (`nf-ndc-adapter-generic`) → Rust
   (`nf-ndc-adapter-rs`). Surface by surface. This is why requests flow
   **Rust → Python proxied**, and why a given surface lives where it does.
2. **BRE fee/discount migration** ([NF-003](epics/NF-003-bre-fee-discount-migration/epic.md)) —
   legacy if-else + `OrgMasterRuleSet` → GoRules ZEN decision tables.

They overlap: the BRE epic inherits its surface-ownership split from the stack
migration. State which one you mean; never let "the migration" go unqualified.

## Durable vs snapshot — the rot rule

The leaf repos carry large amounts of **uncommitted** work. Anything here about
code state is a dated snapshot, not ground truth.

- **Durable** — decisions and their reasons, conventions, domain semantics,
  contracts, stale-source warnings. Trust these.
- **Snapshot** — line numbers, spec completion counts, what is committed, "what
  exists today" tables. Carry a date. **Re-verify before acting on them.**

Re-verification is cheap: `git status` in the touched repo, then read the actual
sites. Do it before any change, every time. Do not act on a snapshot's line
numbers without opening the file.

## Working agreement

The order of work, set by the user:

1. User describes a change here in terms of **output / expectation**.
2. Claude checks for **ambiguities** and resolves them with the user before
   designing anything.
3. Claude produces the **cross-repo plan** here — affected repos, code sites,
   blast radius, exclusions, open questions — in the `epics/` format.
4. User **approves**.
5. Implementation happens in each leaf repo via **spec-kit**, as that repo's own
   `specs/NNN-slug/`.
6. Status flows **back up** to this repo, so the hub knows where the epic stands.

Do not jump to editing leaf-repo code from a hub conversation. Plan first.

## Hard rules

- **Never patch a shared contract inside a leaf repo.** Contract changes come
  back here. This is the repo's founding rule.
- **Architectural facts need the user's explicit confirmation.** If research
  suggests the architecture differs from what is recorded, raise it and ask —
  do not rewrite the record unilaterally. Park it in `pending-confirmation.md`
  meanwhile, and delete the entry once the fact moves to its proper home.
- **Do not edit `backlog.md`.** Read it for context; route anything it raises
  into the relevant epic instead. The user maintains it.
- **Per-repo spec numbering is uncorrelated by design.** The `epic:` frontmatter
  key is the join, not the number.
- **One branch name across every repo in an epic:** `epic/NF-NNN-slug`.
- **Never state a money figure, salary, or commercial amount** found in code or
  data. Route pricing and contract questions to sales, and anything about
  employee performance or compensation to HR.

## Multi-repo orchestration

The leaf repos are expected as siblings of this one:

`nf-ndc-connect-rules-engine` · `nf-ndc-adapter-rs` · `nf-ndc-adapter-generic` ·
`nf-app-home` · `nf-app-home-v2` · `nf-app-account` · `nf-app-workbench`

**First-time setup:** they must be registered as `permissions.additionalDirectories`
in `.claude/settings.local.json` (gitignored — the paths are absolute and
machine-specific, so everyone keeps their own). Without it, reading a leaf repo
prompts on every file. Shape:

```json
{ "permissions": { "additionalDirectories": ["/abs/path/to/nf-ndc-adapter-rs", "..."] } }
```

**Researching across repos:** spawn one agent per repo, in parallel, in a single
message. Use fresh `general-purpose` agents with `model: "sonnet"` — research is
Sonnet work; synthesis stays with the main session. A **fork inherits the parent
model and silently ignores a `model` override**, so forks are the wrong tool when
the point is to run cheaper. Brief each agent fully: repo path, branch, the epic,
what to report, what other agents are covering, and a word limit.

**Before acting on any research:** re-verify. See the rot rule.

## House style

Impact maps and epics in this repo are dense and anchored — `file.rs:123`
references over prose, tables over paragraphs, explicit exclusions with reasons
so a gap is never misread as drift. Match it. Record **why** a decision was made,
not just what, so a later session can judge edge cases instead of guessing.
