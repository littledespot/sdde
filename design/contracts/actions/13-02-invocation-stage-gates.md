# 13.2 Invocation, feature, and stage-gate actions

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.


## `ParseWorkflowSelectionAction`

- **Input:** captured CLI/API invocation
- **Output:** raw workflow selector plus remaining workflow arguments
- **Responsibility:** Parse exactly one explicit leading workflow selector after the
  executable/API operation; choose no default, inspect no workflow definition, and do not parse
  workflow-specific arguments.

## `ValidateWorkflowIdAction`

- **Input:** raw workflow selector and workflow-ID lexical policy
- **Output:** validated invocation `WorkflowId` plus unchanged remaining arguments
- **Responsibility:** Validate the closed workflow-ID syntax without filename inference,
  registry lookup, normalization fallback, or workflow-specific branching.

## `ParseSpecifyInvocationAction`

- **Input:** remaining workflow arguments
- **Output:** parsed specify invocation
- **Responsibility:** Parse the required `--feature` and `--reference` values without resolving
  paths or reading files.

## `ValidateSpecifyArgumentsAction`

- **Input:** parsed invocation
- **Output:** validated specify invocation context
- **Responsibility:** Require one non-empty `--feature` directory and one non-empty
  `--reference` selector; reject missing, duplicate, positional and unknown inputs.

## `NormalizeReferenceSelectorAction`

- **Input:** validated raw `--reference` value
- **Output:** normalized selector candidate
- **Responsibility:** Decode strict UTF-8 once, normalize NFC and literal separators, and remove
  only literal `.` segments; do not join a root.

## `ValidateReferenceSelectorLexicalSafetyAction`

- **Input:** normalized selector candidate and selector policy
- **Output:** `RelativeReferenceSelector`
- **Responsibility:** Reject empty/dot-only, absolute/drive/UNC/URI/control/NUL, `..`, encoded
  dot/separator, invalid segment, length, and trailing-separator ambiguity before identity or
  root resolution.

## `NormalizeFeatureDirectoryAction`

- **Input:** raw supplied feature directory
- **Output:** normalized `paths.specs`-relative path candidate
- **Responsibility:** Reuse shared path normalization; no slug, transliteration, truncation or
  suffix.

## `ValidateFeatureDirectoryAction`

- **Input:** normalized directory candidate, configured specs/archive roots and shared path
  policy
- **Output:** validated feature-directory selector
- **Responsibility:** Resolve against the configured specs root and enforce lexical safety,
  containment and archive exclusion; no filesystem access or ownership lookup.

## `InspectFeatureDirectoryAction`

- **Input:** validated selector and narrow no-follow filesystem port
- **Output:** absent or directory observation, or typed rejection
- **Responsibility:** Inspect only the selected path and ancestors; reject aliases/unsafe nodes
  without scanning other features.

## `ValidateFeatureBriefProposalAction`

- **Input:** one operation-result-valid feature brief and complete reference
  claim/citation/passive/clarification registries
- **Output:** feature-brief evidence
- **Responsibility:** Prove all reference or resolved-response grounding joins, business-only
  fields, completeness, and absence of unbound path tokens.

## `AssignFeatureRequestIdAction`

- **Input:** durable canonical reference-state ID and compiler-locked singleton `feature_brief`
  request slot
- **Output:** owner-local feature-request identity
- **Responsibility:** Construct `(referenceStateId, feature_brief)` without a run-local
  allocator, model scalar, content, or fingerprint; exactly one exists per reference revision.

## `BuildFeatureRequestAction`

- **Input:** feature-request identity, validated feature brief, validated supplied feature
  directory, exact required selector/snapshot, and validated clarification-response joins
- **Output:** identified reference-derived feature request
- **Responsibility:** Bind title/description/goal and source authorities without minting any
  identity or accepting a model-owned feature/path.

## `AssignFeatureRequestStateIdAction`

- **Input:** feature ID, validated current feature `StateIdLedger`, and matching single-use
  namespace capability
- **Output:** feature-request-state reservation plus successor ledger
- **Responsibility:** Reserve one immutable request-state ID.

## `BuildFeatureRequestStateAction`

- **Input:** state identity, identified request, validated supplied feature directory, exact
  reference snapshot, and exact current clarification registry ID/revision
- **Output:** feature-request state candidate
- **Responsibility:** Bind the validated derived brief/request ID to its immutable
  reference/clarification authorities without minting IDs.

## `AssignWorkflowArtifactRegistryStateIdAction`

- **Input:** feature identity, config version, validated current feature `StateIdLedger`, and
  matching single-use namespace capability
- **Output:** workflow-artifact-registry reservation plus successor ledger
- **Responsibility:** Reserve the immutable artifact-authority state ID before resolving paths.

## `ResolveWorkflowArtifactPathsAction`

- **Input:** registry identity, feature identity, validated config roots, and closed
  selector/path table
- **Output:** workflow-artifact-registry candidate
- **Responsibility:** Calculate every canonical workflow/view/state/log collection path; the
  model supplies none.

## `ValidateWorkflowArtifactRegistryAction`

- **Input:** registry candidate, canonical root-access registry, portability policy, and closed
  required-selector table
- **Output:** workflow-artifact-registry evidence
- **Responsibility:** Prove exact singleton/collection coverage, selector-specific
  `rootAuthority`, root-relative containment, editability/access class, non-overlap, and
  host/target collision safety.
- Require views/forms/logs under `specs_feature`, published-state selectors under their declared
  engine root, and reject interpreting one entry against two bases.

## `SerializeWorkflowArtifactRegistryAction`

- **Input:** validated workflow-artifact registry
- **Output:** canonical registry bytes
- **Responsibility:** Serialize the exact path authority used by restart and rendering.

## `ParseWorkflowArtifactRegistryAction`

- **Input:** raw canonical registry bytes
- **Output:** unvalidated workflow-artifact registry
- **Responsibility:** Parse one persisted artifact authority only.

## `BuildActiveFeatureDirectoryCapabilityAction`

- **Input:** validated supplied feature directory, exact registered artifact/state roots, fresh
  no-follow observations and declared operations
- **Output:** run-local feature-directory capability
- **Responsibility:** Bind only the selected target and authorized operations; no ownership
  record, activation transaction, or successful-output claim.

## `ScanFeatureLogRunInventoryAction`

- **Input:** validated feature log collection paths, active-feature capability, bounded
  no-follow descriptor, and hard segment/heading/control-row limits
- **Output:** raw feature-log run/binding/stream inventory
- **Responsibility:** Enumerate and capture bounded pipe-delimited headings plus
  `segment_header`/`segment_trailer` control rows grouped by their declared run/binding/stream
  without closing, truncating, trusting, or acquiring a stream lock.

## `ValidateHistoricalFeatureLogRunInventoryAction`

- **Input:** raw inventory, fresh current run ID, workflow-artifact/bootstrap-authority lineage,
  segment schemas, and hard limits
- **Output:** ordered historical run-group inventory or diagnostic
- **Responsibility:** Exclude the fresh run, validate every historical binding/policy ID against
  a readable authority in the current lineage, classify each group as active-tail or
  closed-only, and block unknown/corrupt/aliased groups; this does not authorize close.

## `ResolveHistoricalFeatureLogAuthorityAction`

- **Input:** one validated historical group, its log-policy ID, and current bootstrap
  lineage/authority collection
- **Output:** exact historical bootstrap authority and compiled logging fragment
- **Responsibility:** Resolve the policy tuple's bootstrap state, validate its lineage
  reachability and persisted fragment, and never consult current config or choose a path.

## `BuildHistoricalFeatureLogPolicyAction`

- **Input:** validated historical group, resolved historical authority/fragment, feature ID, and
  workflow-artifact registry
- **Output:** historical feature-log-policy candidate
- **Responsibility:** Reconstruct only the exact closed policy tuple recorded in headers;
  perform no binding construction, segment I/O, or current-config lookup.
- The ordinary policy validator then validates it.

## `CloseRecoveredHistoricalFeatureLogStreamAction`

- **Input:** locked active-tail inspection, recovered historical stream state, validated
  historical policy/binding, and matching ordinary single-binding stream-lock capability
- **Output:** `HistoricalFeatureLogTailCloseObservation`
- **Responsibility:** Invoke the typed historical-close port once, fsync a crash-finalization
  trailer, and close exactly one prior-run active tail; create no successor segment.

## `ValidateAlreadyClosedHistoricalFeatureLogStreamAction`

- **Input:** locked closed-only inspection, validated historical policy/binding, and matching
  ordinary stream-lock capability
- **Output:** `AlreadyClosedHistoricalFeatureLogTailObservation`
- **Responsibility:** Validate existing trailers/sequence bounds and prove the prior-run group
  already needs no write; reject an active, missing, or corrupt tail and record `bytesWritten:
  0`.

## `BuildHistoricalFeatureLogStreamFinalizationEvidenceAction`

- **Input:** one exact validated historical inventory group, its matching
  close-or-already-closed observation, and the terminal ordinary stream-lock release observation
- **Output:** one discriminated `HistoricalFeatureLogStreamFinalizationEvidence`
- **Responsibility:** Join the group's ordinal/run/binding/stream/disposition to exactly one
  terminal tail observation and its exact released lock; perform no I/O, validation, or policy
  reconstruction.

## `ValidateHistoricalFeatureLogRunFinalizationAction`

- **Input:** validated historical inventory and the ordered
  `HistoricalFeatureLogStreamFinalizationEvidence` set
- **Output:** `HistoricalFeatureLogRunFinalizationEvidence` or diagnostic
- **Responsibility:** Prove one-to-one ordered group coverage, disposition/observation equality,
  exact binding/run/stream joins, one successful release per acquired prior-run lock, no
  duplicate/orphan evidence, and no remaining prior-run active tail before current-run
  policy/binding construction or sink initialization.

## `BuildFeatureLogPolicyIdAction`

- **Input:** feature ID, exact bootstrap-authority-state ID, that authority's persisted
  compiled-policy config version, and compiler-locked `feature_logging` slot
- **Output:** stable feature-log-policy identity
- **Responsibility:** Construct the closed tuple without consulting the current root config and
  without an allocator, path, content value, clock, user/model scalar, or run-local capability.

## `BuildFeatureLogPolicyAction`

- **Input:** assigned feature-log-policy identity, exact persisted
  `CompiledFeatureLoggingPolicyFragment` from the bound bootstrap authority, event-definition
  registry, feature ID, and workflow-artifact registry
- **Output:** feature-log-policy candidate
- **Responsibility:** Bind the historical/current authority-owned threshold and
  safety/rotation/retention constants to the exact authority-derived ID and engine-derived
  event/prompt collection IDs; never consult a possibly changed root config for an existing
  authority.

## `ValidateFeatureLogPolicyAction`

- **Input:** log-policy candidate and exact bound bootstrap compiled-policy/artifact authorities
- **Output:** feature-log-policy evidence
- **Responsibility:** Recompute and prove the closed ID tuple, persisted fragment equality,
  level rank/aliases, console boolean, prompt-capture selectors, compiler-fixed
  redaction/limits, and fixed per-feature destinations; equal restart inputs must reproduce the
  same policy identity.

## `BuildFeatureLogBindingIdAction`

- **Input:** validated log-policy ID, run ID, workflow-artifact-registry-state ID, and
  compiler-locked `feature_run_logging` slot
- **Output:** stable feature-log-binding identity
- **Responsibility:** Construct the closed tuple without an allocator, path, clock, or
  active-directory capability token.

## `ResolveFeatureLogBindingAction`

- **Input:** assigned feature-log-binding identity, validated feature-log policy, activated
  feature-directory capability, run metadata, and workflow-artifact registry
- **Output:** feature-log binding
- **Responsibility:** Bind one run only to the fixed event/prompt collections beneath
  `canonicalSpecsFeatureRoot/logs`; accept no engine-state-root, config child path, user path,
  or model path.

## `ValidateFeatureLogBindingAction`

- **Input:** binding, root registry, no-follow metadata, bound bootstrap authority, and
  workflow-artifact registry
- **Output:** log-binding evidence
- **Responsibility:** Recompute and prove the closed policy/binding tuple, containment beneath
  the active feature, append-only access class, owner-only mode, regular-file/ancestor safety,
  and exact authority IDs; historical `segment_header` control rows can be rejoined to the same
  tuple after restart.

## `BuildFeatureLogPolicyTransitionAction`

- **Input:** current/successor validated bootstrap authorities, exact change plan/materialized
  evidence whose logging-transition obligation is true, current/successor validated log policies
  and bindings, run metadata, and enabled streams
- **Output:** closed feature-log-policy transition candidate
- **Responsibility:** Bind one same-run old-to-new logging authority switch after any
  compatible/Spec/Plan owning publication; perform no stream I/O and reject absent logging
  impact or administrative changes.

## `ValidateFeatureLogPolicyTransitionAction`

- **Input:** transition candidate, locked impact registry, both policies/bindings, current
  workflow/bootstrap pointer, and successor committed-bootstrap evidence
- **Output:** log-policy-transition evidence
- **Responsibility:** Validate the logging-impact subset and exact old/new fragments while
  accepting other already-validated plan assignments; require `transitionFeatureLogging=true`,
  reject administrative plans, require the same-run segment/record hard caps and format/safety
  fields to remain equal (cap/format changes require a new run or migration), prove
  historical/successor IDs match their authorities, prove the bootstrap successor is durable,
  and represent every enabled stream exactly once.

## `CloseFeatureLogStreamForPolicyTransitionAction`

- **Input:** one validated transition, recovered current stream/sink state, current
  binding/policy, and validated dual-binding transition-stream-lock capability
- **Output:** durable historical-stream trailer/close evidence
- **Responsibility:** Fsync and close exactly one old-binding active segment without creating
  its successor or changing another stream.

## `ValidateClosedHistoricalFeatureLogStreamAction`

- **Input:** old-binding closed-only inspection, historical policy/binding, validated
  transition, and dual-binding transition-stream-lock capability
- **Output:** reconstructed historical-stream close evidence
- **Responsibility:** Validate the already durable `segment_trailer` control row and reproduce
  the same close-boundary observation after a crash; perform no write and reject an active,
  missing, or corrupt tail.

## `BuildTransitionSuccessorFeatureLogStreamStateAction`

- **Input:** historical close evidence, successor-binding ordinal-one segment creation/recovery
  evidence, exact total same-run/all-binding segment count, and successor policy
- **Output:** successor stream-state candidate
- **Responsibility:** Continue sequence at historical final plus one, initialize the successor
  binding's local segment ordinal, and carry the remaining run/stream lifetime segment budget
  without inspecting or writing a segment.

## `ValidateTransitionSuccessorFeatureLogStreamStateAction`

- **Input:** successor stream candidate, transition, old/new segment inventories, policy, and
  dual-binding lock evidence
- **Output:** successor stream evidence
- **Responsibility:** Prove sequence continuity, binding-local ordinal rules, total all-binding
  segment cap, exact old closure/new active tail, and no segment/path/identity reuse.

## `ValidateFeatureLogPolicyTransitionStreamAction`

- **Input:** one historical close evidence, one initialized/recovered successor-binding stream
  state, transition, and the same dual-binding transition-stream-lock capability
- **Output:** one stream-transition evidence
- **Responsibility:** Prove the old binding has no active tail, the new binding has exactly one
  active tail with valid sequence/ordinal origin, and both belong to the exact authorized
  feature/run/stream/binding pair.

## `BuildTransitionSuccessorFeatureLogSinkStateAction`

- **Input:** assigned successor sink-state ID, successor policy/binding, and exactly one
  initialized-or-recovered successor stream state plus inventory for each enabled stream
- **Output:** successor transition sink-state candidate
- **Responsibility:** Assemble the mixed post-crash/new-stream set into one complete successor
  sink without inspecting, closing, creating, or recovering a segment.

## `ValidateTransitionSuccessorFeatureLogSinkStateAction`

- **Input:** successor sink candidate, validated transition, complete stream-transition
  evidence, successor policy/binding, and segment inventories
- **Output:** successor transition sink evidence
- **Responsibility:** Prove total enabled-stream coverage, exact new binding/policy, unique
  active tails, sequence/ordinal rules, and equality to every per-stream transition result.

## `ActivateFeatureLogPolicyTransitionAction`

- **Input:** validated transition, complete ordered stream-transition evidence, validated
  successor sink state/evidence, and runner logging coordinator
- **Output:** active successor-sink capability
- **Responsibility:** Atomically swap only the run-local logging observer pointer after every
  enabled stream is safe; consume no filesystem port and emit no event itself.

## `InspectFeatureLogStreamAction`

- **Input:** validated binding, one enabled stream, and a matching held operation-lock
  capability (single-binding normally; exact old/new side of a validated transition capability
  during switch)
- **Output:** no-existing, existing-active-tail, or existing-closed-only result
- **Responsibility:** Determine one binding/stream startup or transition-recovery branch from
  validated pipe-delimited headings and segment control rows without creating, truncating,
  recovering, or inventing an active tail.

## `AssignFeatureLogSinkStateIdAction`

- **Input:** feature/run/binding identity and run-local sink allocator
- **Output:** log-sink-state identity
- **Responsibility:** Assign the one run-local sink ID without inspecting files.

## `AssignFeatureLogSegmentIdAction`

- **Input:** binding, stream, exact ordinal, and per-run segment allocator
- **Output:** segment identity
- **Responsibility:** Assign one segment ID for initialization or rotation without creating a
  file.

## `CreateInitialFeatureLogSegmentAction`

- **Input:** no-existing evidence, ordinal-one segment identity, validated binding/policy, exact
  `feature-log/v2` stream-column schema, matching held operation-lock capability, and trusted
  clock
- **Output:** exclusive-create/header evidence
- **Responsibility:** Under the exact binding/stream authorization—including only the successor
  side of a dual-binding transition—create exactly one owner-only no-follow regular `.log`
  segment whose first row is the canonical pipe-delimited column heading and whose second row is
  one durable `segment_header` control row under that heading; fail on a race, pre-existing
  alias, or header/control-row write/flush failure.

## `BuildInitialFeatureLogStreamStateAction`

- **Input:** enabled stream and ordinal-one segment creation evidence
- **Output:** revision-zero stream state
- **Responsibility:** Initialize sequence one, active ordinal one, zero body bytes, and no
  durable event sequence.

## `BuildInitialFeatureLogSegmentRecordAction`

- **Input:** segment identity and creation/header evidence
- **Output:** active ordinal-one segment record
- **Responsibility:** Project one created segment into inventory metadata.

## `BuildInitialFeatureLogSinkStateAction`

- **Input:** sink identity, binding/policy, all enabled initial stream states, and initial
  segment records
- **Output:** initialized log-sink state
- **Responsibility:** Assemble one new-run sink state; create or recover no files.

## `RecoverFeatureLogTailAction`

- **Input:** existing-segments result, validated binding/policy, exact `feature-log/v2`
  stream-column schema, and one matching held operation-lock capability
- **Output:** recovered stream state and segment records
- **Responsibility:** Validate the exact first pipe-delimited column-header row, one matching
  durable `segment_header` control row, every complete event/prompt row, and any final
  `segment_trailer` control row for one binding/stream (the old or successor side when
  transition-authorized); truncate only an incomplete final event/prompt row, while a
  missing/duplicate/mismatched heading/control row, wrong column count, malformed interior row,
  or other interior corruption blocks new work.

## `BuildRecoveredFeatureLogSinkStateAction`

- **Input:** sink identity, binding/policy, and every recovered enabled stream/inventory
- **Output:** recovered log-sink state
- **Responsibility:** Assemble one restart sink state without touching a segment.

## `BuildFeatureLogRetentionAuthorizationAction`

- **Input:** recovered closed segments, trusted clock, and validated policy
- **Output:** single-use retention authorization
- **Responsibility:** Select oldest eligible closed segments deterministically and exclude every
  active segment.

## `PruneFeatureLogSegmentAction`

- **Input:** one retention authorization, matching feature-log binding, and matching held
  stream-lock capability
- **Output:** prune evidence
- **Responsibility:** Under the exact binding/stream lock, delete only the authorized closed
  segments; this is the sole log-retention deletion action.

## `ReadWorkflowStateAction`

- **Input:** feature ID
- **Output:** persisted stage metadata or none
- **Responsibility:** Read state only.

## `AssignWorkflowStateIdAction`

- **Input:** feature ID, optional prior workflow state, validated current feature
  `StateIdLedger`, and matching single-use namespace capability
- **Output:** workflow-state reservation plus successor ledger
- **Responsibility:** Reserve one immutable workflow-state revision ID.

## `BuildInitialWorkflowStateAction`

- **Input:** selected `specify` `WorkflowId` and compiled-graph evidence, new
  feature/artifact/bootstrap/principle/actor/review-decision/workflow-control-event/passive/clarification
  authorities, and empty open-clarification/active-approval projections
- **Output:** pre-snapshot `specifying` workflow-state candidate
- **Responsibility:** Construct the first persisted state with the selected workflow as its sole
  bound workflow ID and no `currentReferenceStateId`; no other state may omit that pointer.

## `ValidateStageOrderAction`

- **Input:** requested stage and state
- **Output:** stage authorization
- **Responsibility:** Enforce predecessor order.

## `ValidateRequiredArtifactPresenceAction`

- **Input:** one required artifact identity
- **Output:** presence evidence
- **Responsibility:** Check one required artifact exists.

## `ValidateRequiredArtifactReadabilityAction`

- **Input:** one required artifact identity
- **Output:** readability evidence
- **Responsibility:** Check one required artifact is readable.

## `ValidateWorkflowMetadataAction`

- **Input:** one stage metadata invariant
- **Output:** metadata evidence
- **Responsibility:** Validate one reference/state/artifact expectation.

## `BuildNextStageStateAction`

- **Input:** next workflow identity, validated stage result, current state, and exact current
  authority/open-clarification/active-approval/control-event projections
- **Output:** next-state payload
- **Responsibility:** Build one state transition for inclusion in the complete workflow output;
  never synthesize an approval or active final/rework pointer.

## `ValidateWorkflowStateAction`

- **Input:** workflow-state candidate, prior revision if any, selected compiled workflow,
  artifact/bootstrap/principle/actor/review-decision/workflow-control-event/passive/clarification/plan-input/stage
  authorities, and transition table
- **Output:** workflow-state evidence
- **Responsibility:** Prove monotonic revision, legal transition, sorted unique bound workflow
  IDs, exact retention plus addition of the selected workflow ID when it first participates,
  direct resolution of every bound ID in the current bootstrap registry, exact current IDs/open
  sets/active approvals/final-rework pointers, stage-valid plan-input presence/absence, and no
  dangling authority.
- A missing reference pointer is valid only for the newly activated `specifying` revision with
  empty clarification history and no feature request/specification.

## `ParseWorkflowStateAction`

- **Input:** raw workflow-state bytes
- **Output:** unvalidated workflow state
- **Responsibility:** Parse one persisted revision only.

## `SerializeWorkflowStateAction`

- **Input:** validated workflow state
- **Output:** canonical workflow bytes
- **Responsibility:** Serialize one restart authority.
