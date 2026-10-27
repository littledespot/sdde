# ADR 0045: Entity meaning and relationships show exact values as code spans

- **Status:** Accepted
- **Date:** 2026-10-27
- **Decision authority:** The user's direction on 27 October 2026, "updated the
  documentation inline with option 1", choosing [FIX05](../../fixes/Z_FIX05.md#21-fix05-retired--28-october-2026) B12's
  option 1: make entity meaning and relationship "**incidental** (rendered as code spans
  through the shared owner, no coverage credit)", instead of keeping the model's
  backticks in prohibited fields.
- **Amends:**
  - [text-field composition](../contracts/text-field-composition.md) (§§7.1, 17.3, 22),
    the field inventory;
  - [ADR 0020](0020-derived-exact-reference-lineage.md)'s 16 October "no exact copies in
    descriptive fields", for these two fields;
  - [ADR 0036](0036-source-quoted-claims.md) Decision 6's effect on them;
  - the §32 index.

  The overall design remains **Proposed design**.

## Context

Entity meaning and each relationship have a prohibited exact-copy role. ADR 0036
Decision 6 removes the model's code delimiters around a recognised exact value, and in a
prohibited field the value stays prose. Loan-renewal's model wrote `` `Renewal refused.` ``
in the entity meaning, and the published text reads "…and the system displays Renewal
refused..". The reader can't see where the message ends, and its full stop runs into the
sentence's. Advisory evaluations flagged it in three of the last four loan-renewal runs
(26 October 08:09 and 10:23, 27 October 05:06). The same value renders as a code span in
the functional requirement, acceptance criterion and outcome.

## Decision

1. **Entity meaning and each relationship take the incidental exact-copy role**, the
   entity name's role. Native recognition turns a current eligible occurrence into an
   exact copy, so ADR 0036 Decision 6 removes its delimiters and the shared renderer shows
   it as a code span. Both fields still require prose.
2. **No coverage credit.** As with the entity name, the occurrence keeps its lineage and
   rendering but never satisfies behavioral exact-copy coverage; only obligation-bearing
   fields do.
3. **One policy owner.** Generation, admission, protocol correction, every repair route
   and stored readback take the role from the existing field policy, which stops rejecting
   an exact copy in these fields as a prohibited insertion. Model-facing schemas and
   prompts don't change: models already type exact values verbatim, and no model-facing
   schema admits `exact_copy` (ADR 0020).
4. **The other descriptive fields stay prohibited:** brief title and goal,
   entity-applicability basis, assumption and clarification question.

## Consequences

- **Effect: readability only.** Requirement preservation, unsupported additions, review,
  repair and cost don't change; the values already survive in obligation-bearing fields.
  The value's own full stop still sits beside the sentence's ("displays
  `Renewal refused.`."), as in functional requirements and acceptance criteria, but the
  code span shows where the value ends.
- **Lineage.** An occurrence adds its claim to the entity's exact lineage (ADR 0020's
  `E`); that is not a new semantic association.
- **ADR 0044.** Its marker check never reads exact-value segments, so text inside a
  recognised value in these fields is no longer read.
- **Persistence.** The segment representation and contract versions don't change; stored
  readback accepts exact copies in these fields. Earlier stored states get no
  compatibility reader (ADR 0020).
- **Tests.**
  - Accepted: an entity meaning and a relationship with a delimited eligible value store
    an exact copy, render a code span and read back; a field without one is unchanged.
  - Rejected: such an occurrence never satisfies coverage; the brief title and goal,
    applicability basis, assumption and clarification question still keep the value as
    prose; overlap and competing identities still reject the field.
