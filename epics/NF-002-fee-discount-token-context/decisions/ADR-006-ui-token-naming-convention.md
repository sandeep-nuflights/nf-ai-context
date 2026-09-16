# ADR-006 — One display-name convention for these tokens across every admin UI

**Status:** Accepted · **Date:** 2026-09-14 · **Epic:** NF-002

## Context

ADR-001 shipped six new context keys but explicitly flagged, under Consequences,
that it made no UI change: *"the editor takes free-form context — but an
unadvertised token is an unused token."* That prediction landed exactly as
written, on the first real ruleset authored against these tokens.

An agency admin created a service-fee ruleset (`AdditionalContextVars`,
`org=T-EK`, `ruleset_id=851822da-5ba2-4571-a1b9-5fb90bac8e82`) intending
`per_segment * 10`. The formula as authored read:

    Persegment*10

Investigation (`nf-ndc-connect-rules-engine` source, `service/src/merge/null_default.rs`,
`service/src/evaluate/handler.rs:1155`, `zen-expression` VM) established two facts
that were not previously documented anywhere in this epic:

1. **There is no bracket-token normalization layer anywhere in the BRE runtime.**
   `[Base Fare]`, `[Per Segment]`, etc. exist only as human-readable names in
   `nf-bre-requirements-summary.md`. The rules engine never parses `[...]`,
   never lowercases, never replaces spaces with underscores. A rule author must
   type the **exact, literal, case-sensitive context key** — `base_fare`,
   `per_segment` — directly into the formula. There is nothing to "get right"
   automatically; naming is entirely a human-authoring convention, enforced by
   nothing at runtime.
2. **A decision-table output cell defaults a missing/mismatched identifier to
   `0`, silently, by design** (`null_default.rs`'s `wrap_missing_as_zero`,
   rewriting every free identifier `X` to `(X==null?0:X)` — deliberately, so a
   context field that is legitimately absent for some transaction shape doesn't
   hard-fail the rule). A **misspelled** identifier is indistinguishable from a
   **legitimately absent** one to this mechanism. `Persegment` (missing
   underscore, wrong case) resolved to `Null`, was defaulted to `0`, and
   `0 * 10` produced a plausible, silent `0` — never an error. (A standalone
   expression node outside a decision-table output cell would instead have
   hard-errored on `Multiply(Null, Number)` — this masking is specific to
   decision-table output cells, which is exactly where these fee/discount
   rulesets live.)

This is precisely the class of failure `nf-ndc-adapter-rs`'s own extraction code
was built to make impossible on the *adapter* side (`specs/012-fee-discount-tokens`
FR-010: "never a fabricated zero") — and it happened one layer further out, in
ruleset authoring, exactly where ADR-001 said the risk remained.

Two admin applications sit in the authoring path, and the exact mechanism by
which the typo reached production was traced precisely (not inferred):

- **`nf-app-home`** (`src/routes/rules/metadata/OutputColumnConfig.tsx`),
  platform admin, `rules/Agency/` — defines which variables a rule
  **template**'s output columns may reference (`allowedVariables`, saved into
  the column's `nfCell` metadata). Its "Additional variables" box is
  **free text, validated only against identifier syntax**
  (`VARIABLE_NAME_RE = /^[a-zA-Z_][a-zA-Z0-9_]*$/`) — nothing checks a typed
  name against the actual set of keys `nf_ndc` populates. This is where
  `Persegment` was typed and accepted: syntactically a valid identifier,
  silently wrong. It became a real, saved entry in that output column's
  `allowedVariables`.
- **`nf-app-account`** (`src/components/RuleEditor/`),
  `/business-rules/:orgShortCode/:rulesetId/:version` — inherits that
  `allowedVariables` list (embedded in the template's merged JDM graph, not a
  separate fetch) and **does** validate: `codecs/expression.ts`'s
  `disallowedIdentifiers`/`parseEquation` tokenizes the formula and rejects any
  bare identifier outside the allow-list. This validation worked exactly as
  designed — it found no problem, because `Persegment` was *already* a valid
  entry on the allow-list it was checking against. The poison entered one
  repo upstream; the downstream check correctly trusted it.
- A separate display layer in `nf-app-account`
  (`widgets/expressionDisplay.ts`'s `humanizeField`) converts between the
  raw stored identifier and a bracket-wrapped human label for the formula
  editor (`base_fare` ↔ `[Base fare]`) — but this only relabels names *already
  on* `allowedVariables`; it has no bearing on how a name gets onto that list
  in the first place, and does not itself normalize or validate anything.

So: this was not a bracket-parsing bug and not a validation bug in
`nf-app-account` — `nf-app-account`'s allow-list check is sound. It was a
missing suggestion/verification step in `nf-app-home`'s free-text box, one
level further upstream than either of those two systems.

## Decision

**Two separate naming conventions, kept explicitly distinct, never conflated:**

1. **Context variable (wire key) — unchanged, snake_case, per ADR-001.** This is
   what actually goes in the JSON context and what a formula's `FetchEnv` must
   match character-for-character:

       segment_count   unflown_segment_count   per_segment
       per_ticket      per_tkt_issue           total_fare

2. **Display/authoring name — PascalCase, no spaces, no abbreviation — standard
   across every application surface that shows these tokens to a human**
   (`nf-app-home`'s template builder, `nf-app-account`'s ruleset editor, and any
   future UI): apply the same PascalCase-no-space rule uniformly across all six,
   consistent with the three the decision was made against directly:

       SegmentCount   UnflownSegmentCount   PerSegment
       PerTicket      PerTicketIssue        TotalFare

   Note `PerTicketIssue` spells "Ticket" and "Issue" in full — it does **not**
   mirror the wire key's `tkt` abbreviation. The display name and the wire key
   are two independent strings, connected only by whichever UI/config maps one
   to the other (see Consequences) — never by a runtime transformation, per the
   Context section above. Neither `[Base Fare]`-style bracket notation nor a
   bare `per Segment` (space, no case convention) is used in any UI going
   forward; existing documentation using bracket notation
   (`nf-bre-requirements-summary.md` §6.2–6.3) describes the token
   *vocabulary*, not literal syntax, and is not itself changed by this ADR.

## Consequences

**Shipped (code):**

- **`nf-app-home`** — `OutputColumnConfig.tsx` gained one array,
  `ALWAYS_AVAILABLE_TOKENS`, listing exactly nine names: the six NF-002 tokens
  plus `base_fare`, `yq`, `yr`. These are unconditionally merged into every
  output column's `availableVariables`, on every template, with no
  per-template "Additional variables" step required — closing the actual gap
  (an admin had nothing to pick from, so free-typed `Persegment`) and a related
  regression found while fixing it (`base_fare`/`yq`/`yr` had been *opt-in*
  only, backed by nothing but one column's own saved data, so unchecking them
  and saving silently deleted them from the picker with no way back except
  re-typing from memory). Deliberately scoped to just these nine, not a
  broader "every known nf_ndc key" catalog — a `<datalist>` autocomplete
  suggestion covering a wider set of stable context keys (`airline_code`,
  `transaction_type`, etc.) was tried and reverted: it doesn't solve the actual
  problem (a datalist only helps someone already typing) and adds keys nobody
  asked this editor to surface.
  - **Tagging: these nine are untagged, exactly like a real input-column
    field — never `custom`.** The `custom` badge is reserved strictly for a
    name typed into "Additional variables" that isn't one of these nine and
    isn't an input column: `!inputFieldSet.has(field) &&
    !ALWAYS_AVAILABLE_TOKENS.includes(field)`. An earlier pass introduced a
    third `builtin` label for these nine instead of leaving them untagged —
    reverted at explicit request; a real nf_ndc-guaranteed key reads better as
    "just there, like an input column" than as a second badge to explain.
  - Test coverage added directly: `OutputColumnConfig.test.tsx` asserts all
    nine appear with zero input columns and nothing manually typed, carry no
    `custom` tag (including the `base_fare`/`yq`/`yr` regression case by
    name), and that a genuinely ad-hoc typed name still gets tagged `custom` —
    the distinction survives, it's just expressed as tagged-vs-untagged rather
    than two different tag words. Two pre-existing tests that assumed "exactly
    one checkbox"/"exactly one tag in this row" were corrected to scope to the
    specific variable's own label, since that assumption is now false by
    design (nine variables are always present).
- **`nf-app-account`** — `expressionDisplay.ts`'s `humanizeField` gained an
  explicit `DISPLAY_NAME_OVERRIDES` map for the six tokens, so once one is
  actually on a template's `allowedVariables`, the editor's chip/insert label
  reads `PerSegment`/`PerTicketIssue`/etc. exactly as decided above — not the
  algorithm's own generic output (`Per segment`), which for `per_tkt_issue`
  specifically has no way to expand `tkt` to `Ticket` at all. Existing tokens'
  display (`base_fare` → `Base fare`, `yq` → `YQ`) is untouched — only these
  six are overridden.

**Still open — content/configuration, not code:**

- The already-live `AdditionalContextVars` ruleset (`851822da-...`) still
  needs two manual corrections, neither automatic: (1) on the template side
  in `nf-app-home`, check the now-always-available `per_segment` checkbox for
  that output column and save (the old misspelled `Persegment` entry stays on
  the allow-list too unless separately removed — harmless, just untidy); (2)
  on the ruleset side in `nf-app-account`, fix the formula text itself from
  `Persegment*10` to `per_segment*10`. The code change in this ADR makes the
  correct variable available to pick; it does not touch either existing
  record.
- This ADR does not change anything in `nf-ndc-adapter-rs` or
  `nf-ndc-adapter-generic` — the context keys and their derivation
  (`specs/012-fee-discount-tokens`) are unaffected. It also does not change
  `nf-ndc-connect-rules-engine`'s runtime — the null-default-to-zero behavior
  for decision-table output cells (`null_default.rs`) is confirmed intentional
  (survives a legitimately-absent field) and its own allow-list check
  (`codecs/expression.ts`) was already working correctly; neither is altered.
- A future audit should confirm the existing tokens already advertised
  anywhere in these two UIs (`BaseFare`, `YQ`, `YR`, in the legacy, unrelated
  MasterRulesets/`subAgencies` formula feature in `nf-app-account`, sourced
  from a Django-generated `CHOICES.js`) follow this same PascalCase
  convention or are migrated to it — out of scope for this ADR to execute,
  recorded here so the inconsistency isn't rediscovered as new. Note that
  legacy feature already uses `[BaseFare]`/`[PerSegment]`/`[PerTicket]`
  PascalCase-in-brackets today; it is a separate system from the
  `/business-rules` BRE editor this ADR addresses and the two are not wired
  together.
