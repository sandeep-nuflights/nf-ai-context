# ADR-003 — First issue is "no previous ticket", not "no `original_issue_info`"

**Status:** Accepted · **Date:** 2026-09-14 · **Epic:** NF-002

## Context

`[Per Tkt Issue]` is `1` when the ticket is a first issue and `0` when it is a
reissue — §6.3 defines first issue as *"Previous Ticket Number does not exist"*.

The obvious implementation, and the one already written down in
`nf-ndc-adapter-rs/docs/rules-engine/orderview-injection-analysis.md:273`, is:

> `1` when `original_issue_info.ticket_number` is **absent** (first issue), else `0`

That reading is IATA-correct — `OriginalIssueInfo` describes the *original* ticket
in an exchange chain, so on a first issue there is no original to point at. It is
also wrong against this platform's own data.

## The defect it would ship

NuFlights' own issuance path writes the ticket's **own** number into
`original_issue_info.ticket_number`:

    backend/inventory/mutations.py:1152    "ticket_number": _nf_ticket_number,     # original_issue_info
    backend/inventory/mutations.py:1162    "ticket_number": _nf_ticket_number,     # ticket[0]

Same variable, both places, at first issue. So on every NF-issued ticket
`original_issue_info.ticket_number` is present, the absence test returns
`0`, and **every `[Per Tkt Issue]` fee is silently dropped** — no error, no log,
an amount of zero that is indistinguishable from "no rule matched".

This is the exact failure mode `rules/context.rs:13` states as law for the Rust
extractor: *"A missing required value is an error, never a zero... revenue
disappears with nothing logged."* Here it is worse, because nothing is missing —
a present field is being read as meaning its opposite.

## Decision

**A ticket is a first issue when `original_issue_info.ticket_number` is absent
**or** equal to this ticket document's own ticket number.**

Anything else is a reissue.

Both halves are required. Absence alone misses every NF-issued ticket; equality
alone misses providers that genuinely omit the field on a first issue, which is
the IATA-correct shape and is what third-party carriers send.

### Which number to compare against, on a conjunction ticket

ADR-002 records that `TicketDocInfoType.ticket` is a `Vec` of 1-4 booklets. The
comparison is against **any booklet's `ticket_number`** — a self-reference to any
part of the same document set means the same thing: this document set is not
pointing at an earlier one.

`TicketType.primary_doc_ind` exists and would let this be narrowed to the lead
booklet. Nothing in either codebase reads it today, and narrowing it without a
real conjunction payload to check against would be guessing at a distinction no
observed data exercises. Left as any-booklet, recorded so the choice is visible.

## Consequences

- Both repos implement the same two-part test. It is cheap and it is the single
  highest-value fixture in `./fixtures` — the NF self-reference case would
  otherwise pass every test written from the IATA reading alone.
- The analysis doc's line 273 is now wrong and must be corrected to point here,
  not left as a second, plausible, incorrect specification.
- Python reads this next to the `issue_date` it already extracts at
  `content_rules.py:6464`, from the same `original_issue_info` node — no new
  navigation.
