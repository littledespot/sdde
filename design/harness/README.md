# Spec workflow evaluation backlog

**Status:** Live generation and rubric handoff are implemented. Human rubric
calibration and broader acceptance remain open. **Reviewed:** 2026-09-11.
[Run instructions and result interpretation](e2e.md).

## User-directed outcome

Run the ordinary `spec.workflow.yaml` against the Hello World reference, then
evaluate the **actual generated `spec.md`** using the **selected OpenAI or Bedrock API and a rubric**.
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

- Initial case: `test/e2e/wf-001-hello-world/node-vitest`, using its
  sibling [stories.md](../../test/e2e/wf-001-hello-world/reference/stories.md).
- Evaluator providers: OpenAI Responses or Bedrock Converse, explicitly selected
  through the internal test environment. The workflow's generation provider
  and the evaluator's provider/model are separate selections. The supplied-spec
  evaluator uses Responses/Converse with native HTTPS without a new dependency. Exact model
  and limits are mandatory operator selections; draft rubric scoring is visible
  in the rubric file, not a production policy or calibrated result.
- This is development-only evaluation of the engine in isolated test projects.
  Live runs transmit their declared inputs and use configured API credentials.
  They are explicitly invoked and are not part of offline verification or CI.
- [Engine design](../design.md) remains Proposed. Its production safety and
  publication rules still apply. This backlog does not make rubric scores into
  workflow approvals, clarification answers or permission to publish.
- [F0100](../features/F0100-SpecWorkflow.md) owns the Spec workflow contract.
  [ADR 0003](../decisions/0003-generic-workflow-engine.md) owns generic YAML
  execution. [ADR 0009](../decisions/0009-atomic-workflow-execution.md) rules out
  transaction stores, checkpoints and resumable executions. Its approved
  publication-failure rule permits already-replaced files to remain after write
  failure/interruption, without new successful completion; a fresh run replaces
  outputs from the beginning.
- [F0050](../features/F0050-SpecWorkflowEvaluationService.md) points to this
  harness contract. Rubric grading is part of the E2E path.

## Implementation snapshot

The [single-case E2E command](e2e.md) runs the selected test's configured LLM
through the production runtime, validates actual publication, and submits that
exact specification to the selected live rubric evaluator. It retains immutable
input captures and separate generation/publication/quality results in one dated
folder. Scripted-generation and golden-document E2E paths have been removed.

| Area | Implemented | Remaining evidence/work |
| --- | --- | --- |
| Generic engine | Ordinary YAML compilation, model requests, validators and publication. | Remaining production clarification and feature-log routes tracked in H-011/H-012. |
| Fixture | Explicit project/resource mapping, original reference capture, rubric/settings capture and source preservation checks. | Broader live workflow cases. |
| Evaluator | Supplied-spec and joined E2E grading through OpenAI/Bedrock with closed result/evidence validation. | Human rubric review and H-016 calibration. |
| Full-workflow harness | Real configured generation, publication identity checks, live grading and failure reports. | H-017 broader live/rerun/failure evidence; see retained run results. |

The latest live run completed extraction with low reasoning, then rejected an
invalid JSON reconciliation response (3 calls; 8,472 accounted tokens). It
produced no specification or
grade. [Run evidence](e2e.md#live-evidence--2026-09-11) retains this unmet acceptance.

Mechanical tests establish the harness contracts. A completed live execution
and its scores must be reported separately; a source inspection is not a test
pass or proof of semantic quality.

## Delivery sequence

1. **Evaluator first:** agree the small case/rubric/result contracts, create the
   rubric, and grade a supplied specimen through the selected provider. Label supplied,
   recorded, scripted and freshly generated artifacts honestly. This work can
   proceed while Specify is unfinished.
2. **Runnable Specify:** finish only its production dependencies and connect the
   ordinary YAML workflow to the isolated-project harness. Fake-provider tests
   prove integration before authorized live generation.
3. **Requested milestone:** run real Spec generation for the original reference,
   grade that run's output through the selected provider, and produce an inspectable report.
   A low score is a valid evaluation result, not an excuse to hide the run.

Neither a supplied-spec evaluation nor a fake-generation integration test alone
completes milestone 3. Rubric work and evaluator calibration are core delivery,
not an optional phase after a golden-file harness.

## Backlog index

H-001–H-006 are implemented; human review/calibration remains open. H-007's native contract/codec and H-008's
shared required-authority boundary and H-009/H-010 generation are implemented;
H-014/H-015 and H-018 code/documentation are implemented; H-011/H-012 gaps,
H-016 human calibration and H-017 broader acceptance remain open.
Dependencies and evidence are defined in the ticket bodies.

| ID | Work item | Track |
| --- | --- | --- |
| [H-001](01-rubric-evaluator.md#h-001--define-the-minimum-evaluation-contracts) | Minimum case/configuration contracts and explicit decisions | Evaluator |
| [H-002](01-rubric-evaluator.md#h-002--create-the-hello-world-rubric) | Hello World rubric and scoring anchors | Evaluator |
| [H-003](01-rubric-evaluator.md#h-003--capture-inputs-and-build-the-judge-packet) | Exact source/spec/rubric capture and judge packet | Evaluator |
| [H-004](01-rubric-evaluator.md#h-004--implement-the-evaluator-provider-boundary) | Selected-provider invocation, credentials and failure handling | Evaluator |
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

Use `e2e-spec` for live generation plus grading and `evaluate-spec` for explicit
supplied-spec grading. Neither changes production workflow authority.

## Completion checklist

- [x] A checked-in rubric evaluates the original reference without a prose golden.
- [ ] An authorized call to the selected provider evaluates an explicitly supplied spec and reports
  criterion evidence; this is clearly labelled evaluator-only evidence.
- [ ] The ordinary Spec YAML executes through the production engine with fake
  model observations, without a fixture-specific execution path.
- [ ] The original Hello World case completes real generation, and the selected provider grades
  the exact `spec.md` produced by that execution.
- [x] Reports distinguish workflow failure/clarification, evaluator error,
  completed low-scoring evaluation and completed satisfactory evaluation.
- [ ] Every workflow's repeated runs completely overwrite registered replaceable
  outputs and unresolved clarification forms at the same paths, retaining
  subject IDs and preserving user-resolved forms byte-for-byte; evaluation
  reports cannot mutate workflow authority.
- [ ] Negative tests and human calibration show that semantic variations can be
  accepted and missing/invented requirements receive appropriate findings.
- [ ] Relevant repository verification and clean native smoke tests pass;
  live checks are explicit opt-in and their actual evidence is recorded.

No ticket adds a dashboard, distributed runner, judge committee, automatic
prompt optimizer, transaction directory, feature-ownership registry or a new
workflow engine. Extend an existing owner where it already provides the needed
contract; remove superseded code/docs in the implementing change.
