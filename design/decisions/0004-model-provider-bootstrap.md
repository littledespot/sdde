# ADR 0004: Derive and conditionally prepare model-provider authority

- **Status:** Accepted
- **Date:** 2026-09-02
- **Amended:** 2026-09-03
- **Decision authority:** Explicit user direction
- **Amends:** ADR 0003's rule that setup beyond the startup graph appears only
  as project-graph setup nodes, solely for model-provider run preparation

## Context

The fixed startup graph must load and compile workflow definitions before a
workflow can be selected. Provider-catalogue loading cannot belong to that
unconditional graph because a selected workflow without model capability must
not probe or read `.sddproviders.json`.

Project workflow data also cannot choose whether provider preparation runs.
Capabilities come only from compiler-registered node contracts and are already
preserved in the validated compiled graph.

## Decision

The composition root owns a fixed, nonselectable, capability-free
`ModelProviderBootstrapOrchestrator`. It runs after exact workflow selection
and before selected-workflow execution. It is engine machinery: project
definitions cannot select, replace, extend, or invoke it.

`DeriveProviderRequirementAction` is the sole branch-fact owner. It examines
only the selected validated compiled graph and returns a closed requirement:

- `required` when any compiled node contract contributes the exact
  compiler-owned capability ID `model-provider`;
- `not_required` otherwise.

The action does not infer from workflow IDs, node IDs, parameters, policy
allowance alone, `.sddtoolkit.json`, provider configuration, or route names.
A project definition cannot author a capability; the workflow compiler can
preserve only capabilities supplied by registered node contracts and allowed
by the selected policy.

The orchestrator may branch only on that typed requirement through
runner-owned child bindings. The `not_required` branch performs no provider
file probe, read, decode, registry, or allowlist work. The `required` branch
coordinates the already separated F0008 and F0006 actions before graph
execution. The orchestrator receives no filesystem, parser, registry-mutator,
provider, network, credential, logger, state, transaction, or command
capability.

For a `required` branch, F0008 captures `.sddproviders.json` exactly once. That
capture is the only provider-document read for the engine invocation. The
validated registry and repository allowlist derived from it are the immutable
provider authority for the remainder of the invocation; the untrusted capture
may be destroyed after preparation. The engine does not stat, reopen, reread,
refresh, hot-reload, or monitor the provider document during that invocation.
A later filesystem change cannot alter the active invocation and is visible
only to a new invocation. There is no last-known-good fallback or
cross-invocation provider-registry cache.

## Consequences

- The unconditional startup graph remains the sole loader/compiler of project
  workflow authority.
- Model-provider preparation is conditional engine-owned run preparation, not
  a project-authored graph or workflow-name special case.
- This decision accepts the orchestration owner, placement, requirement
  derivation, and immutable per-invocation provider snapshot. The fixed
  orchestrator and runner bindings implement that conditional preparation;
  ordinary invocation composition, a production provider adapter, and model
  operations remain separate increments.
- Adding another engine-level conditional preparation concern requires its own
  accepted typed policy; this decision does not create a generic hook system.
