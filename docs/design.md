# Deterministic SDD Engine

## Architecture and detailed design for `specify -> plan -> tasks -> implement`

**Status:** Proposed design  
**Scope:** A new engine. The current repository is source material for workflow behavior; it is not the implementation target.  
**Primary inputs:** `prompts/sdd-specify.md`, `prompts/sdd-plan.md`, `prompts/sdd-tasks.md`, `prompts/sdd-implement.md`, their templates and flow documentation, `new_engine/_structure.yaml`, and `new_engine/.sddtoolkit.json.example`.  
**Out of scope:** Editing the current prompts/scripts, `init`, `drift`, `audit`, version-control workflow integration, and artifact fingerprinting.

---

## 1. Executive summary

The new engine must treat an LLM as an untrusted semantic content generator, not as the workflow runtime. The LLM must not choose the workflow sequence, perform filesystem operations, run arbitrary tools, declare its own output valid, or mark work complete. It receives a small typed assignment, preset-derived guidance, the relevant evidence, and an exact response schema. It returns a candidate. The engine parses, validates, repairs, renders, persists, and verifies that candidate.

The design has five defining properties:

1. **Ordered workflow:** one feature flows through `specify`, `plan`, `tasks`, and `implement` in that order. Every stage revalidates the previous stage before it starts.
2. **Deterministic shell around probabilistic work:** argument parsing, feature identity, paths, filenames, artifact structure, identifiers, traceability, dependency graphs, writes, commands, task state, and stage gates are engine-owned.
3. **Preset-controlled project operations:** every model-proposed project path is classified and checked against the selected development-environment preset, such as React, Node, Java, or .NET, before it can be recorded in a plan, emitted as a task, or written during implementation.
4. **Atomic repair:** a failed candidate is repaired at the smallest independently replaceable field, record, section, task, path, or code operation. Unrelated valid output is retained. The repaired candidate is never committed until all applicable validators pass.
5. **Actions and orchestrators:** actions have one responsibility and a common typed interface. They do not coordinate other components. Orchestrators contain actions and/or other orchestrators, but perform no filesystem, LLM, parsing, validation, rendering, or command work themselves.

The resulting boundary is:

- **The engine owns:** control flow, policy, facts, schemas, identifiers, paths, artifact locations, rendering, side effects, validation, retry limits, diagnostics, and completion.
- **The LLM owns:** understanding arbitrary reference material, extracting intent, writing business-facing requirements, making justified design choices, decomposing work, and generating or repairing code.
- **Executable evidence owns:** syntax, build, lint, test, and other preset-defined checks. An LLM assertion never substitutes for executable evidence.

---

## 2. Existing workflow used as the design basis

### 2.1 Behavior to preserve

The repository defines a specification-first workflow in which requirements lead to design, design leads to an executable task list, and tasks lead to implementation (`README.md:3-9`; `docs/workflow-overview.md:86-90`). The new engine preserves these behavioral concepts:

- `specify` accepts a natural-language feature request and optional reference material.
- Every validated reference artifact is an authoritative input; `README.md`, when present, is an organizer and does not outrank sibling files (`prompts/sdd-specify.md:153-167`; `docs/reference-folder-example.md:58-63`).
- `spec.md` remains business-facing. Supplementary design, visual-system, technical, and verification detail is carried in `reference-context.md` (`prompts/sdd-specify.md:178-238`).
- `plan` uses the specification, optional reference context, the current repository, and project standards to produce research and design artifacts (`prompts/sdd-plan.md:33-113`).
- `tasks` turns the plan and its artifacts into a dependency-ordered, traceable, executable task graph (`prompts/sdd-tasks.md:92-149`).
- `implement` executes that graph, applies relevant project standards, verifies work, and marks a task complete only after it succeeds (`prompts/sdd-implement.md:71-137`).
- Technology-agnostic workflow guidance becomes technology-specific only after the engine resolves the actual project environment (`README.md:315-328`).

### 2.2 Why a new engine is needed

The current material often describes deterministic operations, but expresses them as instructions for an LLM. A model is currently expected to parse arguments, run scripts, interpret output, choose paths, inspect files, decide whether gates passed, write artifacts, run implementation work, and update task state. Those steps can be skipped, misunderstood, or inconsistently applied—especially by a lower-capability model.

The current source material also contains useful examples of ambiguity that a deterministic engine must eliminate rather than ask a model to reconcile:

- Runtime prompts require a feature argument, while helper scripts and several flow documents support auto-selection (`prompts/sdd-plan.md:12-29`; `.specify/scripts/bash/setup-plan.sh:13-35`; `docs/flow-plan.md:5-17`).
- Feature names and feature-directory names are not governed by one explicit, versioned naming policy.
- The prompt checks for `NEED CLARIFICATION`, while templates use `NEEDS CLARIFICATION` (`prompts/sdd-plan.md:55-68`; `.specify/templates/spec-template.md:22,65`). A string typo can therefore bypass a gate.
- Planning and task prompts try to infer whether a specification used references, while `spec.md` is explicitly forbidden from containing reference metadata (`prompts/sdd-specify.md:186,235-238`).
- The specify flow creates a feature directory before it checks whether the requested reference folder exists (`prompts/sdd-specify.md:109-157`). A failed precondition can therefore leave partial output.
- The prompt advertises a maximum generated-name length that the current Bash and PowerShell scripts do not enforce (`prompts/sdd-specify.md:107-119`; `.specify/scripts/bash/create-new-feature.sh:29`; `.specify/scripts/powershell/create-new-feature.ps1:42`).
- Documentation treats some planning artifacts as mandatory and elsewhere treats them as optional. `contracts/` is explicitly intended to be optional and generic (`README.md:298-313`).
- Current parallelism guidance is primarily “different files means parallel,” which does not account for dependencies, shared manifests, generated state, exclusive commands, or other shared resources (`prompts/sdd-tasks.md:119-120`; `prompts/sdd-implement.md:79-89`).
- Current task-shape routing uses generic path-name heuristics. These overlap and do not encode React, Node, Java, and .NET conventions (`prompts/sdd-implement.md:48-59`).

These are observations about the basis material, not requests to patch it. The new engine replaces ambiguity with explicit contracts.

### 2.3 Normative resolutions for the new engine

The new engine adopts the following unambiguous rules:

| Concern | New-engine rule |
|---|---|
| Feature identity | `featureId` is a flat, deterministic, kebab-case identifier. It never contains `/`. |
| Feature directory | `featureDir = <paths.specs>/<featureId>`. The configured `paths.specs` value is the only source of truth. |
| Feature selection | The root workflow passes `featureId` through typed run context. A standalone later-stage invocation must provide `featureId`; directory auto-selection is not used. |
| Stage sequence | `specify -> plan -> tasks -> implement` is enforced by the root orchestrator and by stage precondition validators. |
| Reference use | Whether references were requested is carried in workflow metadata and run context. It is never inferred from business prose. |
| Reference precedence | All successfully decoded reference artifacts are peers and authoritative within the feature-intent domain. `README.md` may organize them but has no special precedence. Conflicts become blocking open questions. |
| Workflow artifact paths | The engine assigns them. The model never chooses `spec.md`, `plan.md`, `tasks.md`, or other canonical artifact locations. |
| Artifact editability | `spec.md` is the only user-editable workflow artifact. `reference-context.md`, all plan/design artifacts, and `tasks.md` are read-only rendered views of engine-owned typed state. |
| User validation | Plan/design views require explicit user approval before task generation. The tasks view requires explicit user approval before implementation. Rejection supplies feedback through the engine; users do not edit generated views. |
| Planning artifacts | `plan.md`, `research.md`, and `quickstart.md` are required. `data-model.md` and `contracts/` use explicit `required` or `not_applicable` decisions in the plan IR; absence alone is never interpreted. |
| TDD/verification order | A verification task precedes dependent implementation only when the resolved preset, repository, and plan support it. Otherwise the plan must name an executable manual verification. |
| Completion states | `completed`, `failed`, `blocked`, and `cancelled` are distinct. A failure report is never routed to a successful terminal state. |
| Paths | Paths are canonical absolute values inside the engine and repository-relative POSIX-style values in model contracts and persistent artifacts. Foreign absolute paths are rejected. |
| Platform | The engine uses platform-neutral ports. Presets define executable/argument arrays; prompts never hard-code Bash or PowerShell scripts. |
| Fingerprinting | No cross-stage content fingerprints are created or compared. Ordered stage gates reload and revalidate predecessor artifacts. |

---

## 3. Goals, non-goals, and invariants

### 3.1 Goals

- Make every mechanically decidable part of the four-stage workflow host-enforced.
- Give nano-class models concrete, bounded assignments instead of large agentic prompts.
- Validate every model-proposed filename and path against a project/environment preset.
- Repair invalid model output without regenerating valid unrelated work.
- Preserve traceability from source material through requirements, planning, tasks, code changes, and verification evidence.
- Make every action independently testable with fake ports and immutable inputs.
- Keep workflow orchestration composable without allowing domain work to leak into orchestrators.
- Support one or more development environments in a repository, including monorepos.
- Make failure explicit, stable, diagnosable, and safe to retry.
- Keep the specification editable while making plan/task outputs review-only projections with explicit approval gates.

### 3.2 Non-goals

- Making LLM output mathematically deterministic.
- Replacing semantic judgment with brittle keyword rules.
- Guaranteeing support for every possible binary reference format without an installed reader.
- Automatically resolving contradictory authoritative requirements.
- Integrating with version-control branching or lifecycle workflows.
- Extending `audit`, `drift`, or `init` in the first implementation.
- Detecting out-of-band predecessor changes with hashes or fingerprints.
- Allowing a model to execute an open-ended shell or use unrestricted agent tools.

### 3.3 Non-negotiable invariants

1. An LLM response is always a candidate, never committed truth.
2. No model-returned path is read, recorded as actionable, or written before path validation.
3. A fixed workflow-artifact path is calculated by the engine, not proposed by the model.
4. A project path must map to exactly one configured environment and project, and its explicitly declared file kind must permit that path and operation.
5. A stage cannot commit any output until all of its blocking deterministic validators pass.
6. A repair can modify only the repair unit selected by the engine.
7. A repaired candidate receives impacted validation followed by a full validation pass before commit.
8. An action performs one responsibility and never invokes an action or orchestrator.
9. An orchestrator coordinates child nodes and performs no domain or infrastructure operation itself.
10. Task completion is an engine transition backed by committed changes and required evidence; the model cannot request `[X]` directly.
11. Unsupported or unreadable reference files are never silently skipped.
12. Persistent artifact paths are repository-relative and normalized.
13. Model-supplied commands are never executed. Only named, preset/config-defined commands can run.
14. Identifiers, checkboxes, Markdown headings, and status text are rendered by the engine wherever possible.
15. The same normalized engine input and the same accepted structured model payload produce byte-stable rendered artifacts.
16. Only `spec.md` accepts user edits. A generated plan/task/reference view is never parsed as authoritative state.
17. Implementation cannot begin until the user has approved the current plan and current task graph.
18. Every actionable project-file reference in model output is a typed `fileId` or a planning-stage `ProjectPathCandidate`; path-shaped tokens in free-text fields are invalid.

---

## 4. Deterministic and LLM responsibility boundary

Deterministic checks should be used wherever the answer can be computed from configuration, schemas, files, parsers, graphs, or command exit status. Semantic classification remains with the LLM. The engine must not disguise model-assisted review as deterministic validation.

| Area | Engine-deterministic | LLM-owned | Limit or escalation |
|---|---|---|---|
| Command input | Parse flags, defaults, enums, duplicates, required arguments | None | Invalid user input is non-repairable by the model. |
| Feature identity | Slugging, configured length, and collision policy | Optional concise display title | Engine uses the original description, not an LLM summary, to calculate identity. |
| Reference discovery | Root containment, traversal, symlinks, inventory, ordering, readability, size, decoder availability | None | Unsupported inputs block or require an installed reader according to policy. |
| Reference understanding | Source span validity, exact token preservation for structured formats, coverage ledger | Extract requirements, classify signals, recognize semantic conflicts | The engine can prove a citation exists; it cannot prove every semantic implication was found. |
| Business/technical split | Obvious lint such as forbidden absolute paths, code fences, known source extensions, known framework identifiers | Decide whether nuanced content belongs in business spec or technical context | Borderline findings are model-assisted warnings or human review, not false “proof.” |
| Spec structure | Required fields, IDs, uniqueness, status, placeholders, citation schema, required sidecar | Stories, acceptance criteria, business rules, assumptions, non-goals | Testability and ambiguity are semantic reviews unless reducible to a schema rule. |
| Repository facts | File inventory, manifests, installed dependencies, scripts, source/test roots, AST parse, tool availability | Interpret which existing areas are relevant to the feature | A model may select among real facts but may not invent facts. |
| Plan structure | Artifact manifest, canonical paths, applicability, required sections, requirement coverage, allowed commands | Architecture, trade-offs, research rationale, minimal change choice, verification strategy | Constitution conflicts requiring judgment remain LLM/human decisions. |
| Planned filenames | Containment, environment, kind, root, extension, filename pattern, include/exclude, test placement | Propose a meaningful valid name | Invalid names receive preset-specific atomic repair guidance. |
| Task graph | IDs, phase enum, references, coverage, DAG, dependency existence, write-set collisions, safe `[P]` calculation | Decompose work, descriptions, non-obvious dependencies, read/write intent | Engine may remove unsafe parallelism; it never invents missing semantic dependencies silently. |
| Code changes | Allowed operation/path, patch applicability, declared scope, syntax, AST rules, import resolution, build/lint/test results | Generate code and repair semantic/compile/test failures | Behavioral correctness is only deterministic where an executable assertion exists. |
| Completion | Evidence requirements, committed transaction, task status, stage status | Summarize completed work | Model claims have no effect on state. |

The operating rule is: **if a validator can answer from typed data or executable evidence, do not ask the LLM to answer it.**

---

## 5. Logical architecture

[View the logical architecture diagram](diagrams/01-logical-architecture.mmd).

### 5.1 Layers

1. **Interface adapters** parse CLI/API input and present final reports. They contain no workflow decisions.
2. **Application orchestration** contains the root and stage orchestrators. It owns ordering and branching on typed outcomes, but no domain work.
3. **Actions** perform one use-case operation each: read one resource, invoke one model request, validate one concern, render one artifact, write one transaction, or execute one configured command.
4. **Domain** contains immutable intermediate representations, identifiers, diagnostics, policies, and result types.
5. **Infrastructure adapters** implement filesystem, model-provider, parser, command-runner, clock, logging, and reader ports.
6. **Preset/config compiler** validates raw configuration and compiles it into normalized, executable policy. Downstream actions use only compiled policy.

### 5.2 Dependency direction

Application and domain code depend on interfaces, never provider implementations. The LLM SDK, OS filesystem, shell/process API, YAML parser, Markdown parser, AST parser, and logger are adapters behind ports. This permits action unit tests without network access, repository mutation, or a real compiler.

Orchestrators receive child `PipelineNode` instances from the composition root. They do not receive `FileSystem`, `ModelGateway`, `CommandRunner`, parser, or validator ports. This makes the rule “orchestrators organize; actions do” mechanically enforceable.

---

## 6. Common action and orchestrator contract

Every action **and** every orchestrator implements the same runtime interface. There is one envelope, one result vocabulary, and one dependency declaration mechanism across the engine. A concrete implementation may add generic compile-time facades, but it must preserve this common runtime ABI so nodes can be chained, reordered, replaced, or nested without bespoke adapters.

[View the Pipeline node interfaces sample](code.md#pipeline-node-interfaces).

`NodeRuntime` is deliberately capability-free:

[View the Capability-free node runtime sample](code.md#node-runtime).

It exposes no filesystem, model, parser, renderer, validator, state, clock, logger, command, node-runner, or service-locator capability. Narrow operational ports are constructor dependencies of actions only. The outer pipeline runner records timing and telemetry around `execute`; nodes do not receive a telemetry adapter.

The common contract makes data dependencies explicit:

[View the Node contract and typed data keys sample](code.md#node-contract-and-data-keys).

An action declares its contract directly. An orchestrator's externally visible `requires`, `produces`, `replaces`, `invalidates`, side-effect summary, and barriers are derived and checked from its child graph by the pipeline compiler; an orchestrator cannot hide a child's capability or claim a narrower effect. Its internal child-only keys are not exposed outside the composition boundary.

Examples of keys are `engine.config@1`, `environment.compiled.web@1`, `reference.manifest@1`, `spec.ir@1`, `plan.ir@1`, `tasks.graph@1`, and `implementation.overlay.T007@1`. Keys are constants supplied by domain modules, never ad hoc strings inside actions.

`PipelineEnvelope` is immutable and identical for all nodes:

[View the Pipeline envelope sample](code.md#pipeline-envelope).

The registry is not an untyped property bag. Every value is retrieved through a versioned `DataKey<T>` and schema-checked on insertion. A node may read only keys declared by `requires`/`optional`, write only keys declared by `produces`/`replaces`, and invalidate only declared keys. Large bodies use engine-controlled content handles; arbitrary model paths are never registry keys.

`Outcome` is the same closed union for actions and orchestrators:

[View the Pipeline outcome sample](code.md#pipeline-outcome).

An `Invalid` result is not an exception. It is the normal input to an atomic repair orchestrator. `Blocked` and `Failed` are never sent to an LLM repair loop unless the diagnostic explicitly declares that model repair is valid.

The pipeline runner validates node contracts before execution, applies immutable deltas after a successful node, and refuses a chain with missing inputs, undeclared writes, incompatible schema versions, duplicate producers, or invalid side-effect ordering. An orchestrator schedules nodes; the runner performs contract/data plumbing.

### 6.1 Action rules

Every action must:

- have one verb-object responsibility;
- be deterministic when its port is deterministic;
- declare `requires`, `produces`, `replaces`, `invalidates`, and side-effect class through `NodeContract`;
- accept all variable behavior through typed input or injected narrow ports;
- return stable diagnostic codes rather than formatted-only error strings;
- support cancellation and configured timeouts;
- never select its successor;
- never call another action or orchestrator;
- never turn an invalid result into success;
- be independently testable.

An action that reads a file does not also parse it. An action that invokes a model does not parse or validate the response. An action that validates a path does not write that path. An action that commits a transaction does not decide whether validation passed; it requires a validated transaction token as input.

### 6.2 Orchestrator rules

Every orchestrator must:

- express a static or data-driven sequence of child nodes;
- branch only on typed `Outcome` and diagnostic metadata;
- pass immutable envelopes between children;
- impose iteration and repair limits from compiled config;
- never open files, call models, parse responses, render content, validate rules, execute commands, or mutate task state directly;
- be testable with spy/fake child nodes;
- allow child orchestrators, while preventing cycles in the orchestration graph.

Architecture tests fail the build if an action field or constructor parameter is a `PipelineNode`, `Action`, `Orchestrator`, dispatcher, executor callback, node runner, or service locator; if an action imports an orchestrator namespace; if any node calls another node's `execute` outside an orchestrator module; or if an orchestrator imports anything outside an allowlist of contracts, outcomes, envelopes, loop controls, and child-node bindings. Orchestrator modules cannot import infrastructure or domain-operation adapters.

### 6.3 Reordering and composition rules

Actions and orchestrators can be reorganized without changing their implementation when their contracts remain satisfiable:

1. Before building a pipeline, the composition validator calculates the keys available at each position.
2. A node is placeable when all `requires` keys exist at compatible schema versions.
3. `produces` adds a new key; `replaces` requires and atomically replaces an existing key; `invalidates` removes stale downstream keys.
4. Two pure/read nodes with satisfied inputs may be reordered or run concurrently when neither invalidates/replaces a key used by the other.
5. Model calls, candidate writes, commands, and commits create declared barriers. A commit cannot move before its validation-authorization key exists.
6. A node cannot depend on execution order that is not represented by a required data/evidence key or an ordering barrier.
7. The pipeline compiler rejects cycles and prints a dependency explanation before runtime.

This enables, for example, swapping one filename validator implementation, moving source parsing earlier, inserting a semantic-review orchestrator, or nesting the same validated-generation orchestrator in a new stage without changing adjacent nodes. Typed keys keep information passing simple while preserving testability and preventing hidden state.

---

## 7. Core domain representations

Markdown is a presentation format, not the internal source of truth while a stage is running. The engine uses typed intermediate representations (IRs) and renders Markdown only after validation.

### 7.1 Shared types

[View the Shared domain types sample](code.md#shared-domain-types).

`isOrganizer` does not reduce authority. It records that a file such as `README.md` helps describe the corpus; any requirements it contains remain peer authoritative with requirements in sibling files.

`sourceId`, `blockId`, and claim IDs are stable within a persisted feature-scoped `ReferenceSnapshot`, including across process restarts. They are derived from normalized source position and snapshot-local ordinal, not content hashes, and are not stale-artifact fingerprints. A changed reference corpus creates a new snapshot identity and invalidates provenance that names the prior snapshot.

`canonicalStateId` is an engine state identifier, not a content digest. The plan and task IRs are persisted as canonical engine state beneath `paths.sddtoolkit`; their Markdown files are review views only. The specification remains authoritative as editable Markdown and is reparsed into `SpecificationIR` at the plan boundary.

### 7.2 Stage IRs

#### Specification IR

The LLM supplies semantic fields, but the engine assigns identifiers and status:

[View the Specification IR sample](code.md#specification-ir).

The renderer deterministically adds `AC-001`, `EC-001`, `FR-001`, `BR-001`, dates, headings, checklist state, and execution state. The model cannot forge a “passed” checklist.

#### Reference-context IR

[View the Reference-context IR sample](code.md#reference-context-ir).

Every `PreservedToken` contains an exact source value and citation. Structured readers can create tokens directly from CSS declarations and JSON/YAML/XML leaves. The LLM classifies relevance but cannot rewrite the exact value. This creates a deterministic propagation ledger for values that the current workflow says must never be lost.

#### Plan IR

[View the Plan IR sample](code.md#plan-ir).

`ArtifactDecision` is explicit:

[View the Artifact decision sample](code.md#artifact-decision).

#### Task IR

The model does not assign task IDs, checkbox syntax, or `[P]` markers:

[View the Task IR sample](code.md#task-ir).

After graph validation, the engine topologically assigns `T001...`, calculates safe parallel markers, and renders checkboxes. A task may be semantically atomic while changing multiple tightly coupled files, but every file, shared resource, command, manual scenario, and completion-evidence predicate must be declared.

#### Implementation IR

[View the Implementation IR sample](code.md#implementation-ir).

`CreateFile` requires an absent destination. `ReplaceFile` requires a present regular-file destination and replaces its complete contents. `CopyFile` performs a byte-exact copy from an engine-resolved `CopySource`; it never accepts a raw source path, and source/destination cannot be the same file. If copied code needs adaptation, the copy completes first in the operation savepoint and a separately authorized `UpdateFile` or `ReplaceFile` operation performs the adaptation. Deletion is disabled by default and requires both task authorization and engine policy. The model never returns a raw shell command.

---

## 8. Diagnostics and evidence

Every deterministic failure is represented consistently:

[View the Diagnostic contract sample](code.md#diagnostic-contract).

Representative codes include:

- `CFG_SCHEMA_INVALID`
- `PRESET_PLACEHOLDER_UNRESOLVED`
- `STAGE_PREDECESSOR_INVALID`
- `REF_PATH_ESCAPE`
- `REF_DECODER_UNAVAILABLE`
- `REF_CITATION_NOT_FOUND`
- `SPEC_UNRESOLVED_CLARIFICATION`
- `SPEC_TECHNICAL_LEAK`
- `ARTIFACT_PATH_INVALID`
- `PATH_ENVIRONMENT_AMBIGUOUS`
- `PATH_KIND_AMBIGUOUS`
- `PATH_ROOT_FORBIDDEN`
- `PATH_EXTENSION_INVALID`
- `PATH_FILENAME_PATTERN_INVALID`
- `TEST_PLACEMENT_INVALID`
- `PLAN_REQUIREMENT_UNCOVERED`
- `TASK_ID_REFERENCE_UNKNOWN`
- `TASK_DEPENDENCY_CYCLE`
- `TASK_PARALLEL_WRITE_CONFLICT`
- `PATCH_OUTSIDE_TASK_SCOPE`
- `PATCH_APPLY_FAILED`
- `SOURCE_SYNTAX_INVALID`
- `IMPORT_TARGET_MISSING`
- `COMMAND_FAILED`
- `TASK_EVIDENCE_INCOMPLETE`
- `REPAIR_SCOPE_VIOLATION`
- `REPAIR_ATTEMPTS_EXHAUSTED`

Diagnostics are sorted deterministically by stage, artifact, location, validator priority, and code. Human-facing messages are rendered from codes and fields; repair logic does not parse prose.

Evidence is separate from diagnostics. It records facts such as a decoded source location, a successfully parsed AST, a passing command, or a committed transaction. A checklist or task status is derived from evidence and cannot be set by the LLM.

---

## 9. Engine configuration

`new_engine/.sddtoolkit.json.example` is a useful starting point for logs, model routing, and paths, but it is not yet sufficient to control a deterministic engine. It has no schema URI, environment preset selection, repair policy, reference-reader policy, validation policy, workflow gates, state policy, or command-safety policy. Its model slots also omit explicit plan, tasks, reference-analysis, and repair routes (`new_engine/.sddtoolkit.json.example:15-22`).

### 9.1 Required configuration shape

The following is illustrative; the implementation must publish a formal JSON Schema and use `additionalProperties: false` at all policy-bearing levels.

[View the Engine configuration sample](code.md#engine-configuration).

The example uses `references/` because that is the new sample configuration. The engine must never hard-code the current repository's `.specify/reference/`; whichever path the validated configuration selects is authoritative.

### 9.2 Configuration validation

Bootstrap must reject configuration before any LLM call when:

- `schemaVersion` is unsupported;
- an unknown key appears in a closed schema;
- a path is absolute, escapes the workspace, overlaps a forbidden root, or conflicts with another engine path; the one declared nesting exception is `paths.specsArchive` beneath `paths.specs`, and the archive subtree is excluded from active feature discovery;
- two environments have the same root or ambiguous equal-specificity roots;
- a named preset, model profile, route, reader, validator, parser, or command adapter is missing;
- a model route required by an enabled stage is absent; a route is either a profile-ID shorthand with no fallback or a closed object `{ primary, fallback?, fallbackAfter }`, and every named profile must exist;
- a numeric limit is negative, zero where prohibited, or above an engine safety maximum;
- response logging is enabled without a redaction/retention policy;
- `useFingerprints` is set to true in this design version;
- a hardened workflow disables required plan or task approval without an explicitly selected non-interactive policy profile;
- a project overlay attempts to disable a locked safety validator.

### 9.3 Precedence

Configuration and content authority are separate systems.

Configuration is resolved in this order, from least to most specific:

1. engine defaults;
2. base language preset;
3. runtime preset;
4. framework preset;
5. build/test-tool preset;
6. project overlay;
7. explicitly permitted CLI overrides.

Non-overridable engine safety invariants sit outside the merge and always win. Repository discovery supplies evidence; it is not a precedence layer. An `auto` field may be filled from unambiguous evidence, but discovered facts cannot silently overwrite explicit configuration.

Merge semantics must be declared per field:

- maps merge by stable key;
- commands replace atomically by command ID;
- extension sets may union;
- forbidden paths and locked validators only union and cannot be weakened;
- roots and naming rules replace by default;
- arrays never concatenate implicitly;
- an explicit merge directive is required for append, prepend, union, or remove;
- removing a locked rule is invalid.

Content authority is domain-specific:

- engine safety and mechanical environment facts cannot be overridden by references;
- explicit feature input and successfully decoded reference artifacts define feature intent;
- authoritative reference conflicts block or create open questions—there is no last-file-wins behavior;
- the specification is the business-intent source for later stages;
- reference context carries supplementary implementation-facing obligations;
- constitution/project standards govern technical choices within the real environment;
- generic prompt examples have the lowest authority.

### 9.4 Project-standards resolution

The current workflow loads project constitution modules; the new engine preserves that input through typed ingestion rather than inserting raw files into every prompt (`prompts/sdd-plan.md:70-85`; `prompts/sdd-implement.md:48-69`). Version-control workflow material is outside this engine's scope and is not loaded, interpreted, or enforced.

Resolution is explicit:

1. read configured project-specific constitution roots;
2. if a required source is missing, use shipped defaults only when `standards.fallback.mode` explicitly enables them;
3. record every fallback as evidence so the model/user can distinguish project rules from defaults;
4. parse Markdown/data standards into typed modules and indexed sections;
5. compile only formally declared typed rules—file patterns, coverage thresholds, command requirements, and forbidden dependencies—into deterministic validators or a project preset overlay;
6. retain arbitrary Markdown prose as semantic sections with source locations; prose is never compiled into mechanical rules by inference;
7. validate compiled standards against engine safety, environment presets, and repository facts;
8. block on contradictions rather than selecting one silently.

Precedence within the standards domain is project-specific module over explicitly configured shipped fallback. Engine safety remains non-overridable. Physical repository/preset facts cannot be contradicted by prose; a conflict is a configuration/standards diagnostic. Generic workflow examples never override project standards.

Applicable standards are selected deterministically from stage, task kind, file kind, and configured mappings. The model does not infer which constitution files to load from a filename. It receives the selected indexed semantic sections plus compiled rules already expressed as concrete guidance.

### 9.5 Legacy configuration migration

The supplied `.sddtoolkit.json.example` is input to a one-time, deterministic migration adapter, not accepted directly as v1 engine policy. The adapter applies a published mapping and emits the complete v1 document for user review:

| Legacy field | v1 destination or treatment |
|---|---|
| `version` | `schemaVersion`, only when the legacy value is in the supported migration table |
| legacy model slots | explicit `models.profiles` plus route entries; no route is guessed when more than one mapping is possible |
| `timestamp` | discarded as sample metadata; runtime timestamps are evidence, not configuration |
| `logFile` | `logs.output` plus an explicit contained file target when file logging is selected |
| existing path fields | normalized into `paths`; conflicts and the archive exception are validated normally |

Unknown legacy keys or ambiguous model mappings block migration. The migrated file must pass the closed v1 schema; runtime code contains no ongoing legacy-field fallback.

---

## 10. Development-environment presets

`new_engine/_structure.yaml` inventories package, build, test, path, quality, and AST concerns. It should be treated as a seed, not as the final contract. Its “mandatory” rules exist only in comments and unresolved `<!-- IMPLEMENT -->` values are valid YAML strings (`new_engine/_structure.yaml:1-101`). A formal schema must reject unresolved placeholders and missing mandatory values.

React, Node, Java, and .NET should not be four flat, monolithic alternatives. React is a framework, Node is a runtime, Java is a language/ecosystem, and .NET is a runtime/toolchain. Presets must therefore be composable.

### 10.1 Preset identity and composition

[View the Preset identity and composition sample](code.md#preset-identity-and-composition).

Every preset and overlay is validated with a JSON Schema (YAML 1.2 parsing for YAML form), closed objects, explicit required fields, enums, anchored patterns, and semantic-version validation. Production configuration pins an exact preset version; ranges and implicit `latest` are invalid. `metadata.layer` is one of `language`, `runtime`, `framework`, `build`, `test`, `environment`, or `project_overlay`. The composition graph must be acyclic; a preset identity may occur only once in its transitive closure, and conflicting versions of one ID are an error. Layer-order constraints and every field's merge operator are schema-defined, so list position cannot silently change policy meaning.

### 10.2 Project discovery

A preset must support multiple manifests and project roots rather than the sample's single `package.configFiles.manifest` field. Manifest semantics vary too much for generic keys such as `sourceDirectoriesKey`, `structureType`, and `directoryTransformer` (`new_engine/_structure.yaml:6-14`). Use registered, non-executable adapters:

- `npm-package-json`
- `npm-workspaces`
- `maven-pom`
- `gradle-project`
- `msbuild-project`
- `dotnet-solution`

[View the Project discovery policy sample](code.md#project-discovery-policy).

Each discovered project receives a `projectId`, canonical root, manifest adapter, language set, and compiled file-kind policies. A proposed path must name a `projectId`, or the nearest owning project must be uniquely derivable. Equal matches are a blocking `PRESET_SELECTION_AMBIGUOUS` diagnostic, not an LLM choice.

For a monorepo, environment resolution uses the longest matching configured root. An equal-length match is invalid configuration. A cross-environment task declares separate paths/operations for each environment.

### 10.3 File-kind policies

The sample has general source patterns and physical policies only for config and style (`new_engine/_structure.yaml:26-38,81-91`). Filename validation needs an extensible role-aware map:

[View the File-kind policies sample](code.md#file-kind-policies).

At minimum, the schema must support these kinds where relevant:

- source module;
- component/view/screen;
- hook/helper;
- state/schema/type;
- unit, integration, and end-to-end test;
- style;
- asset/resource;
- config;
- project/solution manifest;
- contract/interface artifact;
- migration;
- documentation;
- generated output.

Every pattern declares:

- `patternType`: `glob`, `regex`, or exact;
- `target`: basename, project-relative path, or source-root-relative path;
- case sensitivity;
- whether matching is full or partial (full is the default);
- create/update applicability.

Strict naming rules apply primarily to `create`. An `update` of a legacy existing filename normally requires containment, existence, compatible kind, and allowed extension without forcing an unrelated rename. A project overlay may opt into migration enforcement.

### 10.4 Structured commands

Raw command strings in `_structure.yaml` are shell-dependent and unsafe to template (`new_engine/_structure.yaml:15-25,40-77,93-95`). Commands must be structured, capability-based values:

[View the Structured commands sample](code.md#structured-commands).

Rules:

- commands execute without a shell;
- every placeholder is declared, typed, and provided by the engine;
- values are individual argv elements and are never string-interpolated into a shell command;
- working directory must be within the owning project;
- executable resolution follows an engine allowlist;
- time, output, environment, filesystem, and network limits are explicit;
- mutability is declared as `readOnly`, `workspaceWrite`, or `dependencyMutation`;
- every mutating command declares `effects.authorizedWrites` and disposable `effects.ephemeralWrites`; both are compiled path policies, not free-form model values;
- package-add commands distinguish package name, version, project, and dependency scope;
- validation commands cannot alias an install/add operation;
- the engine verifies that an npm script, Maven goal, Gradle task, or .NET target is available before exposing the command ID to the LLM;
- an unsupported capability is disabled with a reason rather than populated with a fake command.

The LLM may select from allowed command IDs supplied in context. It never returns executable text.

### 10.5 AST and parser policy

The sample's extension-to-string AST maps do not identify parser versions, query captures, resolution rules, or missing-resource behavior (`new_engine/_structure.yaml:97-101`). Use explicit parser descriptors:

[View the AST and parser policy sample](code.md#ast-and-parser-policy).

Preset loading verifies parser availability, grammar compatibility, query-resource containment, query compilation, and required captures. If a parser or required query is unavailable, the preset fails at bootstrap; the LLM is not asked to compensate.

### 10.6 Generated and forbidden paths

Every compiled preset includes immutable deny rules for dependency caches, build output, source-control internals, engine internals, and any declared generated source:

[View the Generated and forbidden paths sample](code.md#generated-and-forbidden-paths).

A generated path can be a read-only input but not a model write target unless a specific task, generator adapter, and policy authorize regeneration. Hand-editing compiled output is rejected.

### 10.7 Environment-specific expectations

#### React

- Compose JavaScript or TypeScript, Node, React, and the actual build/test overlay.
- Represent components, hooks, state, styles, assets, and tests as distinct file kinds.
- Typical PascalCase `.tsx`, `useXxx.ts[x]`, and colocated `*.test.tsx` conventions are defaults only when the selected project preset declares them; React itself does not mandate them.
- Validate JSX/TSX syntax, aliases, import resolution, package declarations, and configured test placement.
- Exclude build/cache paths such as `dist`, `.next`, and coverage output according to the selected tool overlay.

#### Node

- Compose JavaScript or TypeScript with ESM or CommonJS and the selected package manager/test runner.
- Detect `package.json`, its `type`, TypeScript configuration, scripts, and lockfiles.
- Do not require compilation for runtime JavaScript.
- Permit `.js`, `.mjs`, `.cjs`, or `.ts` only when the resolved variant allows them.
- Multiple unresolved lockfiles are a configuration ambiguity, not a model decision.

#### Java

- Compose Java/JVM with Maven or Gradle.
- Discover modules from `pom.xml`, `settings.gradle*`, and `build.gradle*`.
- Model `src/main/java`, `src/test/java`, and resource roots per module.
- Deterministically require a public top-level type to match its `.java` basename and its package declaration to match the source-root-relative directory when the preset enables those rules.
- Provide project-configurable `*Test.java`/`*Tests.java` policies.
- Treat `target/`, `build/`, and generated sources as non-writable by default.

#### .NET

- Compose C#/.NET with MSBuild/dotnet.
- Discover `.sln`, `.slnx`, `.csproj`, central package files, and project references.
- Associate every proposed source or test file with exactly one project.
- Provide typed `dotnet build`, `dotnet test`, and `dotnet add <project> package <package>` command definitions.
- Treat PascalCase and `*Tests.cs` as project policies, not universal language laws.
- Exclude `bin/` and `obj/`.
- Validate project ownership, references, and namespace/folder conventions when configured.

### 10.8 Normative matching and platform semantics

Preset compilation uses one portable matching contract:

- Persistent and policy paths are NFC-normalized, repository-relative POSIX paths with `/` separators. Matching is performed on Unicode scalar values after normalization.
- `exact` means full target equality. `regex` uses the RE2-compatible grammar, is implicitly anchored to the entire declared target, and must declare case sensitivity. Unsupported constructs fail preset compilation.
- `glob` uses `/` as the only separator: `*` matches zero or more non-`/` characters, `?` one non-`/` character, `[...]` one class character, and a complete segment `**` zero or more path segments. Brace expansion, extglobs, escaping by platform shell, and partial substring matching are not supported.
- Each path proposal explicitly declares a kind, and validators apply that kind's rules. Overlap with another kind is therefore not ambiguity. When the engine must infer a kind for an existing repository file, the highest unique `inferencePriority` wins; equal-priority matching kinds fail preset compilation for the relevant root/operation domain.
- File-kind policies explicitly declare read/create/update/delete applicability. Read-only repository context uses `read`; a write permission is never inferred from read permission.
- The environment declares target filesystems. The compiled cross-platform policy rejects Windows reserved device basenames, disallowed characters, trailing dots/spaces, and target-specific segment/path length violations when Windows is a target. It also checks normalization and case-fold collisions for every configured target, even when the engine host is more permissive.
- Maven and Gradle adapters evaluate effective module source/resource/test/generated-source sets through registered build-model adapters; directory-name heuristics alone are insufficient. MSBuild adapters evaluate SDK defaults plus explicit `Compile`, `Content`, `None`, `EmbeddedResource`, `Remove`, `Include`, and project-reference ownership rules. An unevaluable dynamic build model blocks path authorization or requires an explicit project overlay.

Plan-time validation is lexical and repository-structural. Content-dependent rules such as Java public-type/basename, Java package/directory, or configured namespace/declaration checks run only when source bytes or an explicit typed declaration proposal is available, and are mandatory again against the parsed generated source during implementation. The engine never claims to prove a content-dependent rule from a filename alone.

---

## 11. Filename and path validation algorithm

Workflow artifacts and project files use two separate policy domains:

- **Workflow artifact policy** owns canonical files beneath `paths.specs`: `spec.md`, `reference-context.md`, `plan.md`, `research.md`, `data-model.md`, `quickstart.md`, optional feature-local contracts, and `tasks.md`.
- **Environment preset policy** owns proposed repository implementation files: source, tests, configuration, styles, assets, project manifests, migrations, documentation, and related files.

This distinction prevents a language preset from incorrectly rejecting `spec.md` because Markdown is not a source extension.

For every model-returned path-like field, the engine executes these checks in order:

1. Validate response field type and UTF-8; reject NUL/control characters.
2. Normalize separators to `/` and remove `.` segments. This is canonicalization, not repair.
3. Reject empty paths, absolute paths, drive prefixes, UNC paths, URI schemes, and `..` segments.
4. Join to the canonical workspace root without following model-controlled indirection.
5. Resolve existing ancestors and symlinks; reject any real path that escapes the workspace or owning environment.
6. Reject engine-internal, VCS, dependency-cache, generated, and build-output targets unless an explicit policy exception applies.
7. Resolve `projectId` and environment. Reject no match or multiple matches.
8. Validate the explicitly declared `kind`; do not infer a different kind to make a proposal pass.
9. Check whether `read`, `create`, `update`, or `delete` is allowed for that kind and stage.
10. Check allowed roots using segment-aware matching, never string-prefix containment.
11. Match exact/regex/glob basename rules using declared case sensitivity.
12. Match allowed compound extensions using longest-suffix semantics, so `.test.tsx` is not reduced to `.tsx`.
13. Apply include and exclude rules to the declared target domain.
14. Apply placement/mapping rules, such as colocated tests or mirrored `src` to `test` structure.
15. Apply environment-specific content rules only when typed declaration facts or source bytes are present; otherwise record them as mandatory implementation-time validators.
16. Detect case-fold collisions on case-insensitive filesystems.
17. For `update`, require an existing regular file unless the operation explicitly supports upsert. For `create`, reject an existing target unless an explicit update was proposed.
18. Validate that plan and task authorization include the target.
19. Immediately before any commit, re-resolve every existing ancestor with descriptor-relative/no-follow operations or the platform-equivalent safe primitive, compare parent identities captured during preparation, and fail if an ancestor or target was swapped. Lexical validation performed earlier never authorizes a race-prone write.

An accepted `ProjectPathCandidate` becomes an engine-assigned `FileRecord`; its `fileId` is the only project-file identity downstream model routes may use. Raw model strings are discarded after normalization and diagnostic reporting. Closed schemas separate prose from file references, and a deterministic path-token lexer rejects path-shaped text in summaries, rationales, descriptions, or code comments returned in non-code fields unless it is an engine-rendered `[file:<fileId>]` reference. This prevents a filename hidden in prose from bypassing preset validation.

Plans and tasks refer to stable `fileId` values once a path is accepted. Filename repair occurs in planning, before the file record is approved. One canonical path record changes and renderers update all human-facing references; the model is not asked to repair repeated prose occurrences.

---

## 12. LLM interaction boundary

### 12.1 Discrete LLM components

LLM interaction is deliberately split across actions:

1. `SelectContextAction` chooses relevant typed facts and bounded source excerpts.
2. `BuildInitialGuidanceAction` converts compiled policy into a concise instruction packet.
3. `BuildModelRequestAction` constructs the provider-neutral request and response schema.
4. `InvokeModelAction` performs exactly one provider call and returns raw provider output plus usage metadata.
5. `DecodeModelEnvelopeAction` converts provider output into the typed model-response envelope.
6. Stage-specific validation actions validate the candidate.
7. `BuildAtomicRepairGuidanceAction` builds a single-diagnostic repair request when required.
8. `MergeAtomicRepairAction` merges only the authorized replacement into the in-memory candidate.

No one action both invokes and interprets the model. No model action reads or writes the workspace directly.

### 12.2 Initial guidance packet

Each generation request contains only what the current unit needs:

[View the Initial guidance packet sample](code.md#initial-guidance-packet).

Raw preset YAML is not sent. The engine sends the compiled subset relevant to the requested unit. Raw whole-repository listings, unrelated constitution sections, and earlier model prose are not sent. Stable identifiers replace repeated text wherever possible.

### 12.3 Provider-neutral response envelope

[View the Model response envelope sample](code.md#model-response-envelope).

The response schema is closed. The provider adapter should use native structured output when available, but the engine still performs its own schema validation. Provider claims of schema compliance are not trusted.

Allowed top-level result kinds are route-specific. A generation route cannot return a patch; a repair route cannot return a whole document; an implementation route cannot return task status.

### 12.4 Context requests

If the current unit cannot be completed with supplied facts, a route may support one typed context request:

[View the Model context request sample](code.md#model-context-request).

The model does not provide a raw path. The context request must reference an already validated ID or a strictly typed query. The orchestrator permits at most the configured number of context rounds. Unsupported requests become a diagnostic, not an agentic tool call.

### 12.5 Low-capability model operating rules

- one reference chunk, artifact section, requirement cluster, task cluster, or file operation per call;
- strict JSON schema with enums and `additionalProperties: false`;
- low temperature or provider equivalent, without relying on it for correctness;
- stable IDs for sources, requirements, tokens, projects, files, tasks, commands, and diagnostics;
- a short valid example matching the current exact schema;
- no request to reproduce engine-known filenames, IDs, headings, checkboxes, or status;
- no open-ended “inspect the repo” instruction;
- no unrestricted tool use;
- no full-document retry for a local validation failure;
- bounded output and repair attempts;
- optional configured fallback route only after deterministic retry exhaustion, never as silent behavior.

### 12.6 Semantic review

Some current gates—testability, ambiguity, minimality, unsupported behavior, and conflict detection—are semantic. If desired, the engine runs a separate `semantic.review` model action over one typed unit. Its findings are labeled `model_assisted`, retain source citations, and never masquerade as deterministic evidence. Configuration determines whether such findings warn, block for user review, or produce a model repair request.

---

## 13. Action catalogue

The names below define responsibility boundaries. Implementations may group them into packages, but must not merge responsibilities in a way that violates the action rules.

### 13.1 Bootstrap and configuration actions

| Action | Input | Output | Single responsibility |
|---|---|---|---|
| `LocateWorkspaceAction` | invocation working directory | canonical workspace descriptor | Find and contain the workspace root. |
| `ReadEngineConfigAction` | configured/default config path | raw config text | Read one engine config resource. |
| `ParseEngineConfigAction` | raw config text | raw config object | Parse JSON without applying policy. |
| `ValidateEngineConfigSchemaAction` | raw config object | schema-valid config | Apply only the closed config schema. |
| `ValidateEngineConfigSemanticsAction` | schema-valid config | semantic config evidence | Validate references, limits, and cross-field invariants. |
| `ValidateEnginePathPolicyAction` | one configured path relation | path-policy evidence | Validate one engine path/overlap relation. |
| `ReadPresetAction` | preset identifier | raw preset resource | Read one preset or overlay. |
| `ParsePresetAction` | raw preset resource | raw preset object | Parse YAML/JSON using fixed semantics. |
| `ValidatePresetSchemaAction` | raw preset object | schema-valid preset | Apply only the closed preset schema. |
| `RejectPresetPlaceholderAction` | one schema-valid preset | placeholder-free preset evidence | Reject unresolved placeholders. |
| `ValidatePresetResourceAction` | one declared preset resource | resource evidence | Validate one referenced parser/query/adapter resource. |
| `ValidatePresetCompositionAction` | preset dependency graph | composition evidence | Validate versions, layers, duplicates, and cycles. |
| `CompilePresetSetAction` | ordered validated presets | compiled environment policy | Apply explicit merge rules once. |
| `EnumerateManifestCandidatesAction` | workspace plus compiled discovery rules | manifest candidates | Enumerate possible manifests only. |
| `ParseProjectManifestAction` | one manifest and one registered adapter | project fragment | Parse one manifest only. |
| `AssembleProjectRegistryAction` | validated project fragments | repository project facts | Assemble non-conflicting ownership records. |
| `ValidateEnvironmentMatchAction` | config, compiled policy, project facts | resolved environments | Detect conflicts and ambiguities. |
| `ProbeCommandCapabilityAction` | one project and command descriptor | command capability evidence | Prove one named capability exists. |
| `AssembleCommandRegistryAction` | capability evidence set | available command registry | Assemble only proven capabilities. |
| `ResolveStandardsSourcesAction` | validated standards config | ordered standards source paths | Resolve project and explicit fallback sources. |
| `ReadStandardModuleAction` | one standards source path | raw standard resource | Read one standards resource. |
| `ParseStandardModuleAction` | one raw standard resource | parsed standard module | Parse one Markdown/data module. |
| `CompileTypedStandardRuleAction` | one formal policy block | deterministic rule/diagnostic | Compile one mechanically enforceable typed rule. |
| `IndexSemanticStandardsAction` | parsed standard modules | source-located semantic sections | Index prose principles without claiming deterministic meaning. |
| `CompareStandardRuleAction` | one typed standard rule and compiled policy | consistency evidence/diagnostic | Compare one rule with engine/preset/repository facts. |
| `SelectApplicableStandardsAction` | stage/task/file kinds and standards index | bounded standards selection | Select exact relevant rule sections. |
| `CreateRunMetadataAction` | invocation plus resolved environment | initial workflow metadata | Create feature-run state without artifact hashes. |

### 13.2 Invocation, feature, and stage-gate actions

| Action | Input | Output | Single responsibility |
|---|---|---|---|
| `ParseSpecifyInvocationAction` | CLI/API arguments | parsed feature arguments | Parse quoted text and named flags. |
| `ValidateSpecifyArgumentsAction` | parsed feature arguments | valid feature arguments | Apply required/default/enum rules. |
| `DeriveFeatureIdentityAction` | valid arguments plus naming policy | feature identity | Calculate `featureId`. |
| `ResolveWorkflowArtifactPathsAction` | feature identity and config paths | artifact registry | Calculate every canonical workflow path. |
| `ReadWorkflowStateAction` | feature ID | persisted stage metadata or none | Read state only. |
| `ValidateStageOrderAction` | requested stage and state | stage authorization | Enforce predecessor order. |
| `ValidateRequiredArtifactPresenceAction` | one required artifact identity | presence evidence | Check one required artifact exists. |
| `ValidateRequiredArtifactReadabilityAction` | one required artifact identity | readability evidence | Check one required artifact is readable. |
| `ValidateWorkflowMetadataAction` | one stage metadata invariant | metadata evidence | Validate one reference/state/artifact expectation. |
| `BuildNextStageStateAction` | validated stage result and current state | next-state payload | Build one state transition for inclusion in the stage transaction. |

### 13.3 Reference actions

| Action | Input | Output | Single responsibility |
|---|---|---|---|
| `ResolveReferenceRootAction` | reference request and config | contained reference root | Resolve and validate one requested root. |
| `EnumerateReferenceFilesAction` | contained root and reader policy | ordered file inventory | Enumerate without decoding. |
| `SniffReferenceMediaTypeAction` | one inventory entry | media-type result | Determine content type using registered sniffers. |
| `RankReferenceReadersAction` | one media type/probe result and registry | ordered reader candidates | Apply threshold, priority, and tie rules. |
| `SelectReferenceReaderAction` | ranked reader candidates | reader selection | Select the unique winning decoder or diagnose ambiguity. |
| `DecodeReferenceAction` | one entry and reader | decoded content blocks | Decode one file only. |
| `ExtractStructuredFactsAction` | decoded structured content | exact machine facts/tokens | Parse values mechanically where supported. |
| `ChunkReferenceAction` | one decoded reference | ordered bounded chunks | Partition while preserving source locations. |
| `RecordBlockDispositionAction` | one decoded block and extraction result | block-ledger entry | Account for one block as extracted, irrelevant, or blocked. |
| `ValidateSourceCitationAction` | one model citation and source corpus | citation evidence | Prove referenced location/text exists. |
| `ValidateReferenceEntryAccountingAction` | one inventory entry and block ledger | entry accounting evidence | Prove one file and all of its blocks have dispositions. |
| `AssembleReferenceSnapshotAction` | validated entries, claims, context, provenance | canonical reference snapshot | Assemble one persisted snapshot without hashing content. |
| `SerializeCanonicalReferenceStateAction` | validated reference snapshot | canonical reference-state bytes | Serialize one authoritative reference snapshot. |
| `RenderReferenceContextAction` | validated reference-context IR | Markdown candidate | Render the sidecar only. |

Semantic extraction and reconciliation use the common LLM actions; there is no special reader that also calls a model.

### 13.4 Model actions

| Action | Input | Output | Single responsibility |
|---|---|---|---|
| `SelectContextAction` | unit plus indexed facts | bounded context set | Select relevant known context. |
| `BuildInitialGuidanceAction` | unit, context, compiled policy | guidance packet | Generate deterministic initial guidance. |
| `BuildModelRequestAction` | guidance and route schema | provider-neutral request | Serialize one request. |
| `InvokeModelAction` | provider-neutral request | raw provider result | Make one model call. |
| `DecodeModelEnvelopeAction` | raw provider result | decoded envelope or protocol diagnostic | Decode only. |
| `ValidateModelRequestIdentityAction` | decoded envelope and request identity | identity evidence | Validate request, stage, operation, and route identity only. |
| `ValidateModelPayloadSchemaAction` | identity-valid envelope and route schema | schema-valid route payload | Apply only the route's closed payload schema. |
| `OrderRepairDiagnosticsAction` | repairable diagnostics | ordered diagnostic IDs | Sort repair diagnostics deterministically. |
| `SelectNextRepairDiagnosticAction` | ordered diagnostics and attempt state | selected diagnostic | Select one next diagnostic only. |
| `CreateRepairAuthorizationAction` | selected diagnostic and candidate revision | repair authorization | Bind one closed operation and its preconditions. |
| `BuildAtomicRepairGuidanceAction` | selected diagnostic and repair unit | repair guidance | Explain one allowed repair. |
| `ValidateRepairEnvelopeAction` | decoded repair response and authorization | identity-valid repair payload | Validate authorization, diagnostic, and revision identity. |
| `ValidateRepairScopeAction` | repair payload and authorization | scope-valid repair operation | Prove only authorized pointers/keys are present. |
| `MergeAtomicRepairAction` | candidate, repair authorization, scope-valid operation | repaired in-memory candidate | Compare-and-swap one authorized operation. |

### 13.5 Artifact, renderer, and traceability actions

| Action | Input | Output | Single responsibility |
|---|---|---|---|
| `ReadArtifactAction` | engine-owned artifact path | raw artifact | Read one artifact. |
| `ParseSpecificationAction` | raw `spec.md` | specification IR/index | Parse the rendered specification contract. |
| `ReadCanonicalPlanStateAction` | engine-owned plan-state path | plan IR | Load authoritative plan state. |
| `ReadCanonicalTaskStateAction` | engine-owned task-state path | task graph | Load authoritative task state. |
| `SerializeCanonicalPlanStateAction` | validated plan IR and plan-input spec IR | canonical plan-state bytes | Serialize one canonical plan state. |
| `SerializeCanonicalTaskStateAction` | validated task graph/runtime state | canonical task-state bytes | Serialize one canonical task state. |
| `StageCanonicalStateAction` | one canonical state payload and transaction | staged canonical-state entry | Stage one authoritative state payload. |
| `ValidateGeneratedViewAction` | canonical IR plus rendered view | view-consistency evidence | Compare a read-only view with deterministic rendering. |
| `AssignRequirementIdsAction` | validated semantic spec content | identified requirements | Assign canonical IDs. |
| `AssignTaskIdsAction` | validated topologically ordered task records | identified tasks | Assign `TNNN` IDs. |
| `BuildRequirementIndexAction` | specification IR | requirement index | Index traceable obligations. |
| `BuildObligationLedgerAction` | spec, reference tokens, plan | full obligation ledger | Include non-ID visible states/guards/tokens as internal IDs. |
| `ValidateTraceReferenceAction` | one downstream source/obligation ID and ledger | reference evidence | Validate one trace reference exists. |
| `ValidateObligationCoverageAction` | one obligation and downstream records | coverage evidence/diagnostic | Apply one obligation's typed coverage rule. |
| `RenderSpecificationAction` | validated specification IR | Markdown candidate | Render `spec.md`. |
| `RenderPlanArtifactAction` | one validated plan artifact IR | Markdown/data candidate | Render one plan output. |
| `RenderTasksAction` | validated task graph | Markdown candidate | Render task IDs, checkboxes, phases, and dependencies. |
| `ValidateEditableSpecificationRenderAction` | rendered `spec.md` and specification IR | round-trip evidence | Reparse only the editable specification and compare normalized IR. |
| `BuildReviewDecisionAction` | review event plus canonical state ID | validated review-state payload | Build one approve/reject record without writing it. |
| `ValidateReviewApprovalAction` | canonical state ID and review evidence | approval authorization | Require approval of the current canonical state. |
| `MapReviewFeedbackAction` | rejected review feedback and unit registry | targeted feedback records | Resolve feedback to explicit plan/task unit IDs. |
| `InvalidateDescendantStateAction` | authorized rework transition and state graph | invalidated-state delta | Invalidate declared descendant states/approvals only. |

### 13.6 Project path and static-validation actions

| Action | Input | Output | Single responsibility |
|---|---|---|---|
| `NormalizeProjectPathAction` | raw model path field | normalized lexical path | Canonicalize separators/dot segments. |
| `ValidateLexicalPathSafetyAction` | normalized path | lexical path evidence | Reject absolute, traversal, control, URI, drive, and UNC forms. |
| `ValidatePathContainmentAction` | lexically safe path and workspace | contained path | Enforce root and existing-ancestor containment. |
| `ResolveProjectForPathAction` | contained path and environment registry | project ownership | Select exactly one project. |
| `ValidateDeclaredFileKindAction` | project path, declared kind, preset | kind evidence | Validate the declared role exists. |
| `ValidatePathOperationAction` | declared kind and operation | operation evidence | Validate read/create/update/delete permission. |
| `ValidatePathRootAction` | project path and kind roots | root evidence | Validate one segment-aware root policy. |
| `ValidateBasenameAction` | basename and kind | basename evidence | Apply exact/glob/regex name rules. |
| `ValidateExtensionAction` | basename and kind | extension evidence | Apply longest compound-extension rules. |
| `ValidateFilenamePortabilityAction` | normalized path and target platforms | portability evidence | Apply Unicode, reserved-name, case, and length rules. |
| `ValidateTestPlacementAction` | test path, source mapping, preset | placement evidence | Enforce co-located/mirrored rules. |
| `ValidateProjectSemanticNameAction` | path and parsed source | semantic filename evidence | Apply Java/C# or configured language rules. |
| `ValidateCommitTargetIdentityAction` | prepared target descriptor and current ancestors | race-free target evidence | Revalidate no-follow ancestors immediately before commit. |
| `RejectUnboundPathTokenAction` | one non-code prose field and file registry | prose-path evidence | Reject actionable path text not bound to a `fileId`. |
| `ParseSourceAction` | source bytes and parser ID | AST/parse diagnostics | Parse one source file. |
| `ExtractImportsAction` | AST and query ID | import records | Execute one import query. |
| `ResolveImportsAction` | import records and resolver | resolution evidence | Resolve referenced modules. |

### 13.7 Task and implementation actions

| Action | Input | Output | Single responsibility |
|---|---|---|---|
| `ValidateTaskDefinitionSchemaAction` | one task definition | schema evidence | Apply the closed task-definition schema. |
| `ValidateTaskExecutabilityAction` | one schema-valid task | executability evidence | Require one concrete file/check/scenario responsibility. |
| `ValidateTaskSourceReferenceAction` | one task source ID | source-reference evidence | Validate one obligation/source reference. |
| `ValidateTaskPhaseKindAction` | one task phase/kind/mode tuple | phase-kind evidence | Apply the verification compatibility matrix. |
| `BuildTaskGraphAction` | valid tasks | dependency graph | Construct graph from declared keys. |
| `ValidateTaskDependencyTargetAction` | one dependency edge and task index | target evidence | Reject an unknown node. |
| `DetectTaskCycleAction` | dependency graph | acyclicity evidence | Detect cycles only. |
| `ValidateTaskPhaseEdgeAction` | one dependency edge and phase policy | phase-edge evidence | Apply phase direction rules. |
| `BuildCompactTaskIndexAction` | validated provisional tasks | compact global task index | Build one model-safe dependency index. |
| `MergeValidatedTaskDependencyAction` | one validated suggested edge and graph | updated graph | Merge one semantic dependency edge. |
| `CalculateParallelEligibilityAction` | one task pair, DAG, paths, locks | pair eligibility evidence | Decide one pair's concurrency eligibility. |
| `CalculateRunnableSetAction` | task graph and execution journal | ordered runnable task IDs | Calculate currently ready tasks only. |
| `SelectRunnableTaskAction` | ordered runnable set | one task or terminal state | Select next task deterministically. |
| `ClaimTaskLeaseAction` | selected task and lock set | task lease | Atomically mark executing and reserve locks. |
| `ReleaseTaskLeaseAction` | task lease and terminal task outcome | lease-release evidence | Release one lease/lock set. |
| `BuildTaskContextAction` | task, indices, repository facts | bounded task context | Gather task-scoped facts. |
| `ValidateChangeTaskIdentityAction` | change proposal and task lease | task-identity evidence | Validate the leased task ID only. |
| `ValidateOperationAuthorizationAction` | one operation and task/file registry | operation authorization | Validate one file ID and operation against plan/task scope. |
| `ResolveCopySourceAction` | one authorized `sourceId` and source registry | contained copy source | Resolve an engine-owned content handle only. |
| `ValidateCopySourceAction` | one resolved copy source and destination policy | copy-source evidence | Validate source kind, media type, provenance, size, and copy permission. |
| `CreateWorkspaceOverlayAction` | task and workspace | isolated task overlay | Create a candidate workspace. |
| `CreateOperationSavepointAction` | task overlay and operation ID | child operation overlay | Create one pre-operation savepoint. |
| `ApplyFileOperationAction` | one valid file operation and overlay | changed overlay | Apply one operation only. |
| `PromoteOperationSavepointAction` | locally valid child overlay | updated task overlay | Promote one operation delta. |
| `DiscardOperationSavepointAction` | invalid child overlay | discard evidence | Discard one operation delta. |
| `DetectUnexpectedChangesAction` | overlay and authorized write set | change-scope evidence | Find unplanned file mutations. |
| `RunConfiguredCommandAction` | available command ID and typed args | command evidence | Execute one restricted command. |
| `DeriveRequiredChecksAction` | task kind, file kinds, diff, preset evidence policy | required command/evidence set | Compute mandatory checks without model choice. |
| `SealTaskTransactionAction` | overlay, evidence, journal, state, rendered view | sealed task transaction | Bind the complete task commit set to one revision. |
| `BuildCompletedTaskStateAction` | task validation authorization and task state | candidate completed task state | Build the state delta to include in the sealed transaction. |
| `RenderCompletionReportAction` | final workflow state and evidence | human report | Produce a report without changing state. |

### 13.8 Persistence actions

| Action | Input | Output | Single responsibility |
|---|---|---|---|
| `CreateArtifactTransactionAction` | intended artifact paths | empty artifact transaction | Reserve a contained staging area. |
| `StageArtifactAction` | one rendered artifact and transaction | updated transaction | Stage one artifact candidate. |
| `ValidateTransactionMembershipAction` | staged transaction and intended entry registry | membership evidence | Prove exact entry-set completeness. |
| `CreateTransactionAuthorizationAction` | sealed transaction and all validation evidence | single-use authorization | Authorize one exact sealed revision. |
| `PrepareTransactionJournalAction` | sealed transaction | durable prepared journal | Persist entries, before-images, target identities, and authorization before mutation. |
| `ApplyTransactionEntryAction` | prepared journal and one entry | applied-entry evidence | Apply and durably record one destination entry. |
| `WriteTransactionCommitMarkerAction` | fully applied journal | committed transaction evidence | Durably write the commit marker last. |
| `CleanCommittedTransactionAction` | committed journal | cleanup evidence | Remove disposable staging/before-images after commit. |
| `ReadTransactionRecoveryStateAction` | one durable journal | typed recovery state | Read marker, phase, and applied entries only. |
| `RestoreTransactionEntryAction` | one uncommitted applied entry and before-image | restored-entry evidence | Restore one entry during rollback. |
| `VerifyCommittedTransactionEntryAction` | one committed journal entry and destination | verified-entry evidence | Verify/roll forward one committed entry idempotently. |
| `DiscardTransactionAction` | uncommitted transaction | discard evidence | Remove candidate state without touching committed files. |

The model is never invoked from a persistence action, and no persistence action accepts a raw model path.

---

## 14. Orchestrator composition

[View the Orchestrator composition sample](code.md#orchestrator-composition).

An orchestrator “contains” children through composition. It does not contain their logic. Actions expose no child collection or dispatcher, so an action cannot contain or call an orchestrator.

### 14.1 `ValidatedGenerationOrchestrator`

This reusable orchestrator expresses the common model interaction:

1. select context;
2. build initial guidance;
3. build request;
4. invoke model;
5. decode response;
6. validate response schema;
7. run the validators registered for the unit;
8. if valid, return the candidate;
9. if model-repairable, invoke actions that order diagnostics and select the next diagnostic, then invoke `AtomicRepairOrchestrator`;
10. repeat local repair within limits;
11. run all unit validators once more;
12. return `Ok`, `Blocked`, or `Failed`.

The orchestrator itself does not build guidance, call the model, validate, or merge content. It only invokes the actions that do so.

### 14.2 `StageGateOrchestrator`

For a requested stage it:

1. invokes stage-order validation;
2. invokes prerequisite presence/readability validation;
3. loads authoritative predecessor inputs through read/parse actions for editable `spec.md` and canonical-state read actions for generated stages;
4. invokes the registered predecessor validators;
5. invokes `ValidateWorkflowMetadataAction` for each metadata invariant, such as whether a reference view is expected;
6. returns the typed predecessor context or stops.

The persisted stage status is advisory until these current artifacts pass. This provides sequential safety without fingerprints.

### 14.3 `TaskSchedulingOrchestrator`

The scheduler invokes `CalculateRunnableSetAction` over phase, dependencies, path sets, shared-resource locks, and command mutability, invokes `SelectRunnableTaskAction`, and invokes `ClaimTaskLeaseAction` to atomically reserve state and locks. Failed/cancelled precommit leases are released through `ReleaseTaskLeaseAction`; successful lease release is an entry in the sealed task transaction. The orchestrator itself does not inspect a graph or lock table. Configuration defaults concurrency to one. Higher concurrency is permitted only for tasks whose validated graph says they are independent and whose overlay commits can be serialized safely. “Different files” alone is never sufficient.

### 14.4 `AtomicRepairOrchestrator`

The repair orchestrator invokes, in order: `OrderRepairDiagnosticsAction`, `SelectNextRepairDiagnosticAction`, `CreateRepairAuthorizationAction`, guidance/request/invoke/decode actions, `ValidateRepairEnvelopeAction`, `ValidateRepairScopeAction`, `MergeAtomicRepairAction`, impacted validators, and the full candidate validator set. It branches only on their outcomes. Selection of a diagnostic, pointer, operation kind, authorization, revision, and validator set is action output; the orchestrator never calculates repair scope.

### 14.5 `UserReviewOrchestrator`

This orchestrator presents engine-rendered plan or task views and waits for an explicit decision tied to the current `canonicalStateId`.

- `approve` records approval and unlocks the next stage.
- `reject` records feedback without changing generated files. Feedback is mapped to one or more explicit IR unit IDs through actions. Each affected unit is regenerated or atomically repaired, the full stage is revalidated and re-rendered, and prior approval is cleared.
- Feedback that cannot be safely mapped to a bounded unit blocks for clarification; the engine does not treat direct edits to a generated view as feedback.

In non-interactive use, approval must arrive through an explicit API/CLI approval event or a deliberately selected policy profile. Merely invoking the next stage does not silently approve review output in the hardened default.

The review record and resulting stage state (`planned`, `tasked`, or rejected/rework state) commit as one `ReviewTransaction` using the Section 25 journal protocol. A crash cannot persist approval without its state transition or vice versa.

---

## 15. Bootstrap flow

Bootstrap occurs before every root workflow and every permitted standalone stage invocation:

[View the Bootstrap flow sample](code.md#bootstrap-flow).

No model call occurs before bootstrap succeeds. A config, preset, reader, parser, project, or command ambiguity is an engine/environment problem and does not consume a repair attempt.

The new engine uses typed filesystem and process adapters. It does not reproduce the current `eval $(get_feature_paths)` pattern (`.specify/scripts/bash/common.sh:71-88`), hard-code `specs/`, or delegate state construction to a shell script.

---

## 16. Reference ingestion and normalization

“Reference requirements in any format” is implemented as an extensible reader system, not as a promise to interpret arbitrary bytes. The invariant is that no reference is silently ignored.

### 16.1 Reader contract

[View the Reference reader contract sample](code.md#reference-reader-contract).

Initial readers should cover:

- plain text and Markdown;
- JSON, YAML, XML, CSV, and other tabular data;
- source code and stylesheet formats;
- PDF;
- common office documents;
- raster images through deterministic OCR/layout decoders where installed;
- a declared opaque-binary adapter only when a purpose-built extractor exists.

Encrypted, corrupted, unsupported, oversized, or unreadable files produce explicit diagnostics. Policy decides whether they block the feature (recommended default) or require explicit user exclusion. “Best effort and silently continue” is prohibited.

Reader selection is deterministic. Each reader declares a media-type rank, minimum probe confidence, stable priority, and whether it is a fallback. Candidates below threshold are removed; the unique highest `(confidence, mediaTypeRank, priority)` tuple wins. A tie is `REF_READER_AMBIGUOUS`, not an arbitrary selection. Deterministic OCR may produce text and regions. Any multimodal or vision-model interpretation is not a reader: it must pass through the normal context/guidance/request/`InvokeModelAction`/closed-schema/citation/repair chain, with citations bound to image regions.

### 16.2 Stable ordering and provenance

Files are processed in normalized repo-relative lexical order. Content blocks receive stable snapshot-local IDs and retain line, node, cell, page, or region coordinates. Each LLM-extracted claim must cite one or more real source locations. The citation validator verifies snapshot/source/block identity, location bounds, and any returned verbatim text.

The complete manifest, source maps, block-disposition ledger, validated claims, `ReferenceContextIR`, and specification-provenance ledger are persisted as one feature-scoped `ReferenceSnapshot` before `specified`. This provenance is not fingerprinting. No content hash is stored or compared across stages.

### 16.3 Structured facts and exact tokens

Where a parser can decide mechanically, the engine extracts facts before involving the LLM:

- JSON/YAML/XML key/value leaves;
- CSV headers/cells;
- CSS selectors/declarations and exact values;
- manifest dependencies/scripts;
- code declarations/imports;
- document headings/tables;
- explicit numeric values, units, and color literals where a format adapter defines them.

The LLM classifies these facts as business, design, visual, technical, validation, assumption, or irrelevant-to-feature. Exact source values are carried separately from model prose. A value marked as a required preserved visual token receives an internal token ID. Downstream coverage validators require that token ID in planning and task records, and renderers insert the exact value.

### 16.4 Semantic extraction flow

1. Decode and chunk each file.
2. Generate claims for one chunk at a time.
3. Validate response schema and every source citation.
4. Repair only an invalid claim/citation.
5. Record a disposition for every decoded block, including a positive `no_feature_claim` result; a file-level status alone is insufficient.
6. Merge validated claims into a per-document claim set. A compact reconciliation item includes claim ID, normalized claim payload, modality, subject/object IDs, and source citations—not an ID without meaning.
7. Reconcile bounded groups hierarchically: within document, across related documents, then across compact group summaries. Every summary retains member claim IDs, payloads needed to decide conflict, and citations.
8. Validate that returned conflict/source/claim IDs exist and that every input claim appears in exactly one retained, superseded, duplicate, or conflicting disposition.
9. Create explicit `SourceConflict` and `OpenQuestion` records.
10. Block specification completion when a conflict changes required behavior and no resolution exists.
11. Validate every inventory entry and every decoded block has a final accounting state.
12. assemble and persist the canonical `ReferenceSnapshot` in the same specify transaction as its rendered view.

`README.md` is flagged as an organizer for presentation, but its claims remain peer authoritative. A conflict with a sibling is treated like any other authoritative conflict.

---

## 17. Specify stage design

### 17.1 Inputs

[View the Specify CLI contract sample](code.md#specify-cli-contract).

The concrete CLI syntax may retain an alias such as `-ref`, but the parser must use a real argument grammar. It must not implement the current “everything before the first hyphen flag” rule because hyphenated descriptions can be misparsed (`prompts/sdd-specify.md:51-61`). Git/branch-type flags are deliberately ignored by the new engine. Quoting, duplicate flags, missing values, unknown flags, and `--` termination must have explicit behavior.

### 17.2 Deterministic preflight

1. Parse arguments.
2. Require a nonblank description.
3. Validate an optional explicit feature ID against the versioned engine naming policy.
4. If references are requested, validate and completely inventory the reference folder **before creating any feature artifact or directory**.
5. Derive identity.
6. Resolve engine-owned artifact paths.
7. Reject a collision under the default create-only policy.
8. Reserve an artifact transaction, not a committed feature directory.

Default deterministic identity derivation is:

1. trim and normalize user text using a versioned Unicode normalization/transliteration adapter;
2. invariant case-fold;
3. replace runs outside `[a-z0-9]` with one hyphen;
4. collapse repeated hyphens and trim ends;
5. apply `workflow.featureIdMaxLength`;
6. truncate on a normalized token boundary where possible, then trim;
7. if no valid characters remain, require explicit `--feature-id`;
8. fail on an existing feature ID rather than overwriting or choosing an LLM-generated alternative.

This algorithm is versioned with the engine. It does not use an LLM summary, so the feature directory cannot vary between model runs.

### 17.3 LLM work

The LLM performs two semantic activities:

1. reference claim extraction/reconciliation, when references exist;
2. specification content generation from the request and validated claims.

Calls are split into typed units:

- display title;
- primary story;
- observable outcomes;
- acceptance-criteria candidates;
- functional-requirement candidates;
- business rules;
- assumptions and scope boundaries;
- explicit non-goals;
- prohibited behaviors;
- entities, only if business data is involved;
- semantic ambiguity/open-question review.

The LLM does not assign IDs, headings, paths, dates, status, checklist state, or execution status. It cites reference claim IDs/source locations and returns business content rather than Markdown.

### 17.4 Deterministic specification validation

The engine validates:

- route response schema and source references;
- nonempty mandatory IR fields;
- engine-assigned, unique, well-formed `AC-*`, `FR-*`, `BR-*`, and `EC-*` identifiers; initial generation is gap-free, while edits preserve surviving IDs, allocate new monotonically increasing IDs, and never reuse deleted IDs;
- explicit `given`, `when`, and `then` fields for each acceptance criterion;
- duplicate or byte-identical requirements;
- typed clarification state rather than fragile substring matching;
- citation validity and reference-file accounting;
- exact user-facing copy obligations;
- exact visual/style token preservation in `reference-context.md`;
- presence of separate observable flows when claims explicitly distinguish success, invalid, empty, error, or terminal outcomes;
- absence of template placeholders and model-authored checklist state;
- artifact boundary: `spec.md` has no `Reference Context` heading or reference metadata;
- obvious technical leakage: foreign absolute paths, fenced code, stylesheet declarations, known source-file paths/extensions, known framework/package identifiers, and implementation-only handles;
- `reference-context.md` existence and section completeness whenever `referenceRequest.used` is true;
- equality between the reference inventory and the sidecar's rendered file inventory;
- unresolved authoritative conflicts and blocking open questions;
- workflow artifact paths and transaction completeness.

The technical-leakage validator is a strong lexical/static lint, not a complete semantic proof. A separate semantic-review action decides nuanced cases and labels them model-assisted.

### 17.5 Rendering and commit

After validation:

1. assign requirement IDs;
2. render `spec.md` from `SpecificationIR` and the canonical template contract;
3. render `reference-context.md` when references were used;
4. serialize the canonical reference snapshot and specification-provenance ledger when references were used;
5. reparse `spec.md` and compare its normalized IR to the validated source IR;
6. compare the read-only reference-context view with deterministic rendering from its canonical IR;
7. stage the complete artifact set, canonical reference state, and next workflow-state record in one stage transaction;
8. validate the transaction;
9. commit the set and durable state marker;
10. report engine-known paths and readiness for user spec editing/validation, then `plan`.

No fingerprint is written. If the engine process is restarted, later stages reload and revalidate the current artifacts.

### 17.6 Specify gate

`specify` succeeds only when:

- the specification IR and rendered `spec.md` pass all blocking rules;
- every reference file is accounted for;
- the sidecar exists and passes when required;
- no behavior-changing reference conflict remains unresolved;
- the artifact transaction committed;
- workflow state recorded `specified` after the commit.

---

## 18. Plan stage design

### 18.1 Inputs and preconditions

`PlanOrchestrator` receives the `featureId` from `FeatureWorkflowOrchestrator`. A standalone `plan` invocation must provide it. It does not count directories or auto-select a feature.

The stage gate:

1. requires workflow state `specified`;
2. requires and parses `spec.md`;
3. requires `reference-context.md` exactly when workflow metadata says references were used;
4. revalidates specification structure, IDs, typed clarifications, and sidecar completeness;
5. builds the current `RequirementIndex` and token/scope obligation ledger;
6. rejects unresolved clarification or reference-conflict records;
7. confirms resolved environments still match the current repository.

Starting `plan` treats the current validated `SpecificationIR` as the user's approved planning input. The engine stores that full normalized IR with canonical plan state, so a later spec edit can invalidate downstream state through direct typed comparison without a fingerprint.

The engine does not run a setup script that overwrites `plan.md`. It creates an isolated artifact transaction and assigns output paths directly.

### 18.2 Deterministic repository reality

Before an LLM design call, actions build repository facts:

- manifests, modules/projects, dependencies, lockfiles, and package manager;
- source/test/style/config/asset roots;
- allowed extensions and filename patterns;
- existing application entry points discovered through configured adapters;
- existing test runners, scripts, fixtures, and verification commands;
- compiler, formatter, linter, AST parser, and import resolver availability;
- current files near requirement-relevant terms and known entry points;
- generated and forbidden paths;
- constitution sections and mechanically compiled project overlays;
- missing prerequisites where a required capability has no current command/tool.

These facts are immutable model inputs. The LLM may interpret relevance, but may not claim that a dependency, command, folder, test suite, or entry point already exists unless it selects a supplied fact ID. A new dependency is a typed proposal, never a repository fact.

Phase-0 “research” is grounded only in the supplied reference snapshot, repository facts, compiled presets, project standards, configured package-registry metadata, and user-provided evidence. The default engine performs no open-web research. When a decision requires unavailable external evidence, the model sets `unresolvedExternalEvidence: true`; the stage blocks with `RESEARCH_EVIDENCE_REQUIRED` until evidence is supplied through a controlled read-only import. The engine does not let a model fill the gap from memory and label it researched.

### 18.3 LLM work

The LLM generates bounded plan units:

- summary and minimal-change hypothesis;
- implementation-shape decision;
- existing touched-area selection from engine-provided file/project IDs;
- proposed new file records, one or a small related group at a time;
- selections from typed repository/preset fact IDs plus separate technical rationale;
- research unknowns and one decision/rationale/alternatives record per question;
- typed new-dependency proposals containing ecosystem, package, version constraint, configured registry source, scope, rationale, and explicit approval state;
- constitution-compliance reasoning and justified deviations;
- data/state entity models when applicable;
- the smallest justified structured contract obligations when applicable;
- quickstart scenarios;
- requirement-to-design/verification mappings;
- task-generation approach.

The model returns project path proposals as typed `{projectId, declaredKind, operation, repoRelativePath}` records. Each one is path-validated immediately. Accepted proposals become `FileRecord`s with stable `fileId`s; later calls refer only to those IDs.

### 18.4 Artifact applicability

The engine requires these decisions:

| Artifact | Disposition |
|---|---|
| `plan.md` | Always required |
| `research.md` | Always required; may state that no unresolved technology choice existed, but must still record grounded decisions |
| `quickstart.md` | Always required; contains executable automated/manual validation scenarios |
| `data-model.md` | `required` when the feature introduces or changes data/state concepts; otherwise explicit `not_applicable` with reason |
| `contracts/` | `required` only when a structured interaction/API/event/file/schema contract adds planning value; otherwise explicit `not_applicable` with reason |

The model proposes applicability reasoning. A semantic-review action may challenge it. The engine validates that the declared disposition and actual artifact set agree; it never infers applicability from a missing file.

### 18.5 Deterministic plan validation

Validators enforce:

- feature ID, date, and spec link match engine facts;
- mandatory plan IR fields and artifact decisions exist;
- every mechanical technical assertion is a typed `FactSelection` whose ID/value matches repository/preset facts; prose rationale receives semantic review and is not claimed to be mechanically contradiction-free;
- every touched existing file exists and is within the selected project;
- every new/update path passes the full environment preset algorithm;
- proposed paths use accepted `fileId`s consistently;
- no persistent foreign absolute paths;
- minimal-change claims do not list rejected layers as proposed outputs;
- research records contain decision, rationale, alternatives, source/fact links, and no unresolved external-evidence flag;
- each dependency proposal names a configured registry source and allowed version form, passes package/source policy, and has explicit approval before a setup task can be emitted; approval does not claim the package is installed;
- entity names/references and relationships resolve within the data-model IR;
- format-specific contract artifacts pass their registered schemas when a validator exists;
- quickstart scenarios have complete typed automated/manual steps and reference real requirements/tokens/guards; whether a prose scenario is adequate remains semantic unless an executable command/assertion proves it;
- configured automated verification references only available command IDs;
- unsupported automation has a prerequisite decision or an explicit manual scenario;
- every `AC-*`, `FR-*`, and `EC-*` has exactly one normalized coverage entry;
- business rules, exact copy, scope guards, visible states, accessibility/responsive obligations, and preserved tokens in the internal obligation ledger have design/verification coverage or an explicit blocking gap;
- every required visual token is named exactly and has a manual visual-verification expectation;
- all planning artifacts remain under the feature directory;
- no repository implementation files or `tasks.md` are staged or changed;
- progress status is engine-derived: planning phases complete only after their validators pass, and implementation phases remain incomplete;
- every read-only planning view exactly equals deterministic rendering from validated canonical `PlanIR`.

### 18.6 Plan outputs and gate

Immediately before transaction preparation, the engine rereads `spec.md` and compares its full normalized IR with the plan input held in memory. If the user edited it during planning, the engine discards the plan candidate and restarts from the new spec; it never overwrites the newer edit. This is direct value comparison, not a fingerprint.

The engine stages and commits normalized `spec.md`, canonical `PlanIR`, the full plan-input `SpecificationIR`, and the complete declared read-only view set in one stage transaction. Successful generation enters `plan_review_pending`. The user validates the plan, research, design, contract, and quickstart views.

- Approval is recorded against the current plan `canonicalStateId` and advances state to `planned`.
- Rejection supplies feedback through the engine. Actions map it to explicit plan unit IDs; those units are repaired/regenerated, full validation/rendering reruns under a new state ID, and review restarts. Generated files are not edited.

`plan` is complete only if:

- specification preconditions remain valid;
- repository facts/preset selection are unambiguous;
- Phase 0 research records pass;
- Phase 1 artifact manifest and artifacts pass;
- Phase 2 task-generation approach passes;
- all coverage obligations pass;
- no implementation-side change occurred;
- the artifact transaction commits;
- current canonical plan state has explicit approval;
- workflow state transitions `specified -> plan_review_pending -> planned`.

---

## 19. Tasks stage design

### 19.1 Inputs and preconditions

The stage gate requires workflow state `planned`, an approval bound to the current plan `canonicalStateId`, and an editable `spec.md` whose normalized IR equals stored plan-input specification state. It loads and revalidates canonical `PlanIR`, validates every required read-only view against deterministic rendering, and confirms that absent `not_applicable` artifacts have reasons. It uses the engine's canonical-state/artifact registry rather than a helper's incomplete `AVAILABLE_DOCS` list.

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

### 19.2 LLM work

The LLM receives one related obligation cluster and proposes task records. It decides:

- useful work decomposition;
- one clear responsibility per task;
- implementation versus integration versus verification intent;
- semantic dependencies;
- whether related obligations can safely share a task;
- manual scenario selection when no automation exists;
- descriptive wording.

It must select files by existing `fileId` where the plan already identified them. If a new path is genuinely required but absent from the plan, the response is invalid and planning must be repaired/re-run; tasks cannot silently expand architecture.

The LLM does not assign `TNNN`, checkbox text, `[P]`, final ordering, or arbitrary commands.

After all clusters have schema-valid provisional definitions, the engine assigns provisional internal IDs and creates a compact global index containing responsibility, source/obligation IDs, produced/consumed `fileId`s, capabilities, and existing edges. A bounded `tasks.dependencies.reconcile` route may propose missing semantic edges over that index. For large graphs the route processes overlapping partitions and a final compact boundary index. The engine validates every proposed edge, then runs global unknown-node, cycle, and phase-edge actions. The model may suggest semantic dependencies; only the engine merges them.

### 19.3 Deterministic task validation

Each proposed task must have:

- one allowed phase and kind;
- one concise responsibility;
- a non-placeholder description;
- at least one known obligation/source ID;
- one or more declared read and/or write `fileId`s for file work;
- or one concrete configured command/scenario for a verification-only task;
- dependency keys that exist after merge;
- a verification mode and evidence expectation appropriate to its kind.

Every `fileId` resolves to a plan-approved path that is revalidated against the selected preset and plan authorization. Automated verification commands must exist in the available command registry. Mandatory checks are derived by `DeriveRequiredChecksAction` from task kind, file kinds, evidence policy, and later the implementation diff. A model may request only an optional additional command from the supplied registry. Test paths must match the configured test type, roots, extension, naming, and placement.

Phase/kind/mode compatibility is closed and validated:

| Task intent | Allowed placement |
|---|---|
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
9. require implementation and manual visual-verification coverage for exact visual tokens;
10. require explicit preservation work for prohibited behavior when code could otherwise introduce it;
11. reject any path outside the plan-selected surface;
12. calculate safe parallel eligibility from transitive dependencies, write/write conflicts, unsafe read/write conflicts, shared-resource locks, and exclusive command capabilities;
13. topologically order tasks within the required phase progression;
14. assign `T001...` after final ordering;
15. render `[P]` only for engine-approved parallel tasks;
16. render all tasks initially as `- [ ]`.

A task that says only “review,” “analyze,” or “lock requirements” cannot pass unless its typed kind names a concrete configured verification command/scenario. Semantic task minimality can receive model-assisted review, but structural executability is deterministic.

### 19.4 Parallelism policy

A task is parallel-eligible only if all are true:

- it has no dependency path to or from another concurrently runnable task;
- write sets do not overlap;
- a read path is not written by another task unless the read is declared snapshot-safe;
- shared-resource locks do not overlap;
- neither task runs an exclusive or dependency-mutating command;
- neither task produces an input needed by the other;
- both can execute in isolated overlays and their commits can be serialized without conflict.

The default execution concurrency is one. `[P]` describes eligibility; it does not force concurrent execution.

### 19.5 Rendering and gate

The renderer creates phase headings, `TNNN`, checkboxes, requirement source tags, paths, dependencies, and parallel examples from the validated graph. It does not ask the LLM to emit task Markdown.

The engine commits canonical `TaskGraph`, engine-owned initial `TaskRuntimeState`, and the read-only `tasks.md` view, then enters `tasks_review_pending`. Approval tied to the current task `canonicalStateId` advances to `tasked`. Rejection maps feedback to task unit IDs, invalidates the prior review, rebuilds/revalidates under a new state ID, and presents a new view; `tasks.md` is never imported as state.

`tasks` is complete only when:

- all predecessors revalidate;
- every task is executable and preset-valid;
- the graph is acyclic and fully resolvable;
- complete obligation coverage passes;
- parallel flags are engine-derived;
- rendered `tasks.md` exactly equals deterministic rendering of current canonical task state;
- the artifact transaction commits;
- current canonical task state has explicit approval;
- workflow state transitions `planned -> tasks_review_pending -> tasked`.

---

## 20. Implement stage design

### 20.1 Inputs and preconditions

The stage gate requires workflow state `tasked`, canonical task state, and an approval whose `canonicalStateId` equals the current task state. It reparses editable `spec.md`, requires equality with the stored plan-input specification IR, loads canonical plan/task/reference state, checks every generated view against deterministic rendering, and revalidates:

- specification and reference obligations;
- plan artifacts and declared repository surface;
- task IR, requirement coverage, paths, dependency DAG, and parallel eligibility;
- current environment/project/preset resolution;
- availability of commands required by pending tasks.

If current repository facts make a task path invalid—for example a project was removed—the stage blocks. It does not ask the LLM to improvise a different architecture.

### 20.2 Task selection

`CalculateRunnableSetAction` calculates ready tasks, `SelectRunnableTaskAction` chooses the lowest phase/order candidate, and `ClaimTaskLeaseAction` atomically changes that task to `executing` while reserving its declared locks. If the compare-and-swap claim fails, selection repeats from fresh state. A task execution journal distinguishes:

- `pending`;
- `executing`;
- `validation_failed`;
- `blocked`;
- `completed`.

`tasks.md` remains the human view (`[ ]` or `[X]`); richer transient/recovery state is stored in engine state. A task is never rendered `[X]` before its transaction and evidence commit.

### 20.3 Task context

The model receives only:

- task responsibility and description;
- linked requirement/obligation records;
- relevant plan decisions;
- exact allowed read/write `fileId`s;
- bounded current contents of target and directly related files;
- nearby repository conventions selected deterministically;
- applicable constitution/preset rules;
- exact available command IDs;
- required evidence;
- one response schema.

The model is not asked to rediscover the repository, choose a different target, or execute tools.

### 20.4 Change planning and filename validation

For a multi-file task, a model call may propose an ordered list of operation intents. Every destination must be a plan-approved `fileId`; implementation cannot mint a path or `fileId`. A missing destination is an upstream plan/task defect. Filename guidance and atomic filename repair occur in planning, where a `ProjectPathCandidate` exists.

Code is generated one file operation at a time. A response cannot include a raw path or command. The closed operation set is:

- `CreateFile`: complete content to an approved absent destination;
- `UpdateFile`: a patch to an approved existing destination;
- `ReplaceFile`: complete replacement content for an approved existing destination;
- `CopyFile`: byte-exact content from an engine-resolved repository/reference/template `sourceId` to an approved destination;
- `DeleteFile`: disabled by default and separately policy-authorized.

`CopyFile` validates source provenance, media type, size, permission, and destination policy. Copy-overwrite is represented as an explicitly authorized replace target through `expectedTargetState`; it is never inferred. A later adaptation is a separate operation.

Before invoking a model, the engine estimates the maximum serialized response size. `CreateFile` and `ReplaceFile` are permitted only when complete content fits the route's hard output budget with schema overhead. A larger change must use an exact `CopyFile` source plus bounded updates, parser-addressed/hunk updates, or an explicitly replanned set of smaller files; responses are never truncated and partial “complete content” is never applied. This keeps nano-class calls bounded while allowing large existing code to be copied deterministically.

### 20.5 Candidate workspace and validation

Each task executes in an isolated workspace overlay. Each operation has a child savepoint based on the same pre-operation task-overlay revision:

1. create the task overlay from the current committed workspace;
2. create an operation savepoint;
3. apply one authorized create/update/replace/copy/delete operation to the savepoint;
4. ensure only that operation's declared destination changed and validate expected target state;
5. run operation-local checks: path/scope, patch applicability, source parse/syntax, local declaration/filename rules, and copy-source policy;
6. on failure, discard the savepoint; every repair is reapplied to the unchanged pre-operation snapshot;
7. after a local pass, promote the operation delta into the task overlay and advance the task-overlay revision;
8. after all declared operations are staged, run coupled/task checks: imports, module/project ownership, compilation/type analysis, lint, targeted tests, and full authorized-delta validation;
9. localize a coupled failure to one operation where evidence permits, repair that operation, and deterministically rebuild the task overlay from the clean task base plus the ordered accepted operations; use an explicitly authorized `replace_group` only when the failure is genuinely inseparable;
10. derive mandatory task/phase commands from policy, run them, and validate manual-evidence gates;
11. after every mutating command, diff the overlay, allow only task writes plus that command's declared authorized/ephemeral effects, discard permitted ephemeral outputs where policy says so, and reject every undeclared delta;
12. run one final no-unexpected-change check immediately before sealing the task transaction.

The exact checks depend on compiled capability, not a universal assumption. Per-operation checks never reject a valid temporary cross-file incompleteness. For example, a JavaScript-only Node project may have no compile command; a Maven Java project will normally compile; a UI-only feature may require a manual visual scenario in addition to unit tests.

### 20.6 Code repair

Compiler/linter/test repair is scoped to the smallest semantically coupled unit supported by the diagnostic:

- one scalar/config value;
- one import declaration;
- one declaration or function;
- one patch hunk;
- one file when the tool cannot localize further;
- a tightly coupled path-plus-reference group when a rename requires import updates.

The repair request includes the failing diagnostic, relevant excerpt, immutable requirement/plan context, allowed `fileId`, pre-operation revision, and exact replacement schema. It does not include other writable files. If the repair legitimately requires a different file, the current task proposal is structurally incomplete; execution follows the explicit upstream-rework protocol rather than expanding scope silently.

### 20.7 Command execution

Only engine-derived mandatory commands and validated model-requested optional command IDs can run. The model may not create a command or omit a required one. The command runner:

- executes `executable` plus argv without a shell;
- uses a contained working directory;
- supplies only allowlisted environment variables;
- enforces timeout, output limit, network policy, and mutability class;
- records bounded stdout/stderr and exit status as evidence;
- treats a non-success exit as a diagnostic;
- snapshots/diffs declared effects after every mutating command and exposes no undeclared result to commit;
- never interprets command output as model instructions.

Dependency-mutating commands run only in the task overlay and require an authorized manifest/lockfile write set. Externally irreversible effects are not automatically executed; they block for explicit policy/user authorization.

### 20.8 Commit and task completion

A task commit authorization exists only after:

- all operations were preset-valid and task-authorized;
- all patches applied;
- no unplanned files changed;
- required syntax/static/import checks passed;
- required configured commands passed, or a `red_then_green` verification task produced the specifically authorized expected-red evidence that its dependent implementation must later turn green;
- required manual evidence was recorded, or the task remains pending;
- the overlay is internally consistent.

The engine first builds candidate completed runtime state, renders `tasks.md`, and seals one `TaskTransaction` containing the exact project overlay delta, verification evidence, execution journal, canonical task graph/runtime state, rendered tasks view, lease/lock transition, and next workflow state when applicable. A single-use authorization is bound to the sealed overlay revision and exact entry set.

The journaled transaction is then prepared, applied entry by entry, and marked committed only after every project/state/evidence/view entry is durable. The commit marker is last. Only that marker permits `[X]` to be reported. Lock release is part of the committed state or is recovered idempotently; an orchestrator never releases it directly. If any persistence step fails before the marker, recovery rolls the complete transaction back. This intentionally differs from the current prompt's warning-and-continue behavior (`prompts/sdd-implement.md:117-127`).

### 20.9 Failure propagation

- A failed sequential task blocks its dependents and its phase.
- A failed parallel-eligible task does not cancel independent in-flight tasks, but it blocks its dependents.
- Successful independent tasks may commit; failures are aggregated at a scheduling boundary.
- No pending or blocked task is marked complete.
- `failed`, `blocked`, and `completed` are distinct workflow results.
- Retry exhaustion returns the last valid candidate, diagnostics, and exact repair unit; it never accepts invalid code.

### 20.10 Final implementation gate

The stage completes only when:

- every required task is `[X]` with committed evidence;
- no task is executing, failed, or blocked;
- configured final build/lint/type/test checks pass;
- required manual quickstart evidence is recorded;
- actual changed paths are within the union of validated task write sets;
- every final mutating command's effects pass a post-command delta gate and disposable outputs are absent from the commit set;
- requirement/obligation evidence remains complete;
- `tasks.md` exactly equals deterministic rendering of the completed canonical task graph/runtime state;
- workflow state transitions from `tasked` to `implemented` after final persistence.

---

## 21. Deterministic validation catalogue

This catalogue is normative for the first engine version. A project may add validators or raise severity. It may not disable locked safety validators.

### 21.1 Cross-stage validators

| Validator | Method | Blocking condition | Repair owner |
|---|---|---|---|
| Config schema | JSON Schema plus semantic rules | Missing/unknown/invalid config | User/environment |
| Preset schema | JSON Schema, resource checks, placeholder rejection | Invalid/unresolved preset | User/environment |
| Environment resolution | Manifest adapters and root specificity | Zero/multiple project owners | User/environment |
| Stage order | Workflow state enum | Requested predecessor not complete | User/workflow |
| Artifact presence | Engine artifact registry and filesystem | Required artifact absent/unreadable | User/workflow |
| Predecessor validity | Reparse editable spec; load canonical generated state; compare deterministic views; run stage validators | Current predecessor no longer passes | Prior-stage repair |
| Path containment | Canonical path and symlink resolution | Escape/absolute/forbidden path | Usually not model-repairable; path field may be repaired only when otherwise safe |
| Model protocol | Request identity plus closed response schema | Malformed/wrong route response | Model retry/repair |
| Placeholder | Template/model sentinel scan | Unresolved placeholder remains | Model atomic |
| Transaction boundary | Staged-set path and membership checks | Missing/extra/outside write | Engine/workflow |

### 21.2 Specify validators

| Validator | Deterministic rule | Semantic remainder |
|---|---|---|
| Argument contract | Required description, known flags, one value each, valid type | None |
| Feature identity | Versioned slug algorithm, configured maximum length, no collision | Display title quality |
| Reference root | Configured-root containment, readable directory, no symlink escape | None |
| Reference accounting | Stable inventory equals processed-status inventory | Relevance of content |
| Reader support | MIME sniff plus installed reader | Meaning of decoded content |
| Citation | Source ID, bounds, and verbatim text exist | Whether citation proves claim |
| Required sections | Typed required fields and renderer contract | Whether prose is adequate |
| Requirement IDs | Engine-assigned type/uniqueness; stable surviving IDs and monotonic new IDs | Whether the requirement is substantively correct |
| Acceptance form | Nonempty Given/When/Then fields | Whether scenario is truly testable |
| Clarification state | No unresolved typed clarification at success | Whether all ambiguity was discovered |
| Business-only lint | No obvious code/path/framework/CSS leakage | Nuanced business/technical classification |
| Exact-copy propagation | Byte-for-byte value from source ledger | Whether source copy is actually required |
| Visual-token propagation | Every required token ID/value rendered in sidecar | Semantic classification of required token |
| Reference conflict gate | Every known conflict has resolution/open question | Discovery of all semantic conflicts |

### 21.3 Plan validators

| Validator | Deterministic rule | Semantic remainder |
|---|---|---|
| Repo-fact consistency | Typed fact ID/value exists in repository/preset facts | Prose relevance and design interpretation |
| Artifact manifest | Required/not-applicable enums match actual outputs | Whether applicability choice is wise |
| Project path | Full preset path algorithm | Whether a new file is justified |
| Existing touched area | File exists and has accepted ID/kind | Whether it is the minimal surface |
| Research record | Required fields and fact/source references exist | Quality of rationale/trade-off |
| Data-model integrity | Unique entities/fields; relationship targets resolve | Correct domain modeling |
| Contract syntax | Registered schema validator passes | Whether contract captures full intent |
| Quickstart integrity | Required typed steps plus real requirement/scenario/command IDs | Scenario adequacy unless executed |
| Coverage | Every obligation ID mapped; no unknown ID | Whether mapping is semantically sufficient |
| Visual obligation | Exact token appears in design and manual verification | Quality of chosen design |
| Scope | Only feature artifacts staged; no `tasks.md`/source writes | None |
| Progress | Phase/gate status derived from evidence | None |

### 21.4 Tasks validators

| Validator | Deterministic rule | Semantic remainder |
|---|---|---|
| Task definition | Closed schema and allowed phase/kind/mode; no model-owned runtime status | Task wording/minimality |
| Source reference | Known obligation IDs only | Whether links are substantively correct |
| Executability | Concrete write, command, or manual scenario exists | Whether work will achieve desired result |
| Path authorization | Every path has `fileId`, plan authorization, preset pass | None |
| Test kind/placement | Preset root/name/extension/mapping | Test-case quality |
| Command availability | Known available command ID and typed arguments | Whether command is the best validation |
| Required checks | Preset evidence policy derives mandatory checks from task/file/diff | Whether optional extra checks add value |
| TDD evidence | Expected-red diagnostic is exact and same check is bound to a later green task | Whether the test captures all desired behavior |
| Dependency integrity | Known nodes, DAG, valid phase direction | Missing semantic dependencies |
| Parallel eligibility | No dependency/path/lock/command conflict | Hidden external shared resources not declared |
| ID/order/render | Engine topological order and gap-free `TNNN` | None |
| Coverage | Obligation-specific required task kinds exist | Semantic sufficiency of task content |
| No placeholder task | No placeholder values; typed executable operation | Overly vague but syntactically concrete wording |

### 21.5 Implement validators

| Validator | Deterministic rule | Semantic remainder |
|---|---|---|
| Runnable task | Pending, dependencies complete, locks free | None |
| Change schema | Closed operation schema and current task ID | None |
| Write scope | Target belongs to declared task write set | None |
| Operation validity | Create/update/replace/copy/delete state matches filesystem and policy | None |
| Copy source | Engine source ID, provenance, media type, size, and permission pass | Whether copied code is the best design choice |
| Patch scope/apply | Patch affects one declared target and applies | Whether change is desirable |
| Filename/path | Full preset path algorithm | Filename meaningfulness within valid rules |
| Source parse | Configured parser accepts code | Runtime behavior |
| Language semantic name | Configured Java/type/namespace rules | Domain naming quality |
| Import resolution | Resolver finds allowed targets | Architectural appropriateness where not mechanically encoded |
| Manifest/dependency | Declared package/project and configured validator | Necessity/security suitability of dependency |
| Tool checks | Exit code/output from formatter, compile, lint, test | Coverage of untested behavior |
| Unexpected change | Overlay delta subset of authorized writes | None |
| Command effects | Post-command delta subset of task plus declared command effects | None |
| Evidence | All task evidence predicates satisfied | Manual observation when required |
| Completion | Commit plus evidence plus status persistence | None |

### 21.6 Validators that must not be overstated

The following remain LLM-assisted or human-reviewed unless an executable/domain-specific rule exists:

- whether a requirement is completely testable and unambiguous;
- whether every behavior was extracted from arbitrary prose, images, or diagrams;
- whether two arbitrary references conflict semantically;
- whether a specification introduced an unsupported but plausible behavior;
- whether a plan is truly the smallest viable implementation;
- whether a task is optimally sized;
- whether code fully satisfies intent beyond executable assertions;
- subjective visual quality beyond exact token/layout checks.

The engine records such findings with their real evidence class.

---

## 22. Atomic repair protocol

### 22.1 Definition of atomic

An atomic repair changes the smallest independently valid IR unit associated with one diagnostic. It is not necessarily one character. The unit may be:

- one scalar field, such as a proposed path;
- one list item, such as a requirement;
- one structured record, such as a task;
- one artifact section;
- one coverage entry;
- one dependency edge;
- one patch hunk or declaration;
- one complete file only when a parser/tool cannot localize the failure;
- one explicitly declared coupled group, such as a renamed path plus import references that cannot be valid separately.

Atomicity means unrelated valid units cannot change.

### 22.2 Repair classification

Every diagnostic declares one class:

- `canonicalize`: a documented semantics-preserving normalization, such as slash normalization, applied before candidate identity is established;
- `model_atomic`: the model produced an invalid repairable unit;
- `user_input`: a missing decision, unresolved authoritative conflict, or explicit approval is required;
- `environment`: configuration, reader, parser, repository, or command capability is missing/broken;
- `not_repairable`: retrying a model cannot make the operation safe.

Configuration and environment errors never consume LLM repair attempts.

### 22.3 Repair authorization

`CreateRepairAuthorizationAction` creates an immutable authorization after diagnostic ordering and selection actions have run:

[View the Repair authorization sample](code.md#repair-authorization).

The operation and every target pointer/key/anchor are selected by the engine. The model cannot choose what to modify. `candidateRevision` is run-local compare-and-swap control for concurrent repair attempts; it is not persisted as an artifact-freshness fingerprint.

The repair algebra is closed:

- `replace(pointer, expectedValue, replacement)`;
- `insert(collectionPointer, stableKeyOrAnchor, replacement)`;
- `delete(pointer, expectedValue)`;
- `replace_group(exactAuthorizedPointers, expectedValues, replacements)`.

`replace_group` is allowed only for a predeclared inseparable unit and never as retry-scope expansion. A missing task uses `insert`; a removable dependency edge uses `delete`; a coupled rename/reference correction uses `replace_group` only when intermediate states cannot be validated independently.

### 22.4 Repair request and response

The repair guidance contains:

- the exact diagnostic code and rule;
- rejected value;
- expected values/patterns or concrete allowed candidates;
- the current repair unit only;
- minimal immutable context required to preserve meaning;
- the fixed target pointer;
- the exact replacement schema;
- the instruction that unrelated fields must not be returned or changed.

Example:

[View the Repair request sample](code.md#repair-request).

Valid response:

[View the Repair response sample](code.md#repair-response).

The response cannot include a pointer, operation kind, or extra replacement. For insert/delete, the route-specific closed schema exposes only the value fields required by the preauthorized operation.

### 22.5 Merge and revalidation

1. Validate authorization, diagnostic, candidate ID, and candidate revision.
2. Validate the exact response cardinality and replacements against the unit schema.
3. Compare every authorized old-value/key/anchor precondition against the current candidate.
4. Reject any attempt to change an immutable sibling or undeclared group member.
5. Apply the closed operation to an in-memory copy with compare-and-swap, then increment the candidate revision.
6. Run the validator that produced the diagnostic.
7. Run declared dependent validators. A planning path change, for example, reruns project ownership, kind, filename, placement, plan authorization, task collision, and render-reference checks.
8. If the unit passes, retain it and select the next diagnostic in stable order.
9. When no local diagnostics remain, run the full candidate validation suite.
10. Only a full pass can authorize rendering or commit.

The engine never trusts a model field such as `valid: true`.

### 22.6 Unparseable output

When no IR exists because the model output cannot be decoded, no atomic pointer is available. The protocol permits a narrowly defined response-level retry containing:

- the original schema;
- decoder diagnostics only;
- no request to reconsider semantics;
- one valid minimal example.

After the configured response-level attempts, the unit fails with `MODEL_RESPONSE_SCHEMA_INVALID`. Whole-stage regeneration is not used.

### 22.7 Repair limits and escalation

Limits apply per unit and per stage. Repeated identical failure at the same pointer ends early. Exhaustion returns:

- last schema-valid candidate, if one exists;
- all stable diagnostics;
- attempted replacements and validation outcomes in redacted metadata form;
- the exact blocked unit;
- whether a stronger configured model route, user decision, or environment change is required.

The engine never broadens repair scope automatically because attempts are running out.

### 22.8 Repair examples

#### Wrong task filename

`src/loginTests.ts` is proposed as a colocated React unit test. The preset requires `*.test.tsx`. Only the path field is repaired. Once accepted, renderer references update from `fileId`; task prose and requirement links remain untouched.

#### Missing coverage

`FR-004` has no task. The repair unit is “one missing task record for obligation `FR-004`,” not the entire task list. The new record is validated, graph-merged, globally ordered, and then assigned an engine task ID.

#### Dependency cycle

If `task-a -> task-b -> task-a`, the diagnostic includes the cycle and selects one proposed edge for semantic reconsideration. The repair response may replace/delete only that edge. IDs and other tasks remain unchanged.

#### Compiler failure

A compiler points to one declaration. The repair unit is that declaration/hunk in one authorized file. The engine discards the invalid operation savepoint, reapplies the repaired candidate to the same pre-operation snapshot, promotes it after local validation, then rebuilds and performs the full task check.

#### Scope expansion

A code repair requires an undeclared second file. This is not treated as a larger code repair. It is a task/plan scope defect and blocks implementation until the upstream artifact is corrected.

---

## 23. Rendering and editability strategy

The engine, not the LLM, renders persistent artifacts. `spec.md` is the only user-editable workflow artifact. Every other workflow file is a read-only review/progress view backed by canonical engine state. This removes repeated parsing and repair of mechanically known syntax and prevents display edits from changing execution.

Renderers own:

- fixed headings and section order;
- front matter/header fields;
- dates and engine-known links;
- `AC/FR/BR/EC` and `TNNN` identifiers;
- checkboxes and phase/gate status;
- Markdown table columns and escaping;
- code fences around structured contracts where applicable;
- repo-relative path formatting;
- deterministic ordering;
- exact preserved token values;
- completion summaries derived from state.

`spec.md` is reparsed and normalized at the plan boundary; its IR must pass the full specification gate. A user may edit semantic fields and add, remove, or reorder semantic records, but engine-owned headings, status/checklist fields, and existing ID syntax remain protected by validation. Surviving IDs stay attached to their records; an un-ID'd new record receives the next monotonic ID; deleted IDs are not reused. A duplicate, malformed, or reassigned ID blocks with targeted guidance. Formatting is normalized by deterministic rendering, and that normalized spec is staged with plan-input state so a crash cannot record a different planning input.

Reference citations are not rendered into the business-only file. On reparse, the engine joins the persisted specification-provenance ledger only when the requirement ID and normalized business content still equal the ledger entry. A changed or new record loses inherited provenance and must be re-attributed from the persisted `ReferenceSnapshot`, explicitly marked user-authored, or blocked when reference support is mandatory. If the spec is edited after downstream canonical state exists, the next gate compares the normalized specification IR with the exact specification input stored in canonical plan state. A difference invalidates plan/task approvals and requires regeneration from `specified`; this is direct typed-state comparison, not fingerprinting.

`reference-context.md`, `plan.md`, `research.md`, `data-model.md`, contract views, `quickstart.md`, and `tasks.md` are never parsed as authoritative execution input. The engine loads their canonical IR, renders the expected bytes, and checks the view for exact equality. A modified generated view produces `GENERATED_VIEW_MODIFIED`; the engine may regenerate the view from canonical state, but never imports the edit. Review feedback is submitted through the review API/CLI and targeted to IR units.

Golden tests ensure byte-stable output for the same canonical IR. Where supported, generated views may also be marked read-only at the filesystem level, but permissions are only a usability guard; canonical-state authority is the security/correctness boundary.

Because plan and task Markdown are projections, copying only those files does not preserve executable workflow state. Portability uses an explicit export/import bundle containing schema-versioned canonical reference/plan/task state, approvals when policy permits, and their views; the bundle contains no hashes. A repository may version-control `.sddtoolkit/features/<featureId>/` under an explicit policy. CI or a clone without canonical state may validate/display `spec.md`, but cannot execute plan/tasks from Markdown alone.

---

## 24. State, sequence, and recovery without fingerprints

### 24.1 Workflow state

The root orchestrator carries state in memory. For crash/restart support, a small state document may be stored beneath configured `paths.sddtoolkit`, for example `.sddtoolkit/state/<featureId>.json`:

[View the Workflow state sample](code.md#workflow-state).

It contains no content hashes or fingerprints. Preset IDs/versions and artifact paths are metadata, not freshness proofs.

### 24.2 Stage transition state machine

[View the Stage transition state machine sample](code.md#stage-transition-state-machine).

Each in-progress state can transition to `blocked`, `failed`, or `cancelled` with a resumable prior committed state. Generated canonical state is committed before entering its review-pending state. `planned` and `tasked` are entered only after approval tied to the exact current canonical state ID.

### 24.3 Gate behavior

State alone never authorizes a stage.

- The editable `spec.md` is reparsed and fully validated.
- When canonical plan state exists, the engine compares current normalized `SpecificationIR` directly with the stored plan-input `SpecificationIR`. A difference invalidates plan/task canonical state and approvals and returns the workflow to `specified`.
- Canonical reference, plan, task-definition, and task-runtime IR is loaded from engine state and revalidated directly.
- Read-only views are compared byte-for-byte with deterministic rendering from their canonical IR. A changed view is regenerated or blocks; it never changes execution state.
- The next stage requires an approval record whose `canonicalStateId` equals the current state.

No hashes or fingerprints are created. Direct typed-state/view comparison is possible because the workflow is ordered and the engine already owns canonical plan/task inputs. A future generalized out-of-band freshness system would be a separate design decision.

### 24.4 Recovery

On restart, recovery actions:

1. load state;
2. inspect every durable transaction journal before trusting workflow state;
3. roll back journals without a commit marker and idempotently roll forward journals with a commit marker, according to Section 25;
4. discard only candidates that never reached `PREPARED`;
5. load and schema-validate canonical reference/plan/task/runtime state;
6. reparse current editable `spec.md`, rejoin valid persisted provenance, and compare it with any plan-input specification state;
7. validate/regenerate read-only views from canonical state;
8. validate that review decisions target current canonical state IDs;
9. reconcile task leases from committed transaction/runtime state;
10. resume from the first pending/invalid node.

Recovery never infers completion solely from generated files or a model summary.

### 24.5 Upstream rework and invalidation

Backward movement is explicit and never inferred from a failed model call:

- A spec edit that differs from stored plan input invokes an authorized `spec_changed` transition to `specified`, invalidates canonical plan/task state and both approvals, and regenerates/removes their views transactionally.
- A tasking-time plan gap enters `plan_rework_required`, invalidates any unapproved task candidate, targets plan units through feedback/repair actions, and returns to `plan_review_pending` with a new plan state ID.
- An implementation-time task gap discovered before any task transaction commits enters `tasks_rework_required`, clears task approval, and returns to task generation/review.
- After one or more implementation task transactions have committed, upstream spec/plan/task change is blocked by default and requires explicit `implementation_reconciliation` authorization. Already committed project changes are preserved. Descendant approvals are invalidated, affected completed tasks become `needs_reconciliation` in engine runtime state, and a newly reviewed task graph must describe follow-up/reconciliation work. The engine never automatically deletes or rolls back accepted user/project code to satisfy a new upstream view.

Every rework transition commits invalidation state, affected canonical state, generated views, and review records in one stage transaction. A rejected review creates a new canonical state ID; an old approval can never authorize it.

---

## 25. Transaction and filesystem model

### 25.1 Artifact transactions

Specification output, canonical reference/plan/task/runtime state, approval/evidence records, generated views, and the next workflow-state document are built in memory and staged under an engine-controlled directory on the same filesystem when possible. A stage is not split into “artifact commit” and a later state write: both belong to one sealed `StageTransaction`.

Before commit the engine validates:

- exact intended path set;
- no unapproved overwrite;
- feature/workspace containment;
- editable-spec render/reparse equivalence and generated-view equality with canonical state;
- required artifact-set completeness.

Every multi-entry stage or task transaction uses this durable state machine:

`OPEN -> PREPARED -> APPLYING -> COMMITTED -> CLEANED`

1. `OPEN`: candidates exist only in staging and may be discarded.
2. `PREPARED`: the engine has sealed the exact entry set and revision, stored/fsynced the journal, before-images or creation tombstones, destination metadata, no-follow ancestor identities, and a single-use authorization. No destination has changed.
3. `APPLYING`: each deterministic entry is revalidated for target identity, applied using descriptor-relative/no-follow operations or a platform equivalent, and recorded/fsynced as applied. The workflow-state entry is ordered last among destinations but is still covered by the same journal.
4. `COMMITTED`: after every entry is durable, the adapter writes/fsyncs the commit marker last. Only this marker makes the logical transaction visible as successful.
5. `CLEANED`: staging and before-images are removed idempotently after commit; loss during cleanup cannot undo success.

Recovery rolls back applied entries in reverse order when no commit marker exists, using durable before-images/tombstones. With a commit marker it rolls forward/idempotently verifies every committed entry and then cleans. Applied-entry records make recovery safe after failure at any individual replacement. The adapter never decides business validity; it only executes a preauthorized sealed transaction.

### 25.2 Implementation overlays

Implementation uses an overlay or equivalent transaction abstraction, independent of Git. It may be implemented with a copy-on-write virtual filesystem, temporary worktree, filesystem snapshot, or before-image journal. The interface guarantee is:

- model-generated changes first affect only the overlay;
- validators and commands run against the overlay;
- a failed task can be discarded without changing committed project files;
- authorized task writes commit as one logical unit;
- unexpected changes block commit.

Each proposed file operation additionally uses a child overlay/savepoint. Invalid create/update/replace/copy/delete deltas are discarded before repair. Promoted operations are replayable in declared order from the clean task base, allowing a localized operation to be repaired without accumulating invalid patches or accepting temporary cross-file failures.

The sealed `TaskTransaction` contains project deltas, command/manual evidence, execution-journal changes, canonical `TaskRuntimeState`, the rendered tasks view, lease/lock changes, and any final workflow state. Its authorization is opaque, single-use, and bound to the sealed overlay revision. There is no moment when project code is committed but task completion state is outside the transaction.

No artifact fingerprint is needed for this transaction behavior. The engine controls sequential writes in the active run.

### 25.3 Failpoint and durability contract

Adapters must define which flush primitive makes a journal, file replacement, directory entry, and marker durable on each supported platform. Conformance tests inject a crash before and after every state transition, journal flush, before-image write, destination replacement, applied-entry record, workflow-state replacement, commit-marker write, and cleanup step. Every restart must yield exactly the pre-transaction or fully committed state—never a mixed state.

### 25.4 Non-transactional effects

Network calls, deployments, external database mutations, cloud operations, messages, and other externally irreversible effects cannot be rolled back by a workspace overlay. They are disabled by default. If a future task type supports them, it must declare an effect adapter, idempotency/compensation contract, policy, and explicit authorization outside this first implementation.

---

## 26. Security and safety

### 26.1 LLM trust boundary

Model and reference content are untrusted data:

- reference text is delimited and labeled as data, never concatenated into system instructions;
- instruction-like content in a reference cannot alter response schema, available tools, paths, or policy;
- the model has no filesystem or shell capability;
- model path/context requests use validated IDs;
- model-returned status, command, and validation assertions are ignored unless part of an allowed typed semantic payload;
- provider output is size-bounded and schema-validated.

### 26.2 Filesystem safety

- reject absolute, drive, UNC, URI, traversal, NUL, and control-character paths;
- use real-path containment and segment-aware root matching;
- reject symlink escapes for reads and writes, then repeat target/ancestor identity checks at commit with descriptor-relative/no-follow operations or the supported platform equivalent;
- deny VCS/engine/cache/generated roots by default;
- separate create/update/replace/copy/delete semantics and validate expected target state;
- require explicit delete policy and task authorization;
- never overwrite an existing feature or artifact implicitly;
- use transaction adapters for all writes.

### 26.3 Command safety

- no shell interpolation;
- no raw model commands;
- registered executable and argv templates only;
- typed placeholders only;
- contained working directory;
- environment-variable allowlist and secret redaction;
- time, output, concurrency, network, and mutability limits;
- validate command capability against actual project manifests;
- isolate dependency mutations;
- refuse externally irreversible operations by default.

### 26.4 Reference safety

- bounded per-file and total corpus size;
- MIME sniffing rather than extension trust alone;
- archive depth/file-count/compression-ratio limits if archive readers are enabled;
- encrypted/corrupt content diagnostics;
- sandboxed document/image parsers where feasible;
- no macro execution;
- no scripts embedded in reference content;
- deterministic hidden-file and symlink policy;
- explicit account for every discovered file.

### 26.5 Secrets and logging

The sample config enables prompt response logging (`new_engine/.sddtoolkit.json.example:8-12`), which could capture source code, references, credentials, or personal data. The new default is off. If enabled:

- secret detectors redact configured fields and common credential forms;
- raw reference/code bodies require separate opt-in;
- files use restrictive permissions;
- retention and rotation are mandatory;
- response truncation occurs after redaction;
- logs never contain environment-variable values unless explicitly allowlisted;
- telemetry contains IDs and diagnostic codes rather than content where possible.

---

## 27. Observability

Every node emits structured events:

[View the Observability events sample](code.md#observability-events).

Event fields include run/feature/stage/node IDs, attempt, duration, model route/profile, token usage, diagnostic codes, repair unit kind, command ID, exit code, and evidence status. Sensitive content is excluded or redacted.

Useful metrics:

- model calls and tokens by stage/unit;
- initial-pass and post-repair validation rate;
- repairs by diagnostic code and preset;
- average atomic repairs per accepted unit;
- schema-failure rate by model route;
- preset path rejection rate;
- command pass/failure duration;
- task throughput and blocked dependency count;
- transaction rollback count;
- unsupported reference formats.

The metrics distinguish deterministic rejection from semantic-review rejection. This is necessary to see whether failures come from model capability, poor initial guidance, preset errors, or repository problems.

---

## 28. Testing strategy

### 28.1 Action unit tests

Each action is tested with immutable fixtures and fake narrow ports. Required cases include:

- schema rejection of unknown keys, missing required fields, and unresolved `<!-- IMPLEMENT -->` placeholders;
- config path overlap and environment-root ambiguity;
- feature slug normalization, maximum length, empty transliteration, and collision;
- path traversal, absolute/drive/UNC paths, encoded separators, NUL/control characters, and symlink escape;
- segment-prefix traps such as `src2` matching `src` incorrectly;
- case-fold collisions;
- compound extensions such as `.test.tsx`;
- create versus update behavior for legacy filenames;
- co-located and mirrored test mappings;
- generated/forbidden path rejection;
- Java package/path and public-type/basename rules;
- .NET project ownership and test naming;
- command placeholder typing and metacharacters passed as literal argv;
- reference MIME mismatch, unsupported reader, corrupt file, and exact accounting;
- citation bounds and verbatim mismatch;
- requirement/task ID assignment and renderer escaping;
- coverage for requirements, guards, copy, states, and visual tokens;
- task unknown dependency, cycle, phase violation, read/write conflict, and exclusive command;
- patch scope, patch failure, unexpected file changes, and evidence predicates;
- create/update/replace/copy/delete expected-state rules and copy-source authorization;
- `red_then_green` intended-failure matching and required later green evidence;
- post-command declared, ephemeral, and undeclared delta handling;
- atomic commit/rollback failure paths.

### 28.2 Property-based tests

Generate large path/task/requirement spaces to prove invariants:

- normalized paths never escape the root;
- accepted create paths always match exactly one environment/project and pass their declared kind;
- task graphs accepted as DAGs remain acyclic after ID assignment;
- calculated parallel pairs never have declared write/write conflicts;
- editable-spec render then parse preserves normalized specification IR;
- every generated view equals deterministic rendering of canonical IR;
- atomic repair never changes immutable sibling pointers;
- stable inputs plus the same accepted model payload render identical bytes.

### 28.3 Orchestrator tests

Use spy child nodes; no real filesystem/model ports are available to the orchestrator.

- bootstrap failure prevents every model action;
- invalid reference preflight prevents artifact creation;
- stage order is always specify, plan, tasks, implement;
- predecessor revalidation occurs at every boundary;
- one invalid filename creates one repair request for one pointer;
- valid sibling units are retained across repairs;
- a repair outside scope is rejected;
- retry exhaustion returns blocked/failed, not success;
- stage commit occurs only after full validation;
- a failed task blocks dependents and cannot mark `[X]`;
- independent parallel failures aggregate correctly;
- task status persistence failure prevents completion;
- recovery discards uncommitted candidates and reconciles committed evidence.

Architecture tests also reject action fields/constructors typed as any node, dispatcher, node runner, executor callback, or service locator; reject node `execute` calls outside orchestrator modules; and enforce the orchestrator import allowlist. Orchestrators receive only child bindings and the capability-free `NodeRuntime`.

### 28.4 Model fault-injection tests

Stub routes deliberately return:

- malformed JSON;
- a wrong request/diagnostic ID;
- extra schema fields;
- a foreign absolute path;
- wrong React casing/extension;
- a misplaced unit test;
- a Java public class/file mismatch;
- a .NET file under no project;
- a hallucinated command;
- an unknown requirement ID;
- a missing coverage item;
- a task dependency cycle;
- two parallel tasks writing one manifest;
- a patch touching two files;
- an unbound filename hidden in a task/plan prose field;
- a copy operation with an unknown/raw-path source;
- a code repair outside the authorized target;
- a claim with a fabricated source citation;
- repeated identical invalid repairs.

Each test asserts that only the corresponding atomic repair unit is exposed and that invalid output never reaches a write/command action.

### 28.5 Preset conformance fixtures

Ship golden valid/invalid repositories for:

- React + TypeScript + Vite;
- Node JavaScript ESM;
- Node TypeScript;
- Java + Maven, including multi-module;
- Java + Gradle;
- .NET single project;
- .NET solution with application and test projects;
- monorepo containing more than one environment.

Tests verify schema validity, detection ambiguity, roots, extensions, naming, placement, generated exclusions, parser/query resources, command capability, and cross-platform argv.

### 28.6 Renderer and artifact tests

- golden `spec.md`, `reference-context.md`, plan artifacts, and `tasks.md`;
- Markdown escaping and code-fence safety;
- exact token/copy preservation;
- fixed heading order;
- correct engine-derived checklist/progress state;
- no `tasks.md` during plan;
- editable `spec.md` parse/render round trip and provenance rejoin/invalidation after edits;
- exact generated-view equality, tamper detection, and regeneration without importing edits.

### 28.7 End-to-end tests

In temporary repositories with a fake model gateway:

1. run a reference-free feature through all four stages;
2. run mixed Markdown/CSS/image/PDF references and verify full accounting;
3. inject an authoritative conflict and verify specification blocks;
4. force an invalid planned filename and verify atomic repair;
5. generate missing task coverage and repair only one task;
6. fail compilation, repair one code unit, and verify revalidation;
7. crash before/after transaction commit and verify recovery;
8. complete implementation and verify every `[X]` has evidence.
9. approve plan/tasks by canonical state ID, reject stale approvals, and exercise upstream rework invalidation;
10. inject crashes at every transaction failpoint and verify all-or-nothing project/state/evidence/view recovery.

---

## 29. Suggested package/module structure

This is logical and language-neutral:

[View the Suggested package structure sample](code.md#suggested-package-structure).

Domain modules have no infrastructure dependencies. The composition root is the only location that constructs concrete adapters and child-node graphs.

---

## 30. Delivery sequence for the new engine

### Increment 1: contracts and deterministic core

- Define config/preset/model-response schemas.
- Define IR, diagnostic, evidence, action, orchestrator, and state contracts.
- Implement config/preset compilation and path validation.
- Implement editable-spec render/parse round trips, generated-view equality, and durable artifact/state transactions.
- Provide fake ports and architecture tests.

### Increment 2: Specify

- Implement invocation/identity and reference preflight.
- Add the initial reader registry and citation system.
- Implement structured reference/spec model routes.
- Add specification/reference-context validators, atomic repair, rendering, and commit.

### Increment 3: Plan

- Implement repository/manifest discovery and environment facts.
- Implement plan IR and artifact applicability.
- Add path/coverage/token/quickstart validators.
- Render and commit planning artifacts.

### Increment 4: Tasks

- Implement obligation ledger and typed task proposal routes.
- Build DAG, path/command validation, coverage, ordering, and parallel calculation.
- Render `tasks.md` deterministically.

### Increment 5: Implement

- Implement operation savepoints, create/update/replace/copy operations, configured command runner, AST/import checks, evidence, sealed task commit, and recovery.
- Start with sequential task execution; enable validated concurrency only after overlay/lock tests pass.

### Increment 6: preset breadth and hardening

- Ship and test React/Node/Java/.NET compositions.
- Add remaining reference readers.
- Add crash/fault/security testing and telemetry.
- Generate human-facing prompt/reference documentation from the authoritative route/schema definitions to avoid duplicated prompt drift.

Each increment must be usable with a fake model gateway before integrating a real provider.

---

## 31. Acceptance criteria for the design implementation

The new engine is ready for production evaluation when all of the following are true:

1. The root workflow cannot execute `plan` before a valid committed specification, `tasks` before an approved current canonical plan, or `implement` before an approved current canonical task graph.
2. No LLM action has a filesystem, process, state, or unrestricted tool interface.
3. No orchestrator imports or directly uses infrastructure/domain-operation ports.
4. Every action and orchestrator implements the same typed `PipelineNode` interface; every action has isolated unit tests and every orchestrator has spy-child tests.
5. Fixed workflow artifact paths are engine-assigned.
6. Every path-like model field is structured, normalized, contained, classified, preset-validated, and authorized before use.
7. Every actionable project-file reference outside planning is a `fileId`, and unbound path-shaped prose is rejected.
8. React, Node, Maven/Gradle Java, and multi-project .NET fixtures have both accepted and rejected filename tests.
9. Every LLM route—including implementation and repair—conforms with a nano-class model and has a closed response schema and bounded guidance packet.
10. A one-field filename defect causes one one-field repair request; valid sibling output is preserved.
11. A repair cannot change a field outside its closed authorization and old-value/revision preconditions.
12. Every repaired candidate receives dependent and full validation before persistence.
13. Unsupported references are reported and cannot be silently omitted; every decoded block has a disposition.
14. Persisted reference citations, provenance, and exact preserved tokens are mechanically verifiable across restart.
15. `spec.md` is business-only according to deterministic lint and configured semantic review, while technical/reference data remains in the sidecar.
16. Plan file records match real repository environments and all obligations have coverage.
17. Task IDs, runtime status, checkboxes, dependencies, ordering, mandatory checks, and `[P]` are engine-derived.
18. The engine rejects dependency cycles and parallel write/resource conflicts.
19. Implementation uses operation savepoints and supports authorized create, update, replace, copy, and policy-gated delete without raw model paths.
20. Only preset/config command IDs execute, without a shell and within configured safety/effect limits; every mutating command receives a post-command delta gate.
21. A task is marked `[X]` only after one durable transaction commits project delta, evidence, canonical task state, rendered view, and lock state.
22. Failed and blocked executions cannot be reported as completed.
23. Stage state and recovery work without storing or comparing artifact fingerprints.
24. Editable `spec.md` round-trips to its IR; generated views exactly match canonical rendering and are never parsed as authority.
25. Prompt/response logging is off by default and safe when explicitly enabled.
26. End-to-end fake-model tests cover valid flow, approvals, malformed output, atomic repair, retry exhaustion, copy/replace, compiler/test repair, upstream rework, transaction failpoints, and final evidence.

---

## 32. Deferred implementation choices

These choices do not alter the architecture and may be decided during implementation:

- implementation language/runtime for the engine;
- concrete JSON Schema, Markdown AST, tree-sitter/compiler, PDF, office, image/OCR, and overlay libraries;
- whether explicit feature-ID collision handling is always “fail” or can offer a user-selected suffix mode;
- the UI/API used to record manual verification evidence;
- which binary reference readers ship in the first release versus plugins;
- the first platform-specific multi-file transaction adapter;
- when concurrency above one becomes enabled by default;
- whether model-assisted semantic warnings block by default in development versus CI.

They must not weaken the invariants, path policy, command safety, repair scoping, evidence requirements, or action/orchestrator separation defined above.

---

## 33. Prompt-to-engine migration matrix

This matrix assigns every material responsibility in the existing four prompts to an engine component. “Repair” always means the closed protocol in Section 22; engine/user/environment failures do not consume model repair attempts.

### 33.1 Specify prompt

| Current prompt responsibility | Deterministic action/orchestrator owner | LLM route | Validation and repair unit | Side effect and gate |
|---|---|---|---|---|
| Parse description and flags | Invocation actions in `SpecifyPreflightOrchestrator` | None | Argument schema; user-input diagnostic | None before valid input |
| Choose feature identity/directory | `DeriveFeatureIdentityAction`, artifact-path action | Optional title route only | Versioned slug/length/collision; no model repair | Reserve stage transaction |
| Resolve optional reference folder | Reference-root/inventory actions | None | Containment, type, symlink, size; user/environment repair | No feature output before complete preflight |
| Read arbitrary reference formats | Per-file reader orchestration and decode actions | Vision interpretation uses normal model chain only | Reader threshold/tie, decode status, block ledger | Stage canonical reference candidates only |
| Extract requirements/signals/tokens | Structured-fact actions plus chunk generation | `reference.extract` per block/chunk | Closed claims, citations, exact values; one claim/citation repair | In-memory snapshot candidate |
| Reconcile all reference content | Hierarchical reconciliation orchestration | `reference.reconcile` over compact claim payloads | Known IDs, claim dispositions, conflict records | Block unresolved authoritative conflict |
| Draft business specification | Validated generation per spec unit | `spec.section.generate` | Spec schema, citations, business-only lint; one field/record | In-memory `SpecificationIR` |
| Separate technical/reference detail | Reference-context generation/render actions | Bounded classification/generation routes | Typed sidecar sections and token/source coverage | Read-only view candidate |
| Assign IDs/headings/checklists/status | ID and renderer actions | None | Renderer/IR equality | Engine-rendered `spec.md` |
| Write outputs and announce readiness | Stage transaction orchestration | None | Full artifact/reference/state set | Durable marker enters `specified` |

### 33.2 Plan prompt

| Current prompt responsibility | Deterministic action/orchestrator owner | LLM route | Validation and repair unit | Side effect and gate |
|---|---|---|---|---|
| Select feature and check spec readiness | `StageGateOrchestrator` and spec parser/validators | None | Explicit feature ID, current spec, provenance/conflicts | No writes before gate |
| Load project principles | Standards source/parse/index/compile actions | None for mechanical rules; semantic review may reason over indexed prose | Typed-block schema/conflict; environment/user repair | Immutable standards selection |
| Inspect repository/tooling | Manifest/project/command/parser actions | None | Real project/fact/capability evidence | Immutable repository fact registry |
| Resolve research unknowns | Evidence selection actions | `plan.section.generate` per decision | Required evidence IDs; unresolved external evidence blocks | Canonical research decision candidate |
| Propose dependency | Package/source policy actions | Bounded plan route | One typed proposal; approval required | No install; later setup task only after approval |
| Choose minimal implementation shape | Context/guidance and plan generation | `plan.section.generate` per unit | Structure and typed-fact checks; rationale semantic review | In-memory `PlanIR` |
| Propose touched/new filenames | Planning path validation orchestration | One `ProjectPathCandidate` at a time | One path field; full preset-derived atomic guidance | Accepted `FileRecord`/`fileId`, no project write |
| Decide artifact applicability | Artifact-decision validation actions | Plan unit route | One decision/section | Canonical artifact manifest |
| Produce research/model/contracts/quickstart | Render actions over validated plan IR | Bounded artifact-section routes | Registered schema, fact IDs, scenario structure, coverage | Read-only view candidates |
| Check constitution and coverage | Mechanical standards/ledger actions plus optional semantic review | `semantic.review` only for judgment | One typed rule/coverage entry or model-assisted finding | Blocking validation authorization |
| Persist and validate plan | Stage transaction orchestration | None | Canonical IR, input spec IR, views, next state | Durable `plan_review_pending` |
| User validates plan | `UserReviewOrchestrator` and review actions | Targeted regeneration/repair only after rejection | Approval exact state ID; feedback unit | Approval enters `planned`; views remain read-only |

### 33.3 Tasks prompt

| Current prompt responsibility | Deterministic action/orchestrator owner | LLM route | Validation and repair unit | Side effect and gate |
|---|---|---|---|---|
| Load plan/design inputs | Stage gate and canonical-state readers | None | Current plan approval, spec-input equality, view equality | No writes before gate |
| Build complete work obligations | Requirement/obligation ledger actions | None | Known IDs, coverage rule completeness | Immutable ledger |
| Decompose work | Validated generation per obligation cluster | `tasks.cluster.generate` | One task definition/field | In-memory definitions; no runtime status |
| Select files/commands/scenarios | File registry and evidence-policy actions | Model selects known file IDs/scenarios and optional checks only | Plan authorization, preset path, command registry | Canonical task candidate |
| Reconcile semantic dependencies | Compact global-index orchestration | `tasks.dependencies.reconcile` | One edge; known targets/phase rule | Validated edge candidates |
| Build DAG/order/IDs | Graph/cycle/phase/topology/ID actions | None | Unknown edge, cycle edge, phase edge | Engine assigns `TNNN` |
| Establish TDD/manual verification | Phase-kind/evidence actions | Model proposes intent/mode | One mode/predicate; intended-red and later-green binding | Canonical evidence requirements |
| Calculate parallel markers | Runnable/conflict/lock actions | None | Graph/path/resource/command policy | Engine-derived `[P]` only |
| Prove complete coverage | Traceability actions | Missing task route for one obligation if model-repairable | One coverage entry/task insertion | Full graph authorization |
| Render/persist tasks | Renderer and stage transaction actions | None | Canonical graph/runtime/view equality | Durable `tasks_review_pending` |
| User validates tasks | User-review actions | Targeted unit repair/regeneration after rejection | Approval exact state ID | Approval enters `tasked` |

### 33.4 Implement prompt

| Current prompt responsibility | Deterministic action/orchestrator owner | LLM route | Validation and repair unit | Side effect and gate |
|---|---|---|---|---|
| Check readiness/current inputs | Stage gate and canonical-state readers | None | Current task approval, editable-spec equality, view equality, environment capability | No execution before gate |
| Select next work and parallelism | Runnable-set/select/lease actions under scheduler | None | Dependency/runtime/lock compare-and-swap | Atomic task lease |
| Gather task context | Context selection/read actions | None | Only authorized file/content handles and relevant facts | Bounded immutable context |
| Plan operations | Change-planning generation orchestration | `implementation.operation.generate` | Authorized operation type and plan-assigned IDs | In-memory ordered intents |
| Create new code | Operation savepoint actions | Nano code route | One complete file in one savepoint | Overlay only |
| Patch existing code | Operation savepoint actions | Nano code route | One patch/hunk in one `fileId` | Overlay only |
| Replace an existing file | Operation savepoint actions | Nano code route | One complete replacement plus expected target state | Overlay only |
| Copy code/file content in | Copy-source resolution/validation and operation actions | None for byte copy; separate nano update route for adaptation | One source ID/destination ID; provenance/media/permission | Overlay only |
| Delete a file | Operation/policy actions | Justification may be model content | One plan/task-authorized delete; disabled by default | Overlay only |
| Repair filename | Planning repair flow, never implementation | `repair.structured` in plan | One planning path candidate | Requires upstream reviewed plan/task state |
| Repair code/tool failure | Atomic repair orchestration over discarded savepoint | `repair.code` | One authorized hunk/declaration/file/group with revision preconditions | Rebuilt overlay only |
| Run syntax/import/build/lint/test | Local validators then derived command actions | None | Executable evidence; diagnostic-local repair where allowed | Command effects remain in overlay and are diff-gated |
| Record manual evidence | Manual-evidence action/API | None | Exact configured scenario/observer record | Evidence candidate |
| Mark task complete | Build state/render/seal/transaction actions | None | All evidence and final delta; model status ignored | One durable project/evidence/state/view/lock marker |
| Handle failure/dependencies | Scheduling and state actions | None | Typed failed/blocked outcome | Dependents blocked; independent leases governed by policy |
| Run final validation | Final-validation orchestration and derived commands | None | Full evidence, final post-command delta, all tasks complete | Durable `implemented` transition |

---

## 34. Final design position

The current workflow has the correct high-level shape but gives the model too much operational authority. The new engine should preserve the semantic progression and artifact intent while reversing that authority:

- The engine supplies facts and constraints before generation.
- The LLM returns one small typed semantic or code unit.
- The engine validates every mechanically decidable property.
- The engine gives precise preset-derived guidance for exactly one failed unit.
- The LLM repairs only that unit.
- The engine renders, writes, runs, verifies, and advances state.

This is the appropriate deterministic layer for lower-capability models: it does not ask a nano model to behave like a reliable workflow engine, and it does not attempt to replace the model where interpretation and synthesis are genuinely required.
