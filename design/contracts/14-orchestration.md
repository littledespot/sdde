# 14. Orchestrator composition

Part of the [proposed design](../design.md#14-orchestrator-composition). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

[View the Orchestrator composition sample](../code.md#orchestrator-composition).

[View the validated-generation and atomic-repair diagram](../diagrams/03-validated-generation-repair.md).

An orchestrator “contains” children through composition. It does not contain their logic. Actions expose no child collection or dispatcher, so an action cannot contain or call an orchestrator.

- For project workflow execution, every reusable workflow operation described in this section is
  available through one unversioned registered operation ID and is selected only by a YAML
  `use` field, directly or inside compiler-expanded local subgraphs under ADR 0013.
- An operation may coordinate the actions needed for its single atomic responsibility, but it
  returns a typed outcome without selecting the next workflow operation.
- The YAML `on` mapping alone selects that successor.
- Whole-stage `Specify`, `Plan`, `Tasks`, and `Implement` orchestrators are prohibited because
  they would duplicate and hide the compiled workflow graph.
- Only the engine kernel identified by ADR 0005, including the sections explicitly marked
  startup, cleanup, or instrumentation-internal, is not callable from YAML.

### 14.0 `WorkflowEngineOrchestrator`

This capability-free root orchestrator executes one explicitly requested
workflow without branching on workflow names:

1. invoke the preselection portion of `BootstrapOrchestrator` through its
   runner-owned binding so configuration roots, the complete workflow
   inventory, compiled graphs, and registry validate before workflow-specific
   work; this portion acquires no workflow execution capability;
2. invoke `ParseWorkflowSelectionAction` and `ValidateWorkflowIdAction` through
   runner-owned bindings to obtain one explicit `WorkflowId` and the unchanged
   workflow-specific arguments;
3. invoke `ResolveSelectedWorkflowAction` through its runner-owned binding for
   that validated `WorkflowId`;
4. receive from the runner the selected graph's bound registered operations;
5. invoke the selected graph's registered capability-free invocation-contract
   node through its runner-owned binding to validate the remaining arguments
   and produce the typed run context;
6. start at the compiled entry node with that context; the selected graph owns
   any later project, feature, toolchain, or other workflow-specific setup.
   After each applied child outcome, follow only the matching validated typed
   transition; and
7. return the compiled terminal outcome.

- It does not parse a workflow definition, compile a graph, construct a node or binding, invoke
  a node directly, inspect domain data, or receive any operation port.
- Unknown workflow IDs, missing operation bindings, unhandled outcomes, invalid graphs, and
  capability-policy failures stop before the selected graph runs.
- The runner remains the sole node invocation and delta-application owner.

- An invocation operation has one responsibility: turn the preserved workflow-specific arguments
  into that workflow's validated typed run context.
- It may be a capability-free orchestrator over runner-bound parse and validation actions.
- For `specify`, those children are `ParseSpecifyInvocationAction` and
  `ValidateSpecifyArgumentsAction`; neither action receives the invocation contract itself or
  invokes the other.

### 14.1 Model-operation composition

- Generation is not a hidden orchestrator.
- A workflow declares separate generic steps for authority reconciliation, context construction,
  model invocation, result validation, clarification, repair, and acceptance as required by that
  workflow.
- Each step returns only its registered typed outcomes.
- The YAML graph declares every branch, including clarification, retry, repair, failure, and
  cancellation.
- Every retry-capable operation instance declares its own bounded limit, which the compiler
  binds to monotonic accounting and which no transition cycle can bypass.
- The selected policy contributes only the workflow execution's total-token budget.

Bounded collection operations may return `more` for successful progress with
remaining work. It is a registered, non-terminal outcome: YAML declares its
successor and every cycle still requires the existing monotonic bound. No policy
may admit `end.more`; it grants no acceptance, gate or completion authority.

### 14.2 `StageGateOrchestrator`

For the selected initial SDD workflow's predecessor gate it:

1. invokes stage-order validation;
2. invokes prerequisite presence/readability validation;
3. loads authoritative predecessor inputs through read/parse actions for editable `spec.md` and canonical-state read actions for generated stages;
4. invokes the registered predecessor validators;
5. invokes `CompareSpecificationIRAction` wherever the stage or fresh-invocation validation matrix requires the current normalized spec to equal the exact specification stored in `PlanState` (and records typed changed-record evidence when it does not);
6. loads/validates the current clarification registry and invokes `ValidateClarificationStageGateAction` for the requested stage;
7. invokes `ValidateWorkflowMetadataAction` for each metadata invariant, such as whether a reference view is expected;
8. invokes `AuthorityReconciliationOrchestrator` over the complete requested-stage gate projection and continues only from `all_resolved`;
9. returns the typed predecessor context or stops.

An unresolved `SNN` causes plan to terminate with `UPSTREAM_SPEC_CLARIFICATION_OPEN`; an unresolved `SNN` or `PNN` causes tasks to terminate with `UPSTREAM_PLAN_CLARIFICATION_OPEN`; any unresolved `SNN`, `PNN`, or `TNN` causes implement to terminate with `UPSTREAM_TASKS_CLARIFICATION_OPEN`. These are deterministic user-input errors with nonzero command status, not model-repair attempts.

The persisted stage status is advisory until these current artifacts pass. This provides sequential safety without fingerprints.

### 14.3 Task-scheduling operation

- The YAML-selected task-scheduling operation invokes `CalculateRunnableSetAction` over phase,
  dependencies, path sets, shared-resource locks, and command mutability, invokes
  `SelectRunnableTaskAction`, and invokes `ClaimTaskLeaseAction` to atomically reserve state and
  locks.
- It returns the typed lease outcome to the YAML graph and does not select the next operation.
- Every lease is released through its declared cleanup boundary on success, failure or
  cancellation; release evidence remains execution-local until the complete workflow output is
  validated.
- The initial execution policy uses concurrency one.
- Higher concurrency is permitted only for tasks whose validated graph says they are independent
  and whose candidate overlay changes can be applied without resource conflicts.
- “Different files” alone is never sufficient.

### 14.4 Atomic-repair operation

- The YAML-selected repair operation invokes ordering and selection, then
  `ClassifyRepairAuthorizationPurposeAction`.
- The ordinary branch invokes `CreateRepairAuthorizationAction` and
  `AdvanceAtomicRepairAttemptAccountingAction`; the unsupported-content branch invokes
  `CreateNoInventionClarificationReplacementAuthorizationAction` and consumes only its
  unit-local one-shot flag during scope validation.
- It performs one authorized repair attempt and returns its typed result.
- A further attempt, candidate validation, clarification, or terminal outcome is a YAML
  transition, not an internal successor choice.

### 14.5 User-review operation

- This YAML-selected operation presents engine-rendered plan or task views and waits for an
  explicit decision tied to the current `planStateId` or immutable `taskDefinitionStateId`.
- It first captures the raw submission and runs `ValidateReviewSubmissionAction` against the
  expected workflow revision, exact target, review-unit registry, decision shape, and bounded
  feedback.
- A stale or malformed submission is rejected before its authentication lease is consumed.
- Only a statically valid submission proceeds through `AuthenticateActorAction`,
  authentication-observation/evidence validation, and `BindAuthenticatedReviewSubmissionAction`;
  decision allocation/build/validation then consumes that exact binding.

- `approve` records approval and returns the typed approved outcome.
- `reject` records feedback without changing generated files and returns the
  typed rejected outcome with mapped IR unit IDs. The YAML graph selects the
  declared regeneration, repair, validation, and rendering steps; prior
  approval is cleared.
- Feedback that cannot be safely mapped to a bounded unit blocks for clarification; the engine does not treat direct edits to a generated view as feedback.

In non-interactive use, approval must arrive through an explicit API/CLI approval event or a deliberately selected policy profile. Merely invoking the next stage does not silently approve review output in the hardened default.

- The complete review output binds actor evidence, the review record/registry, state identities
  and the exact approved or rejected target.
- Validate every join before publication under §25 and write canonical state last.
- Failure cannot record a new successful approval transition; no review journal, rollback or
  commit-marker protocol is introduced.

### 14.6 Protocol-retry operation

- This YAML-selected operation is used only when decoding or workflow-declared result-schema
  validation produced no candidate IR.
- Its compiled subgraph declares `BuildProtocolRetryGuidanceAction`,
  `ValidateModelRequestBindingAction`, `BuildModelRequestAction`, and one accounted provider
  attempt, followed by `ValidateProviderInvocationObservationAction`,
  `DecodeModelEnvelopeAction` and `ValidateModelPayloadSchemaAction`.
- A missing or invalid trusted call association fails closed; it is not malformed model content
  eligible for protocol repair.
- The operation returns a typed result and cannot invoke candidate/semantic validators, choose
  another retry, or call `MergeAtomicRepairAction` because no authorized pointer exists.
- The YAML graph declares any further bounded retry transition.

### 14.7 `ClarificationLifecycleOrchestrator`

[View the clarification lifecycle diagram](../diagrams/07-clarification-lifecycle.md).

- This shared orchestrator coordinates Specify, Plan and Tasks clarification work through
  runner-owned bindings.
- For a typed need, it constructs the subject key, looks up the exact registry entry, validates
  uniqueness, allocates only when absent, and prepares the complete registry/forms through
  §23.2's persistence exception.
- It never interprets a question, chooses an answer or edits a form.

- Reference refresh reconciles the complete previous/current conflict-subject sets in canonical
  key order.
- Same-key entries retain their IDs; answered entries require validated option correspondence.
- Obsolete protected closures remain untouched, unprotected obsolete entries use the permitted
  authority-resolution route, and new subjects use global lookup before allocation.
- Validate the complete set and its exact open-form projection before publication; no per-entry
  intermediate registry is published.
- Unequal keys never imply correspondence.

- On a new invocation, capture controlled submissions before preparing replacement forms.
- Validate revisions, authentication and current applicability; preserve user-closed bytes even
  when stale or invalid.
- Accepted answers and validated resolutions persist under the clarification exception, then the
  owning workflow regenerates from `start`.
- A deferred/open need retains its subject ID and receives a complete replacement form; a
  consumed defer is recorded once, advances the revision and yields a blank open answer region.
- Old submissions become stale.
- Resolved/cancelled forms expose no submittable region.
- A valid cancel remains `cancelled`; an unresolved need ends `needs_user`.
- No partial stage IR or accepted unit checkpoint survives for continuation.

The orchestrator branches only on typed child results; §23.2 owns write-time
protection and §25 owns publication failure.

### 14.8 Execution abandonment

There is no transaction-recovery orchestrator. Failure, cancellation or
interruption ends the execution without a saved continuation. Runner cleanup
releases that execution's resources. A new invocation enters the selected
compiled workflow at `start`, not at a recovered node.

### 14.9 `FeatureLoggingFailureOrchestrator`

This instrumentation-internal orchestrator is entered once for a feature-sink failure. It coordinates transient-handle cleanup, one bounded emergency diagnostic and fail-closed execution abandonment. It performs no transaction stabilization or recovery, has no sink/filesystem capability itself, and is excluded from logging observation.

### 14.10 `FeatureLogPolicyTransitionOrchestrator`

- This instrumentation-only orchestrator switches an existing run after **any** committed
  successor bootstrap authority whose validated change plan sets `transitionFeatureLogging:
  true`, including mixed specification/planning changes.
- Before refresh, startup reconstructs the historical policy solely from the current persisted
  `BootstrapAuthorityState.components.compiledEnginePolicy.loggingPolicyFragment`; until
  feature-WAL recovery and that authority validation finish, only bounded content-free emergency
  telemetry is available.
- Ordinary feature events continue under that historical binding while the successor bootstrap
  candidate is evaluated.

- After the validated policy handoff, the runner pauses new workflow nodes and buffers only
  bounded typed `WorkflowTelemetryFact` values, preserving each active compiled workflow's
  registry-validated shortcode.
- The successor state's durable lineage supplies the exact parent ID and materialized change
  plan.
- In the same live run, the orchestrator builds/validates both policies/bindings, then visits
  each enabled stream in fixed `event`, then `prompt` order.
- It acquires the physical lock from the historical binding and converts that single token into
  the validated dual-binding transition capability.
- Under it, actions recover the historical active tail or validate an already-closed tail,
  durably close when needed through `FeatureLogPort.closeForPolicyTransition`, initialize or
  recover the successor-binding segment namespace, and validate the old/new boundary.
- After all per-stream locks are released, the mixed-state assembler builds/validates one
  complete successor sink; only then does `ActivateFeatureLogPolicyTransitionAction` swap the
  run-local observer and flush buffered facts through the new definitions/policy.
- No normal event/model/node occurs between bootstrap-pointer commit and this switch.
- Any failure emits the one fixed emergency record and enters `block_new_work`; the engine never
  continues on an obsolete or partially switched policy.

- A process restart deliberately creates a fresh `runId`; it never pretends to resume or
  activate the crashed run's in-memory transition.
- Fresh-run startup first uses the fixed event/prompt collection paths from the validated
  `WorkflowArtifactRegistry` and active-feature capability; it does **not** build the current
  run's policy or binding merely to discover history.
- It scans/validates all bounded prior-run binding groups, resolves each historical policy
  solely through its `segment_header` control row's policy identity and readable bootstrap
  lineage, and processes groups in deterministic `(runId, bindingId, stream rank)` order.
- For an active prior tail it acquires that prior run's ordinary single-binding physical lock,
  recovers the tail, invokes `FeatureLogPort.closeHistoricalTailAfterCrash`, validates the
  close, and releases; for a closed-only group it validates the durable `segment_trailer`
  control row under the same lock and performs no write.
- After release, `BuildHistoricalFeatureLogStreamFinalizationEvidenceAction` joins that exact
  group result to its release observation.
- `ValidateHistoricalFeatureLogRunFinalizationAction` requires one such discriminated record per
  group and proves all locks released/no active prior tail.
- Only that complete evidence authorizes canonicalization and construction of the fresh
  current-authority policy/binding, emission of `run.started`, or current-run sink
  initialization.
- Thus crash recovery needs no durable run-local transition pointer, and neither a current
  binding nor a dual-binding capability is misapplied to a historical run.

### 14.11 Implementation workflow composition

- There is no `ImplementOrchestrator` selected by the workflow name.
- The implementation YAML explicitly orders its gate, process-lease, feature-lock, scheduling,
  task, final-validation, reconciliation, cleanup, and release operations.
- Every terminal branch declares cleanup and release transitions.
- The compiler rejects a graph in which task execution, model, overlay, or command steps are
  reachable before the required lease and lock facts.
- Opaque handles remain runner-owned and never enter YAML, durable state, logs, or model
  context.

### 14.12 Per-task implementation composition

- There is no hidden `ImplementTaskOrchestrator`.
- The implementation YAML explicitly composes task-attempt, operation-intent, model-generation,
  savepoint, validation, command/manual-evidence, and task-result operations and declares their
  outcomes.
- Registered contracts prevent any step from broadening the task's file/capability set.
- Task completion is published only after the whole workflow output and its evidence pass
  validation and all required writes succeed, never from model prose or a checklist claim.

### 14.13 Task execution lifetime

- Task work belongs to the containing workflow execution.
- No adapter boundary, promotion receipt or cleanup checkpoint is persisted as restart
  authority.
- Current-execution ownership and cleanup remain runner responsibilities.
- Interruption abandons the entire execution; a later invocation starts at the workflow's
  `start` step and revalidates all current gates.

### 14.14 `AuthorityReconciliationOrchestrator`

- This reusable orchestrator runs at each stage's pre-generation boundary, after every authority
  refresh or clarification response, after candidate repair, immediately before whole-workflow
  publication, and at downstream/rerun gates.
- It invokes the discrete ledger-build/validate, per-requirement candidate-build/validate,
  optional bounded semantic-assessment, outcome-build/validate, complete-ledger-build/validate,
  and gap-routing actions from Section 13.10.
- The runner owns iteration in canonical requirement order; the orchestrator neither interprets
  a requirement nor chooses an owner or resolution.

- A fully resolved ledger yields only validation evidence for the current candidate/gate.
- Any non-success entry prevents generation continuation or commit.
- For a same-stage gap, the generic need-builder action constructs the registered typed need and
  then enters `ClarificationLifecycleOrchestrator`; an earlier-owner gap enters the Section 24.5
  invalidation/rework route; an unregistered or administratively owned gap blocks.
- When multiple gaps exist, the routing action preserves the complete ordered set, chooses the
  earliest owner through the compiler-locked dominance policy, and sends the first canonical gap
  to the existing single-need clarification lifecycle.
- No other gap is treated as resolved or omitted; after that clarification resolves, full
  owning-stage regeneration rebuilds the ledger before another gap can be selected.
- The separately specified complete reference-conflict set transition remains the only v1 batch
  clarification mutation because its accepted snapshot-consistency contract explicitly requires
  atomic set equality.

The orchestrator has no domain-specific branches. A new requirement kind becomes usable only through the common registry, actions, and conformance suite; adding a caller condition to this orchestrator is an architecture violation.
