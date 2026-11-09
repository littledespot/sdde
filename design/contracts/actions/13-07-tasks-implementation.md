# 13.7 Task and implementation actions

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.

No code implements Tasks or Implement yet
([ADR 0034](../../decisions/0034-spec-quality-gate.md)). Their design starts from
[§19](../19-tasks.md) and [§20](../20-implement.md); the entries below are the proposals other
documents name.

Proposed, no code (Tasks, [§19](../19-tasks.md)): validate model task proposals against their
schema and obligation, phase, command and plan-file grants; partition obligations and
dependency candidates; assign task, evidence-predicate, resource and capability identities;
build the proposal graph, merge validated dependencies and convert internal keys to task IDs.

Proposed, no code (Implement, [§20](../20-implement.md)): build a task's context and
operation plan; authorize, apply, validate and promote or discard each file operation through
a private savepoint; run named commands through the shell-disabled port with isolation and
complete cleanup; record operation, command and manual evidence; repair only the failed
replaceable unit; run final validation and release every resource on every terminal path.
A task result is never published or resumed on its own
([ADR 0009](../../decisions/0009-atomic-workflow-execution.md), [§25](../25-publication.md)).

## `ValidateCanonicalTaskGraphAction`

Proposed, no code: recheck node, edge and lock completeness, phase rules and acyclicity after
internal keys resolve to task IDs ([§19](../19-tasks.md)).

## `DeriveRequiredChecksAction`

Proposed, no code: derive a task's mandatory checks from its kind, file kinds and evidence
policy, and later the implementation diff ([§19](../19-tasks.md)).

## `CalculateRunnableSetAction`

Proposed, no code: compute the ordered eligible task IDs from current dependency and resource
facts ([§20](../20-implement.md)).

## `SelectRunnableTaskAction`

Proposed, no code: select one runnable task deterministically under the declared scheduling
policy ([§20](../20-implement.md)).

## `ClaimTaskLeaseAction`

Proposed, no code: reserve only the selected task's resources as an execution-local lease the
runner validates and applies ([§20](../20-implement.md)).

## `BuildCopySourceRegistryAction`

Proposed, no code: capture the task-scoped immutable allowlist of copy sources
([§20](../20-implement.md)).

## `DeriveCopySourceIdAction`

Proposed, no code: derive one copy source's closed source tuple from its canonically ordered
selector ([§20](../20-implement.md)).

## `DeriveCopySourceRegistryIdAction`

Proposed, no code: derive the copy-source registry's closed tuple
([§20](../20-implement.md)).

## `RunConfiguredCommandAction`

Proposed, no code: run one named command descriptor once through the shell-disabled port
([§20](../20-implement.md)).

## `CreateCommandSavepointAction`

Proposed, no code: create the child savepoint a mutating command runs in; for final
validation, return the closed created-or-adapter-failed outcome ([§20](../20-implement.md)).

## `DiscardCommandSavepointAction`

Proposed, no code: discard a command's child savepoint whatever its exit status
([§20](../20-implement.md)).

## `ValidateFinalValidationCommandSavepointCreationAction`

Proposed, no code: prove the final-validation savepoint's authorization, parent, owner and
lock joins before the command can run ([§20](../20-implement.md)).

## `ValidateFinalValidationCommandSavepointDiscardAction`

Proposed, no code: accept only a complete independent proof that final validation's savepoint
was discarded; anything else routes to a parent-only recursive abort
([§20](../20-implement.md)).

## `ValidateFinalValidationOverlayDiscardAction`

Proposed, no code: return normal-discard or recursive-abort evidence for final validation's
overlay ([§20](../20-implement.md)).
