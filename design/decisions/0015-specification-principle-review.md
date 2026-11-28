# ADR 0015: Capture project principles during Specify

- **Status:** Accepted
- **Date:** 2026-09-18
- **Decision authority:** User decisions, 18 September, 1 November and 8 November 2026
- **Amends:** Design §§9.4, 12.7–12.8, 17, 24.5 and 28
- **Amended by:** [ADR 0023](0023-advisory-post-generation-review.md)

## Decision

- Specify captures the current principle registry through the canonical principle capture
  contract ([§9.4](../contracts/09-configuration.md#94-project-principle-resolution)). It
  captures every principle file, and capture needs no configuration: a `principles` member in
  `.sddtoolkit.json` rejects as an unknown configuration member, with no compatibility reader.
- Spec runs no principle assessment. Capturing principle files is not performing an
  assessment: state and evidence distinguish captured inputs from any executed assessment.
- Only the records generation request carries the captured principles, as context, each
  file's text unnumbered ([17-specify.md](../contracts/17-specify.md) owns the request).
  Principles are context and constraints. They never become business-source claims, a
  requirement's origin or permission to change requirements.
- Native principle capture and currentness checks remain mandatory. Plan validates current
  policy under its own required authority.
- This grants no content-repair, upstream-rebuild or model-selection permission, and the
  workflow never modifies principle files.
- The shared
  [clarification contract](../contracts/12-model-boundary.md#127-workflow-defined-model-operations)
  requires actionable questions prepared through existing builders and fields. Identical
  wording does not authorize one answer to resolve different subjects.
- A later stage that filters principles needs its own decision
  ([ADR 0034](0034-spec-quality-gate.md)).
