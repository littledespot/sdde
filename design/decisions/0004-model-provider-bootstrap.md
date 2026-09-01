# ADR 0004: Derive and conditionally prepare model-provider authority

- **Status:** Accepted
- **Date:** 2026-09-02
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
will coordinate the already separated F0008 and F0006 actions before graph
execution. The orchestrator receives no filesystem, parser, registry-mutator,
provider, network, credential, logger, state, transaction, or command
capability.

## Consequences

- The unconditional startup graph remains the sole loader/compiler of project
  workflow authority.
- Model-provider preparation is conditional engine-owned run preparation, not
  a project-authored graph or workflow-name special case.
- This decision accepts the orchestration owner, placement, and requirement
  derivation. It does not yet implement the runner bindings, provider-file
  branch, active-run change policy, provider adapter, or model operation.
- Adding another engine-level conditional preparation concern requires its own
  accepted typed policy; this decision does not create a generic hook system.
