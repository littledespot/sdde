# Project contract

## Purpose

Build a deterministic Zig native single-executable workflow engine that loads,
validates, and executes closed declarative workflows from the configured
`paths.workflows` root.

The initial SDD workflow suite implements the feature flow:

**specify -> plan -> tasks -> implement**

Those four names are workflow definitions, not a fixed engine registry. The
workflow root may contain any bounded number of definitions. The generic engine
may execute any validated definition composed from registered pipeline-node
contracts; project definitions never supply executable code or capabilities.

The engine treats every LLM response as untrusted candidate data. Deterministic
code, closed schemas, validators, transactions, executable evidence, and
explicit human approvals own workflow authority.

## Repository role

This repository is the development workspace for the SDDE engine. Work in this
folder builds, tests, packages, or documents the engine itself.

The completed engine will run code-producing and code-governance workflows
against target projects, including **specify, plan, tasks, implement, drift,
and audit**.

Keep these two contexts distinct:

- **Engine development** changes SDDE in this repository.
- **Engine execution** runs SDDE against an explicitly identified target
  project to produce, inspect, or change that project's code and artifacts.

Do not confuse building the SDDE engine with using SDDE to produce project
code. A request to build, fix, test, or document the engine does not authorize
running it against a target project. A request to use the engine must identify
the target project and workflow explicitly.

## Current project state

- **design/design.md** is the governing implementation baseline, but it is
  currently marked **Proposed design**. Preserve that status until the user
  explicitly accepts or amends it.
- **design/code.md** contains contract and data-shape samples. Treat those
  samples as illustrative unless the governing design explicitly makes a
  contract normative.
- Files beneath **design/principles/** are templates/source material, not an
  instantiated constitution for this engine.
- Files beneath **design/toolchainPresets/** and
  **design/.sddtoolkit.json.example** are source examples, not automatic runtime
  configuration or fallback data.
- **CODEX_TODO.md** does not currently exist. If one is introduced, it is only
  the guardrail implementation plan and progress checklist; it does not
  override the governing design.
- **design/decisions/0001-zig-engine.md** records the accepted implementation
  language and distribution decision: the engine is written in Zig and built
  as a native executable. TypeScript, Node.js, and Node SEA are not engine
  implementation or packaging technologies. JavaScript/TypeScript and Node
  presets remain valid policies for target projects.
- **design/decisions/0003-generic-workflow-engine.md** records the accepted
  workflow-runtime decision: definitions are discovered beneath
  `paths.workflows`, compiled from registered pipeline-node contracts, and
  executed by the generic engine. The four initial SDD workflows retain their
  domain predecessor gates but do not define the registry cardinality.

Do not silently convert a proposed decision, example, template, or TODO into
accepted project authority.

## Project authority

Within repository sources, use this order:

1. Explicit user-approved project decisions and accepted engine constitution.
2. Non-negotiable invariants in **design/design.md**.
3. The remainder of **design/design.md**, as amended by accepted ADRs that name
   what they supersede.
4. Current task acceptance criteria and explicit scope.
5. **design/code.md**, diagrams, examples, and templates.

An ordinary implementation request does not relax an invariant. A user may
explicitly authorize a design change; when that happens, update the governing
decision and its tests before or together with implementation.

If governing sources conflict, a required decision is missing, or the correct
fix requires an unapproved architecture change, stop and report:

- the conflicting or missing authority;
- the affected design sections/invariants;
- why a local interpretation would be unsafe;
- the smallest decision or scope change needed to continue.

Do not choose a convenient local interpretation.

## Design-reading routes

Do not load the entire design for every task. Always read the executive summary,
goals/invariants, and applicable acceptance criteria, then read the focused
sections below.

| Work area | Required design sections |
| --- | --- |
| Any engine implementation | Sections 1, 3, 4, 30, and applicable items in 31 |
| Pipeline-node/runtime contracts | Sections 5-7; code samples 1-6 and 24 |
| Configuration/principles/presets | Sections 9-11 and 15; code samples 14-21 and 25 |
| Model routes/context | Sections 12-13.4 and 21; code samples 22-24 |
| Specify | Section 17 |
| Plan | Section 18 |
| Tasks | Section 19 |
| Implement | Section 20 |
| Validation and repair | Sections 21-22; code samples 13 and 28-30 |
| Rendering/editability | Section 23 |
| State, invalidation, recovery | Section 24; code samples 31-33 |
| Transactions/filesystem | Section 25 |
| Security and command safety | Section 26 |
| Observability | Section 27; code sample 34 |
| Testing | Section 28 |
| Package structure | Section 29; code sample 35 |

If **CODEX_TODO.md** is introduced, consult its applicable section for guardrail
setup and sequencing without treating unchecked proposals as accepted
architecture.

## Work authorization

- Answer, review, explain, diagnose, and plan requests are read-only unless the
  user also asks for changes.
- Build, change, implement, and fix requests authorize the requested in-scope
  local edits and non-destructive validation.
- Do not modify accepted design, ADRs, invariant policy, Codex policy, CI
  policy, or security policy unless the task explicitly includes that policy
  change.
- Require explicit approval before adding/removing a production dependency,
  publishing/releasing, performing an external write, taking a destructive
  action, or materially expanding scope.
- Preserve existing user changes and avoid unrelated edits in a dirty worktree.

## Before editing

For code, schema, configuration, test, or architecture changes:

1. Identify the observable outcome and explicit non-goals.
2. Identify the abstraction that owns the requested behavior.
3. Cite the applicable design sections, invariants, and acceptance criteria.
4. Inspect all producers, consumers, transitions, and sibling implementations
   of the affected contract.
5. Check whether the change affects persistence, security, packaging, or
   recovery.
6. State the causal defect or planned contract change.
7. Identify expected files, tests, validation, and any required approval.

For a small, non-semantic documentation correction, keep this proportional and
do not manufacture an architecture exercise.

## Root-cause and change rules

- Fix defects at the lowest abstraction that owns the violated contract.
- Add a regression test at that owning boundary.
- Apply single responsibility to every abstraction. Each module, type,
  function, action, orchestrator, adapter, and port must have one cohesive
  reason to change; split mixed responsibilities at the owning boundary.
- Prefer the smallest architecturally complete change, not the smallest textual
  diff.
- Preserve unrelated validated behavior.
- If the fix needs an unplanned second component, treat that as scope/plan
  rework rather than silently broadening a local patch.
- Reuse the canonical validator, normalizer, transition, renderer, or policy
  owner instead of duplicating it.
- Treat generated files as projections: change canonical state/source and
  regenerate.
- Parse every external, persisted, configuration, and model value from unknown
  through a closed runtime schema.
- Use typed/opaque IDs and capabilities instead of raw paths, commands, status
  strings, or loosely related booleans.
- Make illegal states and transitions unrepresentable where practical.
- Keep side effects behind narrow declared ports.
- Remove legacy and superseded code in the same change, including obsolete
  paths, adapters, flags, schemas, tests, fixtures, and documentation. Do not
  leave dead or parallel implementations.
- Backward compatibility is not required. Do not add or retain compatibility
  shims, aliases, migrations, dual readers/writers, deprecated entry points, or
  fallback behavior.

## Anti-overfitting rule

- Never solve a cross-cutting invariant with a caller-, workflow-, domain-, format-, framework-, token-, filename-, fixture-, or example-specific branch. An example demonstrates a failure class; it does not define the architecture or limit the fix.
- Interpret "lowest owning abstraction" as the narrowest shared contract that owns the complete failure class, not the closest function, stage, or file where one symptom appeared.
- Before changing code or design, state the general violated invariant and inspect every producer, consumer, transition, validator, repair path, recovery path, and sibling implementation governed by it. If the rule crosses stages or domains, change the shared contract and thread it through all of them.
- Domain-specific components may contribute typed facts, candidates, or evidence to a shared mechanism. They must not create independent continuation, fallback, exception, clarification, or success rules.
- A new special case is allowed only when accepted authority distinguishes that case. Represent it as explicit typed policy with narrow scope, provenance, negative tests, and required approval; never infer it from the current example.
- Regression evidence must cover the reported example and unrelated representatives of the same failure class. A fix proven only by the motivating fixture is incomplete.
- If the general owning contract or intended scope cannot be established from current authority, stop and request the missing design decision instead of committing a local interpretation.

## Non-negotiable engine boundaries

### LLM boundary

- An LLM response is a candidate, never committed truth.
- A model receives bounded data, evidence, and guidance; it receives no
  filesystem, process, state-transition, logger, transaction, completion, or
  unrestricted tool capability.
- Model output never chooses a fixed workflow-artifact path.
- Model-supplied commands are never executed.
- Model claims such as valid, passed, approved, or completed have no state
  effect.
- Unsupported assertions become typed clarification or failure, never a
  plausible invention.
- Model-assisted semantic review must not be labelled deterministic proof.

### Actions, orchestrators, and runner

- Every action has one verb-object responsibility.
- An action never invokes an action or orchestrator and never selects its
  successor.
- An action may receive only the narrow operation ports required for its one
  responsibility.
- An orchestrator coordinates runner-owned child bindings and branches only on
  typed outcomes/diagnostics.
- An orchestrator performs no filesystem, model, parsing, rendering, validation,
  command, logging, state, or transaction work.
- A capability-free pipeline-node runtime stays capability-free.
- The generic workflow engine is a capability-free orchestrator: it resolves
  one validated workflow and follows only its compiled typed transitions
  through runner-owned child bindings.
- Only the runner validates/applies node deltas and invokes node execution.
- Only the composition root constructs concrete adapters, binds registered node
  implementations, and assembles the fixed engine-startup graph needed to load
  project workflows. Only the workflow compiler constructs executable
  project-workflow graph descriptors, and only from validated definitions and
  registered node contracts. The startup graph is not project-authored or
  selectable through `paths.workflows` and has no project/feature transaction
  lock capability.
- Domain code imports no infrastructure/provider implementation.

### Paths and commands

- Validate every model-proposed path before reading, recording, or writing it.
- Persistent/model-facing paths are normalized repository-relative paths;
  canonical absolute paths stay inside the engine.
- Every actionable path maps to exactly one environment, project, declared file
  kind, and authorized operation.
- Tasks/implementation use approved file IDs rather than raw paths.
- Only named config/preset command IDs may execute.
- Commands use structured executable/argument descriptors and a shell-disabled
  process adapter.
- Working directory, environment, network, resources, timeout, and side effects
  are explicit and bounded.

### Workflow, repair, and persistence

- For the initial SDD suite, enforce
  `specify -> plan -> tasks -> implement` through each workflow's predecessor
  gate; do not impose that sequence on unrelated workflows.
- Revalidate current predecessor authority at every downstream gate.
- Bind plan/task approvals to exact current state IDs.
- Upstream changes invalidate affected downstream authority.
- Repair only the engine-authorized unit with old-value/revision preconditions.
- Run impacted/dependent validation and then full-candidate validation after
  repair.
- Retry exhaustion blocks/fails; it never weakens policy.
- Candidate project changes stay in memory/overlay until authorized.
- A task completes only after durable project delta, evidence, state, rendered
  view, and required lock data commit.
- Failed, blocked, cancelled, and completed remain distinct.
- Generated plan/task/reference views are never imported as authority.
- The same normalized input and accepted structured payload render byte-stable
  output.

## Prohibited shortcuts

Do not introduce:

- a caller-specific workaround for a shared-contract defect;
- a special case for one fixture/model/filename/test unless an accepted
  requirement distinguishes it;
- a source-tree/packaged-example runtime fallback;
- duplicated validation, normalization, transition, retry, rendering, or
  command policy;
- unbounded `anytype`/`anyopaque` at domain or trust boundaries, unjustified
  pointer/integer casts, `@constCast`, undefined-memory reads, ignored errors,
  or cleanup omissions;
- skipped/focused tests or weakened assertions;
- schema, validator, type, lint, architecture, or test weakening merely to make
  the current task pass;
- direct edits to generated projections;
- raw strings where a validated path, ID, approval, command, or state is
  required;
- generic capability bags, service locators, dispatcher callbacks, or hidden
  node execution;
- direct infrastructure access in an orchestrator;
- action-to-action or action-to-orchestrator execution;
- a success/completion transition that discards a failure;
- concurrency before the relevant overlay, lock, resource-conflict, and
  failpoint tests pass.

If an exception is genuinely required, expose it as an explicit decision with a
narrow contract, negative tests, and the required approval.

## Zig implementation expectations

Once the Zig scaffold exists:

- Pin the supported Zig compiler version in repository-owned build metadata;
  build and test only through `build.zig` steps once those steps exist.
- Use tagged unions and exhaustive `switch` handling for outcomes, diagnostics,
  workflow states, and every other closed variant set.
- Use distinct wrapper types for validated IDs, paths, approvals, commands,
  evidence, capabilities, and transactions; do not pass raw byte slices where
  one of those states is required.
- Parse external, persisted, configuration, and model bytes into versioned,
  closed structs/unions that reject unknown fields and unsupported versions.
- Keep raw, parsed, normalized, validated, approved, and committed types
  separate and make conversions explicit.
- Make allocator and ownership boundaries explicit. Borrowed slices cannot
  outlive their owner; owned values have deterministic `deinit`, `defer`, and
  `errdefer` cleanup on every success and error path.
- Represent expected domain rejection with typed outcomes and unexpected
  operational failure with Zig error unions; neither may be collapsed into
  success or silently discarded.
- Enforce dependency direction with module-import rules plus an independent
  architecture/dependency test.
- Restrict filesystem, process, network/HTTP, C ABI, and provider-client access
  to their authorized adapters.

Do not select the Zig compiler version, concrete libraries, linking strategy,
or supported platform matrix without recording the decision requested by the
task.

## Testing expectations

- Actions: isolated unit tests with fake narrow ports and immutable
  input/output assertions.
- Orchestrators: spy child-binding tests for order, branching, retry, limits,
  and failure propagation.
- Contracts: accepted/rejected schema fixtures, including unknown fields and
  version mismatch.
- Properties: paths, DAGs, conflicts, transitions, repairs, rendering, IDs, and
  transaction convergence.
- Fault injection: malformed model output, parser/command/filesystem failure,
  every transaction phase, interruption, stale approval, and retry exhaustion.
- End to end: each increment must work with a fake model gateway before using a
  real provider.
- Native packaging: build and run the packaged executable from a clean
  temporary directory without the source tree, Zig toolchain, build cache, or
  development-only assets whenever packaging/runtime behavior is affected.

Line coverage alone is not evidence that an invariant is enforced. Every policy
needs accepted and rejected cases.

## Validation

Discover commands from repository-owned configuration; do not invent commands
or claim they ran.

- While the project has no canonical scripts, run the strongest applicable
  checks available and at minimum use **git diff --check** for changed text.
- Once defined, use the repository's changed-scope verification command during
  iteration and its complete CI verification command before completing
  cross-cutting work.
- Run targeted tests first, then architecture/type/schema checks, then the
  required full suite.
- Run the native-executable clean-environment smoke test for runtime, build,
  asset, config discovery, filesystem, process, or packaging changes.
- If a required check cannot run, explain why, run the strongest safe
  substitute, and disclose the missing evidence. Do not claim full completion.

Never fix a validation failure by weakening the judge unless the task explicitly
changes the governing policy and supplies replacement evidence.

## Definition of done

A change is complete only when:

- the requested observable outcome and applicable acceptance criteria are met;
- governing contracts/invariants remain satisfied;
- regression and negative tests exist at the owning boundary;
- targeted and required full checks pass;
- the complete diff has been reviewed for scope expansion, duplicated policy,
  fallbacks, bypasses, suppression, and weakened validation;
- native packaging is built and smoke-tested when affected;
- generated artifacts match canonical rendering when affected;
- documentation/ADRs/traceability are updated when a contract changed;
- the final report names changed contracts/files, tests, exact validation
  commands/results, unresolved uncertainty, and approved deviations.

## Code review rules

### Symptom patches

- Flag a change that fixes one caller while leaving the owning shared contract
  invalid.
- Safe path: repair the owning abstraction and add its regression test.

### Capability leaks

- Flag any path by which an orchestrator gains an operation capability or an
  action gains child-node execution.
- Safe path: use/reuse a single-responsibility action and coordinate it through
  a runner-owned child binding.

### Policy weakening

- Flag a change that accepts one new case by broadly weakening a schema,
  validator, path rule, stage gate, repair boundary, test, or architecture rule.
- Safe path: represent the intended case explicitly in typed policy and add
  accepted and rejected tests.

### Authority bypass

- Flag raw model paths/commands, generated-view authority, stale approval use,
  or completion without committed evidence.
- Safe path: return through the engine-owned typed validation, approval, and
  transaction flow.

### Packaged-executable regressions

- Flag source-relative, current-directory, dynamic-loading, or unpackaged-asset
  assumptions that are tested only in the development runtime.
- Safe path: make asset/config ownership explicit and prove it with the packaged
  clean-environment test.

## Instruction maintenance

- Keep this file concise and repository-wide.
- Put mechanically enforceable rules in types, tests, scripts, and CI rather
  than expanding prose.
- Add or change an instruction only for a durable project requirement or a
  measured repeated failure.
- State each rule once and link to its detailed authority.
- Start a fresh Codex session after changing this file; instructions are loaded
  at session startup.
