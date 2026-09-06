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

Candidate outputs remain private until whole-workflow validation permits
publication. Success requires writing the complete validated output. Publication
failure may leave replaced files under the approved failure rule below, but
failed, blocked, cancelled or interrupted executions never report success. A later
invocation starts the workflow again from the beginning, revalidating current
inputs; it never resumes a saved step, task, model response or checkpoint.

There is no project-, feature-, task- or provider-level transaction subsystem
for this workflow: no WAL, transaction-ID ledger, write-before-send journal,
commit-marker protocol, durable result handoff, roll-forward/rollback recovery
or recovery directory. Moving or renaming that machinery does not satisfy this
decision. Whole-execution validation is not an all-or-nothing filesystem
transaction or permission to introduce such a subsystem.

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
overwrite user-resolved (user-closed) clarification files. Unresolved forms are
completely overwritten at the same registered paths, retaining their subject
identities, under the rerun replacement rule below. A `needs_user` outcome ends
the execution rather than saving a continuation. After answers are supplied, a new
execution starts at `start`. `implement` cannot execute while specification,
planning or tasks clarifications remain outstanding. Successful reruns replace
existing workflow outputs at the same registered paths.

Logs remain observations, not execution checkpoints or recovery authority.
This decision does not weaken path authorization, candidate validation,
predecessor gates, explicit approvals, command safety or secret redaction.

## Rerun replacement rule (accepted 2026-09-07)

Explicit user direction makes this the shared rule for every workflow execution:
completely overwrite all registered replaceable output files at their existing
engine-owned paths. Clarification forms the user has resolved are the sole
clarification-file exception and MUST remain byte-for-byte unchanged.
Clarification forms the user has not resolved MUST be completely overwritten
from the current validated clarification state on rerun, including their answer
regions; retaining the same subject/ID does not permit retaining the old form.
Do not append, merge old output, skip existing files, add filename suffixes, or
require separate overwrite approval. This applies to every registered workflow,
not only Specify or the initial SDD suite.

User resolution is the controlled user-close submission described in Design
Section 23.2. Capture it before preparing replacement forms and recheck it before
writing. A pending, stale or invalid close remains protected; protection does
not make an answer valid or currently applicable. Unsubmitted drafts in forms
that remain open are replaceable. Preserve stable clarification identities and
applicable validated answers rather than resetting the registry or allocating
duplicate questions. Writable authority-resolved/cancelled audit forms remain
replaceable under their existing lifecycle.

The rule governs the selected workflow's authorized output set, including its
unresolved forms through the clarification persistence exception. It does not
authorize deleting the feature directory, rewriting unrelated files, resetting
immutable history, or bypassing validation and predecessor gates. Normal output
publication still requires successful whole-workflow completion; clarification
publication may end in `needs_user`.

## Publication failure rule (accepted 2026-09-07)

Explicit user approval settles the multi-file write-failure/interruption case.
Validate the complete output set before writing. A write failure or interruption
may leave already-replaced files in place, but must never report success or
record new successful completion. A fresh invocation starts from the beginning
and overwrites the registered outputs; there is no rollback, recovery store or
saved continuation. User-closed clarification files remain protected.

This amends the all-or-nothing filesystem interpretation of Design Section 25:
workflow computation and validation remain whole-execution gates, but ordinary
multi-file publication is not a filesystem transaction. Existing files alone
are not evidence that the current execution completed successfully.

## Acceptance and implementation status

Tests must prove whole-workflow completion or abandonment, no intermediate
task publication, reruns starting at `start`, fresh per-execution provider
state, clarification preservation/deduplication, and absence of transaction or
provider-recovery prerequisites, including for unrelated YAML workflows. Rerun
tests must also prove complete replacement of unresolved forms at unchanged
subject IDs/paths, replacement of unsubmitted drafts, byte-identical preservation
of user-resolved forms, and write-time protection against concurrent user closure.
Publication failpoints must prove that all candidates validate before any write,
each write failure prevents new successful completion, already-replaced files
may remain, and a fresh rerun replaces the complete output set without recovery.

The transaction-ID modules/codecs, provider lifecycle journal projections, and
logging transaction stabilization/events have been removed. Regression tests
cover reruns from `start`, fresh provider state, lease cleanup, and preservation
of terminal outcomes (`zig build test-atomic-execution`). Whole-workflow output publication and clarification
preservation/deduplication still require their implementation evidence. Prior
transaction/checkpoint/recovery contracts in the named documents and samples
are withdrawn; they must not be used to reintroduce this machinery.
