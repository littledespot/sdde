# 2. Existing workflow used as the design basis

Part of the [proposed design](../design.md#2-existing-workflow-used-as-the-design-basis). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

### 2.1 Behavior to preserve

The predecessor toolkit defined a specification-first workflow in which requirements lead to design, design leads to an executable task list, and tasks lead to implementation (`README.md:3-9`; `docs/workflow-overview.md:86-90`). The new engine preserves these behavioral concepts:

- `specify` takes an explicit feature directory and an independent mandatory reference selector; it derives the human feature brief from the reference (ADR 0010).
- Every validated reference artifact is an authoritative input; `README.md`, when present, is an organizer and does not outrank sibling files (`prompts/sdd-specify.md:153-167`; `docs/reference-folder-example.md:58-63`).
- `spec.md` remains business-facing. Supplementary design, visual-system, technical, and verification detail is carried in `reference-context.md` (`prompts/sdd-specify.md:178-238`).
- `plan` uses the specification, its mandatory reference context, the current repository, and project principles to produce research and design artifacts (`prompts/sdd-plan.md:33-113`).
- `tasks` turns the plan and its artifacts into a dependency-ordered, traceable, executable task graph (`prompts/sdd-tasks.md:92-149`).
- `implement` executes that graph, applies relevant project principles, verifies work, and marks a task complete only after it succeeds (`prompts/sdd-implement.md:71-137`).
- Technology-agnostic workflow guidance becomes technology-specific only after the engine resolves the actual project environment (`README.md:315-328`).

### 2.2 Why a new engine is needed

- The predecessor material described deterministic operations as instructions for an LLM.
- A model was expected to parse arguments, run scripts, interpret output, choose paths, inspect
  files, decide whether gates passed, write artifacts, run implementation work, and update task
  state.
- Those steps can be skipped, misunderstood, or inconsistently applied—especially by a
  lower-capability model.

The predecessor source material contained useful examples of ambiguity that a deterministic engine must eliminate rather than ask a model to reconcile:

- Runtime prompts require a feature argument, while helper scripts and several flow documents support auto-selection (`prompts/sdd-plan.md:12-29`; `.specify/scripts/bash/setup-plan.sh:13-35`; `docs/flow-plan.md:5-17`).
- Feature target paths must be explicit and validated, not guessed from reference or model content.
- The prompt checks for `NEED CLARIFICATION`, while templates use `NEEDS CLARIFICATION` (`prompts/sdd-plan.md:55-68`; `.specify/templates/spec-template.md:22,65`). A string typo can therefore bypass a gate.
- Planning and task prompts try to infer whether a specification used references, while `spec.md` is explicitly forbidden from containing reference metadata (`prompts/sdd-specify.md:186,235-238`).
- The specify flow creates a feature directory before it checks whether the requested reference folder exists (`prompts/sdd-specify.md:109-157`). A failed precondition can therefore leave partial output.
- The prompt advertises a maximum generated-name length that the predecessor Bash and PowerShell scripts do not enforce (`prompts/sdd-specify.md:107-119`; `.specify/scripts/bash/create-new-feature.sh:29`; `.specify/scripts/powershell/create-new-feature.ps1:42`).
- Documentation treats some planning artifacts as mandatory and elsewhere treats them as optional. `contracts/` is explicitly intended to be optional and generic (`README.md:298-313`).
- Predecessor parallelism guidance was primarily “different files means parallel,” which does not account for dependencies, shared manifests, generated state, exclusive commands, or other shared resources (`prompts/sdd-tasks.md:119-120`; `prompts/sdd-implement.md:79-89`).
- Predecessor task-shape routing used generic path-name heuristics. These overlap and do not encode React, Node, Java, and .NET conventions (`prompts/sdd-implement.md:48-59`).

These are observations about the basis material, not requests to patch it. The new engine replaces ambiguity with explicit contracts.

### 2.3 Normative resolutions for the new engine

The new engine adopts the following unambiguous rules:

| Concern | New-engine rule |
| --- | --- |
| Feature identity | The normalized supplied feature directory identifies the feature. `featureId` is only its lossless `paths.specs`-relative directory key; no generated slug or ownership registry exists. |
| Feature directory | `--feature <feature-directory>` is relative to `.sddtoolkit.json`'s `paths.specs`. Resolve `<paths.specs>/<feature-directory>` and exclude `paths.specsArchive`; never hard-code or repeat the configured root. |
| Feature selection | Each selected SDD workflow receives the explicit feature directory through its registered invocation/run context. The same directory selects the same feature; no auto-selection or owner lookup. |
| Workflow registry | `paths.workflows` may contain any bounded number of closed declarative definitions and their explicitly declared bounded resources. Every definition, resource binding, and identifier validates; the requested workflow must resolve exactly once. |
| Workflow selection | The CLI/API adapter captures an explicit workflow selector; generic selection actions validate it as `WorkflowId`. `sdde <workflowId> ...` resolves that ID with no default or filename inference, then the compiled workflow's YAML-named invocation operation produces its validated run context. |
| SDD sequence | `specify -> plan -> tasks -> implement` is enforced by those workflows' predecessor gates, not by a fixed engine-wide role list. |
| Reference use | The required reference selector and resulting reference-state identity are carried in workflow metadata and run context. They are never inferred from business prose. |
| Specify launch | `sdde <workflow-id> --feature <feature-directory> --reference <relative-selector>` supplies target and source independently. The equivalent API carries both values; neither is inferred. |
| Reference requirement | Every new specification has one non-empty relative selector beneath `paths.references`. Missing or invalid reference input blocks before feature activation, logging, model calls, or artifact writes; there is no reference-free mode. |
| Reference precedence | All successfully decoded reference artifacts are peers and authoritative within the feature-intent domain. `README.md` may organize them but has no special precedence. Conflicts become blocking open questions. |
| Workflow artifact paths | The engine assigns them. The model never chooses `spec.md`, `plan.md`, `tasks.md`, or other canonical artifact locations. |
| Artifact editability | `spec.md` is the only user-editable stage output. `clarify/SNN.md`, `PNN.md`, and `TNN.md` are controlled input forms whose status/answer regions are user-editable; they are not plan/task authority. `reference-context.md`, all plan/design artifacts, and `tasks.md` remain read-only projections. |
| User validation | Plan/design views require explicit user approval before task generation. The tasks view requires explicit user approval before implementation. Rejection supplies feedback through the engine; users do not edit generated views. |
| Planning artifacts | `plan.md`, `research.md`, and `quickstart.md` are required. `data-model.md` and `contracts/` use explicit `required` or `not_applicable` decisions in the plan IR; absence alone is never interpreted. |
| TDD/verification order | A verification task precedes dependent implementation only when the resolved preset, repository, and plan support it. Otherwise the plan must name an executable manual verification. |
| Completion states | `completed`, `failed`, `blocked`, and `cancelled` are distinct. A failure report is never routed to a successful terminal state. |
| Paths | Paths are canonical absolute values inside the engine and repository-relative POSIX-style values in model contracts and persistent artifacts. Foreign absolute paths are rejected. |
| Platform | The engine uses platform-neutral ports. Presets define executable/argument arrays; prompts never hard-code Bash or PowerShell scripts. |
| Fingerprinting | No cross-stage content fingerprints are created or compared. Ordered stage gates reload and revalidate predecessor artifacts. |
| Required authority | Every contract-required datum and decision is reconciled through one shared closed authority-reconciliation contract. Zero or multiple non-equivalent resolutions create a clarification at the earliest owning stage; a downstream discovery returns through explicit rework rather than accepting a local substitute. |
