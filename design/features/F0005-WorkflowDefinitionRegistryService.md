# F0005 — WorkflowDefinitionRegistryService

**Status:** Proposed feature design

**Implementation:** Complete for the generic workflow-definition increment.
F0005 accepts only the concise closed schema, captures declared workflow
resources, compiles through the single generic operation registry, and
publishes an immutable graph registry. ADR 0003's generic runner now executes
only those compiled transitions. The selected policy's positive total-token
budget and each retry-capable operation instance's explicit `retry-limit` are
compiled into that immutable authority; initial execution is separate from the
declared retry count. No legacy reader, generic loop budget, or split
invocation/step registry remains. Concrete domain operations and initial
workflow definitions remain separately governed increments.

The operation registry also owns versioned native data schemas. Compilation
captures only schemas used by the selected graph; the runner retains owned
invocation values, exposes only declared required/optional inputs, and validates
complete deltas before applying writes, replacements, or invalidations. Rejected
and cancelled candidates are released. This adds no YAML fields or executable
project-supplied schemas. Fixed kernel bindings retain their concrete typed
owners; `DataShape` is dependency/effect metadata, not a workflow value store.

**Compatibility:** None. This pre-release increment accepts only the exact
concise v1 YAML contract. It has no verbose tagged-parameter form, JSON or
`.yml` reader, migration, YAML alias, legacy filename, dual reader, implicit
default, source example, or packaged fallback.

**Classification:** Core, read-only workflow bootstrap authority provider

**Scope:** SDDE engine development. This document does not authorize selecting
or executing a project workflow, running SDDE against a target project, or
mutating project or engine state.

**Governing authority:** [Engine design](../design.md), especially Sections 1,
3, 5-7, 9, 13.1, 15, 28, and 30-32; accepted [ADR
0003](../decisions/0003-generic-workflow-engine.md); accepted [ADR 0005 —
workflow-defined operations](../decisions/0005-workflow-defined-operations.md);
[F0002 —
LogService](F0002-LogService.md); [F0004 —
BootstrapRootRegistryService](F0004-BootstrapRootRegistryService.md); the [path
contract](../paths.md); and the formal [workflow-definition v1 structural
schema](../schemas/workflow-definition-v1.schema.json), expressed as JSON
Schema documentation of the decoded YAML shape.

---

## 1. Responsibility

`WorkflowDefinitionRegistryService` has one responsibility: expose the current
invocation's complete immutable validated identity-free workflow registry,
keyed by unique `WorkflowId` and derived from every in-scope definition beneath
the configured workflow-authority root.

The loader/compiler/registry actions produce and validate that identity-free
candidate before workflow selection. F0005 names the resulting nominal value
`ValidatedWorkflowDefinitionRegistry`; it is the candidate plus its exact
validation evidence, with no `BootstrapComponentId`. Only then does the runner
construct one service with one concrete borrowed `registry()` accessor. The
ordinary later bootstrap materialization owner may consume this same validated
value to assign an ID and construct `WorkflowDefinitionRegistryState`; F0005
does not allocate that identity. The later generic workflow execution slice
owns exact selection through `ResolveSelectedWorkflowAction`; the service
performs no selection itself.

The one feature outcome is built by separate owners:

| Owner | Sole responsibility |
| --- | --- |
| F0004 | Supply the validated `workflow_authority` root capability; no workflow loader reinterprets the raw config string. |
| Workflow loader actions | Derive the reserved layout, inventory every in-scope entry, capture definition bytes, decode YAML 1.2, validate the closed schema, and totally account for the inventory. |
| Workflow compiler actions | Resolve registered contracts and compile one validated immutable graph per schema-valid definition. |
| Registry actions | Index all compiled graphs and prove global uniqueness and total coverage. |
| Fixed startup orchestrator | Coordinate those runner-owned child bindings in order and branch only on typed outcomes. |
| Pipeline runner | Invoke nodes, validate/apply deltas, own intermediates, and destroy rejected candidates. |
| Composition root | Register concrete generic operation implementations in the single operation registry and assemble the fixed nonselectable startup graph. |
| Registry service | Own and expose only the final immutable validated identity-free registry. |

No action calls another action or chooses its successor. The compiler performs
no filesystem I/O or node invocation. The registry builder performs no parsing
or compilation. The orchestrator receives no filesystem, parser, compiler,
registry-mutator, logger, state, or transaction capability.

The service accessor is:

```zig
pub fn registry(
    self: *const WorkflowDefinitionRegistryService,
) *const ValidatedWorkflowDefinitionRegistry
```

Repeated calls return the same borrowed value without lookup by raw string,
allocation, I/O, compilation, selection, or mutation. There is no generic
query, mutable map, copied projection, reload, or fallback API.

## 2. Increment boundary

The workflow-authority media boundary:

- classifies and captures exact `*.workflow.yaml` definitions and only the
  bounded workflow resources explicitly declared by those definitions;
- uses the private bounded YAML 1.2 syntax adapter for infrastructure-only
  reuse without merging toolchain and workflow domain contracts;
- exposes a narrow workflow-definition parser port and composition-root adapter;
- converts parser-library values once into a workflow-owned raw value passed to
  the closed schema-validation boundary, then resolves each concise resource
  alias to one captured workflow-root-relative resource; and
- uses the YAML contract for workflow fixtures, parser tests, runtime tests,
  and clean-package smoke inputs.

The loader/compiler/registry responsibility split and fixed startup
coordination remain unchanged. Their transport, registered input, and runner
bindings use the concise definition and single operation registry exclusively.

It begins with:

- F0004's validated immutable `BootstrapRootRegistry` and exact
  `workflow_authority` capability;
- the single compiler-registered generic operation registry, including
  invocation operations and their typed data-key, outcome, gate, capability,
  and definition-safe parameter descriptors, plus workflow-policy profiles;
  and
- the compiler-owned limits in Section 4.

It ends with either:

- one service owning the completely validated identity-free registry plus its
  inventory, graph, and registry validation evidence; or
- the common terminal `failed` outcome and no service or partial authority for
  deterministic rejection, adapter failure, or deadline exhaustion; or
- terminal `cancelled` and no service or partial authority for an explicit
  runner/user cancellation.

The fixed startup graph is compiler-locked, composition-root-owned,
nonselectable, and not project-extensible. It is not a member of the resulting
registry and acquires no feature transaction lock.

## 3. Closed workflow-definition encoding and schema

### 3.1 File and YAML contract

V1 supports exactly one encoding: UTF-8 YAML 1.2 in a regular file whose
basename has at least one character before the exact case-sensitive suffix
`.workflow.yaml`. One file contains exactly one definition mapping. Discovery is
recursive beneath the validated workflow-authority root, subject to the
reserved-child exclusion in Section 5. A filename never supplies or constrains
`WorkflowId`; identity comes only from validated content.

The syntax reader uses the YAML 1.2 core schema and accepts exactly one
document. It rejects a UTF-8 BOM, invalid UTF-8, duplicate mapping keys at any
depth, aliases, custom tags, a non-mapping root, a second document, and
malformed YAML. It returns a bounded ordinal-bound workflow-owned raw value and
applies no workflow policy. The schema validator alone converts that raw value
into an owned `DeclarativeWorkflowDefinition`.

`ParseWorkflowDefinitionAction` depends only on a narrow
`WorkflowDefinitionParser` port. The composition root binds a workflow adapter
backed by the shared private bounded YAML 1.2 syntax adapter. That low-level
adapter may also serve F0003, but workflow and toolchain parser ports, raw
values, conversions, and schema validators remain separate. The workflow
adapter converts parser-library nodes directly into the workflow-owned raw
value; no parser-library type crosses the port or enters domain/service state,
and there is no YAML-to-JSON text conversion or second parse.

V1 acceptance is the conjunction of three non-overlapping contracts:

1. this section's lexical media policy owns UTF-8, BOM, YAML 1.2 syntax,
   duplicate mapping keys, aliases, custom tags, the one-document mapping root,
   and multiple-document rejection;
2. `design/schemas/workflow-definition-v1.schema.json`, using JSON Schema
   draft 2020-12, is the normative closed structural projection of the decoded
   YAML data for concise mapping fields, scalar types/patterns, resources,
   steps, and static collection bounds; and
3. typed validators own relational rules that JSON Schema cannot express here:
   `ValidateWorkflowDefinitionSchemaAction` owns typed local identifiers while
   the compiler owns step/outcome/resource cross-reference joins, registered
   parameter constraints, resource-kind compatibility, and graph closure.

The executable does not read the repository schema file at runtime. Its Zig
types and validators implement all three layers; conformance fixtures prove
that decoded YAML matches the JSON Schema projection and separately prove
lexical and relational cases. The schema, design examples, and source tree are
never runtime fallbacks or packaged authority.

### 3.2 Root shape

Every definition contains these exact concise fields:

| Field | Exact v1 meaning |
| --- | --- |
| `schema` | The constant string `workflow/v1`. |
| `id` | Project-authored `WorkflowId`: 1-64 ASCII bytes in lower-kebab form. |
| `version` | Positive unsigned 32-bit integer. It is part of semantic authority; v1 performs no migration or range selection. |
| `shortcode` | Exactly four case-sensitive ASCII alphanumeric bytes. F0002's canonical parser owns the same syntax. |
| `invoke` | Exact versioned reference to one registered capability-free invocation operation. |
| `policy` | Exact versioned reference to one registered workflow policy profile containing the positive total model-token budget applied to each execution; it supplies no retry count. |
| `start` | Definition-local ID of the graph entry step. |
| `resources` | Optional map of concise local aliases to bounded workflow-root-relative resource names. |
| `steps` | One to 256 local step IDs mapped to closed operation declarations and outcome maps. |

`sourceInventoryOrdinal` is engine-derived provenance and is not accepted in a
file. A resource name is declarative input resolved only beneath the authorized
workflow-resource root; it is normalized and captured by the compiler and is
never passed as an operational path. Definitions have no field for a raw
project path, command, script, adapter, provider implementation, capability,
gate override, runner control, state identity, bootstrap identity, or
executable payload. Because the root is closed, adding any such field is a
schema error.

The identifier contracts are:

```text
WorkflowId | WorkflowStepId | WorkflowParameterId | WorkflowResourceId
  = [a-z][a-z0-9]*(?:-[a-z0-9]+)*
  = 1..64 ASCII bytes

RegisteredRef
  = [a-z][a-z0-9]*(?:[.-][a-z0-9]+)*@[1-9][0-9]*
  = 3..128 ASCII bytes
```

`RegisteredRef` is one exact contract/profile name plus positive version. The
compiler resolves it by direct typed registry lookup; it never selects a
version range, `latest`, filename, implementation symbol, or near match.

### 3.3 Steps, parameters, resources, and transitions

A step contains one registered generic operation, an optional compact parameter
map, and one outcome map:

```yaml
preflight:
  use: repository.preflight@1
  with: { scope: feature }
  on: { ok: generate, failed: end.failed, cancelled: end.cancelled }
```

The step's mapping key is its unique `WorkflowStepId`. `use` identifies a
registered operation contract, not a concrete implementation or adapter.
`with` is absent when the operation has no parameters; otherwise it contains at
most 32 unique parameter IDs with native YAML boolean, signed integer, or
bounded string scalar values. The selected operation contract supplies their
types, bounds, enum members, registry/resource kind, requiredness, and whether
each parameter is definition-safe. The compiler rejects null, float, sequence,
nested parameter mapping, free unbounded text, raw operational path/command,
unknown, missing, wrong-kind, out-of-range, disallowed, or unresolved values.
There is no repeated `{ parameterId, value: { kind, value } }` wrapper.

`retry-limit` has no global or implicit meaning. A registered retry-capable
operation contract must declare it as a required nonnegative integer parameter
with a finite operation-local maximum. The compiler binds it to that exact step
instance and its monotonic retry transition. A retry edge without the required
parameter, or a `retry-limit` supplied to a contract that does not declare it,
is invalid.

`resources` prevents large prompt, example, or schema content from being
repeated in steps. Each alias resolves to exactly one bounded captured resource
under the authorized workflow root. An operation parameter that expects a
prompt, schema, or example accepts only a declared alias of that expected kind.
Two workflows may bind the same captured resource, but one workflow cannot
declare two aliases for the same source. There is no engine-packaged resource
fallback or undeclared file lookup. At execution, the runner exposes only the
immutable resources referenced by the active step's compiled resource
parameters, never unrelated workflow resources or source paths.

`on` maps every outcome declared by the selected operation contract exactly
once to either another local step ID or one of `end.ok`, `end.needs-user`,
`end.invalid`, `end.blocked`, `end.failed`, and `end.cancelled`. The exact YAML
keys are `ok`, `needs-user`, `invalid`, `blocked`, `failed`, and `cancelled`;
the compiler converts them to the corresponding internal tagged-union variants.
A terminal target must preserve the source outcome and cannot relabel a
non-`ok` result as `ok`.

Source mapping order has no semantic authority. The compiler canonicalizes
steps, parameters, resources, and outcomes by their typed IDs before constructing
`CompiledWorkflowSemanticAuthority`. Reordering a file without changing its
typed content cannot change the compiled semantic graph.

### 3.4 Minimal accepted shape

```yaml
schema: workflow/v1
id: specify
version: 1
shortcode: SPEC
invoke: sdd.specify-invocation@1
policy: sdd.hardened@1
start: preflight
steps:
  preflight:
    use: repository.preflight@1
    on: { ok: end.ok, failed: end.failed, cancelled: end.cancelled }
```

The values are illustrative. `specify` is not a required registry member and
the filename need not match it.

## 4. Compiler-owned bounds

These proof-of-concept limits are fixed, non-configurable, and enforced before
allocation or continued traversal can exceed them:

| Constant | Value |
| --- | ---: |
| `maxWorkflowInventoryEntries` | 4,096 encountered in-scope entries |
| `maxWorkflowInventoryDepth` | 16 descendants below the workflow root |
| `maxWorkflowInventoryDurationMs` | 5,000 monotonic milliseconds |
| `maxWorkflowDefinitions` | 256 files |
| `maxWorkflowDefinitionBytes` | 1,048,576 bytes per file |
| `maxWorkflowDefinitionTotalBytes` | 16,777,216 bytes per inventory |
| `maxWorkflowResourceBytes` | 1,048,576 bytes per resource |
| `maxWorkflowResourceTotalBytes` | 16,777,216 bytes per inventory |
| `maxWorkflowStepsPerDefinition` | 256 steps |
| `maxWorkflowParametersPerStep` | 32 values |
| `maxWorkflowResourcesPerDefinition` | 64 declared aliases |
| `maxWorkflowYamlEvents` | 262,144 events per definition |
| `maxWorkflowYamlTokens` | 262,144 tokens per definition |
| `maxWorkflowYamlNestingDepth` | 16 levels per definition |
| `maxWorkflowYamlScalarBytes` | 128 bytes per scalar |

These YAML limits are workflow-owned and are passed to the shared bounded
syntax adapter. The event and token ceilings admit the maximum v1 graph shape
within the one-mebibyte file ceiling; nesting and individual scalars remain
tightly bounded by the closed schema. F0003 owns its different YAML limits.

Transitions have no independent policy knob. The six closed outcome tags and
unique `(workflowStepId, outcomeTag)` mapping key bound a 256-step graph to
1,536 transitions. Zero definitions is a valid variable-size registry; a later
selection against it returns the ordinary typed unknown-workflow diagnostic.

The enumeration adapter receives the fixed deadline and cancellation token;
timeout or cancellation never turns an incomplete inventory into success.

## 5. Workflow root and reserved children

`BuildWorkflowAuthorityLayoutAction` derives its root only from F0004's exact
`workflow_authority` capability. The root inventory includes an encountered
direct child named exactly `features` to validate its reserved state-root role, but
enumeration never enters its descendant subtree. That child must be a
no-follow directory and receives one `reserved_child_accounted` disposition.
Absence is legal; authorized canonical state publication may create it under
Design Section 25.1. This is not a feature-identity or ownership registry.

Only that exact root child is reserved. An identically named nested
directory elsewhere has no reserved status. Normalization, case-fold,
portable-name, or physical aliases of a reserved child are rejected rather
than treated as another spelling.

Implemented: the filesystem loader reuses the inventory's single reserved-child
rule. Regression tests cover ordinary directory traversal, nested names,
reserved-root rejection, and unregistered-file rejection in the packaged engine.

The engine recursively encounters every other directory, regular file,
symlink, and special node without following links. Exact `*.workflow.yaml`
regular files are definition candidates. After those definitions pass lexical
and structural validation, every other regular file must be referenced by at
least one declared `resources` value and every declared resource must resolve
to exactly one such file. Directories are accounted but not read. An
undeclared regular file, a definition used as a resource, symlink, special
node, wrong-kind reserved child, escaping resource name, or collision is
blocking; the loader never silently ignores an unsupported entry.

## 6. Deterministic loading and total accounting

The loader follows the governing action sequence without combining owners:

1. build and validate the workflow-authority layout;
2. enumerate a bounded unordered no-follow inventory, excluding only reserved
   descendants;
3. normalize every encountered root-relative path;
4. reject the complete duplicate, normalization, case-fold, portable-name,
   physical-alias, and reserved-name collision set;
5. sort once by normalized Unicode-scalar path;
6. assign contiguous one-based inventory-local ordinals;
7. classify every entry by node kind, reserved ownership, and exact media
   policy;
8. capture every definition through its exact no-follow descriptor while
   proving stable identity, regular-file type, and length under both byte
   ceilings;
9. decode each definition capture through the one YAML 1.2 document contract and
   schema-validate it,
   including local step-ID and per-step parameter-ID uniqueness, without
   inferring identity from its filename;
10. resolve the complete declared-resource union against the same normalized
    inventory, reject undeclared or multiply classified regular files, and
    capture each resource once through its exact no-follow descriptor under
    the per-resource and aggregate byte ceilings;
11. build exactly one terminal account for every ordinal; and
12. validate the complete `WorkflowAuthorityInventory` before compilation.

A capture that grows, shrinks, changes identity/type, exceeds a limit, ends
short, or cannot be read completely is blocking. Parse or schema failure is
also blocking. A directory, reserved child, captured definition, and captured
declared resource each have their distinct disposition; no ordinal can have
zero or multiple dispositions. Every capture joins exactly one ordinal and
every captured-definition account joins exactly one definition.

No compilation starts from an unvalidated inventory. One bad sibling blocks
the complete candidate, and no partial definition set, last-known registry, or
service is published.

## 7. Registered-operation graph compilation

Contracts requiring model binding declare their typed slot and explicit
`response-mode`, with optional supported controls. Under
[ADR 0011](../decisions/0011-provider-owned-request-limits.md), retired
`input-bytes`, `output-bytes`, `input-tokens` and `output-tokens` parameters
reject. Registration and compilation require no capacity fields, local size
ceilings or fit estimates. The compiler retains the typed binding requirements;
the runner rejects divergence from the registered contract. F0006 owns exact
slot/model/control/schema compatibility, not provider-size policy. This
capacity-free projection is implemented through the registry, compiler and
runner; the typed slot is its only binding declaration.

The existing compiled model projection represents an immutable binding
requirement independently of operational capabilities (ADR 0004, amended
2026-09-05). Such a contract has exactly one required typed model slot.
Pure operations may consume the runner-supplied binding
without holding a provider port. Provider-call operations still require that
binding and their independently port-derived, policy-permitted capability.

The selected result-schema resource describes the entire compact model result
under [ADR 0006](../decisions/0006-minimal-model-response.md), not an inner
payload or repeated execution metadata. The protocol version and exact resource
identity stay in compiled authority; no new envelope field is needed in YAML.
Compilation implements ADR 0006's [closed result-schema
profile](../decisions/0006-minimal-model-response.md#closed-result-schema-profile)
through one narrow compiler port bound at composition. Only result-schema
resources are decoded; their tagged compiled values carry an opaque immutable
schema and exact captured bytes. The registry owns deep copies of this same
authority. Missing, malformed, unsupported or unbounded schema declarations
reject the graph with `WORKFLOW_GRAPH_COMPILE_INVALID`, without publishing a
partial registry or reading any provider file. Other resource kinds stay bytes.

### Execution guards

A gate is a versioned native contract in the existing operation registry: its
ID, issuing operation ID, evidence key, and nonempty authority-key set. The
issuer is an ordinary YAML-visible validation operation. It must require those
authority keys and produce or replace the gate's closed accepted/rejected
evidence value. It is side-effect-free and holds no operational ports. No other
operation may write that evidence key.

The runner records each applied value's local generation, producer, outcome,
and input generations in its envelope. Before a protected operation, a gate
requires accepted evidence from a successful execution of its exact issuer,
bound to the still-present, unchanged authority generations. Missing, rejected,
foreign, or stale evidence blocks execution. Refresh and domain validation
remain explicit YAML operations; guards perform no I/O or hidden validation
workflow. Evidence cannot be imported from a prior envelope as authority.

Capabilities are derived from the concrete narrow-port types held by each
registered operation binding, not a second asserted list. The compiler captures
that set and the selected policy ceiling; the runner checks the current binding
against both before invoking it. A binding cannot expose an undeclared erased
capability or service locator. Kernel rejection is terminal, not a YAML outcome
that can route around the guard. Cancellation is checked before and after guard
evaluation. These contracts add no workflow-YAML fields.

Registered operational ports include `LLMProviderInterface` (`model-provider`),
the three root-bound toolchain source ports (`toolchain-read`), the toolchain
document parser (`toolchain-parser`), and reference directory inspection
(`reference-read`). The pure bounded Unicode normalizer grants no operational
capability. Further port types require explicit native registration;
unknown erased contexts or callback fields are rejected, not inferred as pure.

The shared value owner copies ordinary immutable data. A sealed native result
may instead transfer its original owner through a typed native accessor and
destructor with a bounded retained-byte count. These hooks stay inside the
runner's value owner, never YAML or model data. Rejected transfers remain with
their producer; accepted transfers are destroyed exactly once on replacement,
invalidation, or cleanup. No second service registry or copied authority exists.

### Compilation checks

`CompileWorkflowGraphAction` is a pure deterministic compiler over one
schema-valid definition and immutable registered contracts. It resolves every
reference exactly and version-exactly once, binds the invocation contract,
validates definition-safe parameters, canonicalizes graph data, and derives
effective data-key, outcome, side-effect, ordering, gate, and capability facts.
It constructs no adapter, child binding, state identity, or executable code and
invokes no node.

`ValidateCompiledWorkflowGraphAction` proves at least:

- the invocation reference resolves to a registered capability-free invocation
  contract and its output typed run context/data keys satisfy graph entry;
- schema evidence proves unique local step and parameter IDs; the entry resolves
  exactly once, and every step is reachable from entry and can reach a terminal;
- every retry cycle crosses a registered monotonic attempt/iteration-budget
  operation whose finite `retry-limit` is an explicitly supplied and validated
  scalar parameter on that retry-capable operation instance; the selected
  workflow policy cannot supply or default it;
- every step's `use` reference resolves to one registered operation contract/version and every
  parameter satisfies that contract's closed definition-safe descriptor;
- every declared resource is captured exactly once, has one compatible typed
  use, and is included in immutable compiled workflow authority;
- each outcome declared by an operation contract has exactly one transition, no
  undeclared outcome has a transition, and every node/terminal target is valid;
- data-key versions, required/optional inputs, producers, replacements,
  invalidations, side-effect barriers, and ordering constraints compose;
- every terminal target preserves its source tag exactly, and graph policy
  cannot discard a failure, invalid result, user-input need, block, or
  cancellation along a later branch;
- referenced gates remain intact, including the predecessor and approval gates
  owned by the initial SDD operations selected in their YAML definitions; and
- effective capabilities are derived only from registered contracts and are a
  subset of the selected workflow policy profile; and
- the selected policy contributes exactly one positive total model-token
  budget to immutable compiled workflow authority, initialized as a fresh
  accounting ledger for each execution rather than shared across executions.

Unknown or mismatched contracts, outcomes, gates, policies, or versions;
dangling, unreachable, unbounded-cycle, duplicate transition-key, or unhandled graph
members; invalid data flow; executable/infrastructure representation; gate weakening;
capability escalation; and runner bypass all fail compilation.

The resulting `CompiledWorkflowSemanticAuthority` contains only stable typed
semantic content, including every resolved operation declaration and exact
captured workflow resource. It excludes operational source paths, inventory
ordinal, registry identity, raw/parsed values, and compilation/validation
evidence.

## 8. Variable-size registry and handoff

`BuildWorkflowDefinitionRegistryAction` indexes the complete compiled graph set
once by typed `WorkflowId`. The candidate retains each graph's validated
`WorkflowShortcode` and source inventory ordinal as metadata, but assigns no
source identity and no `BootstrapComponentId`.

`ValidateWorkflowDefinitionRegistryAction` proves:

- cardinality is between zero and `maxWorkflowDefinitions`, with no required
  workflow name or fixed count;
- `WorkflowId`, `WorkflowShortcode`, and source inventory ordinal are each
  globally unique;
- every schema-valid captured definition has exactly one compiled graph and
  map entry, and there is no extra graph or entry;
- every map key equals its graph's content-derived `WorkflowId`;
- each entry joins the exact captured-definition account and graph evidence;
  and
- a reserved, directory, blocking, or unaccounted ordinal cannot be indexed.

For preselection, the runner constructs exactly one
`WorkflowDefinitionRegistryService` from the validated identity-free value; no
earlier candidate can construct it. Separately, when the larger bootstrap
authority-state flow is required, its materialization owner may consume that
validated value, assign the one owner-local component ID, and construct
immutable `WorkflowDefinitionRegistryState`. That later identity does not
alter graph semantics and is not a precondition for selection.
`ResolveSelectedWorkflowAction` and workflow execution are not part of F0005.

## 9. Failure and cleanup contract

Deterministic rejection, adapter failure, and inventory/capture deadline
exhaustion use the common terminal `failed` outcome with these closed diagnostic
families:

| Code | Owning boundary |
| --- | --- |
| `WORKFLOW_AUTHORITY_INVENTORY_INVALID` | Layout, enumeration, normalization, collision, media classification, limits, or total accounting failed. |
| `WORKFLOW_DEFINITION_READ_ERROR` | A definition or declared resource could not be captured completely and stably through its descriptor. |
| `WORKFLOW_DEFINITION_PARSE_ERROR` | Bytes violate the exact supported UTF-8 YAML 1.2 document contract. |
| `WORKFLOW_DEFINITION_SCHEMA_INVALID` | The raw value violates the closed v1 structural, typed-value, or definition-local identity rules. |
| `WORKFLOW_GRAPH_COMPILE_INVALID` | Registered-reference, parameter, topology, data-flow, transition, gate, or capability validation failed. |
| `WORKFLOW_REGISTRY_INVALID` | Global identity uniqueness or total definition/graph/account coverage failed. |

Diagnostics retain source ordinal and bounded rule evidence; they do not make a
source path operational authority. No failure falls back to another file,
encoding, definition set, cached registry, hard-coded workflow, or source
asset.

Raw bytes, decoded raw values, schema-valid definitions, compiled candidates,
registry candidates, handles, and evidence remain distinct owned values. Each is
destroyed exactly once on success, deterministic rejection, cancellation,
timeout, and unexpected operational error. Before workflow selection there is
no model call, workflow log binding, state write, cache write, transaction,
feature lock, or filesystem mutation.
An explicit runner/user cancellation propagates terminal `cancelled` unchanged,
performs the same complete cleanup, and publishes no service. Cancellation is
never collapsed into `failed`.

## 10. Explicit non-responsibilities

F0005 does not implement:

- workflow selection, invocation-argument parsing, graph execution, or
  workflow-name branching;
- concrete initial `specify`, `plan`, `tasks`, or `implement` operation behavior;
- project-authored executable code, plugins, dynamic libraries, scripts,
  adapters, commands, capabilities, retries, or concurrency;
- JSON or another workflow encoding, YAML aliases or custom tags,
  executable includes/imports, reusable subgraphs, display descriptions,
  alternate authoring aliases, or compatibility readers;
- bootstrap component ID allocation, persistence, registry refresh/migration,
  active-feature change classification, or recovery;
- feature state, toolchain/preset/principle loading, repository
  discovery, model calls, logging sinks, or transaction locks; or
- creation of the missing `features/` directory.

Those concerns remain with their accepted owners or later increments.

## 11. Acceptance criteria

1. Definitions load only from F0004's validated `workflow_authority`
   capability; raw `config.paths.workflows` is never used by F0005.
2. V1 admits only recursive regular `*.workflow.yaml` definitions encoded as
   one strict UTF-8 YAML 1.2 mapping document without aliases or custom tags,
   plus bounded regular resources explicitly declared by those definitions.
   Definitions conform to the formal closed structural schema.
3. Workflow identity comes only from content; a filename/content mismatch does
   not rename, reject, or select the workflow.
4. The exact root child `features/` is accounted when present and never
   traversed; aliases and wrong kinds block. All other directories follow
   normal traversal and definition/resource accounting, with no second
   reserved storage child.
5. Every other encountered entry receives exactly one terminal account.
   Unreferenced or unsupported files, links, special nodes, collisions,
   incomplete definition/resource capture, and invalid definitions block the
   whole inventory.
6. Inventory order and ordinals are deterministic and independent of adapter
   enumeration order.
7. All limits in Section 4 are compiler-owned, enforced at their owning
   boundary, and cannot be relaxed by configuration or a definition.
8. The external schema has no open mapping or unbounded parameter value. It
   uses native scalar parameters without tagged wrappers, and delegates typed
   identity syntax to the canonical ID and F0002 shortcode parsers.
9. Every operation, parameter, resource, outcome, gate, policy, and capability
   reference resolves exactly and version-exactly through compiler-owned
   contracts and the captured workflow authority.
10. Every accepted graph has one entry, only reachable terminal-reachable
    nodes, no unbounded cycle, complete unique outcome transitions, valid typed
    data flow, preserved gates, and policy-bounded effective capabilities.
11. The compiler cannot construct adapters, invoke operations, select behavior
    from a workflow name, or introduce behavior absent from YAML-referenced
    registered contracts. Every non-kernel workflow operation is registered and
    referenceable through the definition's `invoke` or `steps.*.use` fields;
    source-only non-kernel operations are rejected by architecture tests. There
    is no second route or domain-workflow registry.
12. Registry cardinality is variable from zero through 256 and accepts
    arbitrary schema-valid workflow IDs; no workflow name or four-workflow
    count is required.
13. Workflow IDs, four-character shortcodes, and source ordinals are globally
    unique, and every definition/account/compiled-graph/map join is one-to-one.
14. Source order/path, registry identity, and validation evidence cannot change
    another graph's stable semantic authority.
15. One invalid sibling yields no partial or fallback registry.
16. The runner constructs exactly one service after identity-free registry
    validation; `registry()` returns the same borrowed immutable value without I/O,
    compilation, selection, allocation, or mutation.
17. The startup graph is nonselectable and not project-extensible, uses only
    runner-owned bindings, and acquires no feature transaction lock.
18. F0005 performs no model call, command, write, state transition, logging sink
    operation, workflow selection, or graph execution.
19. The packaged executable requires no design schema/example, source tree,
    development cache, or Zig toolchain at runtime.
20. Explicit cancellation remains `cancelled`; deterministic rejection,
    adapter failure, and deadline exhaustion return `failed`. Neither publishes
    a service or partial registry.
21. The selected policy supplies exactly one positive total model-token budget,
    which is applied to a fresh ledger for each workflow execution and supplies
    no retry count. Every retry-capable operation instance declares its own
    bounded `retry-limit`; missing limits, policy-supplied retry defaults, and
    retry parameters on non-retry contracts fail compilation.

## 12. Verification

Implementation tests must cover the owning boundaries:

- **Path/layout:** relocated workflow roots; no raw-config or fallback path;
  reserved children absent/present as directories; descendant exclusion;
  wrong-kind, symlink, case/normalization/portable alias, and collision
  rejection.
- **Inventory:** zero, one, many, 256, and 257 definitions; 4,096 and 4,097
  entries; depths 16 and 17; deadline/cancellation; randomized adapter order;
  contiguous Unicode-scalar-sorted ordinals; exact `*.workflow.yaml`
  acceptance; `.workflow.json`, `.workflow.yml`, case variants, suffix-only
  basenames, declared/unreferenced/unsupported regular resources, links, and
  special nodes rejection; and
  exact one-account-per-entry coverage.
- **Capture/parse:** exactly 1,048,576 and 1,048,577 bytes; exact and exceeded
  total bytes; short read, growth, shrink, replacement, and type change;
  invalid UTF-8, BOM, duplicate mapping keys, aliases, custom tags, malformed
  YAML, non-mapping root, multiple documents, and every accepted parser-limit
  boundary; comments and equivalent block/flow spellings have no semantic
  authority.
- **Schema:** accepted minimal, parameterized, and resource-using definitions; every
  required/unknown/wrong-kind field; unsupported schema version; malformed IDs,
  references, version, shortcode, scalar parameter types, integer limits,
  nested values, local duplicate IDs, resource aliases, and prohibited raw
  operational path/command/adapter/capability/script or runner-control shapes.
- **Compiler:** unknown/version-mismatched invocation, operation, policy, parameter,
  outcome, gate, and capability references; non-capability-free invocation;
  entry/run-context mismatch; missing entry or target; dangling, unreachable,
  nonterminal, cyclic, missing/duplicate-key/undeclared transition;
  invalid terminal mapping; data-key/version/producer/effect/barrier failure;
  gate weakening; capability escalation; missing, negative, excessive, or
  policy-supplied retry limits; retry limits on non-retry contracts; a missing
  or nonpositive policy token budget; and runner bypass.
- **Registry:** arbitrary non-SDD IDs; zero definitions; duplicate workflow ID,
  shortcode, or ordinal; missing/extra graph; mismatched map key;
  capture/account/evidence mismatch; reserved ordinal indexed; and proof that
  one invalid sibling publishes nothing.
- **Properties:** every accepted definition compiles only registered contracts
  and handles every declared outcome; adding/removing an unrelated definition
  or inserting an earlier-sorting source cannot change another workflow's
  `CompiledWorkflowSemanticAuthority`; initial SDD predecessor/approval gates
  cannot be weakened by any accepted parameter combination; and two executions
  of one compiled workflow initialize independent total-token ledgers without
  changing its immutable semantic authority.
- **Architecture and startup:** actions cannot call nodes; the compiler imports
  no filesystem/provider implementation; the workflow parse action depends
  only on its narrow parser port; the YAML library and syntax-node types remain
  adapter-private; workflow and toolchain ports/raw values/schema validators do
  not merge; the startup orchestrator has only child bindings; the runner is
  the sole node/delta owner; the fixed startup graph is absent from the
  registry; no write, model call, command, or feature lock occurs; and
  all owned intermediates are released on every terminal branch.
- **Packaging:** load a valid relocated variable registry and its declared
  workflow-owned resources with the native
  executable in a clean directory containing only target-owned runtime inputs,
  never `design/`, source files, build cache, or a Zig toolchain.

## 13. Traceability

| Concern | Authority |
| --- | --- |
| Generic loader/compiler/registry split | ADR 0003; Design Sections 5.2 and 15 |
| Shared path capability and reserved ownership | F0004; Design Section 9.1; `design/paths.md` |
| Closed v1 YAML transport and structural projection | F0005 Section 3; `design/schemas/workflow-definition-v1.schema.json`; Design Section 32 |
| Action, runner, orchestrator, and composition-root boundaries | Design Sections 5-6 and 13.1 |
| Registered-operation graph and common outcomes | Design Sections 6-7; `design/code.md` Sections 1-6 and 24 |
| Workflow shortcode | F0002 Sections 3.2 and 6.1 |
| Variable registry and stable semantic authority | ADR 0003; Design Sections 9.1, 15, and 24 |
| Verification and clean native packaging | Design Sections 28 and 30-31 |
