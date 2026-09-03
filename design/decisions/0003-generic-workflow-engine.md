# ADR 0003: Load and execute declarative workflows generically

- **Status:** Accepted
- **Date:** 2026-08-29
- **Decision authority:** Explicit user direction
- **Amended by:** [ADR 0005 — workflow-defined operations](0005-workflow-defined-operations.md)
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
workflow definitions and only the bounded resources those definitions
explicitly declare. `features/` and `transactions/` remain reserved
engine-owned children and are excluded from workflow-authority traversal.

Each definition has a validated project-authored `WorkflowId`, version,
workflow logging shortcode, registered invocation operation, graph of
engine-registered generic operation references, closed parameters, declared
workflow-owned resources, and typed outcome transitions. Definitions contain
no executable code. ADR 0005 owns the concise YAML representation and prohibits
a separate built-in model-route registry or hidden workflow behavior.

The workflow runtime has four separate responsibilities:

1. The workflow loader inventories, captures, and parses definitions.
2. The workflow compiler validates identities, operation contracts, parameters,
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

A definition may compose only compiler-registered operation contracts and may use
only their closed parameter and outcome schemas under an allowed workflow
policy profile. It cannot load code, name an infrastructure adapter, provide a
raw path or command, grant a capability, bypass runner delta validation, or
weaken an operation's gate. Adding new executable operation behavior or a new capability
still requires an engine change and the normal architecture and security
tests.

The selected definition's invocation contract is itself a registered
capability-free pipeline node. It owns conversion of remaining arguments into
validated typed run context; when parsing and validation are separate actions,
the node is an orchestrator that coordinates their runner-owned bindings. The
workflow engine coordinates that node before graph entry, then supplies only
the validated run context to the graph. Project/feature/toolchain setup beyond
the minimal engine-startup graph is included only when the selected workflow
graph references the corresponding registered setup operations.

`specify`, `plan`, `tasks`, and `implement` are the initial workflow suite, not
special cases in the generic engine. Their YAML definitions explicitly select
the registered operation contracts whose domain gates enforce
`specify -> plan -> tasks -> implement` for a feature. A different workflow is
not placed into that sequence unless its own definition selects the relevant
predecessor-gate operation.

## Consequences

- Adding a definition that uses existing registered operations, invocation
  contracts, policy profiles, and state contracts does not require rebuilding
  the engine.
- Every non-kernel workflow operation is addressable from YAML through the one
  generic operation registry; only the engine-kernel responsibilities named by
  ADR 0005 remain non-callable.
- Durable feature state records the workflow IDs whose compiled graphs have
  participated in that feature. Change classification compares only each bound
  graph's stable semantic authority; source inventory ordinals, registry
  identity, and validation evidence are provenance and do not participate.
  Changing a bound semantic graph requires the existing administrative
  migration route; changing only an unrelated definition does not invalidate
  the feature.
- Bootstrap validates a variable-size workflow registry rather than requiring
  exact four-role coverage.
- The composition root registers concrete generic operation implementations and adapters;
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
