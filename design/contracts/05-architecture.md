# 5. Logical architecture

Part of the [proposed design](../design.md#5-logical-architecture). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

[View the logical architecture diagram](../diagrams/01-logical-architecture.md).

### 5.1 Layers

1. **Interface adapters** parse CLI/API input and present final reports. They contain no workflow decisions.
2. **Application orchestration** contains the generic workflow-engine
   orchestrator and registered reusable operation orchestrators. The engine
   selects one compiled graph and follows its YAML-declared typed transitions
   through runner-owned child bindings. A workflow-visible orchestrator is
   addressable from YAML and cannot hide a workflow-specific graph; all
   orchestrators own ordering and branching only, not domain work.
3. **Actions** perform one use-case operation each: read one resource, invoke one model request, validate one concern, render one artifact, publish authorized workflow output, or execute one configured command.
4. **Domain** contains immutable intermediate representations, identifiers, diagnostics, policies, and result types.
5. **Infrastructure adapters** implement filesystem, model-provider, parser, command-runner, clock, logging, and reader ports.
6. **Workflow/preset/config compilers** validate declarative workflow graphs,
   the project toolchain layer, preset packages, and raw configuration into
   normalized executable graphs and policy. Downstream components use only
   validated registries and compiled results.

### 5.2 Dependency direction

Application and domain code depend on interfaces, never provider implementations. The LLM SDK, OS filesystem, shell/process API, YAML parser, Markdown parser, AST parser, and logger are adapters behind ports. This permits action unit tests without network access, repository mutation, or a real compiler.

- In Zig, this dependency direction is enforced through module imports, build configuration, and
  an independent architecture test.
- Filesystem, process, network/HTTP, C ABI, and provider-client imports are confined to their
  declared adapter modules.
- Domain modules cannot reach those capabilities through a generic context, erased service
  locator, or transitive re-export.

- Orchestrators receive runner-owned `ChildNodeBinding` instances resolved from the validated
  compiled graph and the composition root's registered operation implementations, never raw
  child nodes.
- They do not receive `FileSystem`, `LLMProviderInterface`, `CommandRunner`, parser, or
  validator ports.
- This makes the rule “orchestrators organize; actions do” mechanically enforceable and prevents
  child execution from bypassing the runner.

- The composition root registers concrete generic operation implementations in one registry of
  current operation contracts and binds their pipeline nodes and infrastructure adapters.
- It assembles the fixed engine-startup graph that loads and compiles project workflow
  definitions and the separate fixed, nonselectable, capability-free
  `ModelProviderBootstrapOrchestrator` accepted by ADR 0004.
- Project definitions cannot change either mechanism.
- The startup graph remains unconditional.
- After exact workflow selection, `DeriveProviderRequirementAction` inspects only compiled
  model-binding requirements and provider-call capabilities; the run-preparation orchestrator
  conditionally coordinates the provider-file children before selected-workflow execution.
- The workflow loader inventories and parses the definitions beneath `paths.workflows`.
- The workflow compiler alone resolves each referenced operation contract by its unversioned ID,
  validates its closed parameters and typed transitions, proves the effective graph and
  capability set are permitted by the selected workflow policy, and produces an immutable
  executable graph.
- The workflow registry owns the unique `WorkflowId -> CompiledWorkflowGraph` mapping.
- The generic workflow-engine orchestrator coordinates exact selection actions, invokes the
  selected YAML-named invocation operation through a runner-owned binding, then follows the
  graph's typed transitions through runner-owned child bindings; the runner remains the sole
  node invocation and delta-application owner.

- A project definition describes graph topology only with registered generic operation
  contracts.
- It explicitly selects each operation, its definition-safe parameters and workflow-owned
  resources, and every outcome transition.
- It cannot supply executable code, select a concrete adapter, provide an operational raw path
  or command, add a capability, bypass runner delta validation, or weaken a referenced
  operation's gate.
- The initial `specify`, `plan`, `tasks`, and `implement` definitions use registered contracts
  whose predecessor gates preserve their required feature order; that order is not a global
  restriction on unrelated workflows.
- No workflow name activates additional engine-owned domain behavior.
