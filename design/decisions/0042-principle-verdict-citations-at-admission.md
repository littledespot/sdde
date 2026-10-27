# ADR 0042: Principle verdicts need citations at response admission

- **Status:** Accepted
- **Date:** 2026-10-26
- **Decision authority:** The user's decision on 26 October 2026, "1 yes" and "update
  with recommendations and implement", approving the recommendation to check "a
  `conflicting` or `uncertain` verdict must cite a principle" at response admission and
  to define `uncertain` in the principle prompt.
- **Amends:**
  - [ADR 0023](0023-advisory-post-generation-review.md): an uncited non-compatible
    principle verdict is a typed response-admission defect, corrected with the whole
    response, not a finding-evidence defect for citation-only repair;
  - [ADR 0019](0019-single-request-debugger.md): request descriptions record the new
    constraint, in the same `model-request-debug/v13` as
    [ADR 0039](0039-configured-temperatures-and-runaway-resend.md);
  - §12.2 (native admission constraints), §12.7, §17.3, §22.6, F0100 and the §32 index.
    A principle-prompt line (Decision 4) was tried and withdrawn; the prompt is
    unchanged.

  The overall design remains **Proposed design**.

## Context

The principle rule `citations_required = finding != .supported`
(`principle_assessment.zig`) is checked after the response is admitted; the schema's
`citations` has no minimum. A miss starts an atomic repair that may change only the
citations and must keep the verdict, and the prompt forbids citing an unrelated
principle. When the model had no principle in mind, the only honest repair answer is
`[]`, which is `RepairNoProgress`, terminal under ADR 0023.

On 25 October 2026 loan-renewal failed this way. The title got `uncertain` with no
citations and the detail "The principles do not explicitly address the requirement to
derive a concise name…". In the 33 retained principle-review responses, that is the
only uncited non-compatible verdict among 489 findings (481 `compatible`; 4
`conflicting` and 3 `uncertain`, all cited). The prompt never defines the verdicts.

## Decision

1. **A generic required-items constraint.** The result-schema module gains one native
   admission constraint, beside ADR 0023's `exact_members` and ADR 0038's coverage:
   *when a named property of an object has one of the listed values, a named array
   property of the same object must have at least one item*. It is generic: no
   principle, field or verdict name is compiled into it.
   - The constraint is marked on the array it governs, naming its required sibling
     property. That property is a string; when it is an enum, the listed values must be
     among its allowed values. Restriction rejects an optional or non-array target, an
     empty, duplicate or self-referencing entry, and a second constraint on one array.
   - Response admission rejects a violation as `missing_required_item` at the array's
     exact location, for example `/findings/3/value/citations`, with the explanation
     "Schema validation failed: with the value given for that property, this list needs
     at least one item; add the items the instructions require, or correct that value."
   - Request descriptions record it, so replay enforces the same admission
     (`model-request-debug/v13`, shared with ADR 0039).
2. **Principle review carries it.** Principle-finding packets apply it with the values
   `principle_assessment.rule` requires citations for (`conflicting` and `uncertain`),
   derived from that one rule, so the domain rule stays the single authority. Stored
   readback still applies the domain rule.
3. **A violation takes the whole-response correction.** The principle step's existing
   `retry-limit` bounds it. The model sees the whole finding and may cite the principle
   or correct the verdict. Exhaustion is ADR 0023's advisory protocol exhaustion: the
   review ends incomplete and is published, marked and logged
   ([ADR 0040](0040-incomplete-review-published-marked-logged.md)). Invalid, foreign
   and duplicate citations keep their current native validation and repair.
4. **No prompt line (withdrawn 27 October 2026).** Two wordings of a principle-prompt
   line defining `uncertain` were tried on 26 October. The first stopped the title failure
   but cut citations on `compatible` findings from 481 of 481 to 17 of 76; the second
   brought them back in one run of four, and the principle review then wrote a templated
   "No supplied principle addresses …" for every subject, 20 false statements in one pair.
   False statements are worse than blanket citations, and the admission constraint
   already turns the 25 October failure into a whole-response correction, so the user
   directed on 27 October to revert the line ("apply the follow recommendations"). The
   principle prompt is the pre-ADR text.

## Consequences

- **Limit.** A model may flip a real concern to `compatible` to pass. That loses a true
  finding and is a model limitation to report; review-accuracy measurement (FIX05 B2)
  shows how often it happens.
- **Cost.** The correction replaces the citation repair, so a miss costs about the
  same; admitted responses cost nothing extra.
- **Persistence.** Stored state is unchanged. Retained `v12` descriptions no longer
  decode (ADR 0039).
- **Tests.**
  - The constraint: admitted (a listed value with items, an unlisted value with none),
    rejected at the exact array location, recorded and restored by replay, kept by
    packet clones, and invalid configurations (unknown property, empty value list,
    non-array target) rejected.
  - Principle review: the packet carries the values derived from the domain rule; an
    uncited `uncertain` is corrected once and admitted; repeated, it exhausts the step
    and ends the review incomplete, published and marked; an invalid citation still
    takes its native repair.
