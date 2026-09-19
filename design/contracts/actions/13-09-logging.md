# 13.9 Feature logging actions

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.


The runner-owned logging observer submits trusted lifecycle events attributed
through the active compiled workflow's runner-created `WorkflowLog` and applied
`WorkflowTelemetryFact`s to these ordinary common-interface actions. Their
contract IDs are the only compiler-locked instrumentation-internal IDs and are
not observed recursively. The logging orchestrator coordinates them but has no
clock, filesystem, redaction, serializer, or sink port itself.

[ADR 0018](../../decisions/0018-debug-model-exchange-logging.md) makes production
activation a selected-graph operation: `activate-feature-logging` runs after
preflight, materializes only the observed selected target and registered log layout,
then installs the composition-owned active runner. It returns fresh directory
observations backed by a run-local capability. It grants no model or workflow
completion authority.

The common runner closes active logging before a registered `workflow_publication`
operation can write outputs. A common terminal child binding closes all other
outcomes and reports close failures before releasing the sink. Ordinary filesystem
writes do not imply workflow publication. Both barriers use the same finalization
owner and cannot finalize twice or discard an earlier logging failure.

## `AcquireFeatureLogStreamLockAction`

- **Input:** validated current feature-log binding and exact stream
- **Output:** raw current-binding lock observation or contention diagnostic
- **Responsibility:** Ask the sink adapter once for the exclusive physical `(featureId, runId,
  stream)` lock; the binding supplies feature/run but is not part of physical lock identity.
- Use the compiler-fixed 2,000 ms deadline with no retry/backoff and perform no inspect/write.

## `ValidateFeatureLogStreamLockAction`

- **Input:** raw lock observation, binding/stream, adapter registry, process instance, and
  runner lock table
- **Output:** runner-held stream-lock capability or typed rejection retaining the transient
  observation handle
- **Responsibility:** Prove exact owner/binding/adapter/token uniqueness; keep the opaque token
  out of envelopes, serialization, telemetry, and model/log data.

## `ReleaseRejectedFeatureLogStreamLockObservationAction`

- **Input:** validation rejection and the exact runner-retained raw observation returned by the
  same acquisition call
- **Output:** rejected-lock cleanup observation
- **Responsibility:** Ask the adapter to release-or-confirm-not-owned, destroy the opaque token,
  and prove no runner lock-table entry exists before emitting the terminal diagnostic; accept no
  serialized/model-provided observation.

## `ReleaseFeatureLogStreamLockAction`

- **Input:** runner-held stream-lock capability and terminal stream operation outcome
- **Output:** release observation
- **Responsibility:** Release exactly one held lock on every success/error/cancel branch;
  process death relies on adapter/OS ownership release and the next run reacquires before
  recovery.

## `BuildFeatureLogPolicyTransitionStreamLockCapabilityAction`

- **Input:** validated feature-log-policy transition, still-held current-binding stream-lock
  capability, exact stream, process instance, and runner lock table
- **Output:** nonauthorizing dual-binding transition-lock candidate
- **Responsibility:** Propose rebinding the already-held physical lock to the transition's exact
  current/successor binding IDs without acquiring a token and without consuming/releasing the
  ordinary capability.

## `ValidateFeatureLogPolicyTransitionStreamLockCapabilityAction`

- **Input:** transition-lock candidate, the still-held ordinary capability, transition evidence,
  both bindings, adapter/process identity, and runner lock table
- **Output:** validated dual-binding transition-stream-lock capability, or rejection retaining
  the releasable ordinary capability
- **Responsibility:** Prove one live physical `(featureId,runId,stream)` token, exact old/new
  binding pair, stream membership, and no alias; only the success branch atomically
  consumes/invalidates the ordinary capability and installs the dual capability in the runner
  table.

## `ReleaseFeatureLogPolicyTransitionStreamLockAction`

- **Input:** dual-binding transition-stream-lock capability and terminal old/new
  stream-transition outcome
- **Output:** typed dual-binding transition-lock release observation
- **Responsibility:** Release the one wrapped physical token exactly once on
  success/error/cancel, prove the runner-table entry absent, and invalidate both exact binding
  authorizations.

## `ResolveLogEventDefinitionAction`

- **Input:** trusted runner lifecycle/telemetry-fact kind and exact definition registry
- **Output:** event definition
- **Responsibility:** Resolve the engine-owned canonical severity, template, and field schema;
  ignore any caller-suggested wording/level.

## `BuildLogEventDraftAction`

- **Input:** trusted run/node context, runner binding for the active compiled workflow's
  validated `WorkflowShortcode`, resolved definition, and typed fact/lifecycle data
- **Output:** schema-shaped event draft
- **Responsibility:** Retain the exact registry-validated workflow attribution and project only
  definition-allowed IDs/enums/counts; omit diagnostic message/expected/actual and all raw
  content.

## `RedactLogFieldAction`

- **Input:** one potentially-sensitive draft field and mandatory redaction registry
- **Output:** redacted or omitted field plus evidence
- **Responsibility:** Apply the field-definition-owned classification and remove secrets; a
  producer cannot label a field public.

## `EvaluateLogThresholdAction`

- **Input:** canonical event level and configured canonical threshold
- **Output:** emit/drop decision
- **Responsibility:** Emit exactly when `rank(event) >= rank(threshold)` using `fatal=60`,
  `error=50`, `warning=40`, `info=30`, `debug=20`, `trace=10`.

## `AssignLogEventSequenceAction`

- **Input:** emitted schema-shaped draft with validated workflow attribution, resolved
  definition, redacted fields, trusted clock/monotonic source, and matching per-run/per-stream
  sink state
- **Output:** identified ordered `LogEvent`
- **Responsibility:** Retain the exact registry-validated shortcode from the active
  compiled-workflow binding and assign canonical level/template, timestamp, event ID, and the
  next stream sequence only after filtering/redaction.

## `ValidateSafeLogRecordAction`

- **Input:** identified event, exact definition/policy, exact `feature-log/v2` stream-column
  schema, safe fields, and optional canonically ordered sanitized prompt fragments
- **Output:** one or more `ValidatedSafeLogRecord`s
- **Responsibility:** Prove schema, field types, complete one-to-one field-to-column coverage,
  required/optional/null rules, redaction evidence, stream/payload discrimination, UTF-8 safety,
  and maximum encoded row size; create one scalar-only prompt record per selected fragment in
  `promptBodyFragmentId` order.

## `SerializeFeatureLogRecordAction`

- **Input:** validated safe log record and exact `feature-log/v2` fixed-header pipe-delimited
  serializer
- **Output:** one complete pipe-delimited data-row frame
- **Responsibility:** Encode values in the exact registered column order using the canonical
  UTF-8 pipe-delimited dialect and one final LF; emit no header, omit no column, and never split
  a row.

## `BuildFeatureLogSegmentInventoryAction`

- **Input:** validated pipe-delimited headings, `segment_header`/`segment_trailer` control rows,
  and recovered final event/prompt rows for one binding under a validated stream-lock capability
- **Output:** segment inventory candidate
- **Responsibility:** Reconstruct stream/ordinal/sequence/bytes/created/closed metadata without
  using filesystem modification time.

## `ValidateFeatureLogSegmentInventoryAction`

- **Input:** segment inventory candidate, binding, sink state, and policy
- **Output:** segment-inventory evidence
- **Responsibility:** Prove unique contiguous ordinals, one active segment per enabled stream,
  sequence monotonicity, byte limits, and closed-time iff rules.

## `BuildFeatureLogRunStreamSegmentAccountAction`

- **Input:** all validated binding-local segment inventories for one feature/run/stream and
  exact policy cap
- **Output:** run-stream segment-account candidate
- **Responsibility:** Sort binding inventories and total their immutable records without
  inspecting files or authorizing rotation.

## `ValidateFeatureLogRunStreamSegmentAccountAction`

- **Input:** account candidate, raw run inventory, all binding/inventory evidence, and
  current/historical policies
- **Output:** run-stream segment-budget evidence
- **Responsibility:** Prove total binding coverage, no segment/path alias, one active tail
  across bindings after transition, nonnegative remaining count, and lifetime total at or below
  the unchanged cap.

## `EvaluateFeatureLogRotationNeedAction`

- **Input:** encoded pipe-delimited row size, current sink state, and validated segment limits
- **Output:** append decision, rotation-required request with next ordinal, or
  `LOG_SEGMENT_LIMIT_EXHAUSTED` diagnostic
- **Responsibility:** Decide fit/cap only, including required trailer/next-heading/control-row
  capacity.
- The hard count is per `(featureId, runId, stream)`, ordinals are never reused, and retention
  cannot reclaim an active-run ordinal.

## `BuildLogRotationAuthorizationAction`

- **Input:** one rotation-required request, matching preassigned next-segment identity, current
  sink state, and validated segment limits
- **Output:** single-use rotation authorization
- **Responsibility:** Embed the exact next segment identity and bind its binding/stream/ordinal
  plus compare-and-swap state without reevaluating fit or assigning an ID.

## `RotateFeatureLogSegmentAction`

- **Input:** rotation authorization, matching binding/state, exact `feature-log/v2`
  stream-column schema, and validated stream-lock capability
- **Output:** next segment state
- **Responsibility:** Under the exact held lock, validate the embedded next identity,
  write/fsync the old segment's `segment_trailer` control row, exclusive-create the next
  owner-only `.log` file, and durably write its exact first column-heading row plus one
  `segment_header` control row before any event/prompt row.

## `AppendFeatureLogRecordAction`

- **Input:** complete pipe-delimited event/prompt row, validated binding, expected
  sequence/segment state, flush policy, and matching stream-lock capability
- **Output:** append evidence and next sink state
- **Responsibility:** Append exactly one LF-terminated row under the held lock and
  compare-and-swap expected state; never append or repeat a heading, and fsync when the bound
  policy requires it.

## `DestroyRawPromptLogHandlesAction`

- **Input:** transient fragment-manifest/candidate/sanitized handle set plus terminal
  emit/drop/error outcome
- **Output:** destruction evidence
- **Responsibility:** Release every raw, redacted, and split fragment handle on every
  branch, including selection/redaction/splitting/validation failure; no emitted record is a
  precondition.

## `EmitEmergencyLogFailureRecordAction`

- **Input:** validated workflow shortcode, closed sink failure code, and fixed emergency adapter
- **Output:** emergency-write evidence
- **Responsibility:** Attempt exactly one direct stderr write of `SDDE_LOG_FAILURE
  workflow=<CODE> level=fatal code=<FAILURE_CODE>\n`, bounded to 128 ASCII bytes; add no
  fields/content, retry, sink invocation, allocation from failed content, or recursive logging.

## `BuildLoggingBlockedControlAction`

- **Input:** sink failure, cleanup and bounded emergency evidence
- **Output:** fail-closed block result
- **Responsibility:** End the atomic execution before new work; no transaction stabilization or
  recovery.
