# Spec workflow evaluation backlog

**Status:** Proposed implementation backlog; nothing below is implemented by
creating these documents. **Reviewed:** 2026-09-06, including uncommitted work.

## User-directed outcome

Run the ordinary `spec.workflow.yaml` against the Hello World reference, then
evaluate the **actual generated `spec.md`** using the **OpenAI API and a rubric**.
Report criterion-level judgments, scores, evidence and explanations.

The LLM evaluates semantic quality: coverage, correctness, unsupported additions,
clarity, testability and appropriate scope. Mechanical checks establish that
inputs, execution and evaluator responses can be processed safely. They do not
establish that the specification is semantically correct.

An exact expected `spec.md`, a universal deterministic definition of good
requirements, or completion of Plan/Tasks/Implement is **not** a prerequisite
for rubric evaluation. Offline fakes test the machinery; they do not replace the
requested live, LLM-based evaluation.

## Scope and authority

- Initial case: `test/evaluation/wf-001-hello-world/node-vitest`, using its
  sibling [stories.md](../../test/evaluation/wf-001-hello-world/reference/stories.md).
- Initial evaluator provider: OpenAI API. The workflow's generation provider
  and the evaluator's provider/model are separate selections; the user has not
  selected an exact model, SDK, API endpoint, score scale or threshold.
- This is development-only evaluation of the engine, not authorization to run
  against a real target project, send data externally, incur API charges, add
  dependencies or change release/CI policy.
- [Engine design](../design.md) remains Proposed. Its production safety and
  publication rules still apply. This backlog does not make rubric scores into
  workflow approvals, clarification answers or permission to publish.
- [F0100](../features/F0100-SpecWorkflow.md) owns the Spec workflow contract.
  [ADR 0003](../decisions/0003-generic-workflow-engine.md) owns generic YAML
  execution. [ADR 0009](../decisions/0009-atomic-workflow-execution.md) rules out
  transaction stores, checkpoints and resumable executions.
- The older [F0050 readiness finding](../features/F0050-SpecWorkflowEvaluationService.md)
  incorrectly defers semantic rubric scoring and refers to a missing harness
  document. Do not use those statements to replace this user-directed goal
  with a conformance-only milestone. H-018 tracks reconciliation of those docs;
  it does not authorize bypassing production invariants.

## Observed starting point

| Area | Evidence at review | Remaining boundary |
| --- | --- | --- |
| Generic engine | YAML discovery/compiler/runner and explicit feature/reference invocation exist. | Complete Specify definition and content-producing operations. |
| References | F0100 §§3.1–3.9 implement Markdown inputs, citations, typed text, exact-value preservation and scripted extraction/reconciliation. | Model wiring, semantic generation and final artifact/state publication. |
| Model calls | [Native request operations](../../src/composition/model_request_operations.zig) and fake-provider tests exist; lifecycle work is changing in the worktree. | Verify/reuse that work, supply live provider integration and domain request/result bindings. |
| Specify | [Native reference tests](../../src/composition/root.zig) explicitly assert that no `spec.md` was written. | Specification generation, authority integration, clarification lifecycle, rendering and publication. |
| Fixture | `stories.md` plus seven `node-vitest/principles/*.md` files exist. | Case configuration, runtime resources and `node-vitest/rubric/spec.json`. |
| Harness | No `TEST_HARNESS.md`, executable evaluator, rubric file or harness build step was found. | Evaluator and full-workflow harness. Existing references to absent files are not implementation evidence. |

This is a source inspection, not a fresh test-pass claim. Recheck changing
boundaries before implementing a ticket; do not rebuild existing functionality.

## Delivery sequence

1. **Evaluator first:** agree the small case/rubric/result contracts, create the
   rubric, and grade a supplied specimen through OpenAI. Label supplied,
   recorded, scripted and freshly generated artifacts honestly. This work can
   proceed while Specify is unfinished.
2. **Runnable Specify:** finish only its production dependencies and connect the
   ordinary YAML workflow to the isolated-project harness. Fake-provider tests
   prove integration before authorized live generation.
3. **Requested milestone:** run real Spec generation for the original reference,
   grade that run's output through OpenAI, and produce an inspectable report.
   A low score is a valid evaluation result, not an excuse to hide the run.

Neither a supplied-spec evaluation nor a fake-generation end-to-end test alone
completes milestone 3. Rubric work and evaluator calibration are core delivery,
not an optional phase after a golden-file harness.

## Backlog index

All tickets are open. `Decision` identifies a choice to record, not a reason to
block unrelated work. Dependencies are defined in the ticket bodies.

| ID | Work item | Track |
| --- | --- | --- |
| [H-001](01-rubric-evaluator.md#h-001--define-the-minimum-evaluation-contracts) | Minimum case/configuration contracts and explicit decisions | Evaluator |
| [H-002](01-rubric-evaluator.md#h-002--create-the-hello-world-rubric) | Hello World rubric and scoring anchors | Evaluator |
| [H-003](01-rubric-evaluator.md#h-003--capture-inputs-and-build-the-judge-packet) | Exact source/spec/rubric capture and judge packet | Evaluator |
| [H-004](01-rubric-evaluator.md#h-004--implement-the-openai-evaluator-boundary) | OpenAI invocation, credentials and failure handling | Evaluator |
| [H-005](01-rubric-evaluator.md#h-005--validate-judgments-and-calculate-results) | Closed response validation and score calculation | Evaluator |
| [H-006](01-rubric-evaluator.md#h-006--report-results-and-support-supplied-spec-evaluation) | Reports and evaluator-only entry point | Evaluator |
| [H-007](02-spec-workflow.md#h-007--align-the-existing-specification-contract) | Existing production contract alignment | Workflow |
| [H-008](02-spec-workflow.md#h-008--implement-the-shared-required-authority-boundary) | Shared authority gate, with Specify integration | Workflow |
| [H-009](02-spec-workflow.md#h-009--connect-reference-operations-to-model-execution) | Reference/model operation wiring | Workflow |
| [H-010](02-spec-workflow.md#h-010--generate-and-validate-specification-content) | Feature brief, specification records and validation | Workflow |
| [H-011](02-spec-workflow.md#h-011--complete-specification-clarification-handling) | Clarifications, answers and fresh reruns | Workflow |
| [H-012](02-spec-workflow.md#h-012--render-and-publish-the-complete-workflow-output) | Render/reparse and safe output replacement | Workflow |
| [H-013](02-spec-workflow.md#h-013--supply-the-executable-spec-workflow-definition) | Concrete generic YAML definition and resources | Workflow |
| [H-014](03-harness-verification.md#h-014--assemble-the-isolated-hello-world-project) | Fixture mapping and temporary-project builder | Integration |
| [H-015](03-harness-verification.md#h-015--run-the-workflow-and-evaluate-its-actual-output) | Ordinary workflow execution and evaluator handoff | Integration |
| [H-016](03-harness-verification.md#h-016--test-and-calibrate-the-evaluator) | Mechanical tests and human-reviewed live calibration | Verification |
| [H-017](03-harness-verification.md#h-017--prove-the-complete-spec-evaluation-case) | End-to-end, rerun and failure evidence | Verification |
| [H-018](03-harness-verification.md#h-018--add-build-wiring-and-correct-the-documentation) | Commands, documentation cleanup and handoff | Delivery |

Start H-001/H-002 and H-007 together. H-003–H-006 do not depend on H-007–H-013.
H-014 can prepare fixture assembly while production work proceeds. H-015 joins
the two tracks; H-016 can start as soon as the evaluator is callable.

## Completion checklist

- [ ] A checked-in rubric evaluates the original reference without a prose golden.
- [ ] An authorized OpenAI call evaluates an explicitly supplied spec and reports
  criterion evidence; this is clearly labelled evaluator-only evidence.
- [ ] The ordinary Spec YAML executes through the production engine with fake
  model observations, without a fixture-specific execution path.
- [ ] The original Hello World case completes real generation, and OpenAI grades
  the exact `spec.md` produced by that execution.
- [ ] Reports distinguish workflow failure/clarification, evaluator error,
  completed low-scoring evaluation and completed satisfactory evaluation.
- [ ] Repeated runs overwrite workflow outputs and preserve user-closed
  clarification files; evaluation reports cannot mutate workflow authority.
- [ ] Negative tests and human calibration show that semantic variations can be
  accepted and missing/invented requirements receive appropriate findings.
- [ ] Relevant repository verification and clean native smoke tests pass;
  live checks are explicit opt-in and their actual evidence is recorded.

No ticket adds a dashboard, distributed runner, judge committee, automatic
prompt optimizer, transaction directory, feature-ownership registry or a new
workflow engine. Extend an existing owner where it already provides the needed
contract; remove superseded code/docs in the implementing change.
