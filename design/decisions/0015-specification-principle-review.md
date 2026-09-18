# ADR 0015: Review project principles during Specify

- **Status:** Accepted design amendment; implementation pending
- **Date:** 2026-09-18
- **Decision authority:** User instruction to update the design and fixes so including
  principles improves Spec outcomes, preserving shared owners and single responsibility
- **Amends:** Design §§9.4, 12.7–12.8, 17, 24.5, 28 and 33, and their linked acceptance criteria

## Decision

Specify includes a focused requirement–principle consistency assessment using the
canonical principle capture/selection/guidance contracts. The assessment detects
conflicts early; principles do not become business-source claims or permission to
change requirements. [§9.4](../contracts/09-configuration.md#94-project-principle-resolution)
owns selection and [§17.3.1](../contracts/17-specify.md#1731-requirementprinciple-consistency-review)
owns the assessment, evidence and handoff to Plan.

Source-preservation review, policy assessment, authority reconciliation and
clarification preparation retain separate responsibilities. Reuse the shared
semantic-request/evidence path; introduce no second principle loader, policy
registry, summary model or reconciliation mechanism.

Clear business intent with a policy conflict produces a mandatory cited Plan
obligation. Genuine uncertainty about business intent remains a Spec clarification.
Plan resolves its policy obligations under current authority before publication;
early detection neither grants policy approval nor creates a Plan form before its
required predecessor/input state exists.

The predecessor gates remain hard requirements: open Spec clarifications prevent
Plan execution; open Spec or Plan clarifications prevent Tasks execution. Deferring
a policy obligation never reclassifies or bypasses an unresolved business question.

The shared [clarification contract](../contracts/12-model-boundary.md#127-workflow-defined-model-operations)
requires actionable questions prepared through existing builders and fields.
Identical wording does not authorize one answer to resolve different subjects.
Multi-subject answer authority and H-011 authentication remain separate decisions.

## Scope and evidence

This supersedes technical-stage-only principle selection for the assessment above;
reference extraction and business-content generation retain reference/validated-answer authority.
The overall design remains **Proposed design**. This amendment does not implement
runtime operations, change project principles, approve a live run or amend the
pending shared-lineage repair decision.

[§28](../contracts/28-testing.md) owns conformance requirements;
[FIX_001 implementation](../../fixes/IMP_001.md#spec-principle-review--approved-design-implementation-pending)
tracks missing bindings, integration, measurements and verification. Better conflict
detection is the intended improvement; fewer clarifications or live success is not
guaranteed.
