# Project contract

This file binds every coding agent in this repository. Tool-specific files, such as
`CLAUDE.md`, may add to it; they never restate, relax or outrank it.

## Purpose

SDDE is a deterministic, single-executable Zig engine that loads, validates and runs
closed declarative workflows from the configured `paths.workflows` root.

- The initial suite, `specify -> plan -> tasks -> implement`, is four workflow
  definitions, not a fixed registry. Projects never supply code or capabilities.
- Every LLM response is untrusted candidate data. Deterministic code, closed
  schemas, validators, validated publication, evidence and explicit human approvals
  own workflow authority.

## Repository role

This repository develops the engine, which will later run specify, plan, tasks,
implement, drift and audit against target projects. A request to build, fix, test
or document the engine never authorizes running it. Running it needs a named target
project and workflow.

## Commands

Use Zig **0.16.0** exactly ([.zigversion](.zigversion)). Build and test only
through `build.zig` steps; `zig build --help` lists them.

| Purpose | Command |
| --- | --- |
| Format and AST check | `zig build lint` |
| Unit tests | `zig build test` |
| Layer and authority boundaries | `zig build test-architecture` |
| One owning boundary | `zig build test-<area>` |
| Offline integration scenarios | `./scripts/test-integration.sh` |
| Packaged executable in a clean directory | `zig build smoke` |
| Complete offline verification | `zig build verify` |

None of these makes a model call. These do, or run the engine, and each run needs
explicit user approval naming the case or target project: `zig build run`,
`e2e-spec`, `e2e-call`, `evaluate-spec`, `provider-compatibility`, `baseline`, the
matching `scripts/*.sh` launchers and any `zig-out/bin/` binary. Never read, print,
source, copy or edit `.env.e2e`; the launchers load it.

## Repository map

- `src/` layers (domain, ports, actions, application, adapters, composition) are
  enforced by `src/architecture_test.zig`
  ([29-package-structure.md](design/contracts/29-package-structure.md)).
- `test/integration/` and `test/harness/`: offline scenarios and the E2E harness.
  `test/e2e/`: live cases.
- `design/contracts/`: detail for each design section. `design/decisions/`: ADRs.
- [fixes/README.md](fixes/README.md) names the active fix record.

## Current project state

- [design/design.md](design/design.md) is **Proposed design**; keep that status
  until the user accepts or amends it. Accepted ADRs amend it, indexed in §32.
  Cross-cutting: [0001](design/decisions/0001-zig-engine.md) native Zig,
  [0003](design/decisions/0003-generic-workflow-engine.md) generic engine,
  [0009](design/decisions/0009-atomic-workflow-execution.md) atomic execution,
  [0010](design/decisions/0010-explicit-feature-directory.md) feature directory,
  [0011](design/decisions/0011-provider-owned-request-limits.md) provider-owned
  limits.
- [ADR 0034](design/decisions/0034-spec-quality-gate.md): no Plan, Tasks or
  Implement work until the user declares the Spec quality gate passed. If asked to
  start it, report the gate.
- `design/code.md` samples are illustrative. `design/templates/`,
  `design/toolchainPresets/` and `design/examples/` are source material, never
  runtime configuration or fallback. Diagrams stay `.md` with a `mermaid` fence.
- Never silently promote a proposal, example, template or TODO to authority.

## Project authority

Precedence, highest first:

1. Explicit user-approved decisions and the accepted engine constitution.
2. Non-negotiable invariants ([design.md §3.3](design/design.md)).
3. The rest of `design/design.md`, as amended by accepted ADRs.
4. The current task's acceptance criteria and scope.
5. `design/code.md`, diagrams, examples and templates.

An implementation request never relaxes an invariant. When the user authorizes a
design change, update the decision and its tests with the code. If sources
conflict, a decision is missing, or the fix needs an unapproved architecture change,
stop and report the missing authority, the affected sections, why a local reading
is unsafe, and the smallest decision that unblocks the work. Never choose a
convenient local interpretation.

## Design-reading routes

Read the executive summary, goals and invariants, and the applicable acceptance
criteria, then only the sections for the work area. Section *N* is detailed in
`design/contracts/NN-*.md`; the §13 catalogue is in `design/contracts/actions/`.

| Work area | Design sections |
| --- | --- |
| Any engine implementation | 1, 3, 4, 30; applicable items in 31 |
| Pipeline-node/runtime contracts | 5-7; code samples 1-6, 24 |
| Configuration/principles/presets | 9-11, 15; code samples 14-21, 25 |
| Model routes/context | 12-13.4, 21; code samples 22-24 |
| Specify / Plan / Tasks / Implement | 17 / 18 / 19 / 20 |
| Validation and repair | 21-22; code samples 13, 28-30 |
| Rendering/editability | 23 |
| State, invalidation, recovery | 24; code samples 31-33 |
| Publication/filesystem | 23.2, 25 |
| Security and command safety | 26 |
| Observability | 27; code sample 34 |
| Testing / Package structure | 28 / 29; code sample 35 |

## Work authorization

- Answer, review, explain, diagnose and plan requests are read-only.
- Build, change, implement and fix requests authorize in-scope local edits and
  non-destructive validation.
- Change accepted design, ADRs, invariants, agent-instruction files, CI or security
  policy only when the task explicitly includes it.
- Get explicit approval before changing a production dependency, publishing,
  writing externally, acting destructively or materially expanding scope.
- Never stage, commit or push unless the user asks.
- Preserve existing user changes; make no unrelated edits in a dirty worktree.

## Before editing

For a code, schema, configuration, test or architecture change, state:

1. The observable outcome and non-goals.
2. The abstraction that owns the behaviour.
3. The governing design sections, invariants and acceptance criteria, cited.
4. Every producer, consumer, transition and sibling implementation, inspected.
5. Effects on persistence, security, packaging or recovery.
6. The causal defect or planned contract change.
7. Expected files, tests, validation and approvals.

A small non-semantic documentation fix needs none of this.

## Root-cause and change rules

- Fix at the lowest abstraction that owns the violated contract, with a regression
  test there. Prefer the smallest architecturally complete change.
- Give each module, type, function, action, orchestrator, adapter and port one
  reason to change. An unplanned second component is scope rework, not a patch.
- Reuse the canonical validator, normalizer, transition, renderer or policy owner.
- Change canonical state or sources, then regenerate projections.
- Parse every external, persisted, configuration and model value through a closed
  schema. Use typed or opaque IDs and capabilities, not raw strings or loose
  booleans; make illegal states unrepresentable where practical.
- Keep side effects behind narrow declared ports.
- Delete superseded code, flags, schemas, tests, fixtures and docs in the same
  change. No compatibility shims, aliases, migrations, dual readers or writers,
  deprecated entry points or fallbacks.

## Anti-overfitting rule

- Never fix a cross-cutting invariant with a branch for one caller, workflow,
  domain, format, framework, token, filename, fixture, example or model wording. The
  owner is the narrowest shared contract covering the whole failure class.
- Name the violated invariant and inspect everything it governs, including
  validators, repair and recovery paths; change shared contracts across stages.
- Domain components contribute typed facts or evidence to shared mechanisms; they
  never add their own continuation, fallback, clarification or success rules.
- A special case needs accepted authority, explicit typed policy, provenance,
  negative tests and approval.
- Test the reported example and unrelated members of the same failure class. If the
  owning contract is unclear, ask for the decision.

## Model output, prompts and evidence

- Deterministic code computes only what it can compute reliably: structure, IDs,
  links, schemas and exact source bytes. It never judges the meaning of prose with
  word lists, phrase rules or punctuation heuristics, and no test enumerates model
  phrasing.
- Prompts and model-facing guidance state the task. Each instruction has one owner;
  prompts carry no engine vocabulary, restated engine-enforced rules or case-specific
  wording.
- A model limitation under a coherent contract is a valid result; report it. Never
  work around it with case-, field- or model-specific rules, sampling changes, extra
  retries, a second model or a weaker admission rule. The recorded exceptions are the
  standalone evaluator's one mechanical correction (harness only, user decision of
  18 October 2026), the §22.6 normalization of a malformed response opening (ADR 0014;
  user decisions of 21 September and 18 October 2026) and ADR 0039's single runaway
  re-send (user decision of 26 October 2026); report runaways, re-sends and
  normalizations separately.
- Decide a rule, prompt or contract change on both development cases, with repeated
  runs on one committed build; a single run never decides it. Never tune on the
  sixteen reserved qualification features. Count budget-stopped, malformed and
  exhausted runs as attempted workloads.
- Report separately: implementation complete, mechanical checks passed, semantic
  benefit demonstrated, brittleness reduced, scope qualified. Finding-type accuracy is
  the share of review findings whose type matches a frozen, source-based label; a real
  defect reported with the wrong type is a harmful diagnosis.

## Non-negotiable engine boundaries

The full list is [design.md §3.3](design/design.md). The core rules:

### LLM boundary

- A model receives bounded data and guidance, never a filesystem, process, state,
  logging, transaction, completion or open tool capability.
- Its output never chooses a workflow-artifact path; its commands never run; its
  claims (valid, passed, approved, completed) change no state.
- Unsupported assertions become typed clarification or failure, never inventions.
  Model-assisted review is never labelled deterministic proof.

### Actions, orchestrators, and runner

- An action has one verb-object responsibility, receives only the ports it needs,
  never invokes an action or orchestrator, and never picks its successor. A stage
  action is one deterministic sequence of single-responsibility functions, each
  given only its port ([ADR 0031](design/decisions/0031-stage-actions.md)).
- An orchestrator, including the generic workflow engine, coordinates runner-owned
  child bindings, branches only on typed outcomes, and does no I/O, parsing,
  rendering, validation, logging, state or transaction work.
- Only the runner applies node deltas and executes nodes. Capability-free runtimes
  stay capability-free.
- A fixed engine sequence such as startup becomes an engine routine
  ([ADR 0032](design/decisions/0032-engine-routines.md)): typed single-purpose
  functions, each with only its port, callable only by the callers ADR 0032 names.
- Only the composition root builds adapters, binds nodes and assembles startup,
  which projects cannot author or select and which has no transaction lock. Only
  the compiler builds workflow graphs, from validated definitions and registered
  contracts. Domain code imports no infrastructure.

### Paths and commands

- Validate every model-proposed path before use. Persisted paths are normalized and
  repository-relative, and each maps to exactly one environment, project, file kind
  and operation. Tasks use approved file IDs.
- Only named configuration or preset command IDs run, as structured descriptors
  through a shell-disabled adapter, with explicit working directory, environment,
  network, resources, timeout and side effects.

### Workflow, repair, and persistence

- Enforce the SDD suite's order through predecessor gates (not on other
  workflows), revalidate predecessors at every gate, bind approvals to exact state
  IDs, and let upstream changes invalidate downstream authority.
- Repair only the engine-selected unit, with old-value and revision preconditions,
  then run impacted and full validation. Retry exhaustion fails; it never weakens
  policy.
- Candidate changes stay in memory until authorized. A task completes only in
  successful whole-workflow output, after everything validates and every write
  succeeds; nothing is committed or resumed per task.
- Keep failed, blocked, cancelled and completed distinct. Never import generated
  views as authority. Identical input and payload render byte-identical output.

## Prohibited shortcuts

Beyond the rules above, do not introduce:

- unbounded `anytype` or `anyopaque` at domain or trust boundaries, unjustified
  casts, `@constCast`, undefined reads, ignored errors or missing cleanup;
- skipped or focused tests, weakened assertions, or any schema, validator, type,
  lint, architecture or test weakened to make a task pass;
- capability bags, service locators, dispatcher callbacks or hidden node execution;
- a success transition that discards a failure;
- concurrency before overlay, lock, resource-conflict and failpoint tests pass.

A genuine exception is an explicit decision with a narrow contract, negative tests
and approval.

## Zig implementation expectations

- Change the compiler pin, libraries, linking or platform matrix only by recorded
  decision.
- Use tagged unions with exhaustive `switch` for every closed variant set.
- Configuration parses into the single unversioned closed contract, rejecting
  unknown fields; other bytes parse into closed contracts with version checks.
- Keep raw, parsed, normalized, validated, approved and committed types separate,
  with distinct wrappers for IDs, paths, approvals, commands, evidence and
  capabilities.
- Make ownership explicit: borrowed slices never outlive owners; `deinit`, `defer`
  and `errdefer` clean up on every path.
- Expected rejections are typed outcomes; operational failures are error unions;
  neither is collapsed into success.
- Filesystem, process, network, C ABI and provider access stay in adapters.

## Testing expectations

- Actions: unit tests with fake ports; stage actions also test each function.
  Orchestrators: spy child-binding tests. Routines: fake-port tests plus each step.
- Contracts: accepted and rejected fixtures, unknown fields and version mismatch.
  Every policy needs accepted and rejected cases; coverage alone proves nothing.
- Properties and fault injection: paths, DAGs, transitions, repairs, rendering,
  publication writes, interruption, stale approval and retry exhaustion.
- Unit and integration tests are not E2E evidence. Keep the harnesses separate;
  live E2E needs a named case and explicit user approval before each run.
- E2E runs the full production path with the real configured LLM. Nothing scripted
  substitutes; if it cannot finish, report the unmet criteria.
- No model grades an E2E run. Acceptance comes only from a human-written
  `human-spec-adjudication/v2` record applied with `zig build adjudicate-spec`; never
  write that record or present advisory analysis as acceptance. Write analysis only
  under the Git-ignored `evaluations/`; run directories under `zig-out/` are
  immutable evidence.
- When packaging or runtime behaviour changes, run the packaged executable from a
  clean directory (`zig build smoke`).

## Validation

1. `git diff --check` on changed text.
2. Targeted `zig build test-<area>` while iterating.
3. `zig build lint` and `zig build test-architecture`.
4. `zig build verify` before completing cross-cutting work (includes smoke tests).

Before asking to commit a code change, run its targeted tests and `zig build verify`
on the exact tree being committed, and report the results. Never ask to commit
while a test fails or has not run.

Never claim a check ran when it did not. If one cannot run, say why, run the
strongest safe substitute and disclose the gap. Never weaken a judge to pass.

## Definition of done

The outcome and acceptance criteria are met; invariants hold; regression and
negative tests exist at the owning boundary; targeted and full checks pass; the
whole diff is reviewed for scope creep, duplicated policy, fallbacks, bypasses and
weakened validation; packaging and generated artifacts are checked when affected;
docs, ADRs and traceability follow contract changes. The final report names changed
contracts and files, tests, exact commands and results, open uncertainty and
approved deviations.

## Code review rules

| Flag | Safe path |
| --- | --- |
| **Symptom patch:** one caller fixed, owning contract still invalid | Repair the owning abstraction with its regression test |
| **Capability leak:** an orchestrator gains an operation, or an action gains child execution | A single-responsibility action, or an ADR 0032 routine, reached through a runner-owned binding |
| **Policy weakening:** a schema, validator, path rule, gate, repair boundary, test or architecture rule loosened for one case | Explicit typed policy with accepted and rejected tests |
| **Authority bypass:** raw model paths or commands, generated-view authority, stale approvals, completion without evidence | The engine's typed validation, approval and publication flow |
| **Packaged-executable regression:** source-relative, current-directory, dynamic-loading or unpackaged-asset assumptions | Explicit asset and configuration ownership, proven by the clean-directory test |
| **Prose heuristic:** a word, phrase or punctuation rule over model output, or a prompt patched after one run | Report the model limitation, or change a structural contract decided on repeated runs |

## Instruction maintenance

Keep this file short and repository-wide; enforce what you can in types, tests and
CI. Change it only for a durable requirement or a measured repeated failure, state
each rule once, and start a new agent session after editing it.
