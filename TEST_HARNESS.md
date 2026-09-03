# SDDE Model Output Test Harness

**Status:** Proposed development-harness design

**Scope:** SDDE engine development and evaluation only. This document does not
authorize running SDDE against a target project, does not add a selectable
workflow, and does not amend or accept the proposed engine design.

**Governing authority:** [Engine design](design/design.md), especially Sections
1, 3-4, 9.4, 12-13.4, 21-22, 26-31; accepted
[ADR 0001](design/decisions/0001-zig-engine.md),
[ADR 0002](design/decisions/0002-zig-version.md), and
[ADR 0003](design/decisions/0003-generic-workflow-engine.md); and the repository
[project contract](AGENTS.md).

---

## 1. Purpose

The harness evaluates untrusted LLM candidate output produced for YAML-declared
SDDE model operations. It must answer two different questions without
conflating them:

1. Does the candidate satisfy every mechanically decidable engine contract?
2. How well does a mechanically valid candidate satisfy the supplied semantic
   authority, including the exact applicable project principles?

The first question is answered only by canonical engine schemas, validators,
and executable evidence. The second may use a versioned rubric with human or
model-assisted judgment. A rubric result is evaluation data only. It can never
authorize a workflow transition, repair, file operation, command, approval,
evidence record, task completion, or successful terminal outcome.

The harness is intended to support:

- recorded-response regression tests;
- fake-model end-to-end tests;
- optional live-provider evaluation;
- comparison of model slots, workflow-owned guidance, and workflow versions;
- principle-injection conformance;
- multiple development languages, test frameworks, and mixed-language
  repositories;
- evaluation of initial generation, clarification, semantic review, and atomic
  repair behavior.

## 2. Non-goals

The harness does not:

- make LLM output deterministic;
- replace canonical validators with rubric prose;
- treat an LLM judge as deterministic proof;
- permit a principle to add a path, command, dependency, parser, file
  capability, or workflow capability;
- execute model-supplied commands;
- load runtime authority from `design/` examples or test fixtures;
- become a production `sdd eval` command without a separately accepted design
  decision;
- add language-, framework-, workflow-operation-, filename-, model-, or fixture-specific
  continuation rules to the shared harness;
- weaken a schema, validator, stage gate, authority-reconciliation rule, or test
  to improve an evaluation score.

## 3. Placement and packaging

The harness is development-only and lives outside `src/`:

```text
sdde/
├── TEST_HARNESS.md
├── src/                         # production engine contracts and behavior
├── build/
│   └── evaluation.zig           # proposed build-step wiring
├── test/
│   └── evaluation/
│       ├── harness.zig          # evaluation driver
│       ├── schemas/             # closed harness-only schemas
│       ├── suites/              # versioned evaluation manifests
│       ├── rubrics/             # versioned semantic rubrics
│       ├── fixtures/            # synthetic projects and recorded envelopes
│       ├── judges/              # human and optional model-judge adapters
│       ├── properties/          # scorer and invariant properties
│       └── end_to_end/          # fake/live-provider harness tests
└── zig-out/
    └── evaluation/              # generated reports, not canonical source
```

Compiled workflow resource schemas, model-envelope decoding, request identity, principle
capture and selection, diagnostics, authority reconciliation, path policy,
command policy, and stage validators remain owned by `src/`. The harness imports
and exercises those owners. It must not copy or reinterpret their policy under
`test/evaluation/`.

Evaluation fixtures must not be placed beneath configured runtime roots such as
`paths.workflows`, `paths.references`, or `paths.specs`. Harness resources are
not packaged runtime assets and are never a source-tree fallback for the native
executable.

## 4. Authority boundary

The harness separates three evidence classes:

| Evaluation layer | Owner | Result authority |
| --- | --- | --- |
| Deterministic conformance | Canonical engine schemas, validators, graphs, parsers, and command evidence | Hard accepted/rejected evaluation result |
| Semantic rubric | Human reviewer or closed model-assisted judge | Non-authoritative quality observation |
| Release decision | Explicit repository evaluation policy and authorized human/CI process | Development release decision only |

A candidate rejected by deterministic conformance is not semantically scored as
passing. Its semantic result is `not_evaluated`, and the report retains the
canonical diagnostics.

A model-assisted score cannot be converted into deterministic evidence. A high
score cannot override a missing authority, invalid path, unknown command,
schema failure, failed executable check, or blocking diagnostic.

## 5. Principle injection

### 5.1 Required behavior

Different testing languages, frameworks, styles, and expectations may be
expressed by the principles supplied to an evaluation case. The harness must
inject those principles through the same production capture, validation,
registry, applicability-selection, and guidance-building path used by the
engine. It must not concatenate arbitrary fixture prose directly into a prompt.

An integration evaluation case supplies a synthetic project fixture containing
the exact principle inputs. The harness then:

1. inventories the complete fixture principles root;
2. excludes exact mechanical `toolchain.yaml` from semantic capture;
3. validates and normalizes eligible Markdown principle sources;
4. builds the canonical principle registry;
5. selects the bounded principles applicable to the exact stage, compiled workflow operation, project,
   environment, and file kind;
6. builds model guidance using the production guidance action;
7. records the exact selected principle record IDs and source spans;
8. invokes the fake, recorded, or live model through `LLMProviderInterface`;
9. validates the returned candidate through the normal engine boundary; and
10. evaluates semantic compliance only against the exact selected principles.

Action unit tests may begin from an already validated principle registry when
that is the declared input boundary. End-to-end harness tests must exercise the
complete capture and selection path.

### 5.2 Stage restrictions

Semantic principles apply only where the governing design permits them. The
initial suite selects them for plan, tasks, implement, recovery, and
clarification-resume boundaries. They do not enter specification generation
and cannot invent specification requirements.

An evaluation case that requests principle injection into a workflow operation that forbids it is
invalid harness input. Supporting a new stage requires an explicit governing
design change before the harness or engine is changed.

### 5.3 Semantic and mechanical separation

A semantic principle may require or prefer:

- a testing language;
- a testing framework;
- unit, integration, contract, or end-to-end testing;
- Given/When/Then or Arrange/Act/Assert organization;
- naming, mocking, isolation, and coverage practices;
- architectural or maintainability constraints.

The validated toolchain remains the mechanical authority. It must independently
provide the relevant environment, file-kind policy, parser, placement rules,
and named command capabilities. A principle cannot create those capabilities.

For example, a principle may require TypeScript and Vitest. The resolved
toolchain must still authorize TypeScript test files and expose a registered
Vitest command ID. If the principle and toolchain cannot be reconciled, the
expected outcome is a typed clarification, upstream rework, environment failure,
or administrative block according to the owning contract. The harness must not
install a tool, invent a command, choose a nearest framework, or silently ignore
the principle.

### 5.4 Principle matrix evaluation

The same base case may be evaluated with multiple principle bundles:

```text
login-tests
├── typescript-vitest
│   └── expected semantic choice: TypeScript using Vitest conventions
├── javascript-jest
│   └── expected semantic choice: JavaScript using Jest conventions
└── java-junit
    └── expected semantic choice: Java using JUnit conventions
```

Each matrix entry is a distinct case identity with its exact principle registry
and toolchain authority. Results must not be compared as if only the model had
changed when their injected authority differs.

## 6. Multiple-language support

The harness core is language-neutral Zig code. Language and framework behavior
is contributed by validated toolchain policy, registered parsers and commands,
principle inputs, and fixtures. The harness must not contain a shared-core branch
such as `if language == java`.

Initial suites should cover the environments required by the governing design:

```text
test/evaluation/suites/
├── react-typescript/
├── node-javascript/
├── node-typescript/
├── java-maven/
├── java-gradle/
├── dotnet/
└── mixed-monorepo/
```

A case binds every actionable file to exactly one environment and project. A
mixed-language repository may run several environment-specific observations,
followed by aggregate repository checks. Cross-environment ambiguity is a hard
failure, not a rubric judgment.

Adding another language requires:

- an accepted validated toolchain composition;
- registered file-kind, placement, parser, and command policies;
- accepted and rejected fixtures;
- relevant principle fixtures;
- deterministic validator tests;
- semantic rubric coverage where language-specific judgment is genuinely
  required.

A missing compiler, runtime, parser, or configured command is reported as an
environment capability failure. It is not reported as poor model quality.

## 7. Evaluation contracts

All harness inputs and persisted reports use versioned closed schemas that
reject unknown fields and unsupported versions.

### 7.1 Evaluation suite

```text
EvalSuite {
  schemaVersion,
  suiteId,
  compiledWorkflowAuthorityId,
  cases: EvalCase[],
  rubricRegistryVersion,
  comparisonPolicyId?,
  executionPolicyId
}
```

### 7.2 Evaluation case

```text
EvalCase {
  caseId,
  modelOperationId,
  requestSchemaId,
  resultSchemaId,
  projectFixtureId,
  environmentExpectation,
  toolchainFixtureId,
  principleBundleId?,
  expectedApplicablePrincipleIds[],
  candidateSource:
    recorded | fake_model | live_model,
  expectedConformance,
  rubricId?,
  tags[]
}
```

Case data uses engine-owned IDs and validated fixture capabilities. It does not
supply raw operational paths or commands to a model.

### 7.3 Rubric

```text
Rubric {
  schemaVersion,
  rubricId,
  applicableModelOperationIds[],
  criteria: RubricCriterion[]
}

RubricCriterion {
  criterionId,
  description,
  judgeKind: human | model_assisted,
  weight,
  scale,
  anchors[],
  requiredCitationKinds[],
  insufficientEvidenceAllowed
}
```

Mechanically decidable requirements are not duplicated as rubric criteria.
Rubric criteria cover semantic properties such as groundedness, ambiguity,
testability, completeness, minimality, task sizing, and intent conformance.

Principle compliance criteria bind an exact selected principle record and span:

```text
PrincipleComplianceCriterion {
  principleRecordId,
  sourceSpan,
  applicableUnitOwnerId,
  expectedDisposition: required | preferred | prohibited,
  judgeKind: human | model_assisted
}
```

### 7.4 Observation and report

```text
EvalObservation {
  caseId,
  sampleOrdinal,
  requestIdentity,
  selectedPrincipleEvidence[],
  conformance: accepted | rejected,
  diagnostics[],
  executableEvidence[],
  semanticResult:
    not_evaluated | evaluated,
  criterionResults[],
  usage?,
  duration?
}

EvalRunReport {
  schemaVersion,
  runId,
  suiteId,
  compiledWorkflowAuthorityId,
  rubricRegistryVersion,
  executionPolicyId,
  observations[],
  aggregateResults,
  baselineComparison?
}
```

Raw provider output is retained only according to the evaluation execution
policy. Secrets and opted-out prompt bodies must never enter committed fixtures
or reports.

## 8. Execution flow

For each case, the harness performs the following closed flow:

1. Decode and validate the evaluation suite and case.
2. Construct the isolated synthetic project and configured roots.
3. Capture and validate its toolchain and principle authorities.
4. Resolve the expected environment and project exactly once.
5. Construct the workflow-declared model-operation unit through the production test composition.
6. Select context, principles, and guidance using production actions.
7. Build the provider-neutral request and deterministic request identity.
8. Obtain one recorded, fake, or live provider response.
9. Decode the response envelope and apply canonical schema and identity checks.
10. Apply workflow-operation, authority, path, graph, repair, and stage validators as
    applicable.
11. Run only authorized named commands when the case and execution policy permit
    executable checks.
12. Stop with `semanticResult = not_evaluated` when conformance rejects.
13. Evaluate a conforming candidate with the selected rubric.
14. Validate every human or model-assisted criterion result.
15. Aggregate observations without converting scores into engine evidence.
16. Serialize canonical JSON and render a human-readable report under
    `zig-out/evaluation/`.

The harness drives production nodes through the common runner and test
composition bindings. It does not directly invoke hidden successor nodes or
apply node deltas itself.

## 9. Model-assisted judging

An optional LLM judge receives one bounded evaluation unit, the exact rubric
criterion, the candidate fields needed for that criterion, and the allowed
authority/principle citations. It receives no filesystem, process, state,
transaction, logger, completion, or unrestricted tool capability.

Its response uses a harness-only closed schema containing:

- criterion ID;
- score or `insufficient_evidence`;
- one bounded rationale;
- exact candidate and authority citations;
- no pass/fail authority, repair instruction, path, command, or state field.

The harness must:

- validate the judge response as untrusted candidate data;
- reject missing, stale, foreign, or fabricated citations;
- blind generator model/provider identity during comparative judging;
- prefer a judge model different from the generator when configured;
- calibrate model-assisted judgments against a human-labelled golden set;
- report human/judge disagreement rather than averaging it away;
- defend against candidate text attempting to instruct the judge;
- keep judge retries and token/cost ceilings bounded.

Model-assisted judgment is optional. Recorded deterministic tests and human
ratings must remain usable without provider credentials or network access.

## 10. Metrics and comparison

Reports keep deterministic and semantic measures separate. Useful measures
include:

- closed-schema and request-identity pass rate;
- deterministic validator pass rate;
- unsupported-invention and correct-clarification rate;
- initial-pass and post-repair acceptance rate;
- repair attempts per accepted unit;
- principle-selection accuracy;
- semantic score by criterion and principle bundle;
- executable check pass rate;
- environment capability failure rate;
- token use, latency, and configured cost estimate;
- baseline delta and worst-case regression.

Recorded cases produce byte-stable reports from the same normalized inputs and
accepted structured observations. Live model runs are probabilistic. They use
multiple samples where required and report pass rate, median, dispersion, and
worst case rather than claiming exact reproducibility.

Thresholds, required sample counts, comparison tolerances, and release-blocking
policy require explicit acceptance. The harness must not infer them from a
single model, fixture, or motivating example.

## 11. Test strategy

### 11.1 Contract tests

- reject unknown fields, missing required fields, and unsupported versions;
- reject foreign workflow-operation, request, result, principle, project, and environment
  identities;
- reject invalid rubric weights, score ranges, duplicate criterion IDs, and
  incomplete citation bindings;
- reject raw operational paths and commands in evaluation inputs.

### 11.2 Principle-injection tests

- inject exactly the applicable validated principle records;
- do not inject irrelevant categories or unselected project principles;
- exclude exact mechanical `toolchain.yaml` from semantic guidance;
- reject principle injection into prohibited stages;
- prove filename categories are hints rather than semantic authority;
- detect conflicting or unsupported principles without selecting a default;
- prove principles cannot add paths, commands, dependencies, file capabilities,
  or workflow capabilities;
- prove changing one principle bundle changes only its intended semantic
  expectations;
- cover unrelated principle kinds so no fixture-specific continuation is
  introduced.

### 11.3 Multiple-language tests

- accepted and rejected React/TypeScript, Node JavaScript, Node TypeScript,
  Maven Java, Gradle Java, and .NET cases;
- mixed-language and multi-project repositories;
- zero and multiple environment owners;
- missing compiler/parser/runtime as environment failure;
- framework requested by a principle but unavailable in the toolchain;
- file placement, naming, package/project ownership, and command capability;
- identical shared harness behavior across unrelated languages.

### 11.4 Scoring properties

- stable ordering and aggregation for recorded observations;
- no invalid or unevaluated candidate can receive an overall pass;
- no missing criterion is silently treated as zero or success;
- weights cannot overflow, produce NaN, or escape their configured scale;
- adding an unrelated case does not change another case's result;
- evaluation data cannot construct runner evidence or workflow state.

### 11.5 Fault injection

- malformed generator and judge JSON;
- wrong request, workflow-operation, criterion, or diagnostic identity;
- extra schema fields and out-of-range scores;
- fabricated, stale, or out-of-unit citations;
- prompt injection embedded in candidate prose or code;
- repeated identical invalid repairs;
- provider timeout, truncation, and retry exhaustion;
- secrets in prompt, response, diagnostic, and report fields;
- attempted model path, command, status, approval, or completion claims.

### 11.6 End to end

- fake generator plus deterministic validators;
- fake generator plus fake judge;
- recorded response plus human-labelled rubric;
- principle matrix over the same base case;
- malformed output unable to reach semantic scoring;
- clarification instead of invention;
- atomic repair retaining valid sibling units;
- report generation without network, credentials, source fallback, or target
  project access.

Live-provider evaluation is added only after the equivalent fake and recorded
tests pass.

## 12. Security, privacy, and operational limits

- Live evaluation is disabled by default and requires an explicit build step.
- Provider credentials are obtained only by the authorized provider adapter and
  never stored in fixtures or reports.
- Prompt/response capture follows the same direction/class opt-in, redaction,
  truncation, and retention rules as engine observability.
- Model-generated commands are never executed. Only named toolchain command IDs
  may run with structured executable and argument descriptors.
- Working directory, environment, network, timeout, resources, and expected
  side effects are explicit and bounded.
- Synthetic project roots are isolated temporary directories with validated
  containment and cleanup.
- Evaluation reports are non-authoritative generated artifacts.
- Real target-project material is not captured into committed fixtures without
  separate explicit authorization and sanitization.

## 13. Proposed build integration

Once implemented, the repository may expose these build steps:

```text
zig build eval-fixtures   # deterministic offline suites
zig build eval-report     # render a validated existing result
zig build eval-live       # explicit networked provider evaluation
```

These commands are proposed names and do not exist yet. The offline fixture
suite may join `zig build verify` only after its contracts and runtime are
implemented and accepted. Live evaluation must not be part of ordinary
deterministic verification because it requires credentials, cost, network
access, and probabilistic provider behavior.

Adding a production or development dependency requires the explicit approval
required by the project contract.

## 14. Delivery sequence

1. Accept or amend this bounded harness contract and its unresolved policy
   choices.
2. Implement the common production model-envelope, YAML workflow-operation,
   workflow-resource, diagnostic, principle-registry, guidance, and fake-model
   boundary foundations.
3. Implement closed harness schemas and offline evaluation over recorded
   candidates.
4. Reuse the canonical deterministic validators and add hard conformance
   reports.
5. Add principle-selection and principle-matrix fixtures.
6. Add human-labelled rubrics and scoring properties.
7. Add optional model-assisted judging and calibration.
8. Add suites alongside each model operation declared by specify, plan, tasks, and
   implement.
9. Add explicit live-provider comparison only after fake and recorded suites
   pass.

The harness must remain usable with a fake `LLMProviderInterface` before any real
provider is integrated.

## 15. Acceptance criteria

The harness is complete when:

1. It lives outside production `src/` and is absent from the packaged native
   runtime.
2. It exercises canonical engine schemas, principle selection, validators, and
   runner paths without duplicating their policy.
3. Every candidate receives deterministic conformance before semantic scoring.
4. A rubric or judge result cannot alter workflow evidence, state, repair,
   approval, command execution, or completion.
5. Principle fixtures pass through the production capture and selection path,
   and the report records the exact selected principle evidence.
6. Different principle bundles can require different testing languages or
   styles while the toolchain independently proves mechanical support.
7. Unsupported principle/toolchain combinations clarify, rework, or block; they
   never default or approximate.
8. React/TypeScript, Node JavaScript/TypeScript, Maven/Gradle Java, .NET, and a
   mixed-language repository have accepted and rejected suites.
9. Recorded observations produce stable canonical reports.
10. Live results are represented statistically and never labelled deterministic.
11. Human and model-assisted findings retain their real evidence class and exact
    citations.
12. Malformed, adversarial, out-of-scope, and retry-exhausted outputs cannot
    reach a write, command, stage transition, or successful evaluation result.
13. Offline suites pass without provider credentials, network access, target
    project access, source-tree runtime fallback, or development-only packaged
    assets.

## 16. Decisions required before implementation

The following choices are intentionally not accepted by this proposal:

- rubric score scales and weights;
- release-blocking thresholds and statistical tolerances;
- live sample counts and cost ceilings;
- provider retention policy for evaluation content;
- the first human-labelled golden dataset;
- whether live evaluation is local-only or also scheduled in CI;
- any future production `sdd eval` interface;
- languages beyond the initial design-required environment set.

These choices must be accepted explicitly or supplied as bounded task
acceptance criteria. The implementation must not infer them from examples.
