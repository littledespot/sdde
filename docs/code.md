# Deterministic SDD Engine code and interface samples

This companion contains the sample contracts, schemas, configuration, flow notation, and package layout referenced by [the engine design](design.md). The design document is normative; these samples illustrate its contracts and must evolve with it.

## Contents

1. [Pipeline node interfaces](#pipeline-node-interfaces)
2. [Capability-free node runtime](#node-runtime)
3. [Node contract and typed data keys](#node-contract-and-data-keys)
4. [Pipeline envelope](#pipeline-envelope)
5. [Pipeline outcome](#pipeline-outcome)
6. [Shared domain types](#shared-domain-types)
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
31. [Workflow state](#workflow-state)
32. [Stage transition state machine](#stage-transition-state-machine)
33. [Observability events](#observability-events)
34. [Suggested package structure](#suggested-package-structure)

---

<a id="pipeline-node-interfaces"></a>

## 1. Pipeline node interfaces

```text
interface PipelineNode {
  contract: NodeContract
  execute(
    envelope: PipelineEnvelope,
    runtime: NodeRuntime
  ) -> Outcome
}

interface Action extends PipelineNode {
  contract.kind = "action"
  // Has no children, node runner, dispatcher, or orchestrator reference.
}

interface Orchestrator extends PipelineNode {
  contract.kind = "orchestrator"
  children: readonly PipelineNode[]
  // May invoke/schedule children and branch on Outcome metadata only.
  // Has no filesystem, model, parser, validator, renderer, state, or process port.
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
  retryPolicyId?,
  orderingBarriers[]
}

DataKey<T> {
  id,                 // e.g. "spec.ir"
  schemaVersion,      // e.g. "1"
  valueSchema
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
    repairAttempt
  },
  workspace: {
    canonicalRoot,
    artifactRoot,
    environmentIds
  },
  policy: {
    configVersion,
    compiledPresetIds,
    validationProfile
  },
  data: ImmutableDataRegistry<DataKey, value>,
  evidence: Evidence[],
  diagnostics: Diagnostic[]
}
```

---

<a id="pipeline-outcome"></a>

## 5. Pipeline outcome

```text
Outcome {
  status: ok | invalid | blocked | failed | cancelled,
  envelope: PipelineEnvelope,
  candidateDelta?,       // retained off the committed data path for repair
  diagnostics: Diagnostic[],
  evidence: Evidence[]
}
```

---

<a id="shared-domain-types"></a>

## 6. Shared domain types

```text
ProjectStandards {
  modules: StandardModule[],
  compiledRules: MechanicalStandardRule[],
  semanticSections: SemanticStandardSection[],
  fallbackEvidence[]
}

StandardModule {
  id,
  category: core | architecture | testing | security |
            observability | operations | user_interface | custom,
  sourcePath,
  precedence,
  parsedSections[]
}

FeatureRequest {
  originalText,
  featureId,
  displayName,
  referenceRequest?
}

ReferenceManifest {
  root,
  entries: ReferenceEntry[],
  allEntriesAccountedFor
}

ReferenceEntry {
  sourceId,                 // stable within a persisted reference snapshot
  relativePath,
  mediaType,
  authority: authoritative,
  isOrganizer: boolean,
  decoderId,
  status: decoded | empty | explicitly_excluded | unsupported | failed,
  blocks: ContentBlock[],
  diagnostics: Diagnostic[]
}

ReferenceSnapshot {
  snapshotId,               // state identity, never a content digest
  manifest: ReferenceManifest,
  context: ReferenceContextIR,
  sourceMaps[],
  claimLedger[],
  specificationProvenance[]
}

ContentBlock {
  blockId,
  sourceId,
  ordinal,
  sourceLocation,
  contentHandle,
  accountingStatus: extracted | no_feature_claim | blocked
}

SourceCitation {
  sourceId,
  location: line-range | page-region | cell-range | node-path,
  verbatimText?
}

RequirementIndex {
  acceptanceCriteria: Requirement[],
  functionalRequirements: Requirement[],
  edgeCases: Requirement[],
  businessRules: Requirement[],
  scopeGuards: Requirement[]
}

ArtifactProposal<T> {
  artifactKind,
  engineAssignedPath,
  applicability,
  content: T,
  sourceLinks: SourceLink[]
}

ProjectPathCandidate {
  projectId,
  repoRelativePath,
  declaredKind,
  operation: read | create | update | delete,
  declaredBy
}

FileRecord {
  fileId,
  projectId,
  repoRelativePath,
  environmentId,
  kind,
  operation: read | create | update | delete,
  declaredBy,
  source: repository_existing | plan_approved,
  expectedExistence: present | absent
}

TaskGraph {
  tasks: TaskDefinition[],
  dependencies: Edge[],
  sharedResourceLocks: Lock[]
}

TaskRuntimeState {
  taskId,
  status: pending | executing | validation_failed | blocked | completed | needs_reconciliation,
  leaseId?,
  transactionId?,
  evidenceIds[]
}

ChangeProposal {
  taskId,
  operations: FileOperation[],
  explanation
}

VerificationEvidence {
  validatorId,
  commandId?,
  target?,
  status,
  exitCode?,
  boundedOutput?,
  observedAt
}

GeneratedView {
  viewKind: reference_context | plan | research | data_model | contract | quickstart | tasks,
  canonicalStateId,
  engineAssignedPath,
  renderedBytes,
  editableByUser: false
}

ReviewDecision {
  stage: plan | tasks,
  decision: approve | reject,
  canonicalStateId,
  feedback?,
  targetUnitIds[]?,
  decidedAt
}
```

---

<a id="specification-ir"></a>

## 7. Specification IR

```text
SpecificationIR {
  displayName,
  primaryUserStory,
  acceptanceCriteria: { given, when, then, citations[] }[],
  userVisibleOutcomes: { text, citations[] }[],
  edgeCases: { condition, expectedOutcome, citations[] }[],
  functionalRequirements: { text, modality, citations[] }[],
  businessRules: { text, citations[] }[],
  assumptions: { text, citations[] }[],
  nonGoals: { text, citations[] }[],
  prohibitedBehaviors: { text, citations[] }[],
  entities: { name, businessMeaning, relationships[], citations[] }[],
  openQuestions: OpenQuestion[]
}
```

---

<a id="reference-context-ir"></a>

## 8. Reference-context IR

```text
ReferenceContextIR {
  referencedSourceIds[],
  businessSignals[],
  designInteractionSignals[],
  visualTokens: PreservedToken[],
  terminalAndScopeGuards[],
  technicalObservations[],
  validationSignals[],
  implementationAssumptions[],
  conflicts: SourceConflict[],
  openQuestions[]
}
```

---

<a id="plan-ir"></a>

## 9. Plan IR

```text
PlanIR {
  summary,
  minimalChangeHypothesis,
  technicalFactSelections: FactSelection[],
  repositoryFactSelections: FactSelection[],
  technicalRationale,
  constitutionChecks[],
  implementationShape,
  touchedFiles: FileRecord[],
  proposedFiles: FileRecord[],
  rejectedStructureAdditions[],
  artifactManifest: ArtifactDecision[],
  researchDecisions: ResearchDecision[],
  dependencyProposals: DependencyProposal[],
  dataModel?,
  contracts[],
  quickstartScenarios[],
  coverage: CoverageEntry[],
  taskGenerationApproach,
  complexityDeviations[]
}

FactSelection {
  factId,
  selectedValue,
  interpretation
}

ResearchDecision {
  question,
  decision,
  rationale,
  alternatives[],
  evidenceIds[],
  unresolvedExternalEvidence: boolean
}

DependencyProposal {
  ecosystem,
  packageName,
  versionConstraint,
  registrySourceId,
  dependencyScope,
  rationale,
  approval: required | approved | rejected
}
```

---

<a id="artifact-decision"></a>

## 10. Artifact decision

```text
ArtifactDecision {
  kind: research | data_model | quickstart | contract,
  disposition: required | not_applicable,
  reason,
  engineAssignedPath?
}
```

---

<a id="task-ir"></a>

## 11. Task IR

```text
TaskDefinition {
  internalKey,
  phase: setup | verification | implementation | integration | polish,
  kind: setup | automated_verification | manual_verification |
        source_change | integration_change | documentation,
  responsibility,
  description,
  sourceIds[],
  readFileIds[],
  writeFileIds[],
  commandInvocations: CommandInvocation[],
  manualScenarioIds[],
  verificationMode: red_then_green | existing_check | manual_after_change | none,
  requiredEvidence: EvidencePredicate[],
  dependsOnInternalKeys[],
  sharedResources[]
}

CommandInvocation {
  commandId,                 // an available preset/config command ID
  typedArguments,            // closed argument object declared by that command
  origin: engine_required | model_optional
}

EvidencePredicate {
  kind: file_committed | command_passed | command_failed_as_expected |
        source_parsed | imports_resolved | manual_scenario_recorded |
        no_unexpected_changes,
  targetId,
  commandId?,
  expected,
  requiredDiagnosticCode?,
  mustBecomeGreenByTaskId?
}
```

---

<a id="implementation-ir"></a>

## 12. Implementation IR

```text
FileOperation =
  | CreateFile { fileId, completeContent }
  | UpdateFile { fileId, patch }
  | ReplaceFile { fileId, completeContent, expectedTargetState: present_regular_file }
  | CopyFile { sourceId, destinationFileId, expectedTargetState: absent | present_regular_file }
  | DeleteFile { fileId, justification }

CopySource {
  sourceId,
  kind: repository_file | reference_block | approved_template,
  contentHandle,
  mediaType,
  provenance,
  copyPolicyId
}

ChangeProposal {
  taskId,
  operations,
  completionSummary
}
```

---

<a id="diagnostic-contract"></a>

## 13. Diagnostic contract

```text
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
  rule: { source, ruleId, description },
  repairClass: canonicalize | model_atomic | user_input | environment | not_repairable,
  repairUnit?,
  relatedLocations[],
  validatorDependencies[]
}
```

---

<a id="engine-configuration"></a>

## 14. Engine configuration

```json
{
  "$schema": "https://schemas.sddtoolkit.dev/engine/v1.json",
  "schemaVersion": "1.0",
  "paths": {
    "specs": "specs/",
    "references": "references/",
    "specsArchive": "specs/_archive/",
    "sddtoolkit": ".sddtoolkit/"
  },
  "environments": [
    {
      "id": "web",
      "root": ".",
      "presets": [
        "language/typescript@1.0.0",
        "runtime/node@1.0.0",
        "framework/react@1.0.0",
        "build/vite@1.0.0"
      ],
      "overlay": ".sddtoolkit/presets/web.project.yaml"
    }
  ],
  "standards": {
    "constitutionRoots": [".specify/memory/constitution/"],
    "fallback": {
      "mode": "explicit-shipped-defaults",
      "constitutionRoot": ".specify/templates/constitution/"
    },
    "requiredCategories": ["core", "architecture", "testing", "security"]
  },
  "models": {
    "profiles": {
      "nano": {
        "provider": "openai",
        "model": "gpt-5-nano",
        "reasoningEffort": "low",
        "temperature": 0,
        "maxOutputTokens": 4000
      }
    },
    "routes": {
      "reference.extract": "nano",
      "reference.reconcile": "nano",
      "spec.section.generate": "nano",
      "plan.section.generate": "nano",
      "tasks.cluster.generate": "nano",
      "tasks.dependencies.reconcile": "nano",
      "implementation.operation.generate": "nano",
      "repair.structured": "nano",
      "repair.code": "nano",
      "semantic.review": "nano"
    }
  },
  "workflow": {
    "requireOrderedStages": true,
    "standaloneStageRequiresFeatureId": true,
    "maxContextRequestsPerCall": 1,
    "maxModelAttemptsPerUnit": 3,
    "maxRepairAttemptsPerUnit": 2,
    "maxRepairsPerStage": 20,
    "defaultTaskConcurrency": 1,
    "featureIdMaxLength": 64
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
    "maxFileBytes": 10485760,
    "maxTotalBytes": 104857600,
    "unsupportedFormat": "block",
    "encryptedFile": "block",
    "hiddenFiles": "exclude",
    "readers": ["text", "markdown", "json", "yaml", "xml", "csv", "css", "source", "pdf", "image", "office"]
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
    "commandOutputLimitBytes": 1048576
  },
  "state": {
    "persistStageStatus": true,
    "resume": true,
    "canonicalFeatureState": ".sddtoolkit/features/",
    "useFingerprints": false
  },
  "logs": {
    "level": "info",
    "format": "pretty",
    "output": "console",
    "promptLogs": {
      "enabled": false,
      "includeResponse": false,
      "redactSecrets": true,
      "maxResponseLength": 5000,
      "retentionDays": 7
    }
  }
}
```

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
      file: package.json
      pointer: /dependencies/react
  ambiguity: error
```

---

<a id="project-discovery-policy"></a>

## 16. Project discovery policy

```yaml
projectDiscovery:
  adapters: [npm-package-json, npm-workspaces]
  manifestPatterns: [package.json]
  exclude: [node_modules/**, dist/**]
  selection: explicit-or-nearest-owner
```

---

<a id="file-kind-policies"></a>

## 17. File-kind policies

```yaml
fileKinds:
  reactComponent:
    inferencePriority: 200
    operations: [read, create, update]
    roots:
      - patternType: glob
        target: projectRelativePath
        value: src/components/**
    names:
      - patternType: regex
        target: basename
        value: '^[A-Z][A-Za-z0-9]*\.tsx$'
        caseSensitive: true
    extensions: [.tsx]
    generated: false

  unitTest:
    inferencePriority: 300
    operations: [read, create, update]
    roots:
      - patternType: glob
        target: projectRelativePath
        value: src/**
    names:
      - patternType: glob
        target: basename
        value: '*.test.tsx'
        caseSensitive: true
    extensions: [.test.tsx]
    placement:
      mode: co-located
      sourceKinds: [reactComponent]

  config:
    inferencePriority: 100
    operations: [read, update]
    roots:
      - patternType: glob
        target: projectRelativePath
        value: .
    names:
      - patternType: glob
        target: basename
        value: 'vite.config.*'
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
      ephemeralWrites: [dist/**]
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
      ephemeralWrites: [coverage/**, .cache/**]
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
      configPatterns: [tsconfig*.json]
```

---

<a id="generated-and-forbidden-paths"></a>

## 20. Generated and forbidden paths

```yaml
forbiddenPaths:
  - .git/**
  - .sddtoolkit/**
  - node_modules/**

generatedPaths:
  - dist/**
  - coverage/**
```

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
  presetRules: {
    environmentId?,
    projectId?,
    allowedFileKinds?,
    allowedRoots?,
    allowedExtensions?,
    filenamePatterns?,
    testPlacement?,
    availableCommandIds?
  },
  prohibitedAssumptions[],
  responseSchema,
  oneMinimalValidExample
}
```

---

<a id="model-response-envelope"></a>

## 22. Model response envelope

```json
{
  "schemaVersion": "1.0",
  "requestId": "req-123",
  "stage": "tasks",
  "operation": "generate-task-cluster",
  "result": {
    "kind": "task-cluster",
    "payload": {}
  }
}
```

---

<a id="model-context-request"></a>

## 23. Model context request

```json
{
  "kind": "needs-context",
  "contextType": "existing-file-excerpt",
  "pathId": "file-17",
  "reason": "Need the exported function signature"
}
```

---

<a id="orchestrator-composition"></a>

## 24. Orchestrator composition

```text
FeatureWorkflowOrchestrator
├── BootstrapOrchestrator
│   ├── configuration actions
│   ├── preset compilation actions
│   ├── standards ingestion/compilation actions
│   └── repository discovery actions
├── SpecifyOrchestrator
│   ├── SpecifyPreflightOrchestrator
│   ├── ReferenceIngestionOrchestrator (when requested)
│   │   └── ReferenceDocumentOrchestrator (one per file)
│   ├── ValidatedGenerationOrchestrator (one semantic unit at a time)
│   │   └── AtomicRepairOrchestrator (on Invalid)
│   └── ArtifactCommitOrchestrator
├── PlanOrchestrator
│   ├── StageGateOrchestrator
│   ├── RepositoryAnalysisOrchestrator
│   ├── ValidatedGenerationOrchestrator (one plan unit at a time)
│   │   └── AtomicRepairOrchestrator
│   ├── ArtifactCommitOrchestrator
│   └── UserReviewOrchestrator (approve or targeted rejection feedback)
├── TasksOrchestrator
│   ├── StageGateOrchestrator
│   ├── ObligationIndexOrchestrator
│   ├── ValidatedGenerationOrchestrator (one obligation cluster at a time)
│   │   └── AtomicRepairOrchestrator
│   ├── TaskGraphOrchestrator
│   ├── ArtifactCommitOrchestrator
│   └── UserReviewOrchestrator (approve or targeted rejection feedback)
└── ImplementOrchestrator
    ├── StageGateOrchestrator
    ├── TaskSchedulingOrchestrator
    │   └── ImplementTaskOrchestrator (one ready task)
    │       ├── TaskChangePlanningOrchestrator
    │       ├── ValidatedGenerationOrchestrator (one file operation)
    │       │   └── AtomicRepairOrchestrator
    │       ├── TaskValidationOrchestrator
    │       └── TaskCommitOrchestrator
    └── FinalValidationOrchestrator
```

---

<a id="bootstrap-flow"></a>

## 25. Bootstrap flow

```text
Locate workspace
  -> read/parse/validate engine config
  -> read/parse/validate every selected preset and overlay
  -> compile preset set
  -> discover projects and manifests
  -> validate configured environment against repository evidence
  -> resolve/read/parse project standards
  -> compile mechanical standards and index prose standards
  -> validate standards/preset/repository consistency
  -> validate parser/query resources
  -> validate command capabilities
  -> create or load run metadata
  -> expose immutable CompiledEnginePolicy
```

---

<a id="reference-reader-contract"></a>

## 26. Reference reader contract

```text
interface ReferenceReader {
  id
  supportedMediaTypes
  probe(entry, bytesPrefix) -> confidence
  decode(entry, boundedStream) -> DecodedReference
}

DecodedReference {
  sourceId,
  mediaType,
  contentBlocks[],
  machineFacts[],
  exactTokens[],
  sourceMap
}
```

---

<a id="specify-cli-contract"></a>

## 27. Specify CLI contract

```text
sdd specify <feature-description>
  [--ref <reference-folder>]
  [--feature-id <explicit-id>]
```

---

<a id="repair-authorization"></a>

## 28. Repair authorization

```text
RepairAuthorization {
  authorizationId,
  diagnosticId,
  candidateId,
  candidateRevision,
  operation: replace | insert | delete | replace_group,
  targetPointers[],
  expectedValues[],
  collectionKeyOrAnchor?,
  replacementSchema,
  immutableSiblingPointers[],
  impactedValidatorIds[],
  attempt,
  maxAttempts
}
```

---

<a id="repair-request"></a>

## 29. Repair request

```json
{
  "repairRequest": {
    "authorizationId": "repair-auth-9",
    "candidateRevision": 4,
    "diagnosticId": "diag-41",
    "code": "PATH_FILENAME_PATTERN_INVALID",
    "targetPointer": "/files/file-3/path",
    "actual": "src/components/login-form.tsx",
    "expected": {
      "kind": "reactComponent",
      "roots": ["src/components/**"],
      "basenameRegex": "^[A-Z][A-Za-z0-9]*\\.tsx$",
      "extensions": [".tsx"]
    }
  },
  "responseSchema": {
    "authorizationId": "repair-auth-9",
    "candidateRevision": 4,
    "diagnosticId": "diag-41",
    "replacements": ["string"]
  }
}
```

---

<a id="repair-response"></a>

## 30. Repair response

```json
{
  "authorizationId": "repair-auth-9",
  "candidateRevision": 4,
  "diagnosticId": "diag-41",
  "replacements": ["src/components/LoginForm.tsx"]
}
```

---

<a id="workflow-state"></a>

## 31. Workflow state

```json
{
  "schemaVersion": "1.0",
  "featureId": "user-authentication",
  "stage": "tasks_review_pending",
  "environmentIds": ["web"],
  "compiledPresets": [
    "language/typescript@1.0.0",
    "runtime/node@1.0.0",
    "framework/react@1.0.0",
    "build/vite@1.0.0"
  ],
  "reference": {
    "used": true,
    "root": "references/auth",
    "sourceIds": ["source-001", "source-002"]
  },
  "artifacts": {
    "spec": "specs/user-authentication/spec.md",
    "referenceContext": "specs/user-authentication/reference-context.md",
    "plan": "specs/user-authentication/plan.md",
    "tasks": "specs/user-authentication/tasks.md"
  },
  "canonicalState": {
    "reference": {
      "id": "reference-state-1",
      "path": ".sddtoolkit/features/user-authentication/reference.snapshot.json",
      "provenance": ".sddtoolkit/features/user-authentication/spec.provenance.json"
    },
    "plan": {
      "id": "plan-state-1",
      "path": ".sddtoolkit/features/user-authentication/plan.ir.json",
      "inputSpecification": ".sddtoolkit/features/user-authentication/plan-input-spec.ir.json"
    },
    "tasks": {
      "id": "tasks-state-1",
      "path": ".sddtoolkit/features/user-authentication/tasks.ir.json"
    }
  },
  "reviews": {
    "plan": {
      "canonicalStateId": "plan-state-1",
      "decision": "approved"
    },
    "tasks": {
      "canonicalStateId": "tasks-state-1",
      "decision": "pending"
    }
  },
  "taskRuntimeState": ".sddtoolkit/features/user-authentication/tasks.runtime.json",
  "activeTransactionIds": []
}
```

---

<a id="stage-transition-state-machine"></a>

## 32. Stage transition state machine

```text
new
  -> specifying
  -> specified
  -> planning
  -> plan_review_pending
       -> plan_rejected -> planning
       -> plan_approved
  -> planned
  -> tasking
  -> tasks_review_pending
       -> tasks_rejected -> tasking
       -> tasks_approved
  -> tasked
  -> implementing
  -> implemented

specified <- spec_changed <- planned | tasked | implementing
planning <- plan_rework_required <- tasking | implementing
tasking <- tasks_rework_required <- implementing_before_first_commit
tasks_review_pending <- implementation_reconciliation <- implementing_after_commit
```

---

<a id="observability-events"></a>

## 33. Observability events

```text
run.started
stage.started | stage.completed | stage.blocked | stage.failed
action.started | action.completed | action.invalid | action.failed
model.requested | model.completed | model.schema_failed
validation.completed
repair.requested | repair.applied | repair.rejected | repair.exhausted
transaction.staged | transaction.committed | transaction.rolled_back
command.started | command.completed | command.failed
task.started | task.completed | task.blocked | task.failed
```

---

<a id="suggested-package-structure"></a>

## 34. Suggested package structure

```text
engine/
├── interface/
│   ├── cli/
│   └── api/
├── application/
│   ├── actions/
│   │   ├── bootstrap/
│   │   ├── references/
│   │   ├── model/
│   │   ├── artifacts/
│   │   ├── paths/
│   │   ├── validation/
│   │   ├── tasks/
│   │   ├── implementation/
│   │   └── persistence/
│   └── orchestrators/
│       ├── workflow/
│       ├── stages/
│       ├── generation/
│       ├── repair/
│       ├── transactions/
│       └── scheduling/
├── domain/
│   ├── config/
│   ├── preset/
│   ├── workflow/
│   ├── references/
│   ├── specification/
│   ├── planning/
│   ├── tasks/
│   ├── implementation/
│   ├── diagnostics/
│   └── evidence/
├── ports/
│   ├── filesystem/
│   ├── model/
│   ├── process/
│   ├── parser/
│   ├── readers/
│   ├── state/
│   └── telemetry/
├── adapters/
│   ├── filesystem/
│   ├── models/
│   ├── processes/
│   ├── parsers/
│   ├── readers/
│   ├── manifests/
│   └── telemetry/
├── renderers/
├── schemas/
├── presets/
└── tests/
```
