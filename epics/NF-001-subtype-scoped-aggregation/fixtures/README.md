# NF-001 parity fixtures

These are **adapter-level** fixtures, not BRE fixtures. They do not follow the
`templateJdm` / `ruleSetSlotData` shape of
`nf-ndc-connect-rules-engine/fixtures/master-corpus/` — that corpus exercises ZEN
evaluation, which this epic does not touch.

What these exercise is the reduction that happens **after** the BRE has answered:
given a set of per-`(ruleset, context)` amounts, what does one chain level yield?
That logic is duplicated in Rust (`rules/evaluate.rs`) and Python
(`ndc/content_rules.py`), so it is stated once here and asserted in both.

Deliberately left in place rather than merged into `master-corpus`: that corpus is
referenced by relative path from 15 files across `conftest.py`, `tests/common/mod.rs`,
`test_parity.rs` and two bench harnesses. Moving it is its own piece of work and is
not a prerequisite for this epic.

## Shape

```jsonc
{
  "testLabel": "...",
  "given":  { "contexts": [...], "outcomes": [ {ruleType, subType, ruleset, context, amount} ] },
  "expectBefore": { ... },   // the pre-NF-001 answer, for reviewable deltas
  "expect":       { "winners": [...], "serviceFeeTotal": n, "discountTotal": n }
}
```

`expectBefore` is carried so the money delta is reviewable rather than discovered.
It is documentation, not an assertion — do not wire it into either test suite.

## Running

Both repos read these from the epic folder. Neither merges alone: the gate is
identical results across implementations, 0 discrepancies.

| Fixture | Asserts |
|---|---|
| `nf001-01` | ServiceFee: one winner per sub-type, min within each, summed |
| `nf001-02` | Discount: one winner per sub-type, max within each, summed |
| `nf001-03` | Fan-out direction (ADR-002) — **rs only**; Python has no fan-out axis (verified) |
| `nf001-04` | Ties across rulesets inside one slot (Q5 stays accepted) |
| `nf001-05` | Reference order — the 1855 -> 1827 delta. **Data not yet filled in.** |
