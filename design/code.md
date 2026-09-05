# Deterministic SDD Engine contract and data-shape samples

This companion contains the sample contracts, schemas, configuration, flow notation, and package layout referenced by [the engine design](design.md). The design document is normative; these samples illustrate its contracts and must evolve with it.

Clarification identity is independent of execution identity. Its complete
registry, forms, and responses persist across successive workflows and are
consumed after current applicability checks. `implement` cannot execute while
any specification, planning, or tasks clarification remains outstanding.

The `text` blocks use language-neutral SDDE contract notation; they are not
TypeScript or JavaScript source. In the Zig implementation, closed `A | B`
variants map to `union(enum)`, exhaustive branches map to `switch`, optional
values map to `?T`, and unexpected operational failures map to error unions.
`immutable` means runner-owned storage exposed through bounded const views, not
merely a const binding. Generic-looking forms such as `DataKey<T>` describe a
typed relationship that Zig must enforce at compile time; they do not authorize
an unchecked heterogeneous map or runtime reflection. Target-project YAML/JSON
examples may still mention TypeScript, JavaScript, or Node because those are
environments the Zig engine governs.

Result carriers in `text` blocks are engine-side types, not automatic JSON
schemas. For example, `{kind, proposal}` does not require a wire `proposal`
wrapper. Under [ADR 0006](decisions/0006-minimal-model-response.md), the selected
response schema omits fixed unit tags already bound by the engine and exposes
the candidate fields directly. Meaningful nested objects, discriminators and
collections remain; there is no generic flattening of arbitrary model JSON.

## Contents

1. [Pipeline node contracts](#pipeline-node-interfaces)
2. [Capability-free node runtime](#node-runtime)
3. [Node contract and typed data keys](#node-contract-and-data-keys)
4. [Pipeline envelope](#pipeline-envelope)
5. [Pipeline outcome](#pipeline-outcome)
6. [Shared domain types](#shared-domain-types)
   - [Authority reconciliation contract](#authority-reconciliation-contract)
7. [Specification IR](#specification-ir)
8. [Reference-context IR](#reference-context-ir)
9. [Plan IR](#plan-ir)
10. [Artifact decision](#artifact-decision)
11. [Task IR](#task-ir)
12. [Implementation IR](#implementation-ir)
13. [Diagnostic contract](#diagnostic-contract)
14. [Engine configuration](#engine-configuration)
15. [Preset identity and composition](#preset-identity-and-composition)
16. [Project discovery policy](#project-discovery-policy)
17. [File-kind policies](#file-kind-policies)
18. [Structured commands](#structured-commands)
19. [AST and parser policy](#ast-and-parser-policy)
20. [Generated and forbidden paths](#generated-and-forbidden-paths)
21. [Initial guidance packet](#initial-guidance-packet)
22. [Model response envelope](#model-response-envelope)
23. [Model context request](#model-context-request)
24. [Orchestrator composition](#orchestrator-composition)
25. [Bootstrap flow](#bootstrap-flow)
26. [Reference reader contract](#reference-reader-contract)
27. [Specify CLI contract](#specify-cli-contract)
28. [Repair authorization](#repair-authorization)
29. [Repair request](#repair-request)
30. [Repair response](#repair-response)
31. [Clarification file contract](#clarification-file-contract)
32. [Workflow state](#workflow-state)
33. [Stage transition state machine](#stage-transition-state-machine)
34. [Observability events](#observability-events)
35. [Suggested package structure](#suggested-package-structure)

---

<a id="pipeline-node-interfaces"></a>

## 1. Pipeline node contracts

```text
contract PipelineNode {
  contract: NodeContract
  execute(
    envelope: PipelineEnvelope,
    runtime: NodeRuntime
  ) -> Outcome
}

contract Action conforms PipelineNode {
  contract.kind = "action"
  // Has no children, node runner, dispatcher, or orchestrator reference.
}

contract Orchestrator conforms PipelineNode {
  contract.kind = "orchestrator"
  childBindings: immutable sequence<ChildNodeBinding>
  // May invoke/schedule only runner-owned bindings and branch on Outcome metadata.
  // Has no filesystem, model, parser, validator, renderer, state, or process port.
}

contract ChildNodeBinding {
  contract: ImmutableNodeContract
  invoke(envelope: PipelineEnvelope, runtime: NodeRuntime) -> AppliedChildOutcome
  // Created only by PipelineRunner. Invocation always performs contract checks,
  // node-ID/attempt updates, delta application, and telemetry.
}

ImmutableNodeContract = Immutable<NodeContract>

Immutable<T> {
  // Type-system utility: every scalar/field/collection reachable from T is
  // immutable. It has no runtime mutation or reflection capability.
}

PipelineOutcomeStatus = ok | needs_user | invalid | blocked | failed | cancelled

AppliedChildOutcome {
  status: PipelineOutcomeStatus,
  nextEnvelope,          // runner-created by applying the child's one NodeDelta
  candidateDelta?        // available only on the invalid branch for authorized repair
}
```

---

<a id="node-runtime"></a>

## 2. Capability-free node runtime

```text
NodeRuntime {
  cancellationToken,
  deadline,
  correlationContext,
  traceContext
}

RunnerLifecycleEvent =
  | { kind: run_started | run_completed | run_needs_user | run_blocked | run_failed,
      runId, featureId?, stage, observedAt, durationMs? }
  | { kind: node_started | node_completed | node_invalid | node_blocked |
            node_needs_user | node_failed | node_cancelled,
      runId, featureId?, stage, nodeId, nodeContractId, attempt,
      observedAt, durationMs? }

TrustedNodeContext {
  runId,
  featureId?,
  stage,
  nodeId,
  nodeContractId,
  attempt,
  parentNodeId?,
  correlationId
  // Constructed only by PipelineRunner and never accepted from a node/model.
}

port PipelineTelemetryObserver {
  observeRunnerLifecycle(workflowLog: WorkflowLog,
                         event: RunnerLifecycleEvent) -> void
  observeAppliedDelta(context: TrustedNodeContext,
                      facts: immutable sequence<WorkflowTelemetryFact>) -> void
  // Owned by PipelineRunner. It is not a PipelineNode and is not reachable
  // from Action, Orchestrator, NodeRuntime, or model-facing data.
}

port FeatureLogPort {
  acquireStreamLock(binding: FeatureLogBinding, stream, lockPolicy)
    -> FeatureLogStreamLockObservation
  inspect(binding: FeatureLogBinding, stream,
          lock: FeatureLogStreamOperationLockCapability)
    -> FeatureLogStreamInspection
  createInitialSegment(segmentIdentity: FeatureLogSegmentIdentity,
                       binding: FeatureLogBinding,
                       lock: FeatureLogStreamOperationLockCapability,
                       policy: FeatureLogPolicy)
    -> FeatureLogSegmentCreationObservation
  recoverTail(binding: FeatureLogBinding, stream,
              lock: FeatureLogStreamOperationLockCapability,
              policy: FeatureLogPolicy)
    -> RecoveredFeatureLogStreamObservation
  closeForPolicyTransition(
      transition: FeatureLogPolicyTransition,
      currentBinding: FeatureLogBinding,
      currentStreamState: FeatureLogStreamState,
      lock: FeatureLogPolicyTransitionStreamLockCapability)
    -> FeatureLogPolicyTransitionCloseObservation
  closeHistoricalTailAfterCrash(
      historicalBinding: FeatureLogBinding,
      recoveredStreamState: FeatureLogStreamState,
      lock: FeatureLogStreamLockCapability,
      historicalPolicy: FeatureLogPolicy)
    -> HistoricalFeatureLogTailCloseObservation
  append(frame: SerializedFeatureLogFrame,
         binding: FeatureLogBinding,
         lock: FeatureLogStreamLockCapability,
         expectedStreamState: FeatureLogStreamState,
         flushPolicy)
    -> FeatureLogSinkState
  rotate(authorization: LogRotationAuthorization,
         lock: FeatureLogStreamLockCapability)
    -> FeatureLogSinkState
  prune(authorization: LogRetentionAuthorization,
        lock: FeatureLogStreamLockCapability)
    -> FeatureLogSinkState
  flush(featureId, runId, stream, lock: FeatureLogStreamLockCapability)
  releaseStreamLock(lock: FeatureLogStreamLockCapability)
    -> FeatureLogStreamLockReleaseObservation
  releasePolicyTransitionStreamLock(
      lock: FeatureLogPolicyTransitionStreamLockCapability)
    -> FeatureLogPolicyTransitionStreamLockReleaseObservation
  releaseRejectedStreamLockObservation(
      observation: FeatureLogStreamLockObservation,
      rejection: FeatureLogStreamLockRejection)
    -> FeatureLogRejectedLockCleanupObservation
}

port TaskExecutionOverlayPort {
  createOperationSavepoint(boundary: OperationApplyReadyBoundary,
                           key: TaskExecutionAdapterBoundaryRecordKey,
                           taskOverlayId, expectedTaskOverlayRevision)
    -> TaskExecutionAdapterBoundaryEntryObservation
  createCommandSavepoint(boundary: CommandRunReadyBoundary,
                         key: TaskExecutionAdapterBoundaryRecordKey,
                         taskOverlayId, expectedTaskOverlayRevision)
    -> TaskExecutionAdapterBoundaryEntryObservation
  promoteOperationSavepoint(
      boundary: OperationPromotionReadyBoundary,
      key: TaskExecutionAdapterBoundaryRecordKey,
      predecessorApplyBoundaryRecordKey: TaskExecutionAdapterBoundaryRecordKey,
      predecessorApplyBoundaryEntryRecordId: AdapterBoundaryEntryRecordId,
      promotionAuthorization: OperationPromotionAuthorization,
      expectedTaskOverlayRevision)
    -> TaskExecutionAdapterPromotionReceipt
  promoteCommandSavepoint(
      boundary: CommandRunReadyBoundary,
      key: TaskExecutionAdapterBoundaryRecordKey,
      commandEntry: TaskExecutionAdapterBoundaryEntryObservation,
      commandAuthorization: CommandAuthorization,
      expectedTaskOverlayRevision)
    -> TaskExecutionAdapterPromotionReceipt
  discardOperationSavepoint(entry: TaskExecutionAdapterBoundaryEntryObservation)
    -> TaskExecutionAdapterDiscardReceipt
  discardCommandSavepoint(entry: TaskExecutionAdapterBoundaryEntryObservation)
    -> TaskExecutionAdapterDiscardReceipt
  inspectWriteOnceBoundaryRecords(set: TaskExecutionAdapterBoundaryRecordSet)
    -> RecoveredTaskExecutionAdapterBoundaryObservation
  restoreExactBoundaryBeforeImages(receipt: TaskExecutionAdapterPromotionReceipt,
                                   taskOverlayId, expectedPromotedRevision)
    -> TaskExecutionAdapterRestoreReceipt
  releaseBoundaryRecords(
      authorization: TaskExecutionAdapterBoundaryRecordReleaseAuthorization)
    -> TaskExecutionAdapterBoundaryRecordReleaseObservation
  // Boundary entry/discard records are durable atomically with child publication/
  // removal. A promotion receipt and every exact before-image record are durable
  // before or atomically with publication of the parent-overlay revision. No
  // record may be deleted before a boundary-free checkpoint commit names it.
  // Every adapter metadata ID is the closed structural tuple declared below:
  // boundary key + fixed record kind + canonical effect ordinal/file where used.
  // Implementations may not substitute randomness, paths, timestamps, model
  // values, content-derived IDs, hashes, or an ambient adapter-side allocator.
}

port FeatureExecutionControlPort {
  acquireProcessLease(
      identity: FeatureExecutionProcessLeaseId,
      boundedLeasePolicy)
    -> FeatureExecutionProcessLeaseObservation
  acquireFeatureLock(
      activeFeatureDirectoryCapability: ActiveFeatureDirectoryCapability,
      processLease: FeatureExecutionProcessLeaseCapability,
      boundedLockPolicy)
    -> FeatureExecutionLockObservation
  inspectLeaseLiveness(
      ownerLeaseRefs: FeatureExecutionProcessLeaseOwnerRef[],
      currentProcessLease: FeatureExecutionProcessLeaseCapability,
      featureExecutionLock: FeatureExecutionLockCapability,
      overlayCollectionLock: FinalValidationOverlayCollectionLockCapability)
    -> FeatureExecutionProcessLeaseLivenessOutcome
  releaseFeatureLock(lock: FeatureExecutionLockCapability)
    -> FeatureExecutionLockReleaseObservation
  releaseProcessLease(lease: FeatureExecutionProcessLeaseCapability)
    -> FeatureExecutionProcessLeaseReleaseObservation
  releaseRejectedFeatureLockObservation(
      observation: FeatureExecutionLockAcquiredObservation,
      rejection: FeatureExecutionLockValidationRejection)
    -> FeatureExecutionRejectedCapabilityCleanupObservation
  releaseRejectedProcessLeaseObservation(
      observation: FeatureExecutionProcessLeaseAcquiredObservation,
      rejection: FeatureExecutionProcessLeaseValidationRejection)
    -> FeatureExecutionRejectedCapabilityCleanupObservation
  // Lease/lock capabilities are runner-held, nonserializable adapter tokens.
  // The adapter proves liveness through OS/process ownership rather than a
  // caller-supplied timestamp. Process death releases both capabilities; a
  // lease identity is never rebound to a later process or run.
}

port FinalValidationOverlayPort {
  acquireCollectionLock(
      collectionCapability,
      processLease: FeatureExecutionProcessLeaseCapability,
      featureExecutionLock: FeatureExecutionLockCapability,
      boundedLockPolicy)
    -> FinalValidationOverlayCollectionLockObservation
  createOverlay(header: FinalValidationOverlayLeaseHeader,
                headerValidation: FinalValidationOverlayLeaseHeaderValidation,
                collectionCapability,
                processLease: FeatureExecutionProcessLeaseCapability,
                featureExecutionLock: FeatureExecutionLockCapability,
                lock: FinalValidationOverlayCollectionLockCapability)
    -> FinalValidationOverlayCreationOutcome
  inspectBoundedInventory(collectionCapability, inventoryCeilings,
                          lock: FinalValidationOverlayCollectionLockCapability)
    -> FinalValidationOverlayStartupInventoryObservation
  discardOrphan(entry: OrphanedFinalValidationOverlayEntry,
                collectionCapability,
                lock: FinalValidationOverlayCollectionLockCapability)
    -> FinalValidationOverlayOrphanDiscardObservation
  discardCreationCandidate(
      invocationId: FinalValidationInvocationId,
      validationOverlayId,
      collectionCapability,
      lock: FinalValidationOverlayCollectionLockCapability)
    -> FinalValidationOverlayCreationCleanupObservation
  inspectCreationCandidateAfterCleanup(
      invocationId: FinalValidationInvocationId,
      validationOverlayId,
      collectionCapability,
      lock: FinalValidationOverlayCollectionLockCapability,
      inspectionCeilings)
    -> FinalValidationOverlayCreationCandidateInspection
  createFinalValidationCommandSavepoint(
      authorization: CommandAuthorization,
      savepointId: FinalValidationCommandSavepointId,
      parentHeader: FinalValidationOverlayLeaseHeader,
      expectedParentOverlayRevision,
      processLease: FeatureExecutionProcessLeaseCapability,
      featureExecutionLock: FeatureExecutionLockCapability)
    -> FinalValidationCommandSavepointCreationOutcome
  discardFinalValidationCommandSavepoint(
      creation: FinalValidationCommandSavepointCreationValidation,
      expectedChildOverlayRevision,
      processLease: FeatureExecutionProcessLeaseCapability,
      featureExecutionLock: FeatureExecutionLockCapability)
    -> FinalValidationCommandSavepointDiscardOutcome
  inspectFinalValidationCommandSavepointAfterDiscard(
      creation: FinalValidationCommandSavepointCreationValidation,
      expectedParentOverlayRevision,
      processLease: FeatureExecutionProcessLeaseCapability,
      featureExecutionLock: FeatureExecutionLockCapability)
    -> FinalValidationCommandSavepointPostDiscardInspection
  discardCurrent(header: FinalValidationOverlayLeaseHeader,
                 collectionCapability,
                 processLease: FeatureExecutionProcessLeaseCapability,
                 featureExecutionLock: FeatureExecutionLockCapability)
    -> FinalValidationOverlayDiscardOutcome
  releaseCollectionLock(lock: FinalValidationOverlayCollectionLockCapability)
    -> FinalValidationOverlayCollectionLockReleaseOutcome
  releaseRejectedCollectionLockObservation(
      observation: FinalValidationOverlayCollectionLockAcquired,
      rejection: FinalValidationOverlayCollectionLockValidationRejection)
    -> FinalValidationOverlayRejectedCollectionLockCleanupOutcome
  // The complete write-once lease header is atomically published and durable
  // before overlay publication; partial header staging is never enumerable. A prior
  // run's overlay is never reopened or promoted; cleanup is idempotent and may
  // delete only a structurally valid entry returned by the bounded inventory
  // and classified orphaned by the separately validated OS-backed liveness
  // registry under the same collection-lock epoch. Final-validation command
  // children are created/discarded only beneath that current validated parent;
  // they never create task adapter-boundary records and are swept with the
  // parent after a crash. Every method returns a closed raw outcome, including
  // adapter failure; no exception or missing observation is treated as proof
  // of absence. The collection lock is an OS/process-owned,
  // nonrebindable capability released automatically on owner-process death;
  // a fresh runner can reacquire only a new epoch before orphan inspection.
}

port AuthenticationPort {
  authenticateAndConsume(authenticationLeaseRef, requiredAssurancePolicyId)
    -> AuthenticationObservation
  // The runner-owned lease table holds the credential handle outside every
  // PipelineEnvelope. authenticationLeaseRef is opaque, nonserializable,
  // nonloggable, single-use, and never model-visible. The adapter must destroy
  // the backing handle on return, throw, timeout, or cancellation.
}
```

---

<a id="node-contract-and-data-keys"></a>

## 3. Node contract and typed data keys

```text
NodeContract {
  id,
  version,
  kind: action | orchestrator,
  requires: DataKey[],
  optional: DataKey[],
  produces: DataKey[],
  replaces: DataKey[],
  invalidates: DataKey[],
  sideEffect: none | read | candidate-write | commit-write | model-call | command,
  runnerAccountingCapability:
    | { kind: none }
    | { kind: emit_exactly_one,
        transitionKind: increment_model_attempt |
                        increment_atomic_repair_attempt |
                        reconcile_workflow_tokens |
                        advance_provider_operation |
                        consume_no_invention_replacement },
  retryLimitContract?: { parameterId, operationLocalMaximum },
  orderingBarriers[]
}

Runner accounting capability registry:
  AdvanceModelAttemptAccountingAction -> increment_model_attempt
  AdvanceAtomicRepairAttemptAccountingAction -> increment_atomic_repair_attempt
  ReconcileWorkflowTokenUsageAction -> reconcile_workflow_tokens
  AdvanceProviderOperationLifecycleAction -> advance_provider_operation
  ValidateRepairScopeAction -> consume_no_invention_replacement only when its
    authorization purpose is no_invention_to_clarification
  every other action/orchestrator -> none

Compiler-locked model-request ledger DataKey ownership:
  BuildInitialModelRequestIdentityLedgerAction -> produces
    DataKey<ModelRequestIdentityLedger>("model.request_identity_ledger", "1")
  AssignModelRequestIdAction -> replaces that key by exact revision CAS
  AdvanceModelRequestLifecycleAction -> replaces that key by exact revision CAS
  every other action/orchestrator -> cannot produce or replace that key

DataKey<T> {
  id,                 // e.g. "spec.ir"
  schemaVersion,      // e.g. "1"
  valueSchema
}

contract ImmutableDataRegistry<K, V> {
  contains(key: K) -> boolean
  get(key: K) -> Immutable<V> | absent
  keys() -> immutable sequence<K>
  // No set/delete/mutable-reference operation; PipelineRunner alone applies
  // validated NodeDelta values into a successor registry.
}

Evidence {
  evidenceId,
  evidenceTypeId,
  schemaVersion,
  ownerStateId,
  typedPayloadHandle
  // The handle resolves through the runner's closed evidence-schema registry;
  // arbitrary maps or untyped messages are not valid payloads.
}
```

---

<a id="pipeline-envelope"></a>

## 4. Pipeline envelope

```text
PipelineEnvelope {
  run: {
    runId,
    featureId?,
    stage,
    nodeId,
    attempt,
    operationAccounting: {
      stageRunEpochId,
      modelAttemptOrdinalsByRequestId: Map<ModelRequestId, NonnegativeInteger>,
      retriesUsedByOperationInstanceId:
        Map<CompiledWorkflowOperationInstanceId, NonnegativeInteger>,
      noInventionReplacementUsedByUnitId: Set<ImmutableUnitOwnerId>
    },
    workflowTokenAccounting: {
      totalModelTokenBudget,
      committedTokens,
      usageUnavailable,
      accountedProviderOperationIds
    }
  },
  workspace: {
    canonicalProjectRoot,
    compiledRootAccessRegistryId,
    activeFeatureDirectoryCapabilityId?,
    // Feature artifacts never share an ambient root string. Nodes resolve the
    // ID only through the exact validated capability in the data registry,
    // whose specs-feature, engine-feature, and engine-state roots are distinct.
    environmentIds
  },
  policy: {
    configVersion,
    rendererContractVersion,
    compiledPresetIds,
    validationProfile
  },
  data: ImmutableDataRegistry<DataKey, value>,
  // The compiler-owned model.request_identity_ledger/v1 DataKey lives here;
  // PipelineRunner alone applies its authorized immutable successor delta.
  evidence: Evidence[],
  diagnostics: Diagnostic[]
}
```

---

<a id="pipeline-outcome"></a>

## 5. Pipeline outcome

```text
Outcome {
  status: PipelineOutcomeStatus,
  delta: NodeDelta,
  candidateDelta?        // retained off the committed data path for repair
}

NodeDelta {
  dataWrites[],
  dataReplacements[],
  dataInvalidations[],
  evidenceAdded: Evidence[],
  diagnosticsAdded: Diagnostic[],
  telemetryFactsAdded: WorkflowTelemetryFact[],
  runnerAccountingTransition?: RepairAccountingTransition
}

RepairAccountingTransition =
  | IncrementModelAttempt {
      stageRunEpochId, modelRequestId, expectedOrdinal, nextOrdinal,
      initialOrRetry,
      retryOperationInstanceId?, expectedRetryValue?, nextRetryValue?,
      explicitRetryLimit?
    }
  | IncrementAtomicRepairAttempt {
      stageRunEpochId, retryOperationInstanceId,
      expectedRetryValue, nextRetryValue, explicitRetryLimit
    }
  | ReconcileWorkflowTokens {
      workflowExecutionId, providerOperationId,
      expectedLedgerRevision,
      recordActualInputAndOutput | provenNotSent | usageUnavailable
    }
  | AdvanceProviderOperation {
      expectedLedger, expectedLedgerRevision,
      providerOperationId, expectedOperationRevision?,
      assignCount | assignInference | invoke | terminate
      // Either assignment binds the request, model binding and exact input;
      // inference requires no prior count operation or count evidence.
      // Runner applies one immutable successor after validating request and
      // attempt revisions. Its non-content journal projection is an intent,
      // not proof of persistence or result consumption.
    }
  | ConsumeNoInventionReplacement {
      stageRunEpochId,
      immutableUnitOwnerId,
      expectedAbsent: true,
      nextPresent: true
    }

// PipelineRunner accepts this field only from the compiler-registered accounting
// action contract, validates compare-and-swap and hard ceilings, and constructs
// the next envelope. It is not a general node-controlled runner mutation.

TelemetryFact =
  | RunStartedFact
  | RunCompletedFact { outcome, durationMs? }
  | RunBlockedFact { diagnosticCode, outcome }
  | RunFailedFact { diagnosticCode, outcome }
  | RunCancelledFact { outcome }
  | StageStartedFact
  | StageCompletedFact { outcome, durationMs? }
  | StageBlockedFact { diagnosticCode, outcome }
  | StageFailedFact { diagnosticCode, outcome, durationMs? }
  | StageClarificationPendingFact { outcome }
  | ActionStartedFact
  | ActionCompletedFact { outcome, durationMs? }
  | ActionInvalidFact { diagnosticCode, outcome }
  | ActionFailedFact { diagnosticCode, outcome, durationMs? }
  | ModelRequestedFact { modelOperationId, modelSlotId }
  | ModelCompletedFact { modelOperationId, modelSlotId, outcome,
                         inputTokens?, outputTokens?, durationMs? }
  | ModelProtocolFailedFact { modelOperationId, modelSlotId,
                              diagnosticCode, outcome }
  | ModelSchemaFailedFact { modelOperationId, modelSlotId,
                            diagnosticCode, outcome }
  | ValidationCompletedFact { validatorId, outcome, count?, durationMs? }
  | ValidationFailedFact { validatorId, diagnosticCode, outcome, count? }
  | RepairRequestedFact { repairUnitKind }
  | RepairAppliedFact { repairUnitKind, outcome }
  | RepairRejectedFact { repairUnitKind, diagnosticCode, outcome }
  | RepairExhaustedFact { repairUnitKind, diagnosticCode, outcome }
  | ReviewRequestedFact
  | ReviewApprovedFact { outcome }
  | ReviewRejectedFact { outcome }
  | TransactionPreparedFact { transactionId, count }
  | TransactionApplyingFact { transactionId, count }
  | TransactionCommittedFact { transactionId, count, outcome }
  | TransactionRolledBackFact { transactionId, diagnosticCode,
                                outcome, count? }
  | TransactionRecoveredFact { transactionId, outcome, count? }
  | CommandStartedFact { commandId }
  | CommandCompletedFact { commandId, outcome, exitCode?, durationMs? }
  | CommandFailedFact { commandId, diagnosticCode, outcome,
                        exitCode?, durationMs? }
  | TaskStartedFact { taskId }
  | TaskCompletedFact { taskId, outcome, durationMs? }
  | TaskBlockedFact { taskId, diagnosticCode, outcome }
  | TaskFailedFact { taskId, diagnosticCode, outcome, durationMs? }
  | SecurityDeniedFact { ruleId, diagnosticCode, outcome }

// Each variant maps one-to-one, by lower-snake variant name to dotted event
// type, to the exhaustive F0002 Section 6.2 registry. Its payload is exactly
// that row's required/optional field set. model.prompt_fragment is not a
// TelemetryFact; it is produced only by the separate sanitization pipeline.
// Common identity/time/context is runner-supplied. Facts contain no body,
// arbitrary message/map/list, shortcode, sensitivity, or level.
```

---

<a id="shared-domain-types"></a>

## 6. Shared domain types

```text
StateIdentityScope = feature

StateIdNamespaceDescriptor {
  namespaceId,
  stateTypeId,
  scope: StateIdentityScope,
  allocationMode: monotonic_ordinal,
  registryVersion
  // The compiler-locked registry contains exactly one descriptor for every
  // feature-scoped canonical authority type. BootstrapRootRegistry and its fixed
  // FeatureIdentityRegistryState revision chain are project-level tuple exceptions
  // outside this registry. Owner-local principle,
  // preset, reference, specification, clarification, plan, and task-execution
  // child IDs are disjoint and use only their named specialized ledgers. A
  // model, preset, config file, or orchestrator cannot add/select a namespace.
}

StateIdentityOwner = FeatureStateIdentityOwner { featureId }

CanonicalStateId {
  owner: StateIdentityOwner,
  namespaceId,
  ordinal: PositiveInteger
  // Identity is an engine-owned tuple, never a content/path fingerprint.
}

StateIdPurposeKey =
  | FeatureActivationStatePurpose {
      featureId,
      inputFeatureIdentityRegistryStateId,
      inputFeatureIdentityRegistryStateRevision,
      stateTypeId,
      transitionSlotId
    }
  | WorkflowStageStatePurpose {
      featureId,
      inputWorkflowStateId?,
      inputWorkflowStateRevision?,
      transitionKind,
      stateTypeId,
      transitionSlotId
    }
  | TaskExecutionStatePurpose {
      taskDefinitionStateId,
      taskId,
      inputTaskRuntimeRevision,
      taskExecutionAttemptId?,
      stateTypeId,
      transitionSlotId
    }
  // transitionSlotId resolves through the compiler-locked state-type/transition
  // slot registry; it is never free text or caller supplied.

StateIdAllocationRecord {
  canonicalStateId: CanonicalStateId,
  purposeKey: StateIdPurposeKey,
  status: reserved | committed | retired,
  reservationRevision,
  terminalTransactionId?
}

StateIdLedger =
  FeatureStateIdLedger {
      ledgerStateId: { featureId, ledgerRevision },
      featureId,
      ledgerRevision,
      nextOrdinalByNamespace: Map<namespaceId, PositiveInteger>,
      allocations: StateIdAllocationRecord[]
    }

StateIdNamespaceCapability {
  owner,
  namespaceDescriptor: StateIdNamespaceDescriptor,
  inputLedgerStateId,
  inputLedgerRevision,
  purposeKey: StateIdPurposeKey,
  singleUse: true
}

StateIdentityMutation =
  | UnchangedStateIdentityLedger { currentLedger: StateIdLedger }
  | InitializedFeatureStateIdentityLedger {
      featureId,
      nextLedger: StateIdLedger,
      validatedInitialReservationIds[]
    }
  | AdvancedStateIdentityLedger {
      inputLedgerStateId,
      inputLedgerRevision,
      nextLedger: StateIdLedger,
      reservedIds[], committedIds[], retiredIds[]
    }

StateIdentityTransactionMember {
  stateIdentityMutations: StateIdentityMutation[]
  // Exactly one mutation per touched owner. Every state ID newly referenced by
  // the transaction is reserved/committed here; untouched ledgers use the
  // Unchanged variant and never receive a no-op revision.
}

TransactionStorageOwner {
  featureId,
  workflowArtifactRegistryStateId
}

DurableTransactionKind =
  bootstrap_authority_refresh |
  state_identity_reservation | state_identity_retirement |
  specification_acknowledgement_id_retirement |
  clarification_pause | clarification_response |
  clarification_authority_resolution | specify_completion |
  plan_input_authority | plan_candidate | tasks_candidate |
  reference_revision | rework_invalidation | final_validation_failed |
  localized_task_remediation | implementation_reconciliation |
  implementation_completion | review_decision | task_checkpoint |
  manual_verification | task_success | task_outcome

TransactionId {
  storageOwner: TransactionStorageOwner,
  transactionOrdinal: PositiveInteger
}

TransactionIdLedger {
  storageOwner: TransactionStorageOwner,
  revision,
  nextTransactionOrdinal,
  reservations: {
    transactionId: TransactionId,
    transactionKind: DurableTransactionKind,
    status: reserved | committed | retired
  }[],
  retiredTransactionIds[]
}

TransactionIdentityMember {
  transactionId: TransactionId,
  inputTransactionIdLedgerRevision,
  nextTransactionIdLedger: TransactionIdLedger
  // Reservation is durably CAS-persisted under the collection lock before a
  // journal path is created; the owning transaction commits or later retires it.
}

TransactionIdentityRecoveryDisposition =
  | RetireOrphanReservation { transactionId, reason: reserved_without_journal }
  | RollbackAndRetire { transactionId, journalId, reason: uncommitted_journal }
  | RecoverCommitId { transactionId, journalId, reason: committed_marker_with_reserved_id }
  | VerifyCommitted { transactionId, journalId }
  | BlockTransactionIdentityRecovery {
      transactionId?, journalId?, diagnosticCode
    }

TransactionIdentityRecoveryPlan {
  storageOwner: TransactionStorageOwner,
  inputTransactionIdLedgerRevision,
  dispositions: TransactionIdentityRecoveryDisposition[]
  // One disposition per ledger reservation and journal, sorted by ordinal;
  // impossible/duplicate/cross-owner combinations have only the block variant.
}

DurableTransactionMember =
  StateIdentityTransactionMember & TransactionIdentityMember

ImmutableUnitOwnerId =
  | ReferenceChunkOwner { kind: reference_chunk, referenceStateId, chunkId }
  | ReferenceGlobalOwner { kind: reference_global, referenceStateId, unitSlotId }
  | SpecificationUnitOwner {
      kind: specification_unit, referenceStateId, featureRequestId, unitSlotId
    }
  | PlanUnitOwner { kind: plan_unit, planInputAuthorityStateId, unitSlotId }
  | TaskClusterOwner { kind: task_cluster, planStateId, obligationClusterId }
  | ImplementationOperationOwner {
      kind: implementation_operation,
      taskDefinitionStateId, taskId, operationIntentId
    }
  | SemanticReviewOwner {
      kind: semantic_review,
      parentUnitOwnerId: ImmutableUnitOwnerId, reviewSlotId
    }

ModelRequestId =
  | InitialGenerationModelRequestId {
      stageRunEpochId,
      immutableUnitOwnerId: ImmutableUnitOwnerId,
      modelOperationId,
      purpose: initial_generation,
      requestOrdinal: PositiveInteger
    }
  | AtomicRepairModelRequestId {
      stageRunEpochId,
      immutableUnitOwnerId: ImmutableUnitOwnerId,
      modelOperationId,
      purpose: atomic_repair,
      repairAuthorizationId,
      requestOrdinal: PositiveInteger
    }
  | SemanticReviewModelRequestId {
      stageRunEpochId,
      immutableUnitOwnerId: SemanticReviewOwner,
      modelOperationId,
      purpose: semantic_review,
      semanticReviewSlotId,
      requestOrdinal: PositiveInteger
    }
  | ClarificationResolutionModelRequestId {
      stageRunEpochId,
      immutableUnitOwnerId: ImmutableUnitOwnerId,
      modelOperationId,
      purpose: clarification_resolution,
      clarificationStateId,
      clarificationStateRevision,
      clarificationId,
      requestOrdinal: PositiveInteger
    }
  | ContextFollowupModelRequestId {
      stageRunEpochId,
      immutableUnitOwnerId: ImmutableUnitOwnerId,
      modelOperationId,
      purpose: context_followup,
      parentModelRequestId,
      validatedContextRequestOrdinal,
      requestOrdinal: PositiveInteger
    }
  // Protocol retries retain the same logical variant/ID and consume another
  // attempt on it; no variant contains an optional or untyped purpose owner.

ModelRequestIdentityLedger {
  stageRunEpochId,
  revision,
  nextOrdinalByUnitOperationPurpose,
  records: {
    modelRequestId: ModelRequestId,
    status: assigned | invoked | terminal,
    terminalReason?: accepted | needs_user | invalid_exhausted | blocked |
                     failed | cancelled | not_invoked_authorization_failure
  }[]
  // Run-local immutable envelope data; every assignment returns a successor.
}

PrincipleCategoryHint =
  | core | architecture | project_structure | security | validation |
    observability | user_interface | custom

PrincipleBootstrapIdNamespace =
  budget_ledger_state | inventory_entry | source | source_map | module | chunk |
  inventory_state | registry_state

PrincipleIdLedger {
  ownerBootstrapRootRegistryId,
  revision,
  nextOrdinalByNamespace: Map<PrincipleBootstrapIdNamespace, PositiveInteger>,
  retiredIdsByNamespace: Map<PrincipleBootstrapIdNamespace, EngineId[]>
  // Inventory-entry retention uses normalized path/node/metadata available
  // before read. Source/map/module/chunk retention additionally requires direct
  // raw-byte/span equality after capture. New/changed identities allocate;
  // removed/failed allocations are tombstoned.
}

PrincipleInventoryNodeKind = directory | regular_file | symlink | special

PrincipleInventoryEntry {
  principleInventoryEntryId,
  observedRelativePath,          // engine-only bootstrap path
  normalizedRelativePath,
  nodeKind: PrincipleInventoryNodeKind,
  noFollowFileIdentity?,
  reportedByteLength?,
  pathEvidenceId?,
  blockingDiagnosticId?
}

PrincipleCaptureBudgetSession {
  bootstrapAttemptId,
  ceilings: { maxEntries, maxDepth, maxSourceBytes, maxTime,
              maxMemoryBytes, maxChunks },
  nextReservationOrdinal,
  reservations: {
    provisionalReservationId, principleInventoryEntryId, reservedBytes,
    status: reserved | debited | released,
    actualBytes?, terminalFact?
  }[],
  totalReservedBytes,
  totalDebitedBytes
  // Run-local validated accounting only; it is never serialized as authority.
}

PrincipleSourceBudgetLedger {
  budgetLedgerStateId,
  revision,
  ceilings: { maxEntries, maxDepth, maxSourceBytes, maxTime,
              maxMemoryBytes, maxChunks },
  nextReservationOrdinal,
  reservations: {
    reservationId, principleInventoryEntryId, reservedBytes,
    status: reserved | debited | released,
    actualBytes?,
    terminalFact?:
      | { kind: debited, noFollowFileIdentity, completeRead: true }
      | { kind: released, diagnosticCode }
  }[],
  retiredReservationIds[],
  totalReservedBytes,
  totalDebitedBytes
}

PrincipleRawCaptureObservation {
  principleInventoryEntryId,
  noFollowFileIdentity,
  immutableBytesHandle,
  observedByteLength,
  completeRead: true
  // Contains no principleSourceId or sourceMapId.
}

PrincipleCapturedSource {
  principleSourceId,
  principleInventoryEntryId,
  immutableBytesHandle,
  byteLength,
  debitBinding: {
    reservationId,
    budgetLedgerStateId,
    budgetLedgerRevision,
    actualBytes,
    noFollowFileIdentity,
    completeRead: true
  }
}

PrincipleSourceMap {
  sourceMapId,
  principleSourceId,
  byteLength,
  lineSpans: { lineNumber, startByte, endByte }[]
}

PrincipleInventoryEntryDisposition =
  | { kind: directory_accounted }
  | { kind: mechanical_toolchain_layer_excluded, projectToolchainLayerPathId }
  | { kind: blocking, diagnosticId }
  | { kind: captured_source, principleSourceId }
  // captured_source is legal only for a normalized bounded *.md regular file;
  // every other regular file except exact toolchain.yaml is blocking.

PrincipleInventoryState {
  principleInventoryStateId,
  revision,
  principlesRootPathId,
  projectToolchainLayerPathId, // exact <paths.principles>/toolchain.yaml
  idLedger: PrincipleIdLedger,
  entries: PrincipleInventoryEntry[],
  sourceBudgetLedger: PrincipleSourceBudgetLedger,
  capturedSources: PrincipleCapturedSource[],
  sourceMaps: PrincipleSourceMap[],
  accounts: {
    principleInventoryEntryId,
    disposition: PrincipleInventoryEntryDisposition
  }[]
}

PrincipleSourceSpan {
  principleSourceId,
  startByte,
  endByte,
  startLine?,
  endLine?
}

PrincipleModule {
  principleModuleId,
  principleSourceId,
  sourceMapId,
  debitBinding,
  engineOwnedFilename,
  categoryHint: PrincipleCategoryHint,
  categoryMappingRuleId,
  rawUtf8BytesHandle,
  byteLength
  // The body is opaque, bounded free text. It requires no front matter,
  // heading, Markdown shape, placeholder substitution, or content schema.
  // The exact sibling `toolchain.yaml` can never produce a module or chunk.
}

PrincipleChunk {
  principleChunkId,
  principleModuleId,
  sourceSpan: PrincipleSourceSpan,
  rawUtf8BytesHandle,
  byteLength,
  boundaryKind: whole_file | paragraph | line_window | byte_window
  // Chunking is deterministic transport/indexing only; it assigns no meaning.
}

PrincipleRegistryState {
  principleRegistryStateId,
  revision,
  configVersion,
  principlesRootPathId,       // direct configured <paths.principles> root
  projectToolchainLayerPathId,
  categoryMappingVersion,
  idLedger: PrincipleIdLedger,
  inventory: PrincipleInventoryState,
  modules: PrincipleModule[],
  chunks: PrincipleChunk[]
}

ApplicablePrincipleSelection {
  principleSelectionId: {
    principleRegistryStateId,
    principleRegistryStateRevision,
    stage: plan | tasks | implement,
    immutableUnitOwnerId: ImmutableUnitOwnerId,
    consumerOrdinal
  },
  principleRegistryStateId,
  principleRegistryStateRevision,
  stage: plan | tasks | implement,
  immutableUnitOwnerId: ImmutableUnitOwnerId,
  consumerOrdinal,
  taskId?,
  fileKindIds[],
  selectedChunkIds[],
  requiredRawSpans: PrincipleSourceSpan[]
  // Selection is deterministic from configured filename category hints. Every
  // selected raw span must fit; the engine never substitutes a model summary.
}

SemanticText {
  nodes: (
    | LiteralText { value }
    | FileReference { fileId }
    | SourceReference { sourceId }
    | PassiveLiteralReference { passiveLiteralId }
  )[]
}

ReferenceSemanticText {
  nodes: (
    | LiteralText { value }
    | SourceReference { sourceId }
    | PassiveLiteralReference { passiveLiteralId }
  )[]
  // FileReference is deliberately not a variant in reference-owned content.
}

BusinessText {
  segments: (
    | BusinessLiteralText { value }
    | PassiveLiteralReference { passiveLiteralId }
  )[]                   // operational file/source references are not permitted
}

BusinessValue =
  | NormalizedBusinessValue { text: BusinessText }
  | ExactBusinessCopy { tokenId, citationId }

BusinessContentIdentity =
  | NormalizedContentIdentity {
      segments: (
        | LiteralContentIdentity { nfcUtf8BytesHandle, byteLength }
        | PassiveLiteralContentIdentity {
            passiveLiteralId, kind, nfcUtf8BytesHandle, byteLength
          }
      )[]
    }
  | ExactSourceContentIdentity { tokenId, rawUtf8BytesHandle, byteLength }

PassiveLiteralKind = external_uri | display_path | display_filename

PassiveLiteralReference { passiveLiteralId }

PassiveLiteralScalar {
  nfcUtf8BytesHandle,
  byteLength
}

PassiveLiteralOrigin =
  | ReferenceBlockSpan { referenceStateId, sourceId, blockId, location }
  | ReferenceManifestName { referenceStateId, sourceId }
  | UserClarificationResponseSpan {
      clarificationResponseId, startByte, endByte
    }
  | UserSpecificationRecord {
      acknowledgementId, recordKey, segmentIndex, startByte, endByte
    }

PassiveLiteralRecord {
  passiveLiteralId,
  kind: PassiveLiteralKind,
  display: PassiveLiteralScalar
}

PassiveLiteralOccurrence {
  passiveLiteralId,
  origin: PassiveLiteralOrigin
}

PassiveLiteralRegistryState {
  passiveLiteralRegistryStateId,
  featureId,
  revision,
  parentPassiveLiteralRegistryStateId?,
  scannerContractVersion,
  pathTokenGrammar: SupersetPathTokenGrammar,
  nextLiteralOrdinal,
  retiredLiteralIds[],
  literals: PassiveLiteralRecord[],
  occurrences: PassiveLiteralOccurrence[]
}

AuthenticatedActorRef {
  actorId,
  authenticationContextId
}

AuthenticatedEventKind =
  clarification_response | specification_edit | plan_review | tasks_review |
  manual_verification | reference_feedback | conflict_resolution

AuthenticationLeaseRef {
  leaseId,
  singleUse: true,
  serializable: false,
  loggable: false,
  modelVisible: false
}

AuthenticationObservation {
  actor: AuthenticatedActorRef,
  providerId,
  assurancePolicyId,
  authenticatedAt,
  expiresAt?
  // No engine evidence ID and no credential material.
}

AuthenticationObservationEvidence {
  providerRegistryId,
  requiredAssurancePolicyId,
  intendedEventKind: AuthenticatedEventKind,
  observedActor: AuthenticatedActorRef,
  observedAt,
  validAtEventTime: true,
  containsCredentialMaterial: false
  // Produced by ValidateAuthenticationObservationAction before ID allocation.
}

AuthenticationEvidenceId {
  featureId,
  authenticationEvidenceOrdinal: PositiveInteger
}

AuthenticationEvidenceIdAllocation {
  authenticationEvidenceId: AuthenticationEvidenceId,
  inputActorEvidenceRegistryStateId,
  inputActorEvidenceRegistryStateRevision,
  inputNextAuthenticationEvidenceOrdinal,
  nextAuthenticationEvidenceOrdinal
  // A closed allocation delta, not an actor-registry mutation by itself.
}

AuthenticatedActorEvidence {
  authenticationEvidenceId: AuthenticationEvidenceId,
  actor: AuthenticatedActorRef,
  providerId,
  assurancePolicyId,
  authenticatedAt,
  expiresAt?
}

ActorEvidenceRegistryState {
  actorEvidenceRegistryStateId,
  featureId,
  revision,
  parentActorEvidenceRegistryStateId?,
  nextAuthenticationEvidenceOrdinal,
  entries: AuthenticatedActorEvidence[],
  retiredAuthenticationEvidenceIds: AuthenticationEvidenceId[]
  // Credential handles and secret material are never persisted here.
}

RawReviewSubmission {
  expectedWorkflowStateId,
  expectedWorkflowStateRevision,
  target:
    | { stage: plan, planStateId }
    | { stage: tasks, taskDefinitionStateId },
  decision: approve | reject,
  feedback?: RawInputText,
  targetUnitIds[]?,
  authenticationLeaseRef
}

ReviewSubmissionId {
  reviewDecisionId,
  submissionSlot: review
}

ValidatedReviewSubmission {
  reviewSubmissionHandleId,     // run-local, nonserializable
  expectedWorkflowStateId,
  expectedWorkflowStateRevision,
  target,
  decision: approve | reject,
  feedback?: BusinessText,
  targetUnitIds[]?,
  targetAuthorityRevision,
  structuralEvidenceIds[]
}

AuthenticatedReviewSubmissionBinding {
  reviewSubmissionHandleId,
  authenticationEvidenceId,
  actor: AuthenticatedActorRef,
  intendedEventKind: plan_review | tasks_review,
  boundAt
}

RawManualVerificationSubmission {
  expectedWorkflowStateId,
  expectedWorkflowStateRevision,
  taskDefinitionStateId,
  taskId,
  expectedTaskRuntimeRevision,
  taskExecutionCheckpointId,
  inputExecutionEvidenceRegistryStateId,
  inputExecutionEvidenceRegistryStateRevision,
  evidencePredicateId,
  scenarioId,
  observation: RawInputText,
  authenticationLeaseRef
}

ManualVerificationSubmissionId {
  evidenceId,
  submissionSlot: manual_verification
}

ValidatedManualVerificationSubmission {
  manualVerificationSubmissionHandleId,  // run-local, nonserializable
  expectedWorkflowStateId,
  expectedWorkflowStateRevision,
  taskDefinitionStateId,
  taskId,
  expectedTaskRuntimeRevision,
  taskExecutionCheckpointId,
  inputExecutionEvidenceRegistryStateId,
  inputExecutionEvidenceRegistryStateRevision,
  evidencePredicateId,
  scenarioId,
  observation: BusinessText,
  structuralEvidenceIds[]
}

AuthenticatedManualVerificationBinding {
  manualVerificationSubmissionHandleId,
  authenticationEvidenceId,
  actor: AuthenticatedActorRef,
  intendedEventKind: manual_verification,
  boundAt
}

RawSourceScalar {
  sourceId,
  sourceLocation,
  utf8BytesHandle,      // validated UTF-8 source bytes; renderer must not normalize them
  byteLength
}

RawInputText {
  utf8BytesHandle,      // immutable invocation-owned bytes, not a reference citation
  byteLength
}

RelativeReferenceSelector {
  value                 // UTF-8/NFC relative descendant selector; never an alternate root
}

ParsedSpecifyInvocation {
  rawReferenceSelector: RawInputText
  // Parser proves only the exact flag cardinality/shape; it cannot mint a
  // normalized or trusted selector.
}

NormalizedReferenceSelectorCandidate {
  value,
  canonicalSegments[]
}

PreservedToken {
  tokenId,
  kind: PreservedTokenKind,
  rawValue: RawSourceScalar,
  citationId,
  downstreamObligationId
}

PreservedTokenKind =
  visual_color | visual_spacing | visual_dimension | visual_typography |
  visual_radius | visual_shadow | visual_motion | business_exact_string |
  numeric_constraint | exact_identifier

PathPattern {
  ruleId,
  base: workspace | environment | project | source_root | command_cwd,
  sourceRootId?,        // required iff base=source_root; forbidden otherwise
  target: relative_path | basename,
  patternType: exact | glob | regex,
  value,
  caseSensitive: boolean
}

SourceRootPathPatternTemplate {
  templateRuleId,
  base: source_root_template,
  sourceRootSelectorId,      // preset-owned semantic selector, never a filesystem path
  target: relative_path | basename,
  patternType: exact | glob | regex,
  value,
  caseSensitive: boolean
}

BoundSourceRootPattern {
  pattern: PathPattern,      // base=source_root and sourceRootId is present
  templateRuleId,
  sourceRootSelectorId
}

ExactEngineConfigLocation {
  canonicalInvocationDirectory,
  canonicalConfigPath,            // basename is exactly `.sddtoolkit.json`
  canonicalProjectRoot,           // config's containing directory
  noFollowFileIdentity,
  ancestorOrdinal,
  exactBasenameMatched: true
}

ConfiguredRootRole =
  specs_artifacts | reference_sources | archived_specs | workflow_authority |
  toolchain_preset_registry | project_principles | initialization_templates

ConfiguredBaseRootCapability {
  configuredRootCapabilityId,
  pathKey: specs | references | specsArchive | workflows | toolchainPreset |
           principles | templates,
  rootRole: ConfiguredRootRole,
  projectRoot: canonicalProjectRoot,
  configuredRelativePath,
  canonicalPath,
  accessClass,
  existencePolicy,
  noFollowValidated: true
  // The schema fixes the one-to-one pathKey/rootRole mapping. In particular,
  // initialization_templates is reserved but unreadable by ordinary bootstrap
  // readers and every action in the initial SDD workflow suite.
}

LLMProviderConfigCapability {
  projectRoot: canonicalProjectRoot,
  configuredRelativePath,              // basename exactly `.sddproviders.json`
  canonicalPath,
  accessClass: engine_only
  // Opaque F0004 capability. Only F0008's filesystem adapter may consume it.
}

BootstrapRootRegistryId {
  canonicalProjectRoot,
  bootstrapRootContractVersion
  // Self-validating engine tuple; it is never allocated by its own ledger.
}

WorkflowId = opaque validated project-authored lower-kebab identifier,
             1..64 ASCII bytes
WorkflowStepId = opaque validated definition-local lower-kebab identifier,
                 1..64 ASCII bytes
WorkflowParameterId = opaque validated definition-local lower-kebab identifier,
                      1..64 ASCII bytes
WorkflowResourceId = opaque validated definition-local lower-kebab identifier,
                     1..64 ASCII bytes
WorkflowRegisteredRef = opaque validated exact registered reference,
                        `[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*@[1-9][0-9]*`,
                        at most 128 ASCII bytes
WorkflowDefinitionSchemaVersion = "workflow/v1"
WorkflowVersion = opaque validated integer in 1..4294967295

WorkflowReservedChildName = features

WorkflowAuthorityLayout {
  bootstrapRootRegistryId,
  configuredWorkflowsRootCapabilityId,
  canonicalWorkflowAuthorityRoot,
  definitionInventoryScope: {
    base: workflow_authority_root,
    includedReservedRootEntries: [features/],
    excludedReservedDescendantSubtrees: [features/**]
  },
  reservedChildren: [
    { name: features, fixedRelativePath: features/, accessClass: engine_only }
  ]
  // Definitions live in the workflow-authority root but cannot collide with,
  // traverse into, or claim the engine-owned child.
}

WorkflowAuthorityNodeKind = directory | regular_file | symlink | special

WorkflowAuthorityRawInventoryEntry {
  observedRootRelativePathBytes,
  nodeKind: WorkflowAuthorityNodeKind,
  noFollowFileIdentity?,
  observedByteLength?
  // Enumeration assigns no durable or caller-supplied identity.
}

WorkflowAuthorityNormalizedInventoryEntryCandidate {
  normalizedRootRelativePath,
  nodeKind: WorkflowAuthorityNodeKind,
  noFollowFileIdentity?,
  observedByteLength?
}

WorkflowAuthorityInventoryEntry {
  inventoryOrdinal: PositiveInteger,
  normalizedRootRelativePath,
  nodeKind: WorkflowAuthorityNodeKind,
  noFollowFileIdentity?,
  observedByteLength?
  // The ordinal is the one-based position after complete collision validation
  // and Unicode-scalar path ordering. It is local to this immutable inventory.
}

WorkflowDefinitionCapture {
  sourceInventoryOrdinal: PositiveInteger,
  noFollowFileIdentity,
  immutableBytesHandle,
  byteLength,
  completeRead: true
}

WorkflowResourceCapture {
  sourceInventoryOrdinal: PositiveInteger,
  noFollowFileIdentity,
  immutableBytesHandle,
  byteLength,
  completeRead: true
}

WorkflowAuthorityEntryDisposition =
  | { kind: directory_accounted }
  | { kind: reserved_child_accounted,
      reservedChildName: WorkflowReservedChildName }
  | { kind: captured_definition,
      workflowId: WorkflowId }
  | { kind: captured_workflow_resource,
      bindings: { workflowId: WorkflowId,
                  resourceId: WorkflowResourceId }[] }
  | { kind: blocking, diagnosticId }

WorkflowAuthorityEntryAccount {
  inventoryOrdinal: PositiveInteger,
  disposition: WorkflowAuthorityEntryDisposition
}

WorkflowAuthorityInventory {
  layout: WorkflowAuthorityLayout,
  entries: WorkflowAuthorityInventoryEntry[],
  definitionCaptures: WorkflowDefinitionCapture[],
  resourceCaptures: WorkflowResourceCapture[],
  accounts: WorkflowAuthorityEntryAccount[]
  // Every encountered entry has exactly one terminal account. Any encountered
  // reserved root child uses reserved_child_accounted, and descendants of both
  // reserved children are outside the inventory scope. Every other regular
  // file is either a definition or an explicitly declared resource.
}

WorkflowResourceBinding {
  sourceInventoryOrdinal: PositiveInteger,
  resourceId: WorkflowResourceId,
  normalizedWorkflowRootRelativeSource,
  immutableBytesHandle
}

DeclarativeWorkflowStep {
  workflowStepId: WorkflowStepId,
  operationContractId: WorkflowRegisteredRef,
  parameters: Map<WorkflowParameterId, boolean | signed_integer | bounded_string>,
  outcomes: Map<PipelineOutcomeStatus,
    WorkflowStepId | MatchingTerminalOutcome>
  // YAML uses `use`, `with`, and `on`. The compiler supplies parameter types
  // from the registered generic operation contract and resolves resource
  // aliases before execution. No tagged parameter wrapper, adapter,
  // implementation symbol, raw operational path/command, or capability is
  // representable here.
}

DeclarativeWorkflowDefinition {
  sourceInventoryOrdinal: PositiveInteger,
  workflowId: WorkflowId,
  schema: WorkflowDefinitionSchemaVersion,
  workflowVersion: WorkflowVersion,
  workflowShortcode: WorkflowShortcode,
  invocationOperationRef: WorkflowRegisteredRef,
  // Resolves to one registered capability-free invocation operation. The
  // runner invokes it before graph entry to produce validated typed run context.
  workflowPolicyProfileRef: WorkflowRegisteredRef,
  entryStepId: WorkflowStepId,
  resources: WorkflowResourceBinding[],
  steps: DeclarativeWorkflowStep[]
  // Closed declarative graph data only. Executable code, infrastructure
  // adapters, raw paths/commands, capability grants, and runner controls are
  // absent. The compiler resolves and validates every referenced contract.
}

CompiledWorkflowSemanticAuthority {
  workflowId,
  schema,
  workflowVersion,
  workflowShortcode,
  resolvedInvocationOperationIdAndVersion,
  workflowPolicyProfileId,
  totalModelTokenBudget,
  entryStepId,
  resolvedOperationContractsParametersAndVersions,
  resolvedWorkflowResources,
  resolvedOutcomeTransitions,
  validatedGateSet,
  effectiveCapabilities
  // Canonical typed value used for bound-workflow change classification.
  // Source path/order, registry identity, and validation evidence are excluded.
}

WorkflowPolicyProfile {
  id,
  allowedCapabilities,
  allowedTerminalOutcomes,
  totalModelTokenBudget: PositiveInteger
  // Initialized as a new runner-owned ledger for each workflow execution.
  // A policy profile supplies no retry, attempt, or repair count.
}

CompiledWorkflowGraph {
  definition: DeclarativeWorkflowDefinition,
  resolvedInvocationOperation, // registered runner-invoked PipelineNode binding
  resolvedOperations: CompiledWorkflowOperation[],
  resolvedTransitions: CompiledWorkflowTransition[],
  validatedGateSet,
  effectiveCapabilities,
  semanticAuthority: CompiledWorkflowSemanticAuthority,
  graphEvidence
  // Immutable and executable only through PipelineRunner. Effective
  // capabilities are derived from registered operation contracts and must remain
  // within the selected workflow policy; the definition cannot add them.
  // sourceInventoryOrdinal and graphEvidence remain provenance and never make
  // an otherwise unchanged bound semantic graph appear changed.
}

WorkflowDefinitionRegistryState {
  workflowDefinitionRegistryId: BootstrapComponentId,
  workflowAuthorityInventory: WorkflowAuthorityInventory,
  workflowsById: Map<WorkflowId, CompiledWorkflowGraph>,
  workflowOperationRegistryVersion,
  capabilityRegistryVersion
  // The BootstrapComponentId is the registry's only canonical identity.
  // The bounded map has no fixed cardinality. Workflow IDs, shortcodes, and
  // sourceInventoryOrdinals are unique; every source ordinal
  // resolves to one captured_definition account; and reserved children resolve
  // only to their reserved accounts. Every encountered definition and compiled
  // graph must validate before the registry is usable. An invocation resolves
  // its requested WorkflowId exactly once. A valid graph change affecting an
  // already active feature remains an administrative migration in v1. That
  // comparison uses CompiledWorkflowSemanticAuthority only, never inventory
  // ordinals, registry identity, or graph evidence.
}

ValidatedWorkflowDefinitionRegistry =
  Validated<IdentityFreeBootstrapComponentPayload<WorkflowDefinitionRegistryState>>
  // Preselection view exposed by WorkflowDefinitionRegistryService. It has
  // complete registry evidence but no BootstrapComponentId; later bootstrap
  // materialization may consume it to construct WorkflowDefinitionRegistryState.

EngineStartupGraph {
  contractVersion,
  childNodeContractIds: compilerLockedConfigAndWorkflowLoadCompileRegisterNodes,
  selectable: false,
  projectExtensible: false
  // Assembled by the composition root so project workflows can be compiled
  // before any project-authored graph exists. It is absent from
  // WorkflowDefinitionRegistryState.
}

ProjectEngineArtifactSelector = FeatureIdentityRegistryCanonicalState

FeatureTransactionCollectionLockCapability {
  featureId,
  workflowArtifactRegistryStateId,
  stageTransactionCollectionArtifactPathId,
  ownerProcessInstanceId,
  opaqueLockTokenHandle,
  validOnlyWhileHeld: true
}

ValidatedTransactionStorageCapability {
  featureId,
  workflowArtifactRegistryStateId,
  stageTransactionCollectionArtifactPathId,
  lock: FeatureTransactionCollectionLockCapability,
  currentTransactionIdLedger: TransactionIdLedger,
  allowedTransactionKinds: DurableTransactionKind
}

BootstrapRootRegistry {
  bootstrapRootRegistryId: BootstrapRootRegistryId,
  configLocation: ExactEngineConfigLocation,
  configuredRoots: ConfiguredBaseRootCapability[7],
  llmProviderConfig: LLMProviderConfigCapability
  // Closed keys: specs, references, specsArchive, workflows, toolchainPreset,
  // principles, templates, and providers exactly once. The only configurable
  // nesting exception is specsArchive beneath specs.
  // This pre-preset authority contains no generated/discovered project roots.
}

RootAccessClass = project_read_write | generated_read_only | engine_only |
                  inaccessible | reference_read_only | private_temporary

RootAccessRecord {
  rootAccessId,
  ownerId,
  canonicalPath,
  accessClass: RootAccessClass,
  precedenceRank,
  allowedDescendantAccessClasses[]
}

RootAccessRegistry {
  rootAccessRegistryId,
  activeFilesystemPolicyId,
  records: RootAccessRecord[]
}

ProjectRecord {
  projectId,
  environmentId,
  canonicalProjectRoot,
  manifestFileId,
  manifestAdapterId,
  ownershipSpecificity,
  sourceRoots: {
    sourceRootId,
    selectorId,
    role: source | unit_test | integration_test | resource | generated,
    canonicalPath
  }[]
}

ProjectRegistry {
  projectRegistryId,
  projects: ProjectRecord[]
}

FilesystemPolicy {
  filesystemPolicyId,
  unicodeNormalization: nfc,
  caseRule: sensitive | insensitive,
  forbiddenCharacters[],
  forbiddenTrailingForms[],
  reservedBasenames[],
  maxSegmentLength,
  maxRelativePathLength,
  maxAbsolutePathLength?,
  lengthUnit: unicode_scalar | utf8_byte | utf16_code_unit
}

PortabilityPolicySet {
  portabilityPolicySetId,
  activeWorkspacePolicyId,
  targetPolicyIds[],
  policies: FilesystemPolicy[]
}

FileKindPolicy {
  kindId,
  inferencePriority,
  plannedIntents: (read | create | update | delete)[],
  capabilityCeiling: (read | create | patch | replace | copy_destination | delete)[],
  copyDestinationPolicy: { create: allowed | forbidden,
                           overwrite: allowed | forbidden },
  namingEnforcementByIntent,
  rootPatterns: PathPattern[],
  includePatterns: PathPattern[],
  excludePatterns: PathPattern[],
  basenamePatterns: PathPattern[],
  compoundExtensions[],
  extensionRuleId,
  extensionCaseSensitive,
  pathTemplateIds[],
  placementRule?,
  contentLimits: { modelCompleteFileBytes, copiedSourceBytes },
  contentReferencePolicy: {
    extractorIds[], fallbackScannerId, resolverId,
    requireCompleteCoverage: true
  },
  generated: boolean
}

CompiledEnvironmentPolicy {
  environmentPolicyId,
  environmentId,
  presetIds[],
  projectIds[],
  sourceRootIds[],
  fileKinds: FileKindPolicy[],
  pathTemplates: PresetPathTemplate[],
  boundSourceRootPatterns: BoundSourceRootPattern[],
  generatedPathPatterns: PathPattern[],
  forbiddenPathPatterns: PathPattern[]
}

ToolchainPresetInventoryNodeKind =
  directory | regular_file | symlink | special | locked_metadata_candidate

ToolchainPresetIdNamespace =
  budget_ledger_state | inventory_entry | resource | source_map | asset |
  inventory_state | registry_state

ToolchainPresetIdLedger {
  ownerBootstrapRootRegistryId,
  revision,
  nextOrdinalByNamespace: Map<ToolchainPresetIdNamespace, PositiveInteger>,
  retiredIdsByNamespace: Map<ToolchainPresetIdNamespace, EngineId[]>
  // Entry-ID retention uses normalized path/node/metadata available pre-read.
  // Resource/map/asset retention additionally requires direct raw-byte/typed
  // equality after capture. Removed/failed allocations are retired; no
  // filename, package ID, or content fingerprint creates an ID.
}

ToolchainPresetInventoryEntry {
  inventoryEntryId,
  observedRelativePath,       // engine-only bootstrap path, never model-visible
  normalizedRelativePath,
  nodeKind: ToolchainPresetInventoryNodeKind,
  noFollowFileIdentity?,
  reportedByteLength?,
  mediaObservation?,
  pathEvidenceId?,
  blockingDiagnosticId?
}

ToolchainPresetCaptureBudgetSession {
  bootstrapAttemptId,
  ceilings: { maxEntries, maxDepth, maxSourceBytes, maxTime, maxMemoryBytes },
  nextReservationOrdinal,
  reservations: {
    provisionalReservationId, inventoryEntryId, reservedBytes,
    status: reserved | debited | released,
    actualBytes?, terminalFact?
  }[],
  totalReservedBytes,
  totalDebitedBytes
  // Run-local validated accounting only; it is never serialized as authority.
}

ToolchainPresetSourceBudgetLedger {
  budgetLedgerStateId,
  revision,
  ceilings: { maxEntries, maxDepth, maxSourceBytes, maxTime, maxMemoryBytes },
  nextReservationOrdinal,
  reservations: {
    reservationId, inventoryEntryId, reservedBytes,
    status: reserved | debited | released,
    actualBytes?,
    terminalFact?:
      | { kind: debited, noFollowFileIdentity, completeRead: true }
      | { kind: released, diagnosticCode }
  }[],
  retiredReservationIds[],
  totalReservedBytes,
  totalDebitedBytes
}

ToolchainPresetRawCaptureObservation {
  inventoryEntryId,
  noFollowFileIdentity,
  immutableBytesHandle,
  observedByteLength,
  completeRead: true
  // Contains no presetResourceId or sourceMapId.
}

ToolchainPresetCapturedBlob {
  presetResourceId,
  inventoryEntryId,
  immutableBytesHandle,
  byteLength,
  debitBinding: {
    reservationId,
    budgetLedgerStateId,
    budgetLedgerRevision,
    actualBytes,
    noFollowFileIdentity,
    completeRead: true
  },
  sourceMapId
}

ToolchainPresetSourceMap {
  sourceMapId,
  presetResourceId,
  byteLength,
  wholeResourceSpan: { startByte: 0, endByte }
  // Package/asset parser coordinates belong to their immutable validation
  // evidence; this pre-parse map never acquires a later mutable revision.
}

ToolchainPresetResourceRole =
  package_document | parser_query | grammar | adapter_descriptor | schema

PresetResourceDeclarationIndex {
  entries: {
    declaringPresetId,
    declaringPresetVersion,
    normalizedResourceLocator,   // locator only; never supplies identity
    declaredStableResourceId,
    exactResourceVersion,
    role: parser_query | grammar | adapter_descriptor | schema,
    mediaType,
    formatDescriptorId
  }[]
}

ToolchainPresetAssetDeclarationJoin {
  presetResourceId,
  inventoryEntryId,
  declaringPresetId,
  declaringPresetVersion,
  declaredStableResourceId,
  exactResourceVersion,
  role,
  mediaType,
  formatDescriptorId,
  pathJoinEvidenceId
}

ToolchainPresetAssetRecord {
  presetAssetId,
  capturedResourceId,
  role: parser_query | grammar | adapter_descriptor | schema,
  mediaType,
  formatDescriptorId,
  declaredStableResourceId,
  exactResourceVersion,
  validationEvidenceId
}

ToolchainPresetPackageRecord {
  presetId,
  exactVersion,
  layer,
  packageDocumentResourceId,
  referencedPresetAssetIds[],
  validationEvidenceIds[]
}

ToolchainPresetEntryDisposition =
  | { kind: directory_accounted }
  | { kind: locked_metadata_excluded, exclusionRuleId }
  | { kind: blocking, diagnosticId }
  | { kind: captured_package_document, presetResourceId }
  | { kind: captured_asset, presetResourceId, presetAssetId }

ToolchainPresetEntryAccount {
  inventoryEntryId,
  disposition: ToolchainPresetEntryDisposition
}

ToolchainPresetInventoryState {
  inventoryStateId,
  revision,
  toolchainPresetRootPathId,
  idLedger: ToolchainPresetIdLedger,
  entries: ToolchainPresetInventoryEntry[],
  sourceBudgetLedger: ToolchainPresetSourceBudgetLedger,
  capturedBlobs: ToolchainPresetCapturedBlob[],
  sourceMaps: ToolchainPresetSourceMap[],
  accounts: ToolchainPresetEntryAccount[]
  // Exactly one terminal account per encountered entry; all reservations close.
}

ToolchainPresetRegistryState {
  toolchainPresetRegistryStateId,
  revision,
  configVersion,
  toolchainPresetRootPathId,    // direct configured <paths.toolchainPreset> root
  registrySchemaVersion,
  idLedger: ToolchainPresetIdLedger,
  inventory: ToolchainPresetInventoryState,
  packages: ToolchainPresetPackageRecord[],
  assets: ToolchainPresetAssetRecord[]
  // Every runtime-root entry is accounted for. Closed v1 packages and their
  // exact typed assets enter policy; legacy source examples never do.
}

ProjectToolchainLayer {
  projectToolchainLayerId: BootstrapComponentId,
  configVersion,
  principlesRootPathId,
  projectToolchainLayerPathId,  // exact <paths.principles>/toolchain.yaml
  schemaVersion,
  encoding: yaml_1_2,
  presetRegistryStateId,
  environmentBindings: {
    environmentId,
    inheritedPresetIds[],
    overrides: ValidatedProjectToolchainOverride[]
  }[],
  validationEvidenceIds[]
  // This is a closed mechanical project layer. Every inherited preset resolves
  // to one exact ID/version in the configured preset registry; ranges, unknown
  // fields, or attempts to weaken a locked rule reject the layer. It is never
  // decoded as free-text principle guidance even though it is stored in the
  // project-principles directory.
}

SupersetPathTokenGrammar {
  pathTokenGrammarStateId,
  grammarContractVersion,
  binding: {
    parentPathTokenGrammarStateId?,
    compiledEnvironmentPolicyIds[],
    repositoryFactStateId,
    rootAccessRegistryId,
    referenceStateId?
  },
  compoundExtensions[],
  exactBasenames[],
  reservedBasenames[],
  manifestBasenames[],
  referenceManifestBasenames[],
  pathAndUriLexemeRules[]
}

CompiledEnginePolicy {
  policyStateId: BootstrapComponentId,
  configVersion,
  bootstrapRootRegistryId,
  workflowDefinitionRegistryId,
  toolchainPresetRegistryStateId,
  projectToolchainLayerId,
  environmentPolicyIds[],
  portabilityPolicySetId,
  rootAccessRegistryId,
  rendererContractVersion,
  readerDescriptorIds[],
  parserAndQueryDescriptorIds[],
  commandRegistryId,
  dependencyPolicyRegistryId,
  fileIntentCapabilityRegistryId,
  factTransitionRuleRegistryId,
  logEventDefinitionRegistryId,
  loggingPolicyFragment: CompiledFeatureLoggingPolicyFragment,
  principleRegistryStateId,
  limitProfileId,
  basePathTokenGrammar: SupersetPathTokenGrammar
}

BootstrapCandidateComponentHandle {
  bootstrapAttemptId,
  componentTypeId,
  candidateOrdinal,
  dataKeyId,
  payloadSchemaId,
  runLocal: true,
  serializableAsCanonicalState: false,
  modelVisible: false
}

BootstrapComponentId {
  bootstrapAuthorityStateId,
  componentTypeId,
  componentOrdinal: PositiveInteger
  // Owner-local closed tuple; consumes no project/feature StateIdLedger entry.
}

BootstrapComponentTypeDescriptor {
  componentTypeId,
  payloadSchemaId,
  cardinality: singleton | ordered_collection,
  canonicalIdFieldId,
  componentOrdinalPolicyId,
  registryVersion
}

IdentityFreeBootstrapComponentPayload<T> {
  componentTypeId,
  payloadSchemaId,
  valueWithoutCanonicalId: Omit<T, canonicalIdFieldId>
  // canonicalIdFieldId comes from the descriptor; the field is structurally
  // absent, not null or provisional, until materialization. This generic form
  // is valid only for a leaf payload whose remaining fields contain no
  // not-yet-materialized generic bootstrap-component IDs.
}

BootstrapCandidateDependencyReference =
  | GenericBootstrapCandidateComponentReference {
      handle: BootstrapCandidateComponentHandle,
      expectedComponentTypeId,
      expectedComponentOrdinal
    }
  | SpecializedBootstrapStateReference {
      componentTypeId: toolchain_preset_registry | principle_registry,
      stateId
    }
  | FixedBootstrapAuthorityReference {
      componentTypeId,
      canonicalId
    }
  // A generic reference is run-local, nonserializable and resolved only by the
  // materialization map. Specialized/fixed authorities already have legal IDs.

IdentityFreeSupersetPathTokenGrammarPayload {
  componentTypeId: base_path_token_grammar,
  payloadSchemaId,
  grammarContractVersion,
  binding: {
    parentPathTokenGrammarStateId?,
    compiledEnvironmentPolicyReferences:
      GenericBootstrapCandidateComponentReference[],
    repositoryFactRegistryReference: BootstrapCandidateDependencyReference,
    rootAccessRegistryReference: BootstrapCandidateDependencyReference,
    referenceStateId?
  },
  compoundExtensions[],
  exactBasenames[],
  reservedBasenames[],
  manifestBasenames[],
  referenceManifestBasenames[],
  pathAndUriLexemeRules[]
  // No pathTokenGrammarStateId or unresolved canonical generic component ID.
}

IdentityFreeCompiledEnginePolicyPayload {
  componentTypeId: compiled_engine_policy,
  payloadSchemaId,
  configVersion,
  bootstrapRootRegistryId,
  workflowDefinitionRegistryReference:
    GenericBootstrapCandidateComponentReference,
  toolchainPresetRegistryStateId,
  projectToolchainLayerReference:
    GenericBootstrapCandidateComponentReference,
  environmentPolicyReferences:
    GenericBootstrapCandidateComponentReference[],
  portabilityPolicyReference: BootstrapCandidateDependencyReference,
  rootAccessRegistryReference: BootstrapCandidateDependencyReference,
  rendererContractVersion,
  readerDescriptorIds[],
  parserAndQueryDescriptorIds[],
  commandRegistryReference: BootstrapCandidateDependencyReference,
  dependencyPolicyRegistryReference: BootstrapCandidateDependencyReference,
  fileIntentCapabilityRegistryReference: BootstrapCandidateDependencyReference,
  factTransitionRuleRegistryReference: BootstrapCandidateDependencyReference,
  logEventDefinitionRegistryReference: BootstrapCandidateDependencyReference,
  loggingPolicyFragment: CompiledFeatureLoggingPolicyFragment,
  principleRegistryStateId,
  limitProfileId,
  basePathTokenGrammarReference:
    GenericBootstrapCandidateComponentReference
  // No policyStateId and no unresolved canonical generic component ID.
}

BootstrapOperationalComponentCandidate =
  | RootAccessRegistryCandidate {
      handle: BootstrapCandidateComponentHandle,
      payload: IdentityFreeBootstrapComponentPayload<RootAccessRegistry>
    }
  | ProjectRegistryCandidate {
      handle: BootstrapCandidateComponentHandle,
      payload: IdentityFreeBootstrapComponentPayload<ProjectRegistry>
    }
  | DiscoveryFileRegistryCandidate {
      handle: BootstrapCandidateComponentHandle,
      payload: IdentityFreeBootstrapComponentPayload<FileRegistryState>
    }
  | RepositoryFactRegistryCandidate {
      handle: BootstrapCandidateComponentHandle,
      payload: IdentityFreeBootstrapComponentPayload<RepositoryFactRegistryState>
    }
  | DependencyPolicyRegistryCandidate {
      handle: BootstrapCandidateComponentHandle,
      payload: IdentityFreeBootstrapComponentPayload<DependencyPolicyRegistry>
    }
  | FileIntentCapabilityRegistryCandidate {
      handle: BootstrapCandidateComponentHandle,
      payload: IdentityFreeBootstrapComponentPayload<FileIntentCapabilityRegistry>
    }
  | FactTransitionRuleRegistryCandidate {
      handle: BootstrapCandidateComponentHandle,
      payload: IdentityFreeBootstrapComponentPayload<FactTransitionRuleRegistry>
    }
  | LogEventDefinitionRegistryCandidate {
      handle: BootstrapCandidateComponentHandle,
      payload: IdentityFreeBootstrapComponentPayload<LogEventDefinitionRegistry>
    }
  | WorkflowDefinitionRegistryCandidate {
      handle: BootstrapCandidateComponentHandle,
      payload: IdentityFreeBootstrapComponentPayload<WorkflowDefinitionRegistryState>
    }
  | ProjectToolchainLayerCandidate {
      handle: BootstrapCandidateComponentHandle,
      payload: IdentityFreeBootstrapComponentPayload<ProjectToolchainLayer>
    }
  | BasePathTokenGrammarCandidate {
      handle: BootstrapCandidateComponentHandle,
      payload: IdentityFreeSupersetPathTokenGrammarPayload
    }
  | PortabilityPolicySetCandidate {
      handle: BootstrapCandidateComponentHandle,
      payload: IdentityFreeBootstrapComponentPayload<PortabilityPolicySet>
    }
  | CompiledEnvironmentPolicyCandidate {
      handle: BootstrapCandidateComponentHandle,
      payload: IdentityFreeBootstrapComponentPayload<CompiledEnvironmentPolicy>
    }
  | CommandRegistryCandidate {
      handle: BootstrapCandidateComponentHandle,
      payload: IdentityFreeBootstrapComponentPayload<CommandRegistry>
    }
  | CompiledEnginePolicyCandidate {
      handle: BootstrapCandidateComponentHandle,
      payload: IdentityFreeCompiledEnginePolicyPayload
    }

ValidatedBootstrapOperationalCandidate {
  bootstrapAttemptId,
  bootstrapRootRegistry: BootstrapRootRegistry,
  configVersion,
  componentCandidates: BootstrapOperationalComponentCandidate[],
  toolchainPresetRegistryCandidate: ToolchainPresetRegistryState,
  principleRegistryCandidate: PrincipleRegistryState,
  readerDescriptorCandidates[],
  parserAndQueryDescriptorCandidates[],
  rendererContractVersion,
  commandDescriptorCandidates[],
  validatedLimitProfile,
  validationEvidenceIds[]
  // Sufficient for bounded deterministic preactivation. Generic project/
  // feature canonical state IDs are assigned only when an enclosing feature
  // transaction can CAS the appropriate state ledgers.
}

BootstrapAuthorityComponentIdentity =
  | OwnerLocalBootstrapComponentIdentity { bootstrapComponentId: BootstrapComponentId }
  | ToolchainPresetRegistryComponentIdentity { toolchainPresetRegistryStateId }
  | PrincipleRegistryComponentIdentity { principleRegistryStateId }

BootstrapComponentCoordinate {
  componentTypeId,
  componentOrdinal: PositiveInteger
}

BootstrapCandidateMaterializationBinding {
  handle: BootstrapCandidateComponentHandle,
  coordinate: BootstrapComponentCoordinate,
  identity: OwnerLocalBootstrapComponentIdentity,
  bindingKind: materialized_leaf | validated_derived_aggregate,
  valueValidationEvidenceIds[]
  // One run-local handle is replaced by one owner-local identity only after the
  // identified value exists and validates. Specialized states need no handle.
}

BootstrapCandidateDependencyResolutionMap =
  | LeafBootstrapCandidateDependencyResolutionMap {
      bootstrapAttemptId,
      bootstrapAuthorityStateId,
      phase: leaf_dependencies,
      bindings: BootstrapCandidateMaterializationBinding[],
      unresolvedAggregateHandles: BootstrapCandidateComponentHandle[2]
      // Exact ordered handles for base_path_token_grammar, compiled_engine_policy.
    }
  | GrammarResolvedBootstrapCandidateDependencyResolutionMap {
      bootstrapAttemptId,
      bootstrapAuthorityStateId,
      phase: base_grammar_resolved,
      bindings: BootstrapCandidateMaterializationBinding[],
      unresolvedAggregateHandles: BootstrapCandidateComponentHandle[1]
      // Exact remaining compiled_engine_policy handle.
    }
  | CompleteBootstrapCandidateDependencyResolutionMap {
      bootstrapAttemptId,
      bootstrapAuthorityStateId,
      phase: complete,
      bindings: BootstrapCandidateMaterializationBinding[],
      unresolvedAggregateHandles: []
    }
  // Each successor strictly extends the prior phase. The complete variant has
  // exactly one binding for every generic candidate handle in the operational
  // candidate; fixed and specialized references resolve outside this map.

BootstrapCandidateComponentReference =
  | GenericBootstrapCandidateReference {
      candidateHandle: BootstrapCandidateComponentHandle
    }
  | SpecializedBootstrapCandidateReference {
      candidateIdentity:
        | ToolchainPresetRegistryComponentIdentity
        | PrincipleRegistryComponentIdentity
    }

BootstrapCandidateComponentDifference {
  coordinate: BootstrapComponentCoordinate,
  changeKind: added | modified | removed,
  currentIdentity?: BootstrapAuthorityComponentIdentity,
  candidateReference?: BootstrapCandidateComponentReference,
  directTypedComparisonEvidenceIds[]
  // candidateReference is required for added/modified and absent for removed.
  // A generic handle is run-local and cannot enter canonical state/journal;
  // specialized preset/principle candidates already carry ledger IDs.
}

BootstrapCandidateChangeEvidence {
  inputBootstrapAuthorityStateId,
  bootstrapAttemptId,
  differences: BootstrapCandidateComponentDifference[]
  // Ordered uniquely by (componentTypeId, componentOrdinal).
}

BootstrapCandidateDirectEqualityEvidence {
  inputBootstrapAuthorityStateId,
  bootstrapAttemptId,
  comparedCoordinates: BootstrapComponentCoordinate[],
  directlyEqual: true
  // Complete canonical-ID-erased typed comparison; no empty change plan is
  // fabricated for this branch.
}

BootstrapAuthorityComparisonResult =
  | BootstrapCandidateDirectEqualityEvidence
  | BootstrapCandidateChangeEvidence

MaterializedBootstrapComponentDifference {
  coordinate: BootstrapComponentCoordinate,
  changeKind: added | modified | removed,
  currentIdentity?: BootstrapAuthorityComponentIdentity,
  successorIdentity?: BootstrapAuthorityComponentIdentity,
  directTypedComparisonEvidenceIds[]
}

MaterializedBootstrapChangeEvidence {
  inputBootstrapAuthorityStateId,
  nextBootstrapAuthorityStateId,
  changePlan: BootstrapAuthorityChangePlan,
  differences: MaterializedBootstrapComponentDifference[]
  // Contains no candidate handle. It is persisted with the adopting transaction.
}

BootstrapAuthorityComponentBundle {
  compiledEnginePolicy: CompiledEnginePolicy,
  bootstrapRootRegistry: BootstrapRootRegistry,
  workflowDefinitionRegistry: WorkflowDefinitionRegistryState,
  rootAccessRegistry,
  projectRegistry,
  portabilityPolicySet: PortabilityPolicySet,
  compiledEnvironmentPolicies: CompiledEnvironmentPolicy[],
  toolchainPresetRegistry: ToolchainPresetRegistryState,
  projectToolchainLayer: ProjectToolchainLayer,
  commandRegistry: CommandRegistry,
  discoveryFileRegistry: FileRegistryState,
  repositoryFactRegistry: RepositoryFactRegistryState,
  dependencyPolicyRegistry: DependencyPolicyRegistry,
  fileIntentCapabilityRegistry: FileIntentCapabilityRegistry,
  factTransitionRuleRegistry: FactTransitionRuleRegistry,
  logEventDefinitionRegistry: LogEventDefinitionRegistry,
  principleRegistry: PrincipleRegistryState,
  basePathTokenGrammar: SupersetPathTokenGrammar
}

BootstrapAuthorityStateCoreCandidate {
  bootstrapAuthorityStateId,
  components: BootstrapAuthorityComponentBundle
  // Not canonical until an initial/successor wrapper is built and validated.
}

BootstrapAuthorityState =
  | InitialBootstrapAuthorityState {
      bootstrapAuthorityStateId,
      components: BootstrapAuthorityComponentBundle,
      lineage: InitialBootstrapAuthorityLineage { kind: initial }
    }
  | SuccessorBootstrapAuthorityState {
      bootstrapAuthorityStateId,
      components: BootstrapAuthorityComponentBundle,
      lineage: SuccessorBootstrapAuthorityLineage {
        kind: successor,
        parentBootstrapAuthorityStateId,
        changeFromParent: MaterializedBootstrapChangeEvidence
      }
    }

BootstrapComponentImpact =
  logging_threshold | logging_retention | model_slot_capacity |
  reference_ingestion | specification_contract | principle |
  technical_planning | administrative_migration

BootstrapComponentImpactAssignment {
  coordinate: BootstrapComponentCoordinate,
  impacts: {
    impact: BootstrapComponentImpact,
    impactRuleId,
    changedFieldSelectors[],
    subfieldComparisonEvidenceIds[]
  }[]
  // Nonempty, unique, and ordered by locked impact rank. One aggregate
  // component coordinate may therefore retain several independently routed
  // subfield impacts without duplicating the coordinate.
}

BootstrapChangeObligations {
  reingestReference: boolean,
  regenerateSpecification: boolean,
  rebuildPlan: boolean,
  rebuildTasks: boolean,
  reconcileCommittedRuntimeWhenPresent: boolean,
  transitionFeatureLogging: boolean
}

BootstrapAuthorityChangePlan =
  | CompatibleRuntimeOnlyBootstrapChangePlan {
      assignments: BootstrapComponentImpactAssignment[],
      earliestOwner: runtime_only,
      obligations: BootstrapChangeObligations,
      allowedImpacts:
        (logging_threshold | logging_retention | model_slot_capacity)[]
    }
  | SpecificationOwningBootstrapChangePlan {
      assignments: BootstrapComponentImpactAssignment[],
      earliestOwner: specify,
      dominantImpact: reference_ingestion | specification_contract,
      obligations: BootstrapChangeObligations
    }
  | PlanningOwningBootstrapChangePlan {
      assignments: BootstrapComponentImpactAssignment[],
      earliestOwner: plan,
      dominantImpact: principle | technical_planning,
      obligations: BootstrapChangeObligations
    }
  | AdministrativeBootstrapMigrationPlan {
      assignments: BootstrapComponentImpactAssignment[],
      earliestOwner: administrative_block,
      obligations: BootstrapChangeObligations,
      reasons: (project_root_or_artifact_layout | workflow_definition_selection |
                state_serializer |
                workflow_artifact_registry_contract | renderer_contract |
                unsupported_schema_transition)[]
    }
  // Every changed coordinate has exactly one assignment. Dominance is
  // administrative > reference > specification > planning > runtime-only;
  // secondary impacts and logging obligations are never discarded.

BootstrapAuthorityChangeRoutePlan =
  | NoBootstrapAuthorityChangeRoute {
      reason: direct_typed_equality,
      currentBootstrapAuthorityStateId,
      adoptionAuthorized: false
    }
  | DeferredPlanningBootstrapRoute {
      changePlan: PlanningOwningBootstrapChangePlan,
      currentBootstrapAuthorityStateId,
      currentStage: specifying | spec_clarification_pending,
      candidateDisposition: discard_run_local_candidate,
      requiredNextEvaluationGate: first_plan_input_after_specified,
      requiredRecheck:
        compare_classify_validate_route_from_fresh_bootstrap_candidate,
      adoptionAuthorized: false
    }
  | AdministrativeBootstrapBlockRoute
  | CompatibleBootstrapRefreshRoute
  | ReferenceIngestionBootstrapRoute
  | OwningSpecificationBootstrapRoute {
      transactionKind:
        specify_completion | clarification_pause |
        clarification_authority_resolution
    }
  | OwningPlanningBootstrapRoute {
      transactionKind:
        plan_input_authority | clarification_pause |
        clarification_authority_resolution
    }
  | BootstrapReworkInvalidationRoute {
      earliestOwnerStage: specify | plan,
      runtimeMutation: no_committed_runtime | reconcile_committed_runtime
    }

ReferenceRevisionBootstrapAuthorityMutation =
  | RetainReferenceRevisionBootstrapAuthority {
      currentBootstrapAuthorityStateId,
      reason: no_bootstrap_authority_change
    }
  | AdoptReferenceIngestionBootstrapAuthority {
      inputBootstrapAuthorityStateId,
      nextBootstrapAuthorityState: BootstrapAuthorityState,
      changePlan: SpecificationOwningBootstrapChangePlan,
      changeEvidence: MaterializedBootstrapChangeEvidence
      // Validation requires dominantImpact=reference_ingestion.
    }

ReworkBootstrapAuthorityMutation =
  | RetainReworkBootstrapAuthority {
      currentBootstrapAuthorityStateId,
      reason: no_bootstrap_authority_change
    }
  | AdoptReworkBootstrapAuthority {
      inputBootstrapAuthorityStateId,
      nextBootstrapAuthorityState: BootstrapAuthorityState,
      changePlan:
        | SpecificationOwningBootstrapChangePlan
        | PlanningOwningBootstrapChangePlan,
      changeEvidence: MaterializedBootstrapChangeEvidence
    }

SpecificationContractBootstrapAuthorityMutation =
  | RetainSpecificationContractBootstrapAuthority {
      currentBootstrapAuthorityStateId,
      reason: no_specification_contract_bootstrap_change
    }
  | AdoptSpecificationContractBootstrapAuthority {
      inputBootstrapAuthorityStateId,
      nextBootstrapAuthorityState: BootstrapAuthorityState,
      changePlan: SpecificationOwningBootstrapChangePlan,
      changeEvidence: MaterializedBootstrapChangeEvidence
      // Validation requires dominantImpact=specification_contract.
    }

SpecificationClarificationBootstrapAuthorityMutation =
  | ReferenceRevisionBootstrapAuthorityMutation
  | SpecificationContractBootstrapAuthorityMutation

PlanningStageBootstrapAuthorityMutation =
  | RetainPlanningBootstrapAuthority {
      currentBootstrapAuthorityStateId,
      reason: no_bootstrap_authority_change
    }
  | AdoptPlanningBootstrapAuthority {
      inputBootstrapAuthorityStateId,
      nextBootstrapAuthorityState: BootstrapAuthorityState,
      changePlan: PlanningOwningBootstrapChangePlan,
      changeEvidence: MaterializedBootstrapChangeEvidence
    }

DependencyPolicyRegistry {
  dependencyPolicyRegistryId,
  registrySources: {
    registrySourceId, ecosystem, canonicalBaseUri,
    trustPolicyId, credentialPolicyId?, allowPrerelease
  }[],
  ecosystems: {
    ecosystem,
    packageNameGrammarId,
    versionConstraintGrammarId,
    allowedScopes[],
    allowedRegistrySourceIds[],
    denyPackageRules: {
      ruleId, patternType: exact | regex, value, caseSensitive
    }[]
  }[]
}

FileIntentCapabilityRegistry {
  registryId,
  version,
  rules: [
    { plannedIntent: read,
      requiredAll: [read], requiredAtLeastOne: [],
      permittedCapabilities: [read] },
    { plannedIntent: create,
      requiredAll: [create], requiredAtLeastOne: [],
      permittedCapabilities: [create, patch, replace, copy_destination] },
    { plannedIntent: update,
      requiredAll: [read], requiredAtLeastOne: [patch, replace],
      permittedCapabilities: [read, patch, replace, copy_destination] },
    { plannedIntent: delete,
      requiredAll: [delete], requiredAtLeastOne: [],
      permittedCapabilities: [read, delete] }
  ]
  implications: [
    { whenPresent: copy_destination, alsoRequireOneOf: [create, replace] }
  ],
  sequencePolicyId
  // A requested set must satisfy requiredAll/requiredAtLeastOne/implications,
  // be a subset of the permitted set and file-kind ceiling, and obey the exact
  // absent/present operation sequence selected by sequencePolicyId.
}

FactTransitionRuleRegistry {
  registryId,
  version,
  rules: (
    | FilePresenceTransitionRule {
        transitionRuleId,
        before: present | absent,
        after: present | absent,
        permittedOperationKinds: (create | copy_create | modify | replace |
                                  copy_replace | delete)[]
      }
    | DependencyTransitionRule {
        transitionRuleId,
        ecosystem,
        before: absent | present,
        after: present | absent,
        requiredManifestDeltaKinds: (modify)[],
        permittedLockfileDeltaKinds: (create | modify | delete)[]
      }
    | ManifestFieldTransitionRule {
        transitionRuleId,
        adapterId,
        jsonPointerPatternId,
        permittedDeltaKinds: (add | replace | remove)[]
      }
  )[]
}

CompiledWorkflowModelOperation {
  workflowId,
  workflowVersion,
  workflowStepId,
  genericOperationId,
  modelSlotId,
  unitTypeId,
  unitPartitionContractId?,
  requestSchemaResourceId,
  resultSchemaResourceId,
  contextRequestSchemaResourceId?,
  guidanceResourceId,
  minimalExampleResourceId,
  inputCeiling: { bytes, tokens },
  outputCeiling: { bytes, tokens },
  repairAuthorizationSchemaId?
}

RendererContract {
  version,
  encoding: utf8_no_bom,
  ordinaryTextNormalization: nfc,
  lineEnding: lf,
  finalNewlineCount: 1,
  markdownEscapeTableId,
  jsonScalarContractId
}

SpecifyInvocation {
  referenceSelector: RelativeReferenceSelector
}

FeatureIdentitySeed {
  referenceSelector: RelativeReferenceSelector,
  namingPolicy: { version: unicode17_ascii_v1, maximumLength: 1..255 },
  featureId
}

FeatureIdentityOwnershipRecord {
  featureId,
  canonicalReferenceSelector: RelativeReferenceSelector,
  namingPolicy: { version: unicode17_ascii_v1, maximumLength: 1..255 },
  lifecycle: active | archived,
  workflowStateId,
  workflowArtifactRegistryStateId,
  featureRootPathId,
  activatedAt,
  archivedAt?
}

FeatureIdentityRegistryState {
  // This is a fixed project-level registry under <paths.workflows>/features/.
  // Its identity is the closed tuple (bootstrapRootRegistryId, revision), not a hash.
  featureIdentityRegistryStateId: { bootstrapRootRegistryId, revision },
  bootstrapRootRegistryId,
  revision,
  parentFeatureIdentityRegistryStateId?,
  records: FeatureIdentityOwnershipRecord[]
  // Records are retained across archive; featureId and the exact selector plus
  // naming-policy version are each unique under the portability policy.
}

FeatureStateInventoryEntry {
  featureId,
  ownershipLifecycle: active | archived,
  ownershipWorkflowStateId,
  ownershipArtifactRegistryStateId,
  ownershipFeatureRootPathId,
  resolvedFeatureRoot,
  rootNodeObservation,
  workflowStateHeaderObservation?,
  artifactRegistryHeaderObservation?,
  featureStateIdLedgerHeaderObservation?,
  terminalAccount:
    | { kind: live_state_headers_captured }
    | { kind: archived_state_headers_captured }
    | { kind: blocking, diagnosticId }
}

FeatureStateInventory {
  featureIdentityRegistryStateId,
  featureIdentityRegistryStateRevision,
  traversalBudget,
  entries: FeatureStateInventoryEntry[]
  // Exactly one ordered entry/account per ownership record. Observations are
  // bounded, no-follow, immutable captures from engine-derived paths only.
}

FeatureIdentityTarget =
  | NewFeatureIdentity {
      seed: FeatureIdentitySeed,
      inputFeatureIdentityRegistryStateId,
      inputFeatureIdentityRegistryStateRevision
    }
  | ExistingFeatureIdentity {
      seed: FeatureIdentitySeed,
      identityRegistryStateId,
      identityRegistryStateRevision,
      ownership: FeatureIdentityOwnershipRecord
    }

FeatureBriefProposal {
  title: BusinessText,
  description: BusinessText,
  primaryGoal: BusinessText,
  claimIds[],
  citationIds[],
  clarificationResponseIds[]
  // No feature ID, path, filename, reference selector, or canonical state ID.
}

FeatureBriefOperationResult =
  | { kind: content, proposal: FeatureBriefProposal }
  | { kind: clarification_needed, proposal: ClarificationNeedProposal }

FeatureRequestId {
  referenceStateId,
  requestSlot: feature_brief
  // Exactly one request identity per immutable reference-state revision.
}

FeatureRequest {
  featureRequestId: FeatureRequestId,
  featureId,
  title: BusinessText,
  description: BusinessText,
  primaryGoal: BusinessText,
  origin: reference_derived,
  referenceStateId,
  claimIds[],
  citationIds[],
  clarificationResponseIds[],
  referenceRequest: { relativeSelector: RelativeReferenceSelector }
}

FeatureRequestState {
  featureRequestStateId,
  featureId,
  inputReferenceStateId,
  inputClarificationStateId,
  inputClarificationStateRevision,
  request: FeatureRequest
}

WorkflowArtifactSelector =
  | EditableSpecificationView
  | ReferenceContextView
  | PlanView
  | ResearchView
  | DataModelView
  | QuickstartView
  | TasksView
  | ContractViewCollection
  | WorkflowArtifactRegistryCanonicalState
  | FeatureStateIdLedgerCanonicalState
  | BootstrapAuthorityStateCollection
  | FeatureRequestCanonicalState
  | PassiveLiteralCanonicalState
  | SpecificationIdLedgerState
  | SpecificationAcknowledgementCanonicalState
  | ClarificationCanonicalState
  | ClarificationViewCollection
  | ActorEvidenceCanonicalState
  | ReviewDecisionCanonicalState
  | WorkflowControlEventCanonicalState
  | SpecificationProvenanceCanonicalState
  | ReferenceCanonicalState
  | PlanInputAuthorityStateCollection
  | PlanCanonicalState
  | TaskDefinitionCanonicalState
  | TaskRuntimeCanonicalState
  | RuntimeFileCanonicalState
  | ExecutionEvidenceCanonicalState
  | WorkflowCanonicalState
  | ExecutionCheckpointCollection
  | FinalValidationOverlayCollection
  | StageTransactionCollection
  | RunLogSink
  | PromptLogSink

WorkflowArtifactPath {
  artifactPathId,
  selector: WorkflowArtifactSelector,
  pathRole: file | collection_root,
  rootAuthority: specs_feature | engine_feature | engine_state,
  rootRelativePath,
  canonicalContainedPath,
  accessClass: editable_view | generated_view | canonical_state |
               controlled_input_view | execution_state | transaction_state |
               append_only_log,
  conditionality: required | plan_artifact_required |
                  implementation_started | clarification_exists |
                  prompt_logging_enabled,
  editableByUser: boolean
}

WorkflowArtifactRegistry {
  workflowArtifactRegistryStateId,
  featureId,
  configVersion,
  rendererContractVersion,
  canonicalSpecsFeatureRoot,    // exactly <paths.specs>/<featureId>
  canonicalEngineFeatureRoot,   // exactly <paths.workflows>/features/<featureId>
  canonicalEngineStateRoot,     // exactly <canonicalEngineFeatureRoot>/state
  entries: WorkflowArtifactPath[]
  // The closed selector table has exactly one entry per singleton selector.
  // Bootstrap-authority/plan-input-authority/clarification/contract/checkpoint/
  // transaction selectors are collection roots only; the feature state-ID
  // ledger is a singleton canonical state and each collection-owned immutable state has
  // an engine-derived child path.
  // Each entry's rootAuthority determines exactly one base; rootRelativePath
  // is never interpreted against another base. Artifact/view/log selectors
  // resolve only under canonicalSpecsFeatureRoot; canonical/execution/
  // transaction state selectors resolve only under the explicit engine roots.
  // WorkflowCanonicalState is
  // the required singleton whose state-root-relative child is `workflow.json`
  // (`rootAuthority: engine_state`, `rootRelativePath: workflow.json`); it resolves under
  // canonicalEngineStateRoot, never by joining that feature-relative token twice.
  // FinalValidationOverlayCollection is the fixed engine-feature collection
  // `execution/final-validation-overlays/`; it is never beneath specs/logs.
  // Only EditableSpecificationView is an editable stage artifact. An open
  // ClarificationSubmissionView derived beneath ClarificationViewCollection
  // exposes only its two declared editable regions; a closed
  // ClarificationAuditView exposes none.
}

ActiveFeatureDirectoryCapability {
  activeFeatureDirectoryCapabilityId,
  featureId,
  canonicalSpecsFeatureRoot,
  canonicalEngineFeatureRoot,
  canonicalEngineStateRoot,
  workflowArtifactRegistryStateId,
  workflowStateId,
  workflowStateRevision,
  accessPolicyId
  // The three named roots are distinct capabilities. A consumer also receives
  // the registry entry and may use only its matching rootAuthority.
}

FeatureDirectoryCreationEntry {
  artifactPathId,
  canonicalContainedPath,
  kind: directory,
  accessClass,
  createMode: owner_only,
  expectedPriorState: absent
}

ConfiguredLogLevel = FATAL | CRITICAL | ERROR | WARNING | WARN |
                     INFO | DEBUG | TRACE |
                     fatal | critical | error | warning | warn |
                     info | debug | trace
CanonicalLogLevel = fatal | error | warning | info | debug | trace

WorkflowShortcode {
  bytes: [4]u8
  parse(rawBytes) -> WorkflowShortcode | InvalidWorkflowShortcode
  // Validated from a declarative workflow definition as exactly four ASCII
  // A-Z, a-z, or 0-9 bytes. Case is retained and significant. The workflow
  // registry proves shortcode uniqueness before any workflow executes.
}

WorkflowTelemetryFact {
  workflowShortcode: WorkflowShortcode,
  fact: TelemetryFact
}

WorkflowLog {
  workflowShortcode: WorkflowShortcode,
  init(shortcode: WorkflowShortcode) -> WorkflowLog,
  log(self, delta: *NodeDelta, fact: TelemetryFact) -> void | AllocationError
  // Constructed by the runner for the selected compiled workflow. Pure delta
  // construction: append one WorkflowTelemetryFact. No sink, filesystem,
  // clock, level, formatter, or direct logging capability.
}

LogLevelPolicy {
  configuredValue: ConfiguredLogLevel,
  threshold: CanonicalLogLevel,
  thresholdRank,              // fatal=60, error=50, warning=40,
                              // info=30, debug=20, trace=10
  aliasEvidenceIds[]          // CRITICAL -> fatal; WARN -> warning
}

FeatureLogDelimitedDialect {
  schemaVersion: feature-log/v2,
  encoding: utf8_without_bom,
  delimiter: ascii_pipe,
  quoting: forbidden,
  rowTerminator: lf,
  embeddedBackslashEncoding: double_backslash,
  embeddedPipeEncoding: backslash_pipe,
  embeddedCrEncoding: backslash_r,
  embeddedLfEncoding: backslash_n,
  absentOptionalCell: backslash_N,
  cellBoundary: unescaped_ascii_pipe,
  absentCheck: before_escape_decoding,
  acceptedEscapes: backslash | pipe | cr | lf,
  unknownOrDanglingEscape: reject,
  repeatedHeaderRows: forbidden,
  multilinePhysicalRows: forbidden
}

FeatureLogColumnSchema =
  | BuiltInEventColumnsV2 {
      columnSchemaId: event-columns/v2,
      schemaVersion: feature-log/v2,
      stream: event,
      orderedColumnIds: [
        record_kind, schema_version, stream, column_schema_id, log_policy_id,
        feature_log_binding_id, segment_ordinal, workflow_shortcode, event_id,
        sequence, occurred_at_utc, monotonic_offset, level, event_type,
        message_template_id, run_id, feature_id, stage, node_id,
        parent_event_id, correlation_id, attempt, task_id, duration_ms,
        diagnostic_code, validator_id, transaction_id, rule_id,
        model_operation_id, model_slot_id, input_tokens, output_tokens,
        repair_unit_kind, command_id, exit_code,
        evidence_status, outcome, count
      ],
      headerUtf8: "record_kind|schema_version|stream|column_schema_id|log_policy_id|feature_log_binding_id|segment_ordinal|workflow_shortcode|event_id|sequence|occurred_at_utc|monotonic_offset|level|event_type|message_template_id|run_id|feature_id|stage|node_id|parent_event_id|correlation_id|attempt|task_id|duration_ms|diagnostic_code|validator_id|transaction_id|rule_id|model_operation_id|model_slot_id|input_tokens|output_tokens|repair_unit_kind|command_id|exit_code|evidence_status|outcome|count\n"
    }
  | BuiltInPromptColumnsV2 {
      columnSchemaId: prompt-columns/v2,
      schemaVersion: feature-log/v2,
      stream: prompt,
      orderedColumnIds: [
        record_kind, schema_version, stream, column_schema_id, log_policy_id,
        feature_log_binding_id, segment_ordinal, workflow_shortcode, event_id,
        sequence, occurred_at_utc, monotonic_offset, level, event_type,
        message_template_id, run_id, feature_id, stage, node_id, attempt,
        request_id, model_operation_id, model_slot_id, fragment_id, direction,
        body_class, content, retained_bytes, truncated, redacted
      ],
      headerUtf8: "record_kind|schema_version|stream|column_schema_id|log_policy_id|feature_log_binding_id|segment_ordinal|workflow_shortcode|event_id|sequence|occurred_at_utc|monotonic_offset|level|event_type|message_template_id|run_id|feature_id|stage|node_id|attempt|request_id|model_operation_id|model_slot_id|fragment_id|direction|body_class|content|retained_bytes|truncated|redacted\n"
    }
  // These are compiler constants in the F0002 implementation, not data loaded
  // from config or an event registry. Event/prompt rows require
  // workflow_shortcode and level; control rows use the same width with \N in
  // event-only cells. During the pre-release proof of concept v2 is edited in
  // place and obsolete headings are rejected; there is no compatibility path.

CompiledFeatureLoggingPolicyFragment {
  configVersion,
  levelPolicy: LogLevelPolicy,
  format: fixed_header_pipe_delimited,
  timestampEnabled: true,
  delimitedDialect: FeatureLogDelimitedDialect,
  eventColumnSchemaId: event-columns/v2,
  promptColumnSchemaId: none | prompt-columns/v2,
  file: { enabled: true, format: fixed_header_pipe_delimited },
  console: { enabled: boolean, delimiter: ascii_pipe, heading: omitted }, // mirror only
  rotation: {
    maxRecordBytes: 65536,
    maxSegmentBytes: 8388608,
    maxSegments: 16
  },
  retentionDays: 14,
  flush: {
    atOrAbove: error,
    everyRecords: 32,
    intervalMs: 1000
  },
  streamLockDeadlineMs: 2000,
  streamLockAttemptCount: 1,
  failureMode: block_new_work,
  emergency: {
    maxAsciiBytes: 128,
    attemptCount: 1,
    format: "SDDE_LOG_FAILURE workflow=<CODE> level=fatal code=<FAILURE_CODE>\\n"
  },
  prompt: {
    captureSelectors: unique subset<request | response | reference_body | code_body>,
    maxContentBytes: 5000,
    redactSecrets: true,
    detectorRegistryId: redaction/default-v1,
    configuredDetectors: forbidden
  }
  // Persisted in CompiledEnginePolicy so historical policy can be rebuilt
  // without consulting a changed current config file.
}

FeatureLogPolicyId {
  featureId,
  bootstrapAuthorityStateId,
  configVersion,
  policySlot: feature_logging
  // Closed tuple: equal authority/config inputs reproduce the same ID.
}

FeatureLogBindingId {
  logPolicyId: FeatureLogPolicyId,
  runId,
  workflowArtifactRegistryStateId,
  bindingSlot: feature_run_logging
  // Closed tuple: no path, capability token, clock, or allocator participates.
}

FeatureLogPolicy {
  logPolicyId: FeatureLogPolicyId,
  configVersion,
  featureId,
  levelPolicy: LogLevelPolicy,
  eventLogCollectionArtifactPathId,
  file: { enabled: true, format: fixed_header_pipe_delimited },
  console: { enabled: boolean, delimiter: ascii_pipe, heading: omitted }, // mirror only
  timestampEnabled: true,
  format: fixed_header_pipe_delimited,
  delimitedDialect: FeatureLogDelimitedDialect,
  eventColumnSchemaId: event-columns/v2,
  promptColumnSchemaId: none | prompt-columns/v2,
  fileMode: owner_read_write,
  rotation: {
    maxRecordBytes: 65536,
    maxSegmentBytes: 8388608,
    maxSegments: 16             // hard lifetime count per (featureId, runId, stream)
  },
  retentionDays: 14,
  flush: {
    atOrAbove: error,
    everyRecords: 32,
    intervalMs: 1000
  },
  streamLockDeadlineMs: 2000,
  streamLockAttemptCount: 1,
  failureMode: block_new_work,
  prompt: {
    captureSelectors: unique subset<request | response | reference_body | code_body>,
    promptLogCollectionArtifactPathId?,
    maxContentBytes: 5000,
    redactSecrets: true,
    detectorRegistryId: redaction/default-v1,
    configuredDetectors: forbidden
  }
}

LogEventDefinitionRegistry {
  registryId: feature-log-events/poc-v2,
  version: 2,
  definitions: {
    eventType,
    canonicalLevel: CanonicalLogLevel,
    messageTemplateId,
    fields: {
      fieldId,
      valueTypeId,
      classification: public_metadata | sanitized_content,
      required: boolean
    }[]
  }[]
  // Every registered fieldId must map to one existing compiler-locked
  // stream column. Definitions are exactly the exhaustive F0002 Section 6.2
  // table. Only model.prompt_fragment.content is sanitized_content; all other
  // registered fields are public_metadata. The registry cannot add/reorder
  // delimited columns and no caller/plugin/configuration can extend it.
}

LogFieldValue =
  | LogString { value }
  | LogInteger { value }
  | LogBoolean { value }
  | LogIdentifier { namespaceId, value }
  | LogDurationMilliseconds { value }

LogField {
  fieldId,                    // from a closed field registry
  value: LogFieldValue
}

LogEventDraft {
  eventType,
  workflowShortcode: WorkflowShortcode,
  runId,
  featureId,
  stage,
  nodeId?,
  attempt?,
  fields: LogField[]
}

LogEvent {
  eventId,
  sequence,
  occurredAtUtc,             // trusted runner clock, fixed UTC RFC3339 form
  monotonicOffset,
  workflowShortcode: WorkflowShortcode,
  level: CanonicalLogLevel,
  eventType,
  messageTemplateId,
  runId,
  featureId,
  stage,
  nodeId?,
  attempt?,
  fields: LogField[],
  redactionEvidenceIds[]
}

FeatureLogBinding {
  featureLogBindingId: FeatureLogBindingId,
  featureId,
  runId,
  workflowArtifactRegistryStateId,
  activeFeatureDirectoryCapabilityId,
  eventLogCollectionArtifactPathId,
  promptLogCollectionArtifactPathId?,
  logPolicyId: FeatureLogPolicyId
}

FeatureLogPolicyTransition {
  featureId,
  runId,
  inputBootstrapAuthorityStateId,
  nextBootstrapAuthorityStateId,
  inputLogPolicyId: FeatureLogPolicyId,
  nextLogPolicyId: FeatureLogPolicyId,
  inputFeatureLogBindingId: FeatureLogBindingId,
  nextFeatureLogBindingId: FeatureLogBindingId,
  bootstrapChangeEvidence: MaterializedBootstrapChangeEvidence,
  changePlan: BootstrapAuthorityChangePlan,
  enabledStreams: (event | prompt)[]
}

FeatureLogPolicyTransitionCloseObservation {
  inputFeatureLogBindingId: FeatureLogBindingId,
  nextFeatureLogBindingId: FeatureLogBindingId,
  stream: event | prompt,
  closedHistoricalSegmentId,
  finalHistoricalSequence,
  durableTrailerEvidenceId,
  closedAndFsynced: true
}

HistoricalFeatureLogTailCloseObservation {
  featureId,
  historicalRunId,
  featureLogBindingId: FeatureLogBindingId,
  stream: event | prompt,
  closedSegmentId,
  finalSequence,
  durableTrailerEvidenceId,
  closedAndFsynced: true
}

AlreadyClosedHistoricalFeatureLogTailObservation {
  featureId,
  historicalRunId,
  featureLogBindingId: FeatureLogBindingId,
  stream: event | prompt,
  closedSegmentId,
  finalSequence,
  durableTrailerEvidenceId,
  trailerValidated: true,
  bytesWritten: 0
}

RawFeatureLogRunInventory {
  featureId,
  eventLogCollectionArtifactPathId,
  promptLogCollectionArtifactPathId?,
  observedBindingRunStreamGroups[]
}

ValidatedHistoricalFeatureLogRunInventory {
  featureId,
  currentRunId,
  orderedPriorGroups: {
    groupOrdinal,
    historicalRunId,
    featureLogBindingId: FeatureLogBindingId,
    logPolicyId: FeatureLogPolicyId,
    stream: event | prompt,
    disposition: active_tail_requires_close | already_closed,
    segmentIds[]
  }[]
  // Ordered by (historicalRunId, bindingId, stream rank); current run excluded.
}

HistoricalFeatureLogStreamFinalizationEvidence =
  | RecoveredHistoricalFeatureLogStreamFinalizationEvidence {
      groupOrdinal,
      historicalRunId,
      featureLogBindingId: FeatureLogBindingId,
      stream: event | prompt,
      disposition: active_tail_closed,
      closeObservation: HistoricalFeatureLogTailCloseObservation,
      releaseObservation: FeatureLogStreamLockReleaseObservation
    }
  | AlreadyClosedHistoricalFeatureLogStreamFinalizationEvidence {
      groupOrdinal,
      historicalRunId,
      featureLogBindingId: FeatureLogBindingId,
      stream: event | prompt,
      disposition: already_closed,
      closeObservation: AlreadyClosedHistoricalFeatureLogTailObservation,
      releaseObservation: FeatureLogStreamLockReleaseObservation
    }

HistoricalFeatureLogRunFinalizationEvidence {
  featureId,
  currentRunId,
  orderedGroupEvidence: HistoricalFeatureLogStreamFinalizationEvidence[],
  priorGroupCount,
  activePriorTailCount: 0,
  allPriorLocksReleased: true
}

FeatureLogStreamLockObservation {
  featureLogBindingId,
  stream: event | prompt,
  opaqueLockTokenHandle,
  adapterId,
  adapterVersion,
  acquiredAtMonotonic,
  ownerProcessInstanceId
}

FeatureLogStreamLockRejection {
  featureLogBindingId,
  stream: event | prompt,
  adapterId,
  adapterVersion,
  rejectionCode: owner_mismatch | binding_mismatch | adapter_mismatch |
                 duplicate_token | process_mismatch,
  rejectedAtMonotonic
}

FeatureLogStreamLockCapability {
  featureLogBindingId,
  stream: event | prompt,
  opaqueLockTokenHandle,
  adapterId,
  adapterVersion,
  ownerProcessInstanceId,
  validOnlyWhileHeld: true
  // Runner-held, nonserializable, nonloggable, and never model-visible.
}

FeatureLogPolicyTransitionStreamLockCandidate {
  featureId,
  runId,
  stream: event | prompt,
  inputFeatureLogBindingId: FeatureLogBindingId,
  nextFeatureLogBindingId: FeatureLogBindingId,
  ordinaryCapabilityHandleRef,
  transitionEvidenceId,
  runLocal: true,
  authorizesIo: false
}

FeatureLogPolicyTransitionStreamLockRejection {
  featureId,
  runId,
  stream: event | prompt,
  inputFeatureLogBindingId: FeatureLogBindingId,
  nextFeatureLogBindingId: FeatureLogBindingId,
  rejectionCode: transition_mismatch | binding_mismatch | stream_mismatch |
                 token_alias | process_mismatch,
  ordinaryCapabilityRetained: true
}

FeatureLogPolicyTransitionStreamLockCapability {
  featureId,
  runId,
  stream: event | prompt,
  inputFeatureLogBindingId: FeatureLogBindingId,
  nextFeatureLogBindingId: FeatureLogBindingId,
  opaqueLockTokenHandle,
  adapterId,
  adapterVersion,
  ownerProcessInstanceId,
  transitionEvidenceId,
  validOnlyWhileHeld: true
  // Wraps the same physical (featureId,runId,stream) lock. While live, the
  // consumed single-binding capability cannot be used or released separately.
}

FeatureLogStreamOperationLockCapability =
  | FeatureLogStreamLockCapability
  | FeatureLogPolicyTransitionStreamLockCapability

FeatureLogStreamLockReleaseObservation {
  featureLogBindingId,
  stream: event | prompt,
  released: true,
  releasedAtMonotonic
}

FeatureLogPolicyTransitionStreamLockReleaseObservation {
  featureId,
  runId,
  stream: event | prompt,
  inputFeatureLogBindingId: FeatureLogBindingId,
  nextFeatureLogBindingId: FeatureLogBindingId,
  physicalTokenDestroyed: true,
  runnerLockTableEntryAbsent: true,
  releasedAtMonotonic
}

FeatureLogRejectedLockCleanupObservation {
  featureLogBindingId,
  stream: event | prompt,
  adapterId,
  adapterVersion,
  cleanupOutcome: released | not_owned,
  opaqueTokenDestroyed: true,
  runnerLockTableEntryAbsent: true,
  cleanedAtMonotonic
}

ValidatedSafeLogRecord =
  | SafeEventLogRecord {
      schemaVersion: feature-log/v2,
      stream: event,
      columnSchemaId: event-columns/v2,
      event: LogEvent,
      serializedByteLength,
      safetyEvidenceIds[]
    }
  | SafePromptFragmentLogRecord {
      schemaVersion: feature-log/v2,
      stream: prompt,
      columnSchemaId: prompt-columns/v2,
      event: LogEvent,
      requestId,
      modelOperationId,
      modelSlotId,
      fragment: SanitizedPromptFragmentLogRecord,
      serializedByteLength,
      safetyEvidenceIds[]
    }
  // One SafePromptFragmentLogRecord is produced for each selected sanitized
  // fragment in canonical promptBodyFragmentId order. No composite cell exists.

LogRotationAuthorization {
  authorizationId,
  featureLogBindingId,
  stream,
  expectedActiveSegmentOrdinal,
  expectedBytesInActiveSegment,
  nextSegmentOrdinal,
  nextSegmentIdentity: FeatureLogSegmentIdentity,
  singleUse: true
}

FeatureLogRotationNeed =
  | AppendToActiveSegment { expectedActiveSegmentOrdinal }
  | RotationRequired {
      expectedActiveSegmentOrdinal,
      expectedBytesInActiveSegment,
      nextSegmentOrdinal
    }
  | SegmentLimitExhausted {
      diagnosticCode: LOG_SEGMENT_LIMIT_EXHAUSTED,
      maxSegments,
      activeSegmentOrdinal
    }

LogRetentionAuthorization {
  authorizationId,
  featureLogBindingId,
  closedSegmentIdsInDeletionOrder[],
  excludesActiveSegment: true,
  policyEvidenceId,
  singleUse: true
}

FeatureLogSinkState {
  logSinkStateId,
  logPolicyId,
  runId,
  featureId,
  eventLogCollectionArtifactPathId,
  promptLogCollectionArtifactPathId?,
  streams: FeatureLogStreamState[],
  segmentInventory: FeatureLogSegmentInventory
}

FeatureLogStreamInspection =
  | NoExistingFeatureLogSegments { stream: event | prompt }
  | ExistingActiveFeatureLogSegments {
      stream: event | prompt,
      orderedSegmentOrdinals[],
      activeTailOrdinal
    }
  | ExistingClosedFeatureLogSegments {
      stream: event | prompt,
      orderedSegmentOrdinals[],
      lastClosedOrdinal,
      durableTrailerEvidenceId
    }

FeatureLogSegmentIdentity {
  segmentId,
  featureLogBindingId,
  stream: event | prompt,
  ordinal
}

FeatureLogSegmentCreationObservation {
  segmentId,
  stream,
  ordinal,
  createdAtUtc,
  columnSchemaId,
  columnHeaderByteLength,
  columnHeaderEvidenceId,
  columnHeaderIsFirstRow: true,
  segmentHeaderControlRowByteLength,
  segmentHeaderControlRowEvidenceId,
  segmentHeaderControlRowIsSecondRow: true,
  headingAndControlRowDurable: true
}

FeatureLogRecordKind = segment_header | event | prompt | segment_trailer

RecoveredFeatureLogStreamObservation {
  stream,
  state: FeatureLogStreamState,
  records: FeatureLogSegmentRecord[],
  tailRepairEvidenceId?
}

FeatureLogStreamState {
  stream: event | prompt,
  nextSequence,
  activeSegmentOrdinal,
  bytesInActiveSegment,
  lastDurableSequence
}

SerializedFeatureLogFrame {
  stream: event | prompt,
  sequence,
  columnSchemaId,
  utf8DelimitedDataRowHandle,
  cellCount,
  byteLength,
  endsWithSingleLf: true
}

FeatureLogSegmentRecord {
  segmentId,
  stream: event | prompt,
  runId,
  ordinal,
  status: active | closed,
  firstSequence?,
  lastSequence?,
  byteLength,
  createdAtUtc,
  closedAtUtc?,              // segment_trailer value; forbidden while active
  headingAndControlRowEvidenceIds[]
}

FeatureLogSegmentInventory {
  featureLogBindingId,
  records: FeatureLogSegmentRecord[]
  // Times and bounds come from validated durable frames, never filesystem mtime.
}

FeatureLogRunStreamSegmentAccount {
  featureId,
  runId,
  stream: event | prompt,
  bindingInventories: FeatureLogSegmentInventory[],
  totalLifetimeSegmentCount,
  maxSegments,
  remainingSegmentCount
  // Binding inventories are ordered by binding ID; total covers the whole
  // run/stream so a policy transition cannot reset the lifetime cap.
}

PromptBodyClass = ordinary | reference_body | code_body

PromptBodyFragment {
  promptBodyFragmentId,
  direction: request | response,
  bodyClass: PromptBodyClass,
  typedFieldPointer,
  immutableUtf8Handle,
  byteLength,
  classificationRuleId
}

PromptBodyFragmentManifest {
  requestId,
  modelOperationId,
  resultSchemaResourceId,
  fragments: PromptBodyFragment[],
  coveredTypedFieldPointers[],
  completeCoverage: true
  // Built from typed request/result assembly before provider serialization.
}

PromptExchangeLogCandidate {
  requestId,
  modelOperationId,
  modelSlotId,
  requestMetadataFields: LogField[],
  responseMetadataFields: LogField[],
  selectedFragments: PromptBodyFragment[]
}

SanitizedPromptExchangeLogRecord {
  requestId,
  modelOperationId,
  modelSlotId,
  fragments: SanitizedPromptFragmentLogRecord[],
  // Sorted by promptBodyFragmentId. Metadata uses ordinary event records;
  // evidence IDs remain internal and are never serialized to the prompt stream.
}

SanitizedPromptFragmentLogRecord {
    promptBodyFragmentId,
    direction: request | response,
    bodyClass: PromptBodyClass,
    redactedUtf8Handle,
    retainedBytes,
    truncated: boolean,
    redacted: boolean,
    safetyEvidenceIds[]
}

ReferenceManifest {
  root,
  entries: ReferenceEntry[],
  blockingDiagnostics[],
  allEntriesAccountedFor
}

ReferencePreactivationSession {
  referencePreactivationSessionId: {
    runId, canonicalReferenceSelector, sessionOrdinal
  },
  featureIdentitySeed,
  provisionalNextSourceOrdinal,
  provisionalNextBlockOrdinal,
  retiredProvisionalIds[]
  // Run-local and noncanonical. These IDs may cross only bounded reader/decoder
  // adapter calls; they are never rendered, logged as canonical IDs, persisted,
  // or sent to a model.
}

ProvisionalReferenceBudgetReservationId =
  | ProvisionalReferenceSourceBudgetReservationId {
      referencePreactivationSessionId,
      budgetKind: source_bytes,
      provisionalSourceId
    }
  | ProvisionalReferenceDecodedBudgetReservationId {
      referencePreactivationSessionId,
      budgetKind: decoded_bytes,
      provisionalSourceId,
      readerId
    }
  // Closed run-local tuple: it consumes no allocator and is never persisted,
  // rendered, logged as canonical, or exposed to a model.

ReferencePreactivationSourceBudgetLedger {
  referencePreactivationSessionId,
  limitBytes,
  usedBytes,
  remainingBytes,
  reservations: {
    provisionalReservationId: ProvisionalReferenceSourceBudgetReservationId,
    provisionalSourceId, maximumBytes,
    status: reserved | committed | released,
    actualBytes?
  }[]
}

ReferencePreactivationDecodedBudgetLedger {
  referencePreactivationSessionId,
  limitBytes,
  usedBytes,
  remainingBytes,
  reservations: {
    provisionalReservationId: ProvisionalReferenceDecodedBudgetReservationId,
    provisionalSourceId, readerId, maximumBytes,
    status: reserved | committed | released,
    actualBytes?
  }[]
}

ReferencePreactivationIdentityMap {
  referencePreactivationSessionId,
  referenceStateId,
  sourceMappings: { provisionalSourceId, sourceId }[],
  blockMappings: { provisionalBlockId, blockId }[],
  blobMappings: { provisionalBlobHandle, referenceStateOwnedBlobId }[],
  budgetReservationMappings: {
    provisionalReservationId, canonicalReservationId
  }[]
}

ReferenceBudgetReservationId {
  referenceStateId,
  sourceId,
  budgetKind: source_bytes | decoded_bytes
  // Exactly one terminal canonical reservation per source and budget kind.
}

ReferenceSourceBudgetLedger {
  referenceStateId,
  limitBytes,
  usedBytes,
  remainingBytes,
  reservations: {
    reservationId: ReferenceBudgetReservationId, sourceId, maximumBytes,
    status: reserved | committed | released,
    actualBytes?
  }[]
}

ReferenceDecodedBudgetLedger {
  referenceStateId,
  limitBytes,
  usedBytes,
  remainingBytes,
  reservations: {
    reservationId: ReferenceBudgetReservationId, sourceId, readerId, maximumBytes,
    status: reserved | committed | released,
    actualBytes?
  }[]
}

ReferenceSourceBlob {
  blobId,
  referenceStateId,
  sourceId,
  mediaType?,
  byteLength,
  descriptorEvidenceId,
  contentHandle
}

ReferenceEntryBase {
  sourceId,                 // stable within a persisted reference snapshot
  relativePath,
  authority: authoritative,
  isOrganizer: boolean
}

ReferenceExclusion {
  ruleId,
  reasonCode,
  policyEvidenceId,
  actor: policy
  // v1 preactivation has no feature-local actor registry yet. User-authored
  // exclusions are therefore not representable; update policy and rerun.
}

ReferencePreactivationBranch =
  | PreacceptedReferenceExclusion {
      provisionalSourceId, exclusion: ReferenceExclusion
    }
  | PredecodedEmptyReference {
      provisionalSourceId, provisionalBlobHandle, readerId, readerVersion,
      sourceBudgetDebitBinding, decodedBudgetDebitBinding
    }
  | PredecodedNonemptyReference {
      provisionalSourceId, provisionalBlobHandle, readerId, readerVersion,
      identifiedBlockObservations: {
        provisionalBlockId, blockProposal, decoderCoordinates
      }[],
      sourceMapProposal,
      sourceBudgetDebitBinding,
      decodedBudgetDebitBinding,
      decoderResourceTelemetry
    }
  | PreunsupportedReference { provisionalSourceId, detectedMediaType? }
  | PrefailedReference { provisionalSourceId, attemptedReaderIds[], diagnosticIds[] }
  | PreblockedReference {
      provisionalSourceId,
      phase: readability | source_size | source_capture | reader_selection |
             decode_budget,
      diagnosticIds[]
    }

ReferencePreactivationBranchSet {
  referencePreactivationSessionId,
  orderedBranches: ReferencePreactivationBranch[]
  // Exactly one branch per sorted source. No ContentBlock, semantic accounting
  // status, canonical ReferenceEntry, claim, citation, or reconciliation exists.
}

ReferenceEntry =
  | DecodedReferenceEntry {
      base: ReferenceEntryBase,
      status: decoded | empty,
      mediaType,
      decoder: { id, version },
      blocks: ContentBlock[],
      diagnostics: Diagnostic[]
    }
  | ExcludedReferenceEntry {
      base: ReferenceEntryBase,
      status: explicitly_excluded,
      exclusion: ReferenceExclusion,
      diagnostics: Diagnostic[]
    }
  | UnsupportedReferenceEntry {
      base: ReferenceEntryBase,
      status: unsupported,
      detectedMediaType?,
      diagnostics: Diagnostic[]
    }
  | FailedReferenceEntry {
      base: ReferenceEntryBase,
      status: failed,
      detectedMediaType?,
      attemptedReaderIds[],
      diagnostics: Diagnostic[]
    }
  | BlockedReferenceEntry {
      base: ReferenceEntryBase,
      status: blocked,
      phase: readability | source_size | source_capture | reader_selection |
             decode_budget,
      diagnostics: Diagnostic[]
    }

ReferenceSnapshot {
  referenceStateId,         // state identity, never a content digest
  parentReferenceStateId?,
  passiveLiteralRegistryStateId,
  extractionContract: {
    compiledWorkflowAuthorityId,
    modelOperationId,
    requestSchemaResourceId,
    resultSchemaResourceId,
    unitPartitionContractId
  },
  idLedger: ReferenceIdLedger,
  manifest: ReferenceManifest,
  context: ReferenceContextIR,
  chunks: AccountedReferenceChunk[],
  sourceMaps[],
  sourceBudgetLedger: ReferenceSourceBudgetLedger,
  decodedBudgetLedger: ReferenceDecodedBudgetLedger,
  sourceBlobs: ReferenceSourceBlob[],
  immutableBlobs: ImmutableContentHandle[],
  citations: SourceCitation[],
  reconciliation: HierarchicalReferenceReconciliationState,
  claimLedger: ReferenceClaimLedgerEntry[],
  feedbackEvents: ReferenceFeedback[],
  conflictResolutionDecisions: ReferenceConflictResolutionDecision[]
}

ReferenceIdLedger {
  nextSourceOrdinal,
  nextBlockOrdinal,
  nextChunkOrdinal,
  nextCitationOrdinal,
  nextClaimOrdinal,
  nextSignalOrdinal,
  nextConflictOrdinal,
  nextFeedbackOrdinal,
  nextConflictDecisionOrdinal,
  nextTokenOrdinal,
  nextReconciliationPartitionOrdinal,
  nextReconciliationSummaryOrdinal,
  nextReconciliationStatementOrdinal,
  retiredIds[]
}

ReferenceSignal<T> {
  signalId,
  claimIds[],
  citationIds[],
  content: T
}

ReferenceClaimProposalContent =
  | BusinessClaim { text: BusinessText }
  | DesignClaim { text: ReferenceSemanticText }
  | TechnicalClaim { text: ReferenceSemanticText }
  | ValidationClaim { text: ReferenceSemanticText }
  | ImplementationAssumptionClaim { text: ReferenceSemanticText }
  | OpenQuestionClaim { text: ReferenceSemanticText }
  | ScopeGuardClaim { text: BusinessText }

ReferenceClaimContent =
  | ReferenceClaimProposalContent
  | PreservedTokenClaim { token: PreservedToken }

StructuredTokenCandidate {
  tokenCandidateId,          // engine-assigned to one deterministic parser fact
  rawValue: RawSourceScalar,
  citation: SourceCitationProposal,
  deterministicKindHint?
}

PreservedTokenClassificationProposal {
  tokenCandidateId,
  decision: preserve | irrelevant,
  kind?: PreservedTokenKind  // required iff preserve; forbidden iff irrelevant
}

PreservedTokenClaimCandidate {
  content: PreservedTokenClaim { token: PreservedToken },
  citationIds[],
  sourceBlockIds[],
  sourceChunkIds[]
}

SourceCitationProposal {
  sourceId,                 // must be in this workflow operation unit's allowlist
  blockId,                  // must equal the supplied chunk's block
  location: line-range | page-region | cell-range | node-path,
  verbatim?: RawSourceScalarProposal
}

ReferenceClaimProposal {
  content: ReferenceClaimProposalContent,
  citations: SourceCitationProposal[]
  // No reference-state, chunk, citation, claim, disposition, or related-claim IDs.
}

ClaimDispositionProposal {
  claimId,
  disposition: retained | superseded | duplicate | conflicting,
  relatedClaimIds[]
}

ReferenceSignalProposal {
  kind: business | design_interaction | preserved_token | terminal_scope_guard |
        technical | validation | implementation_assumption | open_question,
  claimIds[],
  citationIds[],
  content: BusinessText | ReferenceSemanticText | PreservedTokenReference
  // The closed result schema couples each kind to exactly one content variant.
}

PreservedTokenReference { tokenId }

SourceConflictProposal {
  claimIds[],
  citationIds[],
  kind: mutually_exclusive | precedence_missing | value_mismatch | scope_mismatch,
  summary: ReferenceSemanticText,
  proposedResolution:
    | { status: unresolved }
    | { status: source_precedence, precedenceRuleId, selectedClaimIds[],
        rationale: ReferenceSemanticText }
}

ReferenceReconciliationProposal {
  claimDispositions: ClaimDispositionProposal[],
  signals: ReferenceSignalProposal[],
  conflicts: SourceConflictProposal[]
  // No signal IDs, conflict IDs, decision IDs, or canonical records.
}

ReferenceReconciliationItem {
  claimId,
  sourceId,
  sourceOrdinal,
  compactContent: ReferenceClaimContent,
  citationIds[]
}

ReferenceReconciliationPartition {
  partitionId,
  level: within_source | cross_source | global,
  ordinal,
  memberClaimIds[],
  memberSummaryIds[],
  estimatedInputBytes,
  estimatedInputTokens
}

ReferenceReconciliationSummaryProposal {
  partitionId,
  memberClaimIds[],
  memberSummaryIds[],
  compactStatements: {
    localKey,
    representedClaimIds[],
    content: ReferenceClaimContent
  }[]
}

ReferenceReconciliationSummary {
  reconciliationSummaryId,
  partitionId,
  memberClaimIds[],
  memberSummaryIds[],
  statements: {
    statementId,
    representedClaimIds[],
    content: ReferenceClaimContent
  }[]
}

ReferenceReconciliationOperationResult =
  | { kind: partition_summary,
      proposal: ReferenceReconciliationSummaryProposal }
  | { kind: global_reconciliation,
      proposal: ReferenceReconciliationProposal }

HierarchicalReferenceReconciliationState {
  reconciliationStateId,
  referenceStateId,
  compiledWorkflowAuthorityId,
  partitionContractId,
  partitions: ReferenceReconciliationPartition[],
  summaries: ReferenceReconciliationSummary[],
  finalProposal: ReferenceReconciliationProposal
}

IdentifiedReferenceClaim {
  claimId,
  sourceBlockIds[],
  sourceChunkIds[],
  citationIds[],
  content: ReferenceClaimContent
}

ReferenceClaimLedgerEntry {
  claimId,
  sourceBlockIds[],
  sourceChunkIds[],
  citationIds[],
  content: ReferenceClaimContent,
  disposition: retained | superseded | duplicate | conflicting,
  relatedClaimIds[]
}

ImmutableContentHandle {
  blobId,
  referenceStateId,
  mediaType,
  encoding?,
  byteLength
}

IdentifiedContentBlock {
  blockId,
  sourceId,
  ordinal,
  sourceLocation,
  contentHandle
}

ContentBlock {
  identified: IdentifiedContentBlock,
  accountingStatus: extracted | no_feature_claim | blocked
}

ReferenceChunk {
  chunkId,
  referenceStateId,
  sourceId,
  blockId,
  ordinal,
  sourceRange,
  contentHandle
}

AccountedReferenceChunk {
  chunk: ReferenceChunk,
  extractionOutcome:
    | { kind: claims, claimIds[] }
    | { kind: no_feature_claim, evidenceId }
    | { kind: blocked, diagnosticIds[] }
}

ReferenceSourceMap {
  sourceId,
  decoder: { id, version },
  mappings: {
    blockId,
    decodedRange,
    sourceLocation,
    contentHandle
  }[]
}

SourceCitation {
  citationId,
  referenceStateId,
  sourceId,
  blockId,
  location: line-range | page-region | cell-range | node-path,
  verbatim?: RawSourceScalar
}

ReferenceAuthorityLocus {
  normalizedReferenceRelativePath,
  readerId,
  readerVersion,
  decoderStructuralSelector,
  // Examples are a JSON pointer, XML node path, table row/column selector,
  // heading path plus paragraph ordinal, page-region anchor, or the decoder's
  // versioned fallback block ordinal. No reference-state/source/block ID occurs.
}

ReferenceConflictSubjectCoordinate {
  conflictKind: mutually_exclusive | precedence_missing | value_mismatch | scope_mismatch,
  requiredDecisionSlotId: source_conflict_resolution,
  loci: ReferenceAuthorityLocus[]
  // Canonically sorted and duplicate-free. It is a structural tuple, not a
  // digest, and remains comparable across independently recaptured snapshots.
}

ReferenceConflictOptionContinuityKey {
  subjectCoordinate: ReferenceConflictSubjectCoordinate,
  claimKind,
  canonicalClaimContent: ReferenceClaimContent,
  citationCoordinates: {
    locus: ReferenceAuthorityLocus,
    location: line-range | page-region | cell-range | node-path,
    exactCapturedScalar?: RawSourceScalar
  }[]
}

ReferenceConflictClarificationBinding {
  referenceStateId,
  conflictId,
  subjectCoordinate: ReferenceConflictSubjectCoordinate,
  options: {
    optionKey,                    // claimId in this exact snapshot only
    continuityKey: ReferenceConflictOptionContinuityKey
  }[]
}

ReferenceConflictExhaustiveAbsenceEvidence {
  currentReferenceStateId,
  priorSubjectKey: ReferenceConflictClarificationSubjectKey,
  inspectedCurrentConflictIds[],
  inspectedCurrentSubjectKeys: ReferenceConflictClarificationSubjectKey[],
  completeCurrentConflictRegistryCovered: true,
  equalSubjectKeyCount: 0
}

ReferenceConflictExactMappingFailureEvidence {
  priorClaimId,
  continuityKey: ReferenceConflictOptionContinuityKey,
  failureKind:
    no_exact_current_option |
    exact_current_scalar_or_coordinate_mismatch,
  inspectedCurrentClaimIds[],
  directFreshCaptureEvidenceIds[]
  // Nonempty direct evidence over the fresh candidate only. Prior meaning and
  // coordinates come from the durable clarification binding, never old blobs.
}

AbsentReferenceConflictCorrespondence {
  kind: conflict_absent,
  clarificationId,
  subjectKey: ReferenceConflictClarificationSubjectKey,
  currentReferenceStateId,
  absenceEvidence: ReferenceConflictExhaustiveAbsenceEvidence
}

FreshReferenceConflictCorrespondence =
  | CurrentReferenceConflictCorrespondence {
      kind: current,
      clarificationId,
      subjectKey: ReferenceConflictClarificationSubjectKey,
      priorReferenceStateId,
      currentReferenceStateId,
      priorConflictId,
      currentConflictId,
      optionMappings: {
        priorClaimId,
        currentClaimId,
        continuityKey: ReferenceConflictOptionContinuityKey,
        directFreshCaptureEvidenceIds[]
      }[],
      selectedCurrentClaimIds[]
    }
  | StaleSameSubjectReferenceConflictCorrespondence {
      kind: stale_same_subject,
      clarificationId,
      subjectKey: ReferenceConflictClarificationSubjectKey,
      currentReferenceStateId,
      currentConflictId,
      currentSubjectCoordinate: ReferenceConflictSubjectCoordinate,
      exactMappingFailures: ReferenceConflictExactMappingFailureEvidence[],
      diagnosticCode
    }

PriorReferenceConflictClarificationSubjectSet {
  priorReferenceStateId?,
  inputClarificationStateId,
  inputClarificationStateRevision,
  subjects: {
    subjectKey: ReferenceConflictClarificationSubjectKey,
    clarificationId,
    recordRevision,
    binding: ReferenceConflictClarificationBinding,
    answerState:
      | { kind: no_usable_closed_response }
      | { kind: usable_closed_response, clarificationResponseId }
  }[]
  // Complete canonical projection of the latest active record revision for
  // every conflict binding owned by priorReferenceStateId. It is empty and
  // the pointer is absent only for initial ingestion. Sorted by the full
  // structural subject key and duplicate-free.
}

CurrentUnresolvedReferenceConflictSubjectSet {
  currentReferenceStateId,
  subjects: {
    subjectKey: ReferenceConflictClarificationSubjectKey,
    currentConflictId,
    binding: ReferenceConflictClarificationBinding
  }[]
  // Complete canonical projection of every unresolved behavior-changing
  // conflict in the fully validated fresh snapshot. Sorted by the same full
  // structural key and duplicate-free.
}

SameKeyReferenceConflictReconciliation {
    subjectKey: ReferenceConflictClarificationSubjectKey,
    priorClarificationId,
    currentConflictId,
    priorAnswerState:
      | { kind: no_usable_closed_response }
      | { kind: usable_closed_response, clarificationResponseId }
}

ObsoletePriorReferenceConflictReconciliation {
  subjectKey: ReferenceConflictClarificationSubjectKey,
  priorClarificationId,
  absenceCorrespondence: AbsentReferenceConflictCorrespondence
}

IntroducedCurrentReferenceConflictReconciliation {
  subjectKey: ReferenceConflictClarificationSubjectKey,
  currentConflictId,
  currentBinding: ReferenceConflictClarificationBinding
}

ReferenceConflictSubjectSetReconciliation {
  priorSet: PriorReferenceConflictClarificationSubjectSet,
  currentSet: CurrentUnresolvedReferenceConflictSubjectSet,
  sameKeySubjects: SameKeyReferenceConflictReconciliation[],       // P ∩ C
  obsoletePriorSubjects: ObsoletePriorReferenceConflictReconciliation[], // P ∖ C
  introducedCurrentSubjects: IntroducedCurrentReferenceConflictReconciliation[], // C ∖ P
  canonicalPriorSubjectKeys: ReferenceConflictClarificationSubjectKey[],
  canonicalCurrentSubjectKeys: ReferenceConflictClarificationSubjectKey[]
  // The three arrays are a disjoint, exhaustive merge-join partition over the
  // two canonical key sets. No entry relates unequal keys and no closest/new
  // subject is selected for an obsolete prior subject. Equality is direct
  // typed-tuple equality: no hash, wording, fuzzy match, or old blob read.
}

RawSourceScalarProposal {
  sourceId,
  sourceLocation,
  value                    // model-returned scalar; validator compares captured blob bytes
}

AcceptanceCriterionRequirementProjection {
  requirementId,
  specificationRecordId,
  // Typed values only. The specification renderer owns the uppercase
  // GIVEN, WHEN, THEN labels and their fixed order.
  given: BusinessValue,
  when: BusinessValue,
  then: BusinessValue,
  claimIds[], citationIds[], clarificationResponseIds[]
}

FunctionalRequirementProjection {
  requirementId,
  specificationRecordId,
  text: BusinessValue,
  modality,
  claimIds[], citationIds[], clarificationResponseIds[]
}

EdgeCaseRequirementProjection {
  requirementId,
  specificationRecordId,
  condition: BusinessValue,
  expectedOutcome: BusinessValue,
  claimIds[], citationIds[], clarificationResponseIds[]
}

BusinessRuleRequirementProjection {
  requirementId,
  specificationRecordId,
  text: BusinessValue,
  claimIds[], citationIds[], clarificationResponseIds[]
}

ScopeGuardRequirementProjection {
  requirementId,
  specificationRecordId,
  sourceKind: assumption | non_goal | prohibited_behavior,
  text: BusinessValue,
  claimIds[], citationIds[], clarificationResponseIds[]
}

RequirementIndex {
  acceptanceCriteria: AcceptanceCriterionRequirementProjection[],
  functionalRequirements: FunctionalRequirementProjection[],
  edgeCases: EdgeCaseRequirementProjection[],
  businessRules: BusinessRuleRequirementProjection[],
  scopeGuards: ScopeGuardRequirementProjection[]
}

ResearchEvidenceRecord {
  evidenceId,
  ownerStateId,
  subjectIds[],
  evidence:
    | InternalResearchEvidence {
        kind: feature_request | reference_claim | repository_fact |
              principle_span | parser_fact | user_decision,
        boundedExcerptHandle?,
        sourceLocation?
      }
    | RegistryAdapterResearchEvidence {
        kind: registry_adapter,
        adapterId,
        adapterVersion,
        registrySourceId,
        remoteRecordId,
        sourceLocation,
        trustPolicyId,
        capturedAt,
        expiresAt,
        boundedCapturedValueHandle
      }
}

ResearchEvidenceRegistry {
  researchEvidenceRegistryStateId,
  revision,
  inputBootstrapAuthorityStateId,
  inputFeatureRequestStateId,
  inputSpecificationProvenanceStateId,
  passiveLiteralRegistryStateId,
  inputReferenceStateId,
  records: ResearchEvidenceRecord[]
}

PlanInputAuthorityState {
  planInputAuthorityStateId,
  revision,
  parentPlanInputAuthorityStateId?,
  inputBootstrapAuthorityStateId,
  inputFeatureRequestStateId,
  inputReferenceStateId,
  normalizedSpecification: SpecificationIR,
  specificationIdLedger: SpecificationIdLedger,
  specificationAcknowledgementState: SpecificationAcknowledgementState,
  specificationProvenanceState: SpecificationProvenanceState,
  passiveLiteralRegistryState: PassiveLiteralRegistryState,
  clarificationStateId,
  clarificationStateRevision,
  principleRegistryStateId,
  principleRegistryStateRevision,
  principleSelection: ApplicablePrincipleSelection,
  repositoryFactRegistryState: RepositoryFactRegistryState,
  baselineFileRegistryState: FileRegistryState,
  researchEvidenceRegistry: ResearchEvidenceRegistry,
  planIdLedger: PlanIdLedger
  // Committed before any plan-generation call. A later deterministic adapter
  // capture creates a successor input authority transaction before reuse.
}

ObligationBase {
  obligationId,
  sourceRecordIds[],
  claimIds[],
  citationIds[],
  projectIds[],
  phaseHint,
  requiredEvidenceKinds[]
}

Obligation =
  | RequirementObligation {
      base: ObligationBase,
      kind: acceptance_criterion | functional_requirement | edge_case |
            business_rule | source_supported_value_treatment
    }
  | UserVisibleStateObligation { base: ObligationBase, kind: user_visible_state }
  | ExactCopyObligation { base: ObligationBase, kind: exact_copy, tokenId }
  | ScopeObligation {
      base: ObligationBase,
      kind: scope_guard | non_goal | prohibited_behavior
    }
  | DesignObligation {
      base: ObligationBase,
      kind: data_state | contract | research_prerequisite |
            missing_repository_prerequisite,
      designRecordIds[]
    }
  | ScenarioObligation { base: ObligationBase, kind: quickstart, scenarioId }
  | ExperienceObligation {
      base: ObligationBase,
      kind: accessibility | responsive | visual_system,
      preservedTokenIds[]
    }
  | PlanCoverageObligation {
      base: ObligationBase,
      kind: plan_coverage,
      coverageEntryId
    }

ObligationLedger {
  obligationLedgerStateId,
  inputPlanStateId,
  obligations: Obligation[]
}

ObligationCluster {
  clusterId,
  ordinal,
  projectId?,
  phaseHint,
  obligationIds[],
  estimatedInputBytes,
  estimatedInputTokens
}

ObligationPartition {
  obligationPartitionStateId,
  obligationLedgerStateId,
  unitPartitionContractId,
  clusters: ObligationCluster[]
}

CompactTaskIndexEntry {
  internalKey,
  phase,
  kind,
  obligationIds[],
  readFileIds[],
  writeFileIds[],
  verificationMode
}

CompactTaskIndex {
  compactTaskIndexStateId,
  entries: CompactTaskIndexEntry[]
}

TaskEdgePartition {
  edgePartitionId,
  ordinal,
  visibleInternalKeys[],
  requiredPairKeys[],
  estimatedInputBytes,
  estimatedInputTokens
}

TaskDependencyPartitionState {
  taskDependencyPartitionStateId,
  compactTaskIndexStateId,
  unitPartitionContractId,
  partitions: TaskEdgePartition[]
}

TaskBoundaryIndex {
  taskBoundaryIndexStateId,
  compactTaskIndexStateId,
  boundaryFacts: {
    internalKey,
    predecessorPhaseKeys[],
    sharedWriteFileIds[],
    redThenGreenTargetKeys[]
  }[]
}

ProjectPathCandidate {
  projectId,
  repoRelativePath,
  declaredKind,
  plannedIntent: create,       // existing files must be selected by fileId
  declaredBy
}

PathIntentProposal {
  pathIntentKey,
  pathIntentOptionId,
  nameSourceId,
  placementAnchorFileId?,
  requestedCapabilities: (create | copy_destination)[]
}

PathIntentOptionId { optionRuleId, projectId, boundSourceRootIds[] }

PathIntentOption {
  pathIntentOptionId: PathIntentOptionId,
  environmentId,
  fileKindId,
  semanticRoleId,
  allowedPathTemplateIds[],
  capabilityCeiling: (create | copy_destination)[]
}

PathIntentOptionRegistry {
  compiledEnginePolicyStateId,
  planUnitId,
  options: PathIntentOption[]             // complete bounded choices for the unit
}

PresetPathTemplate {
  pathTemplateId,
  pathIntentOptionRuleId,
  fileKindId,
  semanticRoleId,
  directoryStrategy:
    | { kind: fixed, repoRelativeDirectory }
    | { kind: colocated_with_anchor }
    | { kind: mirrored_from_anchor, sourceRootId, targetRootId },
  nameTransformId,                       // compiler-owned and versioned
  basenamePrefix,
  basenameSuffix,
  extension,
  extensionRuleId
}

PathNameSourceRegistry {
  registryStateId,
  sources: {
    nameSourceId,
    originId,                // specification/entity/plan-role record ID
    canonicalText: BusinessText
  }[]
}

PathCandidateRecord {
  pathCandidateId,
  pathIntentKey,
  pathIntentOptionId,
  nameSourceId,
  pathTemplateId?,
  candidate: ProjectPathCandidate,
  origin: engine_enumerated | validated_model_fallback,
  validationEvidenceIds[]
}

PathCandidateRegistry {
  pathCandidateRegistryStateId,
  compiledEnginePolicyStateId,
  inputFileRegistryStateId,
  nameSourceRegistryStateId,
  records: PathCandidateRecord[]
}

ProposedPathSelection =
  | { kind: select_candidate, pathCandidateId }
  | { kind: raw_path_fallback, candidate: ProjectPathCandidate }

FileRecord {
  fileId,
  projectId,
  repoRelativePath,
  environmentId,
  kind,
  policyCapabilityCeiling: (read | create | patch | replace | copy_destination | delete)[],
  declaredBy,
  source: repository_existing | generated_existing | plan_declared,
  expectedExistence: present | absent
}

PlanFileGrant {
  fileId,
  plannedIntent: read | create | update | delete,
  authorizedCapabilities: (read | create | patch | replace | copy_destination | delete)[]
}

FileRegistryState {
  fileRegistryStateId,
  revision,
  nextFileOrdinal,
  retiredFileIds[],
  files: FileRecord[]
}

RuntimeFileStateRecord {
  fileId,
  existence: present | absent,
  descriptorRevision,
  lastFileStateTransitionId?
}

RuntimeFileState {
  runtimeFileStateId,
  inputPlanStateId,
  revision,
  records: RuntimeFileStateRecord[]
}

FileStateTransition {
  fileStateTransitionId,
  source:
    | { kind: operation_record, operationRecordId }
    | { kind: command_promotion, commandPromotionEvidenceId, commandId,
        commandDeltaEntryOrdinal },
  fileId,
  expectedRuntimeFileStateRevision,
  before: present | absent,
  after: present | absent,
  transitionKind: create | modify | replace | copy_create | copy_replace | delete
}

FileStateTransitionRegistry {
  fileStateTransitionRegistryId,
  taskExecutionAttemptId,
  inputRuntimeFileStateId,
  revision,
  records: FileStateTransition[],
  retiredFileStateTransitionIds[]
}

RepositoryFactRegistryState {
  repositoryFactStateId,
  environmentIds[],
  facts: RegisteredRepositoryFact[]
}

RegisteredRepositoryFact {
  factId,
  valueId,
  value:
    | ManifestFieldFact { projectId, jsonPointer, scalarValue }
    | DependencyFact { projectId, ecosystem, packageName, versionConstraint }
    | CommandCapabilityFact { projectId, commandId, available }
    | FilePresenceFact { fileId, present, kind }
    | ProjectOwnershipFact { projectId, environmentId, manifestId }
    | PresetRuleFact { environmentId, ruleId, selectedValueId },
  gatePolicy: must_equal_until_implementation |
              transition_requires_task_binding | informational,
  evidenceIds[]
}

TaskGraph {
  tasks: TaskDefinition[],
  dependencies: TaskDependency[],
  sharedResourceLocks: SharedResourceLock[]
}

TaskProposalGraph {
  proposals: TaskDefinitionProposal[],
  dependencies: TaskProposalDependency[]
}

TaskDependencyProposal {
  predecessorInternalKey,
  successorInternalKey,
  reason: SemanticText
}

TaskProposalDependency {
  predecessorInternalKey,
  successorInternalKey,
  basis: explicit | semantic_reconciliation | engine_derived,
  reason: SemanticText
}

TaskDependency {
  predecessorTaskId,
  successorTaskId,
  basis: explicit | semantic_reconciliation | engine_derived,
  reason: SemanticText
}

SharedResourceRegistry {
  resources: SharedResourceRecord[]
}

SharedResourceRecord {
  resourceId,
  kind: manifest | lockfile | schema_registry | generated_index |
        command_capability | project_exclusive,
  owningProjectId,
  derivedFileIds[],
  derivedCommandIds[],
  allowedModes: (shared | exclusive)[]
}

SharedResourceLock {
  taskId,
  resourceId,
  mode: shared | exclusive
}

TaskFileCapabilityRecord {
  taskId,
  fileId,
  role: read | write,
  plannedIntent: read | create | update | delete,
  authorizedCapabilities: (read | create | patch | replace |
                           copy_destination | delete)[],
  planFileGrantEvidenceId,
  fileKindPolicyEvidenceId,
  globalPolicyEvidenceId
}

TaskFileCapabilityRegistry {
  taskFileCapabilityRegistryStateId,
  inputPlanStateId,
  records: TaskFileCapabilityRecord[]
}

TaskDefinitionState {
  taskDefinitionStateId,
  inputPlanStateId,
  inputClarificationStateId,
  inputClarificationStateRevision,
  inputPrincipleRegistryStateId,
  inputPrincipleRegistryStateRevision,
  principleSelections: ApplicablePrincipleSelection[],
  passiveLiteralRegistryStateId,
  obligationLedger: ObligationLedger,
  sharedResourceRegistry: SharedResourceRegistry,
  taskFileCapabilityRegistry: TaskFileCapabilityRegistry,
  graph: TaskGraph,
  factTransitionBindings: FactTransitionBinding[]
}

FactTransitionBinding {
  factId,
  taskId,
  transitionRuleId
}

TaskRuntimeRecord {
  taskId,
  status: pending | remediation_pending | executing | validation_failed | failed | blocked | completed | needs_reconciliation,
  leaseId?,
  transactionId?,
  activeExecutionCheckpointId?,
  evidenceIds[]
}

TaskRuntimeState {
  taskDefinitionStateId,
  runtimeRevision,
  currentRuntimeFileStateId,
  currentRuntimeFileStateRevision,
  currentExecutionEvidenceRegistryStateId,
  currentExecutionEvidenceRegistryRevision,
  records: TaskRuntimeRecord[]
}

TaskExecutionAttempt {
  taskExecutionAttemptId,
  taskLeaseId,
  ordinal,
  parentTaskExecutionAttemptId?,
  operationIntentPlanId,
  baseTaskOverlayRevision,
  baseRuntimeFileStateId,
  baseRuntimeFileStateRevision,
  principleRegistryStateId,
  principleRegistryStateRevision,
  principleSelectionIds[],
  disposition: active | superseded | committed | failed
}

TaskExecutionAttemptRegistry {
  taskExecutionAttemptRegistryId,
  taskDefinitionStateId,
  taskId,
  taskLeaseId,
  revision,
  activeTaskExecutionAttemptId?,
  attempts: TaskExecutionAttempt[]
}

OperationIntentPlan {
  operationIntentPlanId,
  taskDefinitionStateId,
  taskLeaseId,
  taskId,
  operationIntents: OperationIntent[],
  rationale: SemanticText
}

OperationIntentPlanProposal {
  taskId,
  orderedIntents: OperationIntentProposal[],
  rationale: SemanticText
  // No intent IDs, plan ID, paths, target-state assertions, or commands.
}

OperationIntentPlanValidation {
  taskId,
  orderedProposalCount,
  validatedProposalOrdinals[],
  simulatedFileLifecycleEvidenceIds[],
  exactTaskScopeEvidenceId,
  completenessEvidenceId
}

OperationIntentProposal =
  | CreateIntentProposal { fileId }
  | UpdateIntentProposal { fileId }
  | ReplaceIntentProposal { fileId }
  | CopyIntentProposal { sourceId, destinationFileId }
  | DeleteIntentProposal { fileId }

OperationIntent =
  | CreateIntent { operationIntentId, fileId }
  | UpdateIntent { operationIntentId, fileId }
  | ReplaceIntent { operationIntentId, fileId }
  | CopyIntent { operationIntentId, sourceId, destinationFileId }
  | DeleteIntent { operationIntentId, fileId }

ValidatedAutomatedVerificationResult =
  | CommandAutomatedVerificationResult {
      authorizationId,
      commandId,
      commandSavepointId,
      processOutcome: ValidatedCommandProcessOutcome,
      evidencePredicateId?,
      resourceQuotaValidation: CommandResourceQuotaValidation,
      commandDeltaValidation: CommandDeltaValidation,
      disposition:
        | { kind: promoted, commandPromotionEvidenceId }
        | { kind: discarded, discardEvidence: CommandSavepointDiscardEvidence },
      validatorId
    }
  | CopySourceAutomatedVerificationResult {
      operationIntentId,
      operationAuthorizationId,
      copySourceRegistryId,
      copySourceRegistryRevision,
      copySourceId,
      copySourceBlobId,
      copyPolicyId,
      validatorId,
      validatorVersion,
      result: passed
    }
  | OperationLocalAutomatedVerificationResult {
      operationIntentId,
      operationAuthorizationId,
      operationSavepointId,
      targetFileIds[],
      validatorId,
      validatorVersion,
      validationRuleIds[],
      result: passed
    }
  | FileDeltaAutomatedVerificationResult {
      operationIntentId,
      operationAuthorizationId,
      operationSavepointId,
      targetFileIds[],
      fileDeltaValidation: OperationFileDeltaValidation,
      validatorId,
      validatorVersion,
      result: passed
    }

VerificationEvidence =
  | AutomatedVerificationEvidence {
      evidenceId,
      result: ValidatedAutomatedVerificationResult,
      observedAt
    }
  | ManualVerificationEvidence {
      evidenceId,
      manualVerificationSubmissionId: ManualVerificationSubmissionId,
      evidencePredicateId,
      scenarioId,
      observation: BusinessText,
      actor: AuthenticatedActorRef,
      authenticationEvidenceId,
      taskDefinitionStateId,
      taskId,
      taskExecutionCheckpointId,
      inputTaskRuntimeRevision,
      inputExecutionEvidenceRegistryStateId,
      inputExecutionEvidenceRegistryStateRevision,
      observedAt
    }

OperationPromotionEvidence {
  evidenceId,
  operationRecordId,
  operationIntentId,
  savepointId,
  prePromotionOverlayRevision,
  postPromotionOverlayRevision,
  changedFileIds[],
  observedAt
}

CommandPromotionEvidence {
  evidenceId,
  commandId,
  commandSavepointId,
  prePromotionOverlayRevision,
  postPromotionOverlayRevision,
  promotedEntries: {
    commandDeltaEntryOrdinal,
    fileId,
    deltaKind: create | modify | delete
  }[],
  ephemeralDiscardEvidence: CommandEphemeralDiscardEvidence,
  observedAt
}

ExecutionEvidence = VerificationEvidence |
                    OperationPromotionEvidence |
                    CommandPromotionEvidence

ExecutionDiagnosticRecord {
  diagnosticRecordId,
  diagnostic: Diagnostic,
  sourceOutcome:
    | { kind: command_process,
        commandId, commandSavepointId, rejectedOutcome: RejectedCommandProcessOutcome }
    | { kind: validator, validatorId, validationObservationId },
  taskId?,
  operationIntentId?,
  commandId?
}

ExecutionEvidenceIdLedger {
  nextEvidenceOrdinal,
  nextDiagnosticRecordOrdinal,
  retiredEvidenceIds[],
  retiredDiagnosticRecordIds[]
}

ExecutionEvidenceAllocation {
  kind: verification | operation_promotion | command_promotion,
  evidenceId,
  inputNextEvidenceOrdinal,
  successorIdLedger: ExecutionEvidenceIdLedger
  // The successor is mandatory output from every evidence-ID assign action.
  // The matching append consumes it, and the next allocation consumes the
  // ledger carried by that append; a sibling may never reuse the predecessor.
}

ExecutionEvidenceAllocationRetirement {
  evidenceId,
  failureKind: post_allocation_pre_append,
  inputAllocationSuccessorLedger: ExecutionEvidenceIdLedger,
  successorIdLedger: ExecutionEvidenceIdLedger,
  noCanonicalRecordReference: true
  // Before retry/clean exit this successor is persisted in an otherwise
  // authority-equal checkpoint/transaction. If a task adapter boundary is
  // ready, it remains byte/value-equal so restart recovery still owns it.
}

ExecutionEvidenceRegistryState {
  executionEvidenceRegistryStateId,
  taskDefinitionStateId,
  revision,
  idLedger: ExecutionEvidenceIdLedger,
  evidence: ExecutionEvidence[],
  diagnostics: ExecutionDiagnosticRecord[]
}

ExecutionEvidenceInvalidationRecord {
  evidenceInvalidationRecordId,
  cause: final_validation_failed | reference_changed | specification_changed |
         principle_changed | repository_fact_changed | plan_rejected |
         tasks_rejected | task_definition_replaced,
  inputExecutionEvidenceRegistryStateId,
  inputExecutionEvidenceRegistryStateRevision,
  retiredEvidenceIds[],
  affectedTaskIds[],
  nextExecutionEvidenceRegistryStateId,
  nextExecutionEvidenceRegistryStateRevision
}

EditableSpecificationViewStateBinding {
  workflowArtifactRegistryStateId,
  specificationProvenanceStateId,
  specificationAcknowledgementStateId,
  clarificationStateId,
  passiveLiteralRegistryStateId,
  referenceStateId
}

EditableSpecificationViewAuthorityBinding {
  artifactSelector: EditableSpecificationView,
  stateBinding: EditableSpecificationViewStateBinding,
  engineAssignedPath,
  rendererContractVersion,
  protectedStructureContractId
}

EditableSpecificationArtifactView {
  artifactSelector: EditableSpecificationView,
  stateBinding: EditableSpecificationViewStateBinding,
  engineAssignedPath,
  rendererContractVersion,
  renderedBytes,
  editableByUser: true,
  protectedStructureContractId
}

GeneratedView {
  viewKind: reference_context | plan | research | data_model | contract | quickstart | tasks,
  artifactSelector:
    | { kind: singleton, viewKind: reference_context | plan | research |
                         data_model | quickstart | tasks }
    | { kind: contract, contractId },
  stateBinding:
    | { workflowArtifactRegistryStateId,
        referenceStateId, passiveLiteralRegistryStateId }
    | { workflowArtifactRegistryStateId,
        planStateId, fileRegistryStateId, passiveLiteralRegistryStateId,
        inputReferenceStateId }
    | { workflowArtifactRegistryStateId,
        taskDefinitionStateId, taskRuntimeRevision, inputPlanStateId,
        fileRegistryStateId, passiveLiteralRegistryStateId,
        inputReferenceStateId },
  engineAssignedPath,
  rendererContractVersion,
  renderedBytes,
  editableByUser: false
}

ReviewDecision {
  reviewDecisionId,
  reviewSubmissionId: ReviewSubmissionId,
  stage: plan | tasks,
  decision: approve | reject,
  target:
    | { planStateId }
    | { taskDefinitionStateId },
  feedback?: BusinessText,
  targetUnitIds[]?,
  actor: AuthenticatedActorRef,
  authenticationEvidenceId,
  decidedAt
}

ReviewDecisionAllocation {
  reviewDecisionId,
  inputReviewDecisionRegistryStateId,
  inputReviewDecisionRegistryStateRevision,
  allocatedOrdinal,
  nextReviewDecisionOrdinal,
  status: reserved
}

ReviewDecisionRegistryState {
  reviewDecisionRegistryStateId,
  featureId,
  revision,
  parentReviewDecisionRegistryStateId?,
  nextReviewDecisionOrdinal,
  decisions: ReviewDecision[],
  retiredReviewDecisionIds[]
  // Approval activity is a projection in WorkflowState.activeApprovalDecisionIds;
  // rework clears that projection but never rewrites immutable decision history.
}

WorkflowStage = new | specifying | spec_clarification_pending | specified |
                planning | plan_clarification_pending | plan_review_pending | planned |
                tasking | tasks_clarification_pending | tasks_review_pending | tasked |
                implementing | final_validation_failed |
                implementation_reconciliation_spec |
                implementation_reconciliation_plan |
                implementation_reconciliation_tasks |
                implemented | blocked | failed | cancelled

WorkflowState {
  workflowStateId,
  featureId,
  revision,
  stage: WorkflowStage,
  boundWorkflowIds: WorkflowId[],
  // Sorted unique IDs whose compiled graphs have participated in durable
  // feature history. Registry refresh compares their stable semantic authority;
  // source-ordinal shifts and unrelated definitions do not invalidate this
  // feature.
  workflowArtifactRegistryStateId,
  bootstrapAuthorityStateId,
  currentReferenceStateId?,     // absent only in a newly activated pre-snapshot specifying state
  currentPrincipleRegistryStateId,
  currentPrincipleRegistryStateRevision,
  currentActorEvidenceRegistryStateId,
  currentActorEvidenceRegistryStateRevision,
  currentReviewDecisionRegistryStateId,
  currentReviewDecisionRegistryStateRevision,
  currentWorkflowControlEventRegistryStateId,
  currentWorkflowControlEventRegistryStateRevision,
  currentPassiveLiteralRegistryStateId,
  currentPassiveLiteralRegistryStateRevision,
  currentClarificationStateId,
  currentClarificationStateRevision,
  openClarificationIdsByStage: { spec[], plan[], tasks[] },
  currentFeatureRequestStateId?,
  currentSpecificationProvenanceStateId?,
  currentPlanInputAuthorityStateId?,
  currentPlanStateId?,
  currentTaskDefinitionStateId?,
  currentTaskRuntimeRevision?,
  currentFinalValidationRecordId?,
  currentReworkInvalidationRecordId?,
  activeApprovalDecisionIds[]
}

FinalValidationRecord {
  finalValidationRecordId,
  finalValidationInvocationId,
  taskDefinitionStateId,
  inputRuntimeRevision,
  validationOverlayId,
  commandIds[],
  evidenceIds[],
  diagnosticRecordIds[],
  outcome: passed | failed,
  overlayDiscardEvidence: FinalValidationOverlayNormalDiscardEvidence,
  completedAt
}

FinalValidationOverlayDiscardObservation {
  validationOverlayId,
  finalValidationInvocationId: FinalValidationInvocationId,
  finalValidationOverlayCollectionArtifactPathId,
  ownerProcessInstanceId,
  ownerProcessLeaseId: FeatureExecutionProcessLeaseId,
  featureExecutionLockEpoch,
  expectedOverlayRevision,
  disposition: discarded_now | already_absent,
  discardedEntryCount,
  residualEntryCount,
  residualBytes,
  completeBoundedParentTreeInspection: boolean,
  projectSpecsAndEngineStateChanged: boolean,
  adapterId,
  adapterContractVersion,
  discardedAt
}

FinalValidationOverlayDiscardAdapterFailureObservation {
  validationOverlayId,
  finalValidationInvocationId: FinalValidationInvocationId,
  ownerProcessLeaseId: FeatureExecutionProcessLeaseId,
  featureExecutionLockEpoch,
  expectedOverlayRevision,
  failurePhase: recursive_tree_removal | result_delivery | adapter_unavailable,
  parentTreeDisposition: proven_absent | indeterminate,
  boundedAdapterErrorCode,
  adapterId,
  adapterContractVersion
}

FinalValidationOverlayDiscardOutcome =
  | { kind: discard_observed,
      observation: FinalValidationOverlayDiscardObservation }
  | { kind: adapter_failed,
      failure: FinalValidationOverlayDiscardAdapterFailureObservation }

FinalValidationOverlayNormalDiscardEvidence {
  kind: normal_completed_discard,
  discardOutcome: FinalValidationOverlayDiscardOutcome,
  validationOverlayId,
  finalValidationInvocationId: FinalValidationInvocationId,
  finalValidationOverlayCollectionArtifactPathId,
  ownerProcessInstanceId,
  ownerProcessLeaseId: FeatureExecutionProcessLeaseId,
  featureExecutionLockEpoch,
  expectedOverlayRevision,
  commandChildSavepointIds: FinalValidationCommandSavepointId[],
  commandChildDiscardEvidence:
    FinalValidationCommandSavepointDiscardEvidence[],
  everyCommandChildCoveredExactlyOnceAndAbsent: true,
  sandboxAdapterId,
  sandboxAdapterVersion,
  discardedEntryCount,
  residualEntryCount: 0,
  residualBytes: 0,
  projectSpecsAndEngineStateUnchanged: true,
  verifiedAbsent: true,
  discardedAt
}

FinalValidationOverlayRecursiveAbortEvidence {
  kind: recursive_parent_abort,
  validationOverlayId,
  finalValidationInvocationId: FinalValidationInvocationId,
  finalValidationOverlayCollectionArtifactPathId,
  ownerProcessLeaseId: FeatureExecutionProcessLeaseId,
  featureExecutionLockEpoch,
  expectedOverlayRevision,
  abortCause:
    FinalValidationCommandSavepointCreationRejection |
    FinalValidationCommandSavepointDiscardRejection,
  parentTreeDiscardOutcome: FinalValidationOverlayDiscardOutcome,
  parentAddressedOnlyByValidatedHeaderAndCollectionAuthority: true,
  rejectedOrIndeterminateChildNeverAddressedOrTrusted: true,
  completeParentTreeRemoved: true,
  residualParentTreeEntryCount: 0,
  residualParentTreeBytes: 0,
  projectSpecsAndEngineStateUnchanged: true,
  outerFeatureExecutionLockAndProcessLeaseStillLive: true,
  finalValidationRecordForbidden: true
}

FinalValidationOverlayDiscardRejection {
  requestedMode: normal_completed_discard | recursive_parent_abort,
  discardOutcome: FinalValidationOverlayDiscardOutcome,
  rejectionCode: adapter_failure | header_mismatch |
                 collection_mismatch | owner_control_mismatch |
                 overlay_revision_mismatch | incomplete_parent_tree_inspection |
                 residual_parent_tree_entries | project_or_engine_state_changed |
                 child_coverage_incomplete | adapter_contract_mismatch,
  finalValidationRecordForbidden: true,
  runnerFailStopAndFreshRunOrphanRecoveryRequired: true
}

OverlayDiscardEvidence =
  FinalValidationOverlayNormalDiscardEvidence |
  FinalValidationOverlayRecursiveAbortEvidence

FinalValidationRunnerFailStopEvidence =
  RunnerCapabilityLossFailStopEvidence |
  FinalValidationRejectedCollectionLockCleanupFailStopEvidence |
  FinalValidationCollectionLockReleaseFailStopEvidence |
  FinalValidationCreationCleanupFailStopEvidence |
  FinalValidationOverlayDiscardRejection

ReworkInvalidationRecord {
  invalidationRecordId,
  cause: reference_changed | specification_changed | principle_changed |
         repository_fact_changed | bootstrap_reference_ingestion_changed |
         bootstrap_specification_contract_changed |
         bootstrap_technical_planning_changed | plan_rejected |
         tasks_rejected | final_validation_scope_gap,
  bootstrapChangeEvidence?: MaterializedBootstrapChangeEvidence,
  earliestOwnerStage: specify | plan | tasks,
  invalidatedPlanStateIds[],
  invalidatedTaskDefinitionStateIds[],
  invalidatedApprovalIds[],
  implementationWatermark: no_commits | commits_exist
}

WorkflowControlEventRegistryState {
  workflowControlEventRegistryStateId,
  featureId,
  revision,
  parentWorkflowControlEventRegistryStateId?,
  nextFinalValidationRecordOrdinal,
  nextReworkInvalidationRecordOrdinal,
  nextEvidenceInvalidationRecordOrdinal,
  finalValidationRecords: FinalValidationRecord[],
  reworkInvalidationRecords: ReworkInvalidationRecord[],
  evidenceInvalidationRecords: ExecutionEvidenceInvalidationRecord[],
  retiredFinalValidationRecordIds[],
  retiredReworkInvalidationRecordIds[],
  retiredEvidenceInvalidationRecordIds[]
}

RawReferenceFeedbackSubmission {
  expectedReferenceStateId,
  change,
  feedback: RawInputText,
  authenticationLeaseRef
}

ValidatedReferenceFeedbackSubmission {
  submissionHandleId,
  referenceStateId,
  change,
  feedback: BusinessText,
  structuralEvidenceIds[]
}

AuthenticatedReferenceFeedbackBinding {
  submissionHandleId,
  authenticationEvidenceId,
  actor: AuthenticatedActorRef,
  intendedEventKind: reference_feedback,
  boundAt
}

ReferenceFeedback {
  feedbackId,
  referenceStateId,
  change:
    | { intent: reextract_block, target: { kind: block, sourceId, blockId } }
    | { intent: add_claim, target: { kind: chunk, sourceId, blockId, chunkId } }
    | { intent: correct_claim_classification, target: { kind: claim, claimId },
        newClaimKind: business | design | technical | validation |
                      implementation_assumption | open_question | scope_guard }
    | { intent: remove_claim, target: { kind: claim, claimId } }
    | { intent: correct_token, target: { kind: token, tokenId }, replacementCitationId },
  feedback: BusinessText,
  actor: AuthenticatedActorRef,
  authenticationEvidenceId,
  submittedAt
}

ReferenceConflictResolutionDecision {
  decisionId,
  targetReferenceStateId,
  conflictId,
  selectedClaimIds[],
  decisionBasis:
    | { kind: controlled_clarification_response,
        clarificationId, clarificationResponseId }
    | { kind: authenticated_business_rationale, rationale: BusinessText },
  actor: AuthenticatedActorRef,
  authenticationEvidenceId,
  decidedAt
}

SpecificationEditSubmissionId { featureId, submissionOrdinal: PositiveInteger }
SpecificationEditChangeSetId {
  specificationEditSubmissionId: SpecificationEditSubmissionId,
  changeSetOrdinal: PositiveInteger
}
SpecificationAcknowledgementId { featureId, acknowledgementOrdinal: PositiveInteger }

SpecificationEditFailureCause =
  change_set_id_allocation_failed |
  authenticated_binding_build_failed |
  authenticated_event_build_failed |
  acknowledgement_build_failed |
  acknowledgement_coverage_failed |
  plan_input_candidate_build_failed |
  plan_input_candidate_validation_failed |
  transaction_candidate_abandoned

SpecificationEditAuthenticationEvidenceRetirement {
  allocation: AuthenticationEvidenceIdAllocation,
  specificationEditSubmissionId: SpecificationEditSubmissionId,
  cause: SpecificationEditFailureCause,
  retiredAt
}

SpecificationAcknowledgementIdLedger {
  nextSubmissionOrdinal,
  nextChangeSetOrdinalBySubmissionId,
  nextAcknowledgementOrdinal,
  retiredSubmissionIds[],
  retiredChangeSetIds[],
  retiredAcknowledgementIds[]
}

SpecificationAcknowledgementAllocatedId =
  | SpecificationEditSubmissionAllocation {
      kind: submission,
      specificationEditSubmissionId: SpecificationEditSubmissionId
    }
  | SpecificationEditChangeSetAllocation {
      kind: change_set,
      specificationEditChangeSetId: SpecificationEditChangeSetId
    }
  | SpecificationAcknowledgementAllocation {
      kind: acknowledgement,
      specificationAcknowledgementId: SpecificationAcknowledgementId
    }

SpecificationAcknowledgementIdRetirement {
  cause: SpecificationEditFailureCause,
  failedCandidateDisposition:
    | { kind: no_edit_journal_prepared }
    | { kind: edit_journal_rolled_back,
        abandonedTransactionId: TransactionId },
  retiredAllocations: SpecificationAcknowledgementAllocatedId[],
  retiredAt
  // Nonempty and canonically ordered, beginning with exactly one submission
  // allocation. It accounts for every acknowledgement-ledger ID allocated by
  // that failed edit attempt and no accepted event.
}

SpecificationAcknowledgement {
  acknowledgementId: SpecificationAcknowledgementId,
  specificationEditSubmissionId: SpecificationEditSubmissionId,
  specificationEditChangeSetId: SpecificationEditChangeSetId,
  featureId,
  recordKey,
  canonicalBusinessContent: BusinessContentIdentity,
  intent: accept_user_authored_specification_content,
  actor: AuthenticatedActorRef,
  authenticationEvidenceId: AuthenticationEvidenceId,
  acknowledgedAt
}

RawSpecificationEditSubmission {
  expectedWorkflowStateId,
  expectedWorkflowStateRevision,
  expectedSpecificationProvenanceStateId,
  expectedSpecificationProvenanceStateRevision,
  expectedSpecificationAcknowledgementStateId,
  expectedSpecificationAcknowledgementStateRevision,
  expectedEditableViewBinding: EditableSpecificationViewAuthorityBinding,
  authenticationLeaseRef
  // The lease reference is runner-held, opaque, single-use, nonserializable,
  // and is consumed only after all non-authentication validation succeeds.
}

SpecificationEditCaptureAuthority {
  expectedWorkflowStateId,
  expectedWorkflowStateRevision,
  expectedSpecificationProvenanceStateId,
  expectedSpecificationProvenanceStateRevision,
  expectedSpecificationAcknowledgementStateId,
  expectedSpecificationAcknowledgementStateRevision,
  expectedEditableViewBinding: EditableSpecificationViewAuthorityBinding,
  capturedArtifactFileIdentity,
  capturedAt
  // Durable freshness/audit projection only: no submitted bytes, credential,
  // authentication lease, or run-local handle is present.
}

CapturedSpecificationEditSubmission {
  submissionHandleId,          // run-local, nonserializable
  captureAuthority: SpecificationEditCaptureAuthority,
  immutableSubmittedBytesHandle
}

ValidatedSpecificationEditChangeSet {
  submissionHandleId,
  changeSetHandleId,           // run-local, nonserializable
  captureAuthority: SpecificationEditCaptureAuthority,
  inputSpecificationProvenanceStateId,
  inputSpecificationAcknowledgementStateId,
  changedRecords: {
    recordKey,
    changeKind: add | modify | remove,
    priorBusinessContentIdentity?,
    nextBusinessContentIdentity?
  }[],
  protectedStructureChanges: [],
  parseAndDiffEvidenceIds[]
}

DurableSpecificationEditAuthenticationBinding {
  specificationEditSubmissionId: SpecificationEditSubmissionId,
  specificationEditChangeSetId: SpecificationEditChangeSetId,
  captureAuthority: SpecificationEditCaptureAuthority,
  authenticationEvidenceId: AuthenticationEvidenceId,
  actor: AuthenticatedActorRef,
  intendedEventKind: specification_edit,
  boundAt
  // This is the only binding projection admitted by canonical state.
}

AuthenticatedSpecificationEditBinding {
  submissionHandleId,
  changeSetHandleId,
  durableBinding: DurableSpecificationEditAuthenticationBinding,
  runLocal: true,
  serializableAsCanonicalState: false
}

SpecificationAcknowledgementState {
  acknowledgementStateId,
  revision,
  idLedger: SpecificationAcknowledgementIdLedger,
  editEvents: AuthenticatedSpecificationEditEvent[],
  entries: SpecificationAcknowledgement[]
}

SpecificationEditFailureActorEvidenceRegistryMutation {
  inputActorEvidenceRegistryStateId,
  inputActorEvidenceRegistryStateRevision,
  retirement: SpecificationEditAuthenticationEvidenceRetirement,
  nextActorEvidenceRegistryState: ActorEvidenceRegistryState
  // Entries are byte-equal; only identity/revision, next ordinal, and the exact
  // retired authentication-evidence ID may change.
}

SpecificationAcknowledgementRetirementPlanInputMutation =
  | NoPlanInputAuthorityRetirementRebind {
      workflowStage: specified,
      reason: no_current_plan_input_authority
    }
  | ReboundPlanningInputAuthorityForRetirement {
      workflowStage: planning,
      inputPlanInputAuthorityStateId,
      inputPlanInputAuthorityStateRevision,
      nextPlanInputAuthorityState: PlanInputAuthorityState
    }

AuthenticatedSpecificationEditEvent {
  specificationEditSubmissionId: SpecificationEditSubmissionId,
  specificationEditChangeSetId: SpecificationEditChangeSetId,
  binding: DurableSpecificationEditAuthenticationBinding,
  changeSet: {
    inputSpecificationProvenanceStateId,
    inputSpecificationAcknowledgementStateId,
    changedRecords[],
    parseAndDiffEvidenceIds[]
  },
  acceptedAt
}

PlanInputSpecificationMutation =
  | UnchangedPlanInputSpecificationMutation {
      currentSpecificationProvenanceStateId,
      currentSpecificationAcknowledgementStateId,
      reason: direct_typed_specification_equality
    }
  | AuthenticatedPlanInputSpecificationEditMutation {
      editEvent: AuthenticatedSpecificationEditEvent,
      authenticationBinding: DurableSpecificationEditAuthenticationBinding,
      acknowledgements: SpecificationAcknowledgement[],
      inputSpecificationAcknowledgementStateId,
      inputSpecificationAcknowledgementStateRevision,
      successorAcknowledgementIdLedger: SpecificationAcknowledgementIdLedger
    }

ClarificationStage = spec | plan | tasks
ClarificationPrefix = S | P | T

ClarificationSubjectDescriptor =
  | SpecificationClarificationSubject {
      authorityRequirementId: AuthorityRequirementId,
      unitKind,
      stableUnitSelector,
      requiredFieldId,
      authorityGapKind,
      supportingClaimIds[],
      supportingCitationIds[]
    }
  | PlanClarificationSubject {
      authorityRequirementId: AuthorityRequirementId,
      planUnitKind,
      stableUnitSelector,
      requiredDecisionSlotId,
      authorityGapKind,
      supportingAuthorityIds[]
    }
  | TasksClarificationSubject {
      authorityRequirementId: AuthorityRequirementId,
      stableUnitSelector,
      obligationIds[],
      requiredTaskFieldId,
      authorityGapKind,
      supportingAuthorityIds[]
    }

ClarificationSubjectKey =
  | ReferenceConflictClarificationSubjectKey {
      targetId,
      stage: spec,
      authorityRequirementId: AuthorityRequirementId,
      stableUnitSelector: ReferenceConflictSubjectCoordinate,
      requiredSlotId: source_conflict_resolution,
      authorityGapKind: behavior_changing_reference_conflict,
      continuityContractVersion
      // Snapshot-local conflict/claim/citation IDs are deliberately excluded.
    }
  | AuthorityBoundClarificationSubjectKey {
      targetId,
      stage: ClarificationStage,
      authorityRequirementId: AuthorityRequirementId,
      stableUnitSelector,
      requiredSlotId              // required field/decision/task-field ID
    }
  // Engine-built stable subject coordinate; never a digest or model-authored.
  // Requirement identity and unit selector come from registered stable
  // semantics, not a regenerated candidate/state ID. Execution IDs, authority
  // revisions, evidence IDs and transient gap classifications are excluded.
  // Their current values belong to the descriptor/applicability binding.

ClarificationNeedProposal {
  subject: ClarificationSubjectDescriptor,
  question: BusinessText,
  whyRequired: BusinessText,
  answerSchema:
    | { kind: select_one, options: { optionKey, label: BusinessText }[] }
    | { kind: select_many, minSelections, maxSelections,
        options: { optionKey, label: BusinessText }[] }
    | { kind: bounded_business_text, maxBytes }
  // No clarification ID, filename, status, response, subject key, state ID,
  // or resolution may be returned by a model.
}

ClarificationNeedOrigin =
  | { kind: direct_need, sourceSemanticFindings: [] }
  | { kind: authority_reconciliation_gap,
      authorityRequirementId: AuthorityRequirementId,
      reconciliationValidationEvidenceIds[] }
  | { kind: no_invention_replacement,
      sourceSemanticFinding: SemanticFinding,
      replacementAuthorizationId }

ClarificationRecord {
  clarificationId,            // S01..S99, P01..P99, or T01..T99
  stage: ClarificationStage,
  ordinal,                     // 1..99 within the stage; never reused
  subjectKey: ClarificationSubjectKey,
  subject: ClarificationSubjectDescriptor,
  referenceConflictBinding?: ReferenceConflictClarificationBinding,
  currentApplicabilityBinding: {
    canonicalSubjectAuthorityIds[],
    authorityGapKind,
    validatedCurrentSubjectCorrespondence
  },
  question: BusinessText,
  whyRequired: BusinessText,
  origins: ClarificationNeedOrigin[],
  // Nonempty, canonically ordered and deduplicated by direct owner or semantic-
  // finding/authority-requirement identity. Multiple origins never create a
  // second clarification.
  answerSchema,
  recordRevision,
  lifecycle:
    | { status: open }
    | { status: resolved_by_user, clarificationResponseId }
    | { status: resolved_by_authority, clarificationResolutionId,
        authorityIds[] }
    | { status: cancelled_by_user, clarificationResponseId }
}

ClarificationUserSubmission {
  submittedFormBytes: RawSourceScalar, // parser-owned bounded capture, not a form field
  clarificationId,
  expectedClarificationStateId,
  expectedClarificationStateRevision,
  expectedRecordRevision,
  requestedStatus: open | closed | cancel,
  answer:
    | { kind: none }
    | { kind: selected_option, optionKey }
    | { kind: selected_options, optionKeys[] }
    | { kind: business_text, text: BusinessText }
    | { kind: defer, reason: BusinessText }
    | { kind: cancel, reason: BusinessText }
}

ClarificationResponse {
  clarificationResponseId,
  clarificationId,
  inputClarificationStateId,
  inputClarificationStateRevision,
  inputRecordRevision,
  submittedFormBytes: RawSourceScalar, // bounded exact validated capture, not rerendered
  answer:
    | { kind: selected_option, optionKey, canonicalLabel: BusinessText }
    | { kind: selected_options,
        selections: { optionKey, canonicalLabel: BusinessText }[] }
    | { kind: business_text, text: BusinessText }
    | { kind: defer, reason: BusinessText }
    | { kind: cancel, reason: BusinessText },
  actor: AuthenticatedActorRef,
  authenticationEvidenceId,
  answeredAt
}

ClarificationAuthorityResolutionProposal {
  clarificationId,
  subjectKey: ClarificationSubjectKey,
  authorityIds[],
  resolution: BusinessText
  // No lifecycle value or canonical resolution/evidence ID.
}

ClarificationAuthorityResolution {
  clarificationResolutionId,
  clarificationId,
  inputClarificationStateId,
  inputRecordRevision,
  authorityIds[],
  resolution: BusinessText,
  validationBinding:
    | { mode: deterministic_exact, validatorRuleIds[] }
    | { mode: semantic_authority_interpretation,
        compiledWorkflowAuthorityId,
        modelOperationId,
        requestSchemaResourceId,
        resultSchemaResourceId,
        validatorRuleIds[] },
  resolvedAt
}

SameKeyReferenceConflictTransitionOutcome =
  | CurrentAnswerAppliedReferenceConflictOutcome {
      kind: current_answer_applied,
      subjectKey: ReferenceConflictClarificationSubjectKey,
      clarificationId,
      currentConflictId,
      correspondence: CurrentReferenceConflictCorrespondence,
      conflictDecisionId,
      recordMutation: none
    }
  | SameIdOpenReferenceConflictOutcome {
      kind: refreshed_or_reopened_same_id,
      subjectKey: ReferenceConflictClarificationSubjectKey,
      clarificationId,
      currentConflictId,
      reason: open_or_unanswered | stale_answer,
      currentOpenRecord: ClarificationRecord
      // Only unprotected records; user-closed protection blocks before this
      // outcome is constructed when a required answer is no longer applicable.
    }

ObsoletePriorReferenceConflictClosure {
  subjectKey: ReferenceConflictClarificationSubjectKey,
  clarificationId,
  absenceCorrespondence: AbsentReferenceConflictCorrespondence,
  disposition:
    | { kind: preserved_user_closed, clarificationResponseId }
    | { kind: authority_closed,
        authorityResolution: ClarificationAuthorityResolution }
}

IntroducedCurrentReferenceConflictOpening {
  subjectKey: ReferenceConflictClarificationSubjectKey,
  currentConflictId,
  identityDisposition:
    | ReusedExistingConflictClarificationIdentity {
        kind: reused_existing_subject,
        clarificationId,
        inputRecordRevision
      }
    | AllocatedConflictClarificationIdentity {
        kind: allocated_absent_subject,
        clarificationId
      },
  currentOpenRecord: ClarificationRecord
  // A protected user-closed historical key cannot become an opening. Block
  // for user direction; neither reopen it nor allocate a duplicate ID.
}

ReferenceConflictClarificationSetTransition {
  inputClarificationStateId,
  inputClarificationStateRevision,
  currentReferenceStateId,
  reconciliation: ReferenceConflictSubjectSetReconciliation,
  sameKeyOutcomes: SameKeyReferenceConflictTransitionOutcome[],
  obsoletePriorClosures: ObsoletePriorReferenceConflictClosure[],
  introducedCurrentOpenings: IntroducedCurrentReferenceConflictOpening[],
  successorIdLedger: ClarificationIdLedger,
  expectedOpenCurrentSubjectKeys: ReferenceConflictClarificationSubjectKey[]
  // One complete registry mutation. Allocation/reuse is decided independently
  // for each C ∖ P key by exact global subject lookup; no P ∖ C entry is
  // paired with any C ∖ P entry. All arrays use canonical structural order.
}

ClarificationRegistryTransition =
  | SingleClarificationRecordTransition { record: ClarificationRecord }
  | SingleClarificationResponseTransition { response: ClarificationResponse }
  | SingleClarificationAuthorityResolutionTransition {
      resolution: ClarificationAuthorityResolution
    }
  | ReferenceConflictSetReconciliationTransition {
      setTransition: ReferenceConflictClarificationSetTransition
    }
  // The single-entry variants are invalid for every reference-state refresh
  // whose validated prior or current conflict-subject set is nonempty,
  // including equal-key current/stale option refresh. Only P=C=empty may omit
  // the complete set variant, so no intermediate registry can omit a required
  // current form or apply only part of a reconciliation.

ClarificationIdLedger {
  nextOrdinalByStage: { spec, plan, tasks },
  nextResponseOrdinal,
  nextResolutionOrdinal
  // V1 clarification allocations remain transaction-private until the complete
  // registry/view/workflow transaction commits. A failed uncommitted candidate
  // discards its successor ledger and may deterministically reselect the same
  // next ordinal; no candidate ID may enter a log, diagnostic, model request,
  // path, form, serializer, or adapter before that atomic commit. A committed
  // ordinal is advanced in this ledger and can never be reused.
}

ClarificationRegistryState {
  clarificationStateId,
  featureId,
  revision,
  idLedger: ClarificationIdLedger,
  currentReferenceStateId?,    // absent only before the first committed reference snapshot
  currentBootstrapAuthorityStateId,
  currentPrincipleRegistryStateId,
  currentPrincipleRegistryStateRevision,
  currentActorEvidenceRegistryStateId,
  currentActorEvidenceRegistryStateRevision,
  currentPassiveLiteralRegistryStateId,
  currentPassiveLiteralRegistryStateRevision,
  records: ClarificationRecord[],
  responses: ClarificationResponse[],
  authorityResolutions: ClarificationAuthorityResolution[]
  // The full registry survives successful replacement and abandoned executions.
  // Lookup includes open and closed records before allocating any new ID.
  // Reuse applicable answers. Refresh/reopen only unprotected records;
  // preserve user-closed forms and block an unresolved required subject under
  // design Section 23.2. Never allocate a duplicate or reset the ID ledger.
}

ClarificationView =
  | ClarificationSubmissionView {
      kind: open_submission,
      clarificationId,
      artifactPathId,
      engineAssignedPath,      // <featureDir>/clarify/<clarificationId>.md
      inputClarificationStateId,
      inputClarificationStateRevision,
      inputRecordRevision,
      recordLifecycleStatus: open,
      immutableQuestionProjection,
      userSubmissionProjection,
      renderedBytes,
      editableRegions: [frontmatter.requestedStatus, answer]
    }
  | ClarificationAuditView {
      kind: closed_audit,
      clarificationId,
      artifactPathId,
      engineAssignedPath,      // same registered historical path
      inputClarificationStateId,
      inputClarificationStateRevision,
      inputRecordRevision,
      recordLifecycleStatus: resolved_by_authority | cancelled_by_user,
      immutableQuestionProjection,
      immutableResolutionProjection,
      renderedBytes,
      editableRegions: []
    }
  | ClarificationUserClosedView {
      kind: preserved_user_closed,
      clarificationId,
      artifactPathId,
      engineAssignedPath,      // unchanged registered clarification path
      clarificationResponseId, // sole owner of original binding and submittedFormBytes
      editableRegions: []
      // A read/preservation precondition, not a transaction write member.
      // Old engineStatus/revision fields describe the accepted submission;
      // current canonical closure is read from the response/registry instead.
    }

SpecificationIdLedger {
  nextOrdinalByKind,
  retiredIds[]
}

SpecificationProvenanceEntry {
  recordKey,                 // fixed scalar key or engine-assigned repeatable record ID
  canonicalBusinessContent: BusinessContentIdentity,
  origin: reference_derived_feature_brief | reference_extracted |
          user_clarification | reference_and_user_clarification | user_authored,
  referenceStateId?,
  claimIds[],
  citationIds[],
  featureRequestId?,
  clarificationResponseIds[],
  userAcknowledgementId?
  // reference-only => nonempty claims/citations and no responses;
  // clarification-only => no claims/citations and nonempty responses;
  // mixed => both classes and origin=reference_and_user_clarification.
}

SpecificationProvenanceState {
  provenanceStateId,
  revision,
  featureRequestStateId,
  referenceStateId,
  acknowledgementStateId,
  clarificationStateId,
  passiveLiteralRegistryStateId,
  entries: SpecificationProvenanceEntry[],
  claimDispositions: SpecificationClaimDispositionEntry[]
}

SpecificationClaimDispositionEntry {
  claimId,
  disposition:
    | { kind: not_retained, claimDisposition: superseded | duplicate | conflicting }
    | { kind: mapped_to_spec, recordKeys[] }
    | { kind: context_only, signalIds[] }
    | { kind: blocking_conflict, conflictId }
    | { kind: open_question, signalId }
    | { kind: no_spec_relevance, reasonCode }
}
```

<a id="authority-reconciliation-contract"></a>

### 6.1 Authority reconciliation contract

```text
AuthorityOwnerStage = ClarificationStage
AuthorityDetectionStage = spec | plan | tasks | implement | recovery

AuthorityRequirementId {
  ownerStage: AuthorityOwnerStage,
  requirementKindId,
  stableUnitSelector,
  requiredSlotId,
  contractVersion
  // Structural tuple derived only from closed registries/current canonical
  // inputs. Never model-authored, content-hashed, or caller-selected.
}

AuthorityRequirednessSource =
  | SchemaRequiredness { schemaId, fieldId }
  | ObligationRequiredness { obligationId }
  | PolicyRequiredness { policyId, ruleId }
  | AcceptedAuthorityRequiredness { authorityId, recordSelector }

AuthorityRequirement {
  authorityRequirementId: AuthorityRequirementId,
  ownerStage: AuthorityOwnerStage,
  requirementKindId,
  requiredSlotId,
  requirednessSources: AuthorityRequirednessSource[],
  inputAuthorityIds[],
  reconciliationPolicyId,
  downstreamObligationIds[]
}

AuthorityRequirementLedger {
  detectionStage: AuthorityDetectionStage,
  inputAuthorityIds[],
  ownershipRegistryVersion,
  reconciliationPolicyRegistryVersion,
  requirements: AuthorityRequirement[]
  // Deterministic, exhaustive, canonical-order projection. It is rebuilt from
  // canonical authority and is neither a persisted competing truth nor a
  // fingerprint.
}

AuthorityCandidate {
  candidateAuthorityId,
  authorityRevision,
  candidateKindId,
  evidenceIds[],
  citationIds[],
  currentAuthorityValid: true
}

AuthorityCandidateSet {
  authorityRequirementId: AuthorityRequirementId,
  reconciliationPolicyId,
  inspectedPermittedAuthorityIds[],
  candidates: AuthorityCandidate[],
  deterministicEquivalenceClasses: {
    equivalenceRuleId,
    memberCandidateAuthorityIds[]
  }[]
  // Complete permitted-source accounting. No ranking, fuzzy/nearest match,
  // inferred candidate, or ambient model knowledge is representable.
}

AuthorityGapReason =
  missing | ambiguous | conflicting | multiple_non_equivalent |
  stale | unsupported | unregistered_ownership_or_policy

AuthorityReconciliationOutcome =
  | ResolvedExactlyOneAuthority {
      kind: resolved_exactly_one,
      authorityRequirementId: AuthorityRequirementId,
      resolution:
        | { kind: existing_authority, resolutionAuthorityId }
        | { kind: supported_candidate,
            immutableUnitOwnerId, candidateRevision,
            supportingAuthorityIds[], semanticFindingIds[] },
      supportingEquivalentAuthorityIds[],
      evidenceIds[]
    }
  | ResolvedExplicitNotApplicableAuthority {
      kind: resolved_explicit_not_applicable,
      authorityRequirementId: AuthorityRequirementId,
      basis:
        | { kind: deterministic_rule, authorizingRuleId }
        | { kind: supported_candidate,
            immutableUnitOwnerId, candidateRevision,
            supportingAuthorityIds[], semanticFindingIds[] },
      evidenceIds[]
    }
  | ResolvedExplicitExceptionAuthority {
      kind: resolved_explicit_exception,
      authorityRequirementId: AuthorityRequirementId,
      authenticatedExceptionDecisionId,
      exactScopeEvidenceIds[]
    }
  | ClarificationRequiredAuthority {
      kind: clarification_required,
      authorityRequirementId: AuthorityRequirementId,
      ownerStage: AuthorityOwnerStage,
      reason: AuthorityGapReason,
      supportingAuthorityIds[]
    }
  | UpstreamReworkRequiredAuthority {
      kind: upstream_rework_required,
      authorityRequirementId: AuthorityRequirementId,
      detectedAtStage: AuthorityDetectionStage,
      ownerStage: AuthorityOwnerStage,
      invalidatedAuthorityIds[]
    }
  | AdministrativeAuthorityBlock {
      kind: administrative_block,
      authorityRequirementId: AuthorityRequirementId,
      reason: unregistered_ownership_or_policy |
              unauthorized_authority_creation |
              required_external_or_environment_authority_unavailable,
      diagnosticCode
    }
  // There is deliberately no unresolved-success, warning-only, default,
  // approximate, closest-match, conventional-choice, current-stage fallback,
  // or locally-repaired variant.

AuthorityReconciliationEntry {
  requirement: AuthorityRequirement,
  candidateSet: AuthorityCandidateSet,
  outcome: AuthorityReconciliationOutcome,
  validationEvidenceIds[]
}

AuthorityReconciliationLedger {
  requirementLedger: AuthorityRequirementLedger,
  entries: AuthorityReconciliationEntry[],
  continuation:
    | { kind: all_resolved, successfulRequirementIds[] }
    | { kind: gaps_present, orderedGapRequirementIds[] }
  // Exactly one entry per requirement. all_resolved is valid only when every
  // outcome is one of the three resolved variants.
}

ClarificationOwnershipRegistryEntry {
  requirementKindId,
  requiredSlotId,
  ownerStage: AuthorityOwnerStage,
  allowedReconciliationPolicyIds[],
  allowedNotApplicableRuleIds[],
  allowedExceptionScopePolicyIds[]
}

ClarificationOwnershipRegistry {
  registryVersion,
  entries: ClarificationOwnershipRegistryEntry[]
  // Compiler-locked and exhaustive for every registered required slot. Unknown
  // ownership blocks administratively; it never falls back to the detector.
}
```

---

<a id="specification-ir"></a>

## 7. Specification IR

```text
AttributedBusinessText {
  text: BusinessValue,
  claimIds[],
  citationIds[],
  clarificationResponseIds[]
}

FixedSpecificationField {
  recordKey: spec.display_name | spec.primary_user_story,
  text: BusinessValue,
  claimIds[],
  citationIds[],
  clarificationResponseIds[]
}

SpecificationContentProposal {
  displayName: AttributedBusinessText,
  primaryUserStory: AttributedBusinessText,
  acceptanceCriteria: {
    // Closed typed triplet; never model-authored Markdown or free-form prose.
    given: BusinessValue, when: BusinessValue, then: BusinessValue,
    claimIds[], citationIds[], clarificationResponseIds[]
  }[],
  userVisibleOutcomes: { text: BusinessValue, claimIds[], citationIds[], clarificationResponseIds[] }[],
  edgeCases: { condition: BusinessValue, expectedOutcome: BusinessValue, claimIds[], citationIds[], clarificationResponseIds[] }[],
  functionalRequirements: { text: BusinessValue, modality, claimIds[], citationIds[], clarificationResponseIds[] }[],
  businessRules: { text: BusinessValue, claimIds[], citationIds[], clarificationResponseIds[] }[],
  assumptions: { text: BusinessValue, claimIds[], citationIds[], clarificationResponseIds[] }[],
  nonGoals: { text: BusinessValue, claimIds[], citationIds[], clarificationResponseIds[] }[],
  prohibitedBehaviors: { text: BusinessValue, claimIds[], citationIds[], clarificationResponseIds[] }[],
  entities: {
    name: BusinessValue, businessMeaning: BusinessValue,
    relationships: BusinessValue[], claimIds[], citationIds[], clarificationResponseIds[]
  }[],
  openQuestions: { text: BusinessValue, claimIds[], citationIds[], clarificationResponseIds[] }[]
}

SpecificationUnitProposal =
  | { kind: display_name, value: AttributedBusinessText }
  | { kind: primary_user_story, value: AttributedBusinessText }
  | { kind: acceptance_criteria, values: SpecificationContentProposal.acceptanceCriteria }
  | { kind: user_visible_outcomes, values: SpecificationContentProposal.userVisibleOutcomes }
  | { kind: edge_cases, values: SpecificationContentProposal.edgeCases }
  | { kind: functional_requirements, values: SpecificationContentProposal.functionalRequirements }
  | { kind: business_rules, values: SpecificationContentProposal.businessRules }
  | { kind: assumptions, values: SpecificationContentProposal.assumptions }
  | { kind: non_goals, values: SpecificationContentProposal.nonGoals }
  | { kind: prohibited_behaviors, values: SpecificationContentProposal.prohibitedBehaviors }
  | { kind: entities, values: SpecificationContentProposal.entities }
  | { kind: open_questions, values: SpecificationContentProposal.openQuestions }

SpecificationUnitOperationResult =
  | { kind: content, proposal: SpecificationUnitProposal }
  | { kind: clarification_needed, proposal: ClarificationNeedProposal }

SpecificationIR {
  passiveLiteralRegistryStateId,
  displayName: FixedSpecificationField,
  primaryUserStory: FixedSpecificationField,
  acceptanceCriteria: {
    // Renders beneath the exact `## Acceptance Criteria` heading as one
    // uppercase GIVEN/WHEN/THEN triplet in that order.
    id, given: BusinessValue, when: BusinessValue, then: BusinessValue,
    claimIds[], citationIds[], clarificationResponseIds[]
  }[],
  userVisibleOutcomes: { id, text: BusinessValue, claimIds[], citationIds[], clarificationResponseIds[] }[],
  edgeCases: { id, condition: BusinessValue, expectedOutcome: BusinessValue, claimIds[], citationIds[], clarificationResponseIds[] }[],
  functionalRequirements: { id, text: BusinessValue, modality, claimIds[], citationIds[], clarificationResponseIds[] }[],
  businessRules: { id, text: BusinessValue, claimIds[], citationIds[], clarificationResponseIds[] }[],
  assumptions: { id, text: BusinessValue, claimIds[], citationIds[], clarificationResponseIds[] }[],
  nonGoals: { id, text: BusinessValue, claimIds[], citationIds[], clarificationResponseIds[] }[],
  prohibitedBehaviors: { id, text: BusinessValue, claimIds[], citationIds[], clarificationResponseIds[] }[],
  entities: {
    id, name: BusinessValue, businessMeaning: BusinessValue,
    relationships: BusinessValue[], claimIds[], citationIds[], clarificationResponseIds[]
  }[],
  openQuestions: { id, text: BusinessValue, claimIds[], citationIds[], clarificationResponseIds[] }[]
}
```

The canonical `spec.md` projection for each `SpecificationIR.acceptanceCriteria`
record is:

```markdown
## Acceptance Criteria

**AC-001**
- **GIVEN** <nonempty `given` value>
- **WHEN** <nonempty `when` value>
- **THEN** <nonempty `then` value>
```

The heading appears once and each subsequent `AC-*` record repeats only the
identity and three labeled lines. The renderer owns the labels and order. The
editable-specification parser rejects any acceptance criterion that is
free-form, unlabeled, partially labeled, duplicated, reordered, or uses label
casing other than the exact uppercase form.

---

<a id="reference-context-ir"></a>

## 8. Reference-context IR

```text
ReferenceContextIR {
  referencedSourceIds[],
  businessSignals: ReferenceSignal<BusinessText>[],
  designInteractionSignals: ReferenceSignal<ReferenceSemanticText>[],
  preservedTokens: ReferenceSignal<PreservedTokenReference>[],
  terminalAndScopeGuards: ReferenceSignal<BusinessText>[],
  technicalObservations: ReferenceSignal<ReferenceSemanticText>[],
  validationSignals: ReferenceSignal<ReferenceSemanticText>[],
  implementationAssumptions: ReferenceSignal<ReferenceSemanticText>[],
  conflicts: SourceConflict[],
  openQuestions: ReferenceSignal<ReferenceSemanticText>[]
}

SourceConflict {
  conflictId,
  subjectCoordinate: ReferenceConflictSubjectCoordinate,
  claimIds[],
  citationIds[],
  optionContinuityKeys: {
    claimId,
    continuityKey: ReferenceConflictOptionContinuityKey
  }[],
  kind: mutually_exclusive | precedence_missing | value_mismatch | scope_mismatch,
  summary: ReferenceSemanticText,
  resolution:
    | { status: unresolved }
    | { status: resolved, basis: user_decision, decisionId,
        selectedClaimIds[], rationale: ReferenceSemanticText }
    | { status: resolved, basis: source_precedence, precedenceRuleId,
        selectedClaimIds[], rationale: ReferenceSemanticText }
}
```

---

<a id="plan-ir"></a>

## 9. Plan IR

```text
PlanUnitProposal =
  | { kind: overview, summary: SemanticText, minimalChangeHypothesis: SemanticText,
      technicalRationale: SemanticText }
  | { kind: fact_selections, technical: FactSelection[], repository: FactSelection[] }
  | { kind: principle_considerations, values: PrincipleConsideration[] }
  | { kind: implementation_shape, shape: ImplementationShapeProposal,
      touchedFileIds[],
      proposedPaths: { proposalKey, selection: ProposedPathSelection }[],
      rejectedAdditions: SemanticText[] }
  | { kind: artifact_decisions, decisions: ArtifactDecisionProposal[] }
  | { kind: research, decisions: ResearchDecisionProposal[] }
  | { kind: dependencies, proposals: DependencyProposal[] }
  | { kind: data_model, value: DataModelProposal }
  | { kind: contracts, values: ContractProposal[] }
  | { kind: quickstart, scenarios: QuickstartScenarioProposal[] }
  | { kind: coverage, entries: CoverageEntryProposal[] }
  | { kind: task_generation, approach: SemanticText,
      complexityDeviations: { ruleId, justification: SemanticText }[] }

PlanUnitOperationResult =
  | { kind: content, proposal: PlanUnitProposal }
  | { kind: clarification_needed, proposal: ClarificationNeedProposal }

PlanIR {
  summary: SemanticText,
  minimalChangeHypothesis: SemanticText,
  technicalFactSelections: FactSelection[],
  repositoryFactSelections: FactSelection[],
  technicalRationale: SemanticText,
  principleConsiderations: PrincipleConsideration[],
  implementationShape: ImplementationShape,
  touchedFileIds[],
  proposedFileIds[],
  dependencyMutationFileIds[],
  rejectedStructureAdditions: SemanticText[],
  artifactManifest: ArtifactDecision[],
  researchDecisions: ResearchDecision[],
  dependencies: DependencyPlanRecord[],
  dataModel?: DataModelIR,
  contracts: ContractIR[],
  quickstartScenarios: QuickstartScenario[],
  coverage: CoverageEntry[],
  taskGenerationApproach: SemanticText,
  complexityDeviations: { ruleId, justification: SemanticText }[]
}

PlanState {
  planStateId,
  inputPlanAuthorityStateId,
  planIdLedger: PlanIdLedger,
  plannedFileRegistry: FileRegistryState,
  pathCandidateRegistry: PathCandidateRegistry,
  fileGrants: PlanFileGrant[],
  dependencyMutationSurfaceRegistry: DependencyMutationSurfaceRegistry,
  sourceReferenceAuthorityRegistry: SourceReferenceAuthorityRegistry,
  contractViewRegistry: ContractViewRegistry,
  reviewUnitRegistry: PlanReviewUnitRegistry,
  plan: PlanIR
}

PlanIdLedger {
  nextDesignUnitOrdinal,
  nextEntityOrdinal,
  nextFieldOrdinal,
  nextContractOrdinal,
  nextScenarioOrdinal,
  nextResearchDecisionOrdinal,
  nextDependencyOrdinal,
  nextDependencyMutationSurfaceOrdinal,
  nextResearchEvidenceOrdinal,
  nextPathCandidateOrdinal,
  nextReviewUnitOrdinal,
  retiredIds[],
  retiredPathCandidateIds[]
}

PlanLocalKeyMap {
  designUnitIdsByKey,
  entityIdsByKey,
  fieldIdsByQualifiedKey,
  contractIdsByKey,
  scenarioIdsByKey,
  researchDecisionIdsByKey,
  dependencyIdsByKey
}

FactSelection {
  factId,
  selectedValueId,            // an engine-registry value ID, never model-authored free text
  interpretation: SemanticText
}

PrincipleConsideration {
  principleSelectionId,
  principleChunkIds[],
  disposition: aligned | not_applicable | deviation | conflict,
  rationale: SemanticText,
  evidenceIds[]
}

ImplementationShape {
  patternId?,
  summary: SemanticText,
  units: { unitId, responsibility: SemanticText, fileIds[] }[]
}

ImplementationShapeProposal {
  patternId?,
  summary: SemanticText,
  units: {
    unitKey,
    responsibility: SemanticText,
    fileSelections: {
      selection:
        | { kind: existing_file, fileId }
        | { kind: proposed_path, proposalKey },
      plannedIntent: read | create | update | delete,
      requestedCapabilities: (read | create | patch | replace |
                              copy_destination | delete)[]
    }[]
  }[]
}

DataModelProposal {
  entities: {
    entityKey,
    name: BusinessText,
    meaning: BusinessText,
    fields: { fieldKey, name: BusinessText, meaning: BusinessText, valueTypeId }[],
    relationshipTargetKeys[]
  }[]
}

ContractProposal {
  contractKey,
  kind: http | event | schema | file_format | interface,
  name: SemanticText,
  summary: SemanticText,
  body: ContractValueProposal
}

QuickstartScenarioProposal {
  scenarioKey,
  objective: BusinessText,
  requirementIds[],
  steps: (
    | AutomatedScenarioStep { commandSelection: CommandSelection, expected: ScenarioExpectation }
    | ManualScenarioStep { instruction: SemanticText, expectedOutcome: BusinessText }
  )[]
}

CoverageEntryProposal {
  obligationId,
  designUnitKeys[],
  scenarioKeys[],
  evidenceExpectations: EvidenceExpectationProposal[]
}

EvidenceExpectationProposal =
  | { kind: command_passes, commandSelection: CommandSelection }
  | { kind: source_parses, fileId, parserId }
  | { kind: imports_resolve, fileId, resolverId }
  | { kind: manual_scenario, scenarioKey }
  | { kind: no_unexpected_changes }

EvidenceExpectation =
  | { kind: command_passes, commandId, typedArguments }
  | { kind: source_parses, fileId, parserId }
  | { kind: imports_resolve, fileId, resolverId }
  | { kind: manual_scenario, scenarioId }
  | { kind: no_unexpected_changes }

ResearchDecisionProposal {
  decisionKey,
  question: SemanticText,
  decision: SemanticText,
  rationale: SemanticText,
  alternatives: SemanticText[],
  evidenceIds[],
  unresolvedExternalEvidence: boolean
}

ResearchDecision {
  researchDecisionId,
  question: SemanticText,
  decision: SemanticText,
  rationale: SemanticText,
  alternatives: SemanticText[],
  evidenceIds[],
  unresolvedExternalEvidence: boolean
}

DependencyProposal {
  dependencyKey,
  targetProjectId,
  targetManifestFileId,
  ecosystem,
  packageName,
  versionConstraint,
  registrySourceId,
  dependencyScope,
  rationale: SemanticText
}

DependencyPlanRecord {
  dependencyId,
  dependencyMutationSurfaceId,
  targetProjectId,
  targetManifestFileId,
  ecosystem,
  packageName,
  versionConstraint,
  registrySourceId,
  dependencyScope,
  rationale: SemanticText
}

DependencyLockfileResolution =
  | ExistingDependencyLockfile {
      fileId,
      existingFileRegistryStateId
    }
  | RequiredAbsentDependencyLockfile {
      pathIntentOptionId,
      requiredPathTemplateId,
      nameSourceId,
      requiredCapabilities: [create],
      policyEvidenceId
    }
  | NoDependencyLockfile {
      policyEvidenceId
    }

DependencyLockfilePathIntent {
  dependencyKey,
  pathIntentKey,
  pathIntentOptionId,
  nameSourceId,
  requiredPathTemplateId,
  requestedCapabilities: [create]
}

DependencyMutationFileProjection {
  dependencyKey,
  existingTouchedFileIds[],
  proposedCreateFileIds[],
  implementationShapeUnitId
}

DependencyMutationSurface {
  dependencyMutationSurfaceId,
  dependencyKey,
  targetProjectId,
  targetManifestFileId,
  lockfile:
    | { disposition: existing, fileId }
    | { disposition: create, fileId }
    | { disposition: none, evidenceId },
  requiredGrantChecks: {
    fileId,
    plannedIntent: create | update,
    requiredCapabilities[]
  }[],
  commandIds[]
}

DependencyMutationSurfaceRegistry {
  registryStateId,
  inputFileRegistryStateId,
  surfaces: DependencyMutationSurface[]
}

DataModelIR {
  entities: {
    entityId,
    name: BusinessText,
    meaning: BusinessText,
    fields: { fieldId, name: BusinessText, meaning: BusinessText, valueTypeId }[],
    relationshipTargetIds[]
  }[]
}

ContractIR {
  contractId,
  kind: http | event | schema | file_format | interface,
  name: SemanticText,
  summary: SemanticText,
  body: SchemaValidatedContractValue
}

SchemaValidatedContractValue {
  schemaId,                   // exact closed registry schema
  value                       // every string leaf is Identifier, BusinessText,
                              // SemanticText, FileReference, SourceReference,
                              // PassiveLiteralReference, or ContractEndpointReference as declared
                              // by that schema
}

ContractValueProposal {
  schemaId,
  value                       // untrusted closed-schema candidate; no "validated" marker
}

Identifier {
  namespaceId,
  value                       // strict NFC scalar matching the namespace grammar;
                              // path/URI lexemes are forbidden
}

ContractEndpointReference { endpointAuthorityId }

SourceReferenceAuthorityRegistry {
  sourceReferenceAuthorityRegistryStateId,
  inputFileRegistryStateId,
  inputDependencyMutationSurfaceRegistryStateId,
  passiveLiteralRegistryStateId,
  authorities: (
    | ProjectFileAuthority { fileId }
    | PackageModuleAuthority {
        packageAuthorityId,
        source:
          | { kind: repository_existing, dependencyFactId }
          | { kind: plan_declared, dependencyId },
        ecosystem, packageName, allowedSpecifierPatternIds[]
      }
    | ContractEndpointAuthority { endpointAuthorityId, contractId,
                                  allowedOperationIds[] }
    | RuntimeResourceAuthority { resourceAuthorityId, owningFileId?,
                                 resourceNamePatternId }
    | ExternalEndpointAuthority { externalEndpointAuthorityId,
                                  scheme, hostPatternId, operationIds[] }
    | InertDisplayAuthority { passiveLiteralId }
  )[]
}

StaticReferenceOccurrence {
  occurrenceId,
  containingFileId,
  parserId,
  queryId,
  sourceRange,
  syntacticContext: import_specifier | project_file_literal | runtime_resource |
                    contract_endpoint | network_endpoint | display_only,
  rawScalarHandle
}

StaticReferenceTarget =
  | { kind: project_file, fileId }
  | { kind: package_module, packageAuthorityId }
  | { kind: contract_endpoint, endpointAuthorityId }
  | { kind: runtime_resource, resourceAuthorityId }
  | { kind: external_endpoint, externalEndpointAuthorityId }
  | { kind: inert_display, passiveLiteralId }

StaticReferenceResolution {
  occurrenceId,
  target: StaticReferenceTarget,
  resolverId,
  evidenceIds[]
}

ContentReferenceCoverage {
  containingFileId,
  parserId?,
  parserCoveredRanges[],
  fallbackCoveredRanges[],
  occurrences: StaticReferenceOccurrence[],
  resolutions: StaticReferenceResolution[],
  rejectedCandidateIds[]
}

QuickstartScenario {
  scenarioId,
  objective: BusinessText,
  requirementIds[],
  steps: (
    | AutomatedScenarioStep { commandSelection: CommandSelection, expected: ScenarioExpectation }
    | ManualScenarioStep { instruction: SemanticText, expectedOutcome: BusinessText }
  )[]
}

ScenarioExpectation =
  | CommandSucceedsExpectation { kind: command_succeeds }
  | ObservableTextExpectation { kind: observable_text, text: BusinessText }
  | FilePresentExpectation { kind: file_present, fileId }

CoverageEntry {
  obligationId,
  designUnitIds[],
  scenarioIds[],
  evidenceExpectations: EvidenceExpectation[]
}

ContractViewRegistry {
  entries: {
    contractId,
    selector: { kind: contract, contractId },
    engineAssignedPath,
    viewSchemaId,
    extension
  }[]
}

PlanReviewUnitRegistry {
  planReviewUnitRegistryStateId,
  entries: {
    reviewUnitId,
    selector:
      | { kind: fixed_section, sectionKind }
      | { kind: design_unit, designUnitId }
      | { kind: data_entity, entityId }
      | { kind: data_field, entityId, fieldId }
      | { kind: contract, contractId }
      | { kind: quickstart_scenario, scenarioId }
      | { kind: coverage, obligationId }
      | { kind: research, researchDecisionId }
      | { kind: dependency, dependencyId }
      | { kind: fact_selection, factId }
      | { kind: principle_consideration, principleSelectionId, principleChunkIds[] }
  }[]
}
```

---

<a id="artifact-decision"></a>

## 10. Artifact decision

```text
ArtifactDecisionProposal {
  kind: research | data_model | quickstart | contract,
  disposition: required | not_applicable,
  reason: SemanticText
}

ArtifactDecision {
  kind: research | data_model | quickstart | contract,
  disposition: required | not_applicable,
  reason: SemanticText,
  engineAssignedPath?,       // present exactly when required; copied from artifact registry
  pathRole?: file | collection_root
}
```

---

<a id="task-ir"></a>

## 11. Task IR

```text
CommandSelection {
  commandId,
  typedArguments
}

TaskDefinitionProposal {
  internalKey,
  phase: setup | verification | implementation | integration | polish,
  kind: setup | automated_verification | manual_verification |
        source_change | integration_change | documentation,
  responsibility: SemanticText,
  description: SemanticText,
  obligationIds[],
  readFileIds[],
  writeFileIds[],
  optionalCommandSelections: CommandSelection[],
  manualScenarioIds[],
  verification:
    | { mode: red_then_green, command: CommandSelection,
        requiredDiagnosticCode, mustBecomeGreenByInternalKey }
    | { mode: existing_check | manual_after_change | none },
  dependsOnInternalKeys[]
}

TaskClusterOperationResult =
  | { kind: content, proposals: TaskDefinitionProposal[] }
  | { kind: clarification_needed, proposal: ClarificationNeedProposal }

TaskDefinition {
  taskId,
  internalKey,
  phase: setup | verification | implementation | integration | polish,
  kind: setup | automated_verification | manual_verification |
        source_change | integration_change | documentation,
  responsibility: SemanticText,
  description: SemanticText,
  obligationIds[],
  readFileIds[],
  writeFileIds[],
  commandInvocations: CommandInvocation[],
  manualScenarioIds[],
  verificationMode: red_then_green | existing_check | manual_after_change | none,
  requiredEvidence: EvidencePredicate[],
  sharedResourceIds[]
}

CommandInvocation {
  commandId,                 // an available preset/config command ID
  typedArguments,            // closed argument object declared by that command
  origin: engine_required | model_optional
}

EvidencePredicate {
  evidencePredicateId,
  predicate: EvidencePredicateValue
}

EvidencePredicateValue =
  | FileDeltaValidatedPredicate {
      kind: file_delta_validated, fileId
    }
  | CommandPassedPredicate {
      kind: command_passed, commandId
    }
  | CommandFailedAsExpectedPredicate {
      kind: command_failed_as_expected,
      commandId,
      requiredDiagnosticCode,
      mustBecomeGreenByTaskId
    }
  | SourceParsedPredicate {
      kind: source_parsed, fileId, parserId
    }
  | ImportsResolvedPredicate {
      kind: imports_resolved, fileId, resolverId
    }
  | ManualScenarioRecordedPredicate {
      kind: manual_scenario_recorded, scenarioId
    }
  | NoUnexpectedChangesPredicate {
      kind: no_unexpected_changes, taskId
    }
```

---

<a id="implementation-ir"></a>

## 12. Implementation IR

```text
FileOperation =
  | CreateFile { operationIntentId, fileId, completeContent: ModelTextContent }
  | UpdateFile { operationIntentId, fileId, patch: ModelPatchContent }
  | ReplaceFile { operationIntentId, fileId, completeContent: ModelTextContent }
  | CopyFile { operationIntentId, sourceId, destinationFileId }
  | DeleteFile { operationIntentId, fileId, justification: SemanticText }

FileOperationPayload =
  | CreateFilePayload { operationIntentId, fileId, contentUtf8 }
  | UpdateFilePayload { operationIntentId, fileId, patchFormatId, patchUtf8 }
  | ReplaceFilePayload { operationIntentId, fileId, contentUtf8 }
  | CopyFilePayload { operationIntentId, sourceId, destinationFileId }
  | DeleteFilePayload { operationIntentId, fileId, justification: SemanticText }

ModelTextContent {
  utf8BodyHandle,
  byteLength
}

ModelPatchContent {
  patchFormatId,
  utf8PatchHandle,
  byteLength
}

CopySource {
  sourceId,
  canonicalSourceOrdinal,
  stableSourceSelector,
  kind: repository_file | reference_block | approved_template,
  registryRevision,
  immutableBlob: {
    blobId,
    ownerStateId,            // task-context, reference-state, or exact template-package revision
    byteLength
  },
  mediaType,
  provenance,
  copyPolicyId
}

CopySourceRegistry {
  copySourceRegistryId,
  taskDefinitionStateId,
  taskId,
  taskLeaseId,
  taskBaseOverlayRevision,
  revision,
  sources: CopySource[]
}

CopySourceRegistryId {
  taskDefinitionStateId,
  taskId,
  taskLeaseId,
  taskBaseOverlayRevision,
  registryContractVersion
}

CopySourceId {
  copySourceRegistryId,
  canonicalSourceOrdinal
}

// Both copy IDs are closed structural tuples. The registry ID is derived from
// already-canonical task/lease/base authorities; each source ID is then derived
// from the registry ID and the source's unique canonical sort ordinal. They do
// not consume TaskExecutionIdLedger ordinals and cannot be supplied by a model.

TaskExecutionAllocatedId =
  | OperationIntentPlanId { taskExecutionIdLedgerStateId, ordinal }
  | OperationIntentId { taskExecutionIdLedgerStateId, ordinal }
  | TaskExecutionAttemptRegistryId { taskExecutionIdLedgerStateId, ordinal }
  | TaskExecutionAttemptId { taskExecutionIdLedgerStateId, ordinal }
  | OperationRecordRegistryId { taskExecutionIdLedgerStateId, ordinal }
  | OperationRecordId { taskExecutionIdLedgerStateId, ordinal }
  | OperationJournalId { taskExecutionIdLedgerStateId, ordinal }
  | FileStateTransitionRegistryId { taskExecutionIdLedgerStateId, ordinal }
  | FileStateTransitionId { taskExecutionIdLedgerStateId, ordinal }
  | TaskExecutionCheckpointId { taskExecutionIdLedgerStateId, ordinal }
  | OperationAuthorizationId { taskExecutionIdLedgerStateId, ordinal }
  | OperationSavepointId { taskExecutionIdLedgerStateId, ordinal }
  | TaskCommandAuthorizationId { taskExecutionIdLedgerStateId, ordinal }
  | TaskCommandSavepointId { taskExecutionIdLedgerStateId, ordinal }
  | OperationPromotionAuthorizationId { taskExecutionIdLedgerStateId, ordinal }

TaskExecutionAllocationNamespace =
  operation_intent_plan | operation_intent | attempt_registry | attempt |
  operation_record_registry | operation_record | operation_journal |
  file_state_transition_registry | file_state_transition | checkpoint |
  operation_authorization | operation_savepoint | command_authorization |
  command_savepoint | operation_promotion_authorization

TaskExecutionIdAllocationDelta {
  namespace: TaskExecutionAllocationNamespace,
  allocatedId: TaskExecutionAllocatedId,
  inputLedgerRevision,
  expectedCurrentOrdinal,
  disposition: assigned
}

TaskExecutionIdRetirementDelta {
  namespace: TaskExecutionAllocationNamespace,
  allocatedId: TaskExecutionAllocatedId,
  inputLedgerRevision,
  disposition: retired,
  cause
}

OperationAuthorization {
  authorizationId,
  taskLeaseId,
  taskOverlayId,
  expectedTaskOverlayRevision,
  principleRegistryStateId,
  principleRegistryStateRevision,
  principleSelectionIds[],
  operationIntentPlanId,
  operationIntentId,
  operationKind,
  taskFileCapabilityRegistryStateId,
  targetFileIds[],
  copySourceId?,
  copySourceRegistryRevision?,
  copySourceBlobId?,
  expectedTargetState,       // engine-derived; never accepted from model output
  expectedTargetDescriptorRevision
}

OperationSavepoint {
  savepointId,
  baseOverlayId,
  baseRevision,
  operationAuthorizationId,
  adapterBoundaryEntry: TaskExecutionAdapterBoundaryEntryObservation
}

OperationSavepointDiscardEvidence {
  operationAuthorizationId,
  operationSavepointId,
  adapterBoundaryEntry: TaskExecutionAdapterBoundaryEntryObservation,
  adapterDiscardReceipt: TaskExecutionAdapterDiscardReceipt,
  residualEntryCount: 0,
  taskOverlayDirectlyEqualToExpected: true
}

OperationPromotionAuthorization {
  promotionAuthorizationId,
  savepointId,
  operationRecordId,
  expectedTaskOverlayRevision,
  localValidationEvidenceIds[]
}

OperationRecord {
  operationRecordId,
  operationIntentPlanId,
  operationIntentId,
  operation: FileOperation,       // body/patch handles are execution-store owned
  executionBlobOwnerId,
  replayBinding:
    | { kind: content, blobId, ownerStateId, byteLength, mediaType,
        encoding: utf8, patchFormatId? }
    | { kind: copy, sourceId, copySourceRegistryId,
        copySourceRegistryRevision, blobId, ownerStateId, byteLength,
        mediaType, copyPolicyId, provenanceEvidenceIds[] }
    | { kind: delete, noBody: true },
  authorizationSnapshot: {
    taskFileCapabilityRegistryStateId,
    operationKind,
    targetFileIds[],
    expectedTargetState,
    expectedTargetDescriptorRevision,
    sourceValidationEvidenceIds[]
  },
  operationAuthorizationId,
  savepointId
}

OperationRecordRegistry {
  operationRecordRegistryId,
  taskExecutionAttemptId,
  taskLeaseId,
  revision,
  records: OperationRecord[],
  retiredOperationRecordIds[]
}

OperationJournalEntry {
  ordinal,
  operationRecordId,
  fileStateTransitionId,
  operationIntentId,
  operationKind,
  targetFileIds[],
  sourceId?,
  operationAuthorizationId,
  promotionAuthorizationId,
  savepointId,
  prePromotionOverlayRevision,
  postPromotionOverlayRevision,
  localValidationEvidenceIds[],
  promotionEvidenceId
}

OperationJournal {
  operationJournalId,
  taskExecutionAttemptId,
  operationIntentPlanId,
  taskLeaseId,
  taskId,
  taskOverlayId,
  revision,
  entries: OperationJournalEntry[]
}

TaskExecutionIdLedger {
  taskExecutionIdLedgerStateId,
  taskDefinitionStateId,
  taskId,
  taskLeaseId,
  revision,
  nextOperationIntentPlanOrdinal,
  nextOperationIntentOrdinal,
  nextAttemptRegistryOrdinal,
  nextAttemptOrdinal,
  nextOperationRecordRegistryOrdinal,
  nextOperationRecordOrdinal,
  nextOperationJournalOrdinal,
  nextFileStateTransitionRegistryOrdinal,
  nextFileStateTransitionOrdinal,
  nextCheckpointOrdinal,
  nextOperationAuthorizationOrdinal,
  nextOperationSavepointOrdinal,
  nextCommandAuthorizationOrdinal,
  nextCommandSavepointOrdinal,
  nextOperationPromotionAuthorizationOrdinal,
  retiredAllocationIds[]
  // Every Assign* task-execution action returns its allocated ID plus one
  // allocation delta. AdvanceTaskExecutionIdLedgerAction alone applies that
  // delta; failed materializations use an explicit retirement delta.
}

TaskExecutionAdapterBoundary =
  | NoPendingTaskExecutionAdapterBoundary { kind: none }
  | OperationApplyReadyBoundary {
      kind: operation_apply_ready,
      operationAuthorization: OperationAuthorization,
      operationSavepointId,
      taskExecutionIdLedgerRevision
    }
  | OperationPromotionReadyBoundary {
      kind: operation_promotion_ready,
      operationAuthorization: OperationAuthorization,
      operationSavepointId,
      promotionAuthorization: OperationPromotionAuthorization,
      predecessorApplyBoundaryRecordKey: TaskExecutionAdapterBoundaryRecordKey,
      predecessorApplyBoundaryEntryRecordId: AdapterBoundaryEntryRecordId,
      taskExecutionIdLedgerRevision
    }
  | CommandRunReadyBoundary {
      kind: command_run_ready,
      commandAuthorization: CommandAuthorization,
      commandSavepointId,
      taskExecutionIdLedgerRevision
    }

TaskExecutionAdapterBoundaryRecordKey {
  taskExecutionCheckpointId,
  boundaryKind: operation_apply_ready | operation_promotion_ready | command_run_ready,
  savepointId,
  taskOverlayId
  // This structural tuple is the adapter record key. It is not an allocated ID,
  // digest, fingerprint, caller path, or model-provided value.
}

TaskExecutionAdapterRecordId =
  | AdapterBoundaryEntryRecordId {
      boundaryRecordKey: TaskExecutionAdapterBoundaryRecordKey,
      recordKind: boundary_entry
    }
  | AdapterChildSavepointRecordId {
      boundaryRecordKey: TaskExecutionAdapterBoundaryRecordKey,
      recordKind: child_savepoint
    }
  | AdapterPromotionReceiptId {
      boundaryRecordKey: TaskExecutionAdapterBoundaryRecordKey,
      recordKind: promotion_receipt
    }
  | AdapterDiscardReceiptId {
      boundaryRecordKey: TaskExecutionAdapterBoundaryRecordKey,
      recordKind: discard_receipt
    }
  | AdapterRestoreReceiptId {
      boundaryRecordKey: TaskExecutionAdapterBoundaryRecordKey,
      recordKind: restore_receipt
    }
  | AdapterBeforeImageRecordId {
      boundaryRecordKey: TaskExecutionAdapterBoundaryRecordKey,
      recordKind: before_image,
      effectOrdinal,
      fileId
    }
  | AdapterCreationTombstoneRecordId {
      boundaryRecordKey: TaskExecutionAdapterBoundaryRecordKey,
      recordKind: creation_tombstone,
      effectOrdinal,
      fileId
    }
  | AdapterDeletionTombstoneRecordId {
      boundaryRecordKey: TaskExecutionAdapterBoundaryRecordKey,
      recordKind: deletion_tombstone,
      effectOrdinal,
      fileId
    }

TaskExecutionAdapterBoundaryRecordSet =
  | SingleTaskExecutionAdapterBoundaryRecordSet {
      kind: single_boundary,
      activeBoundaryRecordKey: TaskExecutionAdapterBoundaryRecordKey
    }
  | OperationPromotionAdapterBoundaryRecordSet {
      kind: operation_promotion_chain,
      predecessorApplyBoundaryRecordKey: TaskExecutionAdapterBoundaryRecordKey,
      predecessorApplyBoundaryEntryRecordId: AdapterBoundaryEntryRecordId,
      activePromotionBoundaryRecordKey: TaskExecutionAdapterBoundaryRecordKey
    }
  // The set is mechanically derived from the current checkpoint and, for an
  // operation promotion, its exact parent checkpoint. It is canonically ordered,
  // duplicate-free, complete, and never discovered by ambient adapter search.

TaskExecutionAdapterImageBlobId {
  imageRecordId: AdapterBeforeImageRecordId | AdapterPromotionReceiptId,
  imageRole: exact_before | exact_after,
  effectOrdinal,
  fileId
  // Blob identity is structural. Its bytes are validated directly; no content
  // digest, fingerprint, random value, path, or model scalar is an identity.
}

TaskExecutionAdapterBoundaryEntryObservation {
  boundaryRecordKey: TaskExecutionAdapterBoundaryRecordKey,
  boundaryEntryRecordId: AdapterBoundaryEntryRecordId,
  expectedTaskOverlayRevision,
  childSavepointRecordId: AdapterChildSavepointRecordId,
  childSavepointRevision,
  childPublished: true,
  entryRecordDurableBeforeOrWithChildPublication: true
}

TaskExecutionAdapterExactEffectEntry =
  | AdapterCreatedFileEffectEntry {
      effectOrdinal,
      fileId,
      deltaKind: create,
      beforeState: {
        kind: absent,
        creationTombstoneRecordId: AdapterCreationTombstoneRecordId
      },
      afterState: {
        kind: regular_file,
        afterDescriptorRevision,
        afterImageBlobId: TaskExecutionAdapterImageBlobId
      }
    }
  | AdapterModifiedFileEffectEntry {
      effectOrdinal,
      fileId,
      deltaKind: modify,
      beforeState: {
        kind: regular_file,
        beforeDescriptorRevision,
        beforeImageRecordId: AdapterBeforeImageRecordId,
        beforeImageBlobId: TaskExecutionAdapterImageBlobId
      },
      afterState: {
        kind: regular_file,
        afterDescriptorRevision,
        afterImageBlobId: TaskExecutionAdapterImageBlobId
      }
    }
  | AdapterDeletedFileEffectEntry {
      effectOrdinal,
      fileId,
      deltaKind: delete,
      beforeState: {
        kind: regular_file,
        beforeDescriptorRevision,
        beforeImageRecordId: AdapterBeforeImageRecordId,
        beforeImageBlobId: TaskExecutionAdapterImageBlobId
      },
      afterState: {
        kind: absent,
        deletionTombstoneRecordId: AdapterDeletionTombstoneRecordId
      }
    }

TaskExecutionAdapterPromotionReceipt {
  boundaryRecordKey: TaskExecutionAdapterBoundaryRecordKey,
  boundaryEntryRecordId: AdapterBoundaryEntryRecordId,
  sourceSavepointEntry:
    | { kind: operation,
        predecessorApplyBoundaryRecordKey: TaskExecutionAdapterBoundaryRecordKey,
        predecessorApplyBoundaryEntryRecordId: AdapterBoundaryEntryRecordId }
    | { kind: command,
        commandBoundaryRecordKey: TaskExecutionAdapterBoundaryRecordKey,
        commandBoundaryEntryRecordId: AdapterBoundaryEntryRecordId },
  durableEffectReceiptId: AdapterPromotionReceiptId,
  effectKind: operation | command,
  prePromotionTaskOverlayRevision,
  postPromotionTaskOverlayRevision,
  exactEffectEntries: TaskExecutionAdapterExactEffectEntry[],
  childSavepointDisposition: consumed_by_promotion,
  parentRevisionPublished: true,
  promotionBoundaryEntryDurableBeforeOrWithParentPublication: true,
  receiptAndBeforeImagesDurableBeforeOrWithParentPublication: true
  // The complete receipt, creation/deletion tombstones, and exact before images
  // are immutable adapter records retained through the boundary-free checkpoint.
}

TaskExecutionAdapterDiscardReceipt {
  boundaryRecordKey: TaskExecutionAdapterBoundaryRecordKey,
  boundaryEntryRecordId: AdapterBoundaryEntryRecordId,
  durableDiscardReceiptId: AdapterDiscardReceiptId,
  expectedTaskOverlayRevision,
  observedTaskOverlayRevision,
  childSavepointDisposition: absent,
  parentTaskOverlayDirectlyEqualToExpected: true,
  discardReceiptDurableWithChildRemoval: true
}

TaskExecutionAdapterRestoreReceipt {
  boundaryRecordKey: TaskExecutionAdapterBoundaryRecordKey,
  boundaryEntryRecordId: AdapterBoundaryEntryRecordId,
  durableEffectReceiptId: AdapterPromotionReceiptId,
  durableRestoreReceiptId: AdapterRestoreReceiptId,
  promotedTaskOverlayRevision,
  restoredTaskOverlayRevision,
  restoredFileIds[],
  exactBeforeImagesOrAbsenceRestored: true,
  residualEffectEntryCount: 0,
  restoreReceiptDurableWithRestoration: true
}

TaskExecutionAdapterBoundaryEntryValidation {
  boundaryRecordKey: TaskExecutionAdapterBoundaryRecordKey,
  boundaryEntryRecordId: AdapterBoundaryEntryRecordId,
  exactCheckpointBoundarySavepointOverlayJoin: true,
  childPublishedOnlyAfterDurableEntry: true
}

TaskExecutionAdapterPromotionReceiptValidation {
  boundaryRecordSet: TaskExecutionAdapterBoundaryRecordSet,
  durableEffectReceiptId: AdapterPromotionReceiptId,
  completeCanonicalEffectOrdinalAndFileCoverage: true,
  exactBeforeAfterImageAndTombstoneCoverage: true,
  parentRevisionPublicationDurabilityOrderValid: true
}

TaskExecutionAdapterDiscardReceiptValidation {
  boundaryRecordSet: TaskExecutionAdapterBoundaryRecordSet,
  durableDiscardReceiptId: AdapterDiscardReceiptId,
  exactEntryAndParentRevisionJoin: true,
  childAbsentAndParentUnchanged: true,
  receiptRemovalAtomicityValid: true
}

TaskExecutionAdapterRestoreReceiptValidation {
  boundaryRecordSet: TaskExecutionAdapterBoundaryRecordSet,
  durableRestoreReceiptId: AdapterRestoreReceiptId,
  exactPromotionReceiptAndBeforeImageJoin: true,
  completeRestorationAndZeroResidualEffect: true,
  receiptRestorationAtomicityValid: true
}

RecoveredTaskExecutionAdapterBoundaryObservation =
  | RecoveredAdapterBoundaryNeverEnteredObservation {
      kind: never_entered,
      taskExecutionCheckpointId,
      boundaryKind: operation_apply_ready | command_run_ready,
      boundaryRecordSet: TaskExecutionAdapterBoundaryRecordSet,
      savepointId,
      expectedTaskOverlayRevision,
      observedTaskOverlayRevision,
      durableAdapterRecordDisposition: absent,
      childSavepointDisposition: absent,
      taskOverlayDirectlyEqualToExpected: true
    }
  | RecoveredAdapterBoundaryUnpromotedSavepointObservation {
      kind: unpromoted_savepoint_present,
      taskExecutionCheckpointId,
      boundaryKind: operation_apply_ready | operation_promotion_ready | command_run_ready,
      boundaryRecordSet: TaskExecutionAdapterBoundaryRecordSet,
      savepointId,
      expectedTaskOverlayRevision,
      observedTaskOverlayRevision,
      durableAdapterRecordDisposition: created_not_promoted,
      childSavepointRecordId: AdapterChildSavepointRecordId,
      childSavepointRevision,
      taskOverlayDirectlyEqualToExpected: true
    }
  | RecoveredAdapterBoundaryPromotedEffectObservation {
      kind: already_applied_or_promoted,
      taskExecutionCheckpointId,
      boundaryKind: operation_apply_ready | operation_promotion_ready | command_run_ready,
      boundaryRecordSet: TaskExecutionAdapterBoundaryRecordSet,
      savepointId,
      expectedTaskOverlayRevision,
      observedTaskOverlayRevision,
      promotionReceipt: TaskExecutionAdapterPromotionReceipt,
      childSavepointDisposition: consumed_by_promotion,
      receiptAndBeforeImagesDurable: true
    }
  | RecoveredAdapterBoundaryAlreadyDiscardedObservation {
      kind: already_discarded_no_parent_effect,
      taskExecutionCheckpointId,
      boundaryKind: operation_apply_ready | operation_promotion_ready | command_run_ready,
      boundaryRecordSet: TaskExecutionAdapterBoundaryRecordSet,
      savepointId,
      expectedTaskOverlayRevision,
      observedTaskOverlayRevision,
      discardReceipt: TaskExecutionAdapterDiscardReceipt,
      childSavepointDisposition: absent,
      taskOverlayDirectlyEqualToExpected: true
    }
  | RecoveredAdapterBoundaryAlreadyRestoredObservation {
      kind: already_restored_no_parent_effect,
      taskExecutionCheckpointId,
      boundaryKind: operation_apply_ready | command_run_ready,
      boundaryRecordSet: TaskExecutionAdapterBoundaryRecordSet,
      savepointId,
      expectedTaskOverlayRevision,
      promotedTaskOverlayRevision,
      observedRestoredTaskOverlayRevision,
      promotionReceipt: TaskExecutionAdapterPromotionReceipt,
      restoreReceipt: TaskExecutionAdapterRestoreReceipt,
      childSavepointDisposition: consumed_by_promotion,
      taskOverlayValueDirectlyEqualToRecordedBeforeState: true,
      residualEffectEntryCount: 0
    }
  | IndeterminateRecoveredAdapterBoundaryObservation {
      kind: indeterminate,
      taskExecutionCheckpointId,
      boundaryKind: operation_apply_ready | operation_promotion_ready | command_run_ready,
      boundaryRecordSet: TaskExecutionAdapterBoundaryRecordSet,
      savepointId,
      expectedTaskOverlayRevision,
      observedTaskOverlayRevision?,
      diagnosticCode:
        adapter_record_missing_for_changed_overlay |
        savepoint_and_receipt_conflict |
        effect_receipt_corrupt |
        before_image_missing |
        overlay_revision_unjoinable |
        unauthorized_effect_kind
    }

TaskExecutionAdapterBoundaryRecoveryDisposition =
  | ClearNeverEnteredBoundary {
      kind: clear_never_entered,
      requiresAdapterMutation: false
    }
  | ClearAlreadyTerminalizedBoundary {
      kind: clear_already_terminalized,
      terminalKind: discarded_no_parent_effect | restored_no_parent_effect,
      requiresAdapterMutation: false
    }
  | DiscardRecoveredUnpromotedSavepoint {
      kind: discard_unpromoted_savepoint,
      requiresAdapterMutation: true
    }
  | ReconstructRecoveredOperationPromotion {
      kind: reconstruct_operation_promotion,
      requiresAdapterMutation: false
    }
  | RestoreRecoveredEffectBeforeImage {
      kind: restore_exact_before_image,
      reason:
        promotion_without_promotion_ready_authority |
        command_evidence_not_durable_at_boundary,
      requiresAdapterMutation: true
    }
  | BlockIndeterminateAdapterBoundary {
      kind: block_indeterminate,
      requiresAdapterMutation: false,
      diagnosticCode
    }

TaskExecutionAdapterBoundaryRecoveryPlan {
  taskExecutionCheckpointId,
  boundaryRecordSet: TaskExecutionAdapterBoundaryRecordSet,
  taskExecutionIdLedgerStateId,
  taskExecutionIdLedgerRevision,
  boundaryKind: operation_apply_ready | operation_promotion_ready | command_run_ready,
  observation: RecoveredTaskExecutionAdapterBoundaryObservation,
  disposition: TaskExecutionAdapterBoundaryRecoveryDisposition,
  requiredTerminalBoundary: none,
  ordinaryAllocationModelAndAdapterWorkBlocked: true
  // Only IDs/actions required to reconstruct an already authorized operation
  // promotion and to commit the pending-release and cleanup-closed checkpoints
  // are allowed before closure.
}

RecoveredTaskExecutionSavepointDiscardEvidence {
  taskExecutionCheckpointId,
  boundaryRecordSet: TaskExecutionAdapterBoundaryRecordSet,
  boundaryKind: operation_apply_ready | operation_promotion_ready | command_run_ready,
  savepointId,
  childSavepointRecordId,
  expectedTaskOverlayRevision,
  observedTaskOverlayRevision,
  discardReceipt: TaskExecutionAdapterDiscardReceipt,
  childSavepointAbsentAfterDiscard: true,
  taskOverlayDirectlyEqualToExpected: true,
  adapterDiscardReceiptAppended: true
}

RecoveredTaskExecutionBeforeImageRestoreEvidence {
  taskExecutionCheckpointId,
  boundaryRecordSet: TaskExecutionAdapterBoundaryRecordSet,
  boundaryKind: operation_apply_ready | command_run_ready,
  savepointId,
  promotionReceipt: TaskExecutionAdapterPromotionReceipt,
  restoreReceipt: TaskExecutionAdapterRestoreReceipt,
  promotedOverlayRevision,
  restoredTaskOverlayRevision,
  restoredFileIds[],
  exactBeforeImagesRestored: true,
  residualEffectEntryCount: 0,
  adapterRestoreReceiptAppended: true
}

RecoveredOperationPromotionObservation {
  taskExecutionCheckpointId,
  boundaryRecordSet: OperationPromotionAdapterBoundaryRecordSet,
  boundaryKind: operation_promotion_ready,
  operationAuthorizationId,
  operationSavepointId,
  promotionAuthorizationId,
  operationRecordId,
  promotionReceipt: TaskExecutionAdapterPromotionReceipt,
  prePromotionOverlayRevision,
  postPromotionOverlayRevision,
  changedFileIds[],
  exactReceiptReconstruction: true
}

TaskExecutionAdapterBoundaryRecoveryTerminalEvidence =
  | NeverEnteredBoundaryTerminalEvidence {
      observation: RecoveredAdapterBoundaryNeverEnteredObservation
    }
  | AlreadyDiscardedBoundaryTerminalEvidence {
      observation: RecoveredAdapterBoundaryAlreadyDiscardedObservation
    }
  | AlreadyRestoredBoundaryTerminalEvidence {
      observation: RecoveredAdapterBoundaryAlreadyRestoredObservation
    }
  | DiscardedRecoveredSavepointTerminalEvidence {
      evidence: RecoveredTaskExecutionSavepointDiscardEvidence
    }
  | RestoredRecoveredEffectTerminalEvidence {
      evidence: RecoveredTaskExecutionBeforeImageRestoreEvidence
    }
  | ReconstructedOperationPromotionTerminalEvidence {
      recoveredObservation: RecoveredOperationPromotionObservation,
      operationPromotionEvidenceId,
      fileStateTransitionIds[],
      operationJournalEntryOrdinal,
      executionEvidenceRegistryStateId,
      executionEvidenceRegistryStateRevision
    }

TaskExecutionAdapterBoundaryRecoveryCompletionEvidence {
  inputTaskExecutionCheckpointId,
  boundaryRecordSet: TaskExecutionAdapterBoundaryRecordSet,
  recoveryPlan: TaskExecutionAdapterBoundaryRecoveryPlan,
  terminalEvidence: TaskExecutionAdapterBoundaryRecoveryTerminalEvidence,
  boundaryFreeTaskExecutionCheckpointId,
  boundaryFreeCheckpointTransactionId,
  adapterRecordCleanupState: pending_release,
  committedBoundaryFreeCheckpoint: true
}

TaskExecutionAdapterBoundaryRecordReleaseAuthorization {
  boundaryRecordSet: TaskExecutionAdapterBoundaryRecordSet,
  boundaryFreeTaskExecutionCheckpointId,
  boundaryFreeCheckpointTransactionId,
  committedBoundaryFreeCheckpoint: true,
  terminalAuthority:
    | { kind: forward,
        evidence:
          OperationSavepointDiscardEvidence |
          OperationPromotionEvidence |
          CommandSavepointDiscardEvidence |
          CommandPromotionEvidence }
    | { kind: recovered,
        completion: TaskExecutionAdapterBoundaryRecoveryCompletionEvidence }
  // This engine-built value is not a persistence authorization. It permits only
  // idempotent deletion of the complete, now-inert adapter record set.
}

TaskExecutionAdapterBoundaryRecordReleaseAuthorizationValidation {
  boundaryRecordSet: TaskExecutionAdapterBoundaryRecordSet,
  pendingReleaseTaskExecutionCheckpointId,
  boundaryFreeCheckpointTransactionId,
  exactTerminalAuthorityJoin: true,
  completeRetainedRecordInventoryCovered: true,
  cleanupOnlyAfterCommittedBoundaryFreeCheckpoint: true
}

TaskExecutionAdapterBoundaryRecordReleaseObservation =
  | TaskExecutionAdapterBoundaryRecordsReleasedNowObservation {
      kind: released_now,
      boundaryRecordSet: TaskExecutionAdapterBoundaryRecordSet,
      boundaryFreeTaskExecutionCheckpointId,
      boundaryFreeCheckpointTransactionId,
      releasedRecordIds: TaskExecutionAdapterRecordId[],
      releasedBlobIds: TaskExecutionAdapterImageBlobId[],
      residualRecordCount: 0
    }
  | TaskExecutionAdapterBoundaryRecordsAlreadyReleasedObservation {
      kind: already_released,
      boundaryRecordSet: TaskExecutionAdapterBoundaryRecordSet,
      boundaryFreeTaskExecutionCheckpointId,
      boundaryFreeCheckpointTransactionId,
      completeAuthorizedRecordSetAlreadyAbsent: true,
      residualRecordCount: 0
    }

TaskExecutionAdapterBoundaryRecordReleaseEvidence {
  authorization: TaskExecutionAdapterBoundaryRecordReleaseAuthorization,
  observation: TaskExecutionAdapterBoundaryRecordReleaseObservation,
  completeRecordSetReleasedOrAlreadyAbsent: true,
  ordinaryWorkAuthorityUnchanged: true
  // Cleanup is permitted only after the named checkpoint transaction is known
  // committed. Failure to clean leaks inert metadata and never reauthorizes work.
}

TaskExecutionAdapterRecordCleanupState =
  | NoPendingTaskExecutionAdapterRecordCleanup { kind: none }
  | PendingTaskExecutionAdapterRecordRelease {
      kind: pending_release,
      inputBoundaryTaskExecutionCheckpointId,
      boundaryRecordSet: TaskExecutionAdapterBoundaryRecordSet,
      terminalAuthority:
        | { kind: forward,
            evidence:
              OperationSavepointDiscardEvidence |
              OperationPromotionEvidence |
              CommandSavepointDiscardEvidence |
              CommandPromotionEvidence }
        | { kind: recovered,
            terminalEvidence: TaskExecutionAdapterBoundaryRecoveryTerminalEvidence }
    }

TaskExecutionAdapterRecordCleanupClosureBinding {
  inputPendingReleaseTaskExecutionCheckpointId,
  boundaryRecordSet: TaskExecutionAdapterBoundaryRecordSet,
  releaseEvidence: TaskExecutionAdapterBoundaryRecordReleaseEvidence,
  outputCleanupState: none
}

TaskExecutionAdapterRecordCleanupClosureEvidence {
  inputPendingReleaseTaskExecutionCheckpointId,
  boundaryRecordSet: TaskExecutionAdapterBoundaryRecordSet,
  releaseEvidence: TaskExecutionAdapterBoundaryRecordReleaseEvidence,
  cleanupClosedTaskExecutionCheckpointId,
  cleanupClosedCheckpointTransactionId,
  cleanupClosedTaskExecutionIdLedgerStateId,
  cleanupClosedTaskExecutionIdLedgerRevision,
  pendingAdapterBoundary: none,
  adapterRecordCleanupState: none,
  nonCheckpointAuthoritiesDirectlyEqual: true,
  committedAndReloaded: true
}

TaskExecutionRecoveryResumeGate {
  taskExecutionCheckpointId,
  taskExecutionIdLedgerStateId,
  taskExecutionIdLedgerRevision,
  pendingAdapterBoundary: none,
  adapterRecordCleanupState: NoPendingTaskExecutionAdapterRecordCleanup,
  adapterRecordCleanupClosureEvidence: TaskExecutionAdapterRecordCleanupClosureEvidence,
  residualAdapterBoundaryRecordCount: 0,
  ordinaryAllocationModelAndAdapterWorkAuthorized: true
}

TaskExecutionCheckpoint =
  | TaskExecutionPreparationCheckpoint {
      phase: preparation,
      taskExecutionCheckpointId,
      parentTaskExecutionCheckpointId?,
      serializerContractVersion,
      taskExecutionIdLedger: TaskExecutionIdLedger,
      taskDefinitionStateId,
      taskLeaseId,
      copySourceRegistry: CopySourceRegistry,
      pendingAdapterBoundary: NoPendingTaskExecutionAdapterBoundary,
      adapterRecordCleanupState: NoPendingTaskExecutionAdapterRecordCleanup,
      statePath
    }
  | ActiveTaskExecutionCheckpoint {
      phase: active,
      taskExecutionCheckpointId,
      parentTaskExecutionCheckpointId?,
      serializerContractVersion,
      taskExecutionIdLedger: TaskExecutionIdLedger,
      taskExecutionAttempts: TaskExecutionAttemptRegistry,
      activeTaskExecutionAttemptId,
      taskDefinitionStateId,
      principleRegistryStateId,
      principleRegistryStateRevision,
      principleSelectionIds[],
      taskLeaseId,
      operationIntentPlan: OperationIntentPlan,
      copySourceRegistry: CopySourceRegistry,
      operationRecords: OperationRecordRegistry,
      operationJournal: OperationJournal,
      fileStateTransitions: FileStateTransitionRegistry,
      runtimeFileState: RuntimeFileState,
      executionEvidenceRegistry: ExecutionEvidenceRegistryState,
      taskOverlayId,
      expectedTaskOverlayRevision,
      pendingAdapterBoundary: TaskExecutionAdapterBoundary,
      adapterRecordCleanupState: TaskExecutionAdapterRecordCleanupState,
      adapterRecordCleanupClosureBinding?: TaskExecutionAdapterRecordCleanupClosureBinding,
      statePath
      // A ready boundary requires cleanup kind none. A terminal successor has
      // boundary none + pending_release; its committed cleanup-only successor
      // has both discriminants none plus the closure binding before ordinary
      // work may resume. The binding is forbidden on every other checkpoint.
    }

FinalValidationInvocationId {
  featureId,
  workflowStateId,
  workflowStateRevision,
  taskDefinitionStateId,
  taskRuntimeRevision,
  finalCommittedWorkspaceRevision,
  requiredFinalCheckSetId,
  featureLogRunId
}

FeatureExecutionProcessLeaseId {
  featureId,
  featureLogRunId,
  processInstanceId,
  leaseSlot: feature_execution
  // Closed run/process tuple. It is never reused by a later process or run and
  // is not derived from a path, clock, model value, content, or fingerprint.
}

FeatureExecutionProcessLeaseOwnerRef {
  processLeaseId: FeatureExecutionProcessLeaseId,
  featureId,
  featureLogRunId,
  processInstanceId
}

FeatureExecutionProcessLeaseCapability {
  owner: FeatureExecutionProcessLeaseOwnerRef,
  leaseEpoch,
  opaqueLeaseTokenHandle,
  adapterId,
  adapterContractVersion
  // Runner-held, nonserializable, nonloggable, and never model-visible.
}

FeatureExecutionProcessLeaseObservation =
  | FeatureExecutionProcessLeaseAcquiredObservation {
      kind: acquired,
      owner: FeatureExecutionProcessLeaseOwnerRef,
      leaseEpoch,
      opaqueLeaseTokenHandle,
      adapterId,
      adapterContractVersion,
      osProcessOwnershipLive: true
    }
  | FeatureExecutionProcessLeaseRejectedObservation {
      kind: rejected,
      processLeaseId: FeatureExecutionProcessLeaseId,
      reason: identity_already_live | adapter_unavailable |
              process_ownership_unprovable
    }

FeatureExecutionProcessLeaseValidation {
  capability: FeatureExecutionProcessLeaseCapability,
  exactFeatureRunProcessIdentityJoin: true,
  adapterBackedProcessOwnershipLive: true,
  leaseIdentityNeverRebinds: true
}

FeatureExecutionProcessLeaseValidationRejection {
  observation: FeatureExecutionProcessLeaseAcquiredObservation,
  rejectionCode: feature_mismatch | run_mismatch | process_mismatch |
                 adapter_mismatch | duplicate_token | ownership_not_live,
  transientTokenRetainedForCleanup: true
}

FeatureExecutionProcessLeaseAcquisitionRejectionEvidence {
  observation: FeatureExecutionProcessLeaseRejectedObservation,
  exactFeatureRunProcessIdentityJoin: true,
  noLeaseCapabilityOrOpaqueTokenIssued: true
}

FeatureExecutionLockCapability {
  featureId,
  featureLogRunId,
  activeFeatureDirectoryCapabilityId,
  processLeaseId: FeatureExecutionProcessLeaseId,
  ownerProcessInstanceId,
  lockEpoch,
  opaqueLockTokenHandle,
  adapterId,
  adapterContractVersion
  // Exclusive per feature, runner-held, nonserializable, and OS-released on
  // process death. It is distinct from the short feature-WAL collection lock.
}

FeatureExecutionLockObservation =
  | FeatureExecutionLockAcquiredObservation {
      kind: acquired,
      featureId,
      featureLogRunId,
      activeFeatureDirectoryCapabilityId,
      processLeaseId: FeatureExecutionProcessLeaseId,
      ownerProcessInstanceId,
      lockEpoch,
      opaqueLockTokenHandle,
      adapterId,
      adapterContractVersion
    }
  | FeatureExecutionLockContendedObservation {
      kind: contended,
      featureId,
      liveOwnerProcessLeaseId: FeatureExecutionProcessLeaseId,
      boundedWaitExhausted: true
    }

FeatureExecutionLockValidation {
  capability: FeatureExecutionLockCapability,
  processLeaseValidation: FeatureExecutionProcessLeaseValidation,
  exactFeatureDirectoryAndRunJoin: true,
  exclusiveFeatureOwnershipProven: true
}

FeatureExecutionLockValidationRejection {
  observation: FeatureExecutionLockAcquiredObservation,
  rejectionCode: feature_mismatch | directory_mismatch | run_mismatch |
                 lease_mismatch | adapter_mismatch | duplicate_token |
                 exclusivity_unprovable,
  transientTokenRetainedForCleanup: true
}

FeatureExecutionLockContentionEvidence {
  observation: FeatureExecutionLockContendedObservation,
  exactFeatureAndLiveOwnerJoin: true,
  noFeatureLockCapabilityOrOpaqueTokenIssued: true
}

FeatureExecutionRejectedCapabilityCleanupObservation {
  capabilityKind: process_lease | feature_execution_lock,
  adapterId,
  ownerProcessInstanceId,
  releasedOrConfirmedNotOwned: true,
  runnerTableEntryAbsent: true
}

FeatureExecutionRejectedCapabilityCleanupEvidence {
  capabilityKind: process_lease | feature_execution_lock,
  exactValidationRejectionJoin: true,
  releaseOrNonownershipObserved: true,
  noCapabilityOrRunnerTableEntryRemains: true
}

FeatureExecutionProcessLeaseLivenessEntryObservation =
  | LiveFeatureExecutionProcessLeaseEntry {
      owner: FeatureExecutionProcessLeaseOwnerRef,
      disposition: live,
      exactOsProcessOwnershipObserved: boolean
    }
  | AbsentOrTerminalFeatureExecutionProcessLeaseEntry {
      owner: FeatureExecutionProcessLeaseOwnerRef,
      disposition: absent_or_terminal,
      leaseIdentityCannotBeReacquired: boolean
    }
  | UnknownFeatureExecutionProcessLeaseEntry {
      owner: FeatureExecutionProcessLeaseOwnerRef,
      disposition: unknown,
      reason: adapter_unavailable | ownership_unprovable |
              malformed_owner_ref | observation_ceiling_exceeded
    }

FeatureExecutionProcessLeaseLivenessRegistryObservation {
  featureId,
  featureExecutionLockEpoch,
  overlayCollectionLockEpoch,
  requestedOwners: FeatureExecutionProcessLeaseOwnerRef[],
  entries: FeatureExecutionProcessLeaseLivenessEntryObservation[],
  currentProcessLeaseId: FeatureExecutionProcessLeaseId,
  currentProcessLeaseObservedLive: boolean,
  completeBoundedObservation: boolean,
  adapterId,
  adapterContractVersion
}

FeatureExecutionProcessLeaseLivenessAdapterFailureObservation {
  featureId,
  featureExecutionLockEpoch,
  overlayCollectionLockEpoch,
  requestedOwners: FeatureExecutionProcessLeaseOwnerRef[],
  failureCode: adapter_unavailable | os_ownership_query_failed |
               result_delivery_failed,
  completeBoundedObservation: false,
  adapterId,
  adapterContractVersion
}

FeatureExecutionProcessLeaseLivenessOutcome =
  | { kind: observed,
      observation: FeatureExecutionProcessLeaseLivenessRegistryObservation }
  | { kind: adapter_failed,
      failure: FeatureExecutionProcessLeaseLivenessAdapterFailureObservation }

FeatureExecutionProcessLeaseLivenessRegistryValidation {
  outcome: FeatureExecutionProcessLeaseLivenessOutcome,
  exactOwnerCoverageOnceEach: true,
  noUnknownOrDuplicateOwner: true,
  currentLeaseAndFeatureLockJoin: true,
  sameOverlayCollectionLockEpoch: true,
  onlyLiveToTerminalTransitionCanFollow: true
  // This run-local value authorizes classification only; it is neither
  // persisted workflow authority nor a timeout/heartbeat guess.
}

FeatureExecutionProcessLeaseLivenessRejection {
  outcome: FeatureExecutionProcessLeaseLivenessOutcome,
  rejectionCode: adapter_failure | incomplete_owner_coverage |
                 duplicate_or_unknown_owner | unknown_disposition |
                 current_lease_not_live | owner_ref_mismatch |
                 feature_lock_epoch_mismatch |
                 collection_lock_epoch_mismatch |
                 adapter_contract_mismatch | ceiling_exceeded,
  overlayInventoryClassificationForbidden: true,
  ordinaryCollectionLockReleaseAllowedOnlyIfCapabilitiesRemainLive: true
}

FeatureExecutionLockReleaseObservation {
  featureId,
  processLeaseId: FeatureExecutionProcessLeaseId,
  lockEpoch,
  released: true
}

FeatureExecutionLockReleaseEvidence {
  releaseObservation: FeatureExecutionLockReleaseObservation,
  allTaskOverlayAndFinalValidationWorkTerminal: true,
  finalValidationOverlayCollectionLockTerminalEvidence:
    FinalValidationOverlayCollectionLockTerminalEvidence,
  noOverlayCollectionLockHeld: true,
  exactFeatureLockReleasedOnce: true
}

FeatureExecutionLockTerminalEvidence =
  | ReleasedFeatureExecutionLockTerminalEvidence {
      kind: released_validated,
      releaseEvidence: FeatureExecutionLockReleaseEvidence
    }
  | FeatureExecutionLockNeverAcquiredTerminalEvidence {
      kind: contention_proves_not_acquired,
      contentionEvidence: FeatureExecutionLockContentionEvidence
    }
  | RejectedFeatureExecutionLockCleanedTerminalEvidence {
      kind: rejected_acquired_observation_cleaned,
      rejection: FeatureExecutionLockValidationRejection,
      cleanupEvidence: FeatureExecutionRejectedCapabilityCleanupEvidence
    }

FeatureExecutionProcessLeaseReleaseObservation {
  processLeaseId: FeatureExecutionProcessLeaseId,
  leaseEpoch,
  released: true
}

FeatureExecutionProcessLeaseReleaseEvidence {
  releaseObservation: FeatureExecutionProcessLeaseReleaseObservation,
  featureExecutionLockTerminalEvidence: FeatureExecutionLockTerminalEvidence,
  exactLeaseReleasedOnceAfterFeatureLockTerminal: true
}

FinalValidationOverlayCollectionLockCapability {
  collectionArtifactPathId,
  featureId,
  ownerProcessInstanceId,
  ownerProcessLeaseId: FeatureExecutionProcessLeaseId,
  featureExecutionLockEpoch,
  lockEpoch,
  opaqueLockTokenHandle,
  adapterId,
  adapterContractVersion,
  osProcessOwned: true,
  releasedOnOwnerProcessDeath: true,
  epochCannotBeRebound: true
  // Runner-held, nonserializable, nonloggable, and never model-visible. A
  // later process can acquire only a fresh epoch after OS-observed owner death.
}

FinalValidationOverlayCollectionLockObservation =
  | FinalValidationOverlayCollectionLockAcquired {
      kind: acquired,
      collectionArtifactPathId,
      featureId,
      ownerProcessInstanceId,
      ownerProcessLeaseId: FeatureExecutionProcessLeaseId,
      featureExecutionLockEpoch,
      lockEpoch,
      opaqueLockTokenHandle,
      adapterId,
      adapterContractVersion,
      acquiredUnderValidatedFeatureExecutionLock: boolean,
      osProcessOwnedObserved: boolean,
      processDeathReleaseObserved: boolean,
      epochNonrebindabilityObserved: boolean
    }
  | FinalValidationOverlayCollectionLockContended {
      kind: contended,
      collectionArtifactPathId,
      boundedWaitExhausted: true
    }
  | FinalValidationOverlayCollectionLockAcquisitionFailed {
      kind: adapter_failed_no_token,
      collectionArtifactPathId,
      failureCode: adapter_unavailable | os_lock_error | policy_timeout,
      noOpaqueTokenIssued: true,
      runnerTableEntryAbsent: true,
      adapterId,
      adapterContractVersion
    }

FinalValidationOverlayCollectionLockValidation {
  capability: FinalValidationOverlayCollectionLockCapability,
  exactFeatureRootCollectionJoin: true,
  exactProcessLeaseAndFeatureExecutionLockEpochJoin: true,
  adapterBackedOwnerProcessLiveness: true,
  processDeathReleaseAndNonrebindableEpochProven: true,
  runnerHeldNonserializableCapability: true,
  outerCapabilitiesObservedLive: true
}

FinalValidationOverlayCollectionLockValidationRejection {
  observation: FinalValidationOverlayCollectionLockAcquired,
  rejectionCode: collection_mismatch | feature_mismatch | process_mismatch |
                 lease_mismatch | feature_lock_epoch_mismatch |
                 adapter_mismatch | duplicate_token |
                 acquisition_outer_binding_unprovable |
                 os_process_ownership_unprovable |
                 process_death_release_unprovable |
                 epoch_nonrebindability_unprovable |
                 outer_capability_not_live,
  transientTokenRetainedForCleanup: true
}

FinalValidationOverlayCollectionLockContentionEvidence {
  observation: FinalValidationOverlayCollectionLockContended,
  exactCollectionAndOuterAuthorityJoin: true,
  boundedWaitPolicyExhausted: true,
  noCollectionLockCapabilityOrOpaqueTokenIssued: true,
  runnerTableEntryAbsent: true
}

FinalValidationOverlayCollectionLockAcquisitionFailureEvidence {
  observation: FinalValidationOverlayCollectionLockAcquisitionFailed,
  exactCollectionAndOuterAuthorityJoin: true,
  adapterFailureCodeValidated: true,
  noCollectionLockCapabilityOrOpaqueTokenIssued: true,
  runnerTableEntryAbsent: true
}

FinalValidationOverlayRejectedCollectionLockCleanupObservation {
  collectionArtifactPathId,
  ownerProcessInstanceId,
  releasedOrConfirmedNotOwned: true,
  runnerTableEntryAbsent: true,
  adapterId,
  adapterContractVersion
}

FinalValidationOverlayRejectedCollectionLockCleanupAdapterFailureObservation {
  collectionArtifactPathId,
  ownerProcessInstanceId,
  failureCode: adapter_unavailable | release_failed | result_delivery_failed,
  cleanupDisposition: proven_not_owned | indeterminate,
  adapterId,
  adapterContractVersion
}

FinalValidationOverlayRejectedCollectionLockCleanupOutcome =
  | { kind: cleanup_observed,
      observation: FinalValidationOverlayRejectedCollectionLockCleanupObservation }
  | { kind: adapter_failed,
      failure:
        FinalValidationOverlayRejectedCollectionLockCleanupAdapterFailureObservation }

FinalValidationOverlayRejectedCollectionLockCleanupEvidence {
  rejection: FinalValidationOverlayCollectionLockValidationRejection,
  cleanupOutcome: FinalValidationOverlayRejectedCollectionLockCleanupOutcome,
  exactObservationRejectionAndAdapterJoin: true,
  releaseOrNonownershipObserved: true,
  opaqueHandleDestroyed: true,
  noCollectionLockCapabilityOrRunnerTableEntryRemains: true
}

FinalValidationRejectedCollectionLockCleanupFailStopEvidence {
  rejection: FinalValidationOverlayCollectionLockValidationRejection,
  cleanupOutcome: FinalValidationOverlayRejectedCollectionLockCleanupOutcome,
  failureKind: adapter_failure_indeterminate | token_or_table_entry_may_remain,
  noFurtherPipelineNodeInvoked: true,
  ordinaryReleaseEvidenceForbidden: true,
  ownerProcessTerminationRequired: true,
  freshRunRecoveryRequired: true
}

RunnerCapabilityLossFailStopEvidence {
  expectedProcessLeaseId: FeatureExecutionProcessLeaseId,
  expectedFeatureExecutionLockEpoch,
  expectedOverlayCollectionLockEpoch?,
  lossKind: process_lease_absent | feature_lock_absent |
            overlay_collection_lock_absent | epoch_substituted |
            runner_table_token_mismatch,
  detectedByRunnerCapabilityGuard: true,
  noFurtherPipelineNodeInvoked: true,
  noOrdinaryReleaseEvidenceFabricated: true,
  ownerProcessTerminationRequired: true,
  freshRunMustAcquireNewNonrebindableEpochsAndSweepOrphans: true
  // This is runner infrastructure evidence for crash/restart testing, not a
  // successful PipelineOutcome and not an orchestrator-produced value.
}

FinalValidationOverlayCollectionLockReleaseObservation {
  collectionArtifactPathId,
  ownerProcessInstanceId,
  ownerProcessLeaseId: FeatureExecutionProcessLeaseId,
  featureExecutionLockEpoch,
  lockEpoch,
  disposition: released_now | already_absent,
  runnerTableEntryAbsent: true,
  adapterId,
  adapterContractVersion
}

FinalValidationOverlayCollectionLockReleaseAdapterFailureObservation {
  collectionArtifactPathId,
  ownerProcessInstanceId,
  ownerProcessLeaseId: FeatureExecutionProcessLeaseId,
  featureExecutionLockEpoch,
  lockEpoch,
  failureCode: adapter_unavailable | release_failed | result_delivery_failed,
  lockDisposition: proven_still_held | indeterminate,
  adapterId,
  adapterContractVersion
}

FinalValidationOverlayCollectionLockReleaseOutcome =
  | { kind: release_observed,
      observation: FinalValidationOverlayCollectionLockReleaseObservation }
  | { kind: adapter_failed,
      failure: FinalValidationOverlayCollectionLockReleaseAdapterFailureObservation }

FinalValidationOverlayCollectionLockReleaseRetryEvidence {
  releaseOutcome: FinalValidationOverlayCollectionLockReleaseOutcome,
  exactOriginalValidatedCapabilityAndEpochJoin: true,
  lockDisposition: proven_still_held,
  runnerTableEntryStillExact: true,
  outerFeatureExecutionLockAndProcessLeaseStillLive: true,
  sameLogicalReleaseRetryOnly: true
}

FinalValidationCollectionLockReleaseFailStopEvidence {
  releaseOutcome: FinalValidationOverlayCollectionLockReleaseOutcome,
  failureKind: lock_disposition_indeterminate | runner_table_indeterminate,
  noOrdinaryReleaseEvidenceFabricated: true,
  noFurtherPipelineNodeInvoked: true,
  ownerProcessTerminationRequired: true,
  freshRunRecoveryRequired: true
}

FinalValidationOverlayLeaseHeader {
  validationOverlayId,
  finalValidationInvocationId: FinalValidationInvocationId,
  featureId,
  featureLogRunId,
  ownerProcessLease: FeatureExecutionProcessLeaseOwnerRef,
  featureExecutionLockEpoch,
  finalValidationOverlayCollectionArtifactPathId,
  finalCommittedWorkspaceRevision,
  headerAtomicallyPublished: true,
  headerDurableBeforeOverlayPublication: true
  // The overlay ID is the already closed run-scoped invocation tuple plus its
  // fixed overlay slot. No random/path/content/model-derived identity is used.
}

FinalValidationOverlayLeaseHeaderValidation {
  header: FinalValidationOverlayLeaseHeader,
  exactInvocationFeatureRunLeaseLockCollectionAndBaseRevisionJoin: true,
  engineDerivedStructuralOverlayIdentity: true,
  canonicalHeaderBytesOwnedByEngine: true,
  adapterMustPublishThoseExactBytesAtomicallyOrNothing: true,
  partialHeaderStagingNeverEnumerable: true
}

RawFinalValidationOverlayLeaseHeaderObservation {
  validationOverlayId,
  finalValidationInvocationId: FinalValidationInvocationId,
  featureId,
  featureLogRunId,
  ownerProcessLease: FeatureExecutionProcessLeaseOwnerRef,
  featureExecutionLockEpoch,
  finalValidationOverlayCollectionArtifactPathId,
  finalCommittedWorkspaceRevision,
  headerAtomicallyPublished: boolean,
  headerDurableBeforeOverlayPublication: boolean
}

FinalValidationOverlayCreationObservation {
  rawHeader: RawFinalValidationOverlayLeaseHeaderObservation,
  collectionLockEpoch,
  validationOverlayRevision,
  overlayPublished: boolean,
  observedEntryCount,
  adapterId,
  adapterContractVersion
}

FinalValidationOverlayCreationAdapterFailureObservation {
  finalValidationInvocationId: FinalValidationInvocationId,
  engineDerivedValidationOverlayId,
  finalValidationOverlayCollectionArtifactPathId,
  collectionLockEpoch,
  failurePhase: header_persistence | overlay_publication | result_delivery |
                adapter_unavailable,
  publicationDisposition: proven_absent | indeterminate,
  boundedAdapterErrorCode,
  adapterId,
  adapterContractVersion
}

FinalValidationOverlayCreationOutcome =
  | { kind: created,
      observation: FinalValidationOverlayCreationObservation }
  | { kind: adapter_failed,
      failure: FinalValidationOverlayCreationAdapterFailureObservation }

FinalValidationOverlayCreationValidation {
  observation: FinalValidationOverlayCreationObservation,
  header: FinalValidationOverlayLeaseHeader,
  validationOverlayId,
  finalValidationInvocationId: FinalValidationInvocationId,
  finalValidationOverlayCollectionArtifactPathId,
  collectionLockEpoch,
  exactHeaderRunProcessLeaseAndBaseRevisionJoin: true,
  exactValidatedFeatureExecutionLockJoin: true,
  headerAtomicallyPublished: true,
  headerDurableBeforeEmptyOverlayPublication: true,
  noCoexistingLiveOverlay: true
}

FinalValidationOverlayCreationRejection {
  outcome: FinalValidationOverlayCreationOutcome,
  rejectionCode: adapter_failure | invocation_mismatch | overlay_identity_mismatch |
                 collection_mismatch | base_revision_mismatch |
                 header_owner_mismatch | outer_control_mismatch |
                 lock_epoch_mismatch | header_order_unprovable |
                 nonempty_initial_overlay | coexisting_overlay |
                 adapter_contract_mismatch,
  candidateCleanupRequired: true,
  ordinaryCollectionLockReleaseForbiddenUntilCleanupValidated: true
}

FinalValidationOverlayCreationCleanupObservation {
  finalValidationInvocationId: FinalValidationInvocationId,
  engineDerivedValidationOverlayId,
  finalValidationOverlayCollectionArtifactPathId,
  collectionLockEpoch,
  disposition: discarded_now | already_absent | adapter_failed,
  residualCandidateEntryCount?,
  residualCandidateBytes?,
  projectSpecsAndEngineStateUnchanged: boolean,
  adapterId,
  adapterContractVersion
}

FinalValidationOverlayCreationCandidateInspection {
  finalValidationInvocationId: FinalValidationInvocationId,
  engineDerivedValidationOverlayId,
  finalValidationOverlayCollectionArtifactPathId,
  collectionLockEpoch,
  observedCandidateEntryCount,
  observedCandidateBytes,
  completeBoundedInspection: boolean,
  ceilingExceeded: boolean,
  projectSpecsAndEngineStateChanged: boolean,
  adapterId,
  adapterContractVersion
}

FinalValidationOverlayCreationCleanupEvidence {
  rejection: FinalValidationOverlayCreationRejection,
  cleanupObservation: FinalValidationOverlayCreationCleanupObservation,
  candidateInspection: FinalValidationOverlayCreationCandidateInspection,
  exactEngineDerivedCandidateAndCollectionJoin: true,
  discardedOrAlreadyAbsent: true,
  residualCandidateEntryCount: 0,
  residualCandidateBytes: 0,
  completeBoundedIndependentInspectionWithNoCeilingBreach: true,
  sameValidatedCollectionLockContinuouslyHeld: true,
  outerFeatureExecutionLockAndProcessLeaseStillLive: true,
  noUntrustedHeaderOrCallerPathUsed: true,
  projectSpecsAndEngineStateUnchanged: true
}

FinalValidationCreationCleanupFailStopEvidence {
  rejection: FinalValidationOverlayCreationRejection,
  cleanupObservation: FinalValidationOverlayCreationCleanupObservation,
  candidateInspection: FinalValidationOverlayCreationCandidateInspection,
  failureKind: cleanup_adapter_failure | inspection_incomplete |
               inspection_ceiling_exceeded | residual_candidate |
               authority_change_observed,
  noOrdinaryCollectionLockReleaseAuthorized: true,
  noFurtherPipelineNodeInvoked: true,
  ownerProcessTerminationRequired: true,
  freshRunRecoveryRequired: true
}

OrphanedFinalValidationOverlayEntry {
  header: FinalValidationOverlayLeaseHeader,
  overlayPublicationState: header_only | overlay_present,
  observedOverlayRevision?,
  observedEntryCount,
  observedBytes,
  ownerRunIsNotCurrent: true,
  ownerProcessLeaseDisposition: absent_or_terminal,
  currentRunCannotReuseIdentity: true
}

FinalValidationOverlayInventoryEntry {
  header: FinalValidationOverlayLeaseHeader,
  overlayPublicationState: header_only | overlay_present,
  observedOverlayRevision?,
  observedEntryCount,
  observedBytes
}

FinalValidationOverlayStartupInventoryObservation {
  finalValidationOverlayCollectionArtifactPathId,
  collectionLockEpoch,
  inventoryCeilings,
  observedEntryCount,
  observedBytes,
  entries: FinalValidationOverlayInventoryEntry[],
  malformedOrUnownedEntryCount,
  ceilingExceeded: boolean,
  completeBoundedInventory: boolean,
  adapterId,
  adapterContractVersion
}

FinalValidationOverlayStartupInventoryValidation {
  inventory: FinalValidationOverlayStartupInventoryObservation,
  leaseLivenessRegistry:
    FeatureExecutionProcessLeaseLivenessRegistryValidation,
  orphanedEntries: OrphanedFinalValidationOverlayEntry[],
  liveEntries: FinalValidationOverlayInventoryEntry[],
  currentLiveEntryCount: 0,
  otherLiveEntryCount: 0,
  everyInventoryEntryClassifiedExactlyOnce: true,
  sameFeatureExecutionAndCollectionLockEpochs: true
}

FinalValidationOverlayStartupInventoryRejection {
  inventory: FinalValidationOverlayStartupInventoryObservation,
  rejectionCode: malformed_or_unowned_entry | entry_ceiling_exceeded |
                 byte_ceiling_exceeded | incomplete_inventory |
                 owner_liveness_incomplete | current_or_other_live_entry |
                 collection_lock_epoch_mismatch | outer_control_mismatch |
                 adapter_contract_mismatch,
  overlayCreationForbidden: true,
  ordinaryReleaseAllowedOnlyIfAllCapabilitiesRemainValidatedAndLive: true
}

FinalValidationOverlayOrphanDiscardObservation {
  header: FinalValidationOverlayLeaseHeader,
  disposition: discarded_now | already_absent | adapter_failed,
  residualEntryCount?,
  residualBytes?,
  projectSpecsAndEngineStateUnchanged: boolean,
  adapterId,
  adapterContractVersion
}

FinalValidationOverlayStartupCleanupEvidence {
  inventoryValidation: FinalValidationOverlayStartupInventoryValidation,
  discardObservations: FinalValidationOverlayOrphanDiscardObservation[],
  everyOrphanCoveredExactlyOnce: true,
  residualOrphanCount: 0,
  residualLiveEntryCount: 0,
  sameCollectionLockContinuouslyHeldThroughCleanup: true,
  cleanupCompleteBeforeNewFinalValidationOverlay: true
}

FinalValidationOverlayStartupCleanupRejection {
  inventoryValidation: FinalValidationOverlayStartupInventoryValidation,
  discardObservations: FinalValidationOverlayOrphanDiscardObservation[],
  rejectionCode: missing_or_duplicate_orphan_result | orphan_identity_mismatch |
                 adapter_failure | residual_orphan_entries |
                 residual_live_entry | authority_changed |
                 collection_lock_epoch_mismatch | adapter_contract_mismatch,
  newOverlayCreationForbidden: true,
  ordinaryReleaseAllowedOnlyIfAllCapabilitiesRemainValidatedAndLive: true
}

FinalValidationOverlayCollectionLockReleaseEvidence =
  | FinalValidationOverlayCreatedLockReleaseEvidence {
      startupCleanupEvidence: FinalValidationOverlayStartupCleanupEvidence,
      overlayCreationObservation: FinalValidationOverlayCreationObservation,
      overlayCreationValidation: FinalValidationOverlayCreationValidation,
      releaseOutcome: FinalValidationOverlayCollectionLockReleaseOutcome,
      sameCollectionLockEpoch: true,
      outerFeatureExecutionLockAndProcessLeaseStillLive: true,
      releasedAfterOverlayPublication: true
    }
  | FinalValidationOverlayPrepublicationLockReleaseEvidence {
      failurePhase: inventory | lease_liveness_inspection |
                    lease_liveness_validation | inventory_validation |
                    orphan_cleanup | cleanup_validation,
      releaseOutcome: FinalValidationOverlayCollectionLockReleaseOutcome,
      noOverlayPublished: true,
      sameCollectionLockEpoch: true,
      outerFeatureExecutionLockAndProcessLeaseStillLive: true
    }
  | FinalValidationOverlayCreationCleanupLockReleaseEvidence {
      creationCleanupEvidence: FinalValidationOverlayCreationCleanupEvidence,
      releaseOutcome: FinalValidationOverlayCollectionLockReleaseOutcome,
      sameCollectionLockEpoch: true,
      releasedAfterCandidateProvenAbsent: true,
      outerFeatureExecutionLockAndProcessLeaseStillLive: true
    }

FinalValidationOverlayCollectionLockTerminalEvidence =
  | FinalValidationOverlayCollectionLockNotAttemptedEvidence {
      kind: not_attempted,
      acquisitionNodeInvocationCount: 0,
      runnerTableEntryAbsent: true
    }
  | ReleasedFinalValidationOverlayCollectionLockTerminalEvidence {
      kind: released_validated,
      releaseEvidence: FinalValidationOverlayCollectionLockReleaseEvidence
    }
  | ContendedFinalValidationOverlayCollectionLockTerminalEvidence {
      kind: contention_proves_not_acquired,
      contentionEvidence:
        FinalValidationOverlayCollectionLockContentionEvidence
    }
  | FailedAcquisitionFinalValidationOverlayCollectionLockTerminalEvidence {
      kind: acquisition_failure_proves_not_acquired,
      acquisitionFailureEvidence:
        FinalValidationOverlayCollectionLockAcquisitionFailureEvidence
    }
  | RejectedFinalValidationOverlayCollectionLockTerminalEvidence {
      kind: rejected_acquired_observation_cleaned,
      rejection: FinalValidationOverlayCollectionLockValidationRejection,
      cleanupEvidence:
        FinalValidationOverlayRejectedCollectionLockCleanupEvidence
    }
  // Capability loss/substitution is deliberately absent: that run fail-stops
  // and returns no PipelineOutcome; only a fresh run may recover orphan state.

FinalValidationCommandAuthorizationId {
  finalValidationInvocationId,
  requiredCheckOrdinal,
  boundedAttemptOrdinal
}

FinalValidationCommandSavepointId {
  commandAuthorizationId,
  validationOverlayId,
  expectedValidationOverlayRevision
}

FinalValidationCommandChildOverlayId {
  commandSavepointId: FinalValidationCommandSavepointId,
  childSlot: child_overlay
}

FinalValidationCommandSavepointCreationObservation {
  commandSavepointId: FinalValidationCommandSavepointId,
  commandAuthorizationId: FinalValidationCommandAuthorizationId,
  parentValidationOverlayId,
  expectedParentValidationOverlayRevision,
  observedParentValidationOverlayRevision,
  childValidationOverlayId: FinalValidationCommandChildOverlayId,
  childValidationOverlayRevision,
  observedChildEntryCount,
  ownerProcessLeaseId: FeatureExecutionProcessLeaseId,
  featureExecutionLockEpoch,
  childPublished: boolean,
  noTaskExecutionAdapterBoundaryRecord: boolean,
  adapterId,
  adapterContractVersion
  // The child ID is the savepoint identity plus the fixed `child_overlay` slot;
  // no random/path/content/model value or task adapter record is introduced.
}

FinalValidationCommandSavepointCreationAdapterFailureObservation {
  commandSavepointId: FinalValidationCommandSavepointId,
  commandAuthorizationId: FinalValidationCommandAuthorizationId,
  parentValidationOverlayId,
  expectedParentValidationOverlayRevision,
  failurePhase: child_publication | result_delivery | adapter_unavailable,
  childPublicationDisposition: proven_absent | indeterminate,
  boundedAdapterErrorCode,
  adapterId,
  adapterContractVersion
}

FinalValidationCommandSavepointCreationOutcome =
  | { kind: created,
      observation: FinalValidationCommandSavepointCreationObservation }
  | { kind: adapter_failed,
      failure: FinalValidationCommandSavepointCreationAdapterFailureObservation }

FinalValidationCommandSavepointCreationValidation {
  observation: FinalValidationCommandSavepointCreationObservation,
  exactAuthorizationSavepointParentRevisionJoin: true,
  exactHeaderOwnerLeaseAndFeatureLockJoin: true,
  childIdentityStructuralAndUnique: true,
  childPublishedAtRevisionZeroAndEmpty: true,
  parentOverlayUnchangedAtPublication: true,
  noTaskExecutionAdapterBoundaryRecord: true
}

FinalValidationCommandSavepointCreationRejection {
  outcome: FinalValidationCommandSavepointCreationOutcome,
  rejectionCode: adapter_failure | authorization_mismatch | savepoint_identity_mismatch |
                 parent_revision_mismatch | header_owner_mismatch |
                 outer_control_mismatch | child_alias |
                 child_not_published | child_revision_mismatch |
                 nonempty_initial_child |
                 task_boundary_record_present | adapter_contract_mismatch,
  commandExecutionForbidden: true,
  parentOverlayAbortRequired: true
}

FinalValidationCommandSavepointDiscardObservation {
  commandSavepointId: FinalValidationCommandSavepointId,
  childValidationOverlayId: FinalValidationCommandChildOverlayId,
  disposition: discarded_now | already_absent,
  expectedParentValidationOverlayRevision,
  adapterId,
  adapterContractVersion
}

FinalValidationCommandSavepointDiscardAdapterFailureObservation {
  commandSavepointId: FinalValidationCommandSavepointId,
  childValidationOverlayId: FinalValidationCommandChildOverlayId,
  expectedParentValidationOverlayRevision,
  failurePhase: child_removal | result_delivery | adapter_unavailable,
  childRemovalDisposition: proven_absent | indeterminate,
  boundedAdapterErrorCode,
  adapterId,
  adapterContractVersion
}

FinalValidationCommandSavepointDiscardOutcome =
  | { kind: discard_observed,
      observation: FinalValidationCommandSavepointDiscardObservation }
  | { kind: adapter_failed,
      failure: FinalValidationCommandSavepointDiscardAdapterFailureObservation }

FinalValidationCommandSavepointPostDiscardInspection {
  commandSavepointId: FinalValidationCommandSavepointId,
  parentValidationOverlayId,
  expectedParentValidationOverlayRevision,
  observedParentValidationOverlayRevision,
  childPresent: boolean,
  residualChildEntryCount,
  residualChildBytes,
  taskExecutionAdapterBoundaryRecordCount,
  projectSpecsAndEngineStateChanged: boolean,
  completeBoundedInspection: boolean,
  ceilingExceeded: boolean,
  ownerProcessLeaseId: FeatureExecutionProcessLeaseId,
  featureExecutionLockEpoch,
  adapterId,
  adapterContractVersion
}

FinalValidationCommandSavepointDiscardEvidence {
  creationValidation: FinalValidationCommandSavepointCreationValidation,
  discardOutcome: FinalValidationCommandSavepointDiscardOutcome,
  postDiscardInspection: FinalValidationCommandSavepointPostDiscardInspection,
  exactSavepointAndOwnerJoin: true,
  childAbsent: true,
  residualChildEntryCount: 0,
  residualChildBytes: 0,
  parentValidationOverlayDirectlyEqualToExpected: true,
  noTaskExecutionAdapterBoundaryRecord: true,
  projectSpecsAndEngineStateUnchanged: true,
  completeBoundedInspectionWithNoCeilingBreach: true,
  outerFeatureExecutionLockAndProcessLeaseStillLive: true
}

FinalValidationCommandSavepointDiscardRejection {
  creationValidation: FinalValidationCommandSavepointCreationValidation,
  discardOutcome: FinalValidationCommandSavepointDiscardOutcome,
  postDiscardInspection: FinalValidationCommandSavepointPostDiscardInspection,
  rejectionCode: adapter_failure_indeterminate | savepoint_mismatch |
                 child_still_present | inspection_incomplete |
                 inspection_ceiling_exceeded |
                 parent_revision_changed | task_boundary_record_present |
                 project_or_engine_state_changed |
                 outer_control_mismatch | adapter_contract_mismatch,
  commandVerificationForbidden: true,
  parentOverlayAbortRequired: true
}

CommandSavepoint {
  savepointId,
  baseOverlayId,
  baseRevision,
  commandAuthorizationId,
  adapterBoundaryBinding:
    | { kind: task_execution,
        entry: TaskExecutionAdapterBoundaryEntryObservation }
    | { kind: final_validation,
        creationValidation: FinalValidationCommandSavepointCreationValidation,
        noTaskExecutionAdapterBoundaryRecord: true }
}

CommandDescriptor {
  commandId,
  descriptorVersion,
  owningProjectId,
  executableCapabilityId,
  resolvedExecutable,
  argvTemplate: {
    elementKind: literal | typed_placeholder,
    literal?, placeholderId?, placeholderTypeId?
  }[],
  canonicalWorkingDirectory,
  successExitCodes[],
  diagnosticMatcherIds[],
  timeoutMs,
  outputLimitBytes,
  allowedEnvironmentVariableNames[],
  networkPolicyId,
  mutability: read_only | task_persistent | dependency_mutation |
              disposable_validation,
  persistentWritePatterns: PathPattern[],
  ephemeralWritePatterns: PathPattern[],
  sandboxAdapterId,
  resourceQuotaProfileId
}

CommandRegistry {
  commandRegistryId,
  registryVersion,
  descriptors: CommandDescriptor[]
}

CommandAuthorization {
  authorizationId,
  authorizationScope: task_execution | final_validation,
  commandId,
  commandRegistryId,
  commandRegistryVersion,
  descriptorVersion,
  resolvedExecutable,
  resolvedArgv[],
  canonicalWorkingDirectory,
  successExitCodes[],
  diagnosticMatcherIds[],
  timeoutMs,
  outputLimitBytes,
  environmentVariableNameAllowlist[],
  networkPolicyId,
  mutability,
  sandboxAdapterId,
  taskFileCapabilityRegistryStateId?,  // required for task binding; forbidden for final validation
  typedArguments,
  processOutcomeExpectation:
    | { kind: success_required }
    | { kind: expected_red,
        evidencePredicateId,
        requiredDiagnosticCode,
        diagnosticMatcherId,
        mustBecomeGreenByTaskId },
  overlayBinding:
    | { kind: task, taskOverlayId, expectedTaskOverlayRevision }
    | { kind: final_validation, validationOverlayId, expectedValidationOverlayRevision },
  promotionMode: promote_intersection | discard_all,
  approvedTaskWriteFileIds[],
  commandAuthorizedWritePatterns: PathPattern[],
  promotableFiles: {
    fileId,
    allowedDeltaKinds: (create | modify | delete)[]
  }[],                       // task IDs intersect path policy and file capabilities
  ephemeralWrites: PathPattern[],
  resourceQuotas: {
    maxCreatedEntries,
    maxBytesWritten,
    maxCurrentDeltaBytes,
    maxFileBytes,
    maxPrivateTempBytes
  }
}

CommandDeltaEntry =
  | PersistentRegularFileDelta {
      fileId, repoRelativePath,
      deltaKind: create | modify | delete,
      nodeType: regular_file
    }
  | EphemeralRegularFileDelta {
      repoRelativePath,
      deltaKind: create | modify | delete,
      matchedRuleId,
      nodeType: regular_file
    }
  | EphemeralStructuralDirectoryDelta {
      repoRelativePath,
      deltaKind: create | delete,
      matchedRuleId,
      nodeType: directory,
      disposable: true
    }

RawCommandExecutionObservation {
  commandId,
  commandSavepointId,
  exitCode,
  boundedStdoutHandle,
  boundedStderrHandle,
  rawFilesystemObservationHandle,
  resourceTelemetry,
  durationMs
}

ValidatedCommandProcessOutcome =
  | CommandPassedProcessOutcome {
      commandId,
      commandSavepointId,
      exitCode,
      matchedSuccessExitCode,
      durationMs
    }
  | CommandFailedAsExpectedProcessOutcome {
      commandId,
      commandSavepointId,
      exitCode,
      evidencePredicateId,
      requiredDiagnosticCode,
      diagnosticMatcherId,
      matchedDiagnosticObservation: {
        stream: stdout | stderr,
        boundedRange,
        matcherVersion
      },
      mustBecomeGreenByTaskId,
      durationMs
    }

RejectedCommandProcessOutcome {
  commandId,
  commandSavepointId,
  exitCode,
  diagnosticCode: COMMAND_EXIT_UNEXPECTED | EXPECTED_RED_DIAGNOSTIC_MISSING |
                  EXPECTED_RED_UNEXPECTEDLY_GREEN | COMMAND_IDENTITY_MISMATCH,
  repairClass: model_atomic | environment | not_repairable
}

CommandResourceQuotaValidation {
  authorizationId,
  quotaProfileId,
  observedCounters: {
    createdEntries, bytesWritten, currentDeltaBytes,
    maximumFileBytes, privateTempBytes
  },
  authorizedCeilings,
  withinLimits: true,
  validatorId,
  validatorVersion
}

CommandDeltaValidation {
  authorizationId,
  commandSavepointId,
  persistentEntryOrdinals[],
  ephemeralEntryOrdinals[],
  structuralDisposableDirectoryOrdinals[],
  rejectedEntryOrdinals: [],
  validatorId,
  validatorVersion
}

CommandSavepointDiscardEvidence {
  authorizationId,
  commandSavepointId,
  preDiscardRevision,
  discardedEntryCount,
  residualEntryCount: 0,
  verifiedAbsent: true,
  adapterBoundaryDisposition:
    | { kind: task_execution_terminalized,
        discardReceipt: TaskExecutionAdapterDiscardReceipt }
    | { kind: final_validation_disposable,
        noTaskExecutionAdapterBoundaryRecord: true },
  sandboxAdapterId,
  sandboxAdapterVersion
}

CommandEphemeralDiscardEvidence {
  authorizationId,
  commandSavepointId,
  discardedEphemeralEntryOrdinals[],
  residualEphemeralEntryCount: 0,
  verifiedAbsent: true,
  sandboxAdapterId,
  sandboxAdapterVersion
}

OperationFileDeltaValidation {
  operationAuthorizationId,
  operationSavepointId,
  targetFileIds[],
  observedEntryCount,
  unexpectedEntryCount: 0,
  aliasOrSpecialNodeCount: 0,
  validatorId,
  validatorVersion
}

CommandDelta {
  entries: CommandDeltaEntry[]
  // Symlinks, hard-link aliases, devices, sockets, FIFOs, and other node types
  // have no representable valid variant and are rejected during raw-delta decoding.
}

TaskValidationAuthorization {
  authorizationId,
  taskLeaseId,
  taskDefinitionStateId,
  expectedRuntimeRevision,
  taskId,
  taskOverlayId,
  expectedTaskOverlayRevision,
  operationJournalId,
  operationJournalRevision,
  taskExecutionAttemptId,
  taskExecutionCheckpointId,
  operationRecordRegistryId,
  operationRecordRegistryRevision,
  fileStateTransitionRegistryId,
  fileStateTransitionRegistryRevision,
  inputRuntimeFileStateId,
  inputRuntimeFileStateRevision,
  nextRuntimeFileStateId,
  nextRuntimeFileStateRevision,
  executionEvidenceRegistryStateId,
  executionEvidenceRegistryRevision,
  requiredEvidencePredicateIds[],
  satisfiedEvidenceIds[],
  noUnexpectedChangeEvidenceId,
  singleUse: true
}

ImplementationActorRegistryMutation =
  | UnchangedImplementationActorRegistry {
      currentActorEvidenceRegistryState: ActorEvidenceRegistryState
    }
  | AppendedImplementationActorRegistry {
      inputActorEvidenceRegistryStateId,
      inputActorEvidenceRegistryStateRevision,
      nextActorEvidenceRegistryState: ActorEvidenceRegistryState,
      appendedEvidenceIds[]
    }

ManualVerificationTransaction = DurableTransactionMember & {
  transactionId,
  expectedWorkflowStateId,
  expectedWorkflowStateRevision,
  taskDefinitionStateId,
  taskId,
  expectedTaskRuntimeRevision,
  taskExecutionCheckpointId,
  inputExecutionEvidenceRegistryStateId,
  inputExecutionEvidenceRegistryStateRevision,
  nextExecutionEvidenceRegistry: ExecutionEvidenceRegistryState,
  actorEvidenceRegistryMutation: AppendedImplementationActorRegistry,
  manualVerificationEvidenceId,
  unchangedRuntimeFileStateId,
  unchangedRuntimeFileStateRevision,
  unchangedTaskOverlayId,
  unchangedTaskOverlayRevision,
  unchangedTaskRuntimeState: TaskRuntimeState,
  renderedTasksView: GeneratedView,
  projectDelta: none,
  singleUse: true
}

TaskExecutionCheckpointTransaction = DurableTransactionMember & {
  transactionId,
  featureId,
  expectedWorkflowStateId,
  expectedWorkflowStateRevision,
  taskDefinitionStateId,
  taskId,
  expectedTaskRuntimeRevision,
  inputTaskExecutionCheckpointId?,
  nextTaskExecutionCheckpoint: TaskExecutionCheckpoint,
  renderedTasksView: GeneratedView,
  projectDelta: none,
  singleUse: true
  // The inherited StateIdentityTransactionMember.stateIdentityMutations array
  // commits the first TaskExecutionIdLedger feature-state reservation; later
  // checkpoints carry its explicit unchanged/advanced feature-ledger member.
}

TaskOutcomeTransaction = DurableTransactionMember & {
  transactionId,
  taskDefinitionStateId,
  expectedRuntimeRevision,
  nextRuntimeState,
  executionJournalDelta,
  diagnosticIds[],
  evidenceIds[],
  inputExecutionEvidenceRegistryStateId,
  inputExecutionEvidenceRegistryRevision,
  nextExecutionEvidenceRegistry: ExecutionEvidenceRegistryState,
  actorEvidenceRegistryMutation: ImplementationActorRegistryMutation,
  unchangedRuntimeFileStateId,
  unchangedRuntimeFileStateRevision,
  renderedTasksView,
  leaseAndLockReleaseDelta,
  projectDelta: none
}

TaskTransaction = DurableTransactionMember & {
  transactionId,
  taskValidationAuthorizationId,
  taskDefinitionStateId,
  expectedTaskRuntimeRevision,
  taskId,
  taskLeaseId,
  taskOverlayId,
  expectedTaskOverlayRevision,
  taskExecutionAttemptId,
  taskExecutionCheckpointId,
  operationIntentPlanId,
  operationRecords: OperationRecordRegistry,
  operationJournal: OperationJournal,
  fileStateTransitions: FileStateTransitionRegistry,
  inputRuntimeFileStateId,
  inputRuntimeFileStateRevision,
  nextRuntimeFileState: RuntimeFileState,
  inputExecutionEvidenceRegistryStateId,
  inputExecutionEvidenceRegistryRevision,
  nextExecutionEvidenceRegistry: ExecutionEvidenceRegistryState,
  actorEvidenceRegistryMutation: ImplementationActorRegistryMutation,
  projectDelta,
  evidenceIds[],
  nextTaskRuntimeState: TaskRuntimeState,
  renderedTasksView: GeneratedView,
  leaseAndLockReleaseDelta,
  nextWorkflowState,
  singleUse: true
}

ReferenceRevisionDescendantMutation =
  | NoReferenceDescendantMutation {
      reason: no_feature_request_or_descendants
    }
  | InvalidateUncommittedReferenceDescendants {
      inputWorkflowControlEventRegistryStateId,
      inputWorkflowControlEventRegistryStateRevision,
      nextWorkflowControlEventRegistryState: WorkflowControlEventRegistryState,
      invalidation: ReworkInvalidationRecord
    }
  | ReconcileCommittedReferenceDescendants {
      inputWorkflowControlEventRegistryStateId,
      inputWorkflowControlEventRegistryStateRevision,
      nextWorkflowControlEventRegistryState: WorkflowControlEventRegistryState,
      invalidation: ReworkInvalidationRecord,
      inputTaskDefinitionStateId,
      inputTaskRuntimeRevision,
      nextTaskRuntimeState: TaskRuntimeState,
      inputExecutionEvidenceRegistryStateId,
      inputExecutionEvidenceRegistryStateRevision,
      nextExecutionEvidenceRegistry: ExecutionEvidenceRegistryState,
      evidenceInvalidation: ExecutionEvidenceInvalidationRecord
    }

FeatureActivation {
  featureIdentityTarget: NewFeatureIdentity,
  inputFeatureIdentityRegistryState: FeatureIdentityRegistryState,
  nextFeatureIdentityRegistryState: FeatureIdentityRegistryState,
  featureStateIdLedger: StateIdLedger,
  bootstrapAuthorityState: BootstrapAuthorityState,
  workflowArtifactRegistry: WorkflowArtifactRegistry,
  initialActorEvidenceRegistryState: ActorEvidenceRegistryState,
  initialReviewDecisionRegistryState: ReviewDecisionRegistryState,
  initialWorkflowControlEventRegistryState: WorkflowControlEventRegistryState,
  initialPassiveLiteralRegistryState: PassiveLiteralRegistryState,
  initialClarificationState: ClarificationRegistryState,
  initialWorkflowState: WorkflowState,
  directoryEntries: FeatureDirectoryCreationEntry[]
  // Fixed-path writes under Design Section 25.1, not a StageTransaction.
  // No transaction ID, project journal, marker, or project storage capability.
  // Only verified complete persisted state permits an active-feature capability.
}

StageTransitionKind =
  state_identity_reservation | state_identity_retirement |
  specification_acknowledgement_id_retirement |
  bootstrap_authority_refresh |
  clarification_pause | clarification_response |
  clarification_authority_resolution | specify_completion |
  plan_input_authority | plan_candidate |
  tasks_candidate | reference_revision | rework_invalidation |
  final_validation_failed | localized_task_remediation |
  implementation_reconciliation | implementation_completion

StageTransaction = DurableTransactionMember & (
  | StateIdentityReservationStageTransaction {
      transactionId,
      featureId,
      currentWorkflowStateId,
      currentWorkflowStateRevision,
      reservedStateIds[],
      exposureBoundary:
        model_provider | nontransactional_adapter |
        nontransactional_serializer | diagnostic_or_log |
        public_artifact_or_path,
      changesCanonicalBusinessState: false
    }
  | StateIdentityRetirementStageTransaction {
      transactionId,
      featureId,
      currentWorkflowStateId,
      currentWorkflowStateRevision,
      retiredStateIds[],
      retirementCause,
      changesCanonicalBusinessState: false
    }
  | SpecificationAcknowledgementIdRetirementStageTransaction {
      transactionId,
      featureId,
      expectedWorkflowStateId,
      expectedWorkflowStateRevision,
      expectedWorkflowStage: specified | planning,
      inputSpecificationProvenanceStateId,
      inputSpecificationProvenanceStateRevision,
      inputSpecificationAcknowledgementStateId,
      inputSpecificationAcknowledgementStateRevision,
      retirement: SpecificationAcknowledgementIdRetirement,
      actorEvidenceRegistryMutation:
        SpecificationEditFailureActorEvidenceRegistryMutation,
      nextSpecificationAcknowledgementState: SpecificationAcknowledgementState,
      nextSpecificationProvenanceState: SpecificationProvenanceState,
      planInputAuthorityMutation:
        SpecificationAcknowledgementRetirementPlanInputMutation,
      specificationView: EditableSpecificationArtifactView,
      nextWorkflowState: WorkflowState,
      acceptsSpecificationEdit: false,
      changesSpecificationBusinessContent: false
    }
  | BootstrapAuthorityRefreshStageTransaction {
      transactionId,
      expectedWorkflowStateId,
      expectedWorkflowRevision,
      inputBootstrapAuthorityStateId,
      nextBootstrapAuthorityState: BootstrapAuthorityState,
      changePlan: CompatibleRuntimeOnlyBootstrapChangePlan,
      changeEvidence: MaterializedBootstrapChangeEvidence,
      nextWorkflowState: WorkflowState
    }
  | ClarificationPauseStageTransaction {
      transactionId,
      stage: spec | plan | tasks,
      expectedWorkflowStateId,
      expectedWorkflowRevision,
      authorityBindings: {
        effectiveBootstrapAuthorityStateId,
        workflowArtifactRegistryStateId,
        referenceStateId,
        priorClarificationStateId,
        priorClarificationStateRevision,
        specificationProvenanceStateId?,
        planInputAuthorityStateId?,
        planStateId?,
        taskDefinitionStateId?
      },
      stagedEntries:
        | SpecificationClarificationPauseEntries {
            bootstrapAuthorityMutation: SpecificationClarificationBootstrapAuthorityMutation,
            actorEvidenceRegistryState: ActorEvidenceRegistryState,
            referenceSnapshot: ReferenceSnapshot,
            descendantMutation: ReferenceRevisionDescendantMutation,
            referenceConflictSetTransition?: ReferenceConflictClarificationSetTransition,
            // Required whenever validated P or C is nonempty, or the adopted
            // reference state applies a prior conflict answer.
            passiveLiteralRegistryState,
            featureRequestState?,
            specificationIdLedger?,
            specificationAcknowledgementState?,
            specificationProvenanceState?,
            nextClarificationState: ClarificationRegistryState,
            referenceContextView: GeneratedView,
            clarificationViews: ClarificationView[],
            nextWorkflowState: WorkflowState
          }
        | PlanClarificationPauseEntries {
            bootstrapAuthorityMutation: PlanningStageBootstrapAuthorityMutation,
            actorEvidenceRegistryState: ActorEvidenceRegistryState,
            nextPlanInputAuthorityState: PlanInputAuthorityState,
            nextClarificationState: ClarificationRegistryState,
            clarificationViews: ClarificationView[],
            nextWorkflowState: WorkflowState
          }
        | TasksClarificationPauseEntries {
            bootstrapAuthorityState: BootstrapAuthorityState,
            actorEvidenceRegistryState: ActorEvidenceRegistryState,
            nextClarificationState: ClarificationRegistryState,
            clarificationViews: ClarificationView[],
            nextWorkflowState: WorkflowState
          },
      forbiddenEntries: [SpecificationIR, PlanState, TaskDefinitionState]
    }
  | ClarificationResponseStageTransaction {
      transactionId,
      stage: spec | plan | tasks,
      expectedWorkflowStateId,
      expectedWorkflowRevision,
      expectedClarificationStateId,
      expectedClarificationStateRevision,
      inputActorEvidenceRegistryStateId,
      inputActorEvidenceRegistryStateRevision,
      nextActorEvidenceRegistryState: ActorEvidenceRegistryState,
      nextClarificationState: ClarificationRegistryState,
      nextPassiveLiteralRegistryState?,
      clarificationViews: ClarificationView[],
      nextWorkflowState: WorkflowState
    }
  | ClarificationAuthorityResolutionStageTransaction {
      transactionId,
      stage: spec | plan | tasks,
      expectedWorkflowStateId,
      expectedWorkflowRevision,
      expectedClarificationStateId,
      expectedClarificationStateRevision,
      refreshedAuthorityEntries:
        | SpecificationCurrentReferenceAuthorityRefreshEntries {
            bootstrapAuthorityMutation: SpecificationContractBootstrapAuthorityMutation,
            actorEvidenceRegistryState: ActorEvidenceRegistryState,
            referenceSnapshot: ReferenceSnapshot,
            referenceDisposition: retain_current_reference,
            passiveLiteralRegistryState,
            specificationProvenanceState?
          }
        | SpecificationReferenceRevisionAuthorityRefreshEntries {
            bootstrapAuthorityMutation: ReferenceRevisionBootstrapAuthorityMutation,
            actorEvidenceRegistryState: ActorEvidenceRegistryState,
            referenceSnapshot: ReferenceSnapshot,
            referenceDisposition: adopt_successor_reference,
            descendantMutation: ReferenceRevisionDescendantMutation,
            passiveLiteralRegistryState,
            referenceContextView: GeneratedView,
            forbiddenEntries: [
              FeatureRequestState, SpecificationProvenanceState,
              PlanInputAuthorityState, PlanState, TaskDefinitionState
            ]
          }
        | PlanAuthorityRefreshEntries {
            bootstrapAuthorityMutation: PlanningStageBootstrapAuthorityMutation,
            actorEvidenceRegistryState: ActorEvidenceRegistryState,
            nextPlanInputAuthorityState: PlanInputAuthorityState
          }
        | TasksAuthorityRefreshEntries {
            bootstrapAuthorityState: BootstrapAuthorityState,
            actorEvidenceRegistryState: ActorEvidenceRegistryState
          },
      nextClarificationState: ClarificationRegistryState,
      clarificationViews: ClarificationView[],
      nextWorkflowState: WorkflowState
    }
  | SpecifyCompletionStageTransaction {
      transactionId,
      expectedWorkflowStateId,
      expectedWorkflowRevision,
      bootstrapAuthorityMutation: SpecificationContractBootstrapAuthorityMutation,
      workflowArtifactRegistry: WorkflowArtifactRegistry,
      actorEvidenceRegistryState: ActorEvidenceRegistryState,
      referenceSnapshot: ReferenceSnapshot,
      featureRequestState: FeatureRequestState,
      passiveLiteralRegistryState,
      specificationIdLedger: SpecificationIdLedger,
      specificationAcknowledgementState: SpecificationAcknowledgementState,
      clarificationState: ClarificationRegistryState,
      specificationProvenanceState: SpecificationProvenanceState,
      specification: SpecificationIR,
      specificationView: EditableSpecificationArtifactView,
      referenceContextView: GeneratedView,
      clarificationViews: ClarificationView[],
      nextWorkflowState: WorkflowState
    }
  | PlanInputAuthorityStageTransaction {
      transactionId,
      expectedWorkflowStateId,
      expectedWorkflowRevision,
      bootstrapAuthorityMutation: PlanningStageBootstrapAuthorityMutation,
      actorEvidenceRegistryMutation:
        | UnchangedPlanInputActorRegistry {
            currentActorEvidenceRegistryState: ActorEvidenceRegistryState
          }
        | AppendedPlanInputActorRegistry {
            inputActorEvidenceRegistryStateId,
            inputActorEvidenceRegistryStateRevision,
            nextActorEvidenceRegistryState: ActorEvidenceRegistryState
          },
      specificationMutation: PlanInputSpecificationMutation,
      normalizedSpecification: SpecificationIR,
      specificationView: EditableSpecificationArtifactView,
      specificationIdLedger: SpecificationIdLedger,
      specificationAcknowledgementState: SpecificationAcknowledgementState,
      clarificationState: ClarificationRegistryState,
      specificationProvenanceState: SpecificationProvenanceState,
      passiveLiteralRegistryState: PassiveLiteralRegistryState,
      planInputAuthorityState: PlanInputAuthorityState,
      nextWorkflowState: WorkflowState
    }
  | PlanCandidateStageTransaction {
      transactionId,
      expectedWorkflowStateId,
      expectedWorkflowRevision,
      bootstrapAuthorityState: BootstrapAuthorityState,
      actorEvidenceRegistryState: ActorEvidenceRegistryState,
      normalizedSpecification: SpecificationIR,
      specificationView: EditableSpecificationArtifactView,
      specificationIdLedger: SpecificationIdLedger,
      specificationAcknowledgementState: SpecificationAcknowledgementState,
      clarificationState: ClarificationRegistryState,
      specificationProvenanceState: SpecificationProvenanceState,
      passiveLiteralRegistryState,
      planInputAuthorityState: PlanInputAuthorityState,
      planState: PlanState,
      generatedPlanViews: GeneratedView[],
      clarificationViews: ClarificationView[],
      nextWorkflowState: WorkflowState
    }
  | TasksCandidateStageTransaction {
      transactionId,
      expectedWorkflowStateId,
      expectedWorkflowRevision,
      bootstrapAuthorityState: BootstrapAuthorityState,
      actorEvidenceRegistryState: ActorEvidenceRegistryState,
      clarificationState: ClarificationRegistryState,
      taskDefinitionState: TaskDefinitionState,
      runtimeFileState: RuntimeFileState,
      executionEvidenceRegistry: ExecutionEvidenceRegistryState,
      taskRuntimeState: TaskRuntimeState,
      tasksView: GeneratedView,
      clarificationViews: ClarificationView[],
      nextWorkflowState: WorkflowState
    }
  | ReferenceRevisionStageTransaction {
      transactionId,
      expectedWorkflowStateId,
      expectedWorkflowRevision,
      inputActorEvidenceRegistryStateId,
      inputActorEvidenceRegistryStateRevision,
      bootstrapAuthorityMutation: ReferenceRevisionBootstrapAuthorityMutation,
      referenceSnapshot: ReferenceSnapshot,
      nextActorEvidenceRegistryState: ActorEvidenceRegistryState,
      passiveLiteralRegistryState: PassiveLiteralRegistryState,
      clarificationState: ClarificationRegistryState,
      referenceConflictSetTransition?: ReferenceConflictClarificationSetTransition,
      // Required whenever validated P or C is nonempty, including the
      // zero-open-subject branch after all answers apply.
      clarificationViews: ClarificationView[],
      // Complete registered historical view set. Its open_submission subject
      // projection must equal the successor unresolved-current subject set;
      // the zero-open branch retains closed_audit and preserved_user_closed
      // views. Preserved members are validated, never emitted as file writes.
      descendantMutation: ReferenceRevisionDescendantMutation,
      referenceContextView: GeneratedView,
      nextWorkflowState: WorkflowState
    }
  | ReworkInvalidationStageTransaction {
      transactionId,
      expectedWorkflowStateId,
      expectedWorkflowRevision,
      inputWorkflowControlEventRegistryStateId,
      inputWorkflowControlEventRegistryStateRevision,
      nextWorkflowControlEventRegistryState: WorkflowControlEventRegistryState,
      invalidation: ReworkInvalidationRecord,
      bootstrapAuthorityMutation: ReworkBootstrapAuthorityMutation,
      clarificationState: ClarificationRegistryState,
      actorEvidenceRegistryState: ActorEvidenceRegistryState,
      runtimeMutation:
        | NoImplementationRuntimeMutation { reason: no_committed_task_runtime }
        | ReconcileCommittedRuntimeMutation {
            inputTaskDefinitionStateId,
            inputTaskRuntimeRevision,
            nextTaskRuntimeState: TaskRuntimeState,
            inputExecutionEvidenceRegistryStateId,
            inputExecutionEvidenceRegistryStateRevision,
            nextExecutionEvidenceRegistry: ExecutionEvidenceRegistryState,
            evidenceInvalidation: ExecutionEvidenceInvalidationRecord
          },
      regeneratedViews: GeneratedView[],
      nextWorkflowState: WorkflowState
    }
  | FinalValidationFailedStageTransaction {
      transactionId,
      expectedWorkflowStateId,
      expectedWorkflowRevision,
      inputWorkflowControlEventRegistryStateId,
      inputWorkflowControlEventRegistryStateRevision,
      nextWorkflowControlEventRegistryState: WorkflowControlEventRegistryState,
      finalValidation: FinalValidationRecord,
      inputExecutionEvidenceRegistryStateId,
      inputExecutionEvidenceRegistryStateRevision,
      nextExecutionEvidenceRegistry: ExecutionEvidenceRegistryState,
      unchangedTaskRuntimeRevision,
      tasksView: GeneratedView,
      nextWorkflowState: WorkflowState
    }
  | LocalizedTaskRemediationStageTransaction {
      transactionId,
      expectedWorkflowStateId,
      expectedWorkflowRevision,
      failedFinalValidationRecordId,
      inputWorkflowControlEventRegistryStateId,
      inputWorkflowControlEventRegistryStateRevision,
      nextWorkflowControlEventRegistryState: WorkflowControlEventRegistryState,
      localizedTaskId,
      inputTaskRuntimeRevision,
      nextTaskRuntimeState: TaskRuntimeState,
      inputExecutionEvidenceRegistryStateId,
      inputExecutionEvidenceRegistryStateRevision,
      nextExecutionEvidenceRegistry: ExecutionEvidenceRegistryState,
      evidenceInvalidation: ExecutionEvidenceInvalidationRecord,
      tasksView: GeneratedView,
      nextWorkflowState: WorkflowState
    }
  | ImplementationReconciliationStageTransaction {
      transactionId,
      expectedWorkflowStateId,
      expectedWorkflowRevision,
      inputWorkflowControlEventRegistryStateId,
      inputWorkflowControlEventRegistryStateRevision,
      nextWorkflowControlEventRegistryState: WorkflowControlEventRegistryState,
      invalidation: ReworkInvalidationRecord,
      finalValidation?: FinalValidationRecord,
      inputTaskRuntimeRevision,
      nextTaskRuntimeState: TaskRuntimeState,
      inputExecutionEvidenceRegistryStateId,
      inputExecutionEvidenceRegistryStateRevision,
      nextExecutionEvidenceRegistry: ExecutionEvidenceRegistryState,
      evidenceInvalidation: ExecutionEvidenceInvalidationRecord,
      tasksView: GeneratedView,
      nextWorkflowState: WorkflowState
    }
  | ImplementationCompletionStageTransaction {
      transactionId,
      expectedWorkflowStateId,
      expectedWorkflowRevision,
      inputWorkflowControlEventRegistryStateId,
      inputWorkflowControlEventRegistryStateRevision,
      nextWorkflowControlEventRegistryState: WorkflowControlEventRegistryState,
      finalValidation: FinalValidationRecord,
      nextExecutionEvidenceRegistry: ExecutionEvidenceRegistryState,
      finalRuntimeFileState: RuntimeFileState,
      finalTaskRuntimeState: TaskRuntimeState,
      tasksView: GeneratedView,
      nextWorkflowState: WorkflowState
    }
)

ReviewTransaction = DurableTransactionMember & {
  transactionId,
  expectedWorkflowStateId,
  expectedWorkflowRevision,
  decision: ReviewDecision,
  exactTargetStateId,
  inputActorEvidenceRegistryStateId,
  inputActorEvidenceRegistryStateRevision,
  nextActorEvidenceRegistryState: ActorEvidenceRegistryState,
  inputReviewDecisionRegistryStateId,
  inputReviewDecisionRegistryStateRevision,
  nextReviewDecisionRegistryState: ReviewDecisionRegistryState,
  nextWorkflowState: WorkflowState,
  singleUse: true
}

FileOperationProposal {
  taskId,
  operationIntentId,
  operation: FileOperationPayload,
  explanation: SemanticText,
  completionSummary?: SemanticText
}
```

---

<a id="diagnostic-contract"></a>

## 13. Diagnostic contract

```text
SemanticAuthorityCitationProposal {
  authorityId,                 // must be in the request-local citation allowlist
  recordId?,
  sourceSpan?
}

SemanticFindingProposal {
  findingTargetKey,            // request-owned unit-pointer key, not a raw pointer
  findingKind: ambiguity | testability_gap | unsupported_behavior |
               semantic_conflict | nonminimal_design | task_sizing |
               intent_conformance_gap,
  finding: SemanticText,
  citations: SemanticAuthorityCitationProposal[],
  reportedConfidence?
  // No finding ID, evidence class, state revision, model-operation/slot metadata,
  // disposition, repair class, severity, or canonical unit pointer.
}

SemanticReviewOperationResult {
  kind: findings,
  findings: SemanticFindingProposal[]
}

SemanticFinding {
  semanticFindingId: { modelRequestId, findingOrdinal },
  evidenceClass: model_assisted,
  stage,
  unitTypeId,
  immutableUnitOwnerId: SemanticReviewOwner,
  unitPointer,
  findingKind: ambiguity | testability_gap | unsupported_behavior |
               semantic_conflict | nonminimal_design | task_sizing |
               intent_conformance_gap,
  finding: SemanticText,
  citedAuthorities: {
    authorityKind,
    authorityStateId,
    authorityStateRevision?,
    recordId?,
    sourceSpan?
  }[],
  modelExchange: {
    compiledWorkflowAuthorityId,
    modelOperationId,
    requestId,
    resultSchemaResourceId,
    modelSlotId
  },
  confidencePolicyId,
  reportedConfidence?,
  configuredDisposition: warn | block_for_user | allow_atomic_model_repair
}

Diagnostic {
  id,                         // unique within the run
  code,                       // stable machine code
  severity: info | warning | error | fatal,
  stage,
  nodeId,
  artifactKind?,
  location: json-pointer | markdown-node | project-path | source-location,
  message,
  expected?,
  actual?,
  evidence:
    | { class: deterministic,
        rule: { source, ruleId, description }, evidenceIds[] }
    | { class: model_assisted, semanticFinding: SemanticFinding },
  repairClass: canonicalize | model_atomic | user_input | environment | not_repairable,
  repairUnit?,
  relatedLocations[],
  validatorDependencies[]
}
```

---

<a id="engine-configuration"></a>

## 14. Engine configuration

The runtime captures and canonicalizes the native executable's invocation
working directory once and treats it as the project root. It resolves only the
exact `<projectRoot>/.sddtoolkit.json` child and never searches an ancestor or
descendant. Failure to safely and completely read it returns
`ENGINE_CONFIG_READ_ERROR`; failure to decode its bytes as the exact closed
contract returns `ENGINE_CONFIG_PARSE_ERROR`. Either terminates with a nonzero
exit before workflow work. The runtime config is
accepted only up to the compiler-owned
`maxEngineConfigBytes = 1,048,576` (1 MiB) limit, enforced from file metadata
and again during the read. The repository file
`design/schemas/sddtoolkit-config.schema.json` defines F0001's current closed
reader-facing shape, and `design/examples/.sddtoolkit.json` is one accepted
instance. Neither is a runtime fallback. The larger document below illustrates
a proposed future engine-policy extension; only its `logs` member is kept
identical to the accepted `LogsConfig`. F0001 does not accept its other extra
top-level members, infer missing fields, or provide a compatibility reader. A
missing exact filename blocks invocation. Every configured location is
supplied by the decoded eight-key `paths` object and must then be validated by
the path-policy owner. The configured
`specs`, `references`, `specsArchive`, `workflows`, `toolchainPreset`,
`principles`, and `templates` directory roots plus the `providers`
`.sddproviders.json` file are distinct authorities; only `specsArchive` may be
nested beneath `specs`. No action may substitute a different root, fixed
provider filename, `.specify/`, source-tree, or example path.

`paths.workflows` is the workflow-authority root. It contains an arbitrary
bounded number of closed declarative workflow definitions plus the exact
reserved engine-owned child `features/`. Each definition
has a unique validated `WorkflowId` and logging shortcode and describes graph
topology only through the single registry's generic operation IDs, closed
parameters, declared resources, and typed transitions. It cannot contain
executable code, select infrastructure, provide raw paths/commands, grant a
capability, weaken a registered gate, bypass runner validation, or collide with
a reserved child.
The initial `specify`, `plan`, `tasks`, and `implement` definitions preserve
their order through their own predecessor gates; the generic engine does not
hard-code that sequence. Toolchain presets load directly from
`paths.toolchainPreset`. The exact
`<paths.principles>/toolchain.yaml` is a closed mechanical project toolchain
layer that inherits registered presets; it is accounted for but excluded from
free-text principle decoding and chunking. `paths.templates` is inert during
ordinary bootstrap. Only an explicit `sdd init` workflow may copy selected
principle templates into `paths.principles` under its separately validated init
transaction, after which the copied files are ordinary project principle
sources and receive no automatic placeholder expansion.

```text
<projectRoot>/
├── .sddtoolkit.json
├── .sddproviders.json                   # paths.providers in this example
├── specs/                              # paths.specs in this example
│   └── _archive/                       # paths.specsArchive; sole nesting exception
├── references/                         # paths.references
└── .sddtoolkit/                        # an unconfigured common parent only
    ├── workflows/                      # paths.workflows
    │   ├── <declarative workflow definitions>
    │   └── features/                   # exact reserved engine-owned child
    ├── toolchainPreset/                # paths.toolchainPreset; preset packages
    ├── principles/                     # paths.principles
    │   ├── toolchain.yaml              # closed mechanical project layer
    │   └── *.md                        # free-text principle sources
    └── templates/                      # paths.templates; inert until sdd init
        └── *.template.md
```

`design/templates/` and `design/toolchainPresets/` are source/design material.
`design/schemas/sddtoolkit-config.schema.json` and
`design/examples/.sddtoolkit.json` are the reader-facing schema and example.
None of these design assets is searched, packaged as runtime authority, or
copied implicitly by ordinary bootstrap.

The following extended policy document is illustrative and is not the current
F0001 input contract. Its `models.slots` member nevertheless follows the current
authority split: slots are repository-allowed exact provider/model references,
and every referenced tuple must exist in the separately configured
`.sddproviders.json` catalogue:

```json
{
  "rendererContractVersion": "renderer/v1",
  "paths": {
    "specs": "specs/",
    "references": "references/",
    "specsArchive": "specs/_archive/",
    "workflows": ".sddtoolkit/workflows",
    "toolchainPreset": ".sddtoolkit/toolchainPreset",
    "principles": ".sddtoolkit/principles",
    "templates": ".sddtoolkit/templates",
    "providers": ".sddproviders.json"
  },
  "environments": [
    {
      "id": "web",
      "root": ".",
      "targetPlatforms": ["linux-posix", "windows-ntfs"]
    }
  ],
  "toolchainPresets": {
    "schemaRegistryVersion": "toolchain-presets/v1",
    "legacyDocumentPolicy": "reject",
    "maxFiles": 1000,
    "maxFileBytes": 1048576,
    "maxTotalBytes": 52428800
  },
  "principles": {
    "maxFiles": 100,
    "maxFileBytes": 1048576,
    "maxTotalBytes": 10485760,
    "unknownFilenameCategory": "custom",
    "categoryFilenameHints": [
      { "category": "core", "basenames": ["core", "core.template"] },
      { "category": "architecture", "basenames": ["architecture", "architecture.template"] },
      { "category": "project_structure", "basenames": ["project-structure", "project-structure.template"] },
      { "category": "security", "basenames": ["security", "security.template"] },
      { "category": "validation", "basenames": ["validation", "validation.template"] },
      { "category": "observability", "basenames": ["observability", "observability.template"] },
      { "category": "user_interface", "basenames": ["user-interface", "user-interface.template"] }
    ],
    "stageCategoryHints": {
      "plan": ["core", "architecture", "project_structure", "security", "validation", "observability", "user_interface", "custom"],
      "tasks": ["core", "architecture", "project_structure", "security", "validation", "observability", "user_interface", "custom"],
      "implement": ["core", "architecture", "project_structure", "security", "validation", "observability", "user_interface", "custom"]
    }
  },
  "dependencyPolicy": {
    "registrySources": [
      {
        "registrySourceId": "npm.public",
        "ecosystem": "npm",
        "canonicalBaseUri": "https://registry.npmjs.org/",
        "trustPolicyId": "registry-tls-public/v1",
        "allowPrerelease": false
      }
    ],
    "ecosystems": [
      {
        "ecosystem": "npm",
        "packageNameGrammarId": "npm-package-name/v1",
        "versionConstraintGrammarId": "npm-semver-range/v1",
        "allowedScopes": ["dependencies", "devDependencies", "peerDependencies"],
        "allowedRegistrySourceIds": ["npm.public"],
        "denyPackageRules": []
      }
    ]
  },
  "models": {
    "slots": {
      "audit_analysis": { "provider": "openai", "model": "gpt-5-nano" },
      "drift_analysis": { "provider": "openai", "model": "gpt-5-nano" },
      "spec_generation": { "provider": "openai", "model": "gpt-5-nano", "reasoningEffort": "low" },
      "design_section_generation": { "provider": "openai", "model": "gpt-5.4-nano" },
      "implementation": { "provider": "openai", "model": "gpt-5.4-mini" }
    }
  },
  "workflow": {
    "requireOrderedStages": true,
    "standaloneStageRequiresFeatureId": true,
    "maxContextRequestsPerCall": 1,
    "defaultTaskConcurrency": 1,
    "allowRawPathFallback": false
  },
  "review": {
    "requirePlanApproval": true,
    "requireTasksApproval": true,
    "generatedViewsReadOnly": true,
    "rejectionRequiresFeedback": true
  },
  "references": {
    "recursive": true,
    "followSymlinks": false,
    "maxEntries": 10000,
    "maxDirectoryDepth": 32,
    "enumerationTimeoutMs": 10000,
    "enumerationMemoryBytes": 134217728,
    "maxFileBytes": 10485760,
    "maxTotalBytes": 104857600,
    "maxDecodedBytesPerFile": 52428800,
    "maxDecodedBytesTotal": 268435456,
    "maxBlocksPerFile": 100000,
    "maxPagesPerDocument": 2000,
    "maxCellsPerTableFile": 1000000,
    "decoderTimeoutMs": 30000,
    "decoderMemoryBytes": 536870912,
    "maxArchiveDepth": 3,
    "maxArchiveEntries": 1000,
    "maxArchiveExpansionRatio": "20.0",
    "unsupportedFormat": "block",
    "encryptedFile": "block",
    "hiddenFiles": "exclude",
    "exclusionRules": [
      {
        "id": "reference.hidden.configured",
        "selector": "hidden-entry",
        "acceptance": "configuration-policy"
      },
      {
        "id": "reference.symlink.nonfollow",
        "selector": "non-followed-symlink",
        "acceptance": "configuration-policy"
      }
    ],
    "readers": [
      "builtin/text@1.0.0",
      "builtin/markdown@1.0.0",
      "builtin/json@1.0.0",
      "builtin/yaml@1.0.0",
      "builtin/xml@1.0.0",
      "builtin/csv@1.0.0",
      "builtin/css@1.0.0",
      "builtin/source@1.0.0",
      "builtin/pdf@1.0.0",
      "builtin/image@1.0.0",
      "builtin/office@1.0.0"
    ]
  },
  "repositoryDiscovery": {
    "maxFiles": 200000,
    "maxDirectoryDepth": 64,
    "enumerationTimeoutMs": 30000,
    "enumerationMemoryBytes": 268435456
  },
  "validation": {
    "failSeverity": "error",
    "rejectUnresolvedPlaceholders": true,
    "rejectForeignAbsolutePaths": true,
    "requireFullRequirementCoverage": true,
    "allowManualVerification": true,
    "lockedValidators": [
      "path.containment",
      "path.symlink",
      "response.schema",
      "command.allowlist",
      "stage.order"
    ]
  },
  "execution": {
    "shell": false,
    "allowDelete": false,
    "allowNetworkCommands": false,
    "atomicArtifactWrites": true,
    "taskWorkspace": "overlay",
    "commandOutputLimitBytes": 1048576,
    "commandSandbox": {
      "required": true,
      "filesystemNamespace": true,
      "processTreeConfinement": true,
      "networkNamespace": true,
      "resourceQuotas": {
        "maxCreatedEntries": 100000,
        "maxBytesWritten": 1073741824,
        "maxCurrentDeltaBytes": 536870912,
        "maxFileBytes": 268435456,
        "maxPrivateTempBytes": 536870912
      }
    }
  },
  "state": {
    "persistStageStatus": true,
    "resume": true,
    "useFingerprints": false
  },
  "logs": {
    "level": "debug",
    "console": true,
    "promptCapture": []
  }
}
```

The complementary project layer at the exact
`<paths.principles>/toolchain.yaml` path is parsed as YAML 1.2 through a
versioned closed schema. This illustrative decoded shape moves preset
inheritance out of the root-path map while retaining environment ownership:

```yaml
schemaVersion: project-toolchain/v1
environmentBindings:
  - environmentId: web
    inherits:
      - language/typescript@1.0.0
      - runtime/node@1.0.0
      - framework/react@1.0.0
      - build/vite@1.0.0
    overrides: {}
```

Every inherited ID must resolve in the registry loaded from
`paths.toolchainPreset`. Unknown fields, unknown environments or presets,
cycles, duplicate layers, and attempts to weaken locked policy reject
bootstrap. This file supplies mechanical configuration only and contributes no
`PrincipleModule`, `PrincipleChunk`, or model guidance.

---

<a id="preset-identity-and-composition"></a>

## 15. Preset identity and composition

```yaml
apiVersion: sddtoolkit.dev/v1
kind: EnvironmentPreset

metadata:
  id: react-typescript-vite
  version: 1.0.0
  layer: environment
  displayName: React + TypeScript + Vite
  description: Browser application built with React, TypeScript, and Vite

extends:
  - language/typescript@1.0.0
  - runtime/node@1.0.0
  - framework/react@1.0.0
  - build/vite@1.0.0

detection:
  required:
    - adapter: json-field
      path: { ruleId: detect.react.package, base: environment, target: relative_path, patternType: exact, value: package.json, caseSensitive: true }
      pointer: /dependencies/react
  ambiguity: error
```

---

<a id="project-discovery-policy"></a>

## 16. Project discovery policy

```yaml
projectDiscovery:
  adapters: [npm-package-json, npm-workspaces]
  manifestPatterns:
    - { ruleId: discover.npm.manifest, base: environment, target: relative_path, patternType: glob, value: '**/package.json', caseSensitive: true }
  exclude:
    - { ruleId: discover.exclude.git, base: environment, target: relative_path, patternType: glob, value: '**/.git/**', caseSensitive: true }
    - { ruleId: discover.exclude.node-modules, base: environment, target: relative_path, patternType: glob, value: '**/node_modules/**', caseSensitive: true }
    - { ruleId: discover.exclude.dist, base: environment, target: relative_path, patternType: glob, value: '**/dist/**', caseSensitive: true }
  selection: explicit-or-nearest-owner
```

The compiler injects engine-reserved discovery exclusions from all seven exact
directory capabilities plus the exact provider-document file capability in the
`BootstrapRootRegistry` before merging these preset-owned rules.
The locked rules use the resolved configured paths rather than assuming a
literal `.sddtoolkit` directory. The `specsArchive` rule remains explicit even
when its authorized nesting beneath `specs` makes it physically redundant.
No preset can remove, shadow, or override these exclusions.

---

<a id="file-kind-policies"></a>

## 17. File-kind policies

```yaml
fileKinds:
  reactComponent:
    inferencePriority: 200
    plannedIntents: [read, create, update]
    capabilities: [read, create, patch, replace, copy_destination]
    copyDestination: { create: allowed, overwrite: forbidden }
    contentLimits: { modelCompleteFileBytes: 8192, copiedSourceBytes: 1048576 }
    contentReferencePolicy:
      extractorIds: [typescript-imports@1, jsx-resource-links@1]
      fallbackScannerId: conservative-path-token-scan@1
      resolverId: typescript-vite-resolution@1
      requireCompleteCoverage: true
    namingEnforcement: { create: strict, update: existing_compatible }
    roots:
      - ruleId: react-component.root
        base: project
        target: relative_path
        patternType: glob
        value: 'src/components/**'
        caseSensitive: true
    names:
      - ruleId: react-component.basename
        base: project
        target: basename
        patternType: regex
        value: '^[A-Z][A-Za-z0-9]*\.tsx$'
        caseSensitive: true
    extensions: [.tsx]
    extensionRuleId: react-component.extensions
    extensionCaseSensitive: true
    pathTemplates:
      - pathTemplateId: react-component.from-business-name
        pathIntentOptionRuleId: react-component.create-ui-component
        semanticRoleId: ui-component
        directoryStrategy: { kind: fixed, repoRelativeDirectory: 'src/components' }
        nameTransformId: path-name/pascal-case@1
        basenamePrefix: ''
        basenameSuffix: ''
        extension: '.tsx'
    generated: false

  unitTest:
    inferencePriority: 300
    plannedIntents: [read, create, update]
    capabilities: [read, create, patch, replace, copy_destination]
    copyDestination: { create: allowed, overwrite: forbidden }
    contentLimits: { modelCompleteFileBytes: 8192, copiedSourceBytes: 1048576 }
    contentReferencePolicy:
      extractorIds: [typescript-imports@1, jsx-resource-links@1]
      fallbackScannerId: conservative-path-token-scan@1
      resolverId: typescript-vite-resolution@1
      requireCompleteCoverage: true
    namingEnforcement: { create: strict, update: existing_compatible }
    roots:
      - ruleId: unit-test.root
        base: project
        target: relative_path
        patternType: glob
        value: 'src/**'
        caseSensitive: true
    names:
      - ruleId: unit-test.basename
        base: project
        target: basename
        patternType: glob
        value: '*.test.tsx'
        caseSensitive: true
    extensions: [.test.tsx]
    extensionRuleId: unit-test.extensions
    extensionCaseSensitive: true
    pathTemplates:
      - pathTemplateId: unit-test.colocated-with-source
        pathIntentOptionRuleId: unit-test.create-colocated
        semanticRoleId: unit-test
        directoryStrategy: { kind: colocated_with_anchor }
        nameTransformId: path-name/exact-identifier@1
        basenamePrefix: ''
        basenameSuffix: '.test'
        extension: '.tsx'
    placement:
      mode: co-located
      sourceKinds: [reactComponent]

  config:
    inferencePriority: 100
    plannedIntents: [read, update]
    capabilities: [read, patch, replace]
    contentLimits: { modelCompleteFileBytes: 4096, copiedSourceBytes: 0 }
    contentReferencePolicy:
      extractorIds: [ecmascript-imports@1, ecmascript-static-path-literals@1]
      fallbackScannerId: conservative-path-token-scan@1
      resolverId: node-config-resolution@1
      requireCompleteCoverage: true
    namingEnforcement: { update: strict }
    roots:
      - ruleId: vite-config.root
        base: project
        target: relative_path
        patternType: glob
        value: '*'
        caseSensitive: true
    names:
      - ruleId: vite-config.basename
        base: project
        target: basename
        patternType: glob
        value: 'vite.config.*'
        caseSensitive: true
    extensions: [.ts, .js, .mts, .mjs, .cts, .cjs]
    extensionRuleId: vite-config.extensions
    extensionCaseSensitive: true
```

---

<a id="structured-commands"></a>

## 18. Structured commands

```yaml
commands:
  build:
    capability: build
    executable: npm
    args: [run, build]
    cwd: '${projectRoot}'
    timeoutMs: 120000
    successExitCodes: [0]
    mutability: workspaceWrite
    placeholders:
      projectRoot: { type: containedDirectory, source: owningProjectRoot }
    effects:
      authorizedWrites: []
      ephemeralWrites:
        - { ruleId: command.build.ephemeral.dist, base: command_cwd, target: relative_path, patternType: glob, value: 'dist/**', caseSensitive: true }
    network: forbidden

  unitFile:
    capability: unit-test-file
    executable: npm
    args: [run, test, --, '${testFile}']
    cwd: '${projectRoot}'
    timeoutMs: 120000
    successExitCodes: [0]
    mutability: workspaceWrite
    placeholders:
      projectRoot: { type: containedDirectory, source: owningProjectRoot }
      testFile: { type: validatedFileIdPath, allowedKinds: [unitTest] }
    effects:
      authorizedWrites: []
      ephemeralWrites:
        - { ruleId: command.test.ephemeral.coverage, base: command_cwd, target: relative_path, patternType: glob, value: 'coverage/**', caseSensitive: true }
        - { ruleId: command.test.ephemeral.cache, base: command_cwd, target: relative_path, patternType: glob, value: '.cache/**', caseSensitive: true }
    network: forbidden
```

---

<a id="ast-and-parser-policy"></a>

## 19. AST and parser policy

```yaml
languages:
  - id: typescriptReact
    extensions: [.tsx]
    parser:
      adapter: tree-sitter
      grammar: typescript-tsx
      version: 1
    queries:
      imports:
        resource: queries/typescript/imports.scm
        requiredCaptures: [specifier]
      declarations:
        resource: queries/typescript/declarations.scm
        requiredCaptures: [name, kind]
    moduleResolution:
      adapter: typescript
      configPatterns:
        - { ruleId: typescript-react.config.discovery, base: project, target: relative_path, patternType: glob, value: 'tsconfig*.json', caseSensitive: true }

  - id: typescriptConfig
    extensions: [.ts, .mts, .cts]
    parser:
      adapter: tree-sitter
      grammar: typescript
      version: 1
    queries:
      imports:
        resource: queries/typescript/imports.scm
        requiredCaptures: [specifier]
      staticPathLiterals:
        resource: queries/ecmascript/static-path-literals.scm
        requiredCaptures: [literal, context]
    moduleResolution:
      adapter: typescript
      configPatterns:
        - { ruleId: typescript-config.config.discovery, base: project, target: relative_path, patternType: glob, value: 'tsconfig*.json', caseSensitive: true }

  - id: javascriptConfig
    extensions: [.js, .mjs, .cjs]
    parser:
      adapter: tree-sitter
      grammar: javascript
      version: 1
    queries:
      imports:
        resource: queries/javascript/imports.scm
        requiredCaptures: [specifier]
      staticPathLiterals:
        resource: queries/ecmascript/static-path-literals.scm
        requiredCaptures: [literal, context]
    moduleResolution:
      adapter: node-vite
      manifestPatterns:
        - { ruleId: javascript.manifest.discovery, base: project, target: basename, patternType: exact, value: 'package.json', caseSensitive: true }
```

---

<a id="generated-and-forbidden-paths"></a>

## 20. Generated and forbidden paths

```yaml
forbiddenPaths:
  - { ruleId: root.forbidden.git, base: workspace, target: relative_path, patternType: glob, value: '.git/**', caseSensitive: true }
  - { ruleId: root.forbidden.node-modules, base: project, target: relative_path, patternType: glob, value: 'node_modules/**', caseSensitive: true }

generatedPaths:
  - { ruleId: root.generated.dist, base: project, target: relative_path, patternType: glob, value: 'dist/**', caseSensitive: true }
  - { ruleId: root.generated.coverage, base: project, target: relative_path, patternType: glob, value: 'coverage/**', caseSensitive: true }
```

`forbiddenPaths` above is only the preset-owned portion. The compiler always
injects a higher-precedence `ReservedEngineRootPathPolicy` from the seven exact
directory capabilities, the exact provider-document file capability, and the
engine-derived `features/` child beneath
`paths.workflows`. Presets cannot override
that policy, and neither a model nor a preset supplies its path text.

---

<a id="initial-guidance-packet"></a>

## 21. Initial guidance packet

```text
GuidancePacket {
  objective,
  unit: { kind, id, allowedScope },
  immutableFacts[],
  sourceExcerpts[],
  requirementIds[],
  principleGuidance?: PrincipleGuidance,
  mechanicalGuidance: MechanicalGuidance[],
  prohibitedAssumptions[],
  responseSchema,
  oneMinimalValidExample
}

PrincipleGuidance {
  principleRegistryStateId,
  principleRegistryStateRevision,
  principleSelectionId,
  entries: {
    principleChunkId,
    categoryHint: PrincipleCategoryHint,
    sourceSpan: PrincipleSourceSpan,
    rawUtf8BytesHandle,
    byteLength
  }[],
  completeSelection: true,
  semanticOnly: true,
  grantsOperationalAuthority: false
}

MechanicalGuidance =
  | PathIntentGuidance {
      fieldPointer,
      compiledEnginePolicyStateId,
      planUnitId,
      allowedOptions: {
        pathIntentOptionId,
        displayLabel,
        allowedNameSourceIds[],
        allowedPlacementAnchorFileIds[],
        capabilityCeiling[]
      }[],
      complete: true
    }
  | PathCandidateSelectionGuidance {
      fieldPointer,
      pathCandidateRegistryStateId,
      allowedCandidates: {
        pathCandidateId,
        displayPath,
        fileKindId,
        permittedCapabilities[]
      }[],
      complete: true
    }
  | PathGuidance {                    // explicit raw-path fallback only
      fieldPointer,
      applicableRuleIds[],
      environmentId,
      projectId,
      declaredIntent: read | create | update | delete,
      permittedCapabilities[],
      allowedFileKinds: {
        kindId,
        namingEnforcement,
        roots: PathPattern[],
        includes: PathPattern[],
        excludes: PathPattern[],
        basenames: PathPattern[],
        compoundExtensions[],
        extensionRuleId?,
        extensionCaseSensitive,
        placementRule?,
        contentLimits?
      }[],
      patternContract: { id: path-pattern/v1, fullTargetMatch: true, regexDialect: RE2 },
      filesystemPolicies: {
        policyId,
        activeWorkspacePolicy: boolean,
        unicodeNormalization,
        caseRule,
        forbiddenCharacters[],
        reservedBasenames[],
        maxSegmentLength,
        maxRelativePathLength,
        maxAbsolutePathLength?,
        canonicalAbsoluteBaseLength?
      }[],                       // configured targets plus active host
      inaccessibleRoots: PathPattern[],
      generatedReadOnlyRoots: PathPattern[],
      completeWithinOperationBudget: true
    }
  | PassiveLiteralGuidance {
      fieldPointers[],
      allowedLiterals: {
        passiveLiteralId,
        kind: PassiveLiteralKind,
        displayValue,
        nonOperational: true
      }[],
      operationalAlternatives: {
        allowedFileIds[], allowedSourceIds[]
      },
      diagnostics: {
        inline: UNBOUND_PATH_REFERENCE,
        unknown: PASSIVE_LITERAL_UNKNOWN,
        stale: PASSIVE_LITERAL_STALE,
        crossUnit: PASSIVE_LITERAL_NOT_ALLOWED,
        operationalUse: PASSIVE_LITERAL_OPERATIONAL_USE_FORBIDDEN
      }
    }
  | DependencyGuidance {
      targetProjectIds[],
      targetManifestFileIdsByProject,
      ecosystems: {
        ecosystem,
        packageNameGrammarId,
        versionConstraintGrammarId,
        allowedScopes[],
        allowedRegistrySourceIds[],
        denyRuleIds[]
      }[]
    }
  | CommandGuidance { availableCommandIds[], typedArgumentSchemaIds[] }
  | IdentifierGuidance { namespaceId, allowedIds[] }
  | ContentGuidance { applicableRuleIds[], byteLimit, tokenLimit, requiredValidatorIds[] }
```

---

<a id="model-response-envelope"></a>

## 22. Model response envelope

Under [ADR 0006](decisions/0006-minimal-model-response.md), the model returns
only the closed result object. `model-envelope/v1` and the exact request,
attempt, workflow/unit, binding and result-schema identities stay with the
runner's immutable invocation context; they are not echoed by the model.

For a schema allowing only a task-edge proposal:

```json
{
  "predecessorInternalKey": "verify-login",
  "successorInternalKey": "implement-login",
  "reason": {
    "nodes": [
      {
        "kind": "literal",
        "value": "Implementation must make the intended-red verification pass."
      }
    ]
  }
}
```

The selected task keys and typed reason are meaningful candidate data and
remain. A schema permitting alternative results adds one root `kind` to
distinguish them; it does not add another wrapper. Exact field schemas remain
workflow-declared and bounded. The example defines no built-in model route.

---

<a id="model-context-request"></a>

## 23. Model context request

For an operation whose declared alternatives include this excerpt request,
one discriminator selects the allowed context-result variant. The excerpt
schema is already bound by the engine; there is no echoed `schemaId` or outer
`needs-context` wrapper. The request grants no read authority by itself.

```json
{
  "kind": "authorized-file-excerpt",
  "fileId": "file-17",
  "selector": {
    "kind": "exported-symbol-signature",
    "symbolId": "symbol-4"
  },
  "reasonCode": "NEED_EXPORTED_SIGNATURE"
}
```

---

<a id="orchestrator-composition"></a>

## 24. Orchestrator composition

```text
PipelineRunner
├── WorkflowEngineOrchestrator (capability-free graph coordination)
│   ├── BootstrapOrchestrator preselection portion through a runner-owned child binding
│   │   ├── configuration/root actions
│   │   ├── workflow inventory/capture/parse/schema actions
│   │   ├── workflow graph compile/validate actions
│   │   └── variable-size workflow registry actions; no feature transaction lock
│   ├── ParseWorkflowSelectionAction and ValidateWorkflowIdAction through runner-owned child bindings
│   ├── ResolveSelectedWorkflowAction through a runner-owned child binding
│   └── Selected CompiledWorkflowGraph
│       ├── YAML-named invocation operation through a runner-owned binding
│       │   └── parser/validator child bindings when that contract composes them
│       ├── selected-graph target-context setup binding when required
│       │   ├── feature-ownership validation and feature-local recovery
│       │   ├── toolchain-preset registry/compilation actions
│       │   ├── free-text principles ingestion/indexing actions
│       │   └── repository discovery actions
│       └── follow typed transitions; each YAML-selected operation uses a runner-owned binding
└── FeatureLoggingOrchestrator (runner observer; instrumentation-internal)
    ├── severity/field projection actions
    ├── threshold/redaction/safety actions
    ├── sequence/serialize/rotate/append actions
    └── FeatureLoggingFailureOrchestrator
        ├── transient-handle destruction action
        ├── one emergency-record action
        ├── TransactionRecoveryOrchestrator (only for prepared/applying work)
        │   ├── ReadTransactionRecoveryStateAction
        │   ├── RestoreTransactionEntryAction per uncommitted entry, reverse order
        │   └── VerifyCommittedTransactionEntryAction per committed entry, forward order
        └── fail-closed runner-control action

Project workflow graphs are not registered in source. The compiler constructs
each graph solely from one validated workflow YAML definition:

CompiledWorkflowGraph (one selected project definition)
├── invocation contract named by `invoke`
├── workflow policy named by `policy`
├── immutable resources explicitly named by `resources`
└── steps beginning at `start`
    └── each step calls the registered generic operation named by `use`
        ├── closed parameters from `with`
        └── every typed outcome transition from `on`

The runner follows only this compiled graph. No workflow name selects a hidden
orchestrator, route, prompt, schema, model slot, repair path, or completion rule.
Engine-kernel loading, validation, capability enforcement, delta application,
cancellation, cleanup, and security remain fixed and cannot be called or
bypassed by YAML.
```

---

<a id="bootstrap-flow"></a>

## 25. Bootstrap flow

```text
Capture the invocation working directory as project root and resolve only its
exact .sddtoolkit.json child; any location/read failure returns
ENGINE_CONFIG_READ_ERROR without searching an ancestor or descendant
  -> read that exact no-follow file under the internal 1 MiB guard
  -> directly decode it, with any JSON/version/shape failure returning
     ENGINE_CONFIG_PARSE_ERROR, into one immutable SDDToolKitConfig
  -> resolve/validate seven directory roots and paths.providers against that project root
  -> prove configured-location separation, allowing only paths.specsArchive beneath paths.specs
     and requiring providers to name a distinct `.sddproviders.json` file
  -> build/validate BootstrapRootRegistry before any engine-derived child exists
  -> derive/validate the paths.workflows authority layout and reserve its exact
     engine-owned features/ child; inventory its root entry when present but
     never traverse its reserved descendant subtree
  -> bounded no-follow workflow-authority enumeration -> normalize every in-scope
     path -> reject the complete collision set -> sort -> bind inventory ordinals
  -> classify every entry -> capture/parse/validate definition candidates ->
     build and validate exactly one terminal account for every inventory ordinal
  -> compile every definition from a registered invocation-contract PipelineNode,
     generic operation, outcome, gate, and workflow-policy contracts
  -> prove arbitrary bounded definition cardinality, unique WorkflowIds,
     logging shortcodes, and source ordinals, plus graph/transition closure
  -> prove definitions contain no executable payload or infrastructure selector,
     cannot add a capability, weaken a registered gate, bypass runner validation,
     or claim reserved-child ownership
  -> build/validate the identity-free WorkflowDefinitionRegistryState candidate;
     assign its owner-local component ID only in the generic bootstrap materialization phase
  -> return the complete validated workflow registry to WorkflowEngineOrchestrator
     without acquiring a feature transaction lock;
     ParseWorkflowSelectionAction, ValidateWorkflowIdAction and
     ResolveSelectedWorkflowAction run outside bootstrap
  -> only when the selected graph references the registered target-context
     setup, invoke that portion after its invocation operation produces
     validated workflow context; unrelated workflows do not inherit this branch
  -> for the initial SDD graphs, read/validate feature ownership and inventory
     directly; validate existing activation before feature-local recovery;
     no project transaction collection, ledger, or lock is required
  -> bounded inventory/capture of the direct paths.toolchainPreset root
  -> classify every resource -> reject legacy -> parse/validate closed v1 presets
  -> assign/build/validate ToolchainPresetRegistryState
  -> capture exact no-follow <paths.principles>/toolchain.yaml
  -> parse it as YAML 1.2 through its closed mechanical schema -> resolve every
     exact inherited preset ID/version against ToolchainPresetRegistryState
  -> build and validate the identity-free project toolchain layer
  -> detect and resolve the active workspace filesystem policy
  -> resolve every target-platform/filesystem policy ID
  -> select every inherited preset and validate every declared project override
  -> validate preset graph -> stable dependency-first topological order
  -> merge preset set while retaining preset source-root path-pattern templates
  -> validate environment roots -> enumerate/parse contained project manifests
  -> assemble project registry and manifest/dependency/VCS facts
  -> resolve source-root selectors -> materialize bound patterns
  -> build and validate final compiled environment policies
  -> build and validate the immutable root-access registry
  -> perform bounded project-file discovery under that registry
  -> build repository fact registry and validate configured environments
  -> build and validate the identity-free base superset path-token-grammar blueprint;
     generic environment/repository/root dependencies remain typed run-local references
  -> validate dependency registry sources and resolve package/version grammars
  -> compile deny rules -> build and validate DependencyPolicyRegistry
  -> enumerate/capture/decode bounded normalized *.md files under paths.principles,
     assigning exact toolchain.yaml its mechanical-layer exclusion disposition and
     rejecting every other unclassified regular file
  -> classify category hints from filenames -> partition transport chunks
  -> assign/build/validate PrincipleRegistryState without interpreting prose as policy
  -> leave paths.templates unread and inert during ordinary bootstrap
  -> validate parser/query resources
  -> for each command: validate cwd -> resolve executable -> validate typed placeholders
       -> validate mutability/alias semantics -> compile/check effect policies
       -> validate sandbox/path/quota capability -> probe named project capability
  -> assemble only fully proven command capabilities
  -> create or load run metadata
  -> build/validate the identity-free CompiledEnginePolicy blueprint over leaf and
     base-grammar candidate references
  -> assemble/validate the noncanonical BootstrapOperationalCandidate and, for an
     existing feature, compare/classify/route by canonical-ID-erased component values
  -> only inside activation or the selected owning transaction: assign the prospective
     BootstrapAuthorityState/component IDs -> materialize/validate every leaf candidate
     -> build/validate the leaf_dependencies resolution map
     -> build/validate the canonical base grammar -> bind its aggregate handle
     -> build/validate the base_grammar_resolved map
     -> assemble/validate CompiledEnginePolicy -> bind its aggregate handle
  -> build/validate the complete map with no unresolved generic handle, then build/validate/serialize
     BootstrapAuthorityState transaction-privately
  -> expose only the validated policy
```

---

<a id="reference-reader-contract"></a>

## 26. Reference reader contract

```text
port ReferenceReader {
  id
  version
  supportedMediaTypes
  mediaTypeRanksByType       // bounded integer per supported media type
  minimumProbeScore          // integer 0..1000
  priority                   // bounded integer
  role: primary | fallback
  probe(sourceBlob, boundedBytesPrefix) -> integer 0..1000
  decode(sourceBlob, boundedImmutableStream, decoderBudget) -> DecodedReferenceProposal
}

DecodedReferenceProposal {
  sourceId,
  mediaType,
  blockProposals: DecoderBlockProposal[],
  sourceMapProposal,
  resourceTelemetry
}

DecoderBlockProposal {
  ordinal,
  sourceLocation,
  contentHandle
}
```

---

<a id="specify-cli-contract"></a>

## 27. Specify CLI contract

```text
sdd specify --reference <relative-selector>

SpecifyCommand {
  verb: specify,
  referenceSelector: RelativeReferenceSelector
}

SpecifyApiRequest {
  referenceSelector: RelativeReferenceSelector
}

Removed inputs (`--feature`, `--description`, `--feature-id`, `--ref`,
`-type`, positional descriptions, and Git/branch flags) are schema errors.
```

---

<a id="repair-authorization"></a>

## 28. Repair authorization

```text
RuleAuthority =
  | { kind: preset, authorityId, version }
  | { kind: platform_policy, authorityId, version }
  | { kind: engine_contract, authorityId, version }
  // Free-text principles are semantic guidance and can never be a mechanical
  // RepairRuleBinding authority.

RepairRuleBinding {
  ruleId,
  validatorContractId,
  authority: RuleAuthority,
  value:
    | { kind: path_pattern, pattern: PathPattern,
        patternContract: { id: path-pattern/v1, fullTargetMatch: true,
                           regexDialect: RE2 } }
    | { kind: extension_set, extensions[], extensionCaseSensitive,
        match: longest_suffix }
    | { kind: filesystem_policy, policyId, unicodeNormalization,
        caseRule, reservedBasenames[], forbiddenCharacters[], limits }
    | { kind: closed_schema, schemaId, schemaVersion,
        replacementSchema: ClosedAtomicValueSchema }
    | { kind: enum_set, values[] }
    | { kind: cardinality, minimum?, maximum?, exact? }
    | { kind: identifier_grammar, namespaceId, grammarId, allowedIds[]? }
    | { kind: registry_reference, registryKind, registryStateId,
        allowedIds[] }
    | { kind: coverage, obligationId, requiredRecordKinds[], minimumCountsByKind }
    | { kind: graph, graphStateId, allowedNodeIds[],
        allowedEdgeKinds[], forbiddenCycle: boolean, phaseOrder[] }
    | { kind: dependency_policy, ecosystem, registrySourceIds[],
        packageNameGrammarId, versionConstraintGrammarId, allowedScopes[] }
    | { kind: command_selection, commandRegistryId, allowedCommandIds[],
        typedArgumentSchemaIds[] }
    | { kind: content_policy, validatorIds[], parserIds[], resolverIds[],
        byteLimit?, tokenLimit? }
    | { kind: exact_value, expectedValue }
}

ClosedAtomicValueSchema {
  allowedTypes[],
  enumValues[]?,
  constValue?,
  minimumLength?,
  maximumLength?,
  requiredObjectKeys[]?,
  additionalProperties: false,
  itemSchema?                // same closed type, bounded by schema-depth limit
}

SemanticGuidanceBinding {
  principleSelectionId,
  principleRegistryStateId,
  principleRegistryStateRevision,
  immutableUnitOwnerId: ImmutableUnitOwnerId,
  selectedChunkIds[],
  exactRawSpans: PrincipleSourceSpan[]
  // Context only. It is revalidated against the immutable principle registry
  // and may be quoted to the model, but it never authorizes a mechanical edit.
}

RepairAuthorizationBase {
  authorizationId,
  diagnosticId,
  diagnosticCode,
  compiledEnginePolicyStateId,
  compiledRuleBindings: RepairRuleBinding[],
  semanticGuidanceBindings: SemanticGuidanceBinding[],
  sourceSemanticFinding?,
  candidateId,
  candidateRevision,
  immutableSiblingPointers[],
  impactedValidatorIds[],
  purpose: mechanical_atomic | semantic_atomic,
  retryOperationInstanceId,
  retryOrdinal,
  explicitRetryLimit
}

RepairAuthorization =
  | ReplaceAuthorization {
      base: RepairAuthorizationBase,
      operation: replace,
      targetPointer,
      expectedValue,
      replacementSchema
    }
  | InsertAuthorization {
      base: RepairAuthorizationBase,
      operation: insert,
      collectionPointer,
      stableKeyOrAnchor,
      expectedAbsence,
      elementSchema
    }
  | DeleteAuthorization {
      base: RepairAuthorizationBase,
      operation: delete,
      targetPointer,
      expectedValue
    }
  | ReplaceGroupAuthorization {
      base: RepairAuthorizationBase,
      operation: replace_group,
      unitId,
      targets: { targetId, pointer, expectedValue, replacementSchema }[]
    }
  | NoInventionClarificationReplacementAuthorization {
      authorizationId,
      diagnosticId,
      purpose: no_invention_to_clarification,
      operation: replace,
      sourceSemanticFinding: SemanticFinding,
      candidateId,
      candidateRevision,
      immutableUnitOwnerId: ImmutableUnitOwnerId,
      targetPointer,
      expectedOperationResultKind: content,
      replacementSchema: {
        schemaId,
        requiredKind: clarification_needed,
        additionalProperties: false
      },
      impactedValidatorIds[],
      oneShotOrdinal: 1
    }

RepairResponse =
  | ReplaceResponse { replacement }
  | InsertResponse { element }
  | DeleteResponse { confirmDelete: true }
  | ReplaceGroupResponse { replacementsByTargetId }
```

The engine selects exactly one response schema from its bound authorization;
the model cannot select a repair operation. Authorization, diagnostic and
revision checks use the existing runner-owned context, not model echoes.

---

<a id="repair-request"></a>

## 29. Repair request

The sample below is model-visible guidance plus its response schema. The
engine retains authorization, candidate revision, diagnostic identity and
compiled-policy identity separately; complete applicable rule bindings remain
in guidance. This does not remove authorization or old-value checks.
The sample response's 256-character limit is illustrative, not an engine default.

This filename-shaped repair is a fallback-only example for a specialized preset
that explicitly enables `allowRawPathFallback`. In the normal flow the model
returns a `PathIntentProposal` containing one allowed `pathIntentOptionId` and
`nameSourceId`, the engine enumerates preset-valid candidates through the
registered name transform, and the model selects a `pathCandidateId`; no raw
filename exists to repair.

```json
{
  "repairRequest": {
    "code": "PATH_FILENAME_PATTERN_INVALID",
    "targetPointer": "/rawPathFallbacks/file-3/repoRelativePath",
    "actual": "src/components/login-form.tsx",
    "expected": {
      "kind": "reactComponent",
      "ruleBindings": [
        {
          "ruleId": "react-component.root",
          "validatorContractId": "validate.path-pattern/v1",
          "authority": {
            "kind": "preset",
            "authorityId": "framework/react",
            "version": "1.0.0"
          },
          "value": {
            "kind": "path_pattern",
            "pattern": {
              "ruleId": "react-component.root",
              "base": "project",
              "target": "relative_path",
              "patternType": "glob",
              "value": "src/components/**",
              "caseSensitive": true
            },
            "patternContract": {
              "id": "path-pattern/v1",
              "fullTargetMatch": true,
              "regexDialect": "RE2"
            }
          }
        },
        {
          "ruleId": "react-component.basename",
          "validatorContractId": "validate.path-pattern/v1",
          "authority": {
            "kind": "preset",
            "authorityId": "framework/react",
            "version": "1.0.0"
          },
          "value": {
            "kind": "path_pattern",
            "pattern": {
              "ruleId": "react-component.basename",
              "base": "project",
              "target": "basename",
              "patternType": "regex",
              "value": "^[A-Z][A-Za-z0-9]*\\.tsx$",
              "caseSensitive": true
            },
            "patternContract": {
              "id": "path-pattern/v1",
              "fullTargetMatch": true,
              "regexDialect": "RE2"
            }
          }
        },
        {
          "ruleId": "react-component.extensions",
          "validatorContractId": "validate.extension-set/v1",
          "authority": {
            "kind": "preset",
            "authorityId": "framework/react",
            "version": "1.0.0"
          },
          "value": {
            "kind": "extension_set",
            "extensions": [".tsx"],
            "extensionCaseSensitive": true,
            "match": "longest_suffix"
          }
        }
      ]
    }
  },
  "responseSchema": {
    "type": "object",
    "properties": { "replacement": { "type": "string", "maxLength": 256 } },
    "required": ["replacement"],
    "additionalProperties": false
  }
}
```

---

<a id="repair-response"></a>

## 30. Repair response

```json
{
  "replacement": "src/components/LoginForm.tsx"
}
```

---

<a id="clarification-file-contract"></a>

## 31. Clarification file contract

The engine derives every path beneath `<paths.specs>/<featureId>/clarify/` from
the registry ID. The closed filename grammar is `S01.md` through `S99.md`,
`P01.md` through `P99.md`, or `T01.md` through `T99.md`. No other file,
subdirectory, case variant, or wider/shorter ordinal is imported.

```markdown
---
schemaVersion: clarification-form/v1
clarificationId: S01
stage: spec
clarificationStateId: clarification-state-4
clarificationStateRevision: 4
recordRevision: 1
engineStatus: open
requestedStatus: open
answerKind: bounded_business_text
---

# S01 — Specification clarification

## Question (engine-owned)

Which account roles may approve this operation?

## Why this is required (engine-owned)

The reference requires approval but does not identify the permitted roles.

## Allowed answer (engine-owned)

Enter at most 2,000 UTF-8 bytes. To answer, change `requestedStatus` to
`closed` and replace only the content between the answer markers. Use
`requestedStatus: open` with `defer: <reason>` to keep it open, or
`requestedStatus: cancel` with `cancel: <reason>` to cancel the run.

## Answer (user-editable)

<!-- sdd:answer:start -->

<!-- sdd:answer:end -->
```

For `select_one`, the answer region contains exactly one engine-rendered option
key. For `select_many`, it contains one option key per nonblank line, with no
duplicates; the parser enforces the record's minimum/maximum and normalizes the
canonical response value into engine option order without rewriting the user's
file, so user ordering cannot create a different canonical decision. Conflict forms use only claim-ID option keys from
the committed conflict. The parser compares every engine-owned scalar/section directly with the
current registry and imports only `requestedStatus` plus the bounded answer
region. It does not use hashes. A close with an empty/invalid answer, a stale
state or record revision, or a changed question is rejected. An
authority-resolved record is rerendered with its canonical lifecycle and cannot
be reopened by changing an old form; a later invalidation reopens the same ID
through a new registry/record revision. A consumed `defer` response is persisted
once, increments the registry and record revisions, keeps the workflow in the
same clarification-pending state, and rerenders `requestedStatus: open` with a
blank answer region. Replaying the prior defer form is therefore stale rather
than creating a duplicate response.

A user-closed file is retained byte-for-byte under Design Section 23.2, including
its original open engine status/revision fields and submitted closed status and
answer. Successful ingestion commits the accepted response and canonical
closure, not a replacement audit form. Subsequent reads validate the retained
file against that response's original submission binding. Stale/invalid closes
block without rewriting; a still-required subject with an inapplicable protected
answer requires user direction, not automatic reopening or a duplicate ID.

| Prefix | Owning stage | Pending state | Must be closed before |
|---|---|---|---|
| `S` | specify | `spec_clarification_pending` | plan, tasks, implement |
| `P` | plan | `plan_clarification_pending` | tasks, implement |
| `T` | tasks | `tasks_clarification_pending` | implement |

---

<a id="workflow-state"></a>

## 32. Workflow state

```json
{
  "workflowStateId": "workflow-state-12",
  "featureId": "user-authentication",
  "revision": 12,
  "stage": "tasks_review_pending",
  "workflowArtifactRegistryStateId": "workflow-artifacts-1",
  "bootstrapAuthorityStateId": "bootstrap-authority-3",
  "currentReferenceStateId": "reference-state-2",
  "currentPrincipleRegistryStateId": "principles-state-3",
  "currentPrincipleRegistryStateRevision": 3,
  "currentActorEvidenceRegistryStateId": "actor-evidence-state-4",
  "currentActorEvidenceRegistryStateRevision": 4,
  "currentReviewDecisionRegistryStateId": "review-decisions-state-3",
  "currentReviewDecisionRegistryStateRevision": 3,
  "currentWorkflowControlEventRegistryStateId": "workflow-control-events-state-2",
  "currentWorkflowControlEventRegistryStateRevision": 2,
  "currentPassiveLiteralRegistryStateId": "passive-literals-2",
  "currentPassiveLiteralRegistryStateRevision": 2,
  "currentClarificationStateId": "clarification-state-7",
  "currentClarificationStateRevision": 7,
  "openClarificationIdsByStage": {
    "spec": [],
    "plan": [],
    "tasks": []
  },
  "currentFeatureRequestStateId": "feature-request-state-2",
  "currentSpecificationProvenanceStateId": "spec-provenance-3",
  "currentPlanInputAuthorityStateId": "plan-input-authority-2",
  "currentPlanStateId": "plan-state-2",
  "currentTaskDefinitionStateId": "tasks-definition-1",
  "currentTaskRuntimeRevision": 0,
  "currentFinalValidationRecordId": null,
  "currentReworkInvalidationRecordId": null,
  "activeApprovalDecisionIds": ["review-plan-2"]
}
```

---

<a id="stage-transition-state-machine"></a>

## 33. Stage transition state machine

```text
new
  -> specifying
specifying
  -- valid SNN need --> spec_clarification_pending
  -- complete valid specification --> specified
  -- specification-contract bootstrap change --> specifying
     (adopted by the next complete specify transaction)
  -- planning-owning bootstrap change --> specifying
     (not adopted here; rebuilt/validated at later PlanInput entry)
spec_clarification_pending
  -- authenticated close/resolution while another SNN remains open --> spec_clarification_pending
  -- authenticated close/resolution of the last open SNN --> specifying
  -- authenticated defer --> spec_clarification_pending
  -- authenticated cancel --> cancelled
  -- specification-contract bootstrap change --> spec_clarification_pending
     (adopted by clarification pause/authority resolution; gate remains open)
  -- planning-owning bootstrap change --> spec_clarification_pending
     (not adopted here; rebuilt/validated at later PlanInput entry)

specified
  -- failed specification-edit ID retirement --> specified
     (actor/acknowledgement tombstones plus provenance/view rebind; no accepted edit)
  -- normal entry or planning-owning bootstrap change --> planning
     (PlanInputAuthorityStageTransaction)
  -- specification-contract bootstrap change --> specifying
     (ReworkInvalidationStageTransaction; empty later-descendant sets allowed)
planning
  -- failed specification-edit ID retirement --> planning
     (actor/acknowledgement tombstones plus successor PlanInputAuthorityState rebind;
      no model call)
  -- validated PlanInputAuthority successor refresh, before any model call --> planning
  -- valid PNN need --> plan_clarification_pending
  -- complete valid plan --> plan_review_pending
  -- specification-contract bootstrap change --> specifying
  -- planning-owning bootstrap change --> planning
     (successor PlanInputAuthorityStageTransaction before another model call)
plan_clarification_pending
  -- authenticated close/resolution while another PNN remains open --> plan_clarification_pending
  -- authenticated close/resolution of the last open PNN --> planning
  -- authenticated defer --> plan_clarification_pending
  -- authenticated cancel --> cancelled
  -- planning-owning bootstrap change --> plan_clarification_pending
     (successor PlanInputAuthorityState in clarification transaction)
  -- specification-contract bootstrap change --> specifying
plan_review_pending
  -- reject current plan units --> planning
  -- approve current planStateId --> planned

planned -> tasking
tasking
  -- valid TNN need --> tasks_clarification_pending
  -- complete valid task graph --> tasks_review_pending
tasks_clarification_pending
  -- authenticated close/resolution while another TNN remains open --> tasks_clarification_pending
  -- authenticated close/resolution of the last open TNN --> tasking
  -- authenticated defer --> tasks_clarification_pending
  -- authenticated cancel --> cancelled
tasks_review_pending
  -- reject current task units --> tasking
  -- approve current taskDefinitionStateId --> tasked

tasked
  -- current approvals and no outstanding S/P/T clarification --> implementing
  -- any outstanding S/P/T clarification --> blocked
     (report exact IDs; no task, model, command, or project mutation executes)
implementing -- final checks pass --> implemented

implementing
  -- final_check_failed --> final_validation_failed
final_validation_failed
  -- localized_to_approved_task --> implementing
final_validation_failed
  -- task_scope_gap --> implementation_reconciliation_tasks --> tasking

plan_review_pending | planned | tasking | tasks_review_pending | tasked | implementing(no commits)
  -- authenticated_specification_changed --> specified
specified | planning | plan_clarification_pending |
plan_review_pending | planned | tasking | tasks_review_pending | tasked | implementing(no commits)
  -- reference_changed | bootstrap_reference_ingestion_changed |
     bootstrap_specification_contract_changed --> specifying
plan_review_pending | planned | tasking | tasks_review_pending | tasked | implementing(no commits)
  -- plan_rework_required --> planning
tasks_review_pending | tasked | implementing(no commits)
  -- tasks_rework_required --> tasking
plan_review_pending | planned | tasking | tasks_review_pending | tasked | implementing(no commits)
  -- principle_registry_changed | bootstrap_technical_planning_changed --> planning
implementing(after commit)
  -- authenticated_specification_changed --> implementation_reconciliation_spec --> specified
implementing(after commit)
  -- reference_changed | bootstrap_reference_ingestion_changed |
     bootstrap_specification_contract_changed --> implementation_reconciliation_spec --> specifying
implementing(after commit)
  -- plan_rework_required --> implementation_reconciliation_plan --> planning
implementing(after commit)
  -- tasks_rework_required --> implementation_reconciliation_tasks --> tasking
implementing(after commit)
  -- principle_registry_changed | bootstrap_technical_planning_changed --> implementation_reconciliation_plan --> planning

any nonterminal stage
  -- runtime-only change plan --> same stage with refreshed bootstrap authority
any adopting bootstrap transition whose change plan contains logging impact
  -- committed successor --> logging-policy transition before next normal event/model/node
any nonterminal stage
  -- project-root/artifact-layout/serializer/renderer/unsupported-schema change --> blocked pending explicit administrative migration
```

---

<a id="observability-events"></a>

## 34. Observability events

```text
Levels use the shared CanonicalLogLevel definition from Section 3.
Configured aliases = CRITICAL -> fatal | WARN -> warning
Emission rule = rank(eventDefinition.level) >= rank(featureLogPolicy.threshold)

run.started | run.completed | run.blocked | run.failed | run.cancelled
stage.started | stage.completed | stage.blocked | stage.failed |
stage.clarification_pending
action.started | action.completed | action.invalid | action.failed
model.requested | model.completed | model.protocol_failed |
model.schema_failed
validation.completed | validation.failed
repair.requested | repair.applied | repair.rejected | repair.exhausted
review.requested | review.approved | review.rejected
transaction.prepared | transaction.applying | transaction.committed |
transaction.rolled_back | transaction.recovered
command.started | command.completed | command.failed
task.started | task.completed | task.blocked | task.failed
security.denied
model.prompt_fragment // prompt stream only

// This is the exhaustive proof-of-concept registry. Exact levels, required and
// optional fields, and sensitivity are the F0002 Section 6.2 table. Each name
// resolves to the immutable <event_type>/v1 template.
// Producers supply typed facts only; they cannot choose the name's level or
// message. No event carries arbitrary text, raw model/reference/code content,
// command output, credentials, or diagnostic expected/actual values.
// model.prompt_fragment.content is accepted only after sanitization. The
// logging subsystem's own failure emits the exact bounded F0002 Section 6.4
// emergency stderr line outside this registry and cannot observe itself.
```

---

<a id="suggested-package-structure"></a>

## 35. Suggested package structure

```text
sdde/
├── build.zig
├── build.zig.zon
├── src/
│   ├── main.zig                    # process entry point only
│   ├── root.zig                    # public library surface
│   ├── interface/
│   │   ├── cli.zig
│   │   └── api.zig
│   ├── application/
│   │   ├── node.zig               # common contract/outcome/envelope
│   │   ├── runner.zig             # sole delta application/invocation owner
│   │   ├── workflow_engine.zig     # select, run invocation contract, execute graph
│   │   ├── workflow_compiler.zig   # validated project definition -> registered-operation graph
│   │   ├── workflow_registry.zig   # unique WorkflowId -> compiled graph
│   │   ├── composition_root.zig    # adapters, node bindings, fixed startup graph
│   │   ├── actions/
│   │   │   ├── bootstrap/
│   │   │   ├── workflow_definitions/
│   │   │   ├── preset_ingestion/  # code only; never runtime preset data
│   │   │   ├── project_toolchain/
│   │   │   ├── principles/
│   │   │   ├── references/
│   │   │   ├── authority_reconciliation/
│   │   │   ├── clarifications/
│   │   │   ├── authentication/
│   │   │   ├── logging/
│   │   │   ├── model/
│   │   │   ├── artifacts/
│   │   │   ├── paths/
│   │   │   ├── validation/
│   │   │   ├── tasks/
│   │   │   ├── implementation/
│   │   │   └── persistence/
│   │   └── orchestrators/
│   │       ├── workflow/
│   │       ├── stages/
│   │       ├── generation/
│   │       ├── reconciliation/
│   │       ├── repair/
│   │       ├── transactions/
│   │       └── scheduling/
│   ├── domain/
│   │   ├── config/
│   │   ├── workflow_definition/
│   │   ├── preset/
│   │   ├── project_toolchain/
│   │   ├── principles/
│   │   ├── authority/
│   │   ├── clarifications/
│   │   ├── workflow/
│   │   ├── references/
│   │   ├── specification/
│   │   ├── planning/
│   │   ├── tasks/
│   │   ├── implementation/
│   │   ├── diagnostics/
│   │   └── evidence/
│   ├── ports/
│   │   ├── filesystem.zig
│   │   ├── model.zig
│   │   ├── process.zig
│   │   ├── parser.zig
│   │   ├── readers.zig
│   │   ├── state.zig
│   │   ├── authentication.zig
│   │   ├── feature_log.zig
│   │   └── telemetry.zig
│   ├── adapters/
│   │   ├── filesystem/
│   │   ├── models/
│   │   ├── processes/
│   │   ├── parsers/
│   │   ├── readers/
│   │   ├── manifests/
│   │   ├── authentication/
│   │   ├── feature_log/
│   │   └── telemetry/
│   ├── renderers/
│   ├── schemas/
│   ├── preset_schema/              # schemas/compiler, no preset fallback data
│   └── principle_categories/
├── test/
│   ├── architecture/
│   ├── contracts/
│   ├── properties/
│   ├── fault_injection/
│   ├── end_to_end/
│   └── packaging/
└── design/
    ├── examples/
    │   └── .sddtoolkit.json         # sample only; never runtime fallback
    ├── templates/                   # sdd init source examples; never packaged authority
    └── toolchainPresets/            # examples only; never packaged authority
```
