# F0004 — BootstrapRootRegistryService

**Status:** Proposed feature design

**Accepted amendment:** Explicit user direction on 2026-09-02 establishes the
`paths.providers` provider-document path; this does not change the status of
unrelated F0004 design.

**Implementation readiness:** Ready for the bounded configured-root
capability increment. It begins with F0001's immutable configuration and exact
project-root descriptor and ends with one service exposing the validated
immutable `BootstrapRootRegistry`. It does not inventory or read workflow
definitions or the provider document.

**Classification:** Core, read-only bootstrap path authority

**Scope:** SDDE engine development. This document does not authorize running
SDDE against a target project and authorizes no project-content mutation.

**Governing authority:** [Engine design](../design.md), especially Sections 1,
3, 5-6, 9, 11, 15, 25-26, and 28-31; [F0001 —
SDDToolKitConfigService](F0001-SDDToolKitConfigService.md); and the
[path contract](../paths.md).

---

## 1. Responsibility

`BootstrapRootRegistryService` has one responsibility: expose the current
invocation's immutable validated `BootstrapRootRegistry`. The value is built
from the seven decoded directory-root paths and the provider-document path and
is bound to the canonical invocation project root.

This shared boundary owns normalization, containment, active-filesystem
representability, role assignment, and configured-location separation. A
workflow loader consumes its `workflow_authority` capability; it never resolves
`config.paths.workflows` itself. Preset, principle, reference, artifact, and
template consumers use the same registry rather than introducing
caller-specific path resolution. F0008 likewise consumes only the opaque
provider-document capability.

The service is a read-only owner, not a path resolver or general filesystem
authority. Its construction actions own path validation; after validation its
concrete `registry()` accessor only returns a borrowed immutable registry. It
neither reads root contents nor grants a model, orchestrator, or arbitrary
caller a path or operation capability.

## 2. Minimal design

The fixed composition-root-owned startup graph invokes the existing governing
actions through runner-owned bindings:

| Action | Sole responsibility |
| --- | --- |
| `ValidateEnginePathPolicyAction` | Validate one required path or overlap relation under the compiler-locked project-root and portability rules. |
| `ResolveConfiguredBaseRootAction` | Join one decoded relative configured directory or provider-document path to the canonical project root without following an alias or deriving a child path. |
| `ValidateConfiguredBaseRootAction` | Convert that one candidate into its typed root-role capability after normalization, containment, representability, no-follow, and existence/type checks. |
| `BuildBootstrapRootRegistryIdAction` | Construct only the self-validating `(canonical project root, bootstrap-root contract version)` identity. |
| `BuildBootstrapRootRegistryAction` | Assemble the seven validated directory capabilities and one provider-document capability exactly once under that identity. |
| `ValidateBootstrapRootRegistryAction` | Prove exact key/role coverage and the complete configured-location collision and nesting policy. |

No action calls another action. The startup orchestrator coordinates only the
runner-owned bindings, the runner alone validates and applies node deltas, and
the composition root alone constructs the filesystem/path adapter and fixed
bindings. The orchestrator receives no filesystem, path-normalizer, config,
registry-builder, or logger capability. Only after final registry validation
does the runner construct one `BootstrapRootRegistryService`.

## 3. Input, output, and ownership

F0004 consumes:

- F0001's borrowed immutable `SDDToolKitConfig`;
- the exact `ExactEngineConfigLocation`, including its canonical project root;
- the active workspace filesystem/portability policy resolved through a
  trusted adapter; and
- the compiler-locked mapping from each configuration key to exactly one
  `ConfiguredRootRole`, access class, and existence policy.

The seven directory mappings are closed:

| Configuration key | Root role |
| --- | --- |
| `specs` | `specs_artifacts` |
| `references` | `reference_sources` |
| `specsArchive` | `archived_specs` |
| `workflows` | `workflow_authority` |
| `toolchainPreset` | `toolchain_preset_registry` |
| `principles` | `project_principles` |
| `templates` | `initialization_templates` |

The required `providers` member maps separately to the opaque
`llm_provider_config` read-only file capability. Its normalized basename is
exactly `.sddproviders.json`; it is not a directory-root role and does not
increase the configured-root cardinality.

The result is exactly one `BootstrapRootRegistryService` owning one immutable
`BootstrapRootRegistry` containing its tuple identity, exact config location,
seven typed directory capabilities, and the provider-document capability. Its
concrete accessor is:

```zig
pub fn registry(
    self: *const BootstrapRootRegistryService,
) *const BootstrapRootRegistry
```

Repeated calls return the same borrowed value without allocation, I/O,
validation, or mutation. Each capability retains its source key and role;
callers cannot relabel one root as another. A capability contains an opaque
typed canonical-contained-path value for its declared role; it does not expose
that value as caller-constructible path bytes. Raw configuration strings,
untyped path candidates, unwrapped absolute path buffers, adapter handles, and
validation scratch state remain runner-private and are released on every
terminal branch.

F0004 introduces no service locator, generic string-key getter, mutable path
map, cache, reload/watch API, environment override, copied projection, or
second configuration value.

## 4. Path and existence contract

Each configured value is parsed as one normalized project-relative path. The
seven directory entries require directory form; `providers` requires file form
and the exact `.sddproviders.json` basename. Validation rejects an empty or
absolute path, drive/UNC form, NUL or
control scalar, traversal, ambiguous separator or segment, path-policy length
violation or project-root escape. The normalized candidate must be
representable under the active workspace policy. Existing directory-root
components are inspected without following links. The provider-document
capability reserves only its structural location; F0008 performs the no-follow
ancestor/file and physical-identity checks before publishing bytes. Every typed
capability remains bound to the exact canonical project root and role.

All eight normalized locations participate in one collision set even when a
leaf does not yet exist. They must be distinct and non-nested, with exactly one
exception: `specsArchive` may be a proper descendant of `specs`. The provider
document must also differ from `.sddtoolkit.json`. Equality is never permitted.
Duplicate, normalization-equivalent, case-fold-equivalent,
portable-name-equivalent, aliased, or otherwise overlapping peers fail before
any configured root is inventoried or the provider document is read.

For the preselection startup increment:

- `workflows` must resolve to an existing, readable, no-follow directory;
- each other configured root is reserved at its validated location and may be
  absent until a selected registered workflow declares a consumer that applies
  the root's stricter read or transaction policy; and
- if any optional-at-preselection root exists, it must already be a no-follow
  directory. Absence does not grant creation authority, and every later
  operation revalidates the exact capability and its operation policy before
  use; and
- the provider-document location is reserved without probing the leaf. F0008
  opens and reads it only if F0006's selected-workflow branch requires model
  capability.

This allows a non-SDD workflow to omit unrelated reference, preset, principle,
template, and feature-artifact contents without weakening their eventual
validation. The workflow-authority root is the sole exception because the
engine must load the selectable registry before it can select any workflow.

No ancestor/descendant search is performed. The engine never substitutes a
current-directory child, `.specify/`, `design/`, repository example, source
tree, packaged asset, or default path.

## 5. Workflow-authority handoff

F0004 passes F0005 only a borrowed immutable registry view, from which F0005
receives the exact `workflow_authority` capability plus validated
bootstrap-root-registry evidence. F0005 derives the workflow layout, including
the fixed `features/` and `transactions/` reserved children, from that
capability.

F0004 does not:

- enumerate the workflow root or derive an inventory ordinal;
- classify a workflow definition or reserved child;
- read, parse, schema-validate, or compile a definition;
- build or select a workflow registry entry;
- derive a feature-state or transaction-storage capability; or
- acquire a project/feature transaction lock.

The handoff is one-way:

```text
F0001 immutable PathsConfig + exact project root
  -> F0004 validated BootstrapRootRegistryService
  -> F0005 consumes only workflow_authority capability
  -> F0008 consumes only llm_provider_config capability when F0006 requests it
```

## 6. Failure and cleanup contract

Deterministic rejection, adapter failure, or an operation deadline maps to the
common terminal `failed` outcome with one of these closed diagnostic codes:

| Code | Meaning |
| --- | --- |
| `BOOTSTRAP_ROOT_RESOLUTION_ERROR` | A configured path cannot be safely parsed, joined, represented, or inspected under its declared root policy. |
| `BOOTSTRAP_ROOT_REGISTRY_INVALID` | Exact configured-key coverage, key-to-role binding, uniqueness, or the complete overlap policy does not validate. |

The diagnostic may carry bounded engine-owned evidence naming the configuration
key and failed rule. It never exposes an unrestricted canonical absolute path
or creates an alternative control branch.

Any rejection or operational failure publishes no service or partial registry
and prevents workflow inventory, model calls, project writes, state
transitions, workflow logging, and lock acquisition. Candidate paths and
handles are released exactly once on success, rejection, cancellation, timeout,
and operational error. Before workflow selection there is no `WorkflowLog`
binding; bootstrap therefore uses only its typed non-logging diagnostic path.
An explicit runner/user cancellation instead propagates terminal `cancelled`
unchanged; it is never relabelled `failed`. It performs the same cleanup and
publishes no service.

## 7. Acceptance criteria

1. F0001 remains the only `.sddtoolkit.json` reader and structural decoder.
2. Every configured path is resolved by the shared path-policy boundary, never
   by a workflow-, preset-, principle-, reference-, or artifact-specific
   implementation.
3. Each of the seven required directory keys maps to exactly one fixed root
   role; `providers` maps to exactly one provider-document file role; all
   appear exactly once in the immutable registry.
4. All candidates are normalized, project-contained, and representable before
   becoming typed capabilities. Directory roots are no-follow validated at
   bootstrap; F0008 no-follow validates the reserved provider path before read.
5. The complete eight-location collision set is checked before content
   ingestion; only proper `specs/specsArchive` nesting is legal, and the
   provider path cannot collide with `.sddtoolkit.json`; F0008 also rejects a
   physical file-identity alias at open time.
6. `workflows` is an existing readable no-follow directory at preselection.
   An existing peer is also a directory; an absent peer grants no operation.
7. The runner constructs exactly one service only after complete validation;
   `registry()` returns the same borrowed immutable value without I/O,
   validation, allocation, or mutation.
8. No raw path string, untyped absolute path buffer, adapter handle, mutable
   map, copied projection, or partial registry is published. Consumers receive
   only the borrowed registry and its typed opaque directory/file
   capabilities.
9. The fixed startup graph is nonselectable and not project-extensible, uses
   only runner-owned bindings, and acquires no project/feature transaction
   lock.
10. Every invalid input or operational failure publishes no service or registry
    and stops before workflow loading or any downstream operation.
11. The packaged executable resolves only target-project configuration and
    roots and requires no source tree, design example, or development asset.
12. Explicit cancellation returns `cancelled`, while rejection, adapter failure,
    and deadline exhaustion return `failed`; neither publishes a service.

## 8. Verification

Implementation evidence must cover:

- each accepted relative-root form and representative empty, absolute,
  drive/UNC, traversal, separator, control, encoding, component-length, and
  total-length rejection;
- existing, absent, wrong-kind, linked, replaced, and aliased root components,
  including a `workflows` leaf that is missing or unreadable;
- exact seven-directory-role plus provider-file-role coverage,
  duplicate/missing/extra capabilities, and a
  capability whose source key and role disagree;
- direct equality, proper nesting, reverse nesting, unrelated nesting,
  normalization, case-fold, portable-name, and physical-alias collisions,
  including collisions whose leaves are absent;
- proof that adding a caller or a new workflow cannot relabel a capability or
  bypass the shared owner;
- action tests with narrow fake path/filesystem ports, orchestrator spy-binding
  order/failure propagation, cleanup on every terminal class, and architecture
  tests that keep adapters out of domain/actions that do not need them and all
  operation ports out of the orchestrator; and
- a clean native-executable test using a relocated project root and no source,
  example, schema, or packaged fallback assets.

## 9. Traceability

| Concern | Authority |
| --- | --- |
| Configuration transport boundary | F0001; Design Sections 9 and 13.1 |
| Shared action/runner/composition ownership | Design Sections 5-6 and 15 |
| Configured-root identity, containment, and separation | Design Sections 9 and 11; `design/paths.md` |
| No-follow filesystem safety | Design Sections 25-26 |
| Workflow handoff and reserved descendants | F0005; Design Sections 9.1 and 13.1 |
| Provider-document handoff | F0008; F0006 Sections 3-5 |
| Testing and native packaging | Design Sections 28 and 30-31 |
