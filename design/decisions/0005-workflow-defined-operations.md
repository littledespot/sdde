# ADR 0005: Configure workflow behavior in workflow definitions

- **Status:** Accepted
- **Date:** 2026-09-03
- **Decision authority:** Explicit user direction
- **Supersedes:** The compiler-owned built-in model-route registry in proposed
  design Section 12.7, its route-resolution actions, and every requirement for
  a fixed route-to-`models.slots` assignment
- **Amends:** ADR 0003 and the proposed F0005/F0006 workflow and model-operation
  contracts

**Size-policy amendment:** [ADR 0011](0011-provider-owned-request-limits.md)
removes model-call size ceilings and estimates; provider APIs report their own
limits and the workflow accounts actual token usage.

## Context

A fixed engine-owned list such as `spec.section.generate` or
`implementation.operation.generate` makes workflow behavior depend on source
code that an end user cannot configure. It also duplicates the authority of the
workflow definition: the YAML appears to describe the graph while hidden route
descriptors decide prompts, schemas, limits, and model-slot selection elsewhere.

SDDE must load and execute workflows without adding their identities or
operation routes to engine source. Workflow YAML must contain enough explicit
information to compile and execute the workflow, but must remain concise and
must not duplicate large prompts or schemas at every node.

## Decision

There is no built-in workflow or model-route catalogue. The workflow definition
is the sole authority for workflow topology and for selecting the operations
that make up that workflow.

The engine exposes one versioned registry of generic operation contracts. Every
non-kernel workflow operation is addressable from workflow YAML by its
registered ID; a non-kernel operation without such an ID is prohibited. A
definition can call only a registered operation and can
set only parameters declared safe by that operation's closed contract. Adding a
workflow from existing operations requires no engine rebuild. Adding executable
behavior or a capability still requires a new reviewed engine operation; YAML
cannot supply code, an adapter, a capability, or an unrestricted command.

No workflow-specific sequence, model route, prompt selection, schema selection,
model-slot selection, retry branch, repair branch, or success rule may be
hidden behind a workflow name or an inaccessible engine registry. Sequencing
and branching are visible in the YAML graph. An operation retains one cohesive
responsibility and must not conceal a second workflow graph.

Engine-kernel enforcement is not workflow functionality and is not callable or
bypassable from YAML. Loading, parsing, compilation, contract validation,
capability derivation, runner-owned invocation and delta application, provider
preparation, cancellation, cleanup, and security enforcement remain fixed
engine responsibilities. They may inspect only the compiled definition and
registered contracts; they cannot add domain workflow behavior.

### Concise workflow form

The workflow-definition contract will use YAML mappings and native scalar
values instead of repeated tagged `{ kind, value }` parameter objects. Field
names may be concise aliases, and node IDs provide the local identity used by
transitions. The compiler obtains each parameter's type, bounds, and allowed
values from the selected operation contract.

A representative shape is:

```yaml
schema: workflow/v1
id: specify
version: 1
shortcode: SPEC
invoke: sdd.feature-invocation@1
policy: sdd.hardened@1
start: generate

resources:
  spec-prompt: prompts/spec.md
  spec-result: schemas/spec-result.json

steps:
  generate:
    use: model.generate@1
    with:
      slot: spec-generation
      prompt: spec-prompt
      result-schema: spec-result
      retry-limit: 2
    on: { ok: validate, invalid: repair, failed: end.failed, cancelled: end.cancelled }
```

The exact compact schema is owned by F0005 and its formal schema. The example
establishes the required shape, not optional spellings: one operation reference,
one compact parameter map, and one outcome map per step. The implementation
must replace the current verbose v1 transport rather than retain a second
reader or compatibility form.

Large prompts, examples, and schemas may be declared once as workflow-owned
resources and referenced by short local IDs. Every resource is explicitly
named by the YAML, captured from an authorized project-owned root, bounded,
typed, and compiled into immutable workflow authority before execution. The
engine does not substitute a packaged prompt, schema, route descriptor, or
other hidden default. Inline bounded values may be supported where concise.

### Model operations

A generic model operation declares in YAML:

- the repository model slot from `.sddtoolkit.json`;
- the prompt/guidance and request/result schema resource references;
- the typed inputs, outputs, controls, and allowed context behavior required
  by that operation; and
- every outcome transition, including repair, failure, and cancellation.

The selected workflow policy supplies the one workflow-global consumption
limit: a positive total model-token budget initialized separately for each
workflow execution. The accepted actual-usage amendment records API-reported
input plus output tokens after each inference call. A call may overshoot;
record its full usage and return a budget error, and prohibit further model
calls at or above budget. There is no pre-call token reservation or
budget-derived output allowance. Engine/operation/model token ceilings and
mandatory pre-call counting are removed; the retired `input-tokens` and
`output-tokens`, `input-bytes` and `output-bytes` parameters reject. Providers
report their request/output/context errors or stops. No byte ceiling or size
estimate is substituted as a pre-call gate. Optional count
observations neither authorize inference nor replace actual usage. This is
runner-owned accounting/guarding, not a YAML-selectable bypass or hidden model route.
It supplies no retry count. Any operation instance that
can take a retry transition must declare its own `retry-limit` in `with`; the
registered operation contract bounds that value and the compiler rejects a
missing limit or an unbounded retry cycle. An operation with no retry path does
not acquire a hidden retry.

The workflow never names a provider or model directly. The selected slot must
resolve through `ValidatedRepositoryModelAllowlist` to the immutable provider
registry entry prepared for that invocation. Authorization cannot silently
replace the YAML's slot, resources, control flow, or requested operation
semantics.

The stable model-operation identity is derived from the compiled workflow ID,
workflow version, and step ID. Logging, request identity, persistence, and
recovery use that identity instead of a built-in route ID. A workflow-resource
change is a workflow-authority change and is handled by the same compilation,
state-binding, and recovery rules as a graph change.

## Consequences

- End users configure workflows by composing the generic operations exposed by
  the engine and supplying explicit workflow-owned resources.
- The engine has one operation registry, not separate pipeline-node and model-
  route registries with overlapping authority.
- `.sddtoolkit.json` remains the repository model allowlist and
  `.sddproviders.json` remains the provider catalogue. Workflow YAML selects an
  allowed slot; neither configuration file defines workflow control flow.
- The selected workflow policy owns only the per-execution total model-token
  budget. Retry limits are explicit per retry-capable operation instance and
  are never inherited from configuration, provider policy, or a global retry
  default.
- Workflow definitions stay compact through mappings, native scalars, local
  resource aliases, and reuse. Large prompts and schemas are not copied into
  each step.
- The concise workflow-definition schema/parser/compiler, declared-resource
  boundary, single operation registry, and generic transition runner implement
  this decision. Concrete domain and model operations remain separate reviewed
  increments; no legacy syntax, built-in route fallback, or dual authority is
  retained.
- This decision does not make project YAML executable code, allow dynamic
  plugins, or weaken validation, path, provider, command, transaction, or
  capability boundaries.
