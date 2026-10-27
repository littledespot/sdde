# 6. Common action and orchestrator contract

Part of the [proposed design](../design.md#6-common-action-and-orchestrator-contract), as amended by the
[accepted ADRs](../design.md#32-accepted-and-deferred-implementation-choices).

- Every action **and** every orchestrator conforms to the same runtime contract. An
  [ADR 0032](../decisions/0032-engine-routines.md) engine routine (not yet implemented) is not
  a node and does not.
- There is one envelope, one result vocabulary, and one dependency declaration mechanism across
  the engine.
- Zig has no built-in interface construct, so the implementation must encode this contract with
  compile-time-checked descriptors and runner-owned bindings rather than structural convention
  or runtime reflection.
- The exact internal dispatch representation may be selected during implementation, but it must
  preserve the common call contract so nodes can be chained, reordered, replaced, or nested
  without bespoke adapters.
- Any type erasure required inside the runner/composition root is sealed there and never becomes
  a domain, action, orchestrator, or model-facing capability.

[View the Pipeline node contracts sample](../code.md#pipeline-node-interfaces).

`NodeRuntime` is deliberately capability-free:

[View the Capability-free node runtime sample](../code.md#node-runtime).

It exposes no filesystem, model, parser, renderer, validator, state, clock, logger, command, node-runner, or service-locator capability. Narrow operational ports are constructor dependencies of actions only; an ADR 0032 engine routine (not yet implemented) receives them as typed parameters, one port per step function. The outer pipeline runner records timing and telemetry around `execute`; nodes do not receive a telemetry adapter.

The common contract makes data dependencies explicit:

[View the Node contract and typed data keys sample](../code.md#node-contract-and-data-keys).

- An action declares its contract directly.
- An orchestrator's externally visible `requires`, `produces`, `replaces`, `invalidates`,
  side-effect summary, and barriers are derived and checked from its child graph by the workflow
  compiler; an orchestrator cannot hide a child's capability or claim a narrower effect.
- Its internal child-only keys are not exposed outside the composition boundary.

Examples of keys are `environment.compiled.web@1`, `reference.manifest@1`, `spec.ir@1`, `plan.ir@1`, `tasks.graph@1`, and `implementation.overlay.T007@1`. Keys are constants supplied by domain modules, never ad hoc strings inside actions.

`PipelineEnvelope` is immutable and identical for all nodes:

[View the Pipeline envelope sample](../code.md#pipeline-envelope).

- In Zig, immutable means the runner owns the envelope and every reachable allocation, a node
  receives only a bounded const view for the duration of one invocation, and the node cannot
  retain aliases into that storage.
- A returned delta owns its new allocations until the runner either applies or destroys it.
- Allocator ownership, `deinit`, `defer`, and `errdefer` behavior are part of the contract and
  are exercised on every outcome and error path.

- The registry is not an untyped property bag.
- Every value is retrieved through a versioned typed key and schema-checked on insertion.
- A node may read only keys declared by `requires`/`optional`, write only keys declared by
  `produces`/`replaces`, and invalidate only declared keys.
- Large bodies use engine-controlled content handles; arbitrary model paths are never registry
  keys.
- The illustrative `DataKey<T>` notation denotes this contract; it does not require TypeScript
  generics or a heterogeneous unchecked map in Zig.

`Outcome` is the same closed union for actions and orchestrators:

[View the Pipeline outcome sample](../code.md#pipeline-outcome).

- `PipelineEnvelope` is the sole accumulated source of data, evidence, and diagnostics.
- A node returns only a `NodeDelta`; it never repeats competing diagnostic/evidence collections
  or constructs the next envelope.
- The runner validates the delta against `NodeContract`, creates the next immutable envelope,
  and returns that applied result through a child binding.
- For an orchestrator, runner-owned bindings track child deltas and expose the composite delta;
  the orchestrator does not merge registries itself.

- `NodeDelta.telemetryFactsAdded` contains `WorkflowTelemetryFact` values.
- Each value pairs one validated four-character `WorkflowShortcode` from the active compiled
  workflow's runner-created `WorkflowLog` binding with one closed `TelemetryFact` union of IDs,
  enums, counts, timings, and outcomes.
- It contains no log level, message, arbitrary map, environment value, or raw
  model/reference/code body.
- Actions may call that narrow binding to add facts; orchestrator lifecycle/branch facts are
  derived by the runner using the same binding, so orchestrators still perform no logging work.
- After contract/delta validation, the runner's `PipelineTelemetryObserver` starts a separate
  logging-internal `PipelineEnvelope` and passes those attributed facts plus trusted run/node
  context through `FeatureLoggingOrchestrator`. Under
  [ADR 0032](../decisions/0032-engine-routines.md) (not yet implemented), feature logging
  becomes a typed engine routine once its preconditions are met. Only that change replaces the
  logging-internal envelope and logging-only `DataKey`s below with function-local values.
- Both business and logging nodes still use `PipelineNode` and return all intermediate values
  through validated `NodeDelta`s. Under [ADR 0031](../decisions/0031-stage-actions.md) (not yet
  implemented), values passed between a stage action's internal functions are function-local;
  only its stage-edge outputs are node values.
- Logging-only `DataKey`s are compiler-locked, transient, non-model-visible, excluded from
  business-envelope composition and self-observation, and destroyed by the runner on every
  terminal logging branch.
- Thus sanitized prompt records may pass between discrete logging actions without bypassing the
  common ABI, persisting in workflow state, or becoming model context.
- `WorkflowLog.log` performs only delta construction; `NodeRuntime` continues to expose no sink,
  filesystem, or direct logger capability.

- An `invalid` outcome is not an operational error.
- It is the normal input to an atomic repair orchestrator.
- Zig error unions carry unexpected operational failures to a typed failure boundary; they do
  not replace the closed workflow outcome or permit a failure to become success.
- `blocked` and `failed` are never sent to an LLM repair loop unless the diagnostic explicitly
  declares that model repair is valid.

The pipeline runner validates node contracts before execution, applies immutable deltas after a successful node, and refuses a chain with missing inputs, undeclared writes, incompatible schema versions, duplicate producers, or invalid side-effect ordering. An orchestrator schedules nodes; the runner performs contract/data plumbing.

The registered `workflow_publication` effect ends execution. The shared compiled
graph validator and registry admission require each publication outcome to target
its matching workflow terminal directly, including after subgraph expansion.
Preparing the final outcome and every fallible or telemetry-producing operation
must precede publication; even a capability-free step is not a valid successor.

- Runtime execution guards use the [F0005 execution-guard
  contract](../features/F0005-WorkflowDefinitionRegistryService.md#execution-guards).
- Gate evidence is produced by explicit YAML-visible validation operations and bound by the
  runner to the exact input generations they validated.
- A protected operation cannot run with missing, rejected, foreign, or stale evidence.
- Capabilities are derived from typed narrow-port bindings in the same operation registry and
  must fit the compiled policy ceiling.
- Guard rejection terminates execution without following a workflow transition; it introduces no
  hidden domain validation, authority refresh, or alternative evidence store.

An unexpected binding error terminates execution without applying a delta or
following a YAML outcome edge. Rejected input, delta, accounting or dependency-renewal
contracts likewise return a terminal typed runner rejection, never an `invalid` or
`failed` operation outcome. Only a declared operation outcome whose delta and runner
transitions have been accepted and applied may select a YAML successor. After an
eligible terminal failure, the engine may run the definition's declared model-free
`failure-output` subgraph in the runner's failure-output mode; it follows no transition
from the failing step and returns the original failure
([ADR 0041](../decisions/0041-failed-run-incomplete-publication.md) Decision 6, not yet
implemented).

An applied `invalid`, `needs_user`, `blocked`, `failed` or `cancelled` outcome
remains associated with its canonical native subject (including the complete
provider operation ID for a request attempt), or with its exact operation
occurrence when no native association exists. An unrelated successful operation
cannot remove it. Registered native contracts may preserve an association or
provide an explicit disposition using current sealed evidence. YAML edges and an
operation's `ok` tag cannot assert resolution. Approved reclassification, including
missing-final-answer protocol correction, requires its existing sealed proof;
ordinary preservation cannot relabel a failure.
Protocol correction retains the exact rejected inference identity; an older
correction cannot authorize continuation after a later rejected attempt.

Requests, repair permits/progress, required-authority reconciliation and
clarification admission retain their existing canonical owners. Reference-only
continuation control inside the same envelope tracks unresolved associations
without copying native records or adding a retry, ledger or admission authority.
Prepare these reference changes before applying a candidate delta and commit
them together; rejected deltas change neither. Pending outcomes guard protected
effects and require a compatible terminal. Request closure is irreversible, and
cancellation cannot be resolved through repair.
Current carrier provenance excludes historical replacement paths. A native repair
merge may use its already validated transition and exact authorization reference;
that reference alone grants neither continuation nor repair resolution.
Dependent regeneration requires the canonical merged permit awaiting dependent
review and current packet carriers covering every pending repair key. A new
unbound native invalid/blocked finding may be assessed only by a semantic review
whose current packet covers that finding; it does not gain repair authority.
Packet scope alone cannot permit a model call after a native failure.
Composed packets retain their exact current native base, plan, epoch and
prerequisite snapshots; arbitrary derived packets do not establish scope.
A retained native blocked-authorization result, with its exact current retained
inputs, may reclassify its associated invalid rejection
as blocked, without clearing that subject or its repair key. Neither disposition
allows an unrelated, failed, cancelled or needs-user outcome to be relabelled.
Incomplete publication requires current native clarification evidence carried into
the exact prepared output; matching `needs_user` tags do not grant writer access.
The runner rechecks cancellation/deadline immediately before invoking the binding,
including after potentially blocking publication log finalization.
Native repair authorization binds each unresolved subject to its exact repair
key. A joined carrier or completed child repair cannot discharge a parent or
foreign key; only that key's native validated resolution can do so. The canonical
retry owner's suspended-parent relation may permit a child repair to continue,
but grants no resolution of its parent.

#### Execution-local information stack

Configured response composition (ADR 0016) uses this same envelope; there is no
second registry or workflow action. Each selected workflow execution owns
a fresh stack. Steps, compiled subgraphs and retries share it; a new invocation
starts empty, including after `needs_user` (ADR 0009).

- Native schemas explicitly select execution-history retention independently of
  `current`/`captured`/`execution_control` dependency semantics. Unselected values
  retain their existing transient lifetime.
- The runner assigns a native occurrence before invoking a producer. A recorded
  entry binds that execution scope, occurrence and typed key to one sealed immutable
  value owner and its exact origin/dependencies. Retention shares that owner.
- Placing the same canonical value and origin again returns its existing reference
  without another entry, generation or effect. Conflicting value identity or
  provenance rejects. Independently allocated values are not inferred equivalent
  from matching text; a new invocation/repair remains distinct.
- A placement receipt proves recording only. Existing duplicate-delta, lifecycle,
  token reconciliation, retry, telemetry and publication checks remain authoritative.
- Retained history never becomes current through placement. Current slots and
  gates retain their freshness rules; ordinary nodes still receive only declared
  immutable inputs. Read-only report projections may select a registered historical
  key. The stack is never added wholesale to model context.
- Prepare record/value ownership before atomically applying the complete delta.
  Release all retained records after terminal consumers finish on every outcome.
  There is no persistence, replay of effects, checkpoint or cross-execution cache.

### 6.1 Action rules

[ADR 0016](../decisions/0016-configured-json-response-composition.md) places
generic JSON composition within this same envelope. Configured JSON
schemas do not define native pipeline keys: sealed registered values retain the
compiled parts, current dependencies and real producer origins. Assembly proposes
one candidate delta; the runner alone applies it. Staging is retired in the candidate-installation delta; its immutable owners
remain retained only as candidate evidence and cannot overwrite later native repairs.

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

- An action that reads a file does not also parse it.
- An action that invokes a model does not parse or validate the response.
- An action that validates a path does not write that path.
- An action that publishes output does not decide whether validation passed; it consumes the
  complete validated output set through its declared publication port.

[ADR 0031](../decisions/0031-stage-actions.md) (not yet implemented) adds the **stage action**:
one registered action whose verb-object responsibility is a deterministic sequence of internal
steps that routes no outcome. The ADR fixes its contract fields: side effect `none` or `filesystem_read`,
repair role and runner accounting `none`, outcome association `independent`, no retry
authority and no model binding.

- Its internal steps are typed functions. Each has one responsibility and takes at most one
  port parameter. `execute` takes the capability-free `NodeRuntime`, only calls them in order
  with a cancellation check between them, and calls no port itself. No internal function takes the `Action` value or a multi-port
  struct.
- Read versus parse applies to those functions: a function that reads does not parse.
- The other three splits above are unaffected, because a stage action never invokes a model,
  writes or publishes.
- A stage action absorbs only steps whose non-success outcomes all end the stage. Every routed
  outcome stays a YAML transition.

### 6.2 Orchestrator rules

Every orchestrator must:

- express a static or data-driven sequence of child nodes;
- branch only on typed `Outcome` and diagnostic metadata;
- pass immutable envelopes between children;
- coordinate a bounded cycle only when its runner-owned binding carries the
  compiler-validated retry limit declared explicitly by that YAML operation
  instance, or a registered finite-iteration contract bound to a validated
  population and a strictly advancing cursor;
- never open files, call models, parse responses, render content, validate rules, execute commands, or mutate task state directly;
- be testable with spy/fake child nodes;
- allow child orchestrators, while preventing cycles in the orchestration graph.

- Every orchestrator that represents workflow behavior must be bound to a unversioned operation
  ID in the single registry and callable through YAML.
- An unregistered orchestrator is permitted only for an engine-kernel responsibility explicitly
  named by ADR 0005.
- An operation's private child graph may implement that operation's one atomic contract; it
  cannot conceal workflow transitions, retry/repair policy, model-slot or resource selection, or
  a domain stage. An [ADR 0031](../decisions/0031-stage-actions.md) stage action is not a child
  graph: its stage is its declared responsibility, and its internal steps are functions with no
  routed outcomes.
- [ADR 0030](../decisions/0030-engine-owned-model-request.md) (not yet implemented) names the
  stage sequence of one model request as an ADR 0005 kernel responsibility. A fixed,
  capability-free kernel orchestrator implements the registered `request-model` operation,
  with the stage actions as its runner-owned child bindings.
  ADR 0030 narrowly amends the previous rule for it: its child graph may contain exactly one
  retry, the request's protocol correction, bounded by the step's declared `retry-limit`. It
  still cannot conceal workflow transitions, repair policy, slot or resource selection, or a
  domain stage. Each stage keeps its own narrow ports.

- Architecture tests fail the build if an action field or constructor parameter is a
  `PipelineNode`, `Action`, `Orchestrator`, dispatcher, executor callback, node runner, or
  service locator; if an action imports an orchestrator namespace; if any node calls another
  node's `execute` outside an orchestrator module; or if an orchestrator imports anything
  outside an allowlist of contracts, outcomes, envelopes, loop controls, and child-node
  bindings.
- Orchestrator modules cannot import infrastructure or domain-operation adapters.
- For [ADR 0032](../decisions/0032-engine-routines.md) engine routines (not yet implemented),
  the tests also check:
  - a `*_routine.zig` imports only domain and port modules, never adapters or `std.Io`;
  - no step takes two ports, the port set, a capability bag, `anytype` or `anyopaque`;
  - the entry function calls no port method;
  - no `*anyopaque` child-binding context remains for a converted sequence.

### 6.3 Reordering and composition rules

The internal steps of an [ADR 0031](../decisions/0031-stage-actions.md) stage action (not yet implemented) can't be reorganized from YAML; changing them changes the stage action.

Actions and orchestrators can be reorganized without changing their implementation when their contracts remain satisfiable:

1. Before producing an executable graph, the workflow compiler calculates the keys available at each position.
2. A node is placeable when all `requires` keys exist at compatible schema versions.
3. `produces` adds a new key; `replaces` requires and atomically replaces an existing key; `invalidates` removes stale downstream keys.
4. Two pure/read nodes with satisfied inputs may be reordered or run concurrently when neither invalidates/replaces a key used by the other.
5. Model calls, candidate writes, commands, and commits create declared barriers. A commit cannot move before its validation-authorization key exists.
6. A node cannot depend on execution order that is not represented by a required data/evidence key or an ordering barrier.
7. The workflow compiler rejects every unbounded cycle. A retry or repair cycle
   is valid only when it crosses a registered monotonic budget operation with a
   finite compiler-validated ceiling; the diagnostic identifies a cycle that
   lacks such a guard before runtime. Native repair progress uses the registered
   roles, finite keys and monotonic per-key counts in [§22.7](22-repair.md#227-repair-retry-limit-and-escalation);
   it does not reset a graph counter or hide child execution.
8. Native iteration over a validated finite population uses registered initializer
   and advancement contracts, with explicit scope and progress data keys. Only
   the declared advancing outcome guards a cycle; failure edges do not. The
   runner binds the population limit and cursor to their current generations,
   accepts exactly one cursor increment per advancement, and rejects stale,
   repeated, skipped or exhausted progress. Initialization cannot lie on a cycle
   that bypasses an independent retry guard. A new validated scope after upstream
   repair may initialize a fresh pass; the same scope cannot reset its cursor.
   Native facts and pipeline values commit together. Each accepted advancement
   adds one graph traversal to the runner's retry-derived execution allowance;
   rejected deltas add none. This is finite iteration, not semantic retry policy,
   and does not alter model retry limits or the workflow token budget. YAML owns
   every transition; the generic engine remains capability-free.

This enables, for example, swapping one filename validator implementation,
moving source parsing earlier, or composing a declared semantic-review step
without changing adjacent operations. Typed keys keep information passing
simple while preserving testability and preventing hidden state.
