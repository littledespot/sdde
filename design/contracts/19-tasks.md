# 19. Tasks stage design

Part of the [proposed design](../design.md#19-tasks-stage-design). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

### 19.1 Inputs and preconditions

- The stage gate requires workflow state `planned`, an approval bound to the current
  `planStateId`, and an editable `spec.md` whose normalized IR equals the separately stored
  plan-input specification.
- It loads/validates the clarification registry and exits nonzero with
  `UPSTREAM_PLAN_CLARIFICATION_OPEN` if any `SNN` or `PNN` is open.
- It then revalidates the current `PlanInputAuthorityState` and bound `PlanState`, rebuilds
  repository facts and directly compares all gate-sensitive typed values with the input
  authority's registry, validates every required read-only view against deterministic rendering,
  and confirms that absent `not_applicable` artifacts have reasons.
- It uses the engine's canonical-state/artifact registry rather than a helper's incomplete
  `AVAILABLE_DOCS` list.

Actions build a complete `ObligationLedger` from:

- `AC-*`, `FR-*`, `EC-*`, and `BR-*` records;
- user-visible outcomes and states;
- exact-copy obligations;
- scope boundaries, non-goals, and prohibited behaviors;
- data/state obligations;
- contract obligations;
- research prerequisites;
- quickstart scenarios;
- accessibility and responsive expectations;
- visual-system tokens;
- source-supported value-treatment rules;
- plan coverage entries and missing-repository prerequisites.

Obligations without public spec IDs receive internal stable IDs so coverage can still be checked mechanically.

- The task stage also derives task-owned authority requirements for executable decomposition,
  dependency, authorized work surface, command/scenario selection, and evidence binding.
- The ledger is complete only when every upstream obligation and every task-contract-required
  field participates; task generation cannot omit a difficult obligation or invent a local
  execution decision to make the graph close.

### 19.2 LLM work

The LLM receives one related obligation cluster through a declared model operation and returns `TaskClusterOperationResult`: task proposals or one typed clarification need. It decides:

- useful work decomposition;
- one clear responsibility per task;
- implementation versus integration versus verification intent;
- semantic dependencies;
- whether related obligations can safely share a task;
- manual scenario selection when no automation exists;
- descriptive wording.

It must select files by existing `fileId` where the plan already identified them. If a new path is genuinely required but absent from the plan, the response is invalid and planning must be repaired/re-run; tasks cannot silently expand architecture.

- More generally, a gap whose ownership registry names `plan` or `spec` takes explicit upstream
  rework and complete descendant invalidation; it never becomes a `TNN` merely because tasks
  discovered it.
- A `TNN` is valid only for a task-owned required slot that cannot be reconciled from the
  current approved authorities.

- The LLM returns only `TaskDefinitionProposal`.
- It does not assign `TNNN`, checkbox text, `[P]`, final ordering, runtime status, canonical
  evidence, resource locks, or arbitrary commands.
- A proposal carries `obligationIds` from the task-local `ObligationLedger` allowlist—never a
  generic `sourceId` that could collide with a reference-source namespace.
- It may return `CommandSelection {commandId, typedArguments}` only; it cannot set
  `CommandInvocation.origin`.
- After validation, actions assign task IDs, resolve internal-key dependencies and any
  red-to-green target to canonical task IDs, construct model-optional and engine-required
  command invocations, derive mandatory evidence predicates/resources, and finally build
  canonical `TaskDefinition` records.

- Shared resources are never free strings or paths.
- The engine builds a closed `SharedResourceRegistry` from known manifest/lockfile file IDs,
  project/schema/generated-index adapters, and command capabilities.
- Actions derive the complete resource set and lock mode from task files, commands, project
  ownership, and registered adapters, validate every ID/mode, and construct `SharedResourceLock`
  records; the model cannot select, mint, or suppress a lock.

- Evidence expectations use the closed, kind-discriminated `EvidencePredicate` union.
- Each variant accepts only the IDs and fixed status semantics appropriate to a precommit
  validated file delta, configured command, intended-red diagnostic, parser/resolver, manual
  scenario, or task delta.
- `FileDeltaValidatedPredicate` can be satisfied from validated candidate-overlay evidence; it
  never claims that project bytes are already published.
- Durable file completion requires successful whole-workflow publication under §25.
- `mustBecomeGreenByTaskId` is produced only after the proposal's internal key has resolved
  through the assigned task-ID map.
- There is no arbitrary `expected` value or free-form assertion that a model can make true by
  wording it differently.

- After all clusters have schema-valid proposals, the engine builds a `TaskProposalGraph` keyed
  only by unique `internalKey`s and creates a compact global index containing those keys,
  responsibility, obligation IDs, produced/consumed `fileId`s, capabilities, and existing edges.
- A bounded dependency-reconciliation model operation declared by the workflow may propose
  missing internal-key edges over that index.
- For large graphs that operation processes overlapping partitions and a final compact boundary
  index.
- The engine validates every proposed edge, then runs proposal-graph unknown-node, cycle, and
  phase-edge actions.
- After deterministic topological ordering it assigns `TNNN` IDs, resolves every dependency and
  red-to-green internal key through that map, derives commands/evidence/resources, builds
  canonical task definitions, constructs the final ID-keyed graph, and reruns
  `ValidateCanonicalTaskGraphAction`.
- The model may suggest semantic dependencies; only the engine merges them.
- No canonical task or graph is required before the IDs it contains exist.

### 19.3 Tasks clarification behavior

A task-generation need is deduplicated through the shared registry and allocated `T01` through `T99` only for a new subject. Its exact path is `<paths.specs>/<featureId>/clarify/TNN.md`. The clarification publication enters `tasks_clarification_pending` without committing a candidate `TaskDefinitionState`, runtime state, or `tasks.md`.

- On a subsequent tasks run, the engine first rejects any open `SNN`/`PNN`, then refreshes the
  current approved plan/spec/reference/principle/repository authority set.
- A reference/spec/plan change is routed through and approved at its owning upstream stage
  before task generation resumes; tasks never absorb an upstream change into a hidden local
  answer.
- A current non-conflicting authority resolution or revision-current authenticated closed `TNN`
  form closes the existing record.
- The engine regenerates the complete tasks stage, reruns global graph/coverage checks, and
  allocates no duplicate clarification ID.
- Unresolved `TNN` forms are completely overwritten at the same IDs/paths on each rerun under
  Section 23.2; user-resolved forms remain unchanged.
- `tasks.md` remains a read-only projection.

### 19.4 Deterministic task validation

Each proposed task must have:

- one allowed phase and kind;
- one concise responsibility;
- a non-placeholder description;
- at least one known obligation/source ID;
- one or more declared read and/or write `fileId`s for file work;
- or one concrete configured command/scenario for a verification-only task;
- dependency keys that exist after merge;
- a verification mode and evidence expectation appropriate to its kind.

- Every `fileId` resolves to a plan-approved path that is revalidated against the selected
  preset and plan authorization.
- Automated verification commands must exist in the available command registry.
- Mandatory checks are derived by `DeriveRequiredChecksAction` from task kind, file kinds,
  evidence policy, and later the implementation diff.
- A model may request only an optional additional command from the supplied registry.
- Test paths must match the configured test type, roots, extension, naming, and placement.

Phase/kind/mode compatibility is closed and validated:

| Task intent | Allowed placement |
| --- | --- |
| Setup/prerequisite | `setup` before consumers |
| New automated behavior check | `automated_verification` with `red_then_green`; expected red evidence must name the intended assertion/diagnostic and the dependent implementation task that must turn the same check green |
| Existing regression/check | `automated_verification` with `existing_check`; may run at the dependency-appropriate verification or integration point |
| Source/integration change | `source_change` or `integration_change` in implementation/integration |
| Manual observation after code | `manual_verification` with `manual_after_change` in integration/polish, after the changed behavior exists |

An expected command failure counts only as bounded red evidence when the configured check reaches the intended assertion/diagnostic; an unrelated syntax, import, setup, or infrastructure failure does not satisfy it. Final completion requires the same check to pass.

Global validators then:

1. deterministically deduplicate only normalized byte-equivalent records whose responsibility, sources, file IDs, commands/scenarios, and verification are identical; semantic equivalence is model-assisted and never silently merged;
2. build dependency edges;
3. reject unknown dependencies and cycles;
4. reject dependencies that contradict immutable phase constraints;
5. merge validated cross-cluster dependency suggestions and add mechanically required setup-before-capability edges from declared prerequisites;
6. validate `red_then_green`, `existing_check`, and `manual_after_change` phase/dependency/evidence rules;
7. check every required obligation has implementation and/or verification coverage according to its coverage rule;
8. require both implementation and verification coverage for value-treatment behavior;
9. require implementation coverage for every preserved-token obligation and manual visual-verification coverage for visual token kinds;
10. require explicit preservation work for prohibited behavior when code could otherwise introduce it;
11. reject any path outside the plan-selected surface;
12. calculate safe parallel eligibility from transitive dependencies, write/write conflicts, unsafe read/write conflicts, shared-resource locks, and exclusive command capabilities;
13. topologically order tasks within the required phase progression;
14. assign `T001...` after final ordering;
15. render `[P]` only for engine-approved parallel tasks;
16. render all tasks initially as `- [ ]`.

The same validation pass requires one successful shared reconciliation outcome for every task-owned requirement. Coverage that merely names an obligation does not cure missing authority, and a task description cannot serve as a resolution.

A task that says only “review,” “analyze,” or “lock requirements” cannot pass unless its typed kind names a concrete configured verification command/scenario. Semantic task minimality can receive model-assisted review, but structural executability is deterministic.

### 19.5 Parallelism policy

A task is parallel-eligible only if all are true:

- it has no dependency path to or from another concurrently runnable task;
- write sets do not overlap;
- a read path is not written by another task unless the read is declared snapshot-safe;
- shared-resource locks do not overlap;
- neither task runs an exclusive or dependency-mutating command;
- neither task produces an input needed by the other;
- both can execute in isolated overlays and their candidate changes can be combined without conflict before whole-workflow publication.

The default execution concurrency is one. `[P]` describes eligibility; it does not force concurrent execution.

### 19.6 Rendering and gate

The renderer creates phase headings, `TNNN`, checkboxes, requirement source tags, paths, dependencies, and parallel examples from the validated graph. It does not ask the LLM to emit task Markdown.

- The engine commits the current clarification registry/forms, immutable `TaskDefinitionState`
  bound to its exact clarification-state ID/revision, revision-zero `RuntimeFileState`, empty
  revision-zero `ExecutionEvidenceRegistryState`, engine-owned `TaskRuntimeState` bound to both,
  and the read-only `tasks.md` view as the complete Tasks output under §25, writing workflow
  state last and entering `tasks_review_pending` only after all required writes succeed.
- Approval tied to the current `taskDefinitionStateId` advances to `tasked`.
- Rejection maps feedback to task unit IDs; if feedback exposes missing authority it follows the
  `TNN` lifecycle, otherwise the affected units are rebuilt/revalidated under a new definition
  ID and runtime revision zero.
- `tasks.md` is never imported as state.

`tasks` is complete only when:

- all predecessors revalidate;
- every task is executable and preset-valid;
- the graph is acyclic and fully resolvable;
- complete obligation coverage passes;
- no `SNN`, `PNN`, or `TNN` clarification remains open;
- parallel flags are engine-derived;
- rendered `tasks.md` exactly equals deterministic rendering of the current task definition ID and runtime revision;
- the complete validated output is successfully published;
- current immutable task definition state has explicit approval;
- workflow state transitions `planned -> tasking -> tasks_clarification_pending -> tasking` as needed, then `tasks_review_pending -> tasked`.
