# ADR 0015: Review project principles during Specify

- **Status:** Accepted design amendment
- **Date:** 2026-09-18
- **Decision authority:** User instruction to update the design and fixes so including
  principles improves Spec outcomes, preserving shared owners and single responsibility
- **Amends:** Design §§9.4, 12.7–12.8, 17, 24.5 and 28, and their linked acceptance criteria
- **Amended by:** [ADR 0023](0023-advisory-post-generation-review.md): semantic
  principle findings never become mandatory Plan obligations
- **Amended (FIX06 D13.1, 1 November 2026):** by the user's approval to remove both
  post-generation reviews. Spec runs no principle consistency assessment. Principle
  capture and the §9.4 Spec selection row stay: FIX06 D17.1 will give the records
  call the captured principles as context. Principles are context and constraints,
  never a requirement's origin (D13.4), and the workflow never modifies principle
  files.

## Decision

Specify captures the current principle registry and selection through the canonical
principle capture/selection contracts ([§9.4](../contracts/09-configuration.md#94-project-principle-resolution))
and runs no principle assessment. Principles do not become business-source claims
or permission to change requirements. Capturing principle files is not performing an
assessment: state and evidence distinguish captured inputs from any executed
assessment. Native principle capture, selection and currentness checks remain
mandatory; Plan validates current policy under its own required authority. This
grants no content-repair, upstream-rebuild or model-selection permission, and the
workflow never modifies principle files.

The predecessor gates remain hard requirements: open Spec clarifications prevent
Plan execution; open Spec or Plan clarifications prevent Tasks execution. Deferring
a policy obligation never reclassifies or bypasses an unresolved business question.

The shared [clarification contract](../contracts/12-model-boundary.md#127-workflow-defined-model-operations)
requires actionable questions prepared through existing builders and fields.
Identical wording does not authorize one answer to resolve different subjects.
Multi-subject answer authority and answer authentication (FIX05 R2) remain
separate decisions.

## Selection-policy input amendment — 18 September 2026

**Explicitly approved** by the user, 18 September 2026. This amends §9.1 and F0001's closed config
shape: one optional `principles` section in the existing `.sddtoolkit.json` owns
`filenameHints` and `selections`. No separate policy file or registry owns a copy.

Filename hints use exact normalized Markdown basenames; unmatched names remain
`custom`. Closed selection rows contain `stage`, `environment`, `fileKind` and
`categories`; null environment/file-kind explicitly includes every matching scope.
Matching rows contribute their category union. Each row includes `core` and `custom`.
Spec capture requires its explicit unrestricted Spec row. Missing applicable
selection authority rejects; unrelated workflows may omit the section.

The config reader owns structure; the principle-policy compiler owns semantic
validation. Workflow definitions select registered operations and model resources.
This does not amend the separate lineage-repair or answer-authentication decisions.

## Scope and evidence

This supersedes technical-stage-only principle selection for the Spec capture above;
reference extraction and business-content generation retain reference/validated-answer
authority. This amendment does not change project principles or approve a live run.
[§28](../contracts/28-testing.md) owns conformance requirements.
