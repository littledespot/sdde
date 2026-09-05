# F0003 — ToolChainService

**Status:** Proposed feature design

**Implementation readiness:** Ready. The closed project and preset contracts,
package layout, bounds, inheritance, merge, and safety-valid output are defined
below. The JSON Schema files in `design/schemas/` are normative documentation
of the same runtime-validated YAML shapes; runtime code does not load them.

**Classification:** Core, read-only mechanical toolchain provider

**Execution:** Selected-workflow setup under ADR 0003, not fixed startup.
Configuration/root/workflow loading and provider preparation remain kernel work.

**Scope:** SDDE engine development. This document does not authorize running
SDDE against a target project.

**Governing authority:** [Engine design](../design.md), especially Sections
1, 3-6, 9-11, 15, 28, and 30-31; [F0001 —
SDDToolKitConfigService](F0001-SDDToolKitConfigService.md); [F0002 —
LogService](F0002-LogService.md); [F0004 — BootstrapRootRegistryService](F0004-BootstrapRootRegistryService.md);
the [path contract](../paths.md); and the
[toolchain-preset bootstrap diagram](../diagrams/08-toolchain-preset-bootstrap.md).
The [`_structure.yaml`](../toolchainPresets/_structure.yaml) file is reviewed
as source material in Section 5; it is not promoted to runtime authority.

---

## 1. Responsibility

`ToolChainService` has one responsibility: expose the current invocation's
immutable post-composition safety-valid toolchain object to declared consumers.

That object is derived from the complete registry beneath
`paths.toolchainPreset` and the exact project layer at
`<paths.principles>/toolchain.yaml`, which selects exact packages from that
registry. Nothing consumer-visible is published until the project layer,
complete preset registry, inheritance closure, deterministic composition, and
effective merged policy have all passed their owning validators.

F0003 names the resulting nominal value `ValidToolchain`. It is the canonical
immutable post-inheritance, post-composition, safety-valid result, not a wrapper
around raw YAML or another projection of the same authority. Captured bytes,
decoded values, schema-valid layers, registry candidates, and merged pre-safety
candidates remain runner-owned workflow intermediates exposed only to
operations declaring their typed input keys. None can construct
`ToolChainService`.

After the safety gate succeeds, the runner's envelope owns the original sealed
`ValidToolchain` allocation. `ToolChainService` is its non-owning read-only facade.
Declared consumers may borrow only
`*const ValidToolchain` through one concrete read-only accessor. No service
registry, generic or string-key service query, cache, copied projection, reread,
or second authority is introduced. A borrowed service cannot outlive its
envelope value; replacement, invalidation, rejection, and execution cleanup
release native owners through the shared value lifecycle.

### Workflow bindings

The single operation registry exposes the existing action IDs below. Each has
`ok` and `failed` transitions, no parameters, and one action responsibility.
The YAML graph owns ordering; no combined setup operation hides this sequence.

| Operation | Output key |
| --- | --- |
| `capture-project-toolchain@1` | `project_toolchain_capture` |
| `inventory-toolchain-presets@1` | `toolchain_preset_inventory` |
| `capture-toolchain-presets@1` | `toolchain_preset_captures` |
| `parse-toolchain-documents@1` | `raw_toolchain_documents` |
| `validate-project-toolchain-schema@1` | `schema_valid_project_toolchain` |
| `validate-toolchain-preset-registry@1` | `schema_valid_toolchain_registry` |
| `resolve-toolchain-inheritance@1` | `resolved_toolchain_inheritance` |
| `compose-toolchain@1` | `composed_toolchain` |
| `validate-toolchain-safety@1` | `valid_toolchain` |

Composition binds each source port to its exact F0004 root capability after
startup, before invocation. Roots are not copied into workflow data or supplied
by YAML. The source ports derive `toolchain-read`; the parser port derives
`toolchain-parser`. The registered `core.toolchain@1` profile allows those two
capabilities only. Unreferenced setup operations perform no reads. Cancellation
and cleanup remain runner-owned.

## 2. Path authority and the requested upstream service

F0004's `BootstrapRootRegistryService` is the sole upstream path-authority
provider. F0003 consumes only the registry's typed `projectPrinciples()` and
`toolchainPresetRegistry()` capabilities. It does not receive F0001 config,
derive a capability from a decoded path string, reread configuration, accept a
caller path, or create another path authority. The filesystem adapter resolves
the exact `toolchain.yaml` child only through the typed principles capability;
the preset loader receives only the typed preset-registry capability.

The two legal source locations are:

| Source | Location authority |
| --- | --- |
| Project toolchain layer | The exact no-follow child `toolchain.yaml` resolved through F0004's typed `projectPrinciples()` capability. |
| Preset registry | F0004's exact typed `toolchainPresetRegistry()` capability. |

Decoded path strings are information, not filesystem authority. F0003 never
accepts a caller path, absolute path, alternate filename, environment override,
ancestor/descendant search result, `paths.templates` substitute, source-tree
example, or packaged fallback.

## 3. Closed loading and publication contract

### 3.1 Package layout and limits

The project document is exactly `<paths.principles>/toolchain.yaml`. The preset
registry contains only direct regular-file children ending in
`.toolchain-preset.yaml`; directories, links, special nodes, alternate suffixes,
and more than 256 entries reject the complete registry. Each document is at
most 1 MiB, the captured total is at most 16 MiB, nesting is at most 16, and a
document contains at most 32 package references and 64 policy references.

All files are YAML 1.2, one document, without aliases or custom tags. Duplicate
keys, unknown fields, placeholders, nulls, implicit objects, and wrong node
kinds fail closed. Runtime validation implements the same contracts documented
by `project-toolchain-v1.schema.json` and
`toolchain-preset-v1.schema.json`.

### 3.2 Exact schemas

The project document has exactly three required fields:

```yaml
schema: project-toolchain/v1
presets: [zig@0.16.0]
policies: [project.zig@1]
```

A preset package has exactly five required fields:

```yaml
schema: toolchain-preset/v1
package: zig@0.16.0
layer: language
extends: []
policies: [project.zig@1]
```

`package` and every `presets`/`extends` item is an exact
`<package-id>@<MAJOR.MINOR.PATCH>` reference. Package IDs are lowercase ASCII
segments separated by `.` or `-`; versions are canonical decimal triples with
no range, prefix, prerelease, build suffix, alias, or `latest`. `layer` is one
of `language`, `runtime`, `framework`, `build`, `test`, or `environment`.
Policy references are exact registered `<policy-id>@<positive-integer>` IDs.
Lists contain no duplicates.

### 3.3 Inheritance and merge

The complete preset registry validates before project selection. Package
identity comes only from `package`, never the filename. Each identity occurs
once. Every dependency resolves exactly, dependency cycles fail, and one
closure cannot contain two versions of the same package ID. Dependencies are
ordered before dependants; otherwise packages use fixed layer order followed
by bytewise package-reference order.

There is one merge operator: stable set union of policy references. Preset
policies are unioned in resolved package order, then project `policies` are
unioned. Duplicate values collapse without changing the first occurrence.
There is no recursive map merge, replacement, removal, override, subtraction,
or implicit precedence rule.

### 3.4 Safety and publication

The composition root supplies the immutable policy registry. Every selected
policy must resolve to one registered policy marked project-selectable. The
safety gate also injects every compiler-locked required policy and rejects a
missing/duplicate registry definition. Package documents cannot define a
command, path, capability, executable implementation, or safety exception.

Only the safety gate constructs `ValidToolchain`. It owns the deterministic
ordered exact package references and immutable compiled policy descriptors;
it contains no raw YAML, source path, mutable map, unregistered policy, or
pre-safety candidate. The runner then constructs `ToolChainService`.

The service exposes exactly one accessor:

```zig
pub fn toolchain(self: *const ToolChainService) *const ValidToolchain
```

`toolchain()` performs no filesystem read, parse, merge, validation, or
allocation. Repeated calls return the same borrowed immutable value. The
service releases its owned value once on every terminal branch. There is no
generic `query()`, field lookup, raw-document accessor, or pre-safety service
instance.

Every declared inheritance binding names an exact preset package identity and
version, not a directory, filename guess, version range, implicit `latest`, or
untyped map. Preset packages may have a validated transitive composition graph;
the project `toolchain.yaml` supplies only its exact direct bindings and policy
union entries. Project-layer validation alone makes no safety claim; the
post-composition safety validator rejects any effective merged result that
weakens compiler-locked safety.

The bootstrap diagram also covers inventory ledgers, recovery, persistence,
authority-change routing, environment compilation, and downstream
invalidation. Those remain runner, transaction, bootstrap, and policy-compiler
responsibilities. F0003 neither duplicates nor hides them behind a service
method.

`ToolChainService` publishes no raw YAML, decoded/raw value, schema-valid layer, registry
candidate, mutable map, source path, preset bytes, partially merged candidate,
or pre-safety policy. Its sole consumer-visible value is the borrowed immutable
`ValidToolchain` constructed after post-composition safety validation. There is
no service-consumer exception; intermediate workflow keys are not service authority.
Persistence of validated bootstrap authority
remains runner/transaction work outside this read-only boundary.

## 4. Read-only and logging boundary

F0003 uses F0002 LogService as its only logging mechanism. Because F0002 is
not a general logger, the service receives no logger or sink capability; the
runner reports F0003 nodes through the selected compiled workflow's validated,
runner-created `WorkflowLog` binding and the existing registered `action.*`
lifecycle facts.

Read-only means F0003 has no create, update, rename, delete, install, migrate,
process, command, model, network, transaction, state-transition, or project
write capability. It does not mutate `toolchain.yaml`, a preset package, the
effective result, shared workflow state, or configuration. It has no reload,
watch, caller-selected cache, compatibility projection, command-template
resolver, or default-test-command helper.

Before a current feature-log binding exists, bootstrap uses its typed
non-logging diagnostic path; no competing global or direct logger is
permitted. A requirement for a persisted pre-binding record would need a
separate approved F0002 contract.

Toolchain or preset bodies, raw commands, and operational paths are never log
payloads. F0002 owns filtering, redaction, persistence, and failure behavior;
its logging write is not a source mutation by F0003. A logging failure follows
F0002's existing fail-closed outcome and cannot be converted into successful
safety-valid toolchain publication.

## 5. Detailed `_structure.yaml` review

`_structure.yaml` is a useful checklist of legacy concern families:
framework, package management, build, test, physical path policy, quality, and
AST support. It is not a closed schema and is not the structure of an accepted
runtime object. It remains unchanged by this feature.

| Inconsistency | Evidence and consequence | F0003 treatment |
| --- | --- | --- |
| No enforceable contract | Requiredness exists only in comments and every `<!-- IMPLEMENT -->` marker is a valid YAML scalar. `_structure.yaml` itself defines no unknown-field, duplicate-key, conditional, or supported-version policy. | Privately parse into an owned raw value, validate it into the closed Zig layer, reject placeholders and unknown structure before inheritance, and never publish either intermediate. |
| Identity and inheritance are absent | `version: "1.0"` carries no API/package identity, exact package version, layer discriminator, direct project-binding contract, transitive preset-dependency contract, or typed override contract. | Keep project-layer bindings and preset-package identity/dependencies in separate typed contracts. Never infer identity from a filename. |
| Layer responsibilities are mixed | The seed nests language under build, while sibling examples combine framework, package manager, runtime/language, build, test, protection, and parser policy in monoliths. | Preserve composable language/runtime/framework/build/test/environment package layers from governing Section 10. |
| Shapes drift across source examples | Siblings add undeclared `protection`, `test.runner`, and `build.language.name`; grammar values alternate between scalars and untagged objects. | Treat the seed and siblings as inconsistent source evidence, not as a union to accept. |
| Commands are unsafe raw text | Commands, detached flags, and placeholders are strings; siblings contain redirection, glob expansion, nested quoting, and unproven `npx` behavior. No argv, cwd, environment, network, timeout, resource, mutability, effect, or sandbox contract exists. | F0003 never admits commands in project or preset documents. A separate command-policy contract would be required before commands could become runtime authority. |
| Merge behavior is unspecified | The file defines neither per-field precedence nor map, set, array, atomic-command, append, remove, or locked-rule semantics. | Use only contract-declared operators and reject an unsafe effective merge. No generic recursive merge belongs in F0003. |
| Paths and patterns are ambiguous | Roots and globs lack stable rule IDs, base/target domains, pattern type, case policy, ownership, and portability semantics. Brace globs used by siblings are outside the governing grammar; `pathPolicies` covers only config/style. | Path-pattern and file-kind policy owners compile typed rules after inheritance. F0003 exposes nothing pre-compilation as authority. |
| Parser/query identity is incomplete | Extension maps point to raw grammar names or project-relative query paths without package/version identity, required captures, containment, compilation, resolver, fallback, or missing-resource behavior. | Preset registry validation must close every declared asset reference before project selection. |
| Capability absence is ambiguous | Some examples declare E2E locations without commands and cannot distinguish unsupported capability from omitted data. Other package-add commands do not prove manifest mutation. | The closed F0003 contract contains no inferred capability; absence is simply outside this service's authority. |

The current `_structure.yaml` and sibling examples therefore remain
non-normative source material. A separate offline migration may accept an
explicitly selected legacy source, but F0003 never reads these files as a
default, silently upgrades them, or falls back to them when runtime authority
is absent.

## 6. Legacy engine usage review

At the user's request, this review inspected the local legacy
`sdd-workflow-engine` working tree as it existed on 2026-08-29. The observations
below are non-normative comparison evidence, not SDDE authority or a runtime
dependency. Its current flow is:

```text
DefaultWorkflowToolchainService
  -> receives config paths, but per-call/shared-state path values take precedence
  -> absent principles/templates values fall back to built-in directories
  -> loadToolchainAuthority reads principles/toolchain.yaml
  -> scalar extends loads templates/toolchainPresets/<name>.yaml
  -> recursively loads preset extends and generically deep-merges records
  -> validates/derives an authority envelope
  -> caches or reloads it in mutable shared workflow state
  -> also resolves command templates and a default test command
```

The main evidence is in `src/workflow/toolchainService.ts`,
`src/workflow/toolchainService.helper.ts`,
`src/workflow/loadToolchainSetupHandler.ts`,
`src/toolchain/toolchainLoader.ts`, `src/toolchain/toolchainPresets.ts`,
`src/toolchain/toolchainRecordMerge.helper.ts`, and
`src/toolchain/toolchainValidator.ts`. Supporting evidence is in
`src/workflow/loadedToolchainAuthorityState.helper.ts`,
`src/toolchain/loadedToolchainAuthority.helper.ts`,
`src/toolchain/toolchainSourceAuthorityResolver.helper.ts`,
`src/config/configMerger.ts`, and `src/config/configTypes.ts`.

| Legacy observation | Concept carried into F0003 | Mechanic deliberately not carried |
| --- | --- | --- |
| Runtime code does not parse `_structure.yaml` as a schema. Compatibility tests explicitly exclude it from concrete preset inventories; production validation mentions it only in a human-facing suggestion. | Keep structural decoding in one closed typed implementation contract. | Reading `_structure.yaml` at runtime, treating its comments/placeholders as constraints, or accepting sibling files because they resemble it. |
| Its `_structure.yaml` copy has drifted from the SDDE source: it omits `framework` and marks `package`, `build`, and `test` mandatory where the current SDDE file marks them optional. | None; the difference confirms that the closed Zig validation contract, not either documentation copy, must own the accepted shape. | Selecting either documentation copy as runtime authority or merging the two shapes. |
| Uses one fixed `toolchain.yaml` below the selected principles directory and records source provenance. | Fixed filename, validated containment, immutable source evidence, and no auto-detection. | Default principles paths, optional absence, caller path overrides, or raw string path construction outside typed capabilities. |
| Recursive loading detects inheritance cycles; later shared-state publication canonicalizes unique physical source identities. | Exact resolution, cycle/duplicate/conflict rejection, and complete provenance at the owning boundary. | Scalar unversioned `extends`, filename identity, `.yaml`/`.yml` first-match lookup, or preset storage under `paths.templates/toolchainPresets`. |
| Merges inherited values before validating the resolved result. | Dependency-first deterministic composition and validate-before-publish. | Generic recursive map merge with implicit array replacement and no per-field operator or locked-safety proof. |
| Its state helper freezes the cached authority envelope and clones consumer projections. | One immutable post-composition safety-valid result with no partial publication. | Mutable shared-state cache, `reload`, compatibility copies, optional deletion, or multiple query projections. |
| The service also exposes `resolveCommand` and `getDefaultTestCommand`. | None; command consumers use compiled typed command IDs from the owning policy. | Command interpolation, arbitrary dot-string getters, and mixed reader/query/execution responsibilities. |
| Runtime merges then validates, while the legacy file validator validates the raw project layer and resolved preset separately. | One canonical post-composition validation pipeline. | Split judges that can disagree on the same `toolchain.yaml`. |
| Loader code performs synchronous filesystem reads and obtains a global logger; the setup handler separately accepts a free-text debug callback. | Narrow no-follow read ports and F0002 lifecycle observability. | Direct infrastructure imports, two logging mechanisms, free-text messages, caller-chosen fields, or raw path/preset data in logs. |
| Reads use existence/stat checks followed by unbounded reads and may resolve through links. | Bounded capture, stable descriptor evidence, and contained source identity. | Time-of-check/time-of-use gaps, unbounded input, followed links, or optional treatment of an invalid present file. |
| Configuration-derived values, per-call/shared-state overrides, and built-in defaults compete to select principles/templates roots. | One F0004 typed capability for each exact root. | F0003 access to F0001, derivation from a common toolkit path, caller precedence, or built-in fallback roots. |
| Legacy configuration has `paths.templates` but no `paths.toolchainPreset`. | Presets come only from the explicit configured preset-registry root. | Treating templates as executable preset authority or using a source/package fallback. |

The useful concepts are therefore fixed-location capture, provenance,
inheritance validation, cycle rejection, effective-result validation, and
immutable publication. The legacy service class, state mutation, reload model,
path fallbacks, raw commands, logging implementation, and generic merge are not
design inputs.

## 7. Acceptance criteria

1. `ToolChainService` has exactly one responsibility: expose one immutable
   `ValidToolchain` through its concrete read-only `toolchain()` accessor. The
   bounded loading actions remain separate and expose no consumer query.
2. F0001 remains the only `.sddtoolkit.json` reader, and the path-policy owner
   remains the only owner that turns its raw path strings into capabilities.
   F0003 receives those capabilities only through F0004's
   `projectPrinciples()` and `toolchainPresetRegistry()` accessors.
3. Selected toolchain operations read only exact `<paths.principles>/toolchain.yaml` and direct
   children of the `paths.toolchainPreset` registry. Neither uses an alternate,
   template, source, packaged, ancestor, descendant, or current-directory
   fallback.
4. The project layer parses into an owned raw value and then validates into a
   closed owned Zig layer. The complete preset registry passes its separate
   typed validation before inheritance is resolved. The two JSON Schema files
   document those same closed YAML shapes but are not runtime inputs. Raw and schema-valid results
   are runner-private intermediates and cannot construct `ToolChainService`.
5. Every inherited preset identity/version resolves exactly once; missing,
   duplicate, conflicting-version, ranged/latest, and cyclic closures
   fail closed.
6. Only deterministic contract-declared merge behavior is used, and the merged
   result cannot reach a consumer before post-composition safety validation.
7. Only post-composition safety validation can construct the canonical
   `ValidToolchain` and publish `ToolChainService`. `toolchain()` returns only a
   borrowed `*const ValidToolchain`; raw bytes, decoded values, source paths,
   layer/registry states, mutable maps, and partial/pre-safety candidates are
   not queryable.
8. F0003 cannot write source/config/preset/project/state data, execute a
   command, call a model, use the network, mutate shared state, or expose a
   reload/watch/compatibility API.
9. Every F0003 log uses F0002's active `WorkflowLog`/feature binding and
   existing action lifecycle facts; it cannot select log content or a sink,
   and pre-binding work uses no competing logger.
10. Source examples are never searched or used as runtime authority or
    fallback. If a legacy-shaped document is installed beneath the configured
    registry and encountered by selected setup, it rejects rather than upgrades it.
11. Equal complete validated inputs and equal prior authority produce a
    direct-equal `ValidToolchain`; any failure before its safety gate publishes
    neither a service nor a partial authority.
12. The packaged executable requires no SDDE source tree, design examples,
    legacy TypeScript engine, development cache, or Zig toolchain at runtime.
13. Workflows without toolchain operations do not read toolchain documents,
    including when another installed workflow references those operations.

## 8. Verification

Implementation tests cover the owning boundaries:

- path authority: the exact principles root and no-follow
  file, plus rejection of missing, escaping, aliased, linked, special-node,
  alternate, source-example, template, and packaged-fallback cases; the later
  preset registry separately covers its exact configured root;
- typed decoding and boundary confinement: accepted project documents plus
  malformed YAML, duplicate/unknown/missing/wrong-kind fields, unresolved
  placeholders, `_structure.yaml`, and unrelated representative legacy
  documents; raw/schema-valid candidates pass only through their exact
  runner-owned bindings and cannot construct or enter a public service API;
- preset-registry work: accepted packages, unsupported versions,
  unresolved assets, legacy documents, and an invalid unselected package;
- inheritance: multiple unrelated valid compositions and rejected missing,
  duplicate, conflicting-version, ranged/latest, and cyclic
  representatives;
- composition: stable dependency/layer/reference ordering, stable policy-set
  union, and rejection of unregistered policy or attempted compiler-lock weakening;
- validated accessor: only safety-gate evidence can construct
  `ValidToolchain`; repeated `toolchain()` calls return the same borrowed value
  without I/O or allocation, and no generic or pre-safety accessor exists;
- read-only ownership: filesystem/process/model/network/state spies proving
  source reads only, one post-composition safety-valid published view, no
  service on every earlier or failed branch, no reload or mutation path, and
  cleanup on every outcome;
- logging: the selected compiled workflow's registry-validated shortcode on
  existing F0002 action lifecycle events after binding, the typed non-logging
  diagnostic before binding, no
  service-selected message/path/body or competing logger, and fail-closed
  logging error; and
- packaging: clean native-executable bootstrap with only target-owned runtime
  configuration, project toolchain layer, and installed preset registry.

## 9. Traceability

| Concern | Authority |
| --- | --- |
| Single responsibility and action/runner boundary | Design Sections 3.3 and 5-6 |
| Immutable configuration and typed path origin | Design Section 9; F0001; `design/paths.md` |
| Exact `toolchain.yaml`, preset root, inheritance, merge, and safety | Design Sections 9.3-10 and 15 |
| Path and command safety | Design Sections 11 and 26 |
| Logging handoff | F0002; Design Sections 13.9, 26.5, and 27 |
| Bootstrap ownership and sequencing | `design/diagrams/08-toolchain-preset-bootstrap.md` |
| `_structure.yaml` and legacy-example status | Design Section 10; `design/toolchainPresets/_structure.yaml` |
| Verification and clean packaging | Design Sections 28 and 30-31 |
