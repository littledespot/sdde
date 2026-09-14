# F0050 — SpecWorkflowEvaluationService

**Status:** Development harness implemented; human calibration and broader live
acceptance remain tracked in the [harness backlog](../harness/README.md).
**Reviewed:** 2026-09-11. The governing engine design remains Proposed.

## Responsibility

The requested E2E outcome is to run the ordinary Spec workflow using the real
LLM configured in the selected test's `.sddtoolkit.json`, then grade that
execution's actual published specification against its rubric through the
selected live evaluator. Semantic quality assessment is part of this outcome.

## Implementation and interfaces

The implementation is under `test/harness/` with development-only build entry
points. It creates an isolated test project from declared resources, preserves
captured source/configuration/rubric inputs, invokes production workflow and
provider adapters, verifies publication identity, and reports generation,
publication and rubric results separately. It uses neither scripted generation
nor a prewritten specification as E2E evidence.

See [E2E usage and contracts](../harness/e2e.md) and the
[supplied-spec evaluator](../harness/evaluator.md) for implemented commands,
configuration, report interpretation and failure behavior. The supplied-spec
entry point does not run the engine and cannot establish generation success.
Mechanical tests use fakes only to validate their individual boundaries.

## Authority boundary

[F0100](F0100-SpecWorkflow.md) owns production Specify behavior. Rubric judgments
remain semantic observations; they do not approve workflow transitions,
publish candidates, resolve clarification forms or weaken deterministic gates.
[ADR 0009](../decisions/0009-atomic-workflow-execution.md) continues to govern
production execution/publication. No transaction store, checkpoint or resume
protocol is introduced by this harness.

## Acceptance evidence

- H-016 requires human-reviewed calibration.
- H-017 requires complete live generation, grading, rerun and failure evidence.
- Keep completed low-scoring evaluations visible; offline tests or selected
  favorable runs cannot substitute for them.
- Plan, Tasks and Implement each require their own E2E cases.
