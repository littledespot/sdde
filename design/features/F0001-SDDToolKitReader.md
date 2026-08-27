# F0001 — SDDToolKitReader

**Status:** Proposed feature design

**Implementation readiness:** Blocked on the governing catalogue prerequisites
in Sections 4.5 and 13.1; no local implementation substitute is authorized.

**Classification:** Core, read-only bootstrap configuration-ingestion feature

**Mutability:** Strictly read-only. This feature receives no project or
configuration mutation capability.

**Runtime lifetime:** Raw capture, parser state, the schema-valid aggregate,
ingestion-seal values, and projection candidates remain runner-owned only
through their last declared bootstrap consumer. Later nodes retain only the
validated root registry, accepted bootstrap authority, and consumer-specific
compiled values owned by their contracts. F0001 is never a persistent,
workflow-lifetime, or cross-run settings cache.

**Scope:** SDDE engine development. This document specifies behavior and
boundaries only; it does not authorize running SDDE against a target project.

**Governing authority:** This feature refines, but does not accept, amend, or
supersede, the proposed contracts in [the engine design](../design.md),
especially Sections 3-6, 9, 13.1, 15, 24-26, and 28-31. The focused
[path contract](../paths.md) is also governing input. Shapes in
[the code samples](../code.md#engine-configuration) and the repository's
`design/examples/.sddtoolkit.json` are illustrative only; neither is the
formal runtime schema or a fallback configuration.

---

## 1. Purpose

`SDDToolKitReader` owns one logical outcome: from a trusted invocation working
directory, produce exactly one immutable, validated engine-configuration
ingestion seal and the narrow schema-valid projections authorized for
bootstrap consumers. Its responsibility begins with locating the exact
`.sddtoolkit.json` and ends when the runner validates and applies those
projections. It does not turn declarative settings into effective operational
policy, choose derived artifact paths, persist bootstrap authority, or operate
a runtime service.

Ordinary bootstrap and four-stage runtime services must not locate, open,
reread, parse, or inspect `.sddtoolkit.json` themselves. They must not receive
raw configuration bytes, a JSON object, an arbitrary setting lookup facility,
or filesystem access from this feature. The separately authorized offline
legacy-migration adapter remains outside this feature and does not become a
runtime alternate reader.

For logging, the reader's terminal product is only the validated,
destination-free logging-settings projection required by the separately owned
logging-policy compiler. Policy compilation, bootstrap-authority persistence,
feature/run binding, artifact-path derivation, and record processing belong to
other owners. F0001 neither calls nor implements F0002.

`SDDToolKitReader` is a feature name, not a capability-heavy object or one
multi-verb action. No callable `SDDToolKitReader` facade, singleton, getter, or
runtime service type exists. The composition root constructs a
compiler-validated, runner-executed graph of discrete configuration actions
and private adapters. Locating, reading, parsing, schema validation, reference
validation, limit validation, invariant validation, root validation, and
projection remain separate one-responsibility operations.

## 2. Required outcomes

The feature must provide these observable outcomes:

1. Every feature operation is read-only: on success, rejection, cancellation,
   timeout, and operational failure, the feature issues no operation that
   creates, modifies, renames, deletes, migrates, persists a cache, or changes
   permissions on the configuration, project, durable engine state, or another
   filesystem resource.
2. Starting from the invocation working directory, the engine selects the
   nearest canonical ancestor containing the exact file
   `.sddtoolkit.json`.
3. The selected file's containing directory is the canonical project root;
   callers cannot supply a different root or alternate configuration path.
4. `ReadEngineConfigAction` and `ParseEngineConfigAction` are each invoked at
   most once per root-workflow or standalone-stage invocation; successful
   bootstrap invokes each exactly once. Ingestion values remain runner-owned
   only until their last declared bootstrap consumer, while accepted
   downstream registries and compiled authorities follow their own lifetimes.
5. Malformed, unsupported, unknown, ambiguous, unsafe, or incomplete
   configuration fails closed before any model call or workflow side effect.
6. No raw or partially validated configuration value escapes the private
   ingestion chain.
7. The complete schema-valid configuration remains a private ingestion-chain
   aggregate; every consumer outside that chain receives only a versioned,
   immutable, typed projection containing the settings and provenance that its
   own contract requires.
8. F0001 produces declarative projections only for runner validation and
   application. A named downstream compiler owns every conversion to effective
   policy, and an operational service cannot consume the reader projection as
   a shortcut.
9. Equal complete normalized input—including invocation location and resource
   identity/provenance—under the same schema, registries, filesystem policy,
   and engine hard bounds produces the same typed projections and diagnostic
   ordering.
10. No stage, task, action, orchestrator, or operational service rereads or
    reparses the file during the active workflow; it consumes its declared
    immutable root registry, accepted authority, compiled value, or capability
    rather than a retained whole-configuration service.
11. The logging projection contains only the exact schema-valid `logs` member
    and completed-ingestion-seal identity. It contains no compiled policy,
    feature, run, stream, binding, segment, path, destination, sink, or
    filesystem capability.
12. F0001 performs no access beneath a derived feature log collection and
    produces no `CompiledFeatureLoggingPolicyFragment`, `FeatureLogPolicy`,
    `FeatureLogBinding`, sink state, log record, or logging control outcome.

## 3. Scope

### 3.1 In scope

- accepting a trusted invocation working-directory descriptor;
- bounded nearest-first ancestor discovery;
- exact `.sddtoolkit.json` basename matching;
- canonical project-root binding from the selected file location;
- read-only access on every branch, with no mutation-capable port;
- rejection of aliases, symlinks, and non-regular configuration resources;
- bounded, complete, no-follow file reading with stable resource identity;
- deterministic JSON parsing;
- versioned closed-schema validation;
- rejection of unknown and duplicate fields;
- validation of configuration references against closed registries;
- validation of numeric limits against engine-owned hard ceilings;
- validation of schema-declared cross-field invariants;
- normalization and validation of the exact seven configured base roots;
- construction and validation of the immutable `BootstrapRootRegistry`;
- immutable, consumer-specific configuration projections;
- bounded runner-owned retention through each ingestion value's last declared
  bootstrap consumer;
- snapshot ownership, cleanup, diagnostics, and failure behavior;
- configuration-reader unit, contract, architecture, security, integration,
  and packaged-executable verification.

### 3.2 Out of scope

- creating, editing, formatting, repairing, or migrating
  `.sddtoolkit.json`;
- accepting a caller-selected configuration filename or project root;
- watching the file, hot reloading it, or offering consumer-triggered reload;
- a process-global, cross-project, cross-run, serialized, or filesystem cache;
- using environment variables, source examples, packaged assets, or another
  file as fallback configuration;
- enumerating or parsing workflow definitions beneath `paths.workflows`;
- loading or composing preset packages beneath `paths.toolchainPreset`;
- parsing `<paths.principles>/toolchain.yaml`;
- reading semantic Markdown beneath `paths.principles`;
- reading, expanding, or copying anything beneath `paths.templates` during
  the four-stage runtime;
- discovering repository projects or manifests;
- compiling path, command, sandbox, dependency, model-route, validation,
  logging, review, state, or workflow policy into effective operational
  policy;
- applying configuration precedence with presets, the project toolchain
  layer, or permitted CLI overrides;
- executing commands, invoking a model, logging arbitrary content, writing
  workflow state, or creating project directories;
- selecting or binding an active feature/specification, deriving
  `<paths.specs>/<featureId>/logs/`, or creating, recovering, opening, locking,
  appending, rotating, retaining, or deleting a log destination, stream,
  segment, or sink;
- accepting or publishing a configurable log child path, filename,
  destination ID, `FeatureLogBinding`, or logging filesystem capability;
- selecting a JSON library, defining Zig method signatures, or adding a
  production dependency.

## 4. Ownership and architecture boundary

### 4.1 Logical feature boundary

The feature owns the complete configuration-ingestion use case from discovery
through publication of validated projections. This gives other services one
authoritative path to project settings while preserving the engine's action,
orchestrator, runner, and adapter boundaries.

Within that logical feature, configuration discovery owns the exact location,
and the narrower **engine configuration byte reader** consumes that validated
location and owns only bounded byte capture. JSON parsing, general
configuration validation, root validation, and specialized policy compilation
remain distinct owners and actions. Presenting one logical ingress contract to
ordinary consumers does not merge those internal responsibilities.

The single-responsibility test for every F0001 output is: it may answer only
“which configuration value was validated from this exact sealed ingestion?” It
must not answer “which operational policy is active?”, “where should an
artifact be stored?”, or “what runtime operation should occur?” Those questions
belong to downstream compilers, authority/state owners, artifact registries,
and operational features.

The feature is not:

- a pipeline action that performs several verbs;
- an orchestrator that opens files or parses JSON;
- an object that exposes the filesystem or parser to callers;
- a mutable settings singleton;
- a generic service locator or capability bag; or
- an alternate policy compiler.

The composition root constructs the concrete filesystem and parser adapters
and the compiler-registered child-node graph. The pipeline runner alone invokes
child bindings, validates and applies their deltas, and publishes their
declared typed outputs. No configuration action calls another action or
orchestrator.

### 4.2 Read-only invariant

`SDDToolKitReader` is observational only. Its filesystem-facing actions may
receive only the narrow discovery, metadata-inspection, and read operations
needed for their declared responsibilities. The feature must never receive or
exercise an operation that can mutate the configuration file or any other
project resource.

In particular, the feature must not:

- create a missing `.sddtoolkit.json` or any configured directory;
- write, truncate, append, patch, replace, rename, move, copy over, delete, or
  change permissions or ownership on any file or directory;
- repair, format, canonicalize in place, or migrate configuration content;
- persist a reader-owned cache, normalized copy, lock file, state record,
  marker, journal, or temporary file;
- acquire a mutation transaction, project write port, command capability, or
  writable overlay;
- make a discovered root writable merely by validating its configured access
  class; or
- convert diagnostics or telemetry into a reader-owned filesystem side
  effect.

The feature may return immutable in-memory values, evidence, diagnostics, and
typed root-policy descriptors. Those values can describe access that another
component may later receive, but they grant this feature no write adapter or
transaction authority. Any later project or engine-state mutation belongs to
its separately authorized owner and transaction.

Bounded ingestion values are not a persistent cache or filesystem mutation.
They are runner-owned immutable state, use no writable project capability, and
are destroyed after their individual last declared bootstrap consumers.

### 4.3 Required responsibility decomposition

The governing bootstrap actions retain these responsibilities. The existing
catalogue names are retained below. Where the catalogue currently overlaps
root-validation ownership, the registry row shows the proposed
non-duplicating split; it is not implementable until prerequisite 4 in
Section 4.5 is accepted.

| Boundary | Owned responsibility | Must not do |
| --- | --- | --- |
| `LocateExactEngineConfigAction` | Walk canonical ancestors nearest-first, select the exact basename, reject unsafe resource kinds, and bind the containing directory as project root. | Read or interpret file content, accept an alternate name, or select a fallback. |
| `ReadEngineConfigAction` | Read the one validated, bounded, no-follow resource completely. | Parse JSON, apply policy, or open another path. |
| `ParseEngineConfigAction` | Decode the captured bytes as JSON and preserve parse locations needed for diagnostics. | Apply schema or operational policy. |
| `ValidateEngineConfigSchemaAction` | Apply the supported versioned closed schema. | Resolve external registry entries or compile effective policy. |
| `ValidateConfigReferenceAction` | Resolve one named profile, route, reader, validator, or adapter reference. | Resolve unrelated references or select a substitute. |
| `ValidateConfigLimitAction` | Validate one configured limit against its engine-owned hard bound. | Weaken the bound, infer a default outside the schema, or validate unrelated policy. |
| `ValidateConfigInvariantAction` | Evaluate one closed cross-field predicate. | Repair input, emit a warning-only continuation, or choose its successor. |
| `ValidateRouteRegistryVersionAction` | Resolve the configured route-registry version against the built-in registry. | Treat schema-valid spelling as proof of support or select a nearest version. |
| `ValidateRendererContractVersionAction` | Resolve the configured renderer-contract version against the renderer registry. | Treat schema-valid spelling as proof of support or select a nearest version. |
| F0001 binding of `ValidateEnginePathPolicyAction` | Validate exactly one configured-root pair relation against the supplied pre-preset root policy. The shared action remains the owner of one general configured path relation in its other registered bindings. | Resolve a root, recompute unary root validity, claim every use of the shared action, validate an unrelated relation, or apply model-path policy. |
| `ResolveConfiguredBaseRootAction` | Join one schema-valid `paths` value to the canonical project root using the already detected active workspace filesystem policy. | Detect a filesystem policy, follow aliases, derive fixed descendants, or grant access. |
| `ValidateConfiguredBaseRootAction` | Prove one root's unary normalization, containment, active-workspace representability, access class, and declared existence/type policy against the exact config location and compiler-locked pre-preset root limits/rules. | Compare two roots, read root content, resolve target-platform policy, define portability policy, or turn a raw string into unrestricted filesystem access. |
| `BuildBootstrapRootRegistryIdAction` | After receiving the validated exact config location as a prerequisite, construct only the governing closed `(canonical project root, contract version)` identity. The config location is not an identity member. | Depend on configured-root validation, add the config location or content to the identity tuple, derive identity from a fingerprint, or consume a state ledger. |
| `BuildBootstrapRootRegistryAction` | Assemble the exact validated seven-root immutable `BootstrapRootRegistry`. | Add generated, preset-derived, repository-discovered, or caller-supplied roots. |
| `ValidateBootstrapRootRegistryAction` | Prove exact seven-role coverage and join each member to the complete required unary and pairwise evidence set, including the sole archive-nesting exception. | Recompute containment, representability, pairwise separation, or another root rule; load root content; derive child paths; or weaken evidence. |

The reader feature may present one cohesive outcome to its consumers, but that
outcome is assembled only after the runner has applied this chain's valid
typed deltas. A facade must not recreate the sequencing internally or bypass
the common `PipelineNode` contract.

### 4.4 Responsibilities owned elsewhere

| External owner | Responsibility at the F0001 boundary |
| --- | --- |
| Workspace filesystem-policy owner | Detect and validate the active workspace filesystem policy through its trusted adapter before configured-root resolution. F0001 consumes only that typed policy/evidence plus compiler-locked pre-preset root limits/rules. |
| Toolchain/environment portability owners | After the bootstrap roots make preset and project-toolchain inputs reachable, resolve configured target-platform policies and compile their union with the active workspace policy for downstream environment, repository, and artifact checks. F0001 neither performs that later compilation nor makes target policy an initial-root prerequisite. |
| Workflow-definition compiler | Inventory, capture, parse, validate, and bind the four declarative workflow definitions beneath the validated workflow root. |
| Toolchain and preset compiler | Load the direct preset registry, parse the exact project `toolchain.yaml`, compose inheritance and overrides, and validate the effective merged safety policy. |
| Principle ingestion | Account for the principles root, exclude exact `toolchain.yaml` from semantic ingestion, and capture only permitted Markdown. |
| Reference ingestion | Use the validated reference root and policy to enumerate and decode a bounded reference corpus. |
| Repository discovery | Resolve environments, manifests, projects, source roots, and repository facts. |
| Specialized policy compilers | Convert schema-valid configuration projections into validated route, workflow, review, validation, execution, state, reference, repository-discovery, and logging policy fragments. They receive no reader capability and do not persist or activate their output. |
| Workflow-artifact registry owner | `ResolveWorkflowArtifactPathsAction` derives the fixed `<paths.specs>/<featureId>/logs/` event and prompt collections from validated roots, feature identity, and the closed selector table; `ValidateWorkflowArtifactRegistryAction` proves their authority and containment. No reader or logging action derives these paths. |
| Bootstrap-authority and state owners | Assemble compiled fragments into a candidate state; persist an accepted state only through the owning transaction; compare current authority, classify changes, invalidate affected descendants, and authorize any successor transition. A compiler output is not active merely because it was produced. |
| Feature-logging owners | Consume the registry-owned collection IDs, reconstruct policy only from the exact persisted `CompiledFeatureLoggingPolicyFragment` in the bound `BootstrapAuthorityState`, and create or recover the feature/run-bound log binding after the required activation or recovery gate. They receive no raw or transient reader/compiler value and never ask the reader to choose a destination. |
| Application orchestrators | Coordinate runner-owned child bindings and branch only on typed outcomes. |
| Operational services | Consume only the effective typed policies or capabilities required for their one responsibility. |

### 4.5 Governing catalogue prerequisites

This feature cannot locally repair omissions or conflicts in the higher-order
action catalogue. Four prerequisites must be accepted in
[the engine design](../design.md) before the proposed seal/projection seam
is implementable:

1. `ReadEngineConfigAction` currently produces only raw configuration text,
   while the proposed completed-ingestion seal requires stable capture-resource
   identity and extent provenance. The governing action contract must either
   expose a typed capture/provenance result or explicitly remove that binding
   requirement; F0001 cannot infer the evidence after the read.
2. The catalogue exposes individual reference, limit, invariant, version, and
   root-validation evidence but no closed completion authority consumed by a
   projection. A registered assembly/validation pair or an equivalently typed
   compiler barrier must prove total applicable coverage. Schema success alone
   cannot authorize a consumer projection, and graph order without a key or
   barrier is insufficient. The same governing amendment must designate the
   schema-result identity/evidence bound to the exact capture, the typed
   producer and identity contract for one bootstrap attempt, and the sole owner
   plus closed applicability rule for a complete configuration-validation
   obligation manifest; none of those identity/manifest inputs currently has a
   catalogue owner. The Section 7.3 aggregate-to-member projection actions,
   types, and keys are also proposed additions and must be registered; a
   runner, facade, or consumer cannot perform an implicit field extraction.
3. `CanonicalizeLogLevelAction` owns alias canonicalization, while
   `ValidateLoggingPolicyAction` currently neither consumes its canonical
   result/evidence nor relinquishes alias/threshold semantics. That is
   duplicate functionality plus an unrepresented ordering dependency. The
   governing catalogue must select one owner; the smallest single-
   responsibility resolution is for the canonicalizer to own spelling/alias
   conversion and for the policy validator to consume its typed result while
   validating only the complete policy invariants.
4. `ValidateBootstrapRootRegistryAction` currently claims containment and
   separation already assigned to unary `ValidateConfiguredBaseRootAction`
   and pairwise `ValidateEnginePathPolicyAction`, without consuming their
   evidence. The catalogue must decide one owner. The smallest
   single-responsibility resolution is for the registry validator to prove
   total seven-role/evidence coverage and exact joins without recomputing unary
   or pairwise rules.

Until those contracts are accepted, an implementation must stop at the last
governing action whose inputs and outputs are fully defined. It must not add an
implicit projection, recompute provenance, duplicate canonicalization, rely on
incidental graph order, or widen a consumer input to the whole configuration.

## 5. Configuration discovery and project-root binding

### 5.1 Discovery input

The only location input is the invocation working directory supplied through a
trusted interface and filesystem boundary. It is not a model value, a field in
`.sddtoolkit.json`, a free-form project-root argument, or a raw configuration
path.

The parent-walk ceiling is engine-owned and available before project
configuration is trusted. The file being discovered cannot enlarge the limit
used to discover itself.

### 5.2 Selection algorithm

Discovery must:

1. canonicalize and validate the invocation working directory;
2. examine that directory and then its canonical ancestors in fixed
   nearest-first order, subject to the engine-owned ceiling;
3. continue upward only while the exact canonical scalar spelling
   `.sddtoolkit.json` is absent, rejecting rather than accepting a case-fold
   alias or collision;
4. reject bootstrap, without continuing to a farther ancestor, when that
   nearest exact entry is a symlink, alias, special node, or non-regular file;
   and
5. otherwise bind the selected file's containing directory as the canonical
   project root.

When a nested project and one of its ancestors each have a valid exact file,
the nested nearest match selects the nested project. Discovery does not scan
siblings or descendants and does not combine ancestor configurations.

### 5.3 No fallback

If the exact spelling is absent through the bounded ancestor walk, bootstrap
fails. If the first exact entry fails resource or content validation,
bootstrap also fails and the reader never resumes the parent walk. The reader
must not:

- treat the invocation directory as the project root without the file;
- accept a differently cased name, alias, extension, or legacy name;
- search `.specify/`;
- search the SDDE engine source tree;
- load `design/examples/.sddtoolkit.json`;
- use an asset embedded in or adjacent to the executable;
- synthesize defaults as a replacement document; or
- continue with a partial configuration.

## 6. Load, parse, and validate lifecycle

The configuration lifecycle is a fail-closed sequence:

```text
trusted invocation directory
  -> exact nearest configuration location and canonical project root
  -> bounded immutable raw snapshot
  -> parsed JSON candidate
  -> schema-valid configuration
  -> validated references, limits, and cross-field invariants
  -> externally detected active workspace filesystem policy
  -> unary configured-root evidence plus pairwise relation evidence
  -> validated BootstrapRootRegistry
  -> completed-ingestion seal
  -> narrow immutable consumer projections
```

Every arrow represents a typed boundary. A later value cannot be substituted
for an earlier one, and failure at any step prevents all outputs to its right.

### 6.1 Bounded snapshot

The selected file is opened through the exact no-follow descriptor returned by
discovery. The reader applies engine-owned byte, time, and resource ceilings;
it does not trust limits from the document until after the document has been
read and validated.

One successful load captures the complete file and verifies that the resource
identity and observed extent still match the validated descriptor. A short
read, resource replacement, identity change, size change, ceiling breach, or
read error rejects the snapshot. A fresh command invocation may attempt a new
load; the failed read never silently switches resources within its bootstrap.

The file descriptor is closed on every outcome. A producing node owns a raw
buffer or parser value until its delta is applied; after application, the
runner and immutable envelope own it. The pipeline invalidates and releases an
intermediate only after its last declared consumer, and the runner releases
all remaining values on terminal cleanup. A node retains no alias into an
applied or destroyed value.

### 6.2 JSON parsing

Parsing is deterministic and separate from schema validation. The parser must
reject malformed JSON, trailing non-document content, duplicate object member
names, invalid string encoding, and input beyond parser hard limits. It returns
source locations suitable for safe diagnostics but assigns no policy meaning,
defaults, capabilities, or project paths.

### 6.3 Closed-schema validation

The parsed candidate must pass the published formal schema for its declared
version. Policy-bearing objects are closed and reject unknown fields. Required
fields cannot be supplied by a similarly named legacy field, a case variant,
or an inferred sample value.

At minimum, validation rejects:

- an unsupported configuration schema version;
- missing required fields;
- unknown fields at a closed level;
- incorrect scalar, collection, or union variants;
- duplicate IDs or values where the schema requires uniqueness; and
- a similarly named legacy field, case variant, or illustrative sample value
  offered in place of a required field.

The formal schema is a prerequisite implementation artifact. This feature
does not promote the illustrative JSON in `design/code.md` or the abridged
legacy source example into that schema, and it does not select concrete sample
model names, numeric limits, or defaults.

### 6.4 Registry version, reference, limit, and invariant validation

After schema validation, dedicated actions reject:

- a route-registry version that does not resolve exactly through
  `ValidateRouteRegistryVersionAction`;
- a renderer-contract version that does not resolve exactly through
  `ValidateRendererContractVersionAction`;
- an unresolved compiler-registered named-reference kind;
- a numeric limit that is absent when required, invalid, or above an
  engine-owned hard maximum;
- a schema-declared cross-field invariant violation;
- `references.followSymlinks` with any value other than the v1 constant
  `false`;
- `state.useFingerprints` set to `true` in this design version; and
- any other compiler-registered raw configuration predicate assigned to the
  general configuration-validation boundary.

These checks remain distinct from specialized policy compilation. In
particular, a schema-valid logging section is not an effective logging policy,
and a schema-valid toolchain declaration has not passed post-composition
safety validation. A raw cross-field predicate is evaluated only by its one
registered general-validation owner. A specialized compiler consumes that
evidence and validates only its separately registered policy-level joins,
canonical values, hard bounds, and post-composition invariants. If one safety
property has distinct raw-input and effective-policy forms, they require
distinct typed rule IDs and evidence; the same predicate is never re-run under
a second authority.

### 6.5 Configured-root validation

The closed `paths` object contains exactly these seven required keys:

| Key | Root role |
| --- | --- |
| `specs` | The parent root for feature-facing specification views, controlled clarification forms, generated plan/task views, and feature logs. The workflow-artifact registry owner later derives each active feature's exact `<paths.specs>/<featureId>/logs/`; this root is not itself a log destination. |
| `references` | The sole base beneath which mandatory reference selectors resolve. |
| `specsArchive` | Archived specification material, excluded from active feature discovery. |
| `workflows` | Declarative workflow authority and the owner of engine-derived feature and transaction state children. |
| `toolchainPreset` | The direct registry root for validated toolchain preset packages. |
| `principles` | The exact mechanical `toolchain.yaml` project layer plus semantic Markdown principles. |
| `templates` | Inert principle templates reserved for an explicit future `sdd init` boundary. |

Each value must be a normalized project-relative directory root. Resolution
must prove containment within the canonical project root, no-follow identity,
active-workspace representability, the correct access class, and no alias or
workspace-policy collision under the compiler-locked pre-preset root rules.
Configured target-platform policy is resolved only after the validated roots
make preset and project-toolchain inputs reachable; its downstream ownership
does not become an F0001 root-validation responsibility.

Except for `specsArchive` beneath `specs`, configured roots cannot be equal,
nested, aliased, or collide under an active portability policy. No other
nesting exception exists.

`<paths.workflows>/features/` and
`<paths.workflows>/transactions/` are fixed engine-derived children, not
configuration fields. Each `<paths.specs>/<featureId>/logs/` child requires an
already validated `featureId` and is derived exclusively by
`ResolveWorkflowArtifactPathsAction`, then proven by
`ValidateWorkflowArtifactRegistryAction`. Feature logging consumes the
resulting registry-owned collection IDs; it does not derive the paths.
Clarification and final-validation-overlay paths are likewise derived by their
owning components. The reader must not accept or return a configured value for
any derived child.

The validated `templates` root remains reserved and inaccessible to ordinary
four-stage consumers. Its presence in the root registry is not permission to
read it, and its capability must not be passed to a model or normal workflow
action.

## 7. Minimal consumer contract

### 7.1 Private ingestion values

The following values are private to the configuration-ingestion pipeline:

- the filesystem adapter and open descriptor;
- raw configuration bytes and content handles;
- the parser instance and raw JSON tree;
- unvalidated strings, arrays, maps, numbers, paths, and IDs;
- partial validation evidence; and
- any candidate value produced before its complete prerequisites pass.

Private values may move only between nodes through their declared versioned
data keys. They are never returned through a public service method, stored in
a global singleton, written as a persistent cache, logged as content, or
supplied to a model.

### 7.2 Private compiler-chain handoff

The governing action catalogue makes `ValidateEngineConfigSchemaAction`
produce one complete schema-valid configuration value. That value, together
with its general validation evidence, is a private compiler-chain aggregate;
it is not an ordinary service API or an operational policy.

Only an owning boundary whose accepted action-catalogue input explicitly names
the complete aggregate may receive it. A node cannot widen access merely by
declaring the private key in its own `NodeContract`; the pipeline compiler must
also match that declaration to the compiler-locked action descriptor. Actions
such as one-reference, one-limit, one-invariant, or one-root validators receive
only their exact narrow private candidate and evidence keys.

The aggregate and all narrow private candidates travel only in runner-owned
immutable envelopes, cannot be fetched through a dynamic string/name lookup,
and must not be re-exported to an ordinary operational service. If an accepted
catalogue action does not yet own an aggregate-to-member/section handoff, that
one-responsibility producer contract must be accepted before implementation; a
facade, orchestrator, or consumer cannot perform the projection implicitly.

#### Required completed-ingestion seal

A projection must not become runnable immediately after schema validation.
Every projection needs one typed prerequisite proving that the complete
configuration-ingestion contract for the same capture has finished. This
feature therefore proposes one private seal; it must be accepted into the
governing action, type, obligation, and data-key registries before
implementation:

| Data key | Closed value | Visibility |
| --- | --- | --- |
| `engine.config.ingestion-seal.candidate@1` | `EngineConfigIngestionSealCandidate`: the governing bootstrap-attempt identity, exact configuration/project-root identity, stable capture provenance, schema contract/version evidence, complete registered validation-obligation-manifest identity/evidence, and validated `BootstrapRootRegistry` identity/evidence. It contains no configuration aggregate or member. | Private configuration-ingestion graph. |
| `engine.config.ingestion-seal@1` | `SealedEngineConfigIngestion`: the validated identity-and-completeness join for that exact candidate. It grants no filesystem or operational capability. | Private projection actions only. |
| `engine.config.ingestion-seal.evidence@1` | `EngineConfigIngestionSealEvidence`: total obligation coverage and exact same-attempt/capture/root/config/registry join under `engine-config-ingestion-seal/v1`. | Private seal/projection validation actions only. Specialized compilers receive only their narrow projection evidence. |

The proposed seal actions are:

| Action | Requires | Produces | Single responsibility |
| --- | --- | --- | --- |
| `BuildEngineConfigIngestionSealAction` | the exact discovery/root result, accepted capture provenance, schema-result identity/evidence for that capture, the governing bootstrap-attempt identity, the complete registered validation-obligation manifest and its individual evidence, and the validated root registry/evidence | `engine.config.ingestion-seal.candidate@1` | Assemble only the already produced identities/evidence into one candidate without receiving or copying the configuration aggregate; perform no I/O, parsing, rule validation, projection, policy compilation, or successor selection. |
| `ValidateEngineConfigIngestionSealAction` | the candidate, every authoritative input used to build it, and the compiler-locked obligation/contract registries | `engine.config.ingestion-seal@1` and `engine.config.ingestion-seal.evidence@1` | Prove exact identity joins and exactly one passing evidence item for every manifest obligation; do not recompute applicability or any reference, limit, invariant, path, root, or schema rule. |

Both actions are pure and capability-free. The pipeline compiler permits
exactly one registered producer of the candidate and one registered producer
of the validated seal. Every consumer projection requires the validated seal,
so Section 6.3 cannot reorder projection ahead of a validation or root-registry
obligation. A mismatch or incomplete obligation set rejects bootstrap; the
seal cannot select another file, synthesize evidence, or reuse a prior
invocation's value.

The seal type and runner ownership rules prevent mutable aliases by
construction. That property is enforced through Zig types, architecture
checks, and allocator/lifetime tests; the pure seal validator does not attempt
runtime pointer-alias proof. Section 4.5 records the missing governing capture
result and seal contracts that block implementation until accepted.

### 7.3 Runner-delivered consumer values

`SDDToolKitReader` exposes no direct getter to ordinary services. After the
private compiler chain validates the required settings, the action that owns a
consumer's policy or capability publishes the narrow value under that
consumer's declared typed key for runner-mediated delivery. The composition
root only wires the producer and consumer contracts statically.

The delivery sequence is:

1. the composition root constructs the registered producer and consumer
   bindings for the compiler-registered child-node graph;
2. before that selected chain runs, the pipeline compiler proves that every
   producer output key/schema exactly satisfies its consumer's declared
   `requires` key and that the graph preserves capability boundaries;
3. the runner invokes the reader/schema/general-validation/root chain,
   validates/applies its private values, and then invokes the registered
   completed-ingestion-seal builder and validator;
4. the runner invokes each accepted projection or policy owner with only its
   declared private typed input, validates/applies the returned narrow value,
   and never lets the action choose its successor; and
5. when the runner invokes the consumer, it supplies a bounded const view of
   that immutable value from the in-memory `PipelineEnvelope`.

The consumer reads only that typed value during its invocation. It cannot ask
for another key, retain an alias beyond the invocation, access the private
whole-configuration key, or cause a file read. Repeated use throughout the
workflow is therefore an in-memory typed lookup performed by the runner, not
repeated configuration I/O or parsing.

| Consumer need | Permitted value | Explicitly withheld |
| --- | --- | --- |
| A configured root | The validated role-specific root capability or registry view required by the consumer's declared contract. | Raw path strings, unrelated roots, a filesystem adapter, and mutation authority. |
| A file-declared policy setting | A closed schema-valid projection delivered only to its named compiler; the compiler's final policy is a separate downstream product. | The complete schema-valid configuration, unrelated sibling fields, an unvalidated/default-substituted value, or treating projection and compiled policy as interchangeable. |
| A named route, reader, parser, validator, adapter, or platform policy | The resolved typed binding or registry entry required by the consumer. | The original string as authority, registry enumeration not required by the consumer, and nearest-match substitution. |
| A runtime operational service | Its final compiled policy/capability after all applicable composition and safety gates. | Any direct reader value and any means to reopen or reread the file. |

Representative handoffs are:

| Receiving subsystem | Permitted in-memory handoff | It never receives from the reader |
| --- | --- | --- |
| Logging-policy compiler | The reader supplies only `engine.config.logging@1` and its validation evidence. The compiler's output and bootstrap-authority assembly are downstream contracts, not F0001 products. | Raw `logs` JSON, unrelated settings, `featureId`, a feature specification root, destination or sink identity, `FeatureLogPolicy`, `FeatureLogBinding`, or a reader/filesystem handle. |
| Reference ingestion | The validated reference-root capability, reader bindings, exclusion policy, and bounded traversal/decoder limits it requires. | Any other configured root, model settings, or raw reference-policy object. |
| Model routing | The resolved route descriptor and selected validated profile binding for the requested route. | The complete `models` object, provider secrets, or a facility for selecting undeclared routes. |
| Workflow/review gates | Their validated workflow limits and review-policy fragment. | Execution, logging, reference, or model configuration. |
| Repository and path policy | The applicable environment declarations, role-specific roots, and compiled portability/path capabilities. | Unvalidated path strings or a mutation-capable filesystem port. |
| Execution | The final compiled command, sandbox, network, resource, and effect policy required for the authorized operation. | Raw command text, unrelated configuration, or any policy that has not passed post-composition safety validation. |

The value names above describe contract roles, not permission to invent ad hoc
keys. The formal type and compiler-owned data-key registries must define every
handoff before implementation.

#### Required logging projection contract

F0001 owns exactly one outbound logging seam: an exact, destination-free
projection of the already schema-valid `logs` member. It does not own the
logging-policy compiler or any runtime logging type.

These proposed private values make that seam explicit:

| Data key | Closed value | Visibility |
| --- | --- | --- |
| `engine.config.logging.candidate@1` | `LoggingConfigProjectionCandidate`: the exact schema-valid `/logs` member plus its completed-ingestion seal identity; the closed type has no sibling configuration field or operational value. | Private projection actions only. |
| `engine.config.logging@1` | `SchemaValidLoggingConfigProjection`: the validated declarative logging settings from the same completed-ingestion seal. It contains no canonicalized effective policy and no runtime authority. | Specialized logging-policy compiler only. |
| `engine.config.logging.evidence@1` | `LoggingConfigProjectionEvidence`: exact-member equality, schema version, and completed-ingestion-seal join evidence. | Projection validation and compiler input validation only. |

The proposed projection actions retain one responsibility each:

| Action | Requires | Produces | Single responsibility |
| --- | --- | --- | --- |
| `BuildLoggingConfigProjectionAction` | `engine.config@1`, `engine.config.ingestion-seal@1`, and its evidence | `engine.config.logging.candidate@1` | Select the exact typed `/logs` member from the private aggregate and bind the evidence-only seal identity; apply no default, alias mapping, canonicalization, policy rule, or path derivation. |
| `ValidateLoggingConfigProjectionAction` | the candidate, the same `engine.config@1`, sealed ingestion/evidence, and the compiler-locked `logging-config-projection/v1` contract | `engine.config.logging@1` and `engine.config.logging.evidence@1` | Prove exact source-member equality and seal identity; rely on the closed projection type for field shape and compile no logging policy. |

Both actions are pure and capability-free. The projection cannot be produced
from schema success alone: every registered general configuration reference,
limit, invariant, version, and root check applicable to that sealed ingestion
must be represented by one validated completion authority in the graph. Section 4.5
records the governing catalogue additions that must be accepted before these
proposed keys or actions can be implemented.

The closed runtime schema rejects `logFile`, `path`, `directory`,
`destination`, and equivalent aliases. A separately authorized offline
migration adapter may discard a reviewed legacy destination field while
producing a complete v1 document, but F0001 has no runtime compatibility path.

F0001 stops after the runner validates and applies the projection and its
evidence. Ownership then proceeds without a service call:

1. the specialized logging-policy compiler consumes only
   `engine.config.logging@1` and produces a validated compiled fragment under
   its own registered contract;
2. bootstrap-authority assembly incorporates the exact fragment, and the
   owning transaction alone persists an accepted `BootstrapAuthorityState`;
3. feature-policy and binding actions reconstruct and validate the
   authority-bound `FeatureLogPolicy` and `FeatureLogBinding`; and
4. [F0002 — LogService](F0002-LogService.md) consumes only those runtime values
   and the registry-owned event definitions.

No F0001 output is a destination, active threshold, sink, log record,
transition authorization, recovery decision, or continue/block result. Runtime
logging never receives `engine.config@1`, `engine.config.logging@1`, or a
reader capability.

Examples of narrow products include validated environment declarations,
route/profile bindings, reference-reader selections and traversal limits,
workflow limits, review requirements, repository-discovery limits, validation
settings, execution constraints, state settings, and the schema-valid logging
settings projection. These categories describe isolation boundaries; the
eventual formal schema, not the illustrative sample, defines their exact
fields. No configuration projection category includes a feature-log
destination.

Every consumer-facing value must:

- be produced by a named one-responsibility action already present in the
  governing catalogue or added through an explicitly accepted catalogue
  change before implementation;
- have a closed, versioned type and compiler-owned data key whose fields form
  the exact consumer allowlist;
- be immutable and bound to the active-invocation ingestion seal in which it is
  used;
- retain the configuration/project-root identity and validation evidence
  needed to prevent cross-project or cross-ingestion mixing;
- distinguish identifiers, limits, enums, path settings, and capabilities
  with typed values rather than raw strings;
- exclude fields whose validation or compilation has not completed; and
- be destroyed after its last declared bootstrap consumer; any longer-lived
  compiled product follows the downstream owner's separate lifetime contract.

The composition root statically wires the named producer and consumer, the
pipeline compiler validates their keys and contracts, and runtime values move
only through runner-validated envelopes. There is no `get(string)`, JSON
Pointer query, reflection-based settings map, whole-document public
pass-through, mutable update method, consumer-selected default, or generic
configuration capability. A new consumer need requires a narrow owning action
and type plus positive, negative, and architecture tests; a facade or
orchestrator cannot construct the projection itself.

### 7.4 Declarative settings are not effective policy

A schema-valid value from `.sddtoolkit.json` is validated declarative input,
not automatically executable authority. Its named downstream compiler applies
only the precedence, composition, evidence, and safety rules governing that
field. Toolchain-backed fields use the accepted merge rules and preset
inheritance; the direct logging projection follows its separate closed logging
compiler contract and is not silently merged through toolchain precedence.

An operational consumer must receive that compiled result whenever its
contract depends on effective policy. It must not consume the reader's
declarative projection as a shortcut. Engine safety invariants remain outside
the merge and always win.

## 8. Snapshot and change lifecycle

Bootstrap invokes this feature before every root workflow and every permitted
standalone stage invocation. One accepted capture feeds the closed ingestion
graph; it is not installed as a workflow-lifetime settings object.

Runner ownership follows declared last consumers:

- the descriptor, raw bytes, and parser tree are destroyed after their final
  read/parse/schema consumer;
- the schema-valid aggregate and individual validation candidates are destroyed
  after all accepted validation and projection/compiler consumers complete;
- the ingestion-seal candidate is destroyed after seal validation, and the
  validated seal/evidence are destroyed after the final projection/compiler
  join;
- each declarative projection is destroyed after its named downstream compiler
  has produced and validated the separately owned compiled value; and
- the validated `BootstrapRootRegistry`, accepted
  `BootstrapAuthorityState`, and consumer-specific compiled policies or
  capabilities may remain available only under those downstream owners'
  contracts.

Accordingly, F0001 owns no complete configuration object after bootstrap
compilation, no workflow-lifetime cache, and no runtime settings lookup. Later
stages, tasks, retries, and services reuse their immutable registries,
authorities, policies, and capabilities without reopening or reparsing the
file. Each node receives only its declared bounded const view and retains no
alias after invocation.

An external mid-invocation edit cannot mutate already accepted downstream
values. A later command invocation performs exact discovery, capture,
validation, projection, and compilation again. Change comparison, adoption,
invalidation, persistence, policy transition, and administrative migration are
owned by bootstrap-authority/state and operational feature contracts; F0001
does not classify or activate a changed value.

Terminal success, `NeedsUser`/command-ending pause, rejection, failure,
cancellation, or process shutdown releases every value still in runner
ownership exactly once; values whose last consumer ran earlier are already
gone. An early discovery/read/parse/validation branch that never produced an
accepted snapshot releases only the intermediates it actually created. A
paused workflow that resumes in a new process or command invocation reloads
and revalidates the root file; no pointer, alias, serialized snapshot, or
reader-owned cache is reused across invocations.

A later invocation discovers and reads the file again. If validated current
configuration or derived bootstrap authority differs from the target workflow
feature's separately owned persisted bootstrap-authority binding, the existing
bootstrap-authority comparison, classification, rework, refresh, invalidation,
or administrative-migration contract owns the response. The reader does not
decide that a change is safe, advance a workflow pointer, or persist a
successor.

Direct typed value comparison, not a content fingerprint, establishes whether
authority is unchanged. Project-root, configured artifact-layout,
workflow-contract, serializer, review-visible renderer, or unsupported schema
changes remain administrative migration concerns and cannot be hot-swapped by
the reader.

This lifecycle optimizes repeated access by eliminating configuration I/O,
JSON parsing, and general configuration validation from stage/task hot paths,
while keeping freshness explicit at the next invocation boundary.

## 9. Failure and diagnostic behavior

### 9.1 Failure classes

| Phase | Representative rejection |
| --- | --- |
| Discovery | No exact file, parent-walk ceiling exceeded, invalid invocation directory, alias, symlink, special node, wrong case/name, or inaccessible ancestor. |
| Read | Open/read failure, non-regular resource, byte/resource ceiling exceeded, incomplete read, or resource identity/extent change. |
| Parse | Malformed JSON, duplicate member, invalid encoding, trailing content, or parser limit exceeded. |
| Schema/version | Unsupported version, missing field, unknown field, wrong type, invalid closed variant, or duplicate identity. |
| Reference/limit/invariant | Unknown registry reference, unsafe limit, forbidden v1 option, conflicting setting, or attempted safety weakening. |
| Configured roots | Absolute or escaping path, alias/symlink escape, portability failure, wrong role/type, duplicate root, illegal overlap, or a key set other than the exact seven. |
| Ingestion seal | Missing or duplicate producer, incomplete obligation evidence, or mismatched root/resource/config/registry/invocation identity. |
| Projection | Missing evidence, mixed ingestion/project identity, altered source member, incompatible projection version, or incomplete prerequisite chain. |

Every rejection produces a typed non-success outcome and stable diagnostic
data. The implementation's closed diagnostic registry must assign exact codes;
this document does not invent codes that the governing design has not yet
fixed. Diagnostics use bounded safe fields and source locations and never
include the complete raw document, credentials, secret values, or unrelated
settings.

### 9.2 Fail-closed rules

On any failure:

- the runner applies no consumer projection from the failed snapshot;
- no older, parent, sample, default, or partial configuration is substituted;
- no LLM call or LLM repair attempt occurs;
- no workflow definition, preset, principle, reference, repository, or project
  artifact is read because of the rejected configuration;
- no feature directory, durable state, log sink, or persistent cache is created
  by this feature;
- all descriptors, buffers, parser allocations, and candidate projections are
  released; and
- bootstrap returns the typed failure to the interface boundary.

For every reader failure, reporting is limited to the engine's bounded,
content-free process/emergency reporting boundary available before bootstrap.
The reader does not resolve, create, load, recover, or select a feature-log
destination, sink, policy, or binding. Any later use of an already validated
F0002 runtime sink is governed entirely by F0002's startup contract and cannot
change the reader outcome. A configuration failure must never create a
feature, adopt a policy, or introduce a persistent fallback merely to record
its own diagnostic.

## 10. Security, privacy, and determinism

The feature enforces these constraints:

- only discovery, byte-read, and configured-root observation/resolution
  actions receive the responsibility-specific read-only filesystem or path
  operations needed to produce their declared candidates and evidence;
- parser, schema/reference/limit/invariant validators, pure configured-root
  validators, and registry-assembly actions receive immutable data rather than
  filesystem capability;
- no action receives model, process, network, command, state-transition,
  transaction, logger, or child-node execution capability for this feature;
- reader and logging-projection actions receive no `featureId`,
  `WorkflowArtifactRegistry`, active-feature-directory capability, log-path
  resolver, log destination/sink capability, `FeatureLogBinding`, stream lock,
  or logging filesystem adapter;
- no model sees configuration bytes, internal absolute paths, credentials,
  provider settings, or configuration projections;
- canonical absolute locations stay inside the engine; persistent and
  model-facing paths remain normalized repository-relative values;
- no raw path string becomes an actionable root without root resolution and
  validation;
- the only configuration influence on persistent log placement is the
  validated `paths.specs` base; every feature, run, binding, stream, and segment
  descendant is fixed and derived by owners outside this feature;
- no-follow checks and stable resource identity prevent symlink and
  replacement races from silently selecting different bytes;
- engine hard bounds protect discovery, reading, parsing, validation, and
  projection before project-controlled limits are trusted;
- property order and insignificant JSON whitespace do not change the accepted
  typed projection;
- unknown or duplicate members never gain last-write-wins semantics;
- diagnostics are deterministically ordered under the common diagnostic
  contract; and
- cleanup is deterministic on success, rejection, cancellation, timeout, and
  unexpected operational failure.

## 11. Acceptance criteria

An implementation satisfies this feature only when all of the following are
true:

1. The only discovery input is a trusted invocation working directory plus
   engine-owned bounds; a caller cannot supply a configuration path or a
   different project root.
2. Discovery walks canonical ancestors in fixed nearest-first order, accepts
   only exact `.sddtoolkit.json`, and binds its containing directory as the
   canonical project root.
3. When a nested project and an ancestor both contain valid exact files, the
   first exact nested-project entry selects the nested project without merging
   the ancestor document.
4. Missing exact files, aliases, case variants, symlinks, special nodes, and
   parent-walk ceiling breaches reject bootstrap; an invalid nearer exact
   entry never falls through to a farther ancestor.
5. The engine never searches `.specify/`, `design/examples/`, the SDDE source
   tree, packaged assets, or another filename as runtime configuration.
6. The selected resource is read completely through its exact bounded
   no-follow descriptor; short reads, identity/extent changes, and hard-limit
   breaches cannot produce a snapshot.
7. Discovery, reading, parsing, schema validation, one-reference validation,
   one-limit validation, one-invariant validation, one configured-path
   relation, one root resolution, one root validation, registry-ID building,
   registry assembly, and registry validation remain separate actions under
   the common node contract.
8. No action invokes another action or orchestrator, and no orchestrator gains
   filesystem, parser, or validation capability.
9. JSON parsing rejects malformed input, invalid encoding, trailing content,
   duplicate members, and parser-limit breaches before schema validation.
10. The supported formal schema is closed at policy-bearing levels and rejects
    an unsupported configuration-schema version, unknown fields, missing
    required fields, invalid variants, and duplicate identities.
11. Every required registry-version binding, named reference, numeric limit,
    and cross-field invariant is validated by its owning action before the
    runner can apply the corresponding consumer projection.
12. `paths` contains exactly `specs`, `references`, `specsArchive`,
    `workflows`, `toolchainPreset`, `principles`, and `templates` exactly once.
13. All configured roots are normalized, contained, representable, correctly
    capability-typed, and pairwise separate, with only `specsArchive` beneath
    `specs` permitted as a configured-root nesting exception.
14. Engine-owned workflow `features/` and `transactions/` paths,
    `<paths.specs>/<featureId>/logs/`, and every other fixed child are derived
    outside the file schema and cannot be overridden. Only the validated
    `paths.specs` base comes from configuration; the reader cannot accept or
    return a log child path or filename.
15. The ordinary four-stage runtime receives no read capability for
    `paths.templates`.
16. Raw bytes, raw JSON, unvalidated values, descriptors, adapters, and partial
    evidence remain private to the ingestion chain and are released on every
    terminal branch.
17. Outside the explicitly private configuration/compiler chain, each consumer
    receives only a closed, versioned, immutable value with the exact field
    allowlist, identity, and evidence declared by its named owning action and
    `NodeContract`; no unneeded sibling field, generic lookup, mutable map, or
    service locator is available.
18. An operational service cannot consume a declarative setting where its
    contract requires compiled policy or a validated capability.
19. Every projection in one command run requires the same validated
    completed-ingestion seal and project-root identity. The schema-valid
    aggregate and seal values are released after their last bootstrap
    consumers; no whole-configuration object remains available to stages,
    tasks, or operational services.
20. Any failure publishes no partial result, consumes no model attempt, and
    occurs before workflow side effects or downstream authority loading.
21. Configuration changes follow the existing typed bootstrap-authority route
    without a content fingerprint or reader-owned persistent cache.
22. Equal complete normalized configuration, location/resource provenance,
    obligation registries, and authority inputs yield equal typed projections
    and deterministically ordered diagnostics.
23. Architecture tests prevent every reader action and graph from importing or
    accepting project-write, mutation-filesystem, transaction, command,
    writable-overlay, logger, or cache-writer ports; they also prevent
    filesystem/parser capability leaks, raw-config exposure, generic setting
    access, cross-consumer projection access, and every feature, artifact-path,
    log-policy, binding, sink, record, or logging-control input/output.
24. A packaged native executable proves the same behavior in a clean temporary
    project without the SDDE source tree, development examples, Zig toolchain,
    build cache, or unpackaged assets.
25. Filesystem-spy tests prove that success and every failure branch invoke no
    create, write, truncate, append, replace, rename, move, delete, permission,
    ownership, writable-overlay, transaction, or persistent-cache operation
    and leave configuration/project content, topology, permissions, and
    ownership unchanged.
26. Node-call tests prove discovery failure invokes read/parse zero/zero times,
    read failure invokes them one/zero times, parse failure invokes them
    one/one times, and successful bootstrap invokes them one/one times, with
    zero consumer-triggered configuration filesystem operations later in the
    workflow.
27. Lifetime tests prove every descriptor, raw/parser value, schema aggregate,
    validation candidate, ingestion-seal value, and projection is released
    exactly once after its last declared consumer on every terminal branch.
    Accepted downstream registries and compiled authorities remain usable
    without retaining or reconstructing the whole configuration. The next
    invocation performs a fresh load and validation.
28. `BuildEngineConfigIngestionSealAction` and
    `ValidateEngineConfigIngestionSealAction` are the only registered
    producers of the seal candidate and validated seal. Their contracts are
    pure and capability-free, and every projection has the seal as an explicit
    evidence dependency while consuming the private schema-valid aggregate
    separately through its accepted projection contract.
29. The validated evidence-only seal joins the governing bootstrap-attempt
    identity, exact configuration location/project root, accepted capture
    provenance, schema contract/version evidence, complete registered
    validation-obligation-manifest evidence, and validated
    `BootstrapRootRegistry`. It carries no configuration aggregate or member.
    Missing, duplicate, stale, cross-project, cross-resource, cross-attempt, or
    unaccounted evidence fails closed.
30. `BuildLoggingConfigProjectionAction` and
    `ValidateLoggingConfigProjectionAction` are the only producers of the
    Section 7.3 logging keys. The projection is exact and schema-valid but
    declarative; its closed type structurally excludes every non-logging
    sibling, compiled policy, feature/run/stream/binding/segment identity,
    path/destination, sink, and filesystem capability.
31. F0001 ownership ends at the accepted logging projection and evidence.
    Policy canonicalization/validation, compiled-fragment persistence,
    workflow-artifact path derivation, feature-policy/binding construction,
    event processing, sink lifecycle, recovery, retention, transition, and
    logging-failure control are neither implemented nor verified here.
32. Before criteria 28-31 can be implemented, every Section 4.5 prerequisite
    is accepted in the governing action/type/data-key registries. Architecture
    tests reject a feature-local workaround, hidden order dependency,
    recomputed provenance, whole-config widening, or duplicate log-level
    canonicalization.

## 12. Verification plan

### 12.1 Discovery and read tests

- exact file in the invocation directory;
- exact file in the nearest parent;
- nested and ancestor project files, proving nearest-first selection;
- missing file, wrong case, alias, symlink, directory, and special node,
  including an invalid nearer exact entry above a valid farther entry;
- parent-walk ceiling and filesystem adapter failure;
- bounded complete read, zero/short read, oversized input, cancellation, and
  timeout;
- read/parse node-call matrices of zero/zero after discovery failure,
  one/zero after read failure, and one/one after parse/schema failure or
  successful bootstrap;
- replacement, identity change, and size change during capture;
- descriptor and allocation cleanup on every branch;
- explicit absence of every forbidden fallback;
- a filesystem spy that rejects any mutation method on success, rejection,
  cancellation, timeout, and unexpected failure; and
- before/after proof that configuration/project content, directory topology,
  permissions, and ownership all remain unchanged.

### 12.2 Parse, schema, and registered-version tests

- valid JSON with reordered members and insignificant whitespace;
- malformed JSON, invalid string encoding, trailing content, and duplicate
  members;
- unknown and missing fields at every closed policy-bearing level;
- wrong scalar, collection, and closed-union variants;
- unsupported schema, route-registry, and renderer-contract versions;
- duplicate IDs and unresolved named references;
- absent, zero, negative, and over-hard-maximum limits where applicable;
- every registered cross-field invariant in both accepted and rejected forms;
- `references.followSymlinks: true`, `state.useFingerprints: true`, and unsafe
  response-logging combinations;
- rejection of unknown logging destination fields such as `path`, `directory`,
  `destination`, or `logFile`; and
- proof that illustrative sample fields and legacy aliases are not silently
  accepted by the formal schema.

### 12.3 Root, seal, and projection tests

- the exact seven-key `paths` set, including missing, unknown, and duplicate
  keys;
- absolute, drive, UNC, URI, traversal, NUL, control-character, escaping, and
  aliased roots;
- case-fold, normalization, segment, full-path, and each illegal nesting
  collision, plus the sole accepted `specsArchive`-beneath-`specs` case;
- unary root tests proving `ValidateConfiguredBaseRootAction` consumes only
  the externally validated active-workspace policy plus compiler-locked pre-
  preset root limits/rules and cannot compare another root or resolve target-
  platform policy;
- pairwise tests proving the F0001 binding of
  `ValidateEnginePathPolicyAction` owns one configured-root relation, cannot
  resolve or revalidate a root, and does not narrow the shared action's other
  registered relation bindings;
- registry tests proving exact role/evidence coverage without recomputing unary
  or pairwise policy;
- derived-child override attempts, correct access classes, and proof that
  templates remain inaccessible;
- compiler-chain input-width tests proving one-reference, one-limit,
  one-invariant, and one-root actions cannot access the complete aggregate and
  only accepted catalogue owners can declare its private key;
- pipeline-compiler rejection of zero, duplicate, or unregistered producers for
  the ingestion-seal candidate, validated seal, or seal evidence;
- exact seal joins for the governing bootstrap-attempt identity,
  configuration location, canonical root, capture provenance, schema contract/
  version evidence, registered obligation-manifest identity/evidence, and
  validated root registry, including rejection of missing, duplicate, stale,
  altered, cross-project, cross-resource, and cross-attempt members;
- evidence-only seal tests proving it cannot represent the schema-valid
  aggregate or any configuration member and every projection builder requires
  its separately declared private aggregate input;
- a reordering test proving no projection is placeable before every applicable
  general-validation and root-registry obligation is represented by the seal;
- lifetime/architecture tests proving closed ownership prevents borrowed
  mutable aliases and every candidate/seal/evidence value is released exactly
  once after its last consumer;
- one positive and one negative fixture for every consumer projection,
  including version, identity, evidence, and declared-field enforcement;
- exact `/logs` selection by `BuildLoggingConfigProjectionAction` and
  rejection by `ValidateLoggingConfigProjectionAction` of altered members,
  wrong seals, wrong versions, or cross-ingestion candidates;
- compile-time field-isolation proof that the logging projection cannot
  represent any non-logging sibling, compiled policy, feature/run/binding,
  path/destination, sink, or filesystem capability;
- architecture proof that projection actions remain pure and capability-free,
  the specialized compiler can consume exactly the projection/evidence, and
  runtime feature logging cannot consume a reader/private/projection/transient
  compiler key; and
- compile-time rejection of generic getters, raw JSON exposure, mutable
  settings, undeclared projection access, and every mutation-capable
  port/import.

### 12.4 Integration and packaging tests

With fake filesystem, parser, portability-policy, and registry ports, the
complete reader graph must cover valid load, every failure phase, cancellation,
and last-consumer cleanup without a model gateway or project mutation.

A multi-stage, multi-task fake workflow must invoke discovery/capture/parsing
once during bootstrap and produce zero consumer-triggered configuration
filesystem calls afterward. Allocation tracking must prove the complete
schema-valid aggregate and ingestion-seal values are gone after their last
projection/compiler consumers, while the separately owned root registry,
accepted bootstrap authority, and narrow compiled values remain sufficient for
later nodes. Early failures release only the intermediates they constructed.

An external test actor must replace the root file after bootstrap. Already
accepted downstream authorities remain unchanged without a watch/reload; the
next command invocation must discover, read, validate, seal, and project the
new content before the bootstrap-authority owner classifies it.

End-to-end temporary-project tests must prove that workflow, preset, principle,
reference, repository, logging-policy compilation, and model-route work remain
unreachable until reader success and the completed-ingestion seal. Each
consumer receives only its declared projection. One shared boundary-contract
test proves the specialized logging compiler accepts exactly F0001's validated
projection/evidence, while F0002 accepts only persisted-authority-derived
`FeatureLogPolicy` and `FeatureLogBinding` and causes F0001 to perform zero
access beneath any derived feature-log collection. F0002 owns all further
binding, sink, recovery, transition, and multi-feature assertions.

The release executable must repeat exact-root discovery, last-consumer cleanup,
and no-fallback tests from a clean temporary directory with no access to
repository examples, development-only assets, the Zig toolchain, or a build
cache. It must create no persistent reader cache.

## 13. Governing prerequisites and deferred choices

### 13.1 Required governing decisions

The capture-provenance output, capture-bound schema-result identity/evidence,
bootstrap-attempt identity owner, complete validation-obligation-manifest
owner/applicability rule, completed-ingestion seal/actions/data keys,
projection actions/types/data keys, and log-level canonicalizer/policy-
validator and root-registry-validator ownership resolutions in Section 4.5
are governing contract decisions. They are not implementation details and
cannot be selected locally. F0001's proposed projection integration remains
blocked until those amendments are explicitly accepted in the engine action,
type, obligation, and data-key registries.

### 13.2 Deferred implementation choices

The governing design has not yet fixed:

- the formal schema file location, schema URI, and exact supported version
  identifiers;
- the concrete parent-walk, configuration-byte, parser-time, and parser-memory
  hard-limit values and IDs;
- the complete stable diagnostic-code registry for each reader failure;
- the exact required, optional, or create-later existence policy for every one
  of the seven configured root roles;
- any non-logging aggregate-to-member/section projection action contracts not
  already present in the accepted bootstrap/configuration catalogue;
- the exact compiler-owned type and data-key names for each non-logging narrow
  consumer handoff; and
- the concrete Zig module layout and internal dispatch representation.

Implementation may decide these only within the governing design and accepted
project decisions. None may introduce a fallback, weaken a closed schema or
hard bound, merge action responsibilities, expose raw configuration, grant a
new capability, or treat an illustrative sample as runtime authority.

## 14. Traceability

| Feature concern | Governing design authority |
| --- | --- |
| Exact discovery, closed configuration, validation, and precedence | Sections 9.1-9.3 |
| One-responsibility action and orchestrator boundaries | Sections 3.3, 5-6, and 13.1 |
| Strict read-only capability and filesystem behavior | Sections 5-6, 13.1, and 25-26 |
| Runner-owned immutable delivery and last-consumer cleanup | Sections 6 and 15 |
| Completed-ingestion identity and projection isolation | Sections 5-6, 9, and 15; proposed prerequisite in Section 4.5 of this feature |
| Schema-valid logging projection and separation from runtime feature logging | Sections 6, 9.1, 13.1, 13.9, 15, 26.5, and 27; F0002 |
| Bootstrap-before-work and no fallback | Sections 15 and 30, Increment 1 |
| Configured-root roles and path safety | Sections 9.1-9.2, 11, 25-26, and `design/paths.md` |
| Immutable authority and configuration-change routing | Sections 9.4 and 24 |
| Reader, architecture, end-to-end, and package verification | Sections 28, 30, and acceptance criteria 2-7, 35, and 41 in Section 31 |
