# ADR 0015: Capture project principles during Specify

- **Status:** Accepted design amendment
- **Date:** 2026-09-18
- **Decision authority:** User instruction to update the design and fixes so including
  principles improves Spec outcomes, preserving shared owners and single responsibility
- **Amends:** Design §§9.4, 12.7–12.8, 17, 24.5 and 28, and their linked acceptance criteria
- **Amended by:** [ADR 0023](0023-advisory-post-generation-review.md): semantic
  principle findings never become mandatory Plan obligations
- **Amended (FIX06 D13.1, 1 November 2026):** by the user's approval to remove both
  post-generation reviews. Spec runs no principle consistency assessment. Principle
  capture stays: FIX06 D17.1 will give the records call the captured principles as
  context. Principles are context and constraints, never a requirement's origin
  (D13.4), and the workflow never modifies principle files. Retitled 7 November 2026
  from "Review project principles during Specify" to match.
- **Amended (FIX06 E10, 8 November 2026):** by the user's decision that unused code
  with no value is removed ("if it unused and brings no value then remove it"), after
  the registry's selection and guidance functions had no reader. The optional
  `principles` configuration section (filename category hints and selection rows), its
  policy compiler, `Registry.policy`, `Source.category` and the Spec selection row are
  removed. Capture needs no configuration, Spec captures every principle file
  (D17.1), and `specification-state` advances to v22. A later stage that filters
  principles needs its own decision ([ADR 0034](0034-spec-quality-gate.md)). Retitled to
  match.

## Decision

Specify captures the current principle registry through the canonical principle
capture contract ([§9.4](../contracts/09-configuration.md#94-project-principle-resolution))
and runs no principle assessment. Principles do not become business-source claims
or permission to change requirements. Capturing principle files is not performing an
assessment: state and evidence distinguish captured inputs from any executed
assessment. Native principle capture and currentness checks remain mandatory; Plan
validates current policy under its own required authority. This
grants no content-repair, upstream-rebuild or model-selection permission, and the
workflow never modifies principle files.

The predecessor gates remain hard requirements: open Spec clarifications prevent
Plan execution; open Spec or Plan clarifications prevent Tasks execution. Deferring
a policy obligation never reclassifies or bypasses an unresolved business question.

The shared [clarification contract](../contracts/12-model-boundary.md#127-workflow-defined-model-operations)
requires actionable questions prepared through existing builders and fields.
Identical wording does not authorize one answer to resolve different subjects.
Multi-subject answer authority and answer authentication
([ADR 0025](0025-clarification-answer-authentication.md)) are separate decisions.

## Selection-policy input amendment — withdrawn 8 November 2026

The 18 September 2026 amendment, an optional `principles` section in
`.sddtoolkit.json` owning `filenameHints` and `selections` with an explicit Spec row,
is withdrawn with the section. A `principles` member now rejects as an unknown
configuration member, with no compatibility reader. This does not amend the separate
lineage-repair or answer-authentication decisions.

## Scope and evidence

Reference extraction and business-content generation retain reference/validated-answer
authority. This amendment does not change project principles or approve a live run.
[§28](../contracts/28-testing.md) owns conformance requirements.
