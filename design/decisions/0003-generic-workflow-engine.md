# ADR 0003: Load and execute declarative workflows generically

- **Status:** Accepted
- **Date:** 2026-08-29
- **Decision authority:** Explicit user direction
- **Supersedes:** The fixed four-role workflow registry and compiler-owned
  four-workflow graph described in Sections 5.2, 9.1, 9.2, 30, and 31 of the
  proposed design

## Context

The proposed design treats `specify`, `plan`, `tasks`, and `implement` as the
only workflow roles. It requires exactly one definition for each role and lets
each definition select a complete compiler-owned workflow graph. That makes
`paths.workflows` configurable while leaving the engine itself fixed to four
known workflows.

SDDE instead needs to be a deterministic workflow engine. A project may add
workflow definitions beneath its configured `paths.workflows` root, and the
engine must be able to validate and execute any supported definition without
adding the workflow's identity to the engine source.

## Decision

`paths.workflows` contains an arbitrary bounded number of closed declarative
workflow definitions. `features/` and `transactions/` remain reserved
engine-owned children and are excluded from definition traversal.

Each definition has a validated project-authored `WorkflowId`, version,
workflow logging shortcode, registered invocation-contract node, graph of
engine-registered `PipelineNode` contract references, closed parameters, and
typed outcome transitions. Definitions contain no executable code.

The workflow runtime has four separate responsibilities:

1. The workflow loader inventories, captures, and parses definitions.
2. The workflow compiler validates identities, node contracts, parameters,
   transitions, gates, and effective capabilities and produces an immutable
   executable graph.
3. The workflow registry indexes validated compiled graphs by `WorkflowId`.
4. The capability-free workflow engine orchestrator selects one registered
   workflow and follows its compiled typed transitions using only runner-owned
   child bindings; the common runner remains the sole node invocation and delta
   application owner.

A small compiler-locked engine-startup graph is assembled by the composition
root so the runner can load, compile, and register project workflows before one
of them exists to execute. This graph is engine machinery, not a project
workflow: it is not discovered beneath `paths.workflows`, cannot be selected,
cannot be extended by a definition, and acquires no project/feature transaction
lock.

Every encountered definition must validate, every `WorkflowId` and logging
shortcode must be unique, and an invocation must resolve its requested
`WorkflowId` exactly once. Bootstrap requires no particular workflow name or
fixed definition count.

A definition may compose only compiler-registered node contracts and may use
only their closed parameter and outcome schemas under an allowed workflow
policy profile. It cannot load code, name an infrastructure adapter, provide a
raw path or command, grant a capability, bypass runner delta validation, or
weaken a node's gate. Adding new executable node behavior or a new capability
still requires an engine change and the normal architecture and security
tests.

The selected definition's invocation contract is itself a registered
capability-free pipeline node. It owns conversion of remaining arguments into
validated typed run context; when parsing and validation are separate actions,
the node is an orchestrator that coordinates their runner-owned bindings. The
workflow engine coordinates that node before graph entry, then supplies only
the validated run context to the graph. Project/feature/toolchain setup beyond
the minimal engine-startup graph is included only when the selected workflow
graph references the corresponding registered setup nodes.

`specify`, `plan`, `tasks`, and `implement` are the initial workflow suite, not
special cases in the generic engine. Their registered node contracts and
domain gates continue to enforce `specify -> plan -> tasks -> implement` for a
feature. A different workflow is not placed into that sequence unless its own
validated contract declares the relevant predecessor authority.

## Consequences

- Adding a definition that uses existing registered nodes, invocation
  contracts, policy profiles, and state contracts does not require rebuilding
  the engine.
- Durable feature state records the workflow IDs whose compiled graphs have
  participated in that feature. Change classification compares only each bound
  graph's stable semantic authority; source inventory ordinals, registry
  identity, and validation evidence are provenance and do not participate.
  Changing a bound semantic graph requires the existing administrative
  migration route; changing only an unrelated definition does not invalidate
  the feature.
- Bootstrap validates a variable-size workflow registry rather than requiring
  exact four-role coverage.
- The composition root registers concrete node implementations and adapters;
  it no longer resolves complete workflows by hard-coded workflow name.
- The workflow engine remains a capability-free orchestrator. Only
  runner-invoked actions receive their narrow declared ports, and every
  orchestrator—including the workflow engine—receives only runner-owned child
  bindings.
- SDD predecessor validation, approvals, clarification ownership, artifact
  paths, and invalidation remain domain contracts of the four initial
  workflows.
- This decision does not accept the remainder of the proposed design, define a
  plugin or dynamic-library system, permit project-authored executable code, or
  authorize running SDDE against a target project.
