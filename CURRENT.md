# Current focus

**A pointer, not a record.** Detail lives in the epic docs; this file only says
where work currently stands so a new session can pick up without rereading
everything. Keep it short — a long one stops getting maintained.

**Update it at the end of any session that moves the work.**

---

**Active program:** [NF-003 — BRE fee/discount migration](epics/NF-003-bre-fee-discount-migration/epic.md)
**Active sub-epic:** none. NF-001 is complete in both adapters; NF-002 is
Rust-complete and Python-unstarted (no leaf spec in `nf-ndc-adapter-generic`).

**Last updated:** 2026-09-16

## Where we are

Cross-repo research pass completed over all six leaf repos — surface ownership,
management plane, BRE contract, and per-repo spec status are mapped in NF-003's
`impact-map.md`. Scope decisions **D1–D4** are settled; **G1** (Kyte) is resolved
in principle but rests on an unconfirmed premise (see below).

The hub itself was set up this session: `CLAUDE.md`, `stale-sources.md`,
`pending-confirmation.md`, the program/sub-epic two-tier model, and git init.

**Not yet started:** any leaf spec for NF-003. Nothing has been written to a leaf
repo.

## Next step

**The next move is Sandeep's** — the hub is set up and every open thread needs
his input. See below.

When D4's details arrive, the work is its cross-repo shape: `transaction_type` as
a rule-template column, and what it touches across all six repos.

## Waiting on Sandeep

- **D4 detailed design** — the `transaction_type` template column
  (enum `SALE` / `VOID` / `REFUND`). The keystone: it unblocks cancellation and
  reshop, and touches every repo.
- **P1 in `pending-confirmation.md`** — is the Kyte fast path OrderCreate or
  OrderRetrieve? Changes NF-003 §G1 and whether Kyte needs a persistence path.
- The other four items in `pending-confirmation.md`.
- **Glossary** — Sandeep will supply the domain terms directly rather than
  answering a generated question list. Record as `glossary.md` when it arrives.
  Until then, treat domain semantics as a known blind spot: Claude can say what a
  change *breaks*, but not reliably what it *should be*.

## Standing context

- **The leaf repos carry large amounts of uncommitted work** — the BRE
  implementation exists mostly in working trees, and `nf-ndc-adapter-rs` has no
  feature branch at all. Sandeep is aware and committing after review. Until
  then, treat every snapshot in this repo as dated and re-verify before acting.
- Leaf `specs/` directories are currently gitignored in several repos. Sandeep
  has said these will be brought into git, which step 6 of the working agreement
  depends on.
