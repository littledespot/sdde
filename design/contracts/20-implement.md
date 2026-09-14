# 20. Implement stage design

Part of the [proposed design](../design.md#20-implement-stage-design). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

### 20.1 Inputs and preconditions

- `implement` must not execute while any specification (`SNN`), plan (`PNN`), or tasks (`TNN`)
  clarification is outstanding.
- The entry gate loads and validates the complete retained clarification registry before task
  selection, model calls, command execution, overlays or project changes.
- An open, deferred, stale or unvalidated required answer does not satisfy that gate.
- It reports the exact blocking IDs and returns nonzero; implementation cannot answer, bypass or
  duplicate an upstream clarification.
- Resolving one prefix does not waive the other two.

- The stage gate requires workflow state `tasked`, current task definition/runtime state, and an
  approval whose `taskDefinitionStateId` equals the current immutable graph.
- Runtime revision changes do not invalidate that approval.
- It loads/validates the current clarification registry first and exits nonzero with
  `UPSTREAM_TASKS_CLARIFICATION_OPEN` when any `SNN`, `PNN`, or `TNN` is open; implementation
  never asks the code-generation model to answer it.
- It reparses editable `spec.md`, requires equality with the stored plan-input specification IR,
  loads canonical plan/task/reference state, checks every generated view against deterministic
  rendering for its recorded definition/runtime binding, and revalidates:

- specification and reference obligations;
- plan artifacts and declared repository surface;
- task IR, requirement coverage, paths, dependency DAG, and parallel eligibility;
- current environment/project/preset resolution;
- current gate-sensitive repository fact values against the complete fact registry bound into `PlanState`;
- availability of commands required by pending tasks.

If current repository facts make a task path invalid—for example a project was removed—the stage blocks. It does not ask the LLM to improvise a different architecture.

- Before selecting work, implementation rebuilds the complete authority-reconciliation
  projection for every requirement consumed by the approved task and its evidence predicates.
- Implementation has no clarification ownership of its own and cannot create a new requirement,
  policy, exception, path, dependency, command, task, or design choice.
- A non-success outcome routes to `specify`, `plan`, or `tasks` according to the compiler-locked
  earliest owner and Section 24.5; an unknown owner blocks administratively.
- Only a code defect inside already resolved authority and the current operation authorization
  may enter code repair.

### 20.2 Task selection

`CalculateRunnableSetAction` calculates ready tasks, `SelectRunnableTaskAction` chooses the lowest phase/order candidate, and `ClaimTaskLeaseAction` atomically changes that task to `executing` while reserving its declared locks. If the compare-and-swap claim fails, selection repeats from fresh state. Execution-local task runtime distinguishes:

- `pending`;
- `executing`;
- `validation_failed`;
- `failed`;
- `blocked`;
- `completed`;
- `needs_reconciliation`.

The tasks view remains human-facing. Transient task progress belongs only to the current workflow execution. Publish completion markers only with the whole successful workflow output; no recovery state or independent task commit is stored.

### 20.3 Task context

The model receives only:

- task responsibility and description;
- linked requirement/obligation records;
- relevant plan decisions;
- exact allowed read/write `fileId`s;
- exact allowed copy `sourceId`s from the current immutable source-registry revision;
- bounded current contents of target and directly related files;
- nearby repository conventions selected deterministically;
- applicable raw principle guidance and separately enforceable preset rules;
- exact available command IDs;
- required evidence;
- one response schema.

- Before this packet is built, the engine canonically orders eligible
  repository/reference/template selectors, derives the closed registry/source tuples with
  `DeriveCopySourceRegistryIdAction` and `DeriveCopySourceIdAction`, and
  `BuildCopySourceRegistryAction` captures their task-scoped immutable allowlist.
- It initializes the execution-local ledger and validates the exact source/identity bindings
  before model work; no preparation checkpoint is persisted.
- The model is not asked to rediscover the repository, choose a different target/source, assign
  an ID, or execute tools.

### 20.4 Change planning and filename validation

- For a multi-file task, a model call may propose an ordered list of operation intents.
- Every destination must be a plan-approved `fileId`; implementation cannot mint a path or
  `fileId`.
- Planning compiles each record's allowed runtime capabilities from its declared intent,
  file-kind policy, explicit whole-file/copy policy, and approval scope.
- A missing destination or missing capability is an upstream plan/task defect.
- Filename guidance and atomic filename repair occur in planning, where a `ProjectPathCandidate`
  exists.

- This rule is universal rather than path-specific: whenever execution would require any
  authority or decision absent from the approved task context, the operation plan is rejected
  and the shared gap router returns to the owning stage.
- Generating a locally convenient value, dependency, structure, validation method, exception, or
  behavior is prohibited even when it would make a command or test pass.

- Code is generated one file operation at a time.
- A response cannot include a raw path, engine content handle, trusted byte length, or command.
- Create/replace responses carry one schema-bounded UTF-8 string and update carries one allowed
  patch-format ID plus UTF-8 patch string.
- Actions compute the actual serialized/body lengths, capture valid bytes in the run-local
  immutable candidate store, and only then construct the canonical handle-bearing operation.
- The closed canonical operation set is:

- `CreateFile`: complete content to an approved absent destination;
- `UpdateFile`: a patch to an approved existing destination;
- `ReplaceFile`: complete replacement content for an approved existing destination;
- `CopyFile`: byte-exact content from an engine-resolved repository/reference/template `sourceId` to an approved destination;
- `DeleteFile`: disabled by default and separately policy-authorized.

- The engine builds the copy-source registry before task generation/context selection.
- Its registry ID is a closed tuple of exact task-definition/task/lease/base-overlay/contract
  authorities; each source ID is the registry ID plus the source's unique ordinal in canonical
  normalized-selector order.
- Existing repository sources are captured as write-once task-context blobs bound to the exact
  base overlay revision; reference sources point to write-once blobs in the current
  `ReferenceSnapshot`; approved template sources point to a blob in an exactly versioned
  template package.
- Registry revision, blob ID, byte length, media type, provenance/license data, and copy-policy
  ID are immutable.
- The model sees only the source IDs authorized for the current task; it cannot supply a raw
  path, blob handle, revision, ordinal, or new source.

- `CopyFile` validates source kind, provenance, media type, size, permission, and destination
  capability.
- A copy to an absent target requires `copy_destination` plus create-copy permission; overwrite
  requires `copy_destination`, `replace`, and an explicit copy-overwrite policy.
- The model returns no expected target state.
- `ValidateExpectedTargetStateAction` derives it from the current file record and overlay
  metadata, and `OperationAuthorization` binds it, the target descriptor revision, overlay
  revision, copy-registry revision, and exact source blob.
- A commit-time descriptor/no-follow compare-and-swap prevents an out-of-band target swap.
- A later adaptation is a separately authorized `UpdateFile` or `ReplaceFile` operation.

- `CreateFile` and `ReplaceFile` require complete schema-valid content and the existing
  file-kind, path and operation authorization.
- The engine does not estimate serialized response size or impose model-content byte ceilings.
- The provider reports size errors or stopped output; those outcomes follow explicit YAML
  transitions and never authorize partial content.
- `CopyFile` retains its separate filesystem `copiedSourceBytes` constraint.
- Responses are never truncated, and no adapter silently substitutes copies, updates or
  smaller-file calls.

### 20.5 Candidate workspace and validation

- All implementation operations act on the current workflow's private candidate.
- Validate each operation against approved file IDs, exact old-value/revision preconditions,
  authorized effect kinds and the declared write set before applying it to that candidate.
- Validate syntax, imports, paths and all impacted and dependent checks after each repair, then
  validate the complete candidate.

- Commands use only configured IDs and structured shell-disabled descriptors.
- Keep persistent candidate changes distinct from disposable command output; undeclared changes,
  malformed observations and missing evidence fail closed.
- Evidence joins the exact current task, operation, candidate revision and configured check.
- Models cannot fabricate passing evidence or completion.

The runner owns candidate resources and deterministic cleanup. No operation
body, promotion receipt, evidence append or cleanup state is persisted as a
checkpoint. No intermediate candidate is published; interruption abandons the
whole workflow execution.

### 20.6 Code repair

Compiler/linter/test repair is scoped to the smallest semantically coupled unit supported by the diagnostic:

- one scalar/config value;
- one import declaration;
- one declaration or function;
- one patch hunk;
- one file when the tool cannot localize further;
- one tightly coupled declaration/reference group within a single authorized file when no smaller parser-valid unit exists.

- The repair request includes the failing diagnostic, relevant excerpt, immutable
  requirement/plan context, allowed `fileId`, pre-operation revision, and exact replacement
  schema.
- It does not include other writable files.
- If the repair legitimately requires a different file, the current task proposal is
  structurally incomplete; execution follows the explicit upstream-rework protocol rather than
  expanding scope silently.

### 20.7 Command execution

Only engine-derived mandatory commands and validated model-requested optional command IDs can run. The model may not create a command or omit a required one. The command runner:

- executes `executable` plus argv without a shell;
- uses a contained working directory;
- supplies only allowlisted environment variables;
- enforces timeout, output limit, network policy, and mutability class;
- treats bounded stdout/stderr and exit status as raw observations; only a validated typed command result becomes evidence;
- treats a non-success exit as a diagnostic;
- snapshots/diffs declared effects after every mutating command and exposes no undeclared result to commit;
- never interprets command output as model instructions.

- Every command process tree is confined by its declared OS sandbox or container boundary, not
  post-hoc diffing alone.
- The runner validates exact command authorization, candidate revision, environment, resource
  bounds and write authority before the call.
- No durable command-boundary record or checkpoint is required.
- The result and subsequent evidence stay in the current workflow candidate.

- Dependency-mutating commands run only in the task overlay and require task-approved
  manifest/lockfile IDs that also match the command authorization and per-file delta kind.
- A command cannot delete an update-only record, replace a create-only target, or create an
  update-only target merely because its path matches.
- Delete requires the file's delete capability, task authorization, command policy, and the
  global delete gate.
- Symlinks, devices, sockets, and other special-file deltas are always rejected.
- Externally irreversible effects are not automatically executed; they block for explicit
  policy/user authorization.

- Every mutating command runs in a `CommandSavepoint` bound to the exact discriminated overlay
  binding in its authorization.
- `promote_intersection` is valid only with a task-overlay binding; a final-validation binding
  requires `discard_all`, empty promotable files, and an exact validation-overlay revision.
- For final validation, `CreateCommandSavepointAction` calls the dedicated overlay-port
  child-create method and always returns the closed created-or-adapter-failed outcome.
- `ValidateFinalValidationCommandSavepointCreationAction` proves the structural
  authorization/savepoint/parent/header/owner/feature-lock joins and absence of a task adapter
  record before `RunConfiguredCommandAction` is reachable.
- An adapter failure, indeterminate publication, or invalid observation makes execution
  unreachable and authorizes only recursive removal addressed by the already validated parent
  header; the engine never trusts or addresses the candidate child.
- A failed process may have written partial files, but those bytes remain confined to the child
  savepoint and are discarded.
- Promotion requires successful exit evidence, a valid command-delta record, and a
  compare-and-swap against the unchanged task-overlay revision.
- Promotion invalidates prior evidence for every affected file; the engine reruns affected
  deterministic validators and required tools.

- Immediately before whole-output validation, final validation is non-promoting: truly read-only
  commands run with writes mechanically denied, while React/Vite, Maven/Gradle, MSBuild, test,
  and similar tools may write only their declared ephemeral outputs inside a disposable child
  savepoint.
- The engine diff-gates that savepoint and invokes `DiscardCommandSavepointAction` for
  successful `discard_all` as well as failed/invalid outcomes, so all bytes are discarded
  regardless of exit status.
- The final branch uses only
  `FinalValidationOverlayPort.discardFinalValidationCommandSavepoint`, then a separate
  inspection action captures raw child presence/bytes, parent revision, task-record count,
  completeness/ceiling flags, and adapter identity.
- `ValidateFinalValidationCommandSavepointDiscardAction` accepts only a complete independent
  postcondition proof; any adapter-indeterminate, residual, incomplete, mutated-parent, or
  mismatched result forbids verification and routes to parent-only recursive abort.
- `ValidateFinalValidationOverlayDiscardAction` returns a discriminated normal discard or
  recursive-abort evidence.
- Only normal evidence can enter `FinalValidationRecord`; recursive-abort evidence contains the
  typed child failure/rejection and zero-residual parent-tree proof without pretending that an
  untrusted child had ordinary child-discard evidence.
- A final command that requires a persistent write is invalid policy; that mutation must be an
  earlier task-authorized operation/command followed by revalidation.

### 20.8 Task validation within the atomic workflow

A task becomes a validated candidate only after its authorized operations,
path/write-set checks, required commands, manual evidence and dependent
validation pass. Its runtime state and rendered view remain private to the
current workflow execution. No task independently publishes project changes,
completion state or `[X]`.

The complete implementation workflow must pass its final gate before
publishing the complete project delta, evidence, runtime state and views.
There are no task transactions, commit markers or recovery checkpoints.

### 20.9 Failure propagation

- A failed task blocks its dependents.
- Unless an explicit YAML branch repairs the candidate within its declared retry limit, the
  workflow ends with its exact failed/blocked/cancelled outcome and abandons all candidate
  output.
- Successful sibling tasks are not independently published.
- Retry exhaustion never weakens policy or accepts invalid code.
- A subsequent invocation starts the whole workflow again, not from completed task markers.

### 20.10 Final implementation gate

Final checks run against the complete private workflow candidate, never by
mutating previously accepted project output. Commands remain named,
shell-disabled, sandboxed and limited to their declared effects. Disposable
validation output is not part of the published project delta.

- Completion requires the exact current approvals, no outstanding upstream clarifications,
  complete task/dependency coverage, authorized changes, all required passing evidence and the
  complete rendered/state output.
- A failed final check may take only a declared YAML repair branch within its explicit retry
  limit; otherwise the entire execution is abandoned.
- There is no failed stage transaction, independently committed remediation, task checkpoint or
  restart continuation.
