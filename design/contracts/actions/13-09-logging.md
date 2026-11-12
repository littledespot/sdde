# 13.9 Feature logging actions

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.

One entry per registered operation; reads and writes are its `NodeContract` data keys.
[F0002](../../features/F0002-LogService.md) owns the logging contract (events, record format,
segments, locks and the emergency record) and [§26.5](../26-security.md) the levels and emission
rule. The runner-owned logging observer submits trusted lifecycle events and applied
`WorkflowTelemetryFact`s to these operations; their IDs are not observed recursively, and the
logging orchestrator has no clock, filesystem, redaction, serializer or sink port.
[ADR 0018](../../decisions/0018-debug-model-exchange-logging.md#production-activation-and-finalization)
owns activation and finalization: one owner finalizes logging before a registered
`workflow_publication` operation writes, and the terminal binding finalizes every other outcome.
Under [ADR 0032](../../decisions/0032-engine-routines.md) (feature logging not yet implemented) these operations
become the steps of a feature-logging engine routine.

## Policy

The `canonicalize_log_level` and `validate_logging_policy` steps of the startup routine
([`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig)) own
configured-level canonicalization and logging-policy compilation; both reject
`LoggingPolicyInvalid`.

## `ValidateFeatureLogPolicyTransitionAction` (`validate-feature-log-policy-transition`)

- **Owner:** [`src/actions/log/validate_feature_log_policy_transition.zig`](../../../src/actions/log/validate_feature_log_policy_transition.zig)
- **Reads:** `feature_log_binding`, `logging_policy` · **Writes:** `feature_log_policy_transition_authority` · **Side effect:** `none`
- **Does:** Admits a switch to a new binding and policy in the same feature and run, with a new binding ID and policy ID and a transition-compatible policy.
- **Rejects:** `InvalidFeatureLogPolicyTransition`.

## `ValidateFeatureLogFinalizationAction` (`validate-feature-log-finalization`)

- **Owner:** [`src/actions/log/validate_feature_log_finalization.zig`](../../../src/actions/log/validate_feature_log_finalization.zig)
- **Reads:** `feature_log_runtime_status` · **Writes:** `feature_log_finalization_authority` · **Side effect:** `none`
- **Does:** Admits finalization: an active binding must be prepared, and a retired one is never finalized.
- **Rejects:** `InvalidFeatureLogFinalization`.

## Records

## `ReadTrustedLogClockAction` (`read-trusted-log-clock`)

- **Owner:** [`src/actions/log/read_trusted_log_clock.zig`](../../../src/actions/log/read_trusted_log_clock.zig)
- **Reads:** none · **Writes:** `trusted_log_clock` (UTC and monotonic time) · **Side effect:** `none`
- **Rejects:** `LogClockReadFailure`.

## `ValidateLogEventFactAction` (`validate-log-event-fact`)

- **Owner:** [`src/actions/log/validate_log_event_fact.zig`](../../../src/actions/log/validate_log_event_fact.zig)
- **Reads:** `workflow_telemetry_fact` · **Writes:** `log_event_definition` · **Side effect:** `none`
- **Does:** Validates a telemetry fact against the event registry and resolves its definition (level, emission, fields).
- **Rejects:** `InvalidLogEventFact`.

## `EvaluateLogThresholdAction` (`evaluate-log-threshold`)

- **Owner:** [`src/actions/log/evaluate_log_threshold.zig`](../../../src/actions/log/evaluate_log_threshold.zig)
- **Reads:** `logging_policy`, `log_event_definition` · **Writes:** `log_emit_decision` · **Side effect:** `none`
- **Does:** Emits an event the registry marks `always`, and otherwise applies the configured threshold ([§26.5](../26-security.md)), before any identity or sink work.
- **Rejects:** none (`drop` is a decision).

## `BuildLogEventRecordAction` (`build-log-event-record`)

- **Owner:** [`src/actions/log/build_log_event_record.zig`](../../../src/actions/log/build_log_event_record.zig)
- **Reads:** `feature_log_binding`, `feature_log_stream_state`, `trusted_log_clock`, `workflow_telemetry_fact` · **Writes:** `identified_log_event` · **Side effect:** `none`
- **Does:** Identifies an emitted event with its binding, workflow shortcode, event ID, the stream's next sequence and the trusted time.
- **Rejects:** `InvalidLogEvent`.

## `SerializeEventLogRecordAction` (`serialize-event-log-record`)

- **Owner:** [`src/actions/log/serialize_event_log_record.zig`](../../../src/actions/log/serialize_event_log_record.zig)
- **Reads:** `identified_log_event` · **Writes:** `serialized_log_record` · **Side effect:** `none`
- **Does:** Encodes one event as a complete fixed-column pipe-delimited row.
- **Rejects:** `LogSerializationFailure`.

## `ValidatePromptLogFragmentAction` (`validate-prompt-log-fragment`)

- **Owner:** [`src/actions/log/validate_prompt_log_fragment.zig`](../../../src/actions/log/validate_prompt_log_fragment.zig)
- **Reads:** `sanitized_prompt_fragment` · **Writes:** `validated_prompt_fragment` · **Side effect:** `none`
- **Rejects:** `InvalidPromptLogFragment` ([ADR 0018](../../decisions/0018-debug-model-exchange-logging.md) fragment rules).

## `EvaluatePromptLogCaptureAction` (`evaluate-prompt-log-capture`)

- **Owner:** [`src/actions/log/evaluate_prompt_log_capture.zig`](../../../src/actions/log/evaluate_prompt_log_capture.zig)
- **Reads:** `logging_policy`, `validated_prompt_fragment` · **Writes:** `prompt_capture_decision` · **Side effect:** `none`
- **Does:** Captures prompt fragments only when the policy's level enables prompt capture.
- **Rejects:** none (`drop` is a decision).

## `BuildPromptLogRecordAction` (`build-prompt-log-record`)

- **Owner:** [`src/actions/log/build_prompt_log_record.zig`](../../../src/actions/log/build_prompt_log_record.zig)
- **Reads:** `feature_log_binding`, `feature_log_stream_state`, `trusted_log_clock`, `validated_prompt_fragment` · **Writes:** `identified_prompt_log` · **Side effect:** `none`
- **Does:** Identifies a captured fragment with its binding, event ID, next sequence and trusted time.
- **Rejects:** `InvalidPromptLogRecord`.

## `SerializePromptLogRecordAction` (`serialize-prompt-log-record`)

- **Owner:** [`src/actions/log/serialize_prompt_log_record.zig`](../../../src/actions/log/serialize_prompt_log_record.zig)
- **Reads:** `identified_prompt_log` · **Writes:** `serialized_log_record` · **Side effect:** `none`
- **Does:** Encodes one prompt fragment as a complete pipe-delimited row.
- **Rejects:** `LogSerializationFailure`.

## `SerializeFeatureLogControlRecordAction` (`serialize-feature-log-control-record`)

- **Owner:** [`src/actions/log/serialize_feature_log_control_record.zig`](../../../src/actions/log/serialize_feature_log_control_record.zig)
- **Reads:** `feature_log_binding`, `feature_log_stream_state`, `trusted_log_clock` · **Writes:** `serialized_log_control_record` · **Side effect:** `none`
- **Does:** Encodes a `segment_header` or `segment_trailer` control row, and measures its length for rotation.
- **Rejects:** `LogSerializationFailure`.

## `WriteConsoleLogRecordAction` (`write-console-log-record`)

- **Owner:** [`src/actions/log/write_console_log_record.zig`](../../../src/actions/log/write_console_log_record.zig)
- **Reads:** `serialized_log_record` · **Writes:** none · **Side effect:** `filesystem_write`
- **Does:** Mirrors one serialized row to the console sink when the policy enables it.
- **Rejects:** `ConsoleLogWriteFailure`.

## Streams and segments

## `feature_logging_workflow.Activate` (`activate-feature-logging`)

- **Owner:** [`src/application/feature_logging_workflow.zig`](../../../src/application/feature_logging_workflow.zig) (through [`ports/feature_log_activation.zig`](../../../src/ports/feature_log_activation.zig))
- **Reads:** `feature_directory` · **Writes:** `activated_feature_directory` · **Side effect:** `filesystem_write`
- **Does:** Activates the run's feature logging for the resolved feature directory under the workflow's shortcode, and publishes the directory as activated ([ADR 0018](../../decisions/0018-debug-model-exchange-logging.md)).
- **Rejects:** outcomes `blocked` and `cancelled` from the port; a missing port fails.

## `AcquireFeatureLogStreamLockAction` (`acquire-feature-log-stream-lock`)

- **Owner:** [`src/actions/log/acquire_feature_log_stream_lock.zig`](../../../src/actions/log/acquire_feature_log_stream_lock.zig)
- **Reads:** `feature_log_binding` · **Writes:** `feature_log_stream_lock` · **Side effect:** `filesystem_write`
- **Does:** Makes one attempt for the stream's exclusive lock within the fixed deadline, with no retry ([F0002](../../features/F0002-LogService.md)).
- **Rejects:** `LogLockTimeout` (`LOG_LOCK_TIMEOUT`) only for a lock held elsewhere; every other sink fault is `LogSinkFailure` (`LOG_SINK_FAILURE`).

## `ReleaseFeatureLogStreamLockAction` (`release-feature-log-stream-lock`)

- **Owner:** [`src/actions/log/release_feature_log_stream_lock.zig`](../../../src/actions/log/release_feature_log_stream_lock.zig)
- **Reads:** `feature_log_stream_lock` · **Writes:** invalidates `feature_log_stream_lock` · **Side effect:** `filesystem_write`
- **Rejects:** `LogReleaseFailure`.

## `CreateFeatureLogSegmentAction` (`create-feature-log-segment`)

- **Owner:** [`src/actions/log/create_feature_log_segment.zig`](../../../src/actions/log/create_feature_log_segment.zig)
- **Reads:** `feature_log_binding`, `feature_log_stream_lock` · **Writes:** `feature_log_stream_state` · **Side effect:** `filesystem_write`
- **Does:** Creates a stream's first segment with its column heading and `segment_header` row.
- **Rejects:** `LogSinkFailure`.

## `RecoverFeatureLogStreamAction` (`recover-feature-log-stream`)

- **Owner:** [`src/actions/log/recover_feature_log_stream.zig`](../../../src/actions/log/recover_feature_log_stream.zig)
- **Reads:** `feature_log_binding`, `feature_log_stream_lock` · **Writes:** `feature_log_stream_state` · **Side effect:** `filesystem_write`
- **Does:** Recovers an existing stream's state from its segments under the held lock.
- **Rejects:** `LogSinkFailure`.

## `EvaluateFeatureLogRotationNeedAction` (`evaluate-feature-log-rotation-need`)

- **Owner:** [`src/actions/log/evaluate_feature_log_rotation_need.zig`](../../../src/actions/log/evaluate_feature_log_rotation_need.zig)
- **Reads:** `feature_log_stream_state`, `serialized_log_record`, `serialized_log_control_record` · **Writes:** `log_rotation_decision` · **Side effect:** `none`
- **Does:** Decides `append` when the row and trailer fit the segment, `rotate` to the next ordinal otherwise, and `exhausted` at the segment-count cap or when the row can't fit a new segment.
- **Rejects:** none; `exhausted` leads to `LOG_SEGMENT_LIMIT_EXHAUSTED`.

## `RotateFeatureLogSegmentAction` (`rotate-feature-log-segment`)

- **Owner:** [`src/actions/log/rotate_feature_log_segment.zig`](../../../src/actions/log/rotate_feature_log_segment.zig)
- **Reads:** `feature_log_binding`, `feature_log_stream_lock`, `feature_log_stream_state` · **Writes:** replaces `feature_log_stream_state` · **Side effect:** `filesystem_write`
- **Does:** Writes the old segment's trailer and creates the next segment with its heading and header, under the held lock.
- **Rejects:** `LogSinkFailure`.

## `EvaluateFeatureLogFlushNeedAction` (`evaluate-feature-log-flush-need`)

- **Owner:** [`src/actions/log/evaluate_feature_log_flush_need.zig`](../../../src/actions/log/evaluate_feature_log_flush_need.zig)
- **Reads:** `logging_policy`, `feature_log_stream_state`, `trusted_log_clock` · **Writes:** `log_flush_decision` · **Side effect:** `none`
- **Does:** Flushes at or above the policy's flush level, on a terminal stage or task event, or when the buffered record count or interval reaches its limit; otherwise buffers.
- **Rejects:** none.

## `AppendFeatureLogRecordAction` (`append-feature-log-record`)

- **Owner:** [`src/actions/log/append_feature_log_record.zig`](../../../src/actions/log/append_feature_log_record.zig)
- **Reads:** `feature_log_binding`, `feature_log_stream_lock`, `feature_log_stream_state`, `serialized_log_record` · **Writes:** `feature_log_append_evidence` · **Side effect:** `filesystem_write`
- **Does:** Appends one row under the held lock, flushing when decided.
- **Rejects:** `LogFlushFailure`, `LogSinkFailure`.

## `AdvanceFeatureLogStreamStateAction` (`advance-feature-log-stream-state`)

- **Owner:** [`src/actions/log/advance_feature_log_stream_state.zig`](../../../src/actions/log/advance_feature_log_stream_state.zig)
- **Reads:** `feature_log_stream_state`, `feature_log_append_evidence`, `trusted_log_clock` · **Writes:** replaces `feature_log_stream_state` · **Side effect:** `none`
- **Does:** Advances segment bytes, the next sequence and the flush counters after an append.
- **Rejects:** none.

## `CloseFeatureLogStreamAction` (`close-feature-log-stream`)

- **Owner:** [`src/actions/log/close_feature_log_stream.zig`](../../../src/actions/log/close_feature_log_stream.zig)
- **Reads:** `feature_log_binding`, `feature_log_stream_lock`, `feature_log_stream_state` · **Writes:** invalidates `feature_log_stream_state` · **Side effect:** `filesystem_write`
- **Does:** Writes the final `segment_trailer` and closes the stream.
- **Rejects:** `LogFlushFailure`, `LogSinkFailure`.

## Retention

## `BuildFeatureLogRetentionAuthorizationAction` (`build-feature-log-retention-authorization`)

- **Owner:** [`src/actions/log/build_feature_log_retention_authorization.zig`](../../../src/actions/log/build_feature_log_retention_authorization.zig)
- **Reads:** `logging_policy`, `feature_log_binding` · **Writes:** `feature_log_retention_authorization` · **Side effect:** `none`
- **Does:** Authorizes pruning one historical binding's stream from the policy and the trusted time ([ADR 0026](../../decisions/0026-header-identity-log-retention.md)).
- **Rejects:** `FeatureLogRetentionAuthorizationInvalid`.

## `ResolveFeatureLogRetentionStreamAction` (`resolve-feature-log-retention-stream`)

- **Owner:** [`src/actions/log/resolve_feature_log_retention_stream.zig`](../../../src/actions/log/resolve_feature_log_retention_stream.zig)
- **Reads:** `feature_log_binding`, `feature_log_retention_authorization` · **Writes:** none (returns the stream) · **Side effect:** `none`
- **Does:** Resolves the stream an authorization covers for the current and historical bindings.
- **Rejects:** `FeatureLogRetentionAuthorizationInvalid`.

## `PruneFeatureLogSegmentAction` (`prune-feature-log-segment`)

- **Owner:** [`src/actions/log/prune_feature_log_segments.zig`](../../../src/actions/log/prune_feature_log_segments.zig)
- **Reads:** `feature_log_binding`, `feature_log_stream_lock`, `feature_log_retention_authorization` · **Writes:** invalidates `feature_log_retention_authorization` · **Side effect:** `filesystem_write`
- **Does:** Consumes the single-use authorization and prunes the stream's segments older than its cutoff.
- **Rejects:** `LogSinkFailure`, including an authorization that doesn't match the binding.

## Emergency

## `EmitEmergencyLogFailureRecordAction` (`emit-emergency-log-failure-record`)

- **Owner:** [`src/actions/log/emit_emergency_log_failure_record.zig`](../../../src/actions/log/emit_emergency_log_failure_record.zig)
- **Reads:** none · **Writes:** none · **Side effect:** `filesystem_write`
- **Does:** Makes one bounded write of `SDDE_LOG_FAILURE workflow=<CODE> level=fatal code=<FAILURE_CODE>` to the emergency sink, with no retry or recursive logging.
- **Rejects:** none; a failed write is dropped.
