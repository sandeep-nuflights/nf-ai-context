# Stale sources — files that will mislead you

Checked-in documents across the leaf repos that are **wrong, outdated, or say
less than they appear to**. Each entry says what it claims, what is actually
true, and where the truth lives.

Read this before building anything from a leaf repo's own spec or contract.

> **Adding an entry:** only when you have verified the divergence against code.
> Give the claim, the reality, and the authoritative source. Date it. Remove the
> entry when the source is fixed — do not leave a correction standing after the
> thing it corrects is gone.

---

## `nf-ndc-connect-rules-engine/service/openapi/bre-v1.yaml`

*Verified 2026-09-16.* **The most dangerous file in the epic** — it is the only
thing that looks like an authoritative contract for the interface every other
repo depends on, and it is wrong in both path and payload.

| | Claims | Reality |
|---|---|---|
| Path | `POST /v1/evaluate` | `POST /v1/rules/evaluate` |
| Request | `{rule_type, tenant_id, effective_on, version, context}` | `ruleVersions[]` **XOR** `ruleTypeLookups[]`, plus `context`, optional `reference` |
| Response | `{result, trace, rule_version, performance}` | `{timingsMs, results[]}` per-item |

It documents the Feature-006 single-item shape, superseded by Features 010, 014
and 015. **Authoritative source: `service/src/evaluate/handler.rs:73-90`** for the
request, `:178-193` for the item result. See `contracts/bre-evaluate.md` in this
repo if present.

## Every leaf spec's `Status:` frontmatter field

*Verified 2026-09-16.* Across `nf-ndc-adapter-generic` and others, specs carry
**`Status: Draft`** while holding 90%+ complete task lists and live, shipped
code. The field was never maintained.

**Judge completion from the task checklist and the code, never from `Status`.**

## `epics/NF-001/impact-map.md` and `epics/NF-002/impact-map.md` — adopter checklists

*Verified 2026-09-16.* Both list **unticked** boxes for `nf-ndc-adapter-rs` work
that is **done and tested**:

- NF-001: `reduce_across_sub_types` is already deleted; `reduce_across_contexts`
  (`evaluate.rs:259`) already has the split direction and cites ADR-002 by name.
  Tests exist. Spec 011 is 21/21.
- NF-002: all six tokens are already inserted in `build_shared`
  (`context.rs:158-163`, `quote_context.rs:409-414`) — correctly placed, not the
  per-pair arm. Spec 012 is 21/21.

These need a sweep. Until then, **do not read an unticked box in either file as
work outstanding** without checking the code.

## `repos.md` — surface ownership table, pre-2026-09-16 version

The version in git history claimed Python owned OrderCreate/Change/Retrieve
outright and that Rust's injection was "being removed per FR-013". Neither was
verified against Rust, where that injection is present, tested, and merely
flag-gated. It also recorded OrderReshop as adapter-rs owned when it is a stub on
that side.

**The current table is corrected.** Flagged here only because the old shape may
persist in anyone's memory or in a leaf repo quoting it.

## `nf-ndc-adapter-generic` — legacy `available_master_rule()` path

*Verified 2026-09-16.* Not a document, but the same trap: the code **reads as a
working rule engine** and is structurally dead. It filters `OrgMasterRuleSet` by
ids that spec 004 repointed at `bre_rule_set`, so the match is always empty; every
call site guards with `if master_rules:` and skips the block silently.

Its legacy **authoring** surface (admin, GraphQL mutations) is still live and
writable. Rules authored there can never fire.

## Anything in this repo describing code state

Per CLAUDE.md's rot rule: the leaf repos carry large amounts of uncommitted work,
so every line number, task count and "what exists today" table here is a dated
snapshot. `impact-map.md` files are the main ones.

**Re-verify before acting.** `git status` in the touched repo, then read the site.

## `nf-ndc-adapter-generic/backend/ndc/content_rules.py:60-87` — the module docstring on repricing

**Contradicts a confirmed invariant.** It states that "a retrieve of a ticketed
order WILL rewrite the recorded amounts if the provider's base fare has moved.
That is the documented intent, not an oversight", and records that a
freeze-at-ticketing boundary was proposed and reverted (006 Q2/FR-014).

NF-003 **I1** — confirmed by Sandeep 2026-09-23 — says a ticket document's price
does not change after issuing; a change is carried by a new document.

Both can be literally true: the code permits a rewrite, the data never supplies
one. But the docstring reads as a statement about the *domain*, and on that
reading it is wrong. It was cited as evidence against I1 while I1 was parked as
P9. **Do not treat it as a domain fact.** The reverted 006 Q2/FR-014 freeze
proposal is worth revisiting in that light.
