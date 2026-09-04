# F0050 — SpecWorkflowEvaluationService

**Status:** Readiness finding — blocked; no implementation or governing
decision is accepted by this document

**Review date:** 2026-08-30

**Reviewed snapshot:** `main` at `37507fe`, plus the then-present uncommitted
test-only changes in `compile_workflow_graphs.zig`,
`validate_compiled_workflow_graphs.zig`, and `workflow_registry_test.zig`.

**Implementation readiness:** There is no executable harness path for the full
`specify` workflow. The native engine can load, compile, select, and traverse a
generic no-op workflow, but it has no registered Specify contracts, typed
Specify data path, reference/model/specification runtime, durable Specify
transaction, or implemented evaluation harness. The named fixture is source
material, not a runnable target project.

**Classification:** Development-only full-workflow evaluation readiness

**Scope:** SDDE engine development and evaluation only. This finding does not
authorize running SDDE against a real target project, changing the fixture,
calling a live model, accepting the proposed engine or harness designs, or
adding a production/development dependency.

**Governing authority:** Accepted [ADR 0001](../decisions/0001-zig-engine.md),
[ADR 0002](../decisions/0002-zig-version.md), [ADR
0003](../decisions/0003-generic-workflow-engine.md), and [ADR
0005](../decisions/0005-workflow-defined-operations.md); the still-proposed [engine
design](../design.md), especially Sections 1, 3-7, 9-17, and 21-31; [F0003 —
ToolChainService](F0003-ToolChainService.md); [F0005 —
WorkflowDefinitionRegistryService](F0005-WorkflowDefinitionRegistryService.md);
[F0006 — LLMProviderInterface](F0006-LLMProviderInterface.md); [F0100 —
SpecWorkflow](F0100-SpecWorkflow.md); and the still-proposed [test-harness
design](../../TEST_HARNESS.md).

---

## 1. Finding

The requested outcome is not currently runnable. There are three independent
blocking boundaries:

1. the production engine has only generic bootstrap and no-op workflow
   execution foundations;
2. the proposed harness contract evaluates one YAML-declared model operation,
   not one complete compiled workflow and its durable effects; and
3. `test/evaluation/wf-001-hello-world/node-vitest/` does not contain, and
   should not itself become, a complete runtime project.

The causal defect is therefore not a missing fixture-specific command. A
special runner for `wf-001`, `node-vitest`, `stories.md`, or `specify` would
bypass the accepted generic runtime and duplicate production policy. The
smallest architecturally complete milestone is a development-only,
deterministic, fake-model, conformance-only full-workflow case that constructs
an isolated project, executes the ordinary compiled `specify` graph through
the production runner, and validates its artifacts and canonical state.

Semantic rubric scoring, a model-assisted judge, a live provider, and
Node/Vitest command execution are later milestones.

## 2. Required observable outcome

Before this feature can be called usable, an accepted harness command must:

1. validate a closed full-workflow case definition;
2. construct an isolated temporary project from immutable fixture resources;
3. place the Hello World reference beneath that project's configured
   `paths.references` root and invoke `specify` with one contained relative
   selector;
4. bootstrap the exact project configuration and configured authority roots;
5. discover, compile, select, and execute the ordinary `id: specify`
   definition through registered contracts and runner-owned bindings;
6. use a fake production model boundary with a complete, deterministic,
   request-identified response script for every YAML-declared model operation
   the workflow reaches;
7. validate reference accounting, authority reconciliation, model candidates,
   repair or clarification behavior, `SpecificationIR`, and rendered views;
8. assert the case's accepted terminal oracle: either committed `specified` or
   committed `spec_clarification_pending` plus terminal `needs_user`;
9. for a success case, assert byte-stable `spec.md`, mandatory
   `reference-context.md`, canonical workflow state, transaction evidence, and
   required feature-log output;
10. prove the source fixture is unchanged and no network, credential, source
    fallback, model-supplied command, or real target-project access occurred;
    and
11. emit a closed deterministic conformance report beneath generated
    evaluation output, without promoting an evaluation score into workflow
    authority.

The test must use the production schemas, validators, runner, renderers, and
transactions. The harness may provide fixture transport, fake observations,
oracles, and report formatting; it may not own a second implementation of
engine policy.

## 3. Authority decisions required before implementation

The following are missing or conflicting authority. They must be accepted or
amended before the affected implementation is safe.

### 3.1 Close the Specify IR and projection contract

F0100 and the proposed engine design currently disagree:

- Design Section 17.6 renders a top-level `## Acceptance Criteria`, while
  F0100 nests `### Acceptance Criteria` beneath
  `## User Scenarios & Testing`.
- The proposed `SpecificationIR` contains `openQuestions`/`OQ-*`, while F0100
  prohibits committed open questions in `spec.md` and routes unresolved
  specification authority through `SNN`.
- F0100 still defers the exact grammar for non-acceptance records, the Key
  Entities applicability value and provenance, the visible `EN-*` grammar, and
  ownership of functional-requirement modality.

The decision must update the governing contract and its verification together.
An implementation or golden fixture must not choose one side locally.

### 3.2 Define the exact registered Specify contracts

F0100 intentionally contains placeholders. The exact registered invocation,
operation, outcome, parameter, gate, capability, state, and workflow-policy
contracts do not exist. They must be defined before a concrete
`spec.workflow.yaml` can be valid. The YAML must remain ordinary declarative
topology. Under ADR 0005 it explicitly selects generic operations, model slots,
and bounded workflow-owned resources; it cannot contain raw operational paths,
adapters, commands, capabilities, or executable behavior.

### 3.3 Settle the fake model boundary and workflow operation bindings

F0006's catalogue, repository allowlist, fixed conditional bootstrap owner,
selected-graph requirement derivation, `LLMProviderInterface` name, and
provider-operation boundary are accepted. ADR 0005
removes route-to-slot mapping: each YAML model operation explicitly names its
repository-allowed slot and workflow-owned prompt/schema resources for
reference extraction/reconciliation, feature-brief generation,
specification-unit generation, semantic review, protocol retry, and repair.

The smallest decision for the offline milestone may authorize a test
composition to inject a fake behind the one governing narrow production port,
without a live provider or `.sddproviders.json`. That exception and the exact
workflow-operation bindings must be explicit; this finding does not create them. F0007 and
live AWS activity are not prerequisites for the first offline case.

### 3.4 Add a full-workflow harness case contract

`TEST_HARNESS.md` currently defines an operation-centric `EvalCase`: one
`modelOperationId`, one request/result schema pair, and one candidate source.
Its execution flow constructs one operation unit. It does not define a workflow ID, invocation,
reference selector, ordered multi-request fake script, terminal workflow/state
oracle, artifact/state oracle, allowed temporary-project mutation surface,
resume sequence, or source-fixture immutability check.

An accepted closed full-workflow case variant or explicit harness extension is
required. It must remain domain-neutral so later workflows can use the same
mechanism without a `specify` branch.

### 3.5 Choose the `wf-001` terminal oracle

The current reference says only that the application starts successfully and
displays `Hello, World!`. Until Specify requiredness and Key Entities
applicability are closed, it is unsafe to assume those two statements support
every mandatory specification decision.

The case must explicitly choose one of these outcomes:

- enrich the reference with sufficient business authority and expect a golden
  committed `specified` result; or
- retain the minimal reference and expect an exact `SNN` plus terminal
  `needs_user`.

Principles cannot fill the missing business authority. A fake response that
invents enough content merely to force success must be rejected.

### 3.6 Align the executable and harness command contracts

The proposed CLI is `sdd specify --reference <relative-selector>`, while the
current native artifact is named `sdde`. The harness build-step names are also
only proposals, and no per-case selector grammar exists. The accepted command
surface must settle these names without a compatibility shim inferred from the
fixture.

## 4. Current implementation baseline

| Boundary | Implemented evidence | Readiness for this goal |
| --- | --- | --- |
| Native build and packaging | Zig 0.16.0 pin, native executable, lint/test/smoke/verify build steps, clean temporary-directory smoke | Foundation exists. The smoke proves only a packaged generic no-op workflow. |
| Exact configuration | Exact-CWD `.sddtoolkit.json` location/read/decode and closed `logs`, `models.slots`, and eight-path shape | Strict provider-catalogue decoding, immutable registry construction, slot subset allowlist, and exact selected-graph provider-requirement derivation are implemented; production provider contracts and YAML-declared model-operation binding remain missing. |
| Bootstrap roots | Normalization, active-filesystem checks, root roles, separation, and root registry | Foundation exists. The named fixture has no runtime config or roots. |
| Feature logging | Policy, records, sinks, rotation, retention, recovery, and composition tests | Subsystem exists, but no Specify activation/state transaction binds it to a feature run. |
| Workflow authority | Bounded inventory/capture/YAML parse/schema validation, compiler, graph validator, and immutable ID registry | Strong generic foundation exists. The current uncommitted tests strengthen this boundary only. |
| Generic execution | Exact workflow selection, compiled transitions, owned typed invocation/value flow, declared-input views, and schema-checked delta application | Value-flow foundation exists; concrete Specify operations remain missing. |
| Registered behavior | `core.empty-invocation@1`, `core.noop@1`, and `core.capability-free@1` | A definition named `specify` would still reject `--reference` and perform no work. |
| Toolchain | Closed v1 project/preset package references, inheritance, policy composition, and safety validation | Narrow F0003 boundary exists. It does not provide Node/Vitest commands or environment facts. |
| Workflow artifact registry | Validated feature-log paths and sink binding | Logging-only; no specification, reference, clarification, workflow-state, or stage-transaction paths. |
| Specify domain | No `SpecificationIR`, reference snapshot, Specify invocation, YAML model operation, validator, renderer/parser, clarification, or commit implementation | Missing. |
| Evaluation harness | `TEST_HARNESS.md` only | No build wiring, driver, schemas, suites, reports, fake scripts, or end-to-end cases exist. |

The generic runner now retains owned, versioned native values from invocation
through subsequent steps. Its immutable views expose only declared required or
optional inputs. One shared effect validator checks writes, replacements, and
invalidations before the runner transfers ownership; malformed, cancelled, and
unapplied candidates are destroyed. Native schemas remain in the operation
registry, not project YAML. Fixed kernel bindings still have their existing
concrete typed owners and structural `DataShape` checks; this increment does
not claim that every kernel binding has migrated to the owned-value envelope.

An accepted ADR 0003 setup contract remains incomplete:

- the fixed startup orchestrator currently loads the project toolchain before
  workflow selection. ADR 0003 requires project/feature/toolchain setup beyond
  minimal startup to run only when the selected workflow graph references its
  registered setup contracts. This must be corrected at the shared ownership
  boundary, not retained as a Specify convenience.

## 5. Production work remaining, in dependency order

### 5.1 Complete the shared pipeline runtime

Owned workflow value flow is implemented, with regression coverage in
`src/pipeline_data_test.zig` and `src/workflow_value_flow_test.zig` for unrelated
YAML workflows, branch merges, schema drift, restricted inputs, replacement,
invalidation, cancellation, and allocation-failure cleanup. Remaining work:

- execute/validate registered gates and effective capability ceilings; and
- move selected target/toolchain/principle setup out of fixed startup and into
  reusable registered setup nodes selected by compiled topology.

Regression evidence must include unrelated multi-node workflows, real value
flow, branch merges, failure propagation, cancellation, cleanup, and proof that
adding an unrelated definition changes neither execution nor authority.

### 5.2 Complete deterministic feature/state foundations

- Specify invocation parsing and validation for the exact one-selector grammar;
- contained reference-selector resolution and deterministic feature identity;
- feature ownership/inventory, artifact authority, state-ID and transaction-ID
  ledgers;
- project and feature WAL, locks, failpoints, recovery, and all-or-nothing stage
  transactions;
- full workflow state and the `specifying`, clarification-pending, and
  `specified` transitions; and
- feature-log activation, recovery, flush barriers, and finalization bound to
  exact feature/run/workflow identities.

### 5.3 Implement the Markdown reference vertical slice

The first case needs at least the production Markdown reader path:

- bounded no-follow inventory and immutable capture;
- explicit status for every entry and explicit rejection of unsupported media;
- deterministic source/block/chunk identities, source maps, citations, and
  source/decoded budget accounting;
- typed claim extraction and hierarchical reconciliation;
- complete conflict, claim-disposition, passive-literal, and reference-context
  state; and
- full restart validation without a content fingerprint.

Supporting only Markdown in the first slice does not permit silently ignoring
another encountered media type.

### 5.4 Implement model, reconciliation, and repair foundations

- YAML-declared model operations and captured response-schema resources;
- deterministic request/unit identity and total attempt accounting;
- bounded guidance/context selection and production fake-model bindings;
- raw response capture, envelope decode, identity checks, and closed payload
  validation;
- one shared authority-requiredness/reconciliation ledger with earliest-owner
  routing;
- no-invention conversion to clarification;
- protocol retry, atomic repair authorization, old-value/revision checks,
  impacted validation, full validation, and exhaustion; and
- fault tests proving malformed, unsupported, stale, foreign, or exhausted
  candidates cannot reach a write or successful transition.

### 5.5 Implement the Specify domain and commit gate

- feature brief and typed specification-unit generation;
- closed `SpecificationIR`, engine-owned record IDs, ledgers, and provenance;
- complete deterministic and model-assisted validation with honest evidence
  classes;
- `S01..S99` deduplication, controlled forms, pause/resume, current-authority
  resolution, and full regeneration;
- canonical `spec.md` and `reference-context.md` renderers;
- editable-spec parser and normalized IR round trip;
- generated-view equality and tamper handling;
- the complete atomic Specify transaction; and
- success only after durable artifacts/state/evidence commit and recorded
  `specified` state.

### 5.6 Register and prove the concrete graph

Register the exact invocation, setup, reference, generation, validation,
clarification/repair, rendering, transaction, and gate implementations in both
the compiler and implementation registries. Then add one concrete
`spec.workflow.yaml` composed only from those contracts and prove that no
generic runtime module branches on `specify`.

## 6. Harness work remaining

After the production boundaries exist:

1. accept the bounded harness contract and its full-workflow case extension;
2. implement closed suite, workflow-case, fake-script, oracle, observation,
   report, and execution-policy schemas;
3. build a temporary-project constructor that copies only declared fixture
   resources into configured roots and records their exact identities;
4. build a production test composition that substitutes only the authorized
   fake model/clock/effect boundaries and still uses the common runner;
5. validate every expected artifact, canonical state, diagnostic, outcome,
   transaction, log, and allowed mutation;
6. serialize byte-stable JSON and human-readable reports;
7. add accepted offline build wiring and an optional closed per-case selector;
8. keep the harness and its resources out of the packaged native runtime; and
9. add property/fault/end-to-end tests showing evaluation data cannot construct
   workflow authority.

The first conformance-only case does not need rubric scores. If semantic quality
scoring is required, the currently empty rubric must be replaced by a tracked,
versioned closed rubric and the unresolved score scale, weights, golden data,
and release-threshold decisions must be accepted separately.

## 7. `wf-001` fixture work remaining

### 7.1 Current contents

The tracked source bundle contains:

- one sibling reference file,
  `test/evaluation/wf-001-hello-world/reference/stories.md`;
- seven Markdown principle files beneath `node-vitest/principles/`; and
- no tracked rubric file. The local empty `rubric/` directory is not durable Git
  fixture content.

It has no `.sddtoolkit.json`, workflow definition, project `toolchain.yaml`,
v1 preset package, project/environment manifest, suite/case manifest, fake or
recorded model response, expected diagnostic, golden artifact/state, or report.

### 7.2 Required synthetic-project mapping

The harness must construct a temporary project rather than use `node-vitest/`
as the working directory. In particular:

- the sibling `reference/stories.md` must be copied under a configured
  descendant reference directory; a `../reference` selector is forbidden;
- an exact project-root config and disjoint validated roots must be supplied;
- the concrete Specify definition must be supplied beneath the configured
  workflow root, never loaded from `design/`;
- the exact mechanical `principles/toolchain.yaml`, accepted fixture-owned v1
  preset packages, and any required Node project evidence must be supplied;
- semantic principle files must pass normal production inventory/capture; and
- output roots must be isolated generated locations whose mutations are
  compared against the case's closed allowed set.

The legacy `design/toolchainPresets/node-vitest.yaml` is source material, not a
valid runtime preset or fixture fallback.

### 7.3 Specify principle expectation

The Node/Vitest semantic principles must not enter specification generation and
must not cause TypeScript, Vitest, filenames, commands, or architecture choices
to appear in `spec.md`. For this case they are useful as a negative assertion:
the complete principle inventory is accounted for, but the applicable selected
principle set for Specify generation is empty.

Node/Vitest-specific positive principle compliance belongs to later plan,
tasks, or implement cases. Supporting it in Specify would require an explicit
governing design change.

## 8. Verification gates

### 8.1 Production gates

- targeted action and orchestrator tests at every owning boundary;
- accepted/rejected schema and unknown-field fixtures;
- multi-node value-flow, transition, gate, capability, and runner-delta tests;
- malformed model, no-invention, atomic repair, exhaustion, and cancellation
  tests;
- reference accounting and unsupported-reader negative tests;
- renderer/parser golden and round-trip tests;
- transaction failpoints before, during, and after every durable phase;
- end-to-end fake-model success and clarification flows; and
- clean packaged-native execution without source tree, Zig toolchain, cache,
  Node.js, provider credentials, or development-only assets.

### 8.2 `wf-001` gates

- exact CLI/config/root negative cases;
- exact workflow selection and no name-specific runtime branch;
- invalid reference preflight creates no feature artifacts;
- every reference file/block/chunk receives one terminal account;
- fake responses bind to exact request/workflow-operation/unit identities;
- the chosen `specified` or `needs_user` oracle is exact;
- Node/Vitest semantic principle selection for Specify is empty;
- invalid candidates cannot reach artifacts or workflow-state success;
- valid siblings survive atomic repair;
- rendered output and evaluation reports are byte-stable;
- only the temporary project's declared output/state/log set changes; and
- the original fixture tree remains byte-for-byte unchanged.

### 8.3 Repository verification blocker

At the reviewed snapshot:

- `zig build lint` passes;
- `zig build smoke --summary all` passes all 6 steps;
- `git diff --check` passes; and
- `zig build test --summary all` passes 181 of 182 tests, so
  `zig build verify --summary all` remains red with 17 of 20 build steps
  successful.

The sole test failure is the architecture rule requiring every
`design/features/F*.md` filename and H1 to end in `Service`. The existing
`F0006-LLMProviderInterface.md`, `F0007-AWSBedrockProvider.md`, and
`F0100-SpecWorkflow.md` violate that implemented rule. This new feature follows
the rule, but the pre-existing policy/document mismatch must be resolved under
separate authorized scope before the required full repository verification can
be green.

## 9. Completion boundary

This feature's first milestone is complete only when:

1. every Section 3 decision affecting the milestone is explicitly accepted;
2. the generic runtime carries real typed values and selected setup without a
   workflow- or fixture-specific bypass;
3. the full production Specify vertical slice passes with a fake model;
4. the harness owns a closed full-workflow case and isolated-project builder;
5. `wf-001` has one explicit terminal oracle and complete tracked inputs;
6. the case proves principle non-injection and fixture immutability;
7. targeted, architecture, schema, full unit, harness, packaging, and
   `git diff --check` validation pass; and
8. no unresolved uncertainty is represented as success.

Until then, there is no truthful exact command for running this full-workflow
evaluation.
