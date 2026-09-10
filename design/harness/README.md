# Spec workflow evaluation backlog

**Status:** Proposed implementation backlog; evaluator and in-memory generation
are implemented, with partial clarification/publication integration. Human
evaluation and live API verification are excluded from the
current implementation task; neither is claimed completed. **Reviewed:** 2026-09-07,
including uncommitted work. [Evaluator commands and contract](evaluator.md).

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
- This is development-only evaluation of the engine, not authorization to run
  against a real target project, send data externally, incur API charges, add
  dependencies or change release/CI policy.
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
- The older [F0050 readiness finding](../features/F0050-SpecWorkflowEvaluationService.md)
  incorrectly defers semantic rubric scoring and refers to a missing harness
  document. Do not use those statements to replace this user-directed goal
  with a conformance-only milestone. H-018 tracks reconciliation of those docs;
  it does not authorize bypassing production invariants.

## Implementation snapshot

The [single-case E2E command](e2e.md) now executes one declared reference/feature
case in one isolated project, with scripted observations at the provider
boundary. It retains a UTC-dated folder beneath `zig-out/e2e-spec/` and checks
actual engine publication and expected files. The Hello World run now passes:
the ordinary YAML publishes specification and reference views, clarification
state and canonical specification state. The 26-scenario regression suite
remains independent and no longer writes review folders. H-012 feature-log
integration and the H-015 evaluator handoff remain unfinished.

| Area | Evidence at review | Remaining boundary |
| --- | --- | --- |
| Generic engine | YAML discovery/compiler/runner and explicit feature/reference invocation reach registered publication. | Remaining clarification routes and feature-log integration. |
| References | Model-connected extraction/reconciliation, citations, typed text and exact-value preservation are retained in canonical state and rendered in the sidecar. | Applicable clarification answers. |
| Model calls | [Native request operations](../../src/composition/model_request_operations.zig), configured production provider, explicit retirement/protocol retry and fake-provider tests exist. | Authorized live verification; no new provider is required for H-009/H-010. |
| Specify | H-007–H-012 connect content, gates, generation, repair, sidecar/state publication and protected form writes. Tests cover shorter rerun replacements, monotonic IDs, invalid state and every publication write failure. | Authenticated/current answers, remaining gap routes, feature logs and interruption evidence. |
| Fixture | Unchanged `stories.md`, seven principle files, `spec.case.json`, draft rubric and seven [calibration specimens](../../test/e2e/wf-001-hello-world/node-vitest/calibration/README.md) exist. | Human rubric review/live calibration and full-workflow runtime resources. |
| Evaluator | `test/harness/`, `harness.zig` and `evaluate-spec`/offline test/smoke build steps implement supplied-spec OpenAI/Bedrock grading and reports. | Authorized live acceptance; no paid API call was made during implementation. |
| Full-workflow harness | [One-case scripted invocation](e2e.md), explicit fixture mapping, source preservation checks and publication/file checks now exist. Missing publication exits nonzero. | Remaining H-012 integration, H-015 evaluator handoff and live end-to-end evidence. |

This is a source inspection, not a fresh test-pass claim. Recheck changing
boundaries before implementing a ticket; do not rebuild existing functionality.

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

Neither a supplied-spec evaluation nor a fake-generation end-to-end test alone
completes milestone 3. Rubric work and evaluator calibration are core delivery,
not an optional phase after a golden-file harness.

## Backlog index

H-001–H-006 have an offline implementation; live acceptance and human review
are excluded from the current task. H-007's native contract/codec and H-008's
shared required-authority boundary and H-009/H-010 generation are implemented;
H-011–H-018 remain open.
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

Use the callable evaluator for authorized live acceptance and H-016 calibration
while H-007–H-013 proceed independently. H-014 can prepare fixture assembly while
production work proceeds. H-015 joins the two tracks.

## Completion checklist

- [ ] A checked-in rubric evaluates the original reference without a prose golden.
- [ ] An authorized call to the selected provider evaluates an explicitly supplied spec and reports
  criterion evidence; this is clearly labelled evaluator-only evidence.
- [ ] The ordinary Spec YAML executes through the production engine with fake
  model observations, without a fixture-specific execution path.
- [ ] The original Hello World case completes real generation, and the selected provider grades
  the exact `spec.md` produced by that execution.
- [ ] Reports distinguish workflow failure/clarification, evaluator error,
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
