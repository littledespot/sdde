# Deterministic SDD Engine contract and data-shape samples

Illustrative companion to the [proposed engine design](design.md). Samples do
not establish implemented behavior or override governing contracts.

- **Identity:** the supplied feature directory identifies the feature
  ([ADR 0010](decisions/0010-explicit-feature-directory.md)).
- **Execution:** candidates are execution-local; each invocation starts at
  `start`. No sample authorizes independent task commits, transaction storage,
  checkpoints or restart recovery
  ([ADR 0009](decisions/0009-atomic-workflow-execution.md)).
- **Clarifications:** persistent identities and answers require current
  applicability checks. Reruns replace registered outputs and unresolved forms;
  user-closed forms remain byte-for-byte unchanged
  ([§23.2](design.md#232-workflow-reruns-and-protected-clarification-files)).
  Outstanding S/P/T clarifications prevent implementation.
- **Model limits:** providers own per-call size limits; execution accounting uses
  actual API-reported tokens ([ADR 0011](decisions/0011-provider-owned-request-limits.md)).
  Samples add no local size ceilings or size-fit evidence.

**Notation:** `text` fences contain language-neutral SDDE contracts.

| Sample notation | Zig meaning |
| --- | --- |
| Closed `A \| B` variants | `union(enum)` |
| Exhaustive branches | `switch` |
| Optional values | `?T` |
| Unexpected operational failures | Error unions |
| `immutable` | Runner-owned storage exposed through bounded const views |
| `DataKey<T>` and similar forms | Compile-time typed relationships; no unchecked heterogeneous map or runtime reflection |

Target-project YAML/JSON may name TypeScript, JavaScript or Node environments.
Engine-side result carriers are not wire schemas: `{kind, proposal}` does not
require a JSON `proposal` wrapper. [ADR 0006](decisions/0006-minimal-model-response.md)
omits engine-bound fixed tags while retaining meaningful nested objects,
discriminators and collections; it does not flatten arbitrary JSON.

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

PipelineOutcomeStatus = ok | more | needs_user | invalid | blocked | failed | cancelled
// more is successful bounded progress and must transition to another step,
// never to a workflow terminal (F0005 §3.3).

AppliedChildOutcome {
  status: PipelineOutcomeStatus,
  nextEnvelope,          // runner-created by applying the child's one NodeDelta
  candidateDelta?        // available only on the invalid branch for authorized repair
}
```

---

<a id="node-runtime"></a>

## 2. Capability-free node runtime

Implemented as `NodeRuntime` in [pipeline.zig](../src/domain/pipeline.zig): one
`status()` reporting `active`, `cancelled` or `deadline_exhausted`, which carries
the sample's cancellation token and deadline. Kept here, flagged: the native type
has no `correlationContext` or `traceContext`.

- The runtime carries no operation capabilities.
- Orchestrators receive runner-owned child bindings; actions receive narrow ports.
- The runner owns invocation, delta checks/application, telemetry and cleanup.
- [F0002](features/F0002-LogService.md) owns logging I/O through its
  [sink port](../src/ports/feature_log_sink.zig). Log-tail recovery never resumes
  a workflow; there are no checkpoint, receipt or recovery ports
  ([ADR 0009](decisions/0009-atomic-workflow-execution.md)).

Owners: [Design §6](design.md#6-common-action-and-orchestrator-contract),
[runtime types](../src/domain/pipeline.zig),
[workflow runner](../src/application/workflow_pipeline_runner.zig).

---

<a id="node-contract-and-data-keys"></a>

## 3. Node contract and typed data keys

Implemented as `NodeContract` in [pipeline.zig](../src/domain/pipeline.zig) and,
for a registered operation, `Contract` in
[workflow_operation.zig](../src/domain/workflow_operation.zig), whose `retry_limit`
(maximum and scope) is the retry-limit contract. The [§13 catalogue](design.md#13-action-catalogue)
gives each operation's runner accounting transition and the writers of
`model_request_identity_ledger`. Kept here, flagged, because the native types lack them:

- side effect `command`, for proposed Implement commands ([§26](design.md#26-security-and-safety));
- `orderingBarriers[]` ([§6.3](contracts/06-pipeline-nodes.md#63-reordering-and-composition-rules)).

```text
DataKey<T> {
  id,                 // closed key name, e.g. model_request_identity_ledger
  schemaVersion,      // integer, e.g. 1
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
      operationRetryCounts:
        Map<{ operation: CompiledWorkflowOperationInstanceId,
              nativeDefectKey? }, NonnegativeInteger>
    },
    workflowTokenAccounting: {
      workflowTokenBudget,
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
    rendererContractVersion,
    compiledPresetIds,
    validationProfile
  },
  data: ImmutableDataRegistry<DataKey, value>,
  // The compiler-owned model_request_identity_ledger DataKey (schema version 1)
  // lives here; PipelineRunner alone applies its authorized immutable successor delta.
  evidence: Evidence[],
  diagnostics: Diagnostic[]
}
```

---

<a id="pipeline-outcome"></a>

## 5. Pipeline outcome

Native owners:

- `NodeDelta` in [pipeline.zig](../src/domain/pipeline.zig): data writes,
  replacements and invalidations, `WorkflowTelemetryFact` values, an optional runner
  accounting transition and an optional repair transition.
- Runner accounting transitions: `Transition` in
  [runner_accounting.zig](../src/domain/runner_accounting.zig)
  (`increment_model_attempt`, `reconcile_workflow_tokens`,
  `advance_provider_operation`). The runner accepts one only from the registered
  accounting operation; [model-request-operations.md](contracts/model-request-operations.md)
  owns each lifecycle step's inputs, transitions and publication.
- Native repair progress: `Transition` in
  [workflow_retry.zig](../src/domain/workflow_retry.zig) (`authorized`, `merged`,
  `validated`, `merged_validated`); bindings supply facts and only the runner counts
  ([§22.7](contracts/22-repair.md#227-repair-retry-limit-and-escalation)).
- Provider authorization result: `Result` and `Outcome` in
  [provider_authorization_result.zig](../src/domain/provider_authorization_result.zig)
  (`prepared` lease reference, `failed`, `cancelled`); the lease capability stays in
  the runner's private table.
- Telemetry facts: one variant per event in the
  [F0002 §6.2](features/F0002-LogService.md#62-levels-and-content-safety) registry,
  whose payload is exactly that row's fields; F0002 §4 owns the fact shape and what
  a fact may not contain. `model.prompt_fragment` is not a fact. The native
  `TelemetryFact` in [telemetry.zig](../src/domain/telemetry.zig) doesn't meet that
  shape yet (SPEC01 "F0002 event registry").

Kept here, flagged, because the native types lack them:

```text
Outcome {
  status: PipelineOutcomeStatus,
  delta: NodeDelta,
  candidateDelta?        // retained off the committed data path for repair
}

// NodeDelta fields with no native counterpart:
evidenceAdded: Evidence[]
diagnosticsAdded: Diagnostic[]
```

---

<a id="shared-domain-types"></a>

## 6. Shared domain types

Current native types and their governing documentation:

| Contract | Native owner | Design owner |
| --- | --- | --- |
| Configuration | [config.zig](../src/domain/config.zig) | [F0001](features/F0001-SDDToolKitConfigService.md) |
| Configured path validation | [configured_path_policy.zig](../src/domain/configured_path_policy.zig) | [F0004](features/F0004-BootstrapRootRegistryService.md) |
| Workflow definitions | [workflow_definition.zig](../src/domain/workflow_definition.zig) | [F0005](features/F0005-WorkflowDefinitionRegistryService.md) |
| Compiled workflow registry | [workflow_registry.zig](../src/domain/workflow_registry.zig) | [ADR 0003](decisions/0003-generic-workflow-engine.md) |
| Toolchain policy | [toolchain.zig](../src/domain/toolchain.zig) | [F0003](features/F0003-ToolChainService.md) |
| Provider registry and binding | [F0006 source references](features/F0006-LLMProviderInterface.md) | [ADR 0004](decisions/0004-model-provider-bootstrap.md) |
| Request identity and handoff | [model_request_identity.zig](../src/domain/model_request_identity.zig), [model_request_handoff.zig](../src/domain/model_request_handoff.zig) | [ADR 0012](decisions/0012-workflow-owned-model-request.md) |
| Feature directory and artifact paths | [feature_directory.zig](../src/domain/feature_directory.zig), [workflow_artifact_registry.zig](../src/domain/workflow_artifact_registry.zig) | [ADR 0010](decisions/0010-explicit-feature-directory.md) |
| Log policy, columns and events | [log_policy.zig](../src/domain/log_policy.zig), [feature_log_format.zig](../src/domain/feature_log_format.zig), [log_event_registry.zig](../src/domain/log_event_registry.zig) | [F0002 §6](features/F0002-LogService.md#6-levels-and-content-safety) |
| Typed text and exact values | [typed_text.zig](../src/domain/typed_text.zig), [structured_tokens.zig](../src/domain/structured_tokens.zig) | [F0100 §3.8](features/F0100-SpecWorkflow.md#38-exact-value-preservation) |
| Source identities and evidence | [reference_identity.zig](../src/domain/reference_identity.zig), [reference_evidence.zig](../src/domain/reference_evidence.zig) | [Design §16](design.md#16-reference-ingestion-and-normalization) |
| Reconciliation | [reference_reconciliation.zig](../src/domain/reference_reconciliation.zig) | [F0100 §3.9](features/F0100-SpecWorkflow.md#39-reference-reconciliation-boundary) |
| Specification and provenance | [specification_state.zig](../src/domain/specification_state.zig), [specification_provenance.zig](../src/domain/specification_provenance.zig) | [F0100 §5](features/F0100-SpecWorkflow.md#5-specmd-projection-contract) |
| Clarification input and refresh | [clarification_inputs.zig](../src/domain/clarification_inputs.zig), [clarification_refresh.zig](../src/domain/clarification_refresh.zig) | [Design §23.2](design.md#232-workflow-reruns-and-protected-clarification-files) |
| Publication | [workflow_output.zig](../src/domain/workflow_output.zig) | [Design §25](design.md#25-atomic-workflow-execution-and-output) |

Plan, task, implementation and authenticated-review samples remain proposed.
Request/attempt/operation ledgers are execution-local; no durable transaction-ID
allocator, checkpoint or provider journal is implied.

<a id="authority-reconciliation-contract"></a>

### 6.1 Authority reconciliation contract

- This sample illustrates the broader design, not a second wire schema.
- Clarification outcomes require [§12.8.1 admission](contracts/12-model-boundary.md#1281-clarification-admission-and-candidate-failure-precedence).
  The sample's gap enum alone grants no publication authority; candidate/review
  failures retain their separate native rejection path.
- [`required_authority.zig`](../src/domain/required_authority.zig) owns the shared
  execution-local types and compiler-locked policies.
- Closed observations reference supplied evidence; they cannot author rules,
  ownership, evidence records or continuation.
- [F0100 §3.10](features/F0100-SpecWorkflow.md#310-shared-required-authority-boundary)
  defines Specify's native projection and YAML operations.

```text
AuthorityOwnerStage = ClarificationStage
AuthorityDetectionStage = spec | plan | tasks | implement

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
  // There is deliberately no unresolved authority success, default,
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

This illustrative sample describes canonical `specification/v6` under
[ADR 0020](decisions/0020-derived-exact-reference-lineage.md). The display name is native
text, the sources' level-1 heading ([ADR 0048](decisions/0048-engine-derived-specification-title.md)). Initial narrative
responses select current whole groups through `signal_ids`; non-entity record
responses keep their one native-assigned group and name a nonempty ordered subset of
its claims as `claim_ids` ([ADR 0038](decisions/0038-record-claims-and-scenario-coverage.md));
entities keep whole groups. Native admission stores canonical `source_group_ids` and
those `claim_ids`. The engine composes `primary_user_story` from the quoted business
claims of its catalogue's groups; no model response carries it
([ADR 0047](decisions/0047-engine-composed-primary-story.md)).
Exact segments select preserved-token occurrences; effective claims and citations
derive from explicit selection plus exact segments. Fixed repairs preserve the
association and return content only. Earlier shapes have no reader.

Implemented in [specification.zig](../src/domain/specification.zig) as `Provenance`,
`AttributedValue`, `RecordProposal`, `ContentProposal`, the `Content` record union,
`IdentifiedRecord` (whose `outcome_of` links an edge case to the criterion whose
Then it prints, ADR 0038 Decision 7) and `IdentifiedContent`; the initial-response
forms are `AuthoringValue` (`signal_ids`), `AuthoringRecord` (`claim_ids`, non-entity
records) and `AuthoringEntity` in
[specification_generation.zig](../src/domain/specification_generation.zig). The
engine derives an entity's related statements
([§23.1](contracts/23-rendering.md#231-canonical-byte-contract)).

Native [content contract](../src/domain/specification.zig) interpretation:

- Tagged unions encode as single-key objects, e.g.
  `{"functional_requirement":{"text":...}}`; canonical values retain their
  native-admitted associations and provenance.
- Canonical `BusinessValue` holds ordered prose, passive-ID and engine-derived
  `exact_copy` claim-occurrence segments. Under ADR 0020, model prose contains
  verbatim exact values; native recognition owns those segments.
  Requirement wording carries modality; there is no separate modality field.
- Parsing yields a candidate. The shared authority gate, generation validation and
  publication must assemble and validate current reference, passive, clarification,
  identity and provenance state before it
  becomes canonical specification authority.
- Questions use `clarification_needed`, never specification content.
  `ReferenceContextIR.openQuestions` belongs only to reference context.
- [F0100 §5.6](features/F0100-SpecWorkflow.md#56-native-content-and-view-contract)
  owns mechanical grammar and entity applicability. The
  [view codec](../src/domain/specification_markdown.zig) captures text, IDs and
  section presence; missing entities do not prove non-applicability.

The canonical `spec.md` projection for each acceptance-criterion
record is nested under `User Scenarios & Testing` in
[F0100's heading tree](features/F0100-SpecWorkflow.md#51-ownership-and-hierarchy):

```markdown
### Acceptance Criteria

- **AC-001**: **Given** <nonempty `given` value>, **When** <nonempty `when` value>, **Then** <nonempty `then` value>
```

- Render the heading once, then each `AC-*` identity and labeled triplet.
- The renderer owns label spelling, title case and order. The parser rejects
  free-form, missing, partial, duplicate, reordered or incorrectly cased labels.
- Omit empty optional sections under F0100 §5.4; mandatory content remains a
  shared authority obligation.

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
      | { kind: principle_consideration, principleChunkIds[] }
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

Proposed operation shapes for [Design §20](design.md#20-implement-stage-design):

```text
FileOperation =
  | CreateFile { operationIntentId, fileId, completeContent }
  | UpdateFile { operationIntentId, fileId, patch }
  | ReplaceFile { operationIntentId, fileId, completeContent }
  | CopyFile { operationIntentId, sourceId, destinationFileId }
  | DeleteFile { operationIntentId, fileId, justification }
```

- Current approved plan/task authority supplies file IDs. The engine binds target
  existence, revisions, effects and copy-source provenance; models choose no raw
  paths, commands or target state.
- Copies preserve source bytes; adaptation requires a separately authorized edit.
- Delete requires explicit policy and task authority.
- Operation/command savepoints isolate changes within the current execution.
- [Design §26](design.md#26-security-and-safety) governs named commands,
  shell-disabled execution and explicit directory/environment/network/resource/
  timeout policy.
- Validate each effect and its evidence, then the whole candidate. Task completion
  requires whole-workflow publication; there are no durable journals, checkpoints,
  before-image recovery or per-task commits
  ([ADR 0009](decisions/0009-atomic-workflow-execution.md)).

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

[F0001](features/F0001-SDDToolKitConfigService.md) and the
[configuration schema](schemas/sddtoolkit-config.schema.json) own the single
unversioned contract; [examples/.sddtoolkit.json](examples/.sddtoolkit.json) is a
complete example. Implemented as `SDDToolKitConfig` in
[config.zig](../src/domain/config.zig). [§9](contracts/09-configuration.md) owns
its rules: closed immutable decoding, consumer-owned semantic validation, the exact
invocation-directory file with no search or fallback, and slots without an
output-token allowance. F0001's 1 MiB configuration-read guard is unrelated to
provider-owned call limits.

See [§9.1](contracts/09-configuration.md#91-required-configuration-shape) for
configured roots and engine-derived children,
[F0003](features/F0003-ToolChainService.md) for mechanical project policy,
and [F0006](features/F0006-LLMProviderInterface.md) for provider catalogue joins.
Templates remain inert; `init` is outside the initial suite.

---

<a id="preset-identity-and-composition"></a>

## 15. Preset identity and composition

Samples 15–20 illustrate proposed compiled policy concepts, not the current
authored preset YAML. [F0003 §3](features/F0003-ToolChainService.md#3-closed-loading-and-publication-contract)
owns the accepted project/preset document shape, composition and safety gate.
These examples do not add runtime fields or imply environment/parser/command
features are implemented.

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

- Before merging preset discovery rules, inject exclusions from all seven
  `BootstrapRootRegistry` directory capabilities and its provider-file capability.
- Use resolved configured paths, never an assumed `.sddtoolkit` directory.
- Keep `specsArchive` explicit even when nested beneath `specs`.
- Presets cannot remove, shadow or override exclusions
  ([F0004](features/F0004-BootstrapRootRegistryService.md)).

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
    contentLimits: { copiedSourceBytes: 1048576 }
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
    contentLimits: { copiedSourceBytes: 1048576 }
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
    contentLimits: { copiedSourceBytes: 0 }
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

`forbiddenPaths` covers preset policy only. The compiler injects the overriding
`ReservedEngineRootPathPolicy` from the seven directory capabilities, provider
file capability and derived `<paths.workflows>/features/`. Models/presets supply
none of its path text and cannot override it
([§9.1](contracts/09-configuration.md#91-required-configuration-shape)).

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
  responseSchema        // no synthetic candidate example (§12.2)
}

PrincipleGuidance {
  principleRegistryStateId,
  principleRegistryStateRevision,
  entries: {
    principleChunkId,
    sourceSpan: PrincipleSourceSpan,
    rawUtf8BytesHandle,
    byteLength
  }[],
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
      complete: true
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
  | ContentGuidance { applicableRuleIds[], requiredValidatorIds[] }
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
  "reason": "Implementation must make the intended-red verification pass."
}
```

The selected task keys and prose reason (a plain string, §7.1) are meaningful candidate data and
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
CompositionRoot (before the engine starts; ADR 0032 startup routine)
└── startup routine; validated result passed to the engine
    ├── configuration/root steps
    ├── workflow inventory/capture/parse/schema steps
    ├── workflow graph compile/validate steps
    └── variable-size workflow registry steps; no feature transaction lock

PipelineRunner
├── WorkflowEngineOrchestrator (capability-free graph coordination)
│   ├── validate-workflow-operation-registry, parse-workflow-invocation and
│   │   select-compiled-workflow, in that order, through runner-owned child bindings
│   ├── provider-bootstrap routine through a runner-owned binding (ADR 0004, ADR 0032)
│   └── Selected CompiledWorkflowGraph
│       ├── YAML-named invocation operation through a runner-owned binding
│       │   └── parser/validator child bindings when that contract composes them
│       ├── selected-graph target-context setup binding when required
│       │   ├── toolchain-preset registry/compilation actions
│       │   ├── explicit feature-directory and selected-state validation
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
capture invocation working directory
  -> locate/read/decode its exact .sddtoolkit.json
  -> validate configured root capabilities and logging policy
  -> inventory/capture/compile all declared workflows and resources
  -> publish immutable workflow registry
  -> select the exact requested workflow ID
  -> derive provider requirement from the selected compiled graph
     -> required: capture/decode/validate provider catalogue and slot allowlist
     -> not_required: perform no provider-document operation
  -> invoke the selected registered invocation contract
  -> execute from the graph's start through runner-owned bindings
```

Configuration/root/workflow loading and conditional provider preparation are
fixed engine machinery. Further setup is selected by the workflow's registered
operations. Bootstrap creates no feature transaction, recovery store or saved
continuation. See [Design §15](design.md#15-bootstrap-flow) and
[ADR 0004](decisions/0004-model-provider-bootstrap.md).

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

The selected definition supplies the workflow ID. The supplied
[Spec definition](workflows/spec.workflow.yaml) uses `spec-generation`.

```text
sdde <workflow-id> --feature <feature-directory> --reference <relative-selector>

SpecifyCommand {
  workflowId: WorkflowId,
  featureDirectory: ValidatedFeatureDirectory,
  referenceSelector: RelativeReferenceSelector
}

SpecifyApiRequest {
  featureDirectory: ValidatedFeatureDirectory,
  referenceSelector: RelativeReferenceSelector
}

Both inputs are required and independent. featureDirectory is relative to
.sddtoolkit.json paths.specs; referenceSelector is relative to paths.references.
For --feature hello-world, the output is <paths.specs>/hello-world/spec.md.
The configured root is neither repeated by the caller nor hard-coded by the engine.
Missing, empty, duplicate, unknown or positional inputs are schema errors. The generic
engine delegates this grammar to the selected registered invocation operation.
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
    | { kind: content_policy, validatorIds[], parserIds[], resolverIds[] }
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
  retryOperationInstanceId   // compiled step instance (ADR 0033); counts and limits stay runner-owned (§22.7)
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

Answer parsing:

- `select_one`: exactly one engine-rendered option key.
- `select_many`: one key per nonblank line, no duplicates, within the record's
  minimum/maximum. Normalize the canonical answer to engine option order without
  rewriting the submitted file; user ordering cannot change the decision.
- Conflict forms: only claim-ID option keys from the committed conflict.
- Compare every engine-owned scalar/section directly with the current registry,
  without hashes; import only `requestedStatus` and the bounded answer region.
- Reject closes with empty/invalid answers, stale state/record revisions or a
  changed question.

Lifecycle:

- Rerender authority-resolved records with their canonical lifecycle. Editing an
  old form cannot reopen them; later invalidation reopens the same ID at a new
  registry/record revision.
- Consume `defer` once, increment registry/record revisions, retain the pending
  state, and rerender `requestedStatus: open` with a blank answer. Replay is stale.
- [Design §23.2](design.md#232-workflow-reruns-and-protected-clarification-files)
  owns replacement/protection for all workflows and clarification families:
  replace unresolved forms from current state at the same subject IDs/paths,
  including unchanged questions and unsubmitted drafts; retain user-closed bytes.
- Ingest accepted responses and canonical closure without replacing the closed
  file's original engine status/revisions, submitted status or answer. Revalidate
  later reads against the original submission binding.
- Stale/invalid closes block without rewriting. An inapplicable protected answer
  to a still-required subject needs user direction, not reopening or a duplicate ID.
- Validate controlled closes before replacement; recheck protection immediately
  before writing.

| Prefix | Owning stage | Pending state | Must be closed before |
|---|---|---|---|
| `S` | specify | `spec_clarification_pending` | plan, tasks, implement |
| `P` | plan | `plan_clarification_pending` | tasks, implement |
| `T` | tasks | `tasks_clarification_pending` | implement |

---

<a id="workflow-state"></a>

## 32. Workflow state

The current Specify state format is owned by
[specification_state.zig](../src/domain/specification_state.zig) and documented
in [F0100 §3.12](features/F0100-SpecWorkflow.md#312-clarification-refresh-and-registered-publication).
It must not be confused with the proposed multi-stage state in
[Design §24.1](design.md#241-workflow-state).

Published state identifies the accepted content and its supporting source,
claim, citation, clarification and provenance records. Reads revalidate current
authority; generated Markdown alone cannot establish completion. State is
published after the other registered outputs, and publication failure cannot
record a new successful completion. Clarification state has the separate
persistence/protection rules in §23.2. Execution-local requests and candidate
progress are never serialized as a continuation.

---

<a id="stage-transition-state-machine"></a>

## 33. Stage transition state machine

The proposed SDD stage gates are defined by
[Design §24](design.md#24-state-sequence-and-recovery-without-fingerprints).

```text
validated specification
  -> plan generation -> review of exact current plan -> approved plan
  -> task generation -> review of exact current tasks -> approved tasks
  -> implementation -> whole-candidate validation -> successful publication
```

Each downstream invocation revalidates its predecessor and applicable answers.
Upstream changes invalidate affected descendants and approvals. Missing authority
returns to its earliest owner; failed, blocked, cancelled and completed remain
distinct. `needs_user` ends the execution and persists the permitted clarification
output. A later invocation starts at `start` and regenerates the owning workflow.

No state-machine edge resumes a saved task, adopts an interrupted candidate,
commits a task independently or performs checkpoint recovery. Unrelated workflows
follow their own compiled gates and transitions.

---

<a id="observability-events"></a>

## 34. Observability events

[Design §26.5](contracts/26-security.md#265-secrets-and-logging) defines the canonical
levels, aliases and emission rule. The exhaustive event registry, with each event's
level, emission, fields and sensitivity, is the
[F0002 §6.2](features/F0002-LogService.md#62-levels-and-content-safety) table;
F0002 §4 limits what a producer's fact may carry and §6.4 fixes the emergency line.
It is implemented as `EventType` in [telemetry.zig](../src/domain/telemetry.zig)
and [log_event_registry.zig](../src/domain/log_event_registry.zig), which don't meet that
registry yet (SPEC01 "F0002 event registry").

---

<a id="suggested-package-structure"></a>

## 35. Suggested package structure

The current repository layout is:

```text
src/
  domain/        # pure contracts, validated values and deterministic rules
  actions/       # one-responsibility pipeline actions
  application/   # runners, envelopes, bindings, orchestrators and services
  ports/         # narrow operation interfaces
  adapters/      # filesystem, parsing, provider and system implementations
  composition/   # concrete assembly
  debugger/      # embedded request-debugger browser assets (ADR 0019)
  test_fixtures/ # fake inputs and helpers for engine tests
test/
  integration/   # offline integration scenarios
  build/         # build-graph and test-registration checks
  packaging/     # clean native-executable smoke
  calibration/   # calibration cases
  harness/       # development-only live E2E and rubric evaluation
  e2e/           # live E2E case declarations and their resources
build.zig        # repository-owned build and verification steps
```

[Design §29](design.md#29-suggested-packagemodule-structure) owns dependency
rules. Runtime configuration and workflow resources come from the explicitly
configured project; design examples and test assets are not fallback data.
There is no transaction or recovery-storage package.
