# 6. Common action and orchestrator contract

Part of the [proposed design](../design.md#6-common-action-and-orchestrator-contract). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

- Every action **and** every orchestrator conforms to the same runtime contract.
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

It exposes no filesystem, model, parser, renderer, validator, state, clock, logger, command, node-runner, or service-locator capability. Narrow operational ports are constructor dependencies of actions only. The outer pipeline runner records timing and telemetry around `execute`; nodes do not receive a telemetry adapter.

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
  context through `FeatureLoggingOrchestrator`.
- Both business and logging nodes still use `PipelineNode` and return all intermediate values
  through validated `NodeDelta`s.
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
following a YAML outcome edge. Expected failures return their declared typed
data and follow the ordinary validated YAML outcome; no successor may run on
an error that failed to produce its promised inputs.

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

- An action that reads a file does not also parse it.
- An action that invokes a model does not parse or validate the response.
- An action that validates a path does not write that path.
- An action that publishes output does not decide whether validation passed; it consumes the
  complete validated output set through its declared publication port.

### 6.2 Orchestrator rules

Every orchestrator must:

- express a static or data-driven sequence of child nodes;
- branch only on typed `Outcome` and diagnostic metadata;
- pass immutable envelopes between children;
- coordinate a bounded cycle only when its runner-owned binding carries the
  compiler-validated limit declared explicitly by that YAML operation
  instance;
- never open files, call models, parse responses, render content, validate rules, execute commands, or mutate task state directly;
- be testable with spy/fake child nodes;
- allow child orchestrators, while preventing cycles in the orchestration graph.

- Every orchestrator that represents workflow behavior must be bound to a unversioned operation
  ID in the single registry and callable through YAML.
- An unregistered orchestrator is permitted only for an engine-kernel responsibility explicitly
  named by ADR 0005.
- An operation's private child graph may implement that operation's one atomic contract; it
  cannot conceal workflow transitions, retry/repair policy, model-slot or resource selection, or
  a domain stage.

- Architecture tests fail the build if an action field or constructor parameter is a
  `PipelineNode`, `Action`, `Orchestrator`, dispatcher, executor callback, node runner, or
  service locator; if an action imports an orchestrator namespace; if any node calls another
  node's `execute` outside an orchestrator module; or if an orchestrator imports anything
  outside an allowlist of contracts, outcomes, envelopes, loop controls, and child-node
  bindings.
- Orchestrator modules cannot import infrastructure or domain-operation adapters.

### 6.3 Reordering and composition rules

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
   lacks such a guard before runtime.

This enables, for example, swapping one filename validator implementation,
moving source parsing earlier, or composing a declared semantic-review step
without changing adjacent operations. Typed keys keep information passing
simple while preserving testability and preventing hidden state.
