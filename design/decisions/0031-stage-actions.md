# ADR 0031: One action per deterministic stage

- **Status:** Accepted. Not built: the Specify invocation stage action; stages not listed as
  stage actions in the code are still single-step actions.
- **Date:** 2026-10-22
- **Decision authority:** User decisions, 22 October and 12, 19 and 20 November 2026.
- **Amends:** AGENTS.md "Actions, orchestrators, and runner" and "Testing expectations";
  [ADR 0003](0003-generic-workflow-engine.md), [ADR 0005](0005-workflow-defined-operations.md)
  and [ADR 0016](0016-configured-json-response-composition.md), for the internal steps of a
  stage action and for absorbed operations; design.md §1, §3.1, §3.3 (invariants 8 and 28) and
  §13; contracts §5, §6, §13, §27 and §28; [F0003](../features/F0003-Toolchain.md) and
  [F0005](../features/F0005-WorkflowDefinitionRegistryService.md).
- **Amended by:** [ADR 0032](0032-engine-routines.md).

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
- **Absorbed steps become functions, not operations.** They are not registered,
  addressable or composable from YAML, and no absorbed operation remains registered. The
  stage's fixed internal sequence routes no outcome, so it does not compete with the compiled
  YAML graph (invariant 28).
- **Data.** Values passed between internal steps are function-local: typed arguments and
  return values, not envelope values or `DataKey`s. Only data that crosses the stage edge
  is pipeline data, declared in the stage action's `NodeContract`. The runner owns the
  stage's inputs and outputs, not its internal values.
- **Validated types replace removed key checks.** Wherever an absorbed step turned a
  candidate key into a validated key, its function returns a distinct validated wrapper type
  that the next step requires. The order those keys enforced then stays a compile-time fact.
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
  operational capability: they count as one port family, so a step may take any of them
  together. No other pair of ports, even from one module, is exempt.
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
  - model requests (ADR 0030), whose kernel form stays: its stages change runner-owned state,
    and the runner must check the split between invoking and interpreting the model per
    binding, which a stage action can't give;
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
  validated population is ordinary code. A repair is the generic operations of
  [ADR 0033](0033-generic-repair-operations.md) around a `request-model` step, not a stage
  action.

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
engine-startup sequence or the feature-logging pipeline, which
[ADR 0032](0032-engine-routines.md) makes typed engine routines. Under that ADR the specify
invocation operation, a registered parse-then-validate operation, becomes a stage action
under this ADR, with side effect `none`.

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
  toolchain runner propagates. A conversion collapses neither into the other.
- **The failing step is named.** Each stage action defines a closed enum of its internal
  steps.
  - A typed failure carries the failing step in its diagnostic.
  - Zig errors carry no payload. For an error, the stage action records the step in a
    stage-owned diagnostic slot before returning the error, and its binding reads that
    slot before propagating the unchanged error. An allocation failure in a step reports that
    step and still propagates as the same error union.
  - The runner's stage event records the step either way, so a report can still say where
    inside the stage a run stopped. The runner lends each step invocation a slot
    (`StepInput.stage_step`), the binding writes the failing step's name before it returns its
    unchanged error, and the failed action's event records it as `step_id`
    (`event-columns/v3`, F0002).
- **A failing entry is named by its display path.** The reference stage's slot also carries
  the display path of the entry whose own reason the error is.
  - It is copied by value from the validated inventory: the selected directory's
    project-relative path, `/` and the entry's normalized path. It is bounded to 512 bytes
    and is none when it does not fit; the text is never cut.
  - Only the reference stage's binding writes it, and only for the nine entry-level failures
    ([13-03](../contracts/actions/13-03-references.md)). An inventory, accounting, port or
    identity error names none.
  - The runner keeps it beside the terminal rejection for the CLI
    ([§8](../contracts/08-diagnostics-evidence.md)). It is presentation data, never
    authority, and no event, log or E2E report records it.
- **Cancellation** is checked between internal steps. A stage action's `execute` takes the
  capability-free `NodeRuntime` (from `domain/pipeline.zig`), and no other runtime handle, and
  checks its status between steps. A cancelled stage stops before its next internal step and
  cleans up what it owns.
  - The runner supplies the runtime in the step input, and a non-model operation that fails
    after the runtime stopped reports that stop (cancelled), not an
    operation failure, as the checks before and after the invocation do. An allocation
    failure stays itself, and a model call keeps its own reconciled status.
  - A non-model operation that fails with `Cancelled` while the runtime still reports active
    (a cancelled filesystem or random-source call) also ends the run `cancelled`. The runtime
    status does not decide that alone. An adapter maps the standard library's cancellation to
    `Cancelled`; any other failure of the same call stays the port's own error.

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
- **Workflows and tests that use the absorbed operations are updated** in the same change.
- **Logic and tests move, not vanish.** The logic moves into the stage's functions, and
  each removed action's accepted and rejected cases move to its function or to the stage
  edge.
- **Freeze first.** Before converting, record the stage's outcome classes, error identities
  and edge data across the integration scenario matrix and a second workflow that uses the
  stage. The stage action must reproduce them. Diagnostics may only gain the internal-step
  field.
- **Evidence is offline.** A conversion claims no semantic change. It reports AGENTS.md's
  statements separately, with semantic benefit "none claimed". Live E2E runs apply only if a
  conversion claims a semantic or reliability effect.
- **Measures**, recorded before and after: YAML lines and steps, registry entries, `DataKey`
  members, and the files a representative concept change touches. This measure decides
  whether the next stage converts.

### Tests

All offline, for each stage action:

- **Function tests.** Every internal function has unit tests with fake ports, covering
  accepted and rejected cases. The removed actions' negative cases survive.
- **Stage-edge tests.** Accepted and rejected cases for its `NodeContract`, every outcome,
  allocation cleanup, and cancellation between each pair of internal steps.
- **Diagnostics.** A failure in each internal step reports that step.
- **Architecture and registry tests** hold each rule under "Stage actions", "Narrow ports
  inside a stage" and "What a stage action may contain", each with rejected fixtures. For
  every absorbed step that turned a candidate key into a validated key, its output type
  differs from its input type and the next step requires it.

### Unchanged

- The LLM boundary, model requests and their kernel form (ADR 0030).
- Typed IDs, paths, approvals and commands, and every canonical validator and policy
  owner, which stage functions reuse rather than duplicate.
- Publication atomicity (ADR 0009) and command safety (§26).
- Capability-free orchestrators, and the runner as sole delta owner.
- Model calls, prompts, tokens and the workflow budget.

## Consequences

- **Less composability.** A project workflow cannot compose absorbed steps in a
  different combination, such as capturing and parsing the toolchain without the safety
  check. That combination would need a new stage action and an engine rebuild.
- **Narrowness inside a stage rests on Zig types and tests.** The runner checks
  capabilities per stage action, not per internal step.
- **Visibility moves.** Internal steps lose YAML and per-step event visibility. The
  failing-step diagnostic replaces it.
- **No behaviour change is claimed.** No change to model behaviour, token cost or run
  reliability is expected or claimed.
