# ADR 0032: Typed engine routines for fixed engine sequences

- **Status:** Accepted amendment. **Not yet implemented:** startup, provider bootstrap and
  feature logging still run through child bindings until their conversions land.
  Documents that describe those orchestrators carry a pointer to this ADR until then.
- **Date:** 2026-10-22
- **Decision authority:** The user's instruction on 22 October 2026, "update the docs
  around yes, form b". It decides [FIX05](../../fixes/FIX05.md) A3 as option (b): fixed
  engine sequences become typed routines in the pattern of
  [ADR 0031](0031-stage-actions.md), starting with startup. The user had earlier ranked
  the criteria for this proof of concept: "refactoring to best possible outcomes is the
  most important". The choices under "Derived under existing rules" follow from existing
  authority and await the user's confirmation.
- **Amends:**
  - AGENTS.md "Actions, orchestrators, and runner" (the startup-graph line), "Testing
    expectations" and the capability-leak review rule;
  - [ADR 0003](0003-generic-workflow-engine.md): the "compiler-locked engine-startup
    graph" and "every orchestrator … receives only runner-owned child bindings", for
    the sequences below;
  - [ADR 0004](0004-model-provider-bootstrap.md): the fixed, nonselectable,
    capability-free `ModelProviderBootstrapOrchestrator` and its runner-owned bindings;
  - [ADR 0018](0018-debug-model-exchange-logging.md): "retain the fixed logging
    orchestration under §13.9";
  - [ADR 0026](0026-header-identity-log-retention.md): the retention coordinator's
    step-order test;
  - [ADR 0030](0030-engine-owned-model-request.md): its precedent sentence;
  - [ADR 0031](0031-stage-actions.md): its scope exclusion of the invocation operation,
    its stage-action definition (the `invoke:` exception) and its data rules (validated
    wrapper types);
  - design.md:
    - §1 property 6;
    - §3.3 invariants 9 and 27;
    - the §14, §15 and §29 summaries;
    - §31.1, §31.6 and §31.7;
    - the §32 index;
  - contracts:
    - §5: orchestrators receive only child bindings; the startup graph;
    - §6: every node conforms; ports belong to actions only; §6.2's rules and
      architecture tests;
    - §14: §14.0 step 1, the invocation operation, §14.9 and §14.10;
    - §15, §27, §28 and §29;
    - the 13-01, 13-02 and 13-09 catalogues;
  - [F0001](../features/F0001-SDDToolKitConfigService.md),
    [F0002](../features/F0002-LogService.md),
    [F0004](../features/F0004-BootstrapRootRegistryService.md),
    [F0005](../features/F0005-WorkflowDefinitionRegistryService.md),
    [F0006](../features/F0006-LLMProviderInterface.md) and
    [F0008](../features/F0008-LLMProviderConfigService.md): where they require these
    sequences to run as runner-applied actions under a capability-free orchestrator
    with runner-owned child bindings and spy-binding tests.

  The overall design remains **Proposed design**.

## Context

The engine runs several sequences that always take the same steps in the same order.
Startup is the largest: 29 steps from locating `.sddtoolkit.json` to building the
workflow registry. Its orchestrator calls each step through a table of parameterless
function pointers on an untyped `*anyopaque` context. Data moves through shared optional
fields on runner structs (`raw_config: ?RawEngineConfig = null`), and each step checks
its predecessor's field with a debug assertion and a `.?` unwrap. The dependency between
steps isn't visible in any type. A compile-time check already covers declared pipeline
keys, but not the values stored in those fields.

There are ten child-binding files, 515 lines in all. Seven belong to the sequences this ADR
converts; the workflow-engine and workflow-pipeline bindings stay, and the specify-invocation
bindings go with its stage action. `src/application/` has 233 `anyopaque` lines, and
production code about 394. AGENTS.md lists unbounded `anyopaque` at boundaries as a prohibited
shortcut. Each new step costs a vtable slot, an optional field and an assertion, and a
wiring mistake is a runtime failure.

## Decision

### Engine routines

A fixed engine sequence becomes an **engine routine**: one module of typed functions
that runs the sequence. It is engine-kernel work under ADR 0005, like loading,
parsing, compilation, cleanup and provider preparation. It is neither an action nor an
orchestrator, and not a pipeline node: it is not registered, not selectable from YAML,
and produces no `NodeDelta`.

- **Steps.** Each step is a function with one responsibility. Pure steps live in
  `src/domain/`. Each port-using step takes exactly one port parameter.
- **Typed data.** Values pass as typed arguments and return values. A routine uses no
  `*anyopaque` context, no table of parameterless steps, no shared optional fields and
  no per-step envelope or `DataKey` tracking.
- **Validated types replace the removed key checks.** Today some steps are kept in order
  only by pipeline keys. For example, a validator that takes and returns the same
  inventory type turns `workflow_authority_inventory_candidate` into
  `workflow_authority_inventory`. Wherever a step's current contract turns a candidate key
  into a validated key, its function returns a distinct validated wrapper type, and the
  next step requires that type. Running a step before its inputs exist is then a compile
  error. Zig catches misordering only where adjacent types differ, so this rule is what
  makes it hold.
- **The entry function** calls steps in order and calls no port itself. It checks
  cancellation and deadline between steps through the capability-free `NodeRuntime`. It
  owns cleanup through `defer` and `errdefer` on every path.
- **Branches.** A routine may branch on a typed fact its own steps produce, such as
  whether a provider is required, or whether a log event is dropped. It has no retry,
  backoff or loop beyond what its existing contracts already specify. The lock acquire
  stays one attempt with its fixed deadline.
- **Narrow ports.** No step takes the routine's port set, a capability bag, `anytype` or
  `anyopaque`. A side-effecting step acts only on typed values an earlier step already
  validated, so validate versus write holds between functions.
- **Location.** A routine lives in `src/application/<name>_routine.zig`. It imports only
  domain and port modules, never adapters or `std.Io`. It reaches I/O only through its
  port parameters.

### Who calls a routine

- **The composition root** constructs every routine's ports. It runs the startup routine
  before workflow selection, as the code already does. This amends §14.0 step 1, where
  the engine orchestrator invoked that portion through a binding.
- **A runner-owned child binding** runs provider bootstrap after workflow selection. The
  composition root builds the binding and the binding holds the ports. The
  workflow-engine orchestrator sees only the binding and the routine's typed outcome, so
  it gains no capability.
- **The existing logging lifecycle owners** invoke the feature-logging routines: the log
  service, the runtime logging lifecycle and the runner's finalization path (ADR 0018).
- **No action, orchestrator or model-facing code** calls a routine directly.

### What doesn't change

- **Startup properties.** Startup is still not project-authored, registered or
  selectable through `paths.workflows`. It still acquires no feature transaction lock.
- **Service construction.** Each service is still built only after its complete
  validation (F0001, F0004, F0005 and F0008).
- **Public error codes** stay identical. Failure, cancellation and success stay distinct,
  except for a tracked gap: cancellation under a log lock is still reported as a logging
  failure (see Scope).
- **Failure mapping.** Each step keeps its current failure mapping.
  - Startup and provider steps today map every error to their fixed public code,
    including allocation failure and deadline exhaustion, and they keep doing so.
  - Where a sequence propagates a Zig error today, it still propagates that error.
  - Each routine defines a closed enum of its steps, and every failure records the failing
    step. A mapped failure carries it in its diagnostic. A propagated error leaves it in a
    routine-owned diagnostic slot, as ADR 0031 does.
- **Provider bootstrap** still branches only on the typed requirement and gains no
  credential read (ADR 0028). It is no longer capability-free: its locate and read steps
  hold the provider-config port. On `not_required` it makes no provider-config call.

### Scope and order

1. **Startup, first.** It covers three sequences, which only read, decode, validate and
   build in memory:
   - the bootstrap sequence before workflow selection: `bootstrap_orchestrator.zig`, its
     child bindings, `bootstrap_*_runner.zig` and `bootstrap_execution.zig`;
   - the provider-config sequence;
   - the provider-bootstrap sequence after selection.

   This first conversion is measured before the next.
2. **Feature logging, second.** That covers `feature_log_orchestrator.zig` and its
   finalization, retention and policy-transition coordinators. It writes, locks and
   prunes, so it converts only after its own preconditions are met:
   - **Baseline tests first.** Tests for cancellation under a lock, and for the number of
     emergency lines, exist and pass before conversion (ADR 0026 records neither).
   - **Locks.** Every lock is released on every success, error and cancellation path
     (§26.5, 13-09).
   - **Emergency diagnostic.** It stays exactly once and is never recursive or observed
     (§14.9, 13-09, F0002).
   - **Finalization** keeps one idempotent owner that preserves the first failure
     (ADR 0018).
   - **Retention** keeps its five-step order, and pruning stays its only deletion path
     (ADR 0026).
   - **Cancellation mapping.** Cancellation under a lock is still reported as a logging
     failure; fixing that is separate known work. A cancellation check between steps
     never skips a lock release.
   - **The policy-transition coordinator** converts only once its deferred historical
     authority (§14.10) is decided.
   - **Logging-internal pipeline data.** The logging envelope and its compiler-locked
     `DataKey`s (§6) are replaced by function-local values only in the logging change
     itself.

Out of scope:

- **The workflow-engine orchestrator.** It follows the compiled YAML and isn't a fixed
  sequence.
- **[ADR 0030](0030-engine-owned-model-request.md)'s request coordinator.** Its stages
  change runner-owned state that the runner must apply per stage, it is YAML-selected,
  and the runner must check capabilities per stage binding. That form stays.
- **The specify invocation operation.** It is a registered operation that only parses
  and validates, so it becomes an [ADR 0031](0031-stage-actions.md) stage action with side
  effect `none`, not a routine.
  - It is named by the definition's `invoke:` field rather than a graph step, and has no
    `on` map. The workflow-engine orchestrator runs it through its binding before the graph
    starts and reads its `ok` or `failed` outcome, as today.
  - ADR 0031's definition is extended to cover this case.

### Removal

With no compatibility form (AGENTS.md), each conversion removes:

- the child-binding file, its vtable and its spy tests;
- the runner structs' optional state fields;
- the per-step envelope tracking;
- the `DataKey`s used only inside the sequence;
- the absorbed actions' `Action` wrappers, and their registry entries where they exist.
  Their logic becomes the routine's steps.

Each removed test's accepted and rejected cases move to a step test or a routine test.
The architecture rules that pin the removed files are replaced by the routine rules
below.

### Evidence

CLAUDE.md's "Evidence for a contract change" applies. A conversion claims no semantic
change, so its evidence is offline:

- **Frozen equivalence.** Freeze public outcomes and error codes, emitted diagnostics,
  cancellation behaviour and the services built, then reproduce them after conversion.
  Use the integration matrix and two unrelated workflows that run startup: the Specify
  definition and the `toolchain-check` fixture.
- **Clean packaged-executable smoke test.** Startup governs configuration discovery.
- **The FIX05 A2 measures:** files touched per change, lines, and `anyopaque` count.

Each conversion reports CLAUDE.md's statements separately, with semantic benefit "none
claimed".

## Derived under existing rules

The user approved option (b). These choices are derived from existing authority, not
from the user's words, and await the user's confirmation:

1. **Category and location:** a third category, the engine routine, in
   `src/application/*_routine.zig`, importing only domain and ports. No existing file
   class allows a port-holding module that is neither an action nor a runner.
2. **Internal branches** on the routine's own typed facts are allowed, because engine
   kernel work has no YAML to route through.
3. **Callers:**
   - the composition root for startup, matching today's code and amending §14.0 step 1;
   - a runner-owned binding for provider bootstrap;
   - the existing logging lifecycle owners for logging.

   Capability-free orchestrators therefore stay capability-free.
4. **Logging second,** under the preconditions above.
5. **Specify invocation becomes an ADR 0031 stage action,** not a routine, because it
   is a registered operation. ADR 0031's definition is extended to its `invoke:` form.
6. **ADR 0030's request coordinator keeps its form.**
7. **Testing.** Routines are tested with fake ports instead of spy child bindings. FIX05
   A3's earlier idea of keeping spy tests through a typed interface is superseded by
   option (b).
8. **Validated wrapper types** replace the pipeline keys that kept candidate and
   validated values apart. The same rule applies to ADR 0031 stage actions.

## Consequences

Expected benefits, pending the measure:

- **Wiring errors become compile errors.** Step dependencies become types, including the
  validated wrapper types above, so running a step out of order no longer compiles. The
  optional fields, debug assertions and `.?` unwraps go.
- **Less code and fewer erased types.** The converted child-binding files and vtables go.
  That removes roughly 130 of the 233 `anyopaque` lines in `src/application/` after
  startup, and roughly 210 once logging converts too. The implementation measures the
  real figures.
- **Simpler cleanup.** Cleanup moves into one owner per routine.
- **One pattern.** Every deterministic sequence follows the same pattern: stage actions
  for workflow operations, engine routines for kernel sequences. The only exception is
  ADR 0030's request coordinator.

Costs:

- **Tests change kind.** Order and failure propagation are tested by running the routine
  with fake ports, not by spying on child bindings.
- **Narrowness rests on types and tests.** Inside a routine, it rests on Zig signatures
  and architecture tests rather than per-binding capability checks.
- **Logging is the riskier half.** It is gated by the preconditions above.
- **No behaviour change is claimed.**

## Acceptance

All offline, for each conversion:

- **Freeze first,** as under Evidence, then reproduce.
- **Step tests.** Every step has unit tests with fake ports, covering accepted and
  rejected cases. The removed spy and action tests' negative cases survive.
- **Routine tests** with fake ports:
  - step order;
  - every branch;
  - failure propagation with the exact public code;
  - cancellation and deadline between each pair of steps;
  - cleanup on every path.
  For logging, also lock release on every path, exactly one emergency line, and
  finalization idempotence.
- **Diagnostics.** A failure in each step reports that step. An allocation failure in
  step *k* reports step *k* with today's public code, or as the same propagated error where
  the sequence propagates errors today.
- **Provider bootstrap.** On `not_required`, the routine makes zero provider-config port
  calls.
- **Validated types.** For every step whose old contract turned a candidate key into a
  validated key, a compile-time or architecture check shows that its output type differs
  from its input type and that the next step requires the output type.
- **Architecture tests:**
  - a `*_routine.zig` imports only domain and port modules, and never adapters or
    `std.Io`;
  - no step takes two port parameters, the port set, a capability bag, `anytype` or
    `anyopaque`;
  - the entry function calls no port method;
  - no `*anyopaque` child-binding context remains for a converted sequence;
  - only `src/composition/`, the provider-bootstrap binding and the named logging
    lifecycle owners import a `*_routine.zig`, with rejected fixtures for an action and an
    orchestrator that import one;
  - orchestrators stay capability-free and reach routines only through runner-owned
    bindings;
  - each rule has rejected fixtures.
- **Build checks:** `zig build verify` and the clean packaged-executable smoke test pass.
- **Measures**, recorded before and after: files touched per representative change,
  lines, and `anyopaque` count.

## Not decided here

- The policy-transition coordinator's deferred historical authority (§14.10, and FIX05's
  prior-run crash finalization).
- Reporting cancellation under a log lock as cancellation instead of a logging failure.
  That is separate known work, and it changes the shared sink contract.
- The order of the remaining logging conversions after startup has been measured.
