# F0003 — ToolChainService

**Status:** Proposed feature design

**Implementation readiness:** Not ready for implementation. The requested
`SDDToolchainService` dependency is not yet a repository contract, and the
closed project-toolchain and preset-package schemas required by the governing
design do not yet exist. Section 2 records that authority gap; neither missing
contract is invented here.

**Classification:** Core, read-only mechanical toolchain provider

**Scope:** SDDE engine development. This document does not authorize running
SDDE against a target project. It authorizes no code change and does not accept
or amend the governing proposed design.

**Governing authority:** [Engine design](../design.md), especially Sections
1, 3-6, 9-11, 15, 28, and 30-31; [F0001 —
SDDToolKitReader](F0001-SDDToolKitReader.md); [F0002 —
LogService](F0002-LogService.md); the [path contract](../paths.md); and the
[toolchain-preset bootstrap diagram](../diagrams/08-toolchain-preset-bootstrap.mmd).
The [`_structure.yaml`](../toolchainPresets/_structure.yaml) file is reviewed
as source material in Section 5; it is not promoted to runtime authority.

---

## 1. Responsibility

F0003 has one responsibility: make the current invocation's immutable,
validated mechanical toolchain authority available to declared consumers.

That authority is derived from the complete registry beneath
`paths.toolchainPreset` and the exact project layer at
`<paths.principles>/toolchain.yaml`, which selects exact packages from that
registry. Nothing is published until the project layer, complete preset
registry, inheritance closure, deterministic composition, and effective merged
policy have all passed their owning validators.

F0003 names this read-only feature boundary. The runner publishes the validated
`ToolchainPresetRegistryState`, validated `ProjectToolchainLayer`, and
post-composition safety-valid compiled policy through declared typed keys.
Operational consumers receive only the compiled policy. No service registry,
generic getter, cache, copied projection, or second authority is introduced.
The runner uses the existing single-responsibility actions for the loading
steps and owns each published value's invocation lifetime.

## 2. Path authority and the requested upstream service

No repository contract named `SDDToolchainService` exists. Current authority
derives both root capabilities from F0001's immutable configuration through
the bootstrap-root/path-policy owner. Whether the requested name is a
correction for that existing binding or a proposed new abstraction remains an
explicit implementation blocker; F0003 does not define it or create a second
configuration/path authority. The smallest decision needed is to identify that
name with the existing validated principles-root binding, or first approve a
separate narrow contract and name the path authority it replaces.

The two legal source locations are:

| Source | Location authority |
| --- | --- |
| Project toolchain layer | The exact no-follow child `<projectRoot>/<paths.principles>/toolchain.yaml`, resolved from the validated principles-root capability. |
| Preset registry | The exact validated `<projectRoot>/<paths.toolchainPreset>` root, where the raw configuration value comes only from F0001's `paths.toolchainPreset`. |

Decoded path strings are information, not filesystem authority. F0003 never
accepts a caller path, absolute path, alternate filename, environment override,
ancestor/descendant search result, `paths.templates` substitute, source-tree
example, or packaged fallback.

## 3. Minimal loading and inheritance contract

F0003 reuses the governing bootstrap slice rather than defining a parallel
loader:

1. `ResolveConfiguredToolchainPresetRootAction` selects the sole validated
   preset-registry capability from `paths.toolchainPreset`.
2. The existing preset inventory and validation actions account for and
   validate the complete registry independently of project selection.
3. `ResolveProjectToolchainLayerPathAction` resolves only the exact
   `toolchain.yaml`; capture reads it once as a bounded no-follow regular file.
4. `ParseProjectToolchainLayerAction` parses YAML 1.2 and
   `ValidateProjectToolchainLayerSchemaAction` applies the separate closed,
   versioned project-layer contract.
5. `ResolveProjectToolchainInheritanceAction` resolves every exact direct
   preset identity and version against the complete validated registry.
6. The existing graph, ordering, composition, and safety actions reject
   missing, duplicate, conflicting-version, incompatible-layer, and cyclic
   closures; apply only schema-declared merge operators; and validate the
   effective merged result against compiler-locked safety policy.
7. Only that safety-valid merged policy is exposed as the immutable effective
   toolchain view.

Every declared inheritance binding names an exact preset package identity and
version, not a directory, filename guess, version range, implicit `latest`, or
untyped map. Preset packages may have a validated transitive composition graph;
the project `toolchain.yaml` supplies only its exact direct bindings and typed
overrides. Project-layer validation alone makes no safety claim; the
post-composition safety validator rejects any effective merged result that
weakens compiler-locked safety.

The bootstrap diagram also covers inventory ledgers, recovery, persistence,
authority-change routing, environment compilation, and downstream
invalidation. Those remain runner, transaction, bootstrap, and policy-compiler
responsibilities. F0003 neither duplicates nor hides them behind a service
method.

F0003 publishes no raw YAML, mutable map, source path, preset bytes, partially
merged candidate, or pre-safety policy. Operational consumers receive only the
borrowed immutable compiled policy. Persistence of validated bootstrap
authority remains runner/transaction work outside this read-only boundary.

## 4. Read-only and logging boundary

F0003 uses F0002 LogService as its only logging mechanism. Because F0002 is
not a general logger, the service receives no logger or sink capability; the
runner reports F0003 nodes through the calling workflow's validated
`WorkflowLog` and the existing registered `action.*` lifecycle facts.

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
toolchain publication.

## 5. Detailed `_structure.yaml` review

`_structure.yaml` is a useful checklist of legacy concern families:
framework, package management, build, test, physical path policy, quality, and
AST support. It is not a closed schema and is not the structure of an accepted
runtime object. It remains unchanged by this feature.

| Inconsistency | Evidence and consequence | F0003 treatment |
| --- | --- | --- |
| No enforceable contract | Requiredness exists only in comments and every `<!-- IMPLEMENT -->` marker is a valid YAML scalar. `_structure.yaml` itself defines no unknown-field, duplicate-key, conditional, or supported-version policy. | Parse runtime data only through future accepted closed schemas; reject placeholders and unknown structure. |
| Identity and inheritance are absent | `version: "1.0"` carries no API/package identity, exact package version, layer discriminator, direct project-binding contract, transitive preset-dependency contract, or typed override contract. | Keep project-layer bindings and preset-package identity/dependencies in their separate versioned schemas. Never infer identity from a filename. |
| Layer responsibilities are mixed | The seed nests language under build, while sibling examples combine framework, package manager, runtime/language, build, test, protection, and parser policy in monoliths. | Preserve composable language/runtime/framework/build/test/environment package layers from governing Section 10. |
| Shapes drift across source examples | Siblings add undeclared `protection`, `test.runner`, and `build.language.name`; grammar values alternate between scalars and untagged objects. | Treat the seed and siblings as inconsistent source evidence, not as a union to accept. |
| Commands are unsafe raw text | Commands, detached flags, and placeholders are strings; siblings contain redirection, glob expansion, nested quoting, and unproven `npx` behavior. No argv, cwd, environment, network, timeout, resource, mutability, effect, or sandbox contract exists. | F0003 never admits these legacy shapes as runtime authority. Accepted runtime packages contain structured command descriptors validated by the command-policy owner. |
| Merge behavior is unspecified | The file defines neither per-field precedence nor map, set, array, atomic-command, append, remove, or locked-rule semantics. | Use only schema-declared operators and reject an unsafe effective merge. No generic recursive merge belongs in F0003. |
| Paths and patterns are ambiguous | Roots and globs lack stable rule IDs, base/target domains, pattern type, case policy, ownership, and portability semantics. Brace globs used by siblings are outside the governing grammar; `pathPolicies` covers only config/style. | Path-pattern and file-kind policy owners compile typed rules after inheritance. F0003 exposes nothing pre-compilation as authority. |
| Parser/query identity is incomplete | Extension maps point to raw grammar names or project-relative query paths without package/version identity, required captures, containment, compilation, resolver, fallback, or missing-resource behavior. | Preset registry validation must close every declared asset reference before project selection. |
| Capability absence is ambiguous | Some examples declare E2E locations without commands and cannot distinguish unsupported capability from omitted data. Other package-add commands do not prove manifest mutation. | Require a typed supported or disabled-with-reason result; never infer capability from a nearby string. |

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
| Runtime code does not parse `_structure.yaml` as a schema. Compatibility tests explicitly exclude it from concrete preset inventories; production validation mentions it only in a human-facing suggestion. | Keep structure validation in an accepted machine-enforced schema. | Reading `_structure.yaml` at runtime, treating its comments/placeholders as constraints, or accepting sibling files because they resemble it. |
| Its `_structure.yaml` copy has drifted from the SDDE source: it omits `framework` and marks `package`, `build`, and `test` mandatory where the current SDDE file marks them optional. | None; the difference confirms that a separate versioned schema must own the contract. | Selecting either documentation copy as authoritative or merging the two shapes. |
| Uses one fixed `toolchain.yaml` below the selected principles directory and records source provenance. | Fixed filename, validated containment, immutable source evidence, and no auto-detection. | Default principles paths, optional absence, caller path overrides, or raw string path construction outside typed capabilities. |
| Recursive loading detects inheritance cycles; later shared-state publication canonicalizes unique physical source identities. | Exact resolution, cycle/duplicate/conflict rejection, and complete provenance at the owning boundary. | Scalar unversioned `extends`, filename identity, `.yaml`/`.yml` first-match lookup, or preset storage under `paths.templates/toolchainPresets`. |
| Merges inherited values before validating the resolved result. | Dependency-first deterministic composition and validate-before-publish. | Generic recursive map merge with implicit array replacement and no per-field operator or locked-safety proof. |
| Its state helper freezes the cached authority envelope and clones consumer projections. | One immutable accepted result with no partial publication. | Mutable shared-state cache, `reload`, compatibility copies, optional deletion, or multiple query projections. |
| The service also exposes `resolveCommand` and `getDefaultTestCommand`. | None; command consumers use compiled typed command IDs from the owning policy. | Command interpolation, arbitrary dot-string getters, and mixed reader/query/execution responsibilities. |
| Runtime merges then validates, while the legacy file validator validates the raw project layer and resolved preset separately. | One canonical post-composition validation pipeline. | Split judges that can disagree on the same `toolchain.yaml`. |
| Loader code performs synchronous filesystem reads and obtains a global logger; the setup handler separately accepts a free-text debug callback. | Narrow no-follow read ports and F0002 lifecycle observability. | Direct infrastructure imports, two logging mechanisms, free-text messages, caller-chosen fields, or raw path/preset data in logs. |
| Reads use existence/stat checks followed by unbounded reads and may resolve through links. | Bounded capture, stable descriptor evidence, and contained source identity. | Time-of-check/time-of-use gaps, unbounded input, followed links, or optional treatment of an invalid present file. |
| Configuration-derived values, per-call/shared-state overrides, and built-in defaults compete to select principles/templates roots. | One F0001/path-policy authority for each exact root. | Derivation from a common toolkit path, caller precedence, or built-in fallback roots. |
| Legacy configuration has `paths.templates` but no `paths.toolchainPreset`. | Presets come only from the explicit configured preset-registry root. | Treating templates as executable preset authority or using a source/package fallback. |

The useful concepts are therefore fixed-location capture, provenance,
inheritance validation, cycle rejection, effective-result validation, and
immutable publication. The legacy service class, state mutation, reload model,
path fallbacks, raw commands, logging implementation, and generic merge are not
design inputs.

## 7. Acceptance criteria

1. F0003 has exactly one responsibility: publish the validated mechanical
   toolchain states and compiled policy for read-only invocation use.
2. F0001 remains the only `.sddtoolkit.json` reader, and the path-policy owner
   remains the only owner that turns its raw path strings into capabilities.
3. Only exact `<paths.principles>/toolchain.yaml` and the direct
   `paths.toolchainPreset` registry are read; no alternate, template, source,
   packaged, ancestor, descendant, or current-directory fallback exists.
4. The project layer and complete preset registry pass separate closed,
   versioned schemas before inheritance is resolved.
5. Every inherited preset identity/version resolves exactly once; missing,
   duplicate, conflicting, incompatible, ranged/latest, and cyclic closures
   fail closed.
6. Only deterministic schema-declared merge behavior is used, and the merged
   result cannot reach a consumer before post-composition safety validation.
7. The runner publishes the validated registry/layer states and one borrowed
   immutable compiled policy; operational consumers never receive raw bytes,
   source paths, a mutable map, or a partial/pre-safety candidate.
8. F0003 cannot write source/config/preset/project/state data, execute a
   command, call a model, use the network, mutate shared state, or expose a
   reload/watch/compatibility API.
9. Every F0003 log uses F0002's active `WorkflowLog`/feature binding and
   existing action lifecycle facts; it cannot select log content or a sink,
   and pre-binding work uses no competing logger.
10. Source examples are never searched or used as runtime authority or
    fallback. If a legacy-shaped document is installed beneath the configured
    registry and encountered, bootstrap rejects it rather than upgrading it.
11. Equal complete validated inputs and equal prior authority produce a
    direct-equal accepted result; a failure publishes no partial authority.
12. The packaged executable requires no SDDE source tree, design examples,
    legacy TypeScript engine, development cache, or Zig toolchain at runtime.

## 8. Verification

Future implementation tests must cover the owning boundaries:

- path authority: both exact configured roots, exact no-follow file, and
  rejection of missing, escaping, aliased, linked, special-node, alternate,
  source-example, template, and packaged-fallback cases;
- schema and registry: accepted project/preset documents plus malformed YAML,
  duplicate/unknown/missing fields, unsupported versions, unresolved
  placeholders/assets, `_structure.yaml` plus unrelated representative legacy
  documents, and an invalid unselected package;
- inheritance: multiple unrelated valid compositions and rejected missing,
  duplicate, conflicting-version, wrong-layer, ranged/latest, and cyclic
  representatives;
- composition: stable ordering and field provenance, explicit map/set/atomic
  command/array operators, and a schema-valid override whose effective result
  weakens a compiler lock;
- read-only ownership: filesystem/process/model/network/state spies proving
  source reads only, one immutable published view, no partial result, no reload
  or mutation path, and cleanup on every outcome;
- logging: the calling workflow's shortcode on existing F0002 action lifecycle
  events after binding, the typed non-logging diagnostic before binding, no
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
| Bootstrap ownership and sequencing | `design/diagrams/08-toolchain-preset-bootstrap.mmd` |
| `_structure.yaml` and legacy-example status | Design Section 10; `design/toolchainPresets/_structure.yaml` |
| Verification and clean packaging | Design Sections 28 and 30-31 |
