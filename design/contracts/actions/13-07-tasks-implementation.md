# 13.7 Task and implementation actions

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.


Within one workflow execution, the runner owns one revision-validated task identity and evidence chain. Assignment and validation remain explicit actions. No checkpoint, durable adapter boundary or transaction is needed before an operation; candidate state and evidence stay private until whole-workflow completion.

## `ValidateTaskDefinitionProposalSchemaAction`

- **Input:** one model task proposal
- **Output:** schema evidence
- **Responsibility:** Apply the closed proposal schema that excludes canonical
  IDs/origins/evidence/locks.

## `AssignObligationPartitionStateIdAction`

- **Input:** exact obligation-ledger ID, validated current feature `StateIdLedger`, and matching
  single-use namespace capability
- **Output:** obligation-partition reservation plus successor ledger
- **Responsibility:** Reserve one immutable partition-state ID.

## `BuildObligationClustersAction`

- **Input:** partition identity, complete obligation ledger, compiled workflow model-operation
  declaration, and stable phase/project/kind ordering policy
- **Output:** deterministic obligation clusters
- **Responsibility:** Partition by closed affinity keys and the workflow-declared partition
  contract; do not interpret semantics or infer API-size ceilings.

## `ValidateObligationClusterCoverageAction`

- **Input:** clusters, exact ledger, and partition contract
- **Output:** cluster-coverage evidence
- **Responsibility:** Prove every obligation appears exactly once, ordering is canonical, and
  the declared partition contract is satisfied without truncation or a local model-call size
  gate.

## `ValidateTaskProposalPartitionAccountingAction`

- **Input:** all cluster calls/proposals and obligation partition
- **Output:** task-proposal accounting evidence
- **Responsibility:** Prove one final call outcome per cluster and every proposed obligation
  remains inside its cluster allowlist.

## `ValidateTaskExecutabilityAction`

- **Input:** one schema-valid task proposal
- **Output:** executability evidence
- **Responsibility:** Require one concrete file/check/scenario responsibility.

## `ValidateTaskObligationReferenceAction`

- **Input:** one task `obligationId` and task-local obligation allowlist
- **Output:** obligation-reference evidence
- **Responsibility:** Resolve only the closed `ObligationLedger` namespace.

## `ValidateTaskPhaseKindAction`

- **Input:** one task phase/kind/mode tuple
- **Output:** phase-kind evidence
- **Responsibility:** Apply the verification compatibility matrix.

## `ValidateCommandSelectionAction`

- **Input:** one command selection and task/plan-local command allowlist
- **Output:** command-selection evidence
- **Responsibility:** Validate known ID and typed arguments without accepting an origin.

## `BuildCommandInvocationAction`

- **Input:** one validated selection and engine-required/model-optional derivation
- **Output:** canonical command invocation
- **Responsibility:** Assign the invocation origin from engine context only.

## `ValidateTaskFileSelectionAgainstPlanGrantAction`

- **Input:** one proposal read/write file ID, role, exact `PlanFileGrant`, and file-kind/global
  policy
- **Output:** task-file-selection evidence
- **Responsibility:** Require read capability for reads and at least one intent-compatible
  mutation capability for writes; reject an ID outside the plan.

## `ValidateTaskFileSelectionCompletenessAction`

- **Input:** one proposal, its responsibility/obligations/dependency surface, and all selection
  evidence
- **Output:** task-file-scope evidence
- **Responsibility:** Prove mandatory manifest/lockfile/source/test targets are present and
  read/write sets are nonconflicting and sufficient.

## `ResolveTaskInternalReferenceAction`

- **Input:** one internal-key dependency or red-to-green target and assigned task-ID map
- **Output:** canonical task reference
- **Responsibility:** Resolve one internal key to one existing task ID.

## `DeriveTaskEvidenceAction`

- **Input:** task proposal, plan evidence expectations, canonical commands, preset evidence
  policy, and resolved task IDs
- **Output:** mandatory evidence-predicate values
- **Responsibility:** Construct closed values, including red-to-green targets, without
  model-owned canonical fields or IDs.

## `AssignTaskEvidencePredicateIdsAction`

- **Input:** one task ID, ordered predicate values, and task-definition allocator
- **Output:** identified evidence predicates
- **Responsibility:** Assign stable engine predicate IDs after every task/red-to-green target ID
  resolves.

## `ValidateTaskEvidencePredicateCompletenessAction`

- **Input:** identified predicates, task/plan expectations, file/command/scenario registries,
  and policy
- **Output:** predicate-completeness evidence
- **Responsibility:** Prove unique IDs, exact required coverage, valid joins, and no model-added
  completion condition.

## `BuildSharedResourceRegistryAction`

- **Input:** project/file/command adapter facts
- **Output:** shared-resource registry
- **Responsibility:** Build the closed set of resource IDs and modes.

## `ValidateTaskSharedResourceIdAction`

- **Input:** one engine-derived resource ID and shared-resource registry
- **Output:** resource-reference evidence
- **Responsibility:** Validate one known resource and compatible lock mode.

## `DeriveTaskResourceLocksAction`

- **Input:** task file/command sets and resource registry
- **Output:** mandatory lock records
- **Responsibility:** Derive locks implied by one task's operations.

## `BuildTaskDefinitionAction`

- **Input:** assigned task ID, validated proposal, canonical commands/evidence, and resource IDs
- **Output:** canonical task definition
- **Responsibility:** Construct one engine-owned task record.

## `AssignTaskFileCapabilityRegistryStateIdAction`

- **Input:** task-definition scope, validated current feature `StateIdLedger`, and matching
  single-use namespace capability
- **Output:** task-file-capability-registry reservation plus successor ledger
- **Responsibility:** Reserve one immutable registry ID after canonical task IDs exist.

## `BuildTaskFileCapabilityRecordAction`

- **Input:** canonical task/file/role, task-file-selection evidence, exact plan grant, file-kind
  ceiling, and global policy
- **Output:** task-file-capability record
- **Responsibility:** Materialize the exact per-task intersection without broadening plan
  authority.

## `BuildTaskFileCapabilityRegistryAction`

- **Input:** registry identity, all canonical tasks, and all capability records
- **Output:** task-file-capability-registry candidate
- **Responsibility:** Assemble the closed task/file matrix.

## `ValidateTaskFileCapabilityRegistryAction`

- **Input:** registry candidate, task graph, PlanState grants/file registry, and policy
- **Output:** task-file-capability evidence
- **Responsibility:** Prove total read/write coverage, exact intersections, no orphan records,
  and dependency mutation-surface sufficiency.

## `BuildFactTransitionBindingAction`

- **Input:** one transition-required plan fact, task graph, and transition-rule registry
- **Output:** fact-transition binding
- **Responsibility:** Bind one fact to one concrete task/rule after task IDs exist.

## `ValidateFactTransitionBindingAction`

- **Input:** one binding, plan fact, and task definition
- **Output:** transition-binding evidence
- **Responsibility:** Prove task scope/capability can perform the declared transition.

## `BuildTaskProposalGraphAction`

- **Input:** validated task proposals and internal-key dependency proposals
- **Output:** proposal graph
- **Responsibility:** Construct one pre-ID graph using internal keys only.

## `ValidateTaskDependencyProposalAction`

- **Input:** one operation-result-valid `TaskDependencyProposal`, current partition allowlist,
  and semantic-text validators
- **Output:** edge-proposal evidence
- **Responsibility:** Validate both internal keys and bounded reason without accepting a
  canonical basis or task ID.

## `BuildTaskProposalDependencyAction`

- **Input:** validated edge proposal and reconciliation invocation kind
- **Output:** canonical proposal edge
- **Responsibility:** Copy keys/reason and set `basis: semantic_reconciliation`; the model
  cannot choose basis.

## `ValidateTaskProposalDependencyTargetAction`

- **Input:** one canonical proposal edge and internal-key index
- **Output:** target evidence
- **Responsibility:** Reject an unknown/self internal key.

## `DetectTaskProposalCycleAction`

- **Input:** proposal graph
- **Output:** acyclicity evidence
- **Responsibility:** Detect pre-ID cycles only.

## `ValidateTaskProposalPhaseEdgeAction`

- **Input:** one proposal edge and phase policy
- **Output:** phase-edge evidence
- **Responsibility:** Apply phase direction rules before ID assignment.

## `TopologicallyOrderTaskProposalsAction`

- **Input:** validated acyclic proposal graph and stable tie-break policy
- **Output:** ordered internal keys
- **Responsibility:** Calculate one deterministic pre-ID order.

## `AssignCompactTaskIndexStateIdAction`

- **Input:** tasking scope, validated current feature `StateIdLedger`, and matching single-use
  namespace capability
- **Output:** compact-task-index reservation plus successor ledger
- **Responsibility:** Reserve one immutable index ID.

## `BuildCompactTaskIndexAction`

- **Input:** index identity and all validated provisional tasks
- **Output:** compact global task index
- **Responsibility:** Build one complete model-safe dependency index.

## `ValidateCompactTaskIndexAction`

- **Input:** compact index and all provisional proposals
- **Output:** compact-index evidence
- **Responsibility:** Prove one-to-one task coverage and exact projected
  phase/kind/obligation/file/mode fields.

## `AssignTaskDependencyPartitionStateIdAction`

- **Input:** compact-task-index ID, validated current feature `StateIdLedger`, and matching
  single-use namespace capability
- **Output:** task-edge-partition reservation plus successor ledger
- **Responsibility:** Reserve one immutable dependency partition-state ID.

## `AssignTaskBoundaryIndexStateIdAction`

- **Input:** compact-task-index identity, validated current feature `StateIdLedger`, and
  matching single-use namespace capability
- **Output:** task-boundary-index reservation plus successor ledger
- **Responsibility:** Reserve one engine-owned boundary-index state ID.

## `BuildTaskBoundaryIndexAction`

- **Input:** boundary-index identity, exact compact index, phase policy, shared write sets, and
  red-to-green links
- **Output:** task-boundary index
- **Responsibility:** Derive mechanical boundary facts without inventing semantic edges.

## `PartitionTaskDependencyIndexAction`

- **Input:** partition identity, compact index, boundary index, workflow-declared partition
  contract, and stable pair ordering
- **Output:** task-edge partitions
- **Responsibility:** Cover required semantic candidate pairs with bounded overlapping
  visibility sets.

## `ValidateTaskDependencyPartitionCoverageAction`

- **Input:** edge partitions, compact/boundary indexes, and partition contract
- **Output:** edge-partition evidence
- **Responsibility:** Prove every required pair/boundary appears in at least one partition and
  no unknown key appears; perform no model-call size-fit check.

## `MergeValidatedTaskDependencyAction`

- **Input:** one validated internal-key edge and proposal graph
- **Output:** updated proposal graph
- **Responsibility:** Merge one semantic dependency before final ordering.

## `ValidateTaskDependencyMergeCompletenessAction`

- **Input:** all partition outcomes, deduplicated validated edges, engine-derived/explicit
  edges, and edge-partition evidence
- **Output:** dependency-merge evidence
- **Responsibility:** Prove every partition completed, duplicate equal edges coalesced,
  conflicting reasons/bases diagnosed, and no proposed edge was dropped.

## `BuildTaskDependencyAction`

- **Input:** one validated proposal edge and both exact internal-key-to-task-ID resolutions
- **Output:** canonical task dependency
- **Responsibility:** Replace both keys with task IDs while preserving the engine-owned basis
  and validated reason.

## `ValidateTaskDependencyConversionCompletenessAction`

- **Input:** all canonical dependencies, final proposal edges, and task-ID map
- **Output:** dependency-conversion evidence
- **Responsibility:** Prove one-to-one edge conversion, no duplicate/orphan edge, and exact
  basis/reason preservation.

## `BuildTaskGraphAction`

- **Input:** canonical tasks and ID-resolved dependency/lock records
- **Output:** canonical task graph
- **Responsibility:** Construct one final graph using task IDs only.

## `ValidateCanonicalTaskGraphAction`

- **Input:** canonical graph and internal-key-to-task-ID map
- **Output:** canonical-graph evidence
- **Responsibility:** Recheck node/edge/lock completeness, phase rules, and acyclicity after
  resolution.

## `CalculateParallelEligibilityAction`

- **Input:** one task pair, DAG, paths, locks
- **Output:** pair eligibility evidence
- **Responsibility:** Decide one pair's concurrency eligibility.

## `CalculateRunnableSetAction`

- **Input:** current task graph and execution-local runtime/evidence
- **Output:** ordered eligible task IDs
- **Responsibility:** Compute readiness from current dependency and resource facts.

## `SelectRunnableTaskAction`

- **Input:** validated runnable set
- **Output:** selected task
- **Responsibility:** Select deterministically under the declared scheduling policy.

## `ClaimTaskLeaseAction`

- **Input:** selected task and current resource state
- **Output:** execution-local lease proposal
- **Responsibility:** Reserve only the approved task's resources; the runner validates/applies
  the transition.


The remaining implementation actions are proposed responsibilities, not a second
runtime registry. Their closed operation contracts must enforce Sections 20–22
and 26 before being registered:

- Build and validate one immutable task context from approved file IDs, current
  repository facts, exact principle selections and authorized copy sources.
- Build and validate an ordered operation-intent plan; assign intent, attempt,
  operation and evidence IDs inside the current execution.
- Authorize one file operation with exact target state, revision, capability and
  declared effects. Separate actions create its private savepoint, apply it,
  validate the result, and promote or discard candidate changes.
- Derive one named command descriptor and validate its authorization. Separate
  actions create command isolation, execute once through a shell-disabled port,
  validate result/effects, and clean up the complete process tree and scratch.
- Validate explicit manual-evidence submissions and single-use authentication
  before building evidence bound to the exact task, predicate, scenario and
  current input revisions. Models cannot supply observer identity or approval.
- Append validated operation/command/manual evidence to the execution-local
  evidence owner and validate all required predicates before building a task
  result. Failed, blocked, cancelled and validated task results remain distinct.
- Authorize only the failed independently replaceable unit for repair; rebuild
  the candidate from current accepted in-memory values and revalidate impacted
  dependencies plus the whole candidate.
- Run complete final validation and build the final workflow output. Release
  leases, locks, processes, handles and candidate resources on every terminal
  path. Rejected or missing cleanup evidence cannot become success.

A task result is not independently published or resumable. Current-execution
savepoints, resource exclusion, revision checks and executable evidence remain
required. The former durable task-adapter records, promotion receipts,
checkpoint/replay plans, recovery inventories and per-task transaction actions
are withdrawn by ADR 0009; no renamed equivalent is permitted. Section 25 owns
the sole successful output boundary.
