# ADR 0005: Configure workflow behavior in workflow definitions

- **Status:** Accepted
- **Date:** 2026-09-03
- **Decision authority:** User decisions, 3 and 6 September 2026
- **Supersedes:** The compiler-owned built-in model-route registry in proposed
  design Section 12.7, its route-resolution actions, and every requirement for
  a fixed route-to-`models.slots` assignment
- **Amends:** ADR 0003 and the F0005/F0006 workflow and model-operation contracts
- **Amended by:** [ADR 0011](0011-provider-owned-request-limits.md),
  [ADR 0013](0013-workflow-input-reuse.md),
  [ADR 0030](0030-engine-owned-model-request.md), [ADR 0031](0031-stage-actions.md),
  [ADR 0033](0033-generic-repair-operations.md)

## Decision

YAML explicitly describes configurable workflow behavior without duplicating large
resources at every node.

- There is no built-in workflow or model-route catalogue.
- The workflow definition is the sole authority for workflow topology and for selecting
  the operations that make up that workflow.

- The engine exposes one registry of current generic operation contracts.
- Every non-kernel workflow operation is addressable from workflow YAML by its
  registered ID; a non-kernel operation without such an ID is prohibited.
- A definition can call only a registered operation and can set only parameters declared
  safe by that operation's closed contract.
- Adding a workflow from existing operations requires no engine rebuild.
- Adding executable behavior or a capability still requires a new reviewed engine
  operation; YAML cannot supply code, an adapter, a capability, or an unrestricted
  command.

- No workflow-specific sequence, model route, prompt selection, schema selection,
  model-slot selection, retry branch, repair branch, or success rule may be hidden
  behind a workflow name or an inaccessible engine registry.
- Sequencing and branching are visible in the YAML graph.
- An operation retains one cohesive responsibility and must not conceal a second
  workflow graph. ADR 0030's `request-model` operation runs one fixed kernel stage
  sequence for one model request; it is not a workflow graph. Its internal retries are the
  protocol correction, bounded by the step's declared `retry-limit`, and ADR 0039's one
  runaway re-send per attempt, which is outside `retry-limit`.
- A stage action ([ADR 0031](0031-stage-actions.md)) owns a deterministic sequence of
  internal steps that routes no outcome. Every routed outcome stays a YAML transition. The
  internal steps are functions, not workflow operations or a second workflow graph, so
  they are not addressable or composable from YAML. Composing them differently needs a new
  stage action and an engine rebuild.

- Engine-kernel enforcement is not workflow functionality and is not callable or
  bypassable from YAML.
- Loading, parsing, compilation, contract validation, capability derivation,
  runner-owned invocation and delta application, provider preparation, cancellation,
  cleanup, security enforcement and the stage sequence of one model request
  ([ADR 0030](0030-engine-owned-model-request.md)) are fixed engine responsibilities.
- They may inspect only the compiled definition and registered contracts; they cannot
  add domain workflow behavior.

### Unversioned operation IDs

- Operation contracts are not versioned.
- Each operation has one current contract and one unversioned ID, such as
  `request-model`. That one contract may consist of closed variants selected at compile
  time by one closed step parameter; [ADR 0030](0030-engine-owned-model-request.md)
  "Contract variants" owns the mechanism, and
  [ADR 0033](0033-generic-repair-operations.md)'s four generic repair operations use it.
  `request-model` has one contract with no variants.
- Both `invoke` and `steps.*.use` name that ID directly.
- No operation-version field, version suffix, range, compatibility alias or parallel
  legacy contract is retained.
- The compiler and runner enforce the current closed contract.
- Workflow-definition, data-schema, policy and preset versions are unchanged.
- Tests reject retired spellings and version fields; the packaged executable also
  rejects suffixed invocation and step IDs.

### Concise workflow form

- The workflow-definition contract uses YAML mappings and native scalar values
  instead of repeated tagged `{ kind, value }` parameter objects.
- Field names may be concise aliases, and node IDs provide the local identity used by
  transitions.
- The compiler obtains each parameter's type, bounds, and allowed values from the
  selected operation contract.

The exact compact schema is owned by [F0005](../features/F0005-WorkflowDefinitionRegistryService.md#32-root-shape)
and its formal schema. The [provider-request test fixture](../../test/packaging/fixtures/provider-request/provider-request.workflow.yaml)
shows a `request-model` step with its release; the [Specify definition](../workflows/spec.workflow.yaml)
shows reusable subgraphs and one `request-model` step per model request (ADR 0030).

Each operation step has one registered reference, optional compact parameters and
an explicit outcome map. ADR 0013 permits `call` steps expanded by the same compiler.
There is one current reader, with no verbose-transport compatibility form.

- Large prompts, examples, and schemas may be declared once as workflow-owned resources
  and referenced by short local IDs.
- Every resource is explicitly named by the YAML, captured from an authorized
  project-owned root, bounded, typed, and compiled into immutable workflow authority
  before execution.
- The engine does not substitute a packaged prompt, schema, route descriptor, or other
  hidden default.
- Inline bounded values may be supported where concise.

### Model operations

An originating generic model-request step declares in YAML:

- the repository model slot from `.sddtoolkit.json`;
- the prompt/guidance and result-schema resource references;
- the typed inputs, outputs, controls, and allowed context behavior required by that
  operation; and
- every outcome transition, including repair, failure, and cancellation.

- [ADR 0011](0011-provider-owned-request-limits.md) owns the size-limit and actual-usage
  accounting rules. The runner enforces accounting without a YAML bypass or hidden model
  route.

- The token budget supplies no retry count.
- Any operation instance that can take a retry transition must declare its own
  `retry-limit` in `with`; the registered operation contract bounds that value and the
  compiler rejects a missing limit or an unbounded retry cycle.
- An operation with no retry path does not acquire a hidden retry.
- Atomic repair counts are scoped to native defects with validated progress, as defined in [§22.7](../contracts/22-repair.md#227-repair-retry-limit-and-escalation).
  Registered contracts declare that scope; YAML supplies allowances, not defect identity.

- The workflow never names a provider or model directly.
- The originating step's selected slot must resolve through
  `ValidatedRepositoryModelAllowlist` to the immutable provider registry entry prepared
  for that invocation.
- Authorization cannot silently replace the YAML's slot, resources, control flow, or
  requested operation semantics.

- Under [ADR 0012](0012-workflow-owned-model-request.md), the stable model-operation
  identity is derived from the compiled workflow ID, version and originating step.
- Separate YAML consumers retain the same request through typed pipeline data; they do
  not repeat slot/resource controls or substitute their own step ID.
- The internal request contract is `model-request/v1`, not a YAML resource.
- Logging and request identity use the originating identity instead of a built-in route
  ID.
- A workflow-resource change is a workflow-authority change, handled by the same
  compilation and state-binding rules as a graph change.
- Request state remains execution-local; ADR 0009 permits no interrupted-workflow
  resumption.

## Consequences

- End users configure workflows by composing the generic operations exposed by the
  engine and supplying explicit workflow-owned resources.
- The engine has one operation registry, not separate pipeline-node and model-route
  registries with overlapping authority.
- `.sddtoolkit.json` remains the repository model allowlist and `.sddproviders.json`
  remains the provider catalogue.
- Workflow YAML selects an allowed slot; neither configuration file defines workflow
  control flow.
- The selected workflow policy does not own the per-execution token budget
  ([ADR 0011](0011-provider-owned-request-limits.md)).
- Retry limits are explicit per retry-capable operation instance and are never inherited
  from configuration, provider policy, or a global retry default.
- Workflow definitions stay compact through mappings, native scalars, local resource
  aliases, and reuse.
- Large prompts and schemas are not copied into each step.
- No legacy syntax, built-in route fallback, or dual authority is retained.
- This decision does not make project YAML executable code, allow dynamic plugins, or
  weaken validation, path, provider, command, publication, or capability boundaries.
