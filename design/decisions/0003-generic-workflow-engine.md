# ADR 0003: Load and execute declarative workflows generically

- **Status:** Accepted
- **Date:** 2026-08-29
- **Decision authority:** User decisions, 29 August and 5 September 2026
- **Amended by:** [ADR 0004](0004-model-provider-bootstrap.md),
  [ADR 0005](0005-workflow-defined-operations.md),
  [ADR 0009](0009-atomic-workflow-execution.md), [ADR 0031](0031-stage-actions.md),
  [ADR 0032](0032-engine-routines.md)
- **Supersedes:** The fixed four-role workflow registry and compiler-owned
  four-workflow graph described in Sections 5.2, 9.1, 9.2, 30, and 31 of the
  proposed design

## Decision

SDDE validates and executes project definitions composed from supported contracts without
adding workflow identities to engine source.

### Definition inventory

- `paths.workflows` contains an arbitrary bounded number of closed declarative workflow
  definitions and only the bounded resources those definitions explicitly declare.
- Only the root `features/` child is reserved for engine state and excluded from
  workflow-authority traversal.
- Other directories have no reserved status and follow ordinary definition/resource
  inventory rules.
- There is no project-level transaction directory, WAL, ledger, lock or recovery
  prerequisite. Feature activation follows Design Section 25.1; this machinery must not be
  relocated under another path.

- Each definition has a validated project-authored `WorkflowId`, version, workflow
  logging shortcode, registered invocation operation, graph of engine-registered generic
  operation references, closed parameters, declared workflow-owned resources, and typed
  outcome transitions.
- Definitions contain no executable code.
- ADR 0005 owns the concise YAML representation and prohibits a separate built-in
  model-route registry or hidden workflow behavior.

### Runtime ownership

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

- Engine startup is a typed engine routine ([ADR 0032](0032-engine-routines.md)) that the
  composition root runs to load, compile, and register project workflows before one of
  them exists to execute.
- It is engine machinery, not a project workflow: it is compiler-locked, is not
  discovered beneath `paths.workflows`, cannot be selected, cannot be extended by a
  definition, and acquires no feature lock.
- The internal steps of a stage action ([ADR 0031](0031-stage-actions.md)) are functions,
  not workflow operations, so they are not addressable from YAML; the stage action itself
  is.

### Compilation and invocation rules

- Every encountered definition must validate, every `WorkflowId` and logging shortcode
  must be unique, and an invocation must resolve its requested `WorkflowId` exactly
  once.
- Bootstrap requires no particular workflow name or fixed definition count.

- A definition may compose only compiler-registered operation contracts and may use only
  their closed parameter and outcome schemas under an allowed workflow policy profile.
- It cannot load code, name an infrastructure adapter, provide a raw path or command,
  grant a capability, bypass runner delta validation, or weaken an operation's gate.
- Adding new executable operation behavior or a new capability still requires an engine
  change and the normal architecture and security tests.

- The selected definition's invocation contract is itself a registered capability-free
  pipeline node.
- It owns conversion of remaining arguments into validated typed run context; when
  parsing and validation are separate actions, the node is an orchestrator that
  coordinates their runner-owned bindings.
- The workflow engine coordinates that node before graph entry, then supplies only the
  validated run context to the graph.
- Project/feature/toolchain setup beyond engine startup is included only when the
  selected workflow graph references the corresponding registered setup operations. The
  one exception is model-provider run preparation
  ([ADR 0004](0004-model-provider-bootstrap.md)).

### Initial SDD suite

- `specify`, `plan`, `tasks`, and `implement` are the initial workflow suite, not
  special cases in the generic engine.
- Their YAML definitions explicitly select the registered operation contracts whose
  domain gates enforce `specify -> plan -> tasks -> implement` for a feature.
- A different workflow is not placed into that sequence unless its own definition
  selects the relevant predecessor-gate operation.

## Consequences

- Adding a definition that uses existing registered operations, invocation contracts,
  policy profiles, and state contracts does not require rebuilding the engine.
- Every non-kernel workflow operation is addressable from YAML through the one generic
  operation registry; only the engine-kernel responsibilities named by ADR 0005 remain
  non-callable.
- Durable feature state records the workflow IDs whose compiled graphs have participated
  in that feature.
- Change classification compares only each bound graph's stable semantic authority;
  source inventory ordinals, registry identity, and validation evidence are provenance
  and do not participate.
- Changing a bound semantic graph requires the existing administrative migration route;
  changing only an unrelated definition does not invalidate the feature.
- Bootstrap validates a variable-size workflow registry rather than requiring exact
  four-role coverage.
- The composition root registers concrete generic operation implementations and
  adapters; it does not resolve complete workflows by hard-coded workflow name.
- The workflow engine remains a capability-free orchestrator.
- Only runner-invoked actions receive their narrow declared ports, and every
  orchestrator, including the workflow engine, receives only runner-owned child bindings,
  one of which reaches the provider-bootstrap routine.
- SDD predecessor validation, approvals, clarification ownership, artifact paths, and
  invalidation remain domain contracts of the four initial workflows.
- This decision defines no plugin or dynamic-library system and permits no
  project-authored executable code.
