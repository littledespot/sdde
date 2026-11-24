# 13.9 Feature logging routines

Part of [design §13](../../design.md#13-action-catalogue). Feature logging is no registered
operation: under [ADR 0032](../../decisions/0032-engine-routines.md) its fixed sequences are
six engine routines in `src/application/feature_log_*_routine.zig`. Each is a closed `Step`
enum run by one entry function, `run`, whose steps each take only the port they use; pure steps
live in `src/domain/` (`feature_log_decisions.zig`, `feature_log_rows.zig`,
`feature_log_stop.zig`, `feature_log_format.zig`, `feature_log_retention.zig`). Results remain
execution-local until whole-workflow publication; [§25](../25-publication.md) and the
clarification exception apply.

[F0002](../../features/F0002-LogService.md) owns the logging contract (events, record format,
segments, locks and the emergency record) and [§26.5](../26-security.md) the levels and emission
rule. The runner-owned logging observer submits trusted lifecycle events and the
`WorkflowTelemetryFact`s the runner emits to the runtime logging lifecycle through the telemetry
barrier; their IDs are not observed recursively. The lifecycle calls the routines, and composition's
`Assembly.fail` calls the failure routine directly for a failure that has no active lifecycle; the
lifecycle reports each routine's stop once: a logging failure through the failure routine, a cancellation
not at all. A routine has no clock, filesystem, redaction, serializer or sink port of its own; the
composition root builds the ports and the lifecycle hands each routine the ones it names.
[ADR 0018](../../decisions/0018-debug-model-exchange-logging.md#production-activation-and-finalization)
owns activation and finalization: one owner finalizes logging before a registered
`workflow_publication` operation writes, and the terminal binding finalizes every other outcome.

Cancellation reaches a routine only as the sink's `Cancelled`. A routine polls no `NodeRuntime`,
a cancelled step releases its lock, and a cancellation has no `LOG_*` code and emits no emergency
line ([ADR 0032](../../decisions/0032-engine-routines.md), "Cancellation mapping"). A lock that
cannot be released after a cancelled or failed step is a logging failure of its own
(`LOG_RELEASE_FAILURE`) and outranks the stop before it; retention keeps its prune stop and
reports a release failure only when nothing stopped it first.

## Policy

The `canonicalize_log_level` and `validate_logging_policy` steps of the startup routine
([`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig)) own
configured-level canonicalization and logging-policy compilation; both reject
`LoggingPolicyInvalid`.

## Activation

## `feature_logging_workflow.Activate` (`activate-feature-logging`)

- **Owner:** [`src/application/feature_logging_workflow.zig`](../../../src/application/feature_logging_workflow.zig) (through [`ports/feature_log_activation.zig`](../../../src/ports/feature_log_activation.zig))
- **Reads:** `feature_directory` · **Writes:** `activated_feature_directory` · **Side effect:** `filesystem_write`
- **Does:** Activates the run's feature logging for the resolved feature directory under the workflow's shortcode, and publishes the directory as activated ([ADR 0018](../../decisions/0018-debug-model-exchange-logging.md)).
- **Rejects:** outcomes `blocked` and `cancelled` from the port; a missing port fails.

## Persist routine

[`src/application/feature_log_persist_routine.zig`](../../../src/application/feature_log_persist_routine.zig)
· **Steps:** `check_status`, `validate`, `select`, `read_clock`, `acquire`, `recover`,
`serialize_header`, `create`, `render`, `measure`, `rotate`, `append`, `mirror`, `release`.

- **Does:** Persists one telemetry fact to the event stream or one sanitized prompt fragment to
  the prompt stream, in one straight line under the stream's lock.
  - **Validate and select:** a fact must validate against the event registry
    (`InvalidLogEventFact`, a serialization failure) and a fragment against
    [ADR 0018](../../decisions/0018-debug-model-exchange-logging.md)'s fragment rules
    (`InvalidPromptLogFragment`). An event the registry marks `always` is emitted at every
    threshold and every other event follows the configured one ([§26.5](../26-security.md)); a
    fragment is captured only when the policy's level enables prompt capture. A dropped input costs
    no clock, lock or identity work.
  - **Clock and lock:** reads the trusted clock (`LogClockReadFailure`, a serialization failure),
    then makes one attempt for the stream's exclusive lock within the fixed deadline, with no
    retry ([F0002](../../features/F0002-LogService.md)). Only a lock held elsewhere is
    `LOG_LOCK_TIMEOUT`; every other sink fault is `LOG_SINK_FAILURE`.
  - **Open:** a stream with no cached state is recovered from its segments under the held lock, or
    given its first segment with its column heading and `segment_header` row; a stream a cancelled
    step dropped is recovered the same way.
  - **Render:** identifies the row with its binding, workflow shortcode, event ID, the stream's
    next sequence and the trusted time, and encodes it as one complete fixed-column
    pipe-delimited row (`LOG_SERIALIZATION_FAILURE`).
  - **Rotate:** appends when the row and trailer fit the segment; rotates to the next ordinal
    (writing the old segment's trailer and the next segment's heading and header) when they do
    not; and is exhausted at the segment-count cap or when the row cannot fit a new segment
    (`LOG_SEGMENT_LIMIT_EXHAUSTED`). The row then names the segment it opens.
  - **Append:** appends the row, flushing at or above the policy's flush level, on a terminal
    stage or task event, or when the buffered count or interval reaches its limit
    (`LOG_FLUSH_FAILURE`, `LOG_SINK_FAILURE`); the stream's state advances after the row reached
    its file.
  - **Mirror:** writes the row to the console sink when the policy enables it; the console is
    only a mirror, so a failed write is `LOG_SINK_FAILURE` after the state advanced.
  - **Release:** releases the lock on every path.
- **Rejects:** `LOG_LOCK_TIMEOUT`, `LOG_SERIALIZATION_FAILURE`, `LOG_SINK_FAILURE`,
  `LOG_FLUSH_FAILURE`, `LOG_RELEASE_FAILURE`, `LOG_SEGMENT_LIMIT_EXHAUSTED`; a cancellation is
  not a rejection, and it drops the stream's cached state because the file may be ahead of it.

## Prepare routine

[`src/application/feature_log_prepare_routine.zig`](../../../src/application/feature_log_prepare_routine.zig)
· **Steps:** `check_status`, `read_clock`, `acquire`, `recover`, `serialize_header`, `create`,
`release`.

- **Does:** Recovers or creates the first segment of the event stream and, when the policy captures
  prompts, of the prompt stream, each under its own stream lock, before the log can be the active
  observer. A retired run is a sink failure, and a prepared run is already prepared.
- **Rejects:** the persist routine's lock, sink, serialization and release codes. A stopped prompt
  stream leaves the event stream it opened open, so the lifecycle closes it with the close routine
  and the activation's own clock reading before it reports the prompt stop.

## Close routine

[`src/application/feature_log_close_routine.zig`](../../../src/application/feature_log_close_routine.zig)
· **Steps:** `validate_status`, `read_clock`, `acquire_recovery`, `recover_dropped`,
`release_recovery`, `serialize_trailer`, `acquire_close`, `close_stream`, `release_close`.

- **Does:** Finalizes a prepared, live run: for each stream it first recovers a stream whose state
  a cancelled step dropped, under the stream's lock, so the trailer follows the rows really on
  disk, then writes the final `segment_trailer` under the lock, closes the stream and releases the
  lock. Every stream is closed even when the first stopped, the first stop is the one reported,
  and the run is retired only when none stopped. An unprepared or retired run is never finalized.
- **Rejects:** the persist routine's lock, sink, flush, serialization and release codes.

## Retention routine

[`src/application/feature_log_retention_routine.zig`](../../../src/application/feature_log_retention_routine.zig)
· **Steps:** `authorize`, `resolve_stream`, `acquire`, `prune`, `release`.

- **Does:** Prunes one prior run's closed segments of one stream: authorizes the single-use prune
  from the policy and the trusted time ([ADR 0026](../../decisions/0026-header-identity-log-retention.md))
  (`FeatureLogRetentionAuthorizationInvalid`, a sink failure), resolves the stream the
  authorization covers for the current and historical bindings, takes the prior run's own stream
  lock, consumes the authorization and prunes the segments older than its cutoff, and releases the
  lock after any prune outcome. Pruning stays the only deletion path.
- **Rejects:** `LOG_LOCK_TIMEOUT`, `LOG_SINK_FAILURE` (including an authorization that does not
  match the binding), `LOG_RELEASE_FAILURE` when nothing stopped it first.

## Prior-run finalization routine

[`src/application/feature_log_prior_finalization_routine.zig`](../../../src/application/feature_log_prior_finalization_routine.zig)
· **Steps:** `read_clock`, `acquire`, `check_open`, `recover_tail`, `serialize_trailer`,
`close_stream`, `verify_closed`, `release`.

- **Does:** Closes one crashed prior run's open tail of one stream ([§14.10](../14-orchestration.md),
  [ADR 0026](../../decisions/0026-header-identity-log-retention.md)): reads the trusted clock, takes
  the prior run's own stream lock, proves under it that the group still ends in an active tail,
  recovers the tail by truncating it to its last complete row, writes one `segment_trailer` stamped
  with the clock's reading, proves the group closed, and releases the lock on every path. A group
  that is no longer an active tail under the lock is left as it is and stops the routine. A release
  failure outranks the stop before it, as in the close routine.
- **Rejects:** `LOG_LOCK_TIMEOUT`, `LOG_SINK_FAILURE`, `LOG_FLUSH_FAILURE`,
  `LOG_SERIALIZATION_FAILURE` (the clock), `LOG_RELEASE_FAILURE`; a cancellation is not a rejection.

## Failure routine

[`src/application/feature_log_failure_routine.zig`](../../../src/application/feature_log_failure_routine.zig)
· **Steps:** `format`, `write`.

- **Does:** Makes one bounded write of
  `SDDE_LOG_FAILURE workflow=<SHORTCODE> level=fatal code=<FAILURE_CODE>` to the emergency sink,
  with no retry or recursive logging.
- **Rejects:** none; a line that cannot be formatted or written is lost, because a report of that
  would be a second report of one failure.
