# ADR 0009: One atomic workflow execution, no recovery transactions

- **Status:** Accepted
- **Date:** 2026-09-05
- **Decision authority:** Explicit user direction
- **Amends:** ADR 0003, Design Sections 7.3, 20, 24–25, 28, 30–31,
  F0006 and F0007, and their transaction/checkpoint/recovery samples and diagrams.

## Decision

The selected workflow execution is the atomic unit. It starts at its compiled
`start` step and follows its YAML transitions to a terminal outcome. Steps,
model calls, repairs and individual implementation tasks are not independently
committed or resumable executions.

Candidate outputs remain private to that execution. Only successful completion
publishes the complete validated workflow output. Failed, blocked, cancelled or
interrupted executions do not publish partial successful output. A later
invocation starts the workflow again from the beginning, revalidating current
inputs; it never resumes a saved step, task, model response or checkpoint.

There is no project-, feature-, task- or provider-level transaction subsystem
for this workflow: no WAL, transaction-ID ledger, write-before-send journal,
commit-marker protocol, durable result handoff, roll-forward/rollback recovery
or recovery directory. Moving or renaming that machinery does not satisfy this
decision. Atomic execution states the required observable behavior; it is not
permission to introduce such a subsystem as its implementation.

The runner retains request/attempt/operation lifecycle, authorization leases
and actual token accounting only for the current execution. A new execution
has fresh execution identity, leases and token usage. Provider calls require
their declared capabilities, not a feature-owned journal or an active feature
merely to obtain storage.

A sent API request may finish and incur cost even when the workflow is
interrupted. Starting the complete workflow again may repeat API calls. There
is no cross-execution exactly-once request guarantee and no journal-derived
replay approval gate. Within one execution, only explicit YAML transitions
and operation-local `retry-limit` authorize retries.

Clarifications are the explicit persistence exception. Preserve their stable
identity and relevant answers across executions; do not duplicate them or
overwrite user-closed clarification files. A `needs_user` outcome ends the
execution rather than saving a continuation. After answers are supplied, a new
execution starts at `start`. `implement` cannot execute while specification,
planning or tasks clarifications remain outstanding. Successful reruns replace
existing workflow outputs at the same registered paths.

Logs remain observations, not execution checkpoints or recovery authority.
This decision does not weaken path authorization, candidate validation,
predecessor gates, explicit approvals, command safety or secret redaction.

## Acceptance and implementation status

Tests must prove whole-workflow completion or abandonment, no intermediate
task publication, reruns starting at `start`, fresh per-execution provider
state, clarification preservation/deduplication, and absence of transaction or
provider-recovery prerequisites, including for unrelated YAML workflows.

The transaction-ID modules/codecs, provider lifecycle journal projections, and
logging transaction stabilization/events have been removed. Regression tests
cover reruns from `start`, fresh provider state, lease cleanup, and preservation
of terminal outcomes (`zig build test-atomic-execution`). Whole-workflow output publication and clarification
preservation/deduplication still require their implementation evidence. Prior
transaction/checkpoint/recovery contracts in the named documents and samples
are withdrawn; they must not be used to reintroduce this machinery.
