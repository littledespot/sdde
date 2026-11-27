# ADR 0004: Derive and conditionally prepare model-provider authority

- **Status:** Accepted
- **Date:** 2026-09-02
- **Decision authority:** User decisions, 2 and 5 September 2026 and 22 October 2026
- **Amends:** ADR 0003's rule that setup beyond engine startup appears only as
  project-graph setup nodes, solely for model-provider run preparation
- **Amended by:** [ADR 0011](0011-provider-owned-request-limits.md),
  [ADR 0032](0032-engine-routines.md)

## Context

Engine startup must load and compile workflow definitions before a workflow can be
selected. Provider-catalogue loading cannot belong to that unconditional sequence because
a selected workflow without a model-binding requirement or provider-call capability must
not probe or read `.sddproviders.json`.

Project workflow data also cannot choose whether provider preparation runs. Binding
requirements come only from registered operation contracts; operational capabilities are
derived from their concrete narrow ports. Both are preserved in the validated compiled
graph.

## Decision

### Placement and requirement

- Model-provider bootstrap is a fixed, nonselectable typed engine routine
  ([ADR 0032](0032-engine-routines.md)). The composition root or a runner-owned binding
  reaches it.
- It runs after exact workflow selection and before selected-workflow execution.
- It is engine machinery: project definitions cannot select, replace, extend, or invoke
  it.

The routine's first step derives the requirement in the domain. It is the sole
branch-fact owner. It examines only the selected validated compiled graph and returns a
closed requirement:

- `required` when any compiled step has a model-binding requirement or the exact
  compiler-owned provider-call capability ID `model-provider`;
- `not_required` otherwise.

- The derivation does not infer from workflow IDs, step IDs, parameter names, policy
  allowance alone, `.sddtoolkit.json`, provider configuration, or operation names.
- A project definition cannot author a capability; the workflow compiler can preserve
  only capabilities supplied by registered node contracts and allowed by the selected
  policy.

### Binding and capability ownership

- For a new request, the model-binding requirement is the existing typed
  `CompiledStep.model` projection, not a second flag or registry.
- Its registered contract declares exactly one typed model-slot parameter and explicit
  response controls, without capacity fields or size parameters.
- Pure preparation and validation operations may require this binding without holding a
  provider port.
- Under [ADR 0012](0012-workflow-owned-model-request.md), the originating step
  selects that binding once after catalogue bootstrap.
- Consumers declare the typed prepared-request/ledger dependencies and receive its
  retained immutable binding, not a selection rebound to the consumer step.
- They cannot override its slot, resources or controls.
- Existing graph dataflow proves the required producer; there is no second binding
  registry.
- `model-provider` still derives only from the concrete provider-call port, remains
  policy-gated, and requires a model binding.
- Binding data never grants that port.
- Model-slot access is not equivalent to the provider-call capability, and bootstrap is
  not derived from capability alone.
- It adds no hidden operations or provider calls.
- Capacity values are not needed for registration, compilation, bootstrap or pure
  preparation.

### Conditional preparation

- The routine branches only on that typed requirement.
- The `not_required` branch performs no provider file probe, read, decode, registry, or
  allowlist work.
- The `required` branch locates and reads the provider document, decodes it, and builds
  and validates the registry and the repository allowlist before graph execution.
- Each step is a function with only the port it uses, and values pass as typed
  arguments. The locate and read steps hold the provider-config port; no step holds a
  registry-mutator, provider, network, credential, logger, state, transaction, or command
  capability.

### Immutable provider snapshot

- For a `required` branch, F0008 captures `.sddproviders.json` exactly once.
- That capture is the only provider-document read for the engine invocation.
- The validated registry and repository allowlist derived from it are the immutable
  provider authority for the remainder of the invocation; the untrusted capture may be
  destroyed after preparation.
- The engine does not stat, reopen, reread, refresh, hot-reload, or monitor the provider
  document during that invocation.
- A later filesystem change cannot alter the active invocation and is visible only to a
  new invocation.
- There is no last-known-good fallback or cross-invocation provider-registry cache.

## Consequences

- Engine startup remains the sole loader/compiler of project workflow authority.
- Model-provider preparation is conditional engine-owned run preparation, not a
  project-authored graph or workflow-name special case.
- This decision accepts the placement, requirement derivation, and immutable
  per-invocation provider snapshot.
- Adding another engine-level conditional preparation concern requires its own accepted
  typed policy; this decision does not create a generic hook system.
