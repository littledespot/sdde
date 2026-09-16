# 18. Plan stage design

Part of the [proposed design](../design.md#18-plan-stage-design). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

### 18.1 Inputs and preconditions

The selected `plan` workflow receives the explicit feature directory through
its YAML-named invocation contract and validated run context (ADR 0010).
`tasks` and `implement` use the same directory-based selection. No workflow
counts directories, derives a name, registers ownership or auto-selects a feature.

The stage gate:

1. requires current validated specification authority; each Plan invocation starts from its graph start and revalidates every input, without restoring an execution;
2. requires and parses `spec.md`;
3. requires `reference-context.md` and its canonical snapshot/view binding for every feature;
4. loads the clarification registry/forms and returns nonzero `UPSTREAM_SPEC_CLARIFICATION_OPEN` if any `SNN` remains open;
5. revalidates specification structure, IDs, typed clarifications, and sidecar completeness;
6. builds the current `RequirementIndex` and token/scope obligation ledger;
7. rejects unresolved reference-conflict records;
8. confirms resolved environments still match the current repository;
9. builds/validates the normalized editable-spec authorities, baseline file and repository-fact registries, configured read-only research evidence, complete principle selection, and initial `PlanIdLedger`, then retains one validated `PlanInputAuthorityState` candidate before the first plan model call. An authenticated edit and its acknowledgement/passive/provenance candidates remain bound to that input; any persisted clarification must carry the complete stable support required by its own contract.

- The pre-generation boundary also rebuilds the shared authority-requirement projection for all
  planning-owned decision slots.
- A successful specification or preserved upstream obligation is not itself proof that the
  project can implement it: every required design, architecture, policy, repository/capability,
  dependency, and verification-strategy resolution must have exactly one current supported
  outcome before plan content may commit.

- Starting `plan` treats the current validated `SpecificationIR` as the user's approved planning
  input.
- The engine retains it in an immutable `PlanInputAuthorityState` candidate; successful Plan
  publication includes that authority and a `PlanState` bound to it.
- A later spec edit invalidates the current input/plan descendants through direct typed
  comparison without a fingerprint.

- The editable-file boundary is deterministic and authentication-gated.
- On every plan entry, the engine captures the complete current `spec.md` through the registered
  no-follow path and directly compares its parsed typed value with the current canonical
  specification.
- Equal content takes the closed unchanged-spec branch and consumes no authentication lease or
  ID.
- Different content takes the edit branch: capture into a run-local handle; parse and build the
  full add/modify/remove change set; then validate expected
  workflow/view/provenance/acknowledgement revisions, round-trip, record-ID/tombstone legality,
  boundedness, and protected structure **before** consuming authentication.
- A stale or malformed edit is rejected without authenticating.
- A valid changed file without a fresh runner-issued `specification_edit` lease exits nonzero
  with `SPEC_EDIT_AUTHENTICATION_REQUIRED`; it is not sent to an LLM and is not treated as
  authority.

- Only after static validation does `AuthenticateActorAction` consume the single-use lease.
- Validate the returned actor evidence and bind the complete change set to exact
  workflow/view/provenance/acknowledgement revisions and the captured file identity.
- Rebuild normalized specification, passive-literal and provenance candidates; add
  acknowledgements only for added or modified records, and retain removals in the edit event.
- Validate coverage, IDs, actor joins and capture freshness before any dependent model work.

- Candidate records expose no handle, lease, credential or filesystem capability.
- They are published only with the complete owning output or the permitted clarification output.
- Failure abandons private candidates; there is no failed-edit retirement transaction, journal,
  before-image rollback or persisted continuation.
- The engine assigns output paths directly and never runs a setup script that overwrites
  `plan.md` before validation.

### 18.2 Deterministic repository reality

Before an LLM design call, actions perform a bounded project-file discovery and build repository facts:

- manifests, modules/projects, dependencies, lockfiles, and package manager;
- source/test/style/config/asset roots;
- allowed extensions and filename patterns;
- existing application entry points discovered through configured adapters;
- existing test runners, scripts, fixtures, and verification commands;
- compiler, formatter, linter, AST parser, and import resolver availability;
- current files near requirement-relevant terms and known entry points;
- generated and forbidden paths;
- selected raw semantic-principle spans and the separately compiled project-toolchain layer;
- missing prerequisites where a required capability has no current command/tool.

- The scanner uses the same traversal-hard-limit pattern as reference enumeration.
- The traversal capability carries compiled project-discovery exclusions and the engine
  root-access registry.
- Before descending into a directory, enumeration evaluates those rules; an
  excluded/inaccessible subtree is not opened, and a prune record stores its canonical root,
  rule ID, access class, and descriptor evidence.
- Every encountered entry must later join either a canonical classified file, an explicit
  rejection, or one such prune record.
- Root-access/generated classification occurs before kind inference, so
  VCS/engine/workflow/reference/dependency roots cannot become ordinary files and generated
  inputs can receive only the narrow `generated_existing` read capability.

- The scanner then normalizes and collision-checks existing paths, sorts them by `(projectId,
  normalized path)`, infers exactly one existing file kind from the compiled preset languages,
  allocates monotonic file IDs, and constructs `repository_existing` or narrowly authorized
  `generated_existing` records.
- `FileRegistryState` owns `nextFileOrdinal` and retired IDs; surviving canonical paths retain
  IDs across revisions and retired IDs are never reused.
- Accepted planned path candidates—including the explicitly authorized raw-fallback variant—pass
  the same ownership/kind/path/portability chain and receive later IDs from that persisted
  allocator; a raw fallback's declared `projectId` mismatch is repaired as that one field and is
  never silently replaced by the actual owner.
- `BuildFileRegistryStateAction` rejects duplicate IDs/paths and produces the sole file
  authority used by planning and later stages.
- `PlanState` persists that complete registry.

- `BuildRepositoryFactRegistryAction` assembles the complete ordered typed set into
  `RepositoryFactRegistryState`.
- Each fact stores its value, value ID, evidence source, and gate policy; the registry itself
  receives an engine state ID, not a digest.
- `PlanInputAuthorityState` persists that fact registry, baseline file registry, configured
  research registry, exact specification/provenance/passive/reference bindings, and principle
  selection before generation.
- `PlanState` binds the input state and persists the successor sole file registry alongside
  `PlanIR`.
- `PlanIR` stores only `touchedFileIds` and `proposedFileIds`, never duplicate `FileRecord`
  values; every consumer resolves them through the bound registries.
- A `FactSelection` names a fact/value ID and is accepted only when that value resolves in the
  input authority.

- These facts are immutable model inputs.
- The LLM may interpret relevance, but may not claim that a dependency, command, folder, test
  suite, or entry point already exists unless it selects a supplied fact ID.
- A new dependency is a typed proposal, never a repository fact.
- At the tasks and initial implementation gates, the engine rebuilds current facts through the
  same adapters and compares typed values directly with persisted facts marked
  `must_equal_until_implementation`; an ID match without value equality is insufficient.
- A plan-time `transition_requires_task_binding` fact carries no future task ID.
- Task generation must create a validated `FactTransitionBinding {factId, taskId,
  transitionRuleId}` inside immutable `TaskDefinitionState`.
- Only that approved named task's validated execution evidence may satisfy the transition.
- Any other difference blocks for plan rework.
- This is value comparison, not hashing or fingerprinting.

- Phase-0 “research” is grounded only in the supplied reference snapshot, repository facts,
  compiled presets, selected raw project-principle spans, and evidence from version-pinned
  read-only registry adapters already configured and validated at bootstrap.
- The default engine performs no open-web research and defines no ad hoc evidence-import
  channel.
- When a decision requires unavailable external evidence, the model sets
  `unresolvedExternalEvidence: true`; the stage blocks with `RESEARCH_EVIDENCE_REQUIRED`.
- The user must add the material beneath the configured reference root and rerun
  specify/reference ingestion (thereby creating a new snapshot and normal invalidation), or
  configure a supported exact registry adapter and rerun bootstrap/planning.
- The engine does not let a model fill the gap from memory and label it researched.

### 18.3 LLM work

The LLM generates bounded plan units:

- summary and minimal-change hypothesis;
- implementation-shape decision;
- existing touched-area selection from engine-provided file/project IDs;
- proposed new file records, one or a small related group at a time;
- selections from typed repository/preset fact IDs plus separate technical rationale;
- research unknowns and one decision/rationale/alternatives record per question;
- typed new-dependency proposals containing ecosystem, package, version constraint, configured registry source, scope, and rationale;
- principle-consideration reasoning, exact source citations, and justified deviations;
- data/state entity models when applicable;
- the smallest justified structured contract obligations when applicable;
- quickstart scenarios;
- requirement-to-design/verification mappings;
- task-generation approach.

- Each declared plan model operation returns `PlanUnitOperationResult`: either one content unit
  or one typed clarification need.
- When an architecture, dependency, verification, repository, or policy decision cannot be
  supported by the supplied current authorities, the model must request clarification; it may
  not choose a plausible default from memory.

- The shared reconciliation outcome, not a domain-specific prompt instruction, decides whether
  support exists.
- A zero match, multiple non-equivalent matches, ambiguous principle interpretation, unsupported
  repository/capability claim, missing required decision, or stale authority routes to `PNN`
  when planning owns the slot.
- The planner cannot silently create an authority, select a nearest/conventional option,
  reinterpret an upstream obligation, or record the gap as accepted technical debt.
- A current authenticated exception is usable only when its typed scope exactly covers the
  requirement.

- Filename variability is removed at the plan boundary.
- Existing files are selected only by engine `fileId`.
- For a new file, the workflow-declared path-intent model operation first returns an ID-only
  `PathIntentProposal`—one engine-supplied `pathIntentOptionId`, one allowed semantic
  `nameSourceId`, an optional placement-anchor file ID, and requested create/copy
  capabilities—with no filename field.
- The option already binds the exact project, environment, kind, semantic role, templates, and
  capability ceiling, so model fields cannot be recombined into a more permissive policy.
- Actions resolve the option, apply registered versioned name/directory transforms, run the
  complete path/portability/collision algorithm, enforce deterministic ordering and the
  candidate ceiling, assign `pathCandidateId`s, and build a finite `PathCandidateRegistry`.
- The workflow-declared plan-unit result maps its local `proposalKey` only to one allowed
  `pathCandidateId`.

- The hardened default sets `allowRawPathFallback: false`.
- A specialized preset may explicitly enable fallback only when its accepted contract declares a
  non-enumerable naming case.
- Zero candidates, a candidate-limit failure, or an unknown transform never activates fallback.
- In the authorized branch the model's complete `ProjectPathCandidate` is create-only and passes
  the identical normalization/kind/root/name/extension/placement/portability chain plus atomic
  field repair before the engine adds it to the candidate registry.
- Its complete mechanical guidance is never truncated; provider size failures follow the
  explicit YAML outcome transitions.
- Thus a raw LLM filename is never canonical merely because it is schema-valid.

- Each selected absent candidate receives a stable `fileId`; an existing selection retains its
  discovered ID.
- `ImplementationShapeProposal.fileSelections` pairs that selection with requested
  intent/capabilities, and `BuildPlanFileGrantAction` intersects them with the file kind's
  policy ceiling.
- Canonical `PlanIR` stores only file IDs and `PlanState` persists the sole `FileRegistryState`,
  exact grants, and candidate registry.
- Plan/task renderers resolve display paths from that state; task and implementation model
  schemas carry only `fileId`s.
- A rename is a new plan/candidate/file-state decision that clears plan/task approval, never a
  task-level spelling repair.

- All other cross-linked plan records follow the same proposal/canonical split.
- The model supplies bounded local keys for design units, entities/fields, contracts, scenarios,
  research decisions, and dependency proposals; coverage and relationships refer only to those
  keys or allowed upstream obligation IDs.
- After every plan unit is present, actions validate unique keys and total references, build one
  complete proposal index, sort by closed kind rank and Unicode-scalar qualified key, allocate
  monotonic IDs from `PlanIdLedger`, and materialize each canonical record.
- No `PlanUnitProposal` admits a canonical engine ID.
- `PlanState` persists the final ledger and a `PlanReviewUnitRegistry` mapping every reviewable
  record to a fixed or engine-owned selector, so targeted rejection after restart never relies
  on prose or array position.

### 18.4 Plan clarification behavior

- A plan need is deduplicated through the shared registry and allocated `P01` through `P99` only
  when its subject key has never existed.
- Its only path is `<paths.specs>/<featureId>/clarify/PNN.md`.
- The complete clarification output binds a new/reused open record and successor
  `PlanInputAuthorityState` to the next clarification revision. It enters
  `plan_clarification_pending` only after successful publication under §§23.2 and 25;
  failed writes may leave replaced files but cannot record new successful completion.
- Its `PlanIdLedger` includes every path-candidate/research allocation or tombstone consumed
  before the pause, so full-stage regeneration cannot reuse an abandoned ID.
- No candidate `PlanState`, path-candidate record, accepted content unit, or plan view is
  committed, and a `PNN` cannot cite such uncommitted records.

- On a later Plan invocation, reject open `SNN` first, then recapture current
  reference/specification/provenance, principles, presets, repository facts and configured
  research evidence.
- Rebuild and validate Plan's immutable input before any dependent model call; no planning
  checkpoint is published.
- An open `PNN` uses the shared clarification output and cannot be bypassed by a runtime
  refresh.
- Raw reference changes return through Specify and invalidate affected descendants.
- Close a `PNN` only through current non-conflicting authority resolution or a revision-current
  authenticated answer.
- Otherwise retain its ID and replace only its writable form under §23.2.
- After resolution, regenerate the complete Plan workflow and validate it before publication.

`plan.md` and its design artifacts remain read-only. The clarification form is the only file-based plan feedback/answer channel; direct plan edits are never imported.

### 18.5 Artifact applicability

The engine requires these decisions:

| Artifact | Disposition |
| --- | --- |
| `plan.md` | Always required |
| `research.md` | Always required; may state that no unresolved technology choice existed, but must still record grounded decisions |
| `quickstart.md` | Always required; contains executable automated/manual validation scenarios |
| `data-model.md` | `required` when the feature introduces or changes data/state concepts; otherwise explicit `not_applicable` with reason |
| `contracts/` | `required` only when a structured interaction/API/event/file/schema contract adds planning value; otherwise explicit `not_applicable` with reason |

- The model proposes applicability reasoning.
- A semantic-review action may challenge it.
- The engine validates that the declared disposition and actual artifact set agree; it never
  infers applicability from a missing file.
- The workflow artifact registry owns one `contracts/` collection root.
- After contract IDs exist, `BuildContractViewRegistryAction` derives every contained view
  filename solely from the engine contract ID and the registered schema-to-extension table, and
  portability validation rejects collisions.
- The model's contract name/key never becomes a path.
- The resulting per-contract selector/path registry is persisted in `PlanState`; the aggregate
  `ArtifactDecision` names the collection root while each `GeneratedView` uses an exact `{kind:
  contract, contractId}` selector.

### 18.6 Deterministic plan validation

Validators enforce:

- feature ID, date, and spec link match engine facts;
- mandatory plan IR fields and artifact decisions exist;
- every mechanical technical assertion is a typed `FactSelection` whose ID/value matches repository/preset facts; prose rationale receives semantic review and is not claimed to be mechanically contradiction-free;
- every touched existing file exists and is within the selected project;
- every new/update path passes the complete planning-time lexical/structural preset algorithm, and every unavailable content-dependent check is registered as a mandatory implementation validator;
- proposed paths use accepted `fileId`s consistently;
- no persistent foreign absolute paths;
- minimal-change claims do not list rejected layers as proposed outputs;
- research records contain decision, rationale, alternatives, source/fact links, and no unresolved external-evidence flag;
- each dependency proposal names a configured registry source and allowed version form and passes package/source policy; approval of the exact `PlanState` approves all dependency proposals contained in that state for later setup-task generation, but does not claim any package is installed;
- entity names/references and relationships resolve within the data-model IR;
- format-specific contract artifacts pass their registered schemas when a validator exists;
- quickstart scenarios have complete typed automated/manual steps and reference real requirements/tokens/guards; whether a prose scenario is adequate remains semantic unless an executable command/assertion proves it;
- configured automated verification references only available command IDs;
- unsupported automation has a prerequisite decision or an explicit manual scenario;
- every `AC-*`, `FR-*`, and `EC-*` has exactly one normalized coverage entry;
- business rules, exact copy, scope guards, visible states, accessibility/responsive obligations, and preserved tokens in the internal obligation ledger have design/verification coverage or an explicit blocking gap;
- every required preserved token is carried by obligation ID; visual token kinds additionally have a manual visual-verification expectation;
- every planning-owned required decision has one successful shared authority-reconciliation outcome; every missing, ambiguous, conflicting, multiple, stale, or unsupported outcome has become a `PNN`, upstream rework, or administrative block rather than plan content;
- all planning artifacts remain under the feature directory;
- no repository implementation files or `tasks.md` are staged or changed;
- progress status is engine-derived: planning phases complete only after their validators pass, and implementation phases remain incomplete;
- every read-only planning view exactly equals deterministic rendering from validated canonical `PlanIR`.
- no `SNN` or `PNN` clarification remains open.

### 18.7 Plan outputs and gate

- Immediately before publication, reread `spec.md` and compare its full normalized IR with the
  retained Plan input.
- A changed input invalidates the candidate; a fresh invocation starts from `start` and
  validates the edit.
- Never overwrite a newer edit or use a fingerprint as a substitute for direct comparison.

- `PlanInputAuthorityState` owns the exact normalized specification,
  acknowledgement/provenance/passive/clarification bindings, bootstrap/reference/
  principle/repository/baseline-file/research authorities and starting plan-ID ledger.
- `PlanState` references that input and owns the final plan outputs and successor ledger,
  without copying those authorities.
- Validate every join and publish the complete input, output, views and workflow-state set under
  §25.
- Successful generation enters `plan_review_pending`; the user reviews the plan, research,
  design, contract and quickstart views.

- Approval is recorded against the current `planStateId` and advances state to `planned`.
- Rejection supplies feedback through the engine. Actions map it to explicit plan unit IDs; those units are repaired/regenerated, full validation/rendering reruns under a new state ID, and review restarts. Generated files are not edited.

`plan` is complete only if:

- specification preconditions remain valid;
- repository facts/preset selection are unambiguous;
- Phase 0 research records pass;
- Phase 1 artifact manifest and artifacts pass;
- Phase 2 task-generation approach passes;
- all coverage obligations pass;
- no specification or plan clarification remains open;
- no implementation-side change occurred;
- the complete validated output is successfully published;
- current canonical plan state has explicit approval;
- workflow state transitions `specified -> planning -> plan_clarification_pending -> planning` as needed, then `plan_review_pending -> planned`.
