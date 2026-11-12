# ADR 0031: One action per deterministic stage

- **Status:** Accepted amendment. **Partly implemented:** `prepare-toolchain` is the first
  stage action (12 November 2026, SPEC01 E2) and `prepare-inputs` the second (12 November
  2026, SPEC01 E2b), and `prepare-reference-evidence` and `prepare-reference-tokens` the third
  and fourth (12 November 2026, SPEC01 E2c); every other stage is still a run of
  single-step actions until its conversion lands. Documents that describe single-step
  granularity for those stages carry a pointer to this ADR until then.
- **Date:** 2026-10-22
- **Decision authority:** The user's instruction on 22 October 2026, "update the
  documentation with the recommendations for option B". It decides FIX05
  (`fixes/Z_FIX05.md` §21, git `194e29a`) A2 after a comparison of two forms. The user
  ranked the criteria: "this is a proof of concept and refactoring to best possible
  outcomes is the most important". The approved recommendation included three rules:
  single responsibility and narrow ports per function, function-local intermediate
  values, and model calls and every real branch kept in YAML. The choices under "Derived
  under existing rules" follow from existing authority; the user confirmed choices 1–3 and
  6–8 on 12 November 2026 ("yes").
- **Amends:**
  - AGENTS.md "Actions, orchestrators, and runner" (one responsibility and narrow ports)
    and "Testing expectations" (action tests);
  - [ADR 0003](0003-generic-workflow-engine.md) and
    [ADR 0005](0005-workflow-defined-operations.md): "Every non-kernel workflow operation
    is addressable from YAML", "Adding a workflow from existing operations requires no
    engine rebuild", "Sequencing and branching are visible in the YAML graph" and "must
    not conceal a second workflow graph", for the internal steps of a stage action;
  - [ADR 0016](0016-configured-json-response-composition.md): "Keep detailed operations
    available" and "Detailed operations … remain visible", for absorbed operations;
  - [ADR 0030](0030-engine-owned-model-request.md): the rationale of its derived choice 1;
  - design.md:
    - §1 properties 1 and 6;
    - §3.1, adding workflows from existing operations;
    - §3.3 invariants 8 and 28;
    - the §13 introduction;
    - the §32 index;
  - contracts:
    - §5: actions perform one narrow operation;
    - §6: §6.1's split rules, "cannot conceal … a domain stage", "return all intermediate
      values through validated `NodeDelta`s", and §6.3 "Actions and orchestrators can be
      reorganized without changing their implementation";
    - §13: design.md's introduction, which governs every catalogue, and the 13-01
      toolchain entries;
    - §27 and §28;
  - [F0003](../features/F0003-ToolChainService.md): the nine separate toolchain
    operations, runner-owned intermediates and cancellation, and their acceptance and
    verification;
  - [F0005](../features/F0005-WorkflowDefinitionRegistryService.md): "Nothing is hidden
    in an action" and runner ownership of intermediates.

  The overall design remains **Proposed design**.

## Context

Every YAML step is one registered action, even where steps never make a choice. The
first subgraph of the Specify definition, `prepare-toolchain`, is nine actions that
always run in the same order, and every failure ends the run. Each action costs about
six coordinated pieces:

- an action file;
- an application binding;
- a registry entry in the composition root;
- entries in the `DataKey` enum, so it can hand data to the next step;
- a YAML node;
- usually an architecture test.

More than half of the Specify definition's steps only pass `ok` to the next step and
`failed` to the end. Plan, Tasks and Implement would multiply this cost.

A first option would have kept every small action and only hidden runs of them behind a
fixed coordinator, as [ADR 0030](0030-engine-owned-model-request.md) does for model
requests. That shortens the YAML but keeps most of the per-concept cost: each internal
action keeps its file, binding, registry entry and `DataKey` entries. This ADR takes the
second option.

## Decision

### Terms

In this ADR, a **stage** is a cohesive run of deterministic workflow work, such as
toolchain preparation. It is not an SDD workflow stage (Specify, Plan, Tasks, Implement)
and not one of ADR 0030's request stages. Other documents say **stage action** and avoid
the bare word. The parts of a stage are **internal steps**.

### Stage actions

A registered, YAML-selected action may own one stage. This is a **stage action**.

- **Responsibility.** Its one verb-object responsibility is the stage, for example
  `prepare-toolchain`. It has one registry entry, one application binding and one YAML
  step. It is not a whole-SDD-stage orchestrator, which §14 still prohibits.
  - One exception, added by [ADR 0032](0032-engine-routines.md): an invocation operation
    named by a definition's `invoke:` field may be a stage action.
  - Such a stage action has no `on` map. The workflow-engine orchestrator runs it through its
    binding before the graph starts and reads its `ok` or `failed` outcome.
- **Internals.** Each internal step is an ordinary typed Zig function. Single
  responsibility applies to each function, as AGENTS.md already requires of every
  function.
- **Absorbed steps become functions, not operations.** They are no longer registered,
  addressable or composable from YAML. The stage's fixed internal sequence routes no
  outcome, so it does not compete with the compiled YAML graph (invariant 28).
- **Data.** Values passed between internal steps are function-local: typed arguments and
  return values, not envelope values or `DataKey`s. Only data that crosses the stage edge
  is pipeline data, declared in the stage action's `NodeContract`. The runner owns the
  stage's inputs and outputs, not its internal values.
- **Validated types replace removed key checks.** This rule was added with ADR 0032.
  Wherever an absorbed step turned a candidate key into a validated key, its function
  returns a distinct validated wrapper type that the next step requires. The order those
  keys enforced then stays a compile-time fact.
- **Delta.** The stage action returns one delta, which the runner validates and applies
  as for any action. Its outputs record the stage action as producer.
- **Where the code lives.** Pure internal steps live in `src/domain/`. Internal steps
  that use a port live in the stage action's own file, which still declares exactly one
  `Action` and one `contract` and imports only domain and port modules.

### Narrow ports inside a stage

The runner checks capabilities per binding. Inside a stage action, Zig signatures and
architecture tests carry the narrowness instead:

- `execute` only calls internal-step functions in order, with a cancellation check
  between them. It never calls a port method itself.
- Each port-using internal step takes exactly one port parameter. No internal function
  takes the `Action` value, `self` or any struct that holds more than one port. The one
  exception is the Unicode text services (the normalizer, the case folder and the lexical
  classifier, the three types of `ports/unicode_normalizer.zig`), which are pure and carry no
  operational capability: they count as one port family (user ruling, 12 November 2026), so a step
  may take any of them together. No other pair of ports, even from one module, is exempt.
- No capability bag, `anytype` or `anyopaque` crosses an internal-step boundary.
- §6.1's read-versus-parse split holds between functions: a function that reads does not
  parse. Raw, parsed, normalized and validated values stay distinct types, with explicit
  conversions.
- The runner and compiler still derive and check the stage action's capabilities from
  its port types, and the selected policy must permit each.

### What a stage action may contain

- **Side effects:** only `none` or `filesystem_read`. A stage action never writes,
  publishes, executes a command, persists a clarification, activates feature logging or
  calls a model. Those stay their own actions or steps, with their existing contracts:
  - model requests (ADR 0030);
  - publication (§25, ADR 0009);
  - commands (§26);
  - clarification persistence;
  - feature-log activation.

  The other three §6.1 splits are therefore unaffected: invoke versus interpret a model,
  validate versus write a path, and publish versus decide.
- **Model output.** A stage action never requires a retained model request or its
  admitted payload. A separate collect action reads those. A stage action may validate
  or process the typed candidate that collect produces.
- **Contract fields.** The stage action, and every step it absorbs, has:
  - repair role `none`;
  - `runner_accounting` `none`;
  - outcome association `independent`;
  - no retry authority and no model binding.
- **Gates and lineage.** No stage action absorbs a gate issuer, or produces or replaces a
  gate evidence key. It never absorbs a key that a gate contract names, or a key whose
  schema retention is `captured`, because lineage expands through those. Gate issuers stay
  port-free, YAML-visible operations (F0005).
- **No hidden control flow.** It contains no retry, repair, loop over model output, or
  call to another action or orchestrator. Finite deterministic iteration over an already
  validated population is ordinary code.

### What a stage may absorb

A stage absorbs a run of steps only where the workflow cannot usefully route a step's
outcome anywhere else:

- every absorbed step's success continues to the next absorbed step;
- every other outcome ends the stage with that same typed outcome.

The stage action's outcome set is the union of those terminal outcomes, and YAML maps
each of them. Any outcome a workflow routes to a different step, such as clarification,
repair, `blocked` or `more`, stays a YAML outcome of a stage action or a YAML step of its
own.

### Scope

Stage actions apply to registered workflow operations. This ADR does not cover the fixed
engine-startup graph, the feature-logging pipeline or the invocation operation.
[ADR 0032](0032-engine-routines.md) (22 October 2026) decides them:
- startup and feature logging become typed engine routines;
- the specify invocation operation, a registered parse-then-validate operation, becomes a
  stage action under this ADR, with side effect `none`.

### What stays in YAML

- every model request (`request-model`, ADR 0030) and every collect action that reads
  one;
- every real branch and its target;
- repairs;
- the side-effect actions listed above;
- gate issuers;
- every parameter a workflow author may set.

### Failures and diagnostics

- **Failure representation is unchanged.** Each internal step keeps the failure
  representation its absorbed action had. Typed outcomes stay typed outcomes. Error
  unions stay error unions, including allocation, I/O and the terminal errors the
  toolchain runner propagates today. A conversion collapses neither into the other.
- **The failing step is named.** Each stage action defines a closed enum of its internal
  steps.
  - A typed failure carries the failing step in its diagnostic.
  - Zig errors carry no payload. For an error, the stage action records the step in a
    stage-owned diagnostic slot before returning the error, and its binding reads that
    slot before propagating the unchanged error.
  - The runner's stage event records the step either way, so a report can still say where
    inside the stage a run stopped. The runner lends each step invocation a slot
    (`StepInput.stage_step`), the binding writes the failing step's name before it returns its
    unchanged error, and the failed action's event records it as `step_id`
    (`event-columns/v3`, F0002).
- **Cancellation** is checked between internal steps. Unlike other actions today, a stage
  action's `execute` also takes the capability-free `NodeRuntime` (from
  `domain/pipeline.zig`) and checks its status between steps. A cancelled stage stops
  before its next internal step and cleans up what it owns.
  - The runner supplies the runtime in the step input, and a non-model operation that fails
    after the runtime stopped reports that stop (cancelled or deadline exhausted), not an
    operation failure, as the checks before and after the invocation do. An allocation
    failure stays itself, and a model call keeps its own reconciled status.

### Runner, compiler and registry

These are unchanged:

- The runner invokes the stage action, validates and applies its delta and checks its
  capabilities.
- The compiler proves dataflow at stage edges.
- Only the composition root binds the stage action.
- The 1,024-step ceiling still applies to the compiled graph.

### Catalogue entries

A converted stage's §13 catalogue entries become one stage-action entry. That entry lists
the internal steps in order, each keeping its former entry's responsibility, input,
output and rejection rules.

### Conversion

- **Stage by stage.** Each conversion is one change.
- **Removal in the same change**, with no compatibility form (AGENTS.md): the absorbed
  actions' registry entries, application bindings, YAML nodes and `DataKey`s used only
  inside the stage, and tests that pin those files.
- **Workflows and tests that use the absorbed operations are updated.** For
  `prepare-toolchain` that means the Specify definition, the `toolchain-check` fixture
  (`src/test_fixtures/toolchain.workflow.yaml`) and
  `test/integration/workflow_tests.zig`.
- **Logic and tests move, not vanish.** The logic moves into the stage's functions, and
  each removed action's accepted and rejected cases move to its function or to the stage
  edge.
- **First conversion:** `prepare-toolchain`, as the proof of the pattern. It is measured
  before further stages convert. None of its nine steps issues a gate, holds accounting or
  closes a request.

### Evidence

AGENTS.md's "Model output, prompts and evidence" applies. A conversion claims no semantic
change, so its evidence is offline:

- frozen-behaviour equivalence on two unrelated workflows that use the stage: for
  `prepare-toolchain`, the Specify definition and the `toolchain-check` fixture;
- the measures under Acceptance.

Each conversion reports AGENTS.md's statements separately: implementation complete,
mechanical checks passed, brittleness reduced (the measures under Acceptance), and
semantic benefit demonstrated, which is "none claimed". Live E2E runs and the replayed
two-case semantic rule apply only if a conversion claims a semantic or reliability effect.

### Unchanged

- The LLM boundary, model requests and their kernel form (ADR 0030).
- Typed IDs, paths, approvals and commands, and every canonical validator and policy
  owner, which stage functions reuse rather than duplicate.
- Publication atomicity (ADR 0009) and command safety (§26).
- Capability-free orchestrators, and the runner as sole delta owner.
- Model calls, prompts, tokens and the workflow budget.

## Derived under existing rules

The user approved option (b). These choices are derived from existing authority, not
from the user's words, and await the user's confirmation:

1. **Read-only stages.** Writes, publication, commands, clarification persistence,
   feature-log activation, gate issuers and model calls stay their own actions. The
   splits behind them come from §6.1, §25, §26 and F0005's gate rule. AGENTS.md does not
   restate this choice until the user confirms it.
2. **The absorption rule.** It makes "every real branch stays in YAML" exact: only steps
   whose non-success outcomes all end the stage are absorbed (ADR 0005).
3. **ADR 0030's kernel form stays for model requests.** Its stages change runner-owned
   state (accounting, leases and lifecycle ledgers), and the separation between invoking
   and interpreting the model, and between the model and authorization capabilities, must
   be checked by the runner per binding. A stage action can't give that.
4. **Scope.** The fixed startup graph, the logging pipeline and the invocation operation
   are left to a separate decision, since made by ADR 0032: routines for startup and
   logging, and a stage action for the invocation operation.
5. **Repairs.** A repair operation can't contain a model request, which both ADR 0030 and
   this ADR forbid. Superseded by [ADR 0033](0033-generic-repair-operations.md): a repair
   is the generic operations authorize, build input, parse and merge around a
   `request-model` step, not stage actions.
6. **`prepare-toolchain` goes first** and is measured before the next conversion.
7. **Evidence:** a structural conversion is accepted on offline evidence, as stated
   above.
8. **Contract-field limits and model output.** The contract-field limits above, and the
   rule that a stage never reads a retained model request, keep every carrier proof, gate
   and accounting rule attached to a visible step.

## Consequences

Expected benefits, pending the measures:

- **Lower cost per concept.** A concept inside a stage should cost functions and tests,
  not a binding, a registry entry and `DataKey`s, so the composition root and `DataKey`
  enum should change less often.
- **Fewer runtime wiring failures.** Wiring between internal steps becomes typed
  function calls, so registry and binding mismatches that today surface as runtime
  rejections disappear inside a stage. Workflow compilation already catches dataflow
  misordering (§6.3). Zig catches internal misordering only where adjacent steps have
  different types.
- **Shorter YAML** by the pass-through runs each stage absorbs. The implementation
  measures by how much.

Costs:

- **Less composability.** A project workflow can no longer compose absorbed steps in a
  different combination, such as capturing and parsing the toolchain without the safety
  check. That combination would need a new stage action and an engine rebuild.
- **Narrowness inside a stage rests on Zig types and tests.** The runner checks
  capabilities per stage action, not per internal step. Inside a stage, narrowness rests
  on Zig signatures and the architecture tests below.
- **Visibility moves.** Internal steps lose YAML and per-step event visibility. The
  failing-step diagnostic replaces it.
- **It's a large refactor.** It touches most actions, their bindings, the registry and
  many file-pinned architecture tests. Doing it stage by stage, with measurement, bounds
  the risk.
- **No behaviour change is claimed.** No change to model behaviour, token cost or run
  reliability is expected or claimed.

## Acceptance

All offline, for each converted stage:

- **Freeze first.** Before converting, record the stage's outcome classes, error
  identities and edge data across the integration scenario matrix and the second workflow.
  The stage action must reproduce them. Diagnostics may only gain the internal-step
  field.
- **Function tests.** Every internal function has unit tests with fake ports, covering
  accepted and rejected cases. The removed actions' negative cases survive.
- **Stage-edge tests.** Accepted and rejected cases for its `NodeContract`, every outcome,
  allocation cleanup, and cancellation between each pair of internal steps.
- **Diagnostics.** A failure in each internal step reports that step. An allocation failure
  in step *k* reports step *k* and still propagates as the same error union.
- **Architecture and registry tests:**
  - the stage action declares only `none` or `filesystem_read`, repair role `none`,
    `runner_accounting` `none` and outcome association `independent`, with no retry
    authority and no model binding;
  - it imports only domain and port modules;
  - `execute` calls no port method, and takes the capability-free `NodeRuntime` and no
    other runtime handle;
  - no internal function takes two port parameters (the Unicode text services count as one),
    the `Action` value or `self`, or any struct holding more than one port;
  - no internal function takes a capability bag, `anytype` or `anyopaque`;
  - each of these rules has rejected fixtures;
  - no absorbed operation remains registered;
  - no stage action produces or replaces a gate evidence key, absorbs a key with
    `captured` retention, or requires a retained model request;
  - for every absorbed step that turned a candidate key into a validated key, its output
    type differs from its input type and the next step requires it, with a rejected
    fixture.
- **Build checks:** `zig build verify` and the clean packaged-executable smoke test pass.
- **Measures**, recorded before and after: YAML lines and steps, registry entries, `DataKey`
  members, and the files a representative concept change touches. This measure decides
  whether the next stage converts.

## Not decided here

- Which stages convert after `prepare-toolchain`, and in what order.
