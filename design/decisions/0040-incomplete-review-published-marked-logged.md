# ADR 0040: Incomplete review results are published, marked and logged

- **Status:** Accepted
- **Date:** 2026-10-26
- **Decision authority:** The user's decision on 26 October 2026: "incomplete results
  must be published, but it must be indicated that the results are incompelete, and it
  must also be logged", then "update docs". It refines the same day's "the system should
  not publish without a finding, the key goal of the system is accuracy": a missing
  finding is acceptable only when the output says it is missing.
- **Amends:**
  - [ADR 0023](0023-advisory-post-generation-review.md): incomplete advice must now be
    visible in `spec.md` and, for source review too, in `reference-context.md` ("This
    change adds no source-advice Markdown section" no longer holds for incomplete
    review), and it is logged;
  - [ADR 0039](0039-configured-temperatures-and-runaway-resend.md): an advisory runaway
    on its re-send ends that advice as incomplete instead of failing the run;
  - §17.3–17.4 (advisory review closure), §23 (rendering), §27 and F0002 (the
    `review.incomplete` event), F0100, the [E2E harness](../harness/e2e.md) report and
    the §32 index.

  A proposal of 26 October 2026 to stop publication whenever a finding is missing is
  not adopted. The overall design remains **Proposed design**.

## Context

Post-generation source and principle review is advice (ADR 0023). When a review
assignment can't be completed, ADR 0023 ends that advice as incomplete and the run
still publishes. The stored state records which subjects were not assessed, and why.
But a reader of the published files often can't tell:

- `spec.md` says nothing about review;
- `reference-context.md` shows a one-line note for incomplete principle review, and
  nothing for incomplete source review;
- no log event records that review ended incomplete.

So a specification with missing findings reads like one that was fully reviewed.

## Decision

1. **Incomplete review is still published.** When a post-generation source or principle
   review assignment can't be completed, the run publishes the specification with every
   admitted finding it has. The reasons are ADR 0023's: a provider failure, an exhausted
   protocol correction, genuinely missing usage, and, under ADR 0039, a runaway on its
   re-send (`provider_output_limit`). An unassessed subject is never shown as passed.
2. **The published output says the results are incomplete.** Rendering is deterministic
   from stored state, so identical state renders identical bytes.
   - `spec.md` carries a status line directly under its title when any review is
     incomplete: `**Review status: Incomplete — N of M review subjects were not
     assessed.** See reference-context.md for what was not assessed and why.` N counts
     the unassessed subjects and M all subjects, across source and principle review. A
     fully reviewed specification carries no status line. The `spec.md` reader accepts
     the line only in exactly that form.
   - A clarification pause (ADR 0017) carries none: it stops before post-generation
     review.
   - `reference-context.md` has a `## Review Status` section that lists, for each
     incomplete review (source and principle), its reason and each subject that was not
     assessed, named with the identifiers the file already uses. It replaces the
     existing one-line principle note.
3. **Incomplete review is logged.** When advice closes incomplete, the runner emits one
   warning `review.incomplete`, with the reason as its diagnostic code and the number of
   unassessed subjects as its count. Its logging rejection prevents publication, as for
   every required event.
4. **Reports show it.** The E2E report's `incomplete_reviews` records each incomplete
   review: which review, its reason, its unassessed count and its subject total. Evaluations count incomplete-review runs separately from fully
   reviewed ones.
5. **Unchanged.**
   - Required work that can't complete still fails. What a failed run publishes is
     [ADR 0041](0041-failed-run-incomplete-publication.md)'s rule.
   - A global token-budget failure stays fatal; it never becomes incomplete review.
   - Incomplete advice is never positive evidence, and admitted findings keep their
     original identity.

## Consequences

- **Persistence.** Stored state already holds each incomplete review's reason and
  unassessed subjects, so `specification-state` stays v19. `spec.md` and
  `reference-context.md` change only when a review is incomplete.
- **Rubric.** A reviewer of an incomplete-review run sees the status line. It is a
  status, not specification content.
- **Tests.**
  - Rendering: the `spec.md` status line and the `reference-context.md` section for an
    incomplete source review, an incomplete principle review and both; neither for a
    complete review; byte-identical output for identical state.
  - Logging: one `review.incomplete` per incomplete review, with its reason and count;
    none for a complete review; a logging rejection prevents publication.
  - Report: the E2E report records each incomplete review.
  - Each reason, including a runaway on its re-send, publishes marked output.
