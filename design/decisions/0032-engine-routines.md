# ADR 0032: Typed engine routines for fixed engine sequences

- **Status:** Accepted. Not built: the Specify invocation stage action
  ([ADR 0031](0031-stage-actions.md)).
- **Date:** 2026-10-22
- **Decision authority:** User decisions, 22 October and 8, 12, 19, 20 and 21 November 2026.
- **Amends:** AGENTS.md "Actions, orchestrators, and runner", "Testing expectations" and the
  capability-leak review rule; [ADR 0003](0003-generic-workflow-engine.md),
  [ADR 0004](0004-model-provider-bootstrap.md),
  [ADR 0018](0018-debug-model-exchange-logging.md),
  [ADR 0026](0026-header-identity-log-retention.md) and [ADR 0031](0031-stage-actions.md);
  design.md §1, §3.3 (invariants 9 and 27), §14, §15, §29 and §31; contracts §5, §6, §14, §15,
  §27, §28 and §29 and the 13-01, 13-02 and 13-09 catalogues; F0001, F0002, F0004, F0005,
  F0006 and F0008, where they require these sequences to run as runner-applied actions under
  a capability-free orchestrator.

## Decision

### Engine routines

A fixed engine sequence is an **engine routine**: one module of typed functions
that runs the sequence. It is engine-kernel work under ADR 0005, like loading,
parsing, compilation, cleanup and provider preparation. It is neither an action nor an
orchestrator, and not a pipeline node: it is not registered, not selectable from YAML,
and produces no `NodeDelta`.

- **Steps.** Each step is a function with one responsibility. Pure steps live in
  `src/domain/`. Each port-using step takes exactly one port parameter.
- **Typed data.** Values pass as typed arguments and return values. A routine uses no
  `*anyopaque` context, no table of parameterless steps, no shared optional fields and
  no per-step envelope or `DataKey` tracking. No `*anyopaque` child-binding context exists
  for a routine's sequence.
- **Validated types keep the order.** Wherever a step turns a candidate value into a
  validated one, its function returns a distinct validated wrapper type, and the next step
  requires that type. Running a step before its inputs exist is then a compile error. Zig
  catches misordering only where adjacent types differ, so this rule is what makes it hold.
  The same rule applies to ADR 0031 stage actions.
- **The entry function** calls steps in order and calls no port itself. It checks
  cancellation between steps through the capability-free `NodeRuntime`, except a
  feature-logging routine, which polls none: cancellation reaches it only as the sink's
  `Cancelled` (see "Cancellation mapping"), so a finalization after a cancelled run still
  closes the streams. It owns cleanup through `defer` and `errdefer` on every path.
- **Branches.** A routine may branch on a typed fact its own steps produce, such as
  whether a provider is required, or whether a log event is dropped. It has no retry,
  backoff or loop beyond what its existing contracts already specify. The lock acquire
  stays one attempt with its fixed deadline.
- **Narrow ports.** No step takes the routine's port set, a capability bag, `anytype` or
  `anyopaque`. A side-effecting step acts only on typed values an earlier step already
  validated, so validate versus write holds between functions.
- **Location.** A routine lives in `src/application/<name>_routine.zig`. It imports only
  domain and port modules, never adapters or `std.Io`. It reaches I/O only through its
  port parameters.

### Who calls a routine

- **The composition root** constructs every routine's ports. It runs the startup routine
  before workflow selection (§14.0 step 1).
- **A runner-owned child binding** runs provider bootstrap after workflow selection. The
  composition root builds the binding and the binding holds the ports. The
  workflow-engine orchestrator sees only the binding and the routine's typed outcome, so
  it gains no capability.
- **The runtime logging lifecycle** invokes the six feature-logging routines (persist,
  prepare, close, retention, prior-run finalization and failure); the log service reaches
  them through it, and the composition root constructs their ports (ADR 0018). The one other
  caller is composition's `Assembly.fail`, which invokes the failure routine directly to
  report a failure that has no active lifecycle to report it.
- **No action, orchestrator, runner or model-facing code** calls a routine directly. Only
  `src/composition/`, the provider-bootstrap binding and the runtime logging lifecycle import
  a `*_routine.zig`, and the lifecycle only a logging one. Orchestrators stay capability-free
  and reach routines only through runner-owned bindings.

### What doesn't change

- **Startup properties.** Startup is not project-authored, registered or
  selectable through `paths.workflows`. It acquires no feature transaction lock.
- **Service construction.** Each service is built only after its complete
  validation (F0001, F0004, F0005 and F0008).
- **Public error codes** stay identical. Failure, cancellation and success stay distinct,
  including under the feature log: a cancellation under a log lock, or while a segment is
  read, is the run's `cancelled`, not a logging failure (see "Cancellation mapping").
- **Failure mapping.** Each step keeps its failure mapping.
  - Startup and provider steps map every error to their fixed public code,
    including allocation failure and deadline exhaustion.
  - Where a sequence propagates a Zig error, the routine propagates that error.
  - Each routine defines a closed enum of its steps, and every failure records the failing
    step. A mapped failure carries it in its diagnostic. A propagated error leaves it in a
    routine-owned diagnostic slot, as ADR 0031 does.
  - The startup slot also carries a workflow definition's rejection evidence: a closed rule
    class, the definition's source ordinal and, where scoped, a step or resource ID, recorded by
    the owner of the check that rejected it, and the display path the routine copies from the
    inventory by ordinal
    ([F0005](../features/F0005-WorkflowDefinitionRegistryService.md) §9). The public code and its
    `code(step)` mapping are unchanged, and the evidence is neither a code nor a branch.
- **Provider bootstrap** branches only on the typed requirement and gains no
  credential read (ADR 0028). It is not capability-free: its locate and read steps
  hold the provider-config port. On `not_required` it makes no provider-config call.

### Scope

1. **Startup.** It covers three sequences, which only read, decode, validate and
   build in memory:
   - the bootstrap sequence before workflow selection;
   - the provider-config sequence;
   - the provider-bootstrap sequence after selection.
2. **Feature logging.** It writes, locks and prunes.
   - **Routines.** Six, in `src/application/feature_log_*_routine.zig`: persist (one fact or
     prompt fragment), prepare, close, retention, prior-run finalization and failure (the
     emergency write). The runtime logging lifecycle runs them on the run's runner, which holds
     only the run's typed state and ports, and reports each routine's stop: a logging failure
     through the failure routine's one write, a cancellation not at all.
   - **Prior-run crash finalization** is a routine, run by the same lifecycle. For one crashed
     prior run's open tail of one stream it reads the trusted clock, takes that run's own stream
     lock, proves the group still ends in an active tail, recovers the tail by truncating it to
     its last complete row, writes one trailer stamped with the clock's reading, proves the group
     closed, and releases the lock on every path. The composition root finds the tails and
     opens the sibling adapter for each. It runs after the current run's activation and before
     retention, so retention finds the group closed
     ([ADR 0026](0026-header-identity-log-retention.md), which owns its authority).
   - **Locks.** Every lock is released on every success, error and cancellation path
     (§26.5, 13-09).
   - **Emergency diagnostic.** It stays exactly once and is never recursive or observed
     (§14.9, 13-09, F0002).
   - **Finalization** keeps one idempotent owner that preserves the first failure
     (ADR 0018).
   - **Retention** keeps its five-step order, and pruning stays its only deletion path
     (ADR 0026).
   - **No mid-run policy transition.** The run's feature log keeps one binding and policy from
     activation to finalization. A policy change during a run has no producer: §9.4 keeps every
     changed candidate for the next run, so no committed bootstrap authority, durable lineage
     or pointer commit precedes a switch ([ADR 0009](0009-atomic-workflow-execution.md)). There
     is no policy-transition coordinator and no finalization of a historical stream within a
     run.
   - **Logging-internal pipeline data.** The logging routines pass function-local values, not
     `DataKey`s (§6). A key with no producer, consumer or schema is deleted when found.

### Cancellation mapping

The run's cancellation source is the operator's interrupt (SIGINT), installed at the
composition root and read through `NodeRuntime` at the run's own boundaries and at each timer
slice of a model request, never inside a sink call.

The feature-log sink port carries `Cancelled`, and a log outcome is `cancelled` beside
`dropped`, `persisted` and `blocked`. A cancellation during a directory check, a segment read,
creation, rotation, append, close, prune or any step under the lock stops the run as
`cancelled`, never as a logging failure. It has no `LOG_*` code and emits no emergency line,
and its lock is released. The logging routines poll no `NodeRuntime`, so no check between
their steps can skip a lock release. A cancellation can land after a row's or trailer's bytes
were written, so a cancelled persist or close drops the runner's cached stream state. The next
persist, and finalization before it closes the stream, recover that state from the bytes, as
after a crash.

- **Precedence.** A lock that cannot be released after a cancelled step is a logging
  failure of its own and outranks the cancellation, as a release failure outranks any step
  before it. Retention keeps its first stop. In finalization a cancellation never replaces
  a logging failure, and a later logging failure replaces an earlier cancellation.
- **Finalization.** When its own log step is cancelled, a rejection the run already had is
  kept beside the `cancelled` outcome as its first cause, a run that was already cancelled
  stays as it was, and a capture failure stays whole. Finalization closes every stream,
  the second even when the first stopped, and reports the first stop. An activation whose
  prompt prepare stops closes the event stream it opened, since that run is never
  finalized.
- **Accepted limit.** A cancellation between creating a segment and writing its header leaves
  a torn segment, which current-run recovery refuses, so that run's finalization fails and it
  ends `blocked`. It is the crash shape ADR 0026 names. Recovery does not rewrite a torn last
  segment of the current run: the cancellation source is read only at boundaries and timer
  slices, never inside a sink call, so a user interrupt does not produce the shape, and the
  repair would extend what recovery may do to a retained log file.

### Out of scope

- **The workflow-engine orchestrator.** It follows the compiled YAML and isn't a fixed
  sequence.
- **[ADR 0030](0030-engine-owned-model-request.md)'s request coordinator.** Its stages
  change runner-owned state that the runner must apply per stage, it is YAML-selected,
  and the runner must check capabilities per stage binding. That form stays.
- **The specify invocation operation.** It is a registered operation that only parses
  and validates, so it becomes an [ADR 0031](0031-stage-actions.md) stage action with side
  effect `none`, not a routine.
  - It is named by the definition's `invoke:` field rather than a graph step, and has no
    `on` map. The workflow-engine orchestrator runs it through its binding before the graph
    starts and reads its `ok` or `failed` outcome.
  - ADR 0031's definition covers this case.

### Tests

All offline, for each routine:

- **Step tests.** Every step has unit tests with fake ports, covering accepted and
  rejected cases.
- **Routine tests** with fake ports, not spy child bindings:
  - step order;
  - every branch;
  - failure propagation with the exact public code;
  - cancellation between each pair of steps, for a routine that polls `NodeRuntime`; for a
    logging routine, which polls none, the sink's `Cancelled` at each step instead;
  - cleanup on every path.

  For logging, also lock release on every path, exactly one emergency line, and
  finalization idempotence.
- **Diagnostics.** A failure in each step reports that step. An allocation failure in a
  step reports that step with its public code, or as the same propagated error where
  the sequence propagates errors.
- **Provider bootstrap.** On `not_required`, the routine makes zero provider-config port
  calls.
- **Architecture tests** hold each rule under "Engine routines" and "Who calls a routine",
  each with rejected fixtures, including an action, an orchestrator, a runner, the log
  service and the wrong routine that import a `*_routine.zig`.

## Consequences

- **Wiring errors are compile errors.** Step dependencies are types, so running a step out
  of order does not compile.
- **One pattern.** Every deterministic sequence follows the same pattern: stage actions
  for workflow operations, engine routines for kernel sequences. The only exception is
  ADR 0030's request coordinator.
- **Narrowness rests on types and tests.** Inside a routine, it rests on Zig signatures
  and architecture tests rather than per-binding capability checks.
- **No behaviour change is claimed.**
