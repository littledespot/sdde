# 9. Engine configuration

Part of the [proposed design](../design.md#9-engine-configuration). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

- `design/schemas/sddtoolkit-config.schema.json` defines the current reader-facing JSON
  contract, and `design/examples/.sddtoolkit.json` is one accepted instance.
- The closed top-level members are `logs`, `models`, and `paths`.
- Neither file is a runtime default, packaged asset, search location, or fallback.
- Bootstrap captures and canonicalizes the native executable's invocation working directory once
  and uses it as the project root.
- It resolves only the exact `<projectRoot>/.sddtoolkit.json`; it does not search an ancestor or
  descendant.
- If that exact file cannot be safely and completely read, bootstrap returns
  `ENGINE_CONFIG_READ_ERROR`.
- If its bytes cannot be decoded as the exact closed contract, bootstrap returns
  `ENGINE_CONFIG_PARSE_ERROR`.
- Either terminates with a nonzero exit before any workflow node, model call, feature log, or
  project write.
- These are the only public engine-configuration reader codes.

They are the only codes owned by F0001's engine-config reader. The separately
accepted provider-catalogue boundary owns
`LLM_PROVIDER_CONFIG_READ_ERROR`, `LLM_PROVIDER_CONFIG_PARSE_ERROR`,
`LLM_PROVIDER_REGISTRY_INVALID`, and
`LLM_PROVIDER_MODEL_BINDING_INVALID`; those codes cannot be substituted for an
F0001 failure or vice versa.

- F0001 owns one read and closed structural decoding into an immutable `SDDToolKitConfig`.
- It does not turn decoded strings into operational policy.
- Each section-owning compiler queries only its applicable typed field and owns that section's
  semantic validation.
- The `logs` object follows F0001's closed structure; F0002 owns its semantics.
- The companion samples define no alternate accepted members.

The runner owns the complete immutable value and returns one
`SDDToolKitConfigService` through the typed bootstrap result. A consumer queries
the applicable typed field directly. No configuration key, section key, copied
projection, generic string lookup, cache, or second configuration authority
exists.

- The two model configuration sources have distinct authority.
- The `.sddproviders.json` document at `paths.providers` is the bounded catalogue of configured
  provider/model instances.
- The `models.slots` map in `.sddtoolkit.json` selects the models allowed for this repository:
  every slot's exact case-sensitive `(provider, model)` tuple must resolve to exactly one entry
  in the completely validated provider catalogue.
- The selected tuple set may be equal to or a subset of the catalogue tuple set, never a
  superset.
- Catalogue entries not referenced by any slot are valid but are not repository-authorized or
  callable merely because they exist.
- Neither source supplies an implicit default, nearest match, or fallback.
- The validated repository model allowlist is the sole join authority: it stores slot identity,
  the exact referenced catalogue-entry identity, and validated slot options, but does not copy
  provider configuration or model-contract facts from the catalogue.
- The subset invariant compares distinct `(provider, model)` tuples, not slot count; multiple
  named slots may reference the same catalogue entry.
- A model-capable engine invocation captures the provider document exactly once.
- The validated registry/allowlist derived from that capture are immutable until the invocation
  ends; the untrusted bytes may be destroyed after preparation.
- The engine does not stat, reopen, reread, refresh, hot-reload, monitor, retain a last-known
  registry, or use a cross-invocation registry cache.
- A filesystem change can affect only a new invocation.

### 9.1 Required configuration shape

- For the bounded F0001 reader increment, the current closed shape is the formal [JSON
  Schema](../schemas/sddtoolkit-config.schema.json), the repository example, and the typed contract
  in [F0001 — SDDToolKitConfigService](../features/F0001-SDDToolKitConfigService.md).
- The root has exactly `logs`, `models`, and `paths`; fixed records reject missing, duplicate,
  and unknown members.
- `models.slots` is the one keyed collection and each value has the closed slot shape.
- The `logs` object contains exactly the F0002 threshold, optional console-mirror boolean, and
  closed prompt-capture selector list.
- File logging is mandatory and has no configuration switch.
- The delimiter, timestamp, size, retention, flush, redaction, failure, prompt-size, emergency,
  and lock policy is compiler-owned.
- Configuration has no version discriminator or compatibility reader; contract changes update
  this single closed schema and all consumers together.

[View the current engine configuration shape](../code.md#engine-configuration).

The closed `paths` object has exactly eight required keys: seven directory
roots and one provider-document file path. A missing or unknown key blocks
bootstrap:

| Key | Runtime contract |
| --- | --- |
| `specs` | Feature-facing specification views, controlled clarification forms, generated plan/task views, and feature event/prompt logs. Feature directories remain `<paths.specs>/<featureId>/`. |
| `references` | The sole configured base beneath which mandatory reference selectors resolve. |
| `specsArchive` | Archived specification material. It is excluded from active feature discovery and is the one configurable root allowed to nest beneath another configured root, specifically beneath `paths.specs`. Archive mutation remains outside v1. |
| `workflows` | Project workflow authority. It contains an arbitrary bounded number of closed declarative workflow definitions plus the reserved engine-owned `features/` child. The initial definitions are `specify`, `plan`, `tasks`, and `implement`; future definitions use the same generic contract. |
| `toolchainPreset` | The direct root/registry of closed, validated preset packages from which the project toolchain layer may inherit. |
| `principles` | Project principles: the exact mechanical `<paths.principles>/toolchain.yaml` layer and semantic Markdown principle files. |
| `templates` | Inert `*.template.md` principle templates. The initial SDD workflows never import or copy them; only an explicit `sdde init` operation may copy them into `paths.principles`. |
| `providers` | Engine-read-only provider catalogue document. It is a normalized project-relative file path whose basename is exactly `.sddproviders.json`; bootstrap reserves it without reading it, and F0008 captures it exactly once only when the selected compiled workflow requires model binding or provider calls. That owned snapshot and its derived registry/allowlist remain immutable for the complete invocation; there is no active-run reread/refresh or retained fallback. Catalogue membership configures an instance but does not add it to the repository's allowed `models.slots` set. |

- Every configured location is taken solely from the decoded `PathsConfig` in the exact
  current-working-directory project-root `.sddtoolkit.json`, then separately normalized and
  validated by the path-policy owner before use.
- The engine never substitutes an ancestor, descendant, fixed provider filename, `.specify/`,
  source-example, or packaged-example fallback.
- Fixed descendants include `<paths.specs>/<featureId>/clarify/`,
  `<paths.specs>/<featureId>/logs/`, `<paths.workflows>/features/`, each feature's
  `<paths.workflows>/features/<featureId>/execution/final-validation-overlays/`.

- The workflow root is both declarative project authority and the owner of the `features/` state
  subtree.
- Bootstrap performs a bounded, fully accounted inventory: it validates the complete
  path-collision set, orders in-scope entries by normalized Unicode-scalar path, binds
  contiguous inventory-local ordinals, and records exactly one terminal account for every
  encountered entry.
- An encountered `features/` root entry is accounted for as reserved while its complete
  descendant subtree is excluded from definition traversal.

- Every definition retains its source inventory ordinal and supplies one validated
  project-authored `WorkflowId` plus one validated workflow logging shortcode.
- Both are unique in the registry.
- The registry has one generic bootstrap component ID and a bounded variable-size definition
  set; bootstrap does not require a fixed workflow name or count.
- An invocation must resolve its requested `WorkflowId` exactly once before workflow input
  parsing or execution.

- A definition contains only its version, registered capability-free invocation operation,
  registered generic operation references, compact closed parameters, declared workflow-owned
  resources, typed outcome transitions, and selected workflow policy profile.
- The workflow compiler validates graph structure, operation compatibility, transitions, gates,
  and the effective capability ceiling before producing an immutable executable graph.
- It rejects unknown operation contracts, invalid or duplicate identities, unhandled outcomes,
  forbidden transitions, or any attempted capability or gate weakening.
- The composition root binds registered operation implementations and adapters; the generic
  workflow-engine orchestrator selects the compiled graph and follows its typed transitions only
  through runner-owned child bindings, while the runner alone invokes the compiled operation
  nodes.
- Project workflow files are never executable scripts, infrastructure selectors, raw
  path/command sources, or operational capabilities.

- The selected workflow policy owns the sole workflow-global execution limit: a positive total
  model-token budget initialized afresh for each execution.
- It does not own an attempt, retry, repair, or per-action count.
- Every registered action or function that exposes a retry path instead requires an explicit
  bounded `retry-limit` parameter on that YAML operation instance.
- The compiler rejects a missing limit, a retry edge without registered monotonic accounting, or
  a cycle that can avoid the declared counter.
- No configuration file, provider, adapter, or runner supplies a retry default.

- The v1 definition media contract is fixed by [F0005 —
  WorkflowDefinitionRegistryService](../features/F0005-WorkflowDefinitionRegistryService.md) and
  the formal [workflow-definition v1 schema](../schemas/workflow-definition-v1.schema.json).
- Definitions are strict UTF-8 YAML 1.2 regular files discovered recursively by the exact
  case-sensitive `*.workflow.yaml` suffix outside the reserved root `features/` subtree.
- Each file contains one closed `schema: workflow/v1` mapping document; filenames never
  determine workflow identity.
- Only bounded regular resources explicitly declared by a definition are captured alongside it.
- Other encodings, YAML aliases or custom tags, executable includes, and compatibility readers
  are not supported in v1.

The `specify`, `plan`, `tasks`, and `implement` definitions are the initial SDD
suite. Their registered predecessor gates enforce their feature order even
though unrelated workflows are not placed into that sequence.

- Feature-scoped `WorkflowState` retains the sorted unique `WorkflowId` set whose compiled
  graphs have participated in its durable history.
- Before adopting a successor workflow registry, the change classifier directly compares the old
  and candidate graph's stable semantic authority for every bound ID.
- Source inventory ordinals, registry identity, and compilation/validation evidence are
  provenance and do not participate in that comparison.
- A missing or semantically changed bound graph requires the administrative migration route;
  adding, removing, or changing only an unbound definition is a compatible registry refresh.
- This is typed value comparison through the two registry states, not a fingerprint.

- Bootstrap compiles an immutable reserved-location registry with explicit access classes.
- Engine config, provider config, workflow-definition/state, reference,
  principles/preset/template, VCS, and dependency-cache locations are
  `engine_only`/`inaccessible` to project-file operations.
- A workflow may activate a resource beneath an authorized workflow-resource root only by
  declaring its bounded typed reference in YAML; the compiler captures it into immutable
  workflow authority before execution and never passes its raw path capability to a workflow
  operation or model.
- Merely reserving `paths.templates` activates nothing.
- The `paths.providers` capability grants only F0008's bounded no-follow read and does not
  activate a provider or expose bytes during root validation.
- Generated/build roots are `generated_read_only` by default: discovery may mint an
  engine-issued, read-only `FileRecord` for an existing generated input when the preset
  explicitly permits it, but a model cannot propose its raw path and no
  create/patch/replace/copy/delete operation can target it.
- A registered generator command may recreate declared ephemeral/generated output only inside
  its command savepoint; it does not turn that output into a model-writable file.
- Workflow/reference/state actions use their separate engine-artifact policy and publication
  authorizations; a language/framework layer cannot weaken the separation.

- Canonical feature state is always derived as `<paths.workflows>/features/`.
- Preset packages resolve only beneath `paths.toolchainPreset`, while the one project toolchain
  layer resolves only as `<paths.principles>/toolchain.yaml`; neither has another configurable
  or derived overlay root.
- All other engine-owned descendants are likewise derived from their owning configured root.
- Each environment names one or more registered target-platform/filesystem policy IDs, which
  supply normalization, case, reserved-name, segment-length, and repository-relative path
  limits.
- Bootstrap also detects the active workspace filesystem policy through a trusted adapter and
  adds it as a non-overridable member of the compiled portability policy.
- The host policy additionally supplies an absolute-path ceiling measured after joining the
  candidate to the canonical workspace/project root using its declared native encoding/count
  rule.
- All path creation/rename/copy/replace checks therefore use `configured target policies ∪
  active workspace policy`; a deployment-only target list can never omit host representability,
  host collision rules, or the actual absolute target length.

### 9.2 Configuration validation

- F0001 rejects a missing, unsafe, oversized, malformed, or structurally invalid document before
  any LLM call or workflow side effect.
- Structural acceptance grants no path, model, logging, command, state, or workflow authority.
- Each section owner validates its supplied typed view once before any value can influence an
  operation.

The logging-policy compiler rejects a structurally valid `logs` value before
any LLM call unless its level, console boolean, and unique prompt-capture
selector list form one valid F0002 policy. It injects every operational
constant, including the pipe-delimited dialect and column schemas; none is configurable.

Bootstrap and the current section-owning compilers additionally reject every
applicable current input below. When the remaining proposed extended
engine-policy fields are introduced, their compilers must
preserve the applicable rejections. Before any LLM call, bootstrap rejects
when:

- a workflow or declared workflow-resource schema version is unsupported;
- an unknown key appears in a closed schema;
- the `paths` object does not contain exactly `specs`, `references`, `specsArchive`, `workflows`, `toolchainPreset`, `principles`, `templates`, and `providers`;
- a configured location is absolute, escapes the workspace, overlaps a forbidden location, or conflicts with another configured location; the one configurable nesting exception is `paths.specsArchive` beneath `paths.specs`; `paths.providers` must have the exact `.sddproviders.json` basename and must not equal or nest with a configured directory root or `.sddtoolkit.json`; the archive subtree is excluded from active feature discovery; the derived engine-owned `features/` child beneath `paths.workflows` is validated against its fixed ownership tree rather than treated as a peer root;
- a workflow definition collides with reserved `features/`,
  any encountered definition is invalid or unaccounted, workflow IDs or logging
  shortcodes are duplicated, a referenced invocation/node/policy contract is
  unknown, graph transitions or outcomes are incomplete, or a definition
  attempts to provide executable code, select infrastructure, add a capability,
  weaken a gate, or bypass runner validation;
- when selected workflow setup requires the toolchain, `<paths.principles>/toolchain.yaml` is absent, is not a bounded no-follow regular file, fails its closed schema, or names a missing/incompatible preset inheritance closure;
- an `environments[].root` is absolute, escapes the canonical workspace, or resolves through an escaping symlink; every discovered project root and manifest must remain beneath its selected contained environment root;
- two environments have the same root or ambiguous equal-specificity roots;
- a named preset, model slot, workflow operation, workflow resource, exact
  `readerId@version`, target-platform/filesystem policy ID, validator, parser,
  or command adapter is missing;
- an environment's `targetPlatforms` set is empty, contains duplicates, or cannot be resolved completely before path-policy compilation;
- the active workspace filesystem policy cannot be detected/resolved, or any candidate collides/fails under that policy even though it passes the configured deployment targets;
- a request-origin operation omits its YAML-declared repository slot, prompt/guidance,
  result schema, supported controls, or outcome transitions; a named slot does not
  resolve through the validated repository allowlist; or an operation attempts
  to use an undeclared packaged/default resource; a consumer lacks the typed
  retained-request dependency or attempts to reselect its binding/resources;
- a numeric limit is negative, zero where prohibited, or above an engine safety maximum;
- `references.followSymlinks` is anything other than the required v1 constant `false`; followed reference symlinks are deliberately unsupported until a separate version defines containment, loop, depth, deduplication, and accounting semantics;
- a reference traversal/decoder limit (`maxEntries`, directory depth, source/decoded byte totals, blocks, pages, cells, decoder time/memory, or archive expansion limits when applicable) is absent or exceeds the engine hard maximum;
- a repository-discovery file/depth/time/memory limit is absent or exceeds the engine hard maximum;
- `promptCapture` is non-empty without a request/response direction, contains a
  duplicate/unknown selector, or attempts to override fixed redaction,
  retention, or size policy;
- `useFingerprints` is set to true in this design version;
- a hardened workflow disables required plan or task approval without an explicitly selected non-interactive policy profile;
- the post-composition effective merged preset policy conflicts with or weakens a compiler-locked path, command, capability, sandbox, network, resource, effect, or validator rule.

### 9.3 Precedence

Configuration and content authority are separate systems.

The root `.sddtoolkit.json` remains one closed document with no override or fallback
merge layer. [F0003 §3](../features/F0003-ToolChainService.md#3-closed-loading-and-publication-contract)
owns the implemented toolchain format: exact package references and stable union of
registered policy IDs. The broader field-level composition below remains proposed
policy design; it adds no fields to the implemented configuration or toolchain schemas.

The broader policy-composition proposal orders layers, from least to most specific:

1. engine defaults;
2. base language preset;
3. runtime preset;
4. framework preset;
5. build/test-tool preset;
6. the exact project toolchain layer from `<paths.principles>/toolchain.yaml`;
7. explicitly permitted CLI overrides.

Non-overridable engine safety invariants sit outside the merge and always win. Repository discovery supplies evidence; it is not a precedence layer. An `auto` field may be filled from unambiguous evidence, but discovered facts cannot silently overwrite explicit configuration.

Merge semantics must be declared per field:

- maps merge by stable key;
- commands replace atomically by command ID;
- extension sets may union;
- forbidden paths and locked validators only union and cannot be weakened;
- roots and naming rules replace by default;
- arrays never concatenate implicitly;
- an explicit merge directive is required for append, prepend, union, or remove;
- removing a locked rule is invalid.

Content authority is domain-specific:

- engine safety and mechanical environment facts cannot be overridden by references;
- the compulsory reference corpus, together with later authenticated specification edits and clarification answers, defines feature intent;
- authoritative reference conflicts block or create open questions—there is no last-file-wins behavior;
- the specification is the business-intent source for later stages;
- reference context carries supplementary implementation-facing obligations;
- the exact project `toolchain.yaml` principle supplies closed mechanical inheritance and typed override policy over the selected preset packages, while semantic Markdown project principles govern code and structural choices within the resulting real environment; neither grants an undeclared operational capability;
- generic prompt examples have the lowest authority.

### 9.4 Project-principle resolution

- The new engine calls this authority **principles**.
- It fulfils the role that constitution/memory material has in the basis workflow: overarching
  project policy and guidance for code, architecture, project structure, security, validation,
  observability, and user-interface work (`prompts/sdd-plan.md:70-85`;
  `prompts/sdd-implement.md:48-69`).
- Version-control workflow material remains out of scope.
- The configured root deliberately contains two separately typed lanes: the exact
  `toolchain.yaml` project principle is mechanical policy, while Markdown principle files are
  semantic guidance.

- The principle root is exactly `<projectRoot>/<paths.principles>`, resolved directly from the
  project-root `.sddtoolkit.json`.
- Its exact `toolchain.yaml` child is captured, parsed as YAML 1.2, validated through a closed
  versioned schema, and used to select/inherit from the preset packages beneath
  `paths.toolchainPreset`; it is never decoded, chunked, cited, or sent to a model as free-text
  principle prose.
- Every other accepted regular-file source in the root is normalized `*.md` semantic principle
  material.
- The source templates under `design/templates/` are design/init inputs only and are never a
  runtime fallback.
- Their filenames illustrate the initial category hints—`core`, `architecture`,
  `project-structure`, `security`, `validation`, `observability`, and `user-interface`—but a
  Markdown principle body may be arbitrary free text.

- The principle inventory nevertheless accounts for every encountered directory, regular file,
  link, and special node.
- Classification assigns the exact `toolchain.yaml` descriptor one mechanical-exclusion account,
  admits only validated normalized Markdown regular files to the semantic capture budget,
  accounts for directories without reading them, and blocks every other file or node.
- The mechanical member receives no semantic reservation, source ID, module, chunk, citation, or
  model-visible guidance; total inventory validation proves that separation rather than
  filtering the file before accounting.

- `paths.templates` is a distinct inert root containing `*.template.md` files.
- No bootstrap, `specify`, `plan`, `tasks`, or `implement` action reads, expands, or copies
  those files.
- Only an explicit `sdde init` operation may copy a template into `paths.principles` under a
  separately accepted init contract; `init` remains outside the initial SDD suite defined by
  this design.
- Once a copied file exists beneath `paths.principles` as Markdown, ordinary principle capture
  treats it exactly like any other semantic principle—its origin in `paths.templates` grants no
  special authority and no automatic placeholder expansion.

Resolution is explicit:

1. resolve `paths.principles` through the root-access policy, account for the separately captured exact `toolchain.yaml`, select only bounded no-follow normalized `*.md` regular files as semantic sources, reject every unclassified regular file and alias/case collision, and sort the Markdown sources by canonical filename;
2. classify a category hint from the normalized filename using the configured mapping; an unmatched filename receives the explicit `custom` hint rather than having its meaning guessed from its body;
3. decode bounded UTF-8 text and preserve exact source-byte and line spans; no front matter, heading, Markdown structure, template placeholder, or content schema is required;
4. split large files into deterministic transport chunks. A file with no headings or paragraph structure is still valid and receives a whole-file or fixed-window chunk;
5. select categories solely from the configured stage/environment/file-kind hint table and include every chunk from those files in stable source order; no model classifies, summarizes, ranks, or omits principle prose;
6. include the exact selected raw spans in plan, task, implementation, repair, and semantic-review guidance without truncation or a local size-fit gate; provider size errors follow the workflow's explicit outcome transitions;
7. validate only transport facts deterministically: configured root, containment, identity, filename-to-hint mapping, UTF-8, source-capture byte/count ceilings, stable spans, registry joins, and prompt-selection coverage;
8. treat content compliance or conflict as semantic judgment backed by exact principle citations and the plan/tasks user-review gates. If material ambiguity remains, create or retain a plan/task clarification rather than silently choosing a plausible interpretation.

- Semantic principle prose is never parsed or compiled into a deterministic validator, even when
  it resembles YAML, a table, a template, or a formal rule.
- The sole same-root exception is the exact `toolchain.yaml` path, which is never semantic prose
  and must pass the mechanical toolchain-layer schema.
- Machine-enforceable path, filename, command, dependency, coverage, and safety rules come only
  from that validated layer, its inherited presets, other separately configured schemas, and
  engine policy.
- A semantic principle cannot grant a read/write/command/network capability, weaken engine
  safety, change a canonical artifact path, or override a mechanically proven environment fact.
- When prose appears to conflict with those authorities, the mechanical boundary still holds and
  a cited semantic diagnostic asks for a project-level decision.

- The filename is a guide used by the engine, not a claim that the contents obey a schema.
- Category selection deliberately errs toward inclusion: `core` and `custom` are considered for
  all technical stages, while other category hints are selected by explicit configuration.
- The model never chooses which files to open and never sees an operational principle path—only
  registered IDs, category hints, raw bounded spans, and citations.

- Principles are captured once per command-run bootstrap, bound into `BootstrapAuthorityState`,
  and compared by direct typed metadata/raw-byte equality at every plan, tasks, implement and
  fresh clarification-rerun gate.
- They are not supplied to workflow operations that generate specification content because
  `spec.md` is business intent and principles must not invent missing product requirements.
- An updated principle can resolve `PNN` or `TNN` only through cited, current authority
  resolution; it cannot resolve an `SNN`.
- A changed registry invalidates the current plan and downstream task approvals, then requires
  the normal ordered regeneration and review path.
- No content fingerprint is used.

- Bootstrap authority is immutable and versioned.
- Compare current captured inputs with the authority bound by the selected workflow using direct
  typed metadata/raw-byte equality, without fingerprints.
- Equal authority reuses the current identity.
- Changed candidates remain execution-local until the complete owning workflow output, or the
  explicit clarification persistence exception, permits publication.
- Bootstrap does not publish an independent successor.

`ClassifyBootstrapAuthorityChangeAction` retains every changed component and
its typed impact; validation preserves all obligations and chooses the earliest
owner with dominance `administrative > reference ingestion > specification
contract > planning > runtime-only`.

| Change | Required route |
| --- | --- |
| Reference reader, decoder, source map, chunker, extraction/reconciliation contract or reference safety | Reingest references in Specify and invalidate affected descendants. |
| Specification schema, business boundary, passive-literal scanner or renderer/parser | Regenerate and revalidate Specify. |
| Toolchain, project mechanical layer, environment, portability, file-kind/path, parser, command, dependency, sandbox or capability policy | Return to Plan; reconcile previously published implementation when applicable under §24.5. |
| Semantic principles | Rebuild Plan's complete cited principle selection and invalidate affected plan/task approvals; do not change business requirements. |
| Compatible logging/model binding or unrelated workflow definition | Retain the semantic stage; apply the validated runtime change and any logging-transition obligation. Changes are compared by bound `WorkflowId`, not inventory position. |
| Project/artifact root, bound workflow identity/graph, serializer or unsupported schema/renderer change | Block with `BOOTSTRAP_ADMINISTRATIVE_MIGRATION_REQUIRED`; no implicit conversion, pointer advance or hot swap. |

- A planning-owned change discovered during Specify remains a distinct deferred planning
  obligation.
- It grants no planning authority and must be freshly captured, classified and validated before
  the first Plan model call.
- It cannot be relabelled unchanged.
- Runtime-only changes cannot suppress a simultaneous earlier-owner change.
- After an adopting route, the runner completes any required logging-policy transition before
  another normal event, model call or node.

These routes describe ownership and invalidation, not separate transactions.
There is no durable ID reservation, task-commit watermark or saved bootstrap
continuation (ADR 0009).

### 9.5 Configuration evolution

- This is a pre-release proof of concept with no deployed compatibility target.
- The reader-facing configuration has no version discriminator.
- Its single closed contract is edited in place, and every affected consumer and fixture changes
  together.
- A document containing `version`, `schemaVersion`, or any other obsolete member is rejected as
  unknown.
- F0001 does not infer, rename, discard, default, migrate, dual-read, or convert fields, and no
  runtime or offline compatibility path is supported.
