# 25. Atomic workflow execution and output

Part of the [proposed design](../design.md#25-atomic-workflow-execution-and-output). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

[ADR 0009](../decisions/0009-atomic-workflow-execution.md) owns this accepted rule.

### 25.1 One execution, one output boundary

- The selected workflow runs from its compiled `start` to its terminal outcome.
- Model results, repairs, implementation tasks, candidate files, evidence and state updates
  belong to that execution.
- Whole-workflow validation precedes publication; success requires the complete output to be
  written.
- No model step or implementation task publishes independently.

- There is no project-, feature-, task- or provider-level transaction subsystem: no WAL,
  transaction-ID ledger, durable checkpoint, commit-marker protocol, rollback/roll-forward
  recovery, result-handoff marker or recovery directory.
- Whole-execution validation is not a filesystem transaction or permission to introduce that
  machinery.
- Do not relocate or rename it or make an active feature a prerequisite solely for provider
  storage.

Candidate preparation still enforces path authorization, ownership,
write-set checks, approvals, rendering and validation. These rules do not
create intermediate publication or restart checkpoints.

- Validate the complete output set before the first write.
- Publication may replace files sequentially across configured roots.
- If a write fails or execution is interrupted, already-replaced files may remain; report
  failure when possible and never record new successful completion.
- Under [ADR 0018](../decisions/0018-debug-model-exchange-logging.md), registered
  `workflow_publication` operations must pass the common logging-finalization barrier
  before any output write. A failed stream close prevents publication.
- Every compiled successor of a publication operation is the corresponding terminal
  outcome. No later node may perform work, emit telemetry or fail after publication.
  Preparation selects a closed `ok` or `needs_user` outcome from validated state;
  the publisher returns it only after all writes succeed. A blocked clarification
  refresh is rejected before writing. Pure progress checks also precede publication.
- Write successful completion state only after all required outputs have been written.
- Existing files alone do not prove the current run succeeded.
- This explicit failure rule does not relax protected clarification checks or authorize
  rollback/recovery machinery.

### 25.2 Abandonment and reruns

- Failure, blocking, cancellation or interruption abandons the execution and its unpublished
  candidate output; files already replaced during publication may remain under Section 25.1.
- A subsequent invocation starts at `start`, revalidates current inputs and gates, and executes
  the whole selected workflow again.
- It never restores a saved task, step, model response or provider operation.
- Run-local lifecycle, leases and token accounting start fresh.

- Successful reruns completely overwrite all registered replaceable workflow outputs at their
  existing paths, without append, merge, skip, suffix or separate overwrite approval.
- Clarifications are the explicit persistence exception: preserve stable identity and relevant
  validated answers, completely overwrite unresolved forms at the same IDs/paths, do not
  duplicate subjects, and never overwrite user-resolved forms.
- [ADR 0017](../decisions/0017-incomplete-specification-publication.md) extends Spec
  clarification publication to a validated incomplete `spec.md`, current reference
  context and explicit pending state. The full pending set is validated before writes,
  and its state is written last. It grants no completed-stage or downstream authority.
- Section 23.2 owns this rule for every workflow execution.
- Outstanding spec, plan or tasks clarifications prevent `implement` from executing.

### 25.3 External effects and observations

- A sent API request may complete and incur cost even if its workflow is abandoned.
- A full rerun may repeat the call.
- There is no cross-execution exactly-once provider-call guarantee, lost-response recovery or
  replay-approval gate.
- Within one execution, retries remain explicit YAML transitions with the owning operation's
  declared `retry-limit`.

Logs are observations, never completion or continuation authority. This
amendment does not authorize additional external effects or weaken command
safety, path authorization, candidate-only model output or secret handling.
