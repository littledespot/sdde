# 24. State, sequence, and recovery without fingerprints

Part of the [proposed design](../design.md#24-state-sequence-and-recovery-without-fingerprints), as amended by the
[accepted ADRs](../design.md#32-accepted-and-deferred-implementation-choices).

### 24.1 Workflow state

- The selected workflow execution carries current state in memory, but crash/restart authority
  for the initial SDD suite is always persisted at the required `WorkflowCanonicalState`
  singleton selected by the validated `WorkflowArtifactRegistry`.
- The registry unambiguously binds `canonicalSpecsFeatureRoot` to `<paths.specs>/<featureId>`
  for specification views/forms/logs, `canonicalEngineFeatureRoot` to
  `<paths.workflows>/features/<featureId>` for engine-owned feature data, and
  `canonicalEngineStateRoot` to that engine root's `state/` child.
- `WorkflowCanonicalState` resolves its state-root-relative child `workflow.json` beneath
  `canonicalEngineStateRoot` (equivalently feature-relative `state/workflow.json`).
- The exact result is `<paths.workflows>/features/<featureId>/state/workflow.json`; logs remain
  beneath `<paths.specs>/<featureId>/logs/`.
- These paths are neither optional nor ad hoc and cannot be independently configured, supplied
  by a model/workflow definition, or replaced by another state layout:

[View the Workflow state sample](../code.md#workflow-state).

Published reference snapshots retain the exact extraction-contract comparison
evidence defined by [§12.7](12-model-boundary.md#127-workflow-defined-model-operations).
Readback resolves current compiled authority and rejects missing or changed bindings
before model calls; it never executes persisted contract bytes.

Completed and clarification-pending specification state share one versioned
`specification-state` contract (currently v24,
[ADR 0015](../decisions/0015-specification-principle-review.md),
[ADR 0023](../decisions/0023-advisory-post-generation-review.md) and
[ADR 0038](../decisions/0038-record-claims-and-scenario-coverage.md) Decision 7; v25 is
reserved for the `spec_incomplete` variant of
[ADR 0041](../decisions/0041-failed-run-incomplete-publication.md), accepted, on hold
since 30 October 2026, not implemented) over canonical `specification/v5` content, in which
an edge case holds the ID of the acceptance criterion it links to and readback checks the
link against the candidate rule of ADR 0038 Decision 7;
stage discriminators distinguish the variants. Earlier versions reject without
migration, aliases or a compatibility reader. The completed variant keeps the captured
principle registry identity as its own `principle_registry` field, which the next
run's capture reads as its prior registry. The pending variant retains reference and
clarification data without claiming completed attributed content. Changed authority
invalidates affected descendants through the stage rules below.

- **Associations.** State stores required `source_group_ids` inside attributed
  values and shared-provenance records, with no persisted presentation roles and
  no change to general `Selection`/`Provenance` or a parallel association registry.
  Readback resolves those exact captured group occurrences, preserves complete
  member order and legitimate overlap, then recomputes explicit support and lineage.
  Missing, foreign, inactive, stale or inconsistent associations reject; equal claim
  lists or displayed bytes cannot replace an occurrence, and stored projection errors
  are never repaired by substituting a fresh union.
- **Exact values.** Readback validates exact handles against the current captured
  ledger and checks field roles, explicit `S`, derived `E` and `L`, citations and
  coverage (ADR 0020). It recomputes native token
  classification, dispositions and complete original-occurrence coverage (ADR 0024).
  Inconsistent stored authority rejects instead of being inferred from matching
  display bytes. Request-native exact scope binds its snapshot and eligible occurrence
  bytes; `model-request-debug/v16` retains it for diagnostics, not state recovery.
  Published-state validation needs no model request, historical capture or operation
  port.
- **Review evidence.** State holds no review evidence (ADR 0023). Source-review
  findings, including §12's nullable `authority_gap` and ADR 0023's source-only
  readiness evidence, are execution-local, and readback restores none of them.
- **Text wire.** Model-facing prose/composition conversion is never applied to
  persisted authority to guess a missing fragment, separator or source occurrence.

It contains no content hashes or fingerprints. Preset IDs/versions and artifact paths are metadata, not freshness proofs.

Every fresh invocation starts at `start`.

### 24.2 Stage transition state machine

[View the Stage transition state machine sample](../code.md#stage-transition-state-machine).

- Each in-progress execution can terminate as `blocked`, `failed`, or `cancelled`.
- `spec_incomplete`, with a closed cause (`failed` or `blocked`), records a Specify run
  that failed or was blocked but published its validated content as an incomplete
  specification
  ([ADR 0041](../decisions/0041-failed-run-incomplete-publication.md), accepted, on hold
  since 30 October 2026; not implemented). It is written
  last, replaces any earlier completion authority, blocks Plan and later stages, and is
  never resumed: the next run starts at `start`.
- Prior published state remains subject to fresh gate validation; it cannot resume the abandoned
  execution.
- Generated definition state is committed before entering its review-pending state.
- `planned` and `tasked` are entered only after approval tied to the exact current plan or
  task-definition ID.

- `spec_clarification_pending`, `plan_clarification_pending`, and `tasks_clarification_pending`
  are non-failure pauses with a committed clarification-registry revision and no newly accepted
  stage IR.
- A current validated authority resolution or authenticated response to the current record
  revision returns to `specifying`, `planning`, or `tasking`; the clarification response
  publication commits first, then every generation unit in the owning stage is regenerated from
  its current complete authority set.
- No pre-clarification unit candidate, merge result, or partial stage checkpoint is reused.
- If the user explicitly chooses `defer` while the answer is required, the same record remains
  open; `cancel` is a separate terminal transition.
- No default is invented, and a valid clarification pause consumes no operation-local retry.

- The closed downstream matrix is: plan requires no open `S`; tasks requires no open `S/P`;
  implement requires no open `S/P/T`.
- Each failure names the exact open IDs and form paths and returns nonzero.
- Review-pending states are reachable only after their stage's allowed prefix set is closed.

### 24.3 Gate behavior

State alone never authorizes a stage.

- The complete clarification registry and responses, including resolved records, persist
  across executions; Section 23.2 and [ADR 0009](../decisions/0009-atomic-workflow-execution.md)
  own rerun form replacement and user-closed protection.
- Reruns use applicable validated answers before proposing new questions.
- Deduplication uses the stable target, earliest owner, requirement kind, subject selector and
  required slot; execution IDs, regenerated authority IDs, wording and transient gap reasons do
  not define a new clarification.
- Current applicability is validated separately; changed evidence may reopen only an unprotected
  record.
- Section 23.2 preserves user-closed forms and blocks a still-required subject whose protected
  answer is no longer applicable; it never allocates a duplicate.
- Ambiguous subject correspondence blocks rather than using fuzzy text matching.

- The editable `spec.md` is reparsed and fully validated.
- The current clarification registry and exact `clarify/` inventory are parsed/validated; only registered current-revision answer regions are imported, and the requested stage's closed-prefix matrix is enforced.
- When canonical plan state exists, the engine compares current normalized `SpecificationIR` directly with the stored plan-input `SpecificationIR`. A difference invalidates plan/task canonical state and approvals and returns the workflow to `specified`.
- Canonical reference, the published `PlanInputAuthorityState`, its bound `PlanState`, task-definition, and task-runtime IR are loaded from engine state and revalidated directly.
- Current repository facts are rebuilt. Each gate-sensitive value is directly compared through `CompareRepositoryFactValueAction`; during implementation, only a `transition_requires_task_binding` fact with a matching approved `FactTransitionBinding`, transition rule, and validated named-task execution evidence may differ from the plan input. An unexplained difference triggers the relevant plan/task reconciliation path.
- The complete authority-requirement and reconciliation projections are rebuilt from current canonical inputs. Any non-success entry blocks the requested stage and routes by its compiler-locked earliest owner; a downstream gate cannot treat predecessor success, an old approval, or existing code as a substitute resolution.
- Read-only views are compared byte-for-byte with deterministic rendering from their canonical IR. A changed view is regenerated or blocks; it never changes execution state.
- The next stage requires an approval record whose `planStateId` or `taskDefinitionStateId` equals the current immutable definition state. Runtime-only task progress does not affect approval.

No hashes or fingerprints are created. Direct typed-state/view comparison is possible because the workflow is ordered and the engine already owns canonical plan/task inputs. A future generalized out-of-band freshness system would be a separate design decision.

### 24.4 New execution after interruption or clarification

- An interrupted execution is abandoned, not recovered or resumed.
- A new invocation enters the selected compiled graph at `start` and revalidates current inputs,
  predecessor state, approvals and ownership required by its declared operations.
- Existing files, logs, partial candidates and model responses are not continuation authority.

Clarification identity, protected forms and relevant validated answers survive
under Section 23.2. A `needs_user` outcome ends the execution; answers become
inputs to a new beginning-to-end execution, not a saved-step continuation.

No transaction collection, WAL, checkpoint, provider-effect scan or recovery
lock precedes execution. Provider lifecycle, leases and total token usage are
fresh for each execution. A full rerun may repeat API calls; within-run retries
still require explicit YAML transitions and operation-local retry authority. Under
[ADR 0030](../decisions/0030-engine-owned-model-request.md) (not yet implemented), a model
request's protocol correction runs inside its `request-model` step, under that step's
`retry-limit`.

### 24.5 Upstream rework and invalidation

Backward movement requires a validated owner-derived rework outcome, not an
inference from a failed model call. Preserve every affected authority and
invalidation obligation; the detecting component cannot choose a shallower owner.

| Changed authority | Owning route | Invalidated descendants |
| --- | --- | --- |
| Reference or reference-ingestion/specification contract | Specify; reingest when the reference contract changed | Affected reference/request/provenance, Plan input, plan, tasks, runtime/evidence and approvals |
| Authenticated editable specification | Retain the validated edit, then Plan | Plan input, plan, task definitions, views, runtime/evidence and approvals |
| Toolchain, environment, path, parser, command, dependency or capability policy | Plan under the new validated mechanical authority | Plan/task definitions, views, runtime/evidence and approvals |
| Semantic principles | Recapture at the consuming gate; Plan retains policy-resolution ownership | Plan input and affected downstream authority; preserve unchanged source-derived business content |
| Plan decision/review feedback | Plan, then renewed Plan and Tasks review | Current plan approval and affected tasks/runtime/evidence/approval |
| Task-definition feedback or gap | Tasks, then renewed task review | Affected task definitions/runtime/evidence and task approval |
| Compatible logging/model binding or unrelated workflow definition | Same semantic stage; validated runtime refresh | None when all feature-bound semantic authority remains equal |
| Unsupported project/artifact layout, bound workflow, serializer or renderer change | Administrative block; no implicit conversion | No pointer advance before an explicitly authorized complete resolution |

- Previously published project code is preserved.
- Reconcile affected published runtime/evidence before regenerating and approving replacement
  definitions; `implementation_reconciliation_spec | plan | tasks` records the owning route.
- Within an unfinished execution there are no committed tasks: abandon its private candidate
  rather than recovering or publishing individual task progress.

Plan approval revalidates the current specification/reference input. Task approval
also requires `TaskDefinitionState.inputPlanStateId` to match the current approved
plan. Stale approvals fail. `implemented` is forbidden while reconciliation,
required clarifications or missing current approvals remain.

- Build one complete invalidation/output candidate for the owning workflow.
- `ReviewDecisionRegistryState` retains immutable historical decisions; current state removes
  invalidated IDs from active approvals and records exactly which runtime/evidence became stale.
- Publish through §25, preserving §23.2's protected forms.
- A rejected review produces a new definition ID; an older approval cannot authorize it.
- No rework step introduces an independent transaction, task commit, rollback of accepted code
  or saved continuation.
