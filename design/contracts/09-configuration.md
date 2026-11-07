# 9. Engine configuration

Part of the [proposed design](../design.md#9-engine-configuration), as amended by the
[accepted ADRs](../design.md#32-accepted-and-deferred-implementation-choices).

- `design/schemas/sddtoolkit-config.schema.json` defines the current reader-facing JSON
  contract, and `design/examples/.sddtoolkit.json` is one accepted instance;
  [§9.1](#91-required-configuration-shape) lists its closed members.
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
- These are the only public engine-configuration reader codes. The separate
  provider-catalogue boundary owns `LLM_PROVIDER_CONFIG_READ_ERROR`,
  `LLM_PROVIDER_CONFIG_PARSE_ERROR`, `LLM_PROVIDER_REGISTRY_INVALID` and
  `LLM_PROVIDER_MODEL_BINDING_INVALID`; neither set substitutes for the other.

- F0001 owns one read and closed structural decoding into an immutable `SDDToolKitConfig`.
- It does not turn decoded strings into operational policy.
- Each section-owning compiler queries only its applicable typed field and owns that section's
  semantic validation.
- The `logs` object follows F0001's closed structure; F0002 owns its semantics.
- The companion samples define no alternate accepted members.
- [F0001 §4](../features/F0001-SDDToolKitConfigService.md#4-query-and-ownership-contract)
  owns the one immutable `SDDToolKitConfigService` and its typed-field queries; there is no
  configuration key lookup, copied projection, cache or second configuration authority.

- The provider catalogue at `paths.providers` (`.sddproviders.json`) is the second,
  separately owned model-configuration source.
  [F0006 §3](../features/F0006-LLMProviderInterface.md#3-exact-sddprovidersjson-contract)
  owns its closed shape, including each model's required `json` output selection and its
  closed per-provider `config` with `maxOutputTokens` and the required `requestTimeoutMs`
  deadline; [F0006 §5](../features/F0006-LLMProviderInterface.md#5-conditional-bootstrap-and-change-handling)
  owns its single immutable capture per model-capable invocation. Neither configuration
  document carries a credential
  ([ADR 0028](../decisions/0028-anthropic-messages-provider.md#anthropic-contract)).
- `models.slots` selects the models this repository may use.
  [F0006 §6](../features/F0006-LLMProviderInterface.md#6-providermodel-binding-and-workflow-token-accounting)
  owns the join: every slot's exact `(provider, model)` tuple resolves exactly once in the
  validated catalogue, the slot tuples equal or are a subset of the catalogue's, and an
  unreferenced catalogue entry gains no repository authority. Neither source supplies a
  default, nearest match or fallback.

### 9.1 Required configuration shape

- For the bounded F0001 reader increment, the current closed shape is the formal [JSON
  Schema](../schemas/sddtoolkit-config.schema.json), the repository example, and the typed contract
  in [F0001 — SDDToolKitConfigService](../features/F0001-SDDToolKitConfigService.md), which
  also owns each member's decode rejections.
- The root requires `logs`, `models`, `workflowTokenBudget`, `temperature`,
  `temperatureRunawayRetry` and `paths` and permits
  optional `validation` ([ADR 0021](../decisions/0021-optional-source-preservation-review.md));
  fixed records reject missing required, duplicate and unknown members. The removed
  `principles` section is an unknown member
  ([ADR 0015](../decisions/0015-specification-principle-review.md)).
- `workflowTokenBudget` is the total model tokens one workflow execution may use, an
  integer from 1 to 4,294,967,295 with no default
  ([ADR 0037](../decisions/0037-configured-workflow-token-budget.md)).
- `temperature` is the temperature every inference request sends, and
  `temperatureRunawayRetry` the one a runaway re-send sends
  ([ADR 0039](../decisions/0039-configured-temperatures-and-runaway-resend.md)). Each
  is a JSON number, zero or greater, with no default. Models whose registered contract
  takes no temperature omit it. The provider owns its accepted range.
- `models.slots` is a keyed collection; each model slot has the closed slot shape.
- A slot has no output-token allowance: the closed shape rejects `maxOutputTokens`
  ([ADR 0011](../decisions/0011-provider-owned-request-limits.md#no-output-token-allowance)).
- The `logs` object contains exactly the F0002 threshold and the required `console` boolean,
  which enables the optional console mirror.
- Under [ADR 0018](../decisions/0018-debug-model-exchange-logging.md), the threshold alone
  selects prompt capture: `debug` and `trace` capture complete request/response bodies,
  including reference and code bodies, and higher thresholds emit metadata only.
  Credentials remain redacted.
- File logging is mandatory and has no configuration switch.
- `validation.sourcePreservationCheck` is an optional boolean, disabled when
  omitted. It controls only the additional source-preservation review before
  generation; mandatory authority and publication validation remain required.
  The supplied Spec definition routes authorized candidate repairs through
  `models.slots.repair`. All statically referenced model slots must be
  configured even when the optional review is disabled; no slot fallback exists.
- The delimiter, timestamp, size, retention, flush, redaction, failure, prompt-size, emergency,
  and lock policy is compiler-owned.

[View the current engine configuration shape](../code.md#engine-configuration).

The closed `paths` object has exactly eight required keys: seven directory
roots and one provider-document file path. A missing or unknown key blocks
bootstrap:

| Key | Runtime contract |
| --- | --- |
| `specs` | Feature-facing specification views, controlled clarification forms, generated plan/task views, and feature event/prompt logs. Feature directories remain `<paths.specs>/<featureId>/`. |
| `references` | The sole configured base beneath which mandatory reference selectors resolve. |
| `specsArchive` | Archived specification material. It is excluded from active feature discovery and is the one configurable root allowed to nest beneath another configured root, specifically beneath `paths.specs`. Archive mutation remains outside v1. |
| `workflows` | Project workflow authority. It contains an arbitrary bounded number of closed declarative workflow definitions, their declared resources and the reserved engine-owned `features/` child. |
| `toolchainPreset` | The direct root/registry of closed, validated preset packages from which the project toolchain layer may inherit. |
| `principles` | Project principles: the exact mechanical `<paths.principles>/toolchain.yaml` layer and semantic Markdown principle files. |
| `templates` | Inert `*.template.md` principle templates. The initial SDD workflows never import or copy them; only an explicit `sdde init` operation may copy them into `paths.principles`. |
| `providers` | Engine-read-only provider catalogue document: a normalized project-relative file path whose basename is exactly `.sddproviders.json`. Bootstrap reserves it without reading it; F0008 captures it once, only when the selected compiled workflow requires model binding or provider calls. |

- Every configured location is taken solely from the decoded `PathsConfig` in the exact
  current-working-directory project-root `.sddtoolkit.json`, then separately normalized and
  validated by the path-policy owner before use.
- The engine never substitutes an ancestor, descendant, fixed provider filename, `.specify/`,
  source-example, or packaged-example fallback.
- Fixed descendants include `<paths.specs>/<featureId>/clarify/`,
  `<paths.specs>/<featureId>/logs/`, `<paths.workflows>/features/` and, for proposed
  Implement execution, each feature's
  `<paths.workflows>/features/<featureId>/execution/final-validation-overlays/` (§20); the
  engine derives these paths, which are not configuration fields.

- [F0005 — WorkflowDefinitionRegistryService](../features/F0005-WorkflowDefinitionRegistryService.md)
  owns the workflow root: its bounded, totally accounted inventory and reserved `features/`
  child, the closed v1 definition media and
  [schema](../schemas/workflow-definition-v1.schema.json) (including ADR 0041's on-hold
  `workflow/v2`), unique `WorkflowId`s and logging shortcodes, and compilation from registered
  operation contracts. Project workflow files are never executable scripts, infrastructure
  selectors, raw path/command sources, or operational capabilities.
- The sole workflow-global execution limit is the configuration's `workflowTokenBudget`,
  initialized afresh for each execution
  ([ADR 0037](../decisions/0037-configured-workflow-token-budget.md)). Workflow policy and
  compiled graphs don't carry it, and it is not an attempt, retry, repair, or per-action count.
- Every retry path instead requires an explicit bounded `retry-limit` on its YAML operation
  instance ([F0005 §3.3](../features/F0005-WorkflowDefinitionRegistryService.md#33-steps-parameters-resources-and-transitions));
  no configuration file, provider, adapter, or runner supplies a retry default. The one
  engine-owned re-send is
  [ADR 0039](../decisions/0039-configured-temperatures-and-runaway-resend.md)'s single
  re-send after a provider `output_limit` stop, outside `retry-limit`.

The Specify, Plan, Tasks and Implement definitions are the initial SDD suite; the
supplied Specify definition's `WorkflowId` is `spec-generation`. Their registered
predecessor gates enforce their feature order even though unrelated workflows are not
placed into that sequence.

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
any LLM call unless its level and console boolean form one valid F0002 policy.
It injects every operational
constant, including the pipe-delimited dialect and column schemas; none is configurable.

Bootstrap and the current section-owning compilers additionally reject every
applicable current input below. When the remaining proposed extended
engine-policy fields are introduced, their compilers must
preserve the applicable rejections. Before any LLM call, bootstrap rejects
when:

- a workflow or declared workflow-resource schema version is unsupported;
- an unknown key appears in a closed schema;
- the `paths` object does not contain exactly `specs`, `references`, `specsArchive`, `workflows`, `toolchainPreset`, `principles`, `templates`, and `providers`;
- a configured location has a non-ASCII path component ([ADR 0007](../decisions/0007-unicode-normalization.md)), is absolute, escapes the workspace, overlaps a forbidden location, or conflicts with another configured location; the one configurable nesting exception is `paths.specsArchive` beneath `paths.specs`; `paths.providers` must have the exact `.sddproviders.json` basename and must not equal or nest with a configured directory root or `.sddtoolkit.json`; the archive subtree is excluded from active feature discovery; the derived engine-owned `features/` child beneath `paths.workflows` is validated against its fixed ownership tree rather than treated as a peer root;
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
- an engine-owned numeric limit is negative, zero where prohibited, or above its engine safety maximum;
- a reference traversal/decoder limit (entry count, directory depth, source/decoded byte totals, blocks, pages, cells, decoder time/memory, or archive expansion limits when applicable) is absent or exceeds the engine hard maximum;
- a repository-discovery file/depth/time/memory limit is absent or exceeds the engine hard maximum;
- the removed `promptCapture` field is supplied, or logging input attempts to
  override fixed redaction, retention, or size policy;
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

Principle capture takes no configuration beyond `paths.principles`: the engine captures
every semantic Markdown file in that root ([ADR 0015](../decisions/0015-specification-principle-review.md)).
No filename category hint or selection table exists. Missing principle capture rejects a
principle-capturing operation. No model, workflow prompt or mechanical `toolchain.yaml`
supplies a selection table.

- The new engine calls this authority **principles**.
- It fulfils the role constitution/memory material had in the predecessor workflow: overarching
  project policy and guidance for code, architecture, project structure, security, validation,
  observability, and user-interface work.
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
- Their filenames illustrate typical principle topics, but a Markdown principle body may be
  arbitrary free text.

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

1. resolve `paths.principles` through the root-access policy, account for the separately captured exact `toolchain.yaml`, select only bounded no-follow normalized `*.md` regular files as semantic sources, reject every unclassified regular file and alias/case collision, and sort the Markdown sources by normalized Unicode-scalar root-relative path;
2. assign no category: the engine guesses no meaning from a filename or its body;
3. decode bounded UTF-8 text and preserve exact source-byte and line spans; no front matter, heading, Markdown structure, template placeholder, or content schema is required;
4. split large files into deterministic transport chunks. A file with no headings or paragraph structure is still valid and receives a whole-file or fixed-window chunk;
5. include every chunk of every captured file in stable source order; no model classifies, summarizes, ranks, or omits principle prose;
6. include the exact raw spans in plan, task, implementation, repair and semantic-review guidance without truncation or a local size-fit gate; Specify captures them but sends them in no request ([ADR 0015](../decisions/0015-specification-principle-review.md)); provider size errors follow the workflow's explicit outcome transitions;
7. validate only transport facts deterministically: configured root, containment, identity, UTF-8, source-capture byte/count ceilings, stable spans, and registry joins;
8. treat content compliance or conflict as model-assisted judgment backed by exact principle citations. Specify runs no principle assessment ([ADR 0023](../decisions/0023-advisory-post-generation-review.md)); Plan validates current policy and resolves its native required decisions at its own gate.

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

- The filename is no claim that the contents obey a schema, and it carries no category.
- The model never chooses which files to open and never sees an operational principle path—only
  registered IDs, raw bounded spans, and citations.

- Principles are captured once per command-run bootstrap, bound into `BootstrapAuthorityState`,
  and compared by direct typed metadata/raw-byte equality at every consuming Spec capture,
  plan, tasks, implement and fresh clarification-rerun gate.
- Capturing principle files is not performing an assessment
  ([ADR 0015](../decisions/0015-specification-principle-review.md)); state and evidence
  distinguish captured inputs from any executed assessment. Extraction, source-preservation
  review and business-content generation retain their reference/answer authority; principle
  prose cannot invent, erase or override business intent.
- An updated principle can resolve `PNN` or `TNN` only through cited, current authority
  resolution; it cannot supply a missing business answer or resolve an `SNN` by itself.
- A changed registry invalidates the current plan/downstream task approvals through
  shared dependency invalidation. Reassess at the consuming gate;
  do not rewrite or re-extract unchanged business sources solely to refresh policy evidence.
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
| Semantic principles | Recapture at the consuming gate, rebuild Plan's complete cited selection and invalidate affected plan/task approvals; do not change business requirements. |
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
