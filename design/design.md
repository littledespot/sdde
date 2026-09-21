# Deterministic SDDE Workflow Engine

## Generic workflow runtime and the initial `specify -> plan -> tasks -> implement` suite

**Status:** Proposed design

**Authority:** This is the proposed implementation baseline. The
[decision index in §32](#32-accepted-and-deferred-implementation-choices) records
accepted amendments without accepting the remainder of the design. Current
implementation and known gaps are tracked in the [feature contracts](features/)
and [FIX_001 rollout](../fixes/IMP_001.md); design requirements are not
claims that the engine already satisfies them.

**22 September corrective design:** [§12.8.1](contracts/12-model-boundary.md#1281-clarification-admission-and-candidate-failure-precedence)
owns clarification admission and candidate-failure precedence;
[FIX_002](../fixes/FIX_002.md) tracks implementation and semantic validation still
required. This documentation amendment neither implements the gate nor authorizes
the separately proposed verdict reassessment. The overall design remains Proposed.

**Reading this design:** Sections 1, 3, 4, 30–32 retain the overview, invariants,
responsibility boundary, delivery sequence and acceptance criteria. Other sections
link to focused contracts below. Those contracts are part of this same proposed
baseline; moving them does not change their authority or accept a proposal.
Original section links remain available in the reading map.

**Execution:** ADR 0009 makes one whole workflow the computation/validation unit.
A new invocation starts at `start`; there is no transaction, checkpoint or
saved-execution recovery subsystem. Publication failure may leave replaced
files but cannot record new successful completion (§25). Reruns replace registered
outputs and unresolved forms, retaining clarification identities/applicable
answers and protecting user-closed form bytes (§23.2).

**Recent approved guidance:** FIX_001 A1–A3 amend §§12.5, 17.3 and 22.6. The
[approval record](../fixes/IMP_001.md#5-design-amendment-decisions)
preserves the decision scope; subsequent defect reviews do not grant new authority.

[ADR 0015](decisions/0015-specification-principle-review.md) adds early Spec
requirement–principle assessment and shared actionable-question preparation.
Native capture/assessment is implemented; actionable-question preparation and full
readiness remain tracked in FIX_001. Business and policy ownership stay separate.

[ADR 0016](decisions/0016-configured-json-response-composition.md) records the
user-directed generic JSON response decomposition and deterministic assembly design.
Shapes and partitions are workflow configuration; assembly needs no LLM prompt.
The configured compiler, runner integration and initial extraction split are
implemented. The finite graph ceiling is 1,024. The separately approved §12.7
amendment derives persisted comparison evidence from existing compiled bindings;
current registry authority governs readback. The approved §§12.7/22.6 amendment
permits bounded missing-final-answer correction through existing retry owners.
Measured live improvement remains outstanding.

**Scope:** Engine development in this repository. `init`, `drift`, `audit`,
version-control integration and artifact fingerprinting remain outside the
initial suite. A future explicitly selected `init` may materialize principle
templates only under its separately accepted contract.

**Source material:** [paths](paths.md), [schemas](schemas/),
[configuration examples](examples/), [legacy preset examples](toolchainPresets/)
and [principle templates](templates/). They are not runtime fallback data.
The [preset authoring guide](toolchainPresets/README.md) distinguishes the source
examples from current runtime inputs.
References below to predecessor `prompts/`, `.specify/`, `docs/` and old README
line ranges describe historical toolkit inputs outside this checkout; they
are not current-source links or execution authorization.

---

## 1. Executive summary

[ADR 0013](decisions/0013-workflow-input-reuse.md) amends workflow authoring
and model-input representation with compiler-expanded local subgraphs, local
schema reuse, compact schema transport and typed result/evidence projections.
Its accepted amendment preserves the validation and authority boundaries below.

- The new engine must treat an LLM as an untrusted semantic content generator, not as the
  workflow runtime.
- The LLM must not choose the workflow sequence, perform filesystem operations, run arbitrary
  tools, declare its own output valid, or mark work complete.
- It receives a small typed assignment, preset-derived guidance, the relevant evidence, and an
  exact response schema.
- It returns a candidate.
- The engine parses, validates, repairs, renders, persists, and verifies that candidate.

The design has eight defining properties:

1. **Generic workflow execution:** the engine loads an arbitrary bounded set of
   declarative workflow definitions from `paths.workflows`, compiles only graphs
   composed from registered generic operation contracts, and executes a
   selected validated graph through the common runner. Every workflow operation
   is addressable from concise YAML; the engine contains no hidden workflow
   graph or built-in model-route catalogue.
2. **Ordered SDD suite:** one feature flows through `specify`, `plan`, `tasks`,
   and `implement` in that order. Each of those workflows revalidates its
   predecessor before it starts; unrelated workflows do not inherit this order.
3. **Deterministic shell around probabilistic work:** argument parsing, feature identity, paths, filenames, artifact structure, identifiers, traceability, dependency graphs, writes, commands, task state, and stage gates are engine-owned.
4. **Preset-controlled project operations:** every model-proposed project path is classified and checked against the selected development-environment preset, such as React, Node, Java, or .NET, before it can be recorded in a plan, emitted as a task, or written during implementation.
5. **Atomic repair:** a failed candidate is repaired at the smallest independently replaceable field, record, section, task, path, or code operation. Unrelated valid output is retained. The repaired candidate is never committed until all applicable validators pass.
6. **Actions and orchestrators:** actions have one responsibility and a common typed contract. They do not coordinate other components. Orchestrators contain actions and/or other orchestrators, but perform no filesystem, LLM, parsing, validation, rendering, or command work themselves.
7. **Closed authority reconciliation:** every datum or decision required by a workflow contract resolves to exactly one current supported authority, an explicitly authorized `not_applicable`/exception outcome, or a clarification owned by the earliest responsible stage. Missing, ambiguous, conflicting, multiple, stale, or unsupported authority never becomes a warning, default, approximation, or downstream local fix.
8. **Native Zig distribution:** the engine is implemented in Zig and packaged as a native executable. It has no Node.js runtime or Node SEA dependency; JavaScript/TypeScript and Node remain target-project technologies governed through presets.

The resulting boundary is:

- **Workflow YAML owns:** the selected declarative operation graph, operation
  parameters, workflow resources, model slots, and every outcome transition.
- **The engine owns:** closed operation contracts, graph compilation and
  enforcement, policy, facts, identifiers, paths, artifact locations,
  rendering, side effects, validation, hard ceilings, diagnostics, and
  completion evidence.
- **The LLM owns:** understanding arbitrary reference material, extracting intent, writing business-facing requirements, making justified design choices, decomposing work, and generating or repairing code.
- **Executable evidence owns:** syntax, build, lint, test, and other preset-defined checks. An LLM assertion never substitutes for executable evidence.

---

## 2. Existing workflow used as the design basis

The predecessor toolkit supplies the behavioral basis. Historical observations, source
references, and normative resolutions are retained in the linked sections.

[Complete §2 contract](contracts/02-workflow-basis.md).

- <a id="21-behavior-to-preserve"></a>[2.1 Behavior to preserve](contracts/02-workflow-basis.md#21-behavior-to-preserve)
- <a id="22-why-a-new-engine-is-needed"></a>[2.2 Why a new engine is needed](contracts/02-workflow-basis.md#22-why-a-new-engine-is-needed)
- <a id="23-normative-resolutions-for-the-new-engine"></a>[2.3 Normative resolutions for the new engine](contracts/02-workflow-basis.md#23-normative-resolutions-for-the-new-engine)

---

## 3. Goals, non-goals, and invariants

### 3.1 Goals

- Make every mechanically decidable part of workflow loading, compilation,
  execution, and the initial four-workflow SDD suite host-enforced.
- Allow a project to add a workflow composed from existing registered operation,
  invocation, policy, and state contracts without rebuilding the engine.
- Keep workflow YAML concise while making every workflow operation, resource,
  parameter, and outcome transition explicit and configurable.
- Give nano-class models concrete, bounded assignments instead of large agentic prompts.
- Validate every model-proposed filename and path against a project/environment preset.
- Repair invalid model output without regenerating valid unrelated work.
- Preserve traceability from source material through requirements, planning, tasks, code changes, and verification evidence.
- Make every action independently testable with fake ports and immutable inputs.
- Keep workflow orchestration composable without allowing domain work to leak into orchestrators.
- Support one or more development environments in a repository, including monorepos.
- Make failure explicit, stable, diagnosable, and safe to retry.
- Keep the specification editable while making plan/task outputs review-only projections with explicit approval gates.
- Make authority completeness a cross-stage, fail-closed property so no workflow can compensate locally for missing or unreconciled upstream decisions.
- Ship the engine as a native Zig executable whose production behavior does not depend on the source tree, Zig toolchain, build cache, Node.js, or development-only assets.

### 3.2 Non-goals

- Making LLM output mathematically deterministic.
- Replacing semantic judgment with brittle keyword rules.
- Guaranteeing support for every possible binary reference format without an installed reader.
- Automatically resolving contradictory authoritative requirements.
- Integrating with version-control branching or lifecycle workflows.
- Implementing `audit`, `drift`, or `init` in the first implementation; the only reserved init contract is that an explicitly selected future `sdde init` workflow may copy `*.template.md` inputs from `paths.templates` into `paths.principles`.
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
10. Task completion is an engine-validated candidate fact published only with successful completion of the whole workflow and its required evidence. No task commits independently; the model cannot request `[X]` directly.
11. Unsupported or unreadable reference files are never silently skipped.
12. Persistent artifact paths are repository-relative and normalized.
13. Model-supplied commands are never executed. Only named, preset/config-defined commands can run.
14. Identifiers, checkboxes, Markdown headings, and status text are rendered by the engine wherever possible.
15. The same normalized engine input and the same accepted structured model payload produce byte-stable rendered artifacts.
16. Only `spec.md` accepts free user edits as a stage artifact. A registered clarification form accepts edits only in its declared status/answer regions; generated plan/task/reference views are never parsed as authoritative state.
17. Implementation cannot begin until the user has approved the current plan and current task graph.
18. Every actionable project-file reference in model output is a typed `fileId` or a planning-stage `ProjectPathCandidate`; path-shaped tokens in free-text fields are invalid.
19. Every datum or decision marked required by a closed schema, obligation, policy, or accepted authority has exactly one current supported resolution before its owning stage can commit.
20. Zero resolutions, multiple non-equivalent resolutions, semantic ambiguity, conflict, staleness, or unsupported authority produces a typed clarification, explicit upstream rework, or administrative block; it never selects a default, approximation, nearest match, warning-only continuation, or caller-local exception.
21. Clarification ownership is derived from a compiler-locked requirement-kind/decision-slot registry. A model, prompt, caller, principle, preset, or configuration value cannot choose a more convenient stage.
22. A downstream stage never answers an upstream gap. It invalidates affected descendants and returns to the earliest owning stage; implementation may repair code only when all governing upstream decisions are already resolved and the repair remains inside its authorization.
23. Domain-specific extractors and resolvers may contribute typed candidates and evidence, but all domains use the same reconciliation outcomes, ownership routing, clarification lifecycle, stage gates, and negative-test contract. No example, fixture, format, token kind, filename, framework, or caller receives a bypass or special continuation rule.
24. A project workflow definition is closed declarative data, never executable
    code or an operational capability.
25. The workflow compiler accepts only YAML-referenced contracts from the
    single registered generic operation registry,
    closed parameters and outcomes, valid transitions, and capabilities already
    permitted by the selected workflow policy.
26. The capability-free workflow-engine orchestrator follows only the immutable
    compiled graph selected by an exactly resolved `WorkflowId`; it contains no
    workflow-specific branching and cannot bypass runner invocation or delta
    validation.
27. The composition root assembles one fixed engine-startup graph so workflow
    definitions can be loaded and compiled, plus the fixed capability-free
    `ModelProviderBootstrapOrchestrator` that conditionally prepares provider
    authority after exact workflow selection. Neither mechanism is
    project-authored, registered as a runnable workflow, or extensible through
    `paths.workflows`; the workflow compiler remains the sole constructor of
    project-workflow graph descriptors.
28. Every non-kernel workflow operation is referenceable from workflow YAML
    through the one registered generic operation registry; an unregistered or
    source-only non-kernel operation is prohibited. Only the engine-kernel
    responsibilities named by ADR 0005 remain non-callable. The engine contains
    no built-in model routes, workflow-name branches, or inaccessible domain
    sequence that competes with the compiled YAML graph.
29. Workflow YAML uses compact mappings, native scalar parameters, and reusable
    workflow-owned resource aliases. Large prompts and schemas are declared
    once and referenced; they are never hidden packaged defaults or repeatedly
    copied into nodes.
30. The whole workflow is validated before publication. [ADR 0017](decisions/0017-incomplete-specification-publication.md) permits a separately validated incomplete specification with clarification publication, never completion authority. Other non-success abandons unpublished candidates; a new execution starts at `start`. Publication failure may leave already-replaced files but never records new successful completion (Section 25). No transaction, durable checkpoint or provider-recovery subsystem may be introduced.
31. Clarification persistence and rerun replacement:
    - Clarification records and answers survive output replacement and abandoned executions.
    - One stable target/owner/subject/slot has one clarification ID. A new execution, authority
      revision, question wording, or gap reason cannot mint a duplicate.
    - Relevant validated answers are input to each rerun.
    - User-closed clarification files are retained unchanged, not regenerated or automatically
      reopened.
    - Every workflow rerun completely overwrites its registered replaceable outputs and
      unresolved clarification forms at the same paths. Form replacement retains the subject
      ID, not the old form bytes.
    - Section 23.2 owns rerun replacement and protection.
32. Provider APIs own model-call size limits. SDDE adds no request/response
    byte or per-call token ceilings, including renamed transport/memory budgets.
    It records and propagates provider failures/stops and accounts actual input
    plus output tokens against only the execution's total-token budget. Calls
    at or above that budget are prohibited; retries remain explicitly local.

- Runner rejections retain their closed diagnostics through the top-level workflow result rather
  than selecting YAML outcome edges.
- `invoke-model` accounts actual usage before response publication, cancellation or deadline
  rejection; budget overshoots retain their full usage and exact error.
- Response decoding and lifecycle terminalization remain explicitly selected operations.

---

## 4. Deterministic and LLM responsibility boundary

Deterministic checks should be used wherever the answer can be computed from configuration, schemas, files, parsers, graphs, or command exit status. Semantic classification remains with the LLM. The engine must not disguise model-assisted review as deterministic validation.

| Area | Engine-deterministic | LLM-owned | Limit or escalation |
| --- | --- | --- | --- |
| Command input | Parse flags, defaults, enums, duplicates, required arguments | None | Invalid user input is non-repairable by the model. |
| Feature directory and brief | Validate the supplied directory, containment, no-follow safety and exact output paths; validate brief schema/citations | Derive human title, description and goal from reconciled references | The directory identifies the feature; no model-derived name or ownership registry. |
| Reference discovery | Root containment, traversal, symlinks, inventory, ordering, readability, size, decoder availability | None | Unsupported inputs block or require an installed reader according to policy. |
| Reference understanding | Source span validity, exact token preservation for structured formats, coverage ledger | Extract requirements, classify signals, recognize semantic conflicts | The engine can prove a citation exists; it cannot prove every semantic implication was found. |
| Business/technical split | Obvious lint such as forbidden absolute paths, code fences, known source extensions, known framework identifiers | Decide whether nuanced content belongs in business spec or technical context | Borderline findings are model-assisted warnings or human review, not false “proof.” |
| Spec structure | Required fields, IDs, uniqueness, status, placeholders, citation schema, required sidecar | Stories, acceptance criteria, business rules, assumptions, non-goals | Testability and ambiguity are semantic reviews unless reducible to a schema rule. |
| Repository facts | File inventory, manifests, installed dependencies, scripts, source/test roots, AST parse, tool availability | Interpret which existing areas are relevant to the feature | A model may select among real facts but may not invent facts. |
| Plan structure | Artifact manifest, canonical paths, applicability, required sections, requirement coverage, allowed commands | Architecture, trade-offs, research rationale, minimal change choice, verification strategy, principle interpretation | Principle conflicts requiring judgment remain LLM/human decisions. |
| Planned filenames | Authorize the exact project/kind/role option; derive locations and filename shape; enumerate, validate, and identify candidates; validate the selected candidate | Select an allowed semantic name source and then one engine-enumerated `pathCandidateId` | Raw filename/path proposal is disabled by default; fallback-only invalid paths receive preset-specific atomic repair guidance. |
| Task graph | IDs, phase enum, references, coverage, DAG, dependency existence, write-set collisions, safe `[P]` calculation | Decompose work, descriptions, non-obvious dependencies, read/write intent | Engine may remove unsafe parallelism; it never invents missing semantic dependencies silently. |
| Code changes | Allowed operation/path, patch applicability, declared scope, syntax, AST rules, import resolution, build/lint/test results | Generate code and repair semantic/compile/test failures | Behavioral correctness is only deterministic where an executable assertion exists. |
| Completion | Evidence requirements, complete workflow output, task status, stage status | Summarize completed work | Model claims have no effect on state. |
| Required-authority reconciliation | Build the required-slot ledger, validate candidate authority identity/currentness/cardinality, derive the earliest owner, and gate every stage | Classify semantic support/equivalence only within supplied candidates and citations when deterministic comparison cannot decide | Zero/multiple/ambiguous/conflicting/stale/unsupported results pause, rework, or block; no local default or approximation exists. |

The operating rules are:

- **if a validator can answer from typed data or executable evidence, do not ask the LLM to answer it;** and
- **if current authority cannot support exactly one required answer, do not generate or repair a plausible answer—route the typed gap to its earliest owner.**

---

## 5. Logical architecture

Interface adapters, orchestration, actions, domain contracts, and infrastructure have separate
responsibilities. Dependency direction keeps operational capabilities out of domain code and
orchestrators.

[Complete §5 contract](contracts/05-architecture.md).

- <a id="51-layers"></a>[5.1 Layers](contracts/05-architecture.md#51-layers)
- <a id="52-dependency-direction"></a>[5.2 Dependency direction](contracts/05-architecture.md#52-dependency-direction)

---

## 6. Common action and orchestrator contract

Actions and orchestrators share one typed pipeline contract. The runner owns execution and
validated deltas; declared data dependencies and barriers govern composition.

[Complete §6 contract](contracts/06-pipeline-nodes.md).

- <a id="61-action-rules"></a>[6.1 Action rules](contracts/06-pipeline-nodes.md#61-action-rules)
- <a id="62-orchestrator-rules"></a>[6.2 Orchestrator rules](contracts/06-pipeline-nodes.md#62-orchestrator-rules)
- <a id="63-reordering-and-composition-rules"></a>[6.3 Reordering and composition rules](contracts/06-pipeline-nodes.md#63-reordering-and-composition-rules)

---

## 7. Core domain representations

Typed intermediate representations hold canonical data. Markdown presents validated state;
identity, provenance, and immutable ownership are explicit contracts.

[Complete §7 contract](contracts/07-domain-representations.md).

- <a id="71-shared-types"></a>[7.1 Shared types](contracts/07-domain-representations.md#71-shared-types)
- <a id="72-stage-irs"></a>[7.2 Stage IRs](contracts/07-domain-representations.md#72-stage-irs)
  - <a id="specification-ir"></a>[Specification IR](contracts/07-domain-representations.md#specification-ir)
  - <a id="reference-context-ir"></a>[Reference-context IR](contracts/07-domain-representations.md#reference-context-ir)
  - <a id="plan-ir"></a>[Plan IR](contracts/07-domain-representations.md#plan-ir)
  - <a id="task-ir"></a>[Task IR](contracts/07-domain-representations.md#task-ir)
  - <a id="implementation-ir"></a>[Implementation IR](contracts/07-domain-representations.md#implementation-ir)
- <a id="73-canonical-state-and-model-request-identity"></a>[7.3 Canonical state and model-request identity](contracts/07-domain-representations.md#73-canonical-state-and-model-request-identity)

---

## 8. Diagnostics and evidence

Diagnostics distinguish rejection, repairable candidates, missing authority, and operational
failure. Evidence records what each validator or command actually established.

[Complete §8 contract](contracts/08-diagnostics-evidence.md).

---

## 9. Engine configuration

The invocation root supplies the exact closed configuration. Configuration strings become
authority only through the owning validators; principles and mechanical toolchain policy have
separate consumers.

[Complete §9 contract](contracts/09-configuration.md).

- <a id="91-required-configuration-shape"></a>[9.1 Required configuration shape](contracts/09-configuration.md#91-required-configuration-shape)
- <a id="92-configuration-validation"></a>[9.2 Configuration validation](contracts/09-configuration.md#92-configuration-validation)
- <a id="93-precedence"></a>[9.3 Precedence](contracts/09-configuration.md#93-precedence)
- <a id="94-project-principle-resolution"></a>[9.4 Project-principle resolution](contracts/09-configuration.md#94-project-principle-resolution)
- <a id="95-configuration-evolution"></a>[9.5 Configuration evolution](contracts/09-configuration.md#95-configuration-evolution)

---

## 10. Development-environment presets

Preset composition supplies target-project file, command, discovery, and parser policy. The
composed result must pass safety validation before use.

[Complete §10 contract](contracts/10-toolchain-presets.md).

- <a id="101-preset-identity-and-composition"></a>[10.1 Preset identity and composition](contracts/10-toolchain-presets.md#101-preset-identity-and-composition)
- <a id="102-project-discovery"></a>[10.2 Project discovery](contracts/10-toolchain-presets.md#102-project-discovery)
- <a id="103-file-kind-policies"></a>[10.3 File-kind policies](contracts/10-toolchain-presets.md#103-file-kind-policies)
- <a id="104-structured-commands"></a>[10.4 Structured commands](contracts/10-toolchain-presets.md#104-structured-commands)
- <a id="105-ast-and-parser-policy"></a>[10.5 AST and parser policy](contracts/10-toolchain-presets.md#105-ast-and-parser-policy)
- <a id="106-generated-and-forbidden-paths"></a>[10.6 Generated and forbidden paths](contracts/10-toolchain-presets.md#106-generated-and-forbidden-paths)
- <a id="107-environment-specific-expectations"></a>[10.7 Environment-specific expectations](contracts/10-toolchain-presets.md#107-environment-specific-expectations)
  - <a id="react"></a>[React](contracts/10-toolchain-presets.md#react)
  - <a id="node"></a>[Node](contracts/10-toolchain-presets.md#node)
  - <a id="java"></a>[Java](contracts/10-toolchain-presets.md#java)
  - <a id="net"></a>[.NET](contracts/10-toolchain-presets.md#net)
- <a id="108-normative-matching-and-platform-semantics"></a>[10.8 Normative matching and platform semantics](contracts/10-toolchain-presets.md#108-normative-matching-and-platform-semantics)
- <a id="109-legacy-preset-source-material"></a>[10.9 Legacy preset source material](contracts/10-toolchain-presets.md#109-legacy-preset-source-material)

---

## 11. Filename and path validation algorithm

Every actionable project path must resolve to one permitted project, environment, file kind, and
operation. Planning selects validated identities; later stages consume approved file IDs.

[Complete §11 contract](contracts/11-path-validation.md).

- <a id="111-cross-stage-filename-write-gate"></a>[11.1 Cross-stage filename write gate](contracts/11-path-validation.md#111-cross-stage-filename-write-gate)

---

## 12. LLM interaction boundary

Model assignments contain typed data, evidence, guidance, and a closed result schema. Explicit
workflow operations own preparation, invocation, decoding, review, and repair under the shared
authority boundary.

[Complete §12 contract](contracts/12-model-boundary.md).

- <a id="121-discrete-llm-components"></a>[12.1 Discrete LLM components](contracts/12-model-boundary.md#121-discrete-llm-components)
- <a id="122-initial-guidance-packet"></a>[12.2 Initial guidance packet](contracts/12-model-boundary.md#122-initial-guidance-packet)
- <a id="123-provider-neutral-response-envelope"></a>[12.3 Provider-neutral response envelope](contracts/12-model-boundary.md#123-provider-neutral-response-envelope)
- <a id="124-context-requests"></a>[12.4 Context requests](contracts/12-model-boundary.md#124-context-requests)
- <a id="125-low-capability-model-operating-rules"></a>[12.5 Low-capability model operating rules](contracts/12-model-boundary.md#125-low-capability-model-operating-rules)
- <a id="126-semantic-review"></a>[12.6 Semantic review](contracts/12-model-boundary.md#126-semantic-review)
- <a id="127-workflow-defined-model-operations"></a>[12.7 Workflow-defined model operations](contracts/12-model-boundary.md#127-workflow-defined-model-operations)
- <a id="128-closed-authority-reconciliation-boundary"></a>[12.8 Closed authority-reconciliation boundary](contracts/12-model-boundary.md#128-closed-authority-reconciliation-boundary)
- <a id="129-configured-json-response-composition"></a>[12.9 Configured JSON response composition](contracts/12-model-boundary.md#129-configured-json-response-composition)

---

## 13. Action catalogue

Action names define responsibility boundaries. Each entry specifies its input, output,
and single responsibility. The detailed catalogues are part of this baseline;
all actions follow [§6](#6-common-action-and-orchestrator-contract) and
[§25](#25-atomic-workflow-execution-and-output).

- <a id="131-bootstrap-and-configuration-actions"></a>[13.1 Bootstrap and configuration actions](contracts/actions/13-01-bootstrap-configuration.md)
- <a id="132-invocation-feature-and-stage-gate-actions"></a>[13.2 Invocation, feature, and stage-gate actions](contracts/actions/13-02-invocation-stage-gates.md)
- <a id="133-reference-actions"></a>[13.3 Reference actions](contracts/actions/13-03-references.md)
- <a id="134-model-actions"></a>[13.4 Model actions](contracts/actions/13-04-model.md)
- <a id="135-artifact-renderer-and-traceability-actions"></a>[13.5 Artifact, renderer, and traceability actions](contracts/actions/13-05-artifacts-rendering-traceability.md)
- <a id="136-project-path-and-static-validation-actions"></a>[13.6 Project path and static-validation actions](contracts/actions/13-06-project-paths-validation.md)
- <a id="137-task-and-implementation-actions"></a>[13.7 Task and implementation actions](contracts/actions/13-07-tasks-implementation.md)
- <a id="138-whole-workflow-output-boundary"></a>[13.8 Whole-workflow output boundary](contracts/actions/13-08-whole-workflow-output.md)
- <a id="139-feature-logging-actions"></a>[13.9 Feature logging actions](contracts/actions/13-09-logging.md)
- <a id="1310-cross-stage-authority-reconciliation-actions"></a>[13.10 Cross-stage authority-reconciliation actions](contracts/actions/13-10-authority-reconciliation.md)

---

## 14. Orchestrator composition

Orchestrators coordinate runner-owned child bindings and branch on typed results. They perform
no domain or infrastructure operations themselves.

[Complete §14 contract](contracts/14-orchestration.md).

- <a id="140-workflowengineorchestrator"></a>[14.0 `WorkflowEngineOrchestrator`](contracts/14-orchestration.md#140-workflowengineorchestrator)
- <a id="141-model-operation-composition"></a>[14.1 Model-operation composition](contracts/14-orchestration.md#141-model-operation-composition)
- <a id="142-stagegateorchestrator"></a>[14.2 `StageGateOrchestrator`](contracts/14-orchestration.md#142-stagegateorchestrator)
- <a id="143-task-scheduling-operation"></a>[14.3 Task-scheduling operation](contracts/14-orchestration.md#143-task-scheduling-operation)
- <a id="144-atomic-repair-operation"></a>[14.4 Atomic-repair operation](contracts/14-orchestration.md#144-atomic-repair-operation)
- <a id="145-user-review-operation"></a>[14.5 User-review operation](contracts/14-orchestration.md#145-user-review-operation)
- <a id="146-protocol-retry-operation"></a>[14.6 Protocol-retry operation](contracts/14-orchestration.md#146-protocol-retry-operation)
- <a id="147-clarificationlifecycleorchestrator"></a>[14.7 `ClarificationLifecycleOrchestrator`](contracts/14-orchestration.md#147-clarificationlifecycleorchestrator)
- <a id="148-execution-abandonment"></a>[14.8 Execution abandonment](contracts/14-orchestration.md#148-execution-abandonment)
- <a id="149-featureloggingfailureorchestrator"></a>[14.9 `FeatureLoggingFailureOrchestrator`](contracts/14-orchestration.md#149-featureloggingfailureorchestrator)
- <a id="1410-featurelogpolicytransitionorchestrator"></a>[14.10 `FeatureLogPolicyTransitionOrchestrator`](contracts/14-orchestration.md#1410-featurelogpolicytransitionorchestrator)
- <a id="1411-implementation-workflow-composition"></a>[14.11 Implementation workflow composition](contracts/14-orchestration.md#1411-implementation-workflow-composition)
- <a id="1412-per-task-implementation-composition"></a>[14.12 Per-task implementation composition](contracts/14-orchestration.md#1412-per-task-implementation-composition)
- <a id="1413-task-execution-lifetime"></a>[14.13 Task execution lifetime](contracts/14-orchestration.md#1413-task-execution-lifetime)
- <a id="1414-authorityreconciliationorchestrator"></a>[14.14 `AuthorityReconciliationOrchestrator`](contracts/14-orchestration.md#1414-authorityreconciliationorchestrator)

---

## 15. Bootstrap flow

The fixed startup graph loads project workflow authority. The selected compiled workflow then
chooses its permitted setup operations.

[Complete §15 contract](contracts/15-bootstrap.md).

---

## 16. Reference ingestion and normalization

Reference ingestion accounts for every selected source and preserves citations, exact values,
and immutable provenance. Unsupported input and unresolved meaning follow typed failure or
clarification routes.

[Complete §16 contract](contracts/16-reference-ingestion.md).

- <a id="161-reader-contract"></a>[16.1 Reader contract](contracts/16-reference-ingestion.md#161-reader-contract)
- <a id="162-stable-ordering-and-provenance"></a>[16.2 Stable ordering and provenance](contracts/16-reference-ingestion.md#162-stable-ordering-and-provenance)
- <a id="163-structured-facts-and-exact-tokens"></a>[16.3 Structured facts and exact tokens](contracts/16-reference-ingestion.md#163-structured-facts-and-exact-tokens)
- <a id="164-semantic-extraction-flow"></a>[16.4 Semantic extraction flow](contracts/16-reference-ingestion.md#164-semantic-extraction-flow)
- <a id="165-human-correction-without-editing-generated-views"></a>[16.5 Human correction without editing generated views](contracts/16-reference-ingestion.md#165-human-correction-without-editing-generated-views)

---

## 17. Specify stage design

Specify validates an explicit feature directory and independent reference selector, derives
supported business content, and prepares the complete specification output.

[Complete §17 contract](contracts/17-specify.md).

- <a id="171-inputs"></a>[17.1 Inputs](contracts/17-specify.md#171-inputs)
- <a id="172-deterministic-preflight"></a>[17.2 Deterministic preflight](contracts/17-specify.md#172-deterministic-preflight)
- <a id="173-llm-work"></a>[17.3 LLM work](contracts/17-specify.md#173-llm-work)
- <a id="174-specification-clarification-behavior"></a>[17.4 Specification clarification behavior](contracts/17-specify.md#174-specification-clarification-behavior)
- <a id="175-deterministic-specification-validation"></a>[17.5 Deterministic specification validation](contracts/17-specify.md#175-deterministic-specification-validation)
- <a id="176-rendering-and-commit"></a>[17.6 Rendering and commit](contracts/17-specify.md#176-rendering-and-commit)
- <a id="177-specify-gate"></a>[17.7 Specify gate](contracts/17-specify.md#177-specify-gate)

---

## 18. Plan stage design

Plan revalidates the specification and current authority before selecting design, artifacts,
project files, and verification. Its output requires approval before Tasks.

[Complete §18 contract](contracts/18-plan.md).

- <a id="181-inputs-and-preconditions"></a>[18.1 Inputs and preconditions](contracts/18-plan.md#181-inputs-and-preconditions)
- <a id="182-deterministic-repository-reality"></a>[18.2 Deterministic repository reality](contracts/18-plan.md#182-deterministic-repository-reality)
- <a id="183-llm-work"></a>[18.3 LLM work](contracts/18-plan.md#183-llm-work)
- <a id="184-plan-clarification-behavior"></a>[18.4 Plan clarification behavior](contracts/18-plan.md#184-plan-clarification-behavior)
- <a id="185-artifact-applicability"></a>[18.5 Artifact applicability](contracts/18-plan.md#185-artifact-applicability)
- <a id="186-deterministic-plan-validation"></a>[18.6 Deterministic plan validation](contracts/18-plan.md#186-deterministic-plan-validation)
- <a id="187-plan-outputs-and-gate"></a>[18.7 Plan outputs and gate](contracts/18-plan.md#187-plan-outputs-and-gate)

---

## 19. Tasks stage design

Tasks decomposes the approved plan into a traceable dependency graph. The engine validates
coverage, file IDs, commands, evidence requirements, and safe ordering before approval.

[Complete §19 contract](contracts/19-tasks.md).

- <a id="191-inputs-and-preconditions"></a>[19.1 Inputs and preconditions](contracts/19-tasks.md#191-inputs-and-preconditions)
- <a id="192-llm-work"></a>[19.2 LLM work](contracts/19-tasks.md#192-llm-work)
- <a id="193-tasks-clarification-behavior"></a>[19.3 Tasks clarification behavior](contracts/19-tasks.md#193-tasks-clarification-behavior)
- <a id="194-deterministic-task-validation"></a>[19.4 Deterministic task validation](contracts/19-tasks.md#194-deterministic-task-validation)
- <a id="195-parallelism-policy"></a>[19.5 Parallelism policy](contracts/19-tasks.md#195-parallelism-policy)
- <a id="196-rendering-and-gate"></a>[19.6 Rendering and gate](contracts/19-tasks.md#196-rendering-and-gate)

---

## 20. Implement stage design

Implement executes approved tasks inside a private candidate workspace. Commands and changes
require declared authority; completion depends on validation of the whole workflow output.

[Complete §20 contract](contracts/20-implement.md).

- <a id="201-inputs-and-preconditions"></a>[20.1 Inputs and preconditions](contracts/20-implement.md#201-inputs-and-preconditions)
- <a id="202-task-selection"></a>[20.2 Task selection](contracts/20-implement.md#202-task-selection)
- <a id="203-task-context"></a>[20.3 Task context](contracts/20-implement.md#203-task-context)
- <a id="204-change-planning-and-filename-validation"></a>[20.4 Change planning and filename validation](contracts/20-implement.md#204-change-planning-and-filename-validation)
- <a id="205-candidate-workspace-and-validation"></a>[20.5 Candidate workspace and validation](contracts/20-implement.md#205-candidate-workspace-and-validation)
- <a id="206-code-repair"></a>[20.6 Code repair](contracts/20-implement.md#206-code-repair)
- <a id="207-command-execution"></a>[20.7 Command execution](contracts/20-implement.md#207-command-execution)
- <a id="208-task-validation-within-the-atomic-workflow"></a>[20.8 Task validation within the atomic workflow](contracts/20-implement.md#208-task-validation-within-the-atomic-workflow)
- <a id="209-failure-propagation"></a>[20.9 Failure propagation](contracts/20-implement.md#209-failure-propagation)
- <a id="2010-final-implementation-gate"></a>[20.10 Final implementation gate](contracts/20-implement.md#2010-final-implementation-gate)

---

## 21. Deterministic validation catalogue

The validator catalogue specifies each check, its failure behavior, and its evidence. Locked
safety validation remains mandatory; semantic review is identified separately.

[Complete §21 contract](contracts/21-validation.md).

- <a id="211-cross-stage-validators"></a>[21.1 Cross-stage validators](contracts/21-validation.md#211-cross-stage-validators)
- <a id="212-specify-validators"></a>[21.2 Specify validators](contracts/21-validation.md#212-specify-validators)
- <a id="213-plan-validators"></a>[21.3 Plan validators](contracts/21-validation.md#213-plan-validators)
- <a id="214-tasks-validators"></a>[21.4 Tasks validators](contracts/21-validation.md#214-tasks-validators)
- <a id="215-implement-validators"></a>[21.5 Implement validators](contracts/21-validation.md#215-implement-validators)
- <a id="216-validators-that-must-not-be-overstated"></a>[21.6 Validators that must not be overstated](contracts/21-validation.md#216-validators-that-must-not-be-overstated)

---

## 22. Atomic repair protocol

Repair changes only the engine-authorized unit under current identity, revision, and old-value
preconditions. Impacted validation and full-candidate validation precede acceptance.

[Complete §22 contract](contracts/22-repair.md).

- <a id="221-definition-of-atomic"></a>[22.1 Definition of atomic](contracts/22-repair.md#221-definition-of-atomic)
- <a id="222-repair-classification"></a>[22.2 Repair classification](contracts/22-repair.md#222-repair-classification)
- <a id="223-repair-authorization"></a>[22.3 Repair authorization](contracts/22-repair.md#223-repair-authorization)
- <a id="224-repair-request-and-response"></a>[22.4 Repair request and response](contracts/22-repair.md#224-repair-request-and-response)
- <a id="225-merge-and-revalidation"></a>[22.5 Merge and revalidation](contracts/22-repair.md#225-merge-and-revalidation)
- <a id="226-unparseable-output"></a>[22.6 Unparseable output](contracts/22-repair.md#226-unparseable-output)
- <a id="227-repair-retry-limit-and-escalation"></a>[22.7 Repair retry limit and escalation](contracts/22-repair.md#227-repair-retry-limit-and-escalation)
- <a id="228-repair-examples"></a>[22.8 Repair examples](contracts/22-repair.md#228-repair-examples)
  - <a id="wrong-planned-filename"></a>[Wrong planned filename](contracts/22-repair.md#wrong-planned-filename)
  - <a id="missing-coverage"></a>[Missing coverage](contracts/22-repair.md#missing-coverage)
  - <a id="dependency-cycle"></a>[Dependency cycle](contracts/22-repair.md#dependency-cycle)
  - <a id="compiler-failure"></a>[Compiler failure](contracts/22-repair.md#compiler-failure)
  - <a id="scope-expansion"></a>[Scope expansion](contracts/22-repair.md#scope-expansion)

---

## 23. Rendering and editability strategy

The engine renders canonical views. Editable specifications, controlled clarification forms, and
read-only generated views retain distinct ownership and rerun rules.

[Complete §23 contract](contracts/23-rendering.md).

- <a id="231-canonical-byte-contract"></a>[23.1 Canonical byte contract](contracts/23-rendering.md#231-canonical-byte-contract)
- <a id="232-workflow-reruns-and-protected-clarification-files"></a>[23.2 Workflow reruns and protected clarification files](contracts/23-rendering.md#232-workflow-reruns-and-protected-clarification-files)

---

## 24. State, sequence, and recovery without fingerprints

Current canonical state and exact approvals govern stage entry and invalidation. Fresh
invocations revalidate inputs and start again without saved execution recovery or artifact
fingerprints.

[Complete §24 contract](contracts/24-workflow-state.md).

- <a id="241-workflow-state"></a>[24.1 Workflow state](contracts/24-workflow-state.md#241-workflow-state)
- <a id="242-stage-transition-state-machine"></a>[24.2 Stage transition state machine](contracts/24-workflow-state.md#242-stage-transition-state-machine)
- <a id="243-gate-behavior"></a>[24.3 Gate behavior](contracts/24-workflow-state.md#243-gate-behavior)
- <a id="244-new-execution-after-interruption-or-clarification"></a>[24.4 New execution after interruption or clarification](contracts/24-workflow-state.md#244-new-execution-after-interruption-or-clarification)
- <a id="245-upstream-rework-and-invalidation"></a>[24.5 Upstream rework and invalidation](contracts/24-workflow-state.md#245-upstream-rework-and-invalidation)

---

## 25. Atomic workflow execution and output

Validate the complete output before publication. Success requires all required writes; failure
may leave replaced files but cannot record new successful completion. Clarifications retain
their explicit persistence and protection rules.

[Complete §25 contract](contracts/25-publication.md).

- <a id="251-one-execution-one-output-boundary"></a>[25.1 One execution, one output boundary](contracts/25-publication.md#251-one-execution-one-output-boundary)
- <a id="252-abandonment-and-reruns"></a>[25.2 Abandonment and reruns](contracts/25-publication.md#252-abandonment-and-reruns)
- <a id="253-external-effects-and-observations"></a>[25.3 External effects and observations](contracts/25-publication.md#253-external-effects-and-observations)

---

## 26. Security and safety

Typed authority and narrow adapters enforce model, filesystem, command, reference, secret, and
logging boundaries.

[Complete §26 contract](contracts/26-security.md).

- <a id="261-llm-trust-boundary"></a>[26.1 LLM trust boundary](contracts/26-security.md#261-llm-trust-boundary)
- <a id="262-filesystem-safety"></a>[26.2 Filesystem safety](contracts/26-security.md#262-filesystem-safety)
- <a id="263-command-safety"></a>[26.3 Command safety](contracts/26-security.md#263-command-safety)
- <a id="264-reference-safety"></a>[26.4 Reference safety](contracts/26-security.md#264-reference-safety)
- <a id="265-secrets-and-logging"></a>[26.5 Secrets and logging](contracts/26-security.md#265-secrets-and-logging)

---

## 27. Observability

The runner supplies workflow attribution. Registered logging actions transform typed telemetry
into safe records without making logs workflow authority.
At `debug` and `trace`, [ADR 0018](decisions/0018-debug-model-exchange-logging.md)
requires complete credential-redacted production model requests and available raw
responses, including failed attempts, in the registered prompt stream.
[ADR 0019](decisions/0019-single-request-debugger.md) adds the embedded browser
debugger, explicit retry/repair lineage, and exact or modified replay of one selected
request without workflow execution.

[Complete §27 contract](contracts/27-observability.md).

---

## 28. Testing strategy

Action, orchestrator, property, fault-injection, renderer, and packaging checks establish
distinct evidence. Live E2E execution and semantic evaluation have separate acceptance
requirements.

[Complete §28 contract](contracts/28-testing.md).

- <a id="281-action-unit-tests"></a>[28.1 Action unit tests](contracts/28-testing.md#281-action-unit-tests)
- <a id="282-property-based-tests"></a>[28.2 Property-based tests](contracts/28-testing.md#282-property-based-tests)
- <a id="283-orchestrator-tests"></a>[28.3 Orchestrator tests](contracts/28-testing.md#283-orchestrator-tests)
- <a id="284-model-fault-injection-tests"></a>[28.4 Model fault-injection tests](contracts/28-testing.md#284-model-fault-injection-tests)
- <a id="285-preset-conformance-fixtures"></a>[28.5 Preset conformance fixtures](contracts/28-testing.md#285-preset-conformance-fixtures)
- <a id="286-renderer-and-artifact-tests"></a>[28.6 Renderer and artifact tests](contracts/28-testing.md#286-renderer-and-artifact-tests)
- <a id="287-end-to-end-tests"></a>[28.7 End-to-end tests](contracts/28-testing.md#287-end-to-end-tests)

---

## 29. Suggested package/module structure

The package layout reflects the required dependency boundaries and native Zig distribution.

[Complete §29 contract](contracts/29-package-structure.md).

---

## 30. Delivery sequence for the new engine

### Increment 1: contracts and deterministic core

- Pin the accepted Zig compiler version and create the `build.zig` scaffold,
  repository-defined verification steps, module import boundaries, and native
  clean-environment packaging smoke test. Adding a production dependency still
  requires explicit approval.
- Define config, workflow-definition, project-toolchain, preset, and model-response schemas.
- Define IR, diagnostic, evidence, action, orchestrator, and state contracts.
- Implement the compiler-locked requiredness/ownership/reconciliation registries, structural authority-requirement ledger, closed reconciliation outcomes, complete-ledger validator, and generic earliest-owner gap router before enabling any workflow model operation.
- Bind the invocation working directory as project root and resolve only its exact `.sddtoolkit.json`, failing the invocation when it is absent; validate the seven configured directory roots and exact `paths.providers` file location, then derive only the fixed clarification/log and workflow `features/` children without an ancestor, descendant, fixed provider path, source-tree, or packaged-example fallback.
- Implement the fixed nonselectable engine-startup graph and workflow-authority
  loading: inventory, definition/resource capture and schema validation,
  registered-operation project graph
  compilation, and variable-size registry validation.
- Implement generic workflow execution: exact `WorkflowId` selection,
  runner-bound invocation-contract execution, and compiled transition traversal
  with no workflow-name branches.
- Implement direct preset-registry loading, exact project
  `toolchain.yaml` parsing/inheritance compilation, semantic Markdown principle
  inventory/capture/category-hint indexing with mechanical-file exclusion,
  inert template-root reservation, and path validation.
- Implement editable-spec render/parse round trips, generated-view equality and the atomic whole-workflow output/abandonment boundary in Section 25.
- Implement the common feature-event logging pipeline, canonical level/alias handling, fixed per-feature sinks, redaction, rotation, and crash recovery before any feature-producing stage is enabled.
- Provide fake ports and architecture tests.

### Increment 2: Specify

- Implement invocation/identity and reference preflight.
- Add the initial reader registry and citation system.
- Implement the structured reference/spec operations declared by their workflow YAML definitions.
- Add specification/reference-context validators, no-invention routing, atomic repair, rendering, and commit.
- Integrate the shared reconciliation boundary for every specification-owned field, reference-meaning decision, and preserved obligation; specification-local rules may contribute requirements/candidates only.
- Add the focused principle assessment in §17.3.1 using canonical principle selection;
  retain policy conflicts as mandatory Plan obligations and prepare actionable needs.
- Implement the complete `S01..S99` clarification lifecycle, exact subject deduplication, controlled forms, authority/user resolution, rerun regeneration, and the blocking plan gate.

### Increment 3: Plan

- Implement repository/manifest discovery and environment facts.
- Implement plan IR, artifact applicability, and bounded applicable-principle selection over the bootstrap-captured free-text registry.
- Add path/coverage/token/quickstart validators.
- Integrate the shared reconciliation boundary for every planning-owned architecture, policy, repository/capability, dependency, design, and verification-strategy decision; no plan-domain fallback may bypass it.
- Implement `P01..P99` clarification persistence/deduplication and fresh reruns, full plan regeneration, generated-view rendering, explicit plan review, and the blocking tasks gate.

### Increment 4: Tasks

- Implement obligation ledger and typed task proposal operations.
- Build DAG, path/command validation, coverage, ordering, and parallel calculation.
- Integrate the shared reconciliation boundary for task-owned decomposition, authorization, dependency, command/scenario, and evidence slots, with upstream gaps routed back rather than absorbed.
- Implement `T01..T99` clarification persistence/deduplication and fresh reruns, full graph regeneration, deterministic read-only `tasks.md`, explicit task review, and the blocking implement gate.

### Increment 5: Implement

- Implement authorized create/update/replace/copy operations, configured command execution, AST/import checks and evidence inside one private workflow candidate.
- Rebuild reconciliation at implementation entry, after candidate task changes and before whole-workflow publication; route every non-code authority gap to its earliest upstream owner and permit repair only inside fully resolved approved authority.
- Implement current-execution candidate ownership and cleanup, and final checks over the complete candidate before publishing workflow output; no persisted adapter checkpoints.
- Start with sequential task execution; enable validated concurrency only after overlay/lock tests pass.

### Increment 6: preset breadth and hardening

- Ship and test React/Node/Java/.NET compositions.
- Add remaining reference readers.
- Complete cross-stage crash/fault/security, clarification, logging, and root/preset/principle conformance testing; telemetry here means dashboards/metrics over the mandatory logging foundation delivered in Increment 1, not deferred event logging.
- Generate human-facing prompt/reference documentation from the authoritative workflow operation/resource definitions to avoid duplicated prompt drift.

Each increment must be usable with a fake `LLMProviderInterface` before integrating a real provider.

---

## 31. Acceptance criteria for the design implementation

The new engine is ready for production evaluation when all of the following are true:

1. **Workflow registry and execution.**
    - The validated workflow registry has one generic bootstrap component identity, totally
      accounts a collision-free ordinal-bound workflow inventory, accepts an arbitrary bounded
      number of definitions with unique workflow IDs, logging shortcodes, and source ordinals,
      compiles every definition only from registered `PipelineNode` contracts, and resolves an
      invoked `WorkflowId` exactly once.
    - No definition may collide with a reserved child, contain executable code, select
      infrastructure, add a capability, weaken a gate, or bypass runner validation.
    - The initial SDD workflow gates still prohibit `plan` before a valid committed
      specification, `tasks` before an approved current plan state, and `implement` before an
      approved current task-definition state.
    - The composition-root-owned startup graph can build the registry before a project graph
      exists but is neither selectable nor project-extensible and acquires no workflow execution
      capability.
    - After exact selection, the separate fixed capability-free model-provider bootstrap
      orchestrator derives its branch only from the graph's compiled model-binding requirements
      and provider-call capabilities and is likewise nonselectable and not project-extensible.
    - The generic workflow engine contains no branch on workflow names, invokes the selected
      YAML-named invocation operation once, and follows the exactly selected immutable graph
      only through runner-owned child bindings; the common runner remains the sole node
      invocation and delta owner.
    - Bound-graph change classification compares stable semantic authority rather than source
      ordinal, registry identity, or validation evidence.
    - Each execution has a fresh [envelope information stack](contracts/06-pipeline-nodes.md#execution-local-information-stack).
      Repeated placement of one immutable occurrence has no additional effect;
      conflicting or foreign placement rejects, and history cannot restore current authority.

2. **Configuration and provider authority.**
    - Bootstrap treats the invocation working directory as project root and accepts only its
      exact `.sddtoolkit.json` up to the internal 1,048,576-byte guard.
    - Any safe-read failure returns `ENGINE_CONFIG_READ_ERROR`; any JSON/closed-shape failure
      returns `ENGINE_CONFIG_PARSE_ERROR`; either exits nonzero before workflow work.
    - It requires exactly `specs`, `references`, `specsArchive`, `workflows`, `toolchainPreset`,
      `principles`, `templates`, and `providers`; applies only the
      `specsArchive`-beneath-`specs` nesting exception; requires `providers` to identify a
      distinct project-relative `.sddproviders.json` file; never searches a parent/child
      directory; and never treats `design/examples/.sddtoolkit.json`, a fixed provider filename,
      a source tree, or a packaged asset as runtime configuration/fallback.
    - The fixed run-preparation boundary derives model-provider requiredness only from the
      exactly selected compiled graph's typed model-binding requirements or exact
      `model-provider` capability.
    - For a model-capable selected workflow, every exact `(provider, model)` tuple named by
      `models.slots` resolves once in the completely validated provider catalogue; the
      repository may allow some or all catalogue entries but never a model absent from that
      catalogue, and unused entries gain no repository authority.

3. **Configured locations and bootstrap.**
    - Workflow definitions and reserved `features/` resolve only beneath `paths.workflows`.
    - Presets resolve directly beneath `paths.toolchainPreset`; the complete preset registry
      validates independently of project selection.
    - The mechanical project layer resolves only as `<paths.principles>/toolchain.yaml`. Only
      its post-composition safety-valid merged result may feed
      environment/path/command/capability consumers.
    - The total principles inventory accounts for that file exactly once as mechanically
      excluded. Semantic capture accepts only other normalized Markdown beneath
      `paths.principles`.
    - `paths.templates` remains unread and inert throughout the initial SDD suite.
    - All configured and derived locations validate for separation, containment, and reserved
      ownership.

4. **Feature and reference selection.**
    - Specify requires an explicit `--feature <feature-directory>` and independent `--reference
      <relative-selector>` (or the equivalent two-field API).
    - Resolve the feature directory relative only to `.sddtoolkit.json`'s `paths.specs`, with no
      hard-coded or repeated root.
    - The validated resolved directory identifies the feature; no reference-derived name,
      ownership registry or active/archive ownership inventory exists.
    - Same-directory reruns replace the selected workflow's known outputs while preserving
      user-closed clarification files byte-for-byte.
    - The title/description/goal remain reference-derived.

5. No LLM action has a filesystem, process, state, logger, or unrestricted tool interface.

6. No orchestrator imports or directly uses infrastructure/domain-operation ports; actions
    cannot contain/call actions or orchestrators, while orchestrators may contain only
    runner-owned child bindings to actions/orchestrators.

7. Every action and orchestrator conforms to the same typed `PipelineNode` contract,
    communicates through immutable validated envelopes/deltas, and has the required isolated
    action or spy-child orchestrator tests.

8. **Mandatory feature logging.**
    - Mandatory metadata event logs use fixed-header pipe-delimited `feature-log/v2` beneath
      `<paths.specs>/<featureId>/logs/`.
    - Logs use only the compiler-locked `event-columns/v2` and `prompt-columns/v3` headings.
      Each segment has one exact heading and validated segment control rows.
    - Every event/prompt row carries the selected compiled workflow's registry-validated
      `workflow_shortcode` and the registry-owned `level`.
    - The unversioned `.sddtoolkit.json` threshold uses the exact `CRITICAL -> fatal` and `WARN
      -> warning` aliases.
    - Logging survives prior-run tail recovery and fails closed without becoming workflow
      authority.
    - Debug/trace captures complete credential-redacted model exchanges in bounded chunks;
      higher thresholds emit metadata only. `logs.level` is the sole capture control.
    - The native debugger exposes prompt, structured/raw context, schema, exact request,
      response stages and caller/YAML-entry attribution. Retries and repairs link to
      their producing calls. Explicit exact/modified replay sends one selected request
      at most once, retains an immutable linked result and grants no workflow authority.

9. Fixed workflow artifact paths are engine-assigned, and every path-like model field is
    structured, normalized, contained, classified, preset-validated, and authorized before it
    can enter specification, plan, tasks, or a published output.

10. **Planned file identity.**
    - Planned new files select one engine-authorized `pathIntentOptionId` and semantic
      `nameSourceId`, then use deterministically ordered, bounded, engine-enumerated
      `pathCandidateId` choices before minting a `fileId`; the option indivisibly binds project,
      environment, kind, role, templates, and capability ceiling.
    - Every actionable project-file reference in tasks/implementation is only a `fileId`,
      renderers alone display validated paths, and unbound path-shaped prose is rejected.

11. React, Node, Maven/Gradle Java, and multi-project .NET fixtures have accepted and rejected
    option-binding, registered name-transform, zero/over-limit candidate, filename, placement,
    project-ownership, test-mapping, and content-coupled naming tests; overlapping kinds cannot
    be used to obtain a broader capability.

12. **Model results, limits, and retries.**
    - Under the user-approved 2026-09-19 amendment to §12.5, every engine inference
      request uses temperature `0` when supported by its registered model and
      omits it otherwise. Workflow overrides reject; preparation, authorization
      and retries preserve this policy. Bedrock evaluation uses the same policy;
      OpenAI evaluation remains unchanged.
    - Every YAML-declared model operation—including implementation and repair—conforms with a
      nano-class model and has an ADR 0006 compact closed response schema, complete
      evidence/guidance packet, and deterministic runner-owned request identity/accounting
      without model echoes.
    - The selected workflow policy supplies the sole workflow-global model-consumption limit as
      one positive total-token budget initialized for each execution.
    - Every retry-capable operation instance supplies its own explicit compiler-validated
      `retry-limit`; no workflow policy, configuration, provider, adapter, or runner supplies a
      retry default or global attempt ceiling. Atomic repair counts follow the native
      defect identity and validated-progress rules in §22.7.
    - Normal filename selection packets contain only complete bounded option/candidate choices;
      complete raw-fallback rules are never truncated.
    - Provider APIs own model-call size limits; no engine/operation/slot byte ceilings, size
      estimates or static-capacity checks gate calls.
    - Actual reported input/output usage is retained even on budget overshoot, and no subsequent
      call is allowed at or above the execution budget.
    - Configured response parts follow [ADR 0016](decisions/0016-configured-json-response-composition.md):
      one complete schema, generic derived part schemas, independent request identities,
      prompt-free native assembly with actual producer provenance, and full validation.
      Prove the same behavior with unrelated JSON shapes. Increased finite graph capacity
      is verified independently of unchanged token/retry limits.

13. One invalid option/name-source/candidate selection, or one fallback-only filename defect,
    causes one atomic repair request; valid sibling output is preserved.

14. A repair cannot change a field outside its closed authorization and old-value/revision
    preconditions.

15. Every repaired candidate receives impacted/dependent validation followed by full-candidate
    validation before persistence. Validated resolution permits repair of another target;
    recurrence retains its own history under §22.7. Exhaustion of the selected defect's
    explicit operation retry allowance blocks/fails and never weakens policy.
    JSON/schema rejection that cannot be corrected is a terminal error under §22.6,
    even with open clarifications; it cannot publish an incomplete specification.

16. Unsupported references are reported and cannot be silently omitted; every selected source,
    decoded block, and bounded chunk has an exact disposition and accounting record.

17. Persisted reference citations, provenance, claims, conflicts, and exact preserved tokens are
    mechanically verifiable across restart without a content fingerprint.

18. The one-use no-invention repair may produce `clarification_needed` only for an
    admitted authority gap under §12.8.1. Candidate loss and inconclusive review
    retain their repair/rejection outcome. Neither engine nor model invents a
    requirement, architecture decision, task fact, path, command or resolution.

19. **Clarification identity and stage gates.**
    - Clarifications use only registered `<feature>/clarify/S01..S99.md`, `P01..P99.md`, and
      `T01..T99.md` identities/paths.
    - Exact subject keys prevent duplicates.
    - Questions identify the requirement, current evidence and exact unresolved decision
      under §12.7; equal wording across subjects does not authorize answer sharing.
    - Review diagnostics alone are not actionable questions. Do not ask users to
      restate supported behavior in the engine's internal specification categories.
    - Combined candidate defects and genuine gaps obey §12.8.1 in every finding
      order; §28.9 tests the complete path through publication and fresh readback.
    - Open forms expose only controlled fields; closed historical views are read-only.
    - Reruns reconsider current reference/principle/answer authorities and regenerate the
      complete owning stage.
    - Open `S`, `S/P`, or `S/P/T` sets respectively make plan, tasks, or implement emit `ERROR`
      and exit nonzero.

20. **Artifact editability and approvals.**
    - `spec.md` is the sole freely editable stage artifact.
    - Every acceptance criterion uses the canonical compact `Given`/`When`/`Then` triplet.
    - The specification round-trips to normalized specification IR.
    - Plan/design and task files are deterministic read-only review projections and are never
      parsed as authority.
    - Those projections require approvals bound to the current canonical state IDs.

21. `spec.md` is business-only according to deterministic lint and configured semantic review,
    while technical/reference data remains in the sidecar.

22. **Project principle authority.**
    - Semantic Markdown principle filenames are category hints only; their complete bounded
      bodies remain free text.
    - The exact current principle registry is loaded, selected and cited for Spec's
      focused consistency assessment (§17.3.1), and at plan, tasks, implement and fresh
      clarification-rerun gates. It never invents or erases specification requirements.
    - Spec proves assessment/evidence coverage and retains every Plan-owned policy
      obligation. Plan rechecks current principles and resolves those obligations;
      a successful Spec assessment does not certify policy approval.
    - Exact `toolchain.yaml` is closed mechanical policy inherited from validated preset
      packages and never enters semantic guidance.

23. Plan file records match real repository environments, all planned paths were
    preset-validated before rendering, and all requirements/scenarios/preserved-token
    obligations have coverage.

24. Task IDs, runtime status, checkboxes, dependencies, ordering, mandatory checks, and `[P]`
    are engine-derived; every task file reference was already authorized by the validated plan
    file registry.

25. The engine rejects dependency cycles and parallel write/resource conflicts.

26. Implementation uses operation savepoints and supports authorized create, update, full
    replace, byte-exact copy-in plus separately authorized adaptation, and policy-gated delete
    without raw model paths.

27. Only preset/config command IDs execute, without an engine shell and within configured
    sandbox/network/resource/effect limits; every mutating command receives a post-command delta
    gate.

28. Operation/command evidence and candidate changes remain execution-local until the whole
    workflow completes; interruption cannot resume from an adapter record.

29. A task is marked [X] only in the complete successful workflow output with its exact
    validated evidence and definition/runtime identities; no independent task commit is
    permitted.

30. Failed and blocked executions cannot be reported as completed.
    Complete diagnostic capture under §27 includes failures and every correction
    attempt; full model bodies without production event records are insufficient.

31. **Publication and fresh execution.**
    - The selected workflow validates its complete output before publication.
    - Non-success abandons unpublished candidates; a write failure/interruption may leave
      already-replaced files but cannot record new successful completion.
    - A new invocation starts again.
    - No project/feature transaction store, WAL, transaction-ID ledger, durable checkpoint or
      provider-effect recovery is permitted.
    - Clarifications retain their explicit persistence exception, including ADR 0017
      incomplete specification/reference views and pending state; these never authorize Plan.
      A valid clarification pause publishes `spec.md`; terminal validation failure
      remains failure even when clarification records already exist.

32. Stage state, fresh-invocation validation, comparisons and invalidation work without
    storing/comparing artifact fingerprints and without depending on Git flow.

33. **View integrity and rerun replacement.**
    - Generated views exactly match canonical rendering; tampering is detected and regenerated
      rather than imported.
    - Every workflow rerun MUST completely overwrite all its registered replaceable output files
      and unresolved clarification forms at the same paths, retaining clarification subject IDs
      but not old unresolved form bytes.
    - It MUST NOT overwrite clarification files resolved (closed) by the user.
    - Section 23.2 applies to every registered workflow, with no append, merge, skip, suffix or
      separate overwrite approval.

34. `debug` and `trace` capture every production model attempt's complete assembled request
    and available raw response, with credential redaction before lossless bounded chunking.
    Higher thresholds emit metadata only; the removed `promptCapture` field rejects.
    Retention, sink protections and fail-closed capture failures remain mandatory.

35. **Offline integration and fault injection.**
    - Fake-model tests cover valid flow, exact CLI/config roots, variable-size workflow
      definition registries and reserved children.
    - They cover selection and execution of an unrelated valid workflow composed from registered
      nodes.
    - They cover project-toolchain inheritance, semantic principles, inert templates, S/P/T
      clarification gates and reruns, approvals, and generated-view tampering.
    - They cover mandatory event logging and recovery, malformed output, atomic repair, and
      operation-local retry exhaustion.
    - They cover per-execution total-token-budget exhaustion and isolation, copy/replace,
      compiler/test repair, and upstream rework.
    - They cover execution abandonment, candidate isolation, and final evidence.

36. One shared, domain-neutral authority-reconciliation contract enumerates every
    schema/obligation/policy/accepted-authority-required datum or decision, assigns structural
    identity and a compiler-locked earliest owner, and produces exactly one validated closed
    outcome per entry before generation and commit.

37. Zero support, multiple non-equivalent support, ambiguity, conflict, staleness, unsupported
    authority, and unregistered ownership can never satisfy a stage gate or enter ordinary
    atomic repair; they create an owner-correct clarification, explicit upstream rework, or
    administrative block with no default, approximation, nearest match, conventional choice,
    warning-only continuation, or model-memory substitute.

38. Specify owns feature-intent/reference-meaning gaps, plan owns
    design/architecture/policy/repository/capability/verification-strategy gaps, tasks owns
    executable-decomposition/authorization/dependency/evidence-binding gaps, and implementation
    owns none of those decisions; discovering a gap downstream cannot change its owner.

39. Every authority refresh, clarification resolution, repair, fresh-invocation validation,
    approval gate, and pre-commit boundary rebuilds and validates the complete reconciliation
    projection from current canonical authority; upstream changes invalidate all affected
    descendants, approvals, runtime, and evidence through the ordinary Section 24.5 route.
    Source-backed omission repair additionally proves unique producer/target selection,
    raw sibling preservation and complete derived-identity rebuilding under §22;
    ambiguous, stale and source-gap cases cannot enter repair.

40. Conformance tests apply the same reconciliation and routing assertions to multiple unrelated
    requirement kinds and reject caller-, fixture-, format-, framework-, token-, filename-, or
    example-specific continuation branches; a new kind is accepted only with a registered
    schema, ownership rule, reconciliation policy, and positive/negative tests.

41. The engine is built from a repository-pinned Zig compiler through `build.zig`, and its
    release artifact passes the clean native-executable smoke suite without the source tree, Zig
    toolchain, build cache, Node.js, or development-only assets.

---
## 32. Accepted and deferred implementation choices

Accepted ADRs amend only their stated scope. The superseded record remains for
decision history:

| Record | Current decision |
| --- | --- |
| [0001](decisions/0001-zig-engine.md) | Zig engine and native executable; Node/JavaScript remain target-project technologies. |
| [0002](decisions/0002-zig-version.md) | Exact Zig 0.16.0 pin and explicit upgrade policy. |
| [0003](decisions/0003-generic-workflow-engine.md) | Generic discovered workflows, compiled registered operations and a capability-free engine. |
| [0004](decisions/0004-model-provider-bootstrap.md) | Conditional provider bootstrap and one immutable provider capture per invocation. |
| [0005](decisions/0005-workflow-defined-operations.md) | Workflow-owned operation topology/resources and unversioned operation IDs. |
| [0006](decisions/0006-minimal-model-response.md) | Compact closed responses with runner-owned correlation and canonical schema validation. |
| [0007](decisions/0007-unicode-normalization.md) | Pinned utf8proc NFC, statically packaged Unicode data and license notices. |
| [0008](decisions/0008-feature-naming-policy.md) | Superseded by 0010; reference-derived naming is withdrawn. |
| [0009](decisions/0009-atomic-workflow-execution.md) | Whole-execution validation, fresh reruns, protected clarifications and explicit publication-failure semantics; no recovery transactions. |
| [0010](decisions/0010-explicit-feature-directory.md) | The supplied validated directory identifies the feature. |
| [0011](decisions/0011-provider-owned-request-limits.md) | Provider-owned per-call limits and actual execution-token accounting. |
| [0012](decisions/0012-workflow-owned-model-request.md) | Retain one execution-owned request/binding/resource identity across explicit YAML operations. |
| [0013](decisions/0013-workflow-input-reuse.md) | Local subgraphs, local schema reuse and shared lossless input projections. |
| [0014](decisions/0014-universal-response-format-guidance.md) | One shared JSON framing instruction for every serialized model request. |
| [0015](decisions/0015-specification-principle-review.md) | Early Spec principle assessment and shared actionable questions; configuration/capture/review and shared question preparation implemented; final readiness pending. |
| [0016](decisions/0016-configured-json-response-composition.md) | User-directed configured JSON decomposition and prompt-free assembly; finite graph-limit increase approved. Configured object-part compiler and extraction integration implemented; live improvement pending. |
| [0017](decisions/0017-incomplete-specification-publication.md) | Clarification pauses publish a validated incomplete specification and pending state without completion authority. |
| [0018](decisions/0018-debug-model-exchange-logging.md) | Debug/trace capture complete credential-redacted production model exchanges, including failed attempts, without silent truncation. |
| [0019](decisions/0019-single-request-debugger.md) | The native browser debugger inspects captured calls and explicitly replays one selected prompt with immutable parent links and no workflow execution. |

Additional accepted feature boundaries:

- [F0005](features/F0005-WorkflowDefinitionRegistryService.md): v1 workflow
  definitions are strict UTF-8 YAML 1.2 in recursively discovered,
  case-sensitive `*.workflow.yaml` regular files and conform to the closed
  [workflow-definition v1 schema](schemas/workflow-definition-v1.schema.json).
  Identity comes only from validated content, and v1 has no alternate encoding,
  YAML alias or custom tag, include, compatibility reader, or runtime
  schema-file fallback;
- [F0008](features/F0008-LLMProviderConfigService.md): the required
  `.sddtoolkit.json` `paths.providers` value is the sole provider-document path
  authority. F0004 reserves its distinct opaque `.sddproviders.json` file
  capability, and F0008 alone performs its bounded read-only capture without
  parsing, provider-registry construction, fixed-location fallback, or
  unconditional loading;
- [F0006](features/F0006-LLMProviderInterface.md): provider and request authority.
  - `.sddproviders.json` uses the strict bounded common schema in
    `schemas/sddproviders.schema.json`. Provider-specific config closes through compiler-owned
    contracts; `LLMProviderRegistryService` owns the completely validated catalogue.
  - `.sddtoolkit.json` `models.slots` is validated into a separate immutable repository
    allowlist. Every slot tuple must appear exactly once in the catalogue. Slots may reference
    some or all catalogue models, never an additional model; unreferenced entries lack
    repository authority.
  - Each YAML model step selects one typed repository slot. Before invocation, the runner
    resolves that slot to one immutable provider/model binding. `LLMProviderInterface` is the
    sole provider-neutral port.
  - One ordinal covers the complete count and inference attempt. External-operation lifecycle
    remains execution-local, and compiled YAML explicitly selects retries.
  - Authorization preparation is restricted to a preloaded, non-refreshing, no-I/O lease.
  - Production Bedrock contracts, closed configuration, native-schema projection, and concrete
    adapters are included in F0006 completion.
- [F0007](features/F0007-AWSBedrockProvider.md) implements the accepted production
  integration and environment-only credential choice: a narrow infrastructure source
  reads only `AWS_BEARER_TOKEN_BEDROCK` into an invocation-owned snapshot before
  no-I/O lease preparation. No key value may be hardcoded or supplied through
  repository configuration, workflow YAML, prompts, arguments, source,
  examples, fixtures, or binaries; no fallback credential source or refresh is
  permitted.

The following choices remain deferred. Resolve them under the project's
explicit decision/approval rules before dependent implementation:

- release build modes, remaining linking decisions beyond ADR 0007, and the supported platform matrix;
- concrete JSON Schema, Markdown AST, tree-sitter/compiler, PDF, office, image/OCR, and overlay libraries;
- the UI/API used to record manual verification evidence;
- which binary reference readers ship in the first release versus plugins;
- completion of remaining workflow publication/clarification integration; the shared writer is implemented and follows ADR 0009, with current gaps tracked in F0100;
- when concurrency above one becomes enabled by default;
- whether model-assisted semantic warnings block by default in development versus CI.

They must not weaken the invariants, path policy, command safety, repair scoping, evidence requirements, or action/orchestrator separation defined above.

- Template selection, destination naming, collision handling and publication for `sdde init`
  remain deferred to a separate init design.
- The initial SDD suite fixes only that inputs come from `paths.templates`, materialized
  principles go to `paths.principles`, copying requires an explicit accepted init operation, and
  no ordinary bootstrap or feature workflow performs it.

---

## 33. Prompt-to-engine migration matrix

The migration matrix assigns predecessor prompt responsibilities to engine components and
identifies the governing repair and authority rules.

[Complete §33 contract](contracts/33-prompt-migration.md).

- <a id="330-cross-cutting-responsibilities-removed-from-prompts"></a>[33.0 Cross-cutting responsibilities removed from prompts](contracts/33-prompt-migration.md#330-cross-cutting-responsibilities-removed-from-prompts)
- <a id="331-specify-prompt"></a>[33.1 Specify prompt](contracts/33-prompt-migration.md#331-specify-prompt)
- <a id="332-plan-prompt"></a>[33.2 Plan prompt](contracts/33-prompt-migration.md#332-plan-prompt)
- <a id="333-tasks-prompt"></a>[33.3 Tasks prompt](contracts/33-prompt-migration.md#333-tasks-prompt)
- <a id="334-implement-prompt"></a>[33.4 Implement prompt](contracts/33-prompt-migration.md#334-implement-prompt)

---

## 34. Final design position

The predecessor toolkit supplied the high-level workflow shape but delegated operational authority to model instructions. The new engine should preserve the semantic progression and artifact intent while reversing that authority:

- The engine supplies facts and constraints before generation.
- The engine proves every required authority is exactly reconciled or returns to its earliest owner; no stage repairs an authority gap locally.
- The LLM returns one small typed semantic or code unit.
- The engine validates every mechanically decidable property.
- The engine gives precise preset-derived guidance for exactly one failed unit.
- The LLM repairs only that unit.
- The engine renders, writes, runs, verifies, and advances state.
- Zig supplies the native executable, explicit ownership/error model, and
  compile-time structure for these boundaries; it does not move workflow
  authority out of the deterministic contracts.

This is the appropriate deterministic layer for lower-capability models: it does not ask a nano model to behave like a reliable workflow engine, and it does not attempt to replace the model where interpretation and synthesis are genuinely required.
