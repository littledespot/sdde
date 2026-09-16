# 13.1 Bootstrap and configuration actions

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.

[F0003](../../features/F0003-ToolChainService.md#3-closed-loading-and-publication-contract)
owns the current authored toolchain shapes and stable policy-ID union. The
policy-compilation and field-override actions below retain the broader proposed
design; they do not extend the current YAML schema or claim implemented capabilities.


## `LocateExactEngineConfigAction`

- **Input:** invocation working directory and trusted filesystem adapter
- **Output:** exact config location and canonical project-root descriptor, or
  `ENGINE_CONFIG_READ_ERROR`
- **Responsibility:** Capture/canonicalize the invocation working directory as project root and
  resolve only its exact `.sddtoolkit.json` child; map every unsafe/unreadable result to the one
  read error and never inspect an ancestor/descendant or accept a fallback/default name.

## `ReadEngineConfigAction`

- **Input:** validated exact config location and bounded no-follow descriptor
- **Output:** owned engine-config bytes or `ENGINE_CONFIG_READ_ERROR`
- **Responsibility:** Read that one engine config resource completely through the validated
  descriptor, accepting at most the internal `maxEngineConfigBytes = 1,048,576` bytes, and map
  every read/limit failure to the one public read error.

## `DecodeSDDToolKitConfigAction`

- **Input:** owned engine-config bytes
- **Output:** immutable `SDDToolKitConfig` or `ENGINE_CONFIG_PARSE_ERROR`
- **Responsibility:** Parse JSON directly into the exact closed reader-facing structure; map
  malformed JSON, trailing content, and structural violations to the one parse error, retain no
  generic JSON tree, and compile no domain policy.

## `CanonicalizeLogLevelAction`

- **Input:** `LogsConfig.level`
- **Output:** canonical level and alias evidence
- **Responsibility:** Solely normalize the closed configured spelling and map `CRITICAL` to
  `fatal` and `WARN` to `warning`; no other action reinterprets the configured level and no
  event producer chooses severity.

## `ResolveLogEventDefinitionRegistryAction`

- **Input:** exact built-in registry version
- **Output:** immutable event/field-definition registry
- **Responsibility:** Resolve the closed event-to-level/template/field-schema authority.

## `ValidateLoggingPolicyAction`

- **Input:** complete three-value `LogsConfig`, canonical level and alias evidence,
  event-definition registry, and compiler-locked F0002 policy/delimiter constants
- **Output:** validated logging policy fragment
- **Responsibility:** Validate the console boolean and unique closed prompt-capture selectors,
  require a direction for non-empty capture, and inject the exact F0002 Section 6.4 timestamp,
  delimiter, size, retention, flush, failure, redaction, prompt-byte, lock, and emergency
  constants.
- Do not default/reinterpret the configured level or accept any operational override/dynamic
  schema.

## `ValidateEnginePathPolicyAction`

- **Input:** one configured path relation
- **Output:** path-policy evidence
- **Responsibility:** Validate one engine path/overlap relation.

## `ResolveConfiguredBaseRootAction`

- **Input:** exact project-root descriptor, one decoded `PathsConfig` entry, and active
  workspace filesystem policy
- **Output:** configured-location candidate
- **Responsibility:** Join exactly one required relative configured directory or
  provider-document path to project root without following aliases or deriving fixed children.

## `ValidateConfiguredBaseRootAction`

- **Input:** one configured-root candidate, exact config location, portability limits, and
  engine root rules
- **Output:** configured-root capability
- **Responsibility:** Prove normalization, containment, representability, access class, and
  permitted existence/type for one `paths` base.

## `BuildBootstrapRootRegistryIdAction`

- **Input:** validated exact config location, canonical project root, and compiler-locked
  bootstrap-root contract version
- **Output:** self-validating bootstrap-root-registry identity
- **Responsibility:** Construct the closed `(canonical project root, contract version)` tuple;
  consume no state ledger and inspect no content.

## `BuildBootstrapRootRegistryAction`

- **Input:** bootstrap-root-registry identity, exact config/project-root descriptors, seven
  validated directory capabilities, and one provider-document path candidate
- **Output:** immutable bootstrap-root registry
- **Responsibility:** Assemble the seven configured directory roots and exact configured
  provider-document location needed to reserve or load engine-owned inputs; it contains no
  preset-derived/generated/project-discovery roots.

## `ValidateBootstrapRootRegistryAction`

- **Input:** bootstrap-root registry, closed eight-key required-path set, and pre-preset overlap
  matrix
- **Output:** bootstrap-root-registry evidence
- **Responsibility:** Require the seven directory roles and the `providers` file role exactly
  once; reject missing, unknown, duplicate, escaping, or illegally overlapping locations before
  ingestion, with only the declared archive nesting exception.

## `LocateLLMProviderConfigAction`

- **Input:** F0004's opaque `llm_provider_config` capability and narrow read-only source port
- **Output:** exact open provider-config file capability
- **Responsibility:** Open only the configured no-follow regular `.sddproviders.json` file; do
  not resolve raw configuration paths, read bytes, parse content, or search for another file.

## `ReadLLMProviderConfigAction`

- **Input:** exact open provider-config file capability
- **Output:** complete owned untrusted bytes
- **Responsibility:** Capture that already-opened file once under `maxLLMProviderConfigBytes =
  1,048,576`; do not parse JSON or construct provider authority.

## `DecodeLLMProviderConfigAction`

- **Input:** F0008 immutable bytes and the closed common provider-catalogue contract
- **Output:** bounded raw provider document
- **Responsibility:** Enforce strict UTF-8 JSON, common-object closure, integer-only numeric
  tokens, nesting and collection limits, and raw provider/model identity syntax; leave each
  `config` object untrusted.

## `BuildLLMProviderRegistryAction`

- **Input:** bounded raw provider document and compiler-owned provider/model contracts
- **Output:** provider-registry candidate
- **Responsibility:** Join every tuple to one compiled contract and decode its one closed
  registered configuration variant; reject unsupported, duplicate, partially valid, or
  inconsistent input without publishing a partial registry.

## `ValidateLLMProviderRegistryAction`

- **Input:** complete sorted provider-registry candidate and compiler-owned provider/model
  contracts
- **Output:** validated provider-registry owner
- **Responsibility:** Independently rejoin every candidate entry and prove total bounds, exact
  unique identities, implementation discriminators, configuration variants, contract facts, and
  deterministic ordering for the whole catalogue.

## `ValidateRepositoryModelAllowlistAction`

- **Input:** F0001 `models.slots` and validated provider registry
- **Output:** immutable validated repository model allowlist
- **Responsibility:** Require every slot tuple and option to resolve exactly, retaining only
  slot identity, registry-entry identity, and validated slot options.
- Multiple slots may share an entry; unused catalogue entries gain no repository authority.

## `BuildWorkflowAuthorityLayoutAction`

- **Input:** validated bootstrap-root registry, its exact `paths.workflows` capability, and
  compiler-locked reserved-child table
- **Output:** workflow-authority-layout candidate
- **Responsibility:** Derive the exact definition-inventory scope and fixed `features/` child
  descriptor without reading the directory, assigning an identity, or accepting another path;
  include each reserved root entry for ownership accounting while excluding all of its
  descendants.

## `ValidateWorkflowAuthorityLayoutAction`

- **Input:** layout candidate, bootstrap-root-registry evidence, portability policy, and
  reserved-child ownership rules
- **Output:** workflow-authority-layout evidence
- **Responsibility:** Prove exact root/capability joins, containment, distinct reserved
  children, inclusion of their root entries, and exclusion of both complete reserved descendant
  subtrees.

## `EnumerateWorkflowAuthorityResourcesAction`

- **Input:** validated workflow-authority layout and entry/depth/time ceilings
- **Output:** bounded unordered raw workflow-root inventory
- **Responsibility:** Enumerate every encountered directory, regular file, symlink, and special
  node in scope, including an encountered reserved root entry but never its descendants, without
  following links, parsing content, filtering entries, or assigning identities.

## `NormalizeWorkflowAuthorityEntryPathAction`

- **Input:** one raw workflow-root entry and portable path policy
- **Output:** normalized root-relative entry candidate plus path evidence
- **Responsibility:** Decode and normalize one root-relative path, reject escape/absolute/empty
  ambiguity, and preserve its observed node metadata without classifying its role.

## `ValidateWorkflowAuthorityInventoryCollisionAction`

- **Input:** complete normalized entry candidates and active portability policy
- **Output:** workflow-inventory collision evidence
- **Responsibility:** Reject duplicate, normalization-equivalent, case-fold, portable-name, and
  reserved-child alias collisions across the complete inventory.

## `SortWorkflowAuthorityInventoryAction`

- **Input:** collision-valid normalized entry candidates
- **Output:** stable ordered workflow inventory
- **Responsibility:** Sort once by normalized Unicode-scalar root-relative path without
  assigning an ID or interpreting content.

## `AssignWorkflowAuthorityInventoryOrdinalAction`

- **Input:** one entry's one-based position in the stable complete inventory
- **Output:** ordinal-bound workflow inventory entry
- **Responsibility:** Bind the position as a run-independent inventory-local ordinal; use no
  ledger, filename-derived role, content, model value, or path hash.

## `ClassifyWorkflowAuthorityResourceAction`

- **Input:** one ordinal-bound inventory entry, validated layout, and locked workflow-media
  policy
- **Output:** reserved child, definition candidate, resource candidate, directory, or blocking
  diagnostic
- **Responsibility:** Classify the exact root child `features/` only as a reserved directory;
  classify exact `*.workflow.yaml` regular files as definitions and other regular files as
  potential declared resources; account for directories; and reject links, special nodes,
  wrong-kind reserved children, or definition collisions with reserved ownership.

## `CaptureWorkflowDefinitionAction`

- **Input:** one ordinal-bound definition descriptor, no-follow filesystem port, and source-byte
  ceiling
- **Output:** immutable workflow-definition capture
- **Responsibility:** Read one definition candidate through its exact descriptor, bind the
  source inventory ordinal, and prove unchanged identity/length without parsing or inferring a
  workflow ID from its filename.

## `ParseWorkflowDefinitionAction`

- **Input:** one immutable definition capture and its registered encoding
- **Output:** raw workflow-definition value bound to its source inventory ordinal
- **Responsibility:** Parse the supported declarative encoding without applying workflow policy,
  resolving an operation contract, or treating a project workflow ID as an engine state
  identity.

## `ValidateWorkflowDefinitionSchemaAction`

- **Input:** one ordinal-bound raw definition and the closed workflow-definition schema
- **Output:** one schema-valid definition with validated `WorkflowId`, version, logging
  shortcode, invocation-operation reference, step-operation references, closed parameters, typed
  transitions, and policy-profile reference
- **Responsibility:** Apply the closed data schema and reject scripts, adapter selectors, raw
  paths/commands, malformed or duplicate local step IDs, unregistered field shapes, and explicit
  capability claims; preserve the inventory ordinal and perform no operation-contract resolution
  or graph execution.

## `ResolveWorkflowResourceInventoryAction`

- **Input:** complete schema-valid definition set and collision-valid workflow inventory
- **Output:** exact declared-resource-to-inventory bindings or blocking diagnostic
- **Responsibility:** Resolve every declared resource name beneath the workflow root, require
  each binding to name one non-definition regular-file entry, reject undeclared regular files
  and escaping, missing, ambiguous, or multiply classified resources, and perform no read.

## `CaptureWorkflowResourceAction`

- **Input:** one resolved resource binding, no-follow filesystem port, and resource byte
  ceilings
- **Output:** immutable workflow-resource capture
- **Responsibility:** Read the resource once through its exact descriptor, prove unchanged
  identity/type/length and complete bounded capture, and infer no prompt/schema behavior from
  its filename.

## `BuildWorkflowAuthorityEntryAccountAction`

- **Input:** one ordinal-bound inventory entry, its classification, and any matching
  definition/resource capture or schema result
- **Output:** one terminal workflow-authority entry account
- **Responsibility:** Record exactly one directory, reserved-child, captured-definition,
  captured-declared-resource, or blocking disposition; a failed capture/schema result remains
  blocking and no entry can receive two roles.

## `BuildWorkflowAuthorityInventoryAction`

- **Input:** validated layout, complete ordinal-bound inventory, immutable captures, and one
  proposed terminal account per entry
- **Output:** workflow-authority inventory candidate
- **Responsibility:** Assemble the deterministic inventory/accounting projection without
  assigning a separate canonical identity, choosing a successor graph, or dropping a blocking
  entry.

## `ValidateWorkflowAuthorityInventoryAction`

- **Input:** inventory candidate, layout/collision/order/path/definition/resource capture/schema
  evidence, and hard ceilings
- **Output:** workflow-authority inventory evidence
- **Responsibility:** Prove contiguous one-based ordinals, node-kind-correct no-follow metadata,
  total one-to-one terminal accounting, exact capture/entry joins, correct reserved-child
  disposition, absence of reserved descendants and blocking entries, every captured-definition
  join, and exact coverage of all and only YAML-declared resources.

## `CompileWorkflowGraphAction`

- **Input:** one schema-valid definition and the single registered generic operation, outcome,
  gate, and workflow-policy contract set
- **Output:** immutable compiled-workflow-graph candidate
- **Responsibility:** Resolve every YAML-referenced operation and closed parameter, bind the
  invocation operation, typed transitions, and terminal outcomes, and derive the graph's
  effective gate and capability requirements without constructing adapters or invoking an
  operation.

## `ValidateCompiledWorkflowGraphAction`

- **Input:** one compiled-workflow-graph candidate and its complete referenced contract evidence
- **Output:** compiled-workflow-graph evidence
- **Responsibility:** Prove the invocation operation is capability-free and converts preserved
  arguments only to its declared typed run context; prove graph closure, bounded cycles,
  entry/transition/terminal consistency, parameter/resource compatibility, gate preservation,
  and that every effective capability is permitted by the selected workflow policy; reject
  unknown operations, executable payloads, infrastructure selection, and runner bypasses.

## `BuildWorkflowDefinitionRegistryAction`

- **Input:** validated workflow-authority inventory and the complete compiled-workflow-graph set
- **Output:** identity-free workflow-definition-registry candidate
- **Responsibility:** Index the arbitrary bounded graph set by validated `WorkflowId`, retaining
  each source inventory ordinal and logging shortcode while assigning no source or
  bootstrap-component identity.

## `ValidateWorkflowDefinitionRegistryAction`

- **Input:** registry candidate, workflow-inventory evidence, and compiled-workflow-graph
  evidence
- **Output:** workflow-definition-registry evidence
- **Responsibility:** Prove variable-size total coverage of captured definitions, unique
  workflow IDs, logging shortcodes and source ordinals, exact captured-definition account joins,
  reserved-child exclusion, and validation evidence for every indexed graph; require no
  particular workflow name or count.

## `ResolveSelectedWorkflowAction`

- **Input:** validated workflow-definition registry and one validated invocation `WorkflowId`
- **Output:** exactly one selected compiled workflow graph or typed unknown-workflow diagnostic
- **Responsibility:** Resolve the requested workflow exactly once without filename inference,
  default selection, directory auto-selection, or workflow-specific branching.

## `DeriveProviderRequirementAction`

- **Input:** exactly selected validated compiled workflow graph
- **Output:** closed `required` or `not_required` model-provider requirement
- **Responsibility:** Return `required` when a compiled step has typed model-binding
  requirements or the exact compiler-owned `model-provider` capability; do not infer from
  workflow/step identity, parameter names, policy allowance alone, configuration, operation
  names, or provider content.

## `ResolveFeatureStateIdLedgerPathAction`

- **Input:** validated workflow-artifact registry and `FeatureStateIdLedgerCanonicalState`
  selector
- **Output:** fixed feature state-ID-ledger path
- **Responsibility:** Resolve the one engine-owned feature ledger path and accept no caller
  path.

## `ReadStateIdLedgerAction`

- **Input:** one validated feature-ledger path and bounded no-follow descriptor
- **Output:** absent or bounded canonical feature ledger bytes
- **Responsibility:** Read one feature ledger resource without parsing, allocating, or repairing
  it.

## `ParseStateIdLedgerAction`

- **Input:** bounded canonical feature-ledger bytes
- **Output:** unvalidated feature state-ID ledger
- **Responsibility:** Decode the closed feature ledger; trust no owner, namespace, ordinal,
  status, or purpose key.

## `BuildInitialFeatureStateIdLedgerAction`

- **Input:** new feature identity and compiler-locked feature namespace registry
- **Output:** empty in-memory feature ledger revision zero
- **Responsibility:** Initialize every feature namespace at ordinal one; persistence occurs only
  inside activation.

## `ValidateStateIdLedgerAction`

- **Input:** parsed/initial ledger, exact owner, namespace registry, optional prior ledger, and
  complete allocation accounts
- **Output:** state-ID-ledger evidence
- **Responsibility:** Prove owner/path identity, compare-and-swap revision, monotonic ordinals,
  unique purpose-bound records, valid status transitions, total retirement, and no reuse.

## `BuildStateIdPurposeKeyAction`

- **Input:** one closed feature-activation/workflow-stage/task-execution transition descriptor,
  exact current feature authorities, state type, and compiler-locked transition-slot registry
- **Output:** discriminated state-ID purpose key
- **Responsibility:** Construct one exact typed purpose tuple and reject free-text or
  caller/model-selected slots.

## `ValidateStateIdPurposeKeyAction`

- **Input:** purpose key, requested state type, owner, current authorities, and transition-slot
  registry
- **Output:** purpose-key evidence
- **Responsibility:** Prove variant-specific required/forbidden fields, current revision joins,
  state-type/slot compatibility, and stable direct-equality semantics.

## `ResolveStateIdNamespaceCapabilityAction`

- **Input:** validated current ledger, exact state type, engine-built typed purpose key, and
  compiler-locked namespace registry
- **Output:** single-use state-ID namespace capability
- **Responsibility:** Bind one state type to its sole owner/scope/namespace and current ledger
  revision; reject caller-selected namespaces.

## `AssignStateIdReservationAction`

- **Input:** one namespace capability and exact current validated ledger
- **Output:** canonical state-ID reservation plus successor ledger
- **Responsibility:** Reuse only a directly equal open purpose reservation or consume exactly
  one monotonic ordinal; assign no content/path/model-derived identity.
- Registered state-specific ID-assignment actions implement this same ABI directly and never
  invoke this action or one another.

## `RetireStateIdReservationAction`

- **Input:** one reserved ID, typed abandonment cause, and current successor ledger
- **Output:** retired allocation record plus next ledger
- **Responsibility:** Retire exactly one ordinal permanently and create no replacement.

## `BuildStateIdentityMutationAction`

- **Input:** validated input ledger and complete ordered reservation/commit/retirement results
  for one owner
- **Output:** one closed state-identity mutation
- **Responsibility:** Construct unchanged, initialized-feature, or advanced mutation without
  allocating or writing.

## `BuildRootAccessRegistryAction`

- **Input:** validated configured/derived roots, compiled preset generated roots, dependency/VCS
  facts, and locked engine rules
- **Output:** immutable root-access registry
- **Responsibility:** Assign every reachable root one access class without filesystem scanning.

## `ValidateRootAccessRegistryAction`

- **Input:** compiled root-access registry and allowed nesting matrix
- **Output:** root-registry evidence
- **Responsibility:** Reject uncovered, equal-precedence conflicting, or illegally overlapping
  roots.

## `ResolveTargetPlatformPolicyAction`

- **Input:** one exact target-platform ID and platform registry
- **Output:** immutable filesystem policy
- **Responsibility:** Resolve one normalization/case/name/length contract.

## `DetectWorkspaceFilesystemPolicyAction`

- **Input:** trusted workspace/filesystem adapter
- **Output:** active filesystem policy ID and evidence
- **Responsibility:** Detect the host policy independently of user configuration.

## `ValidateEnvironmentTargetPlatformSetAction`

- **Input:** one environment's resolved platform IDs
- **Output:** target-platform-set evidence
- **Responsibility:** Reject empty, duplicate, or unresolved policy sets.

## `BuildPortabilityPolicySetAction`

- **Input:** resolved configured targets and active workspace policy
- **Output:** compiled portability-policy union
- **Responsibility:** Deduplicate and bind the non-overridable host-plus-target set.

## `CompileWorkflowModelOperationAction`

- **Input:** one YAML-declared model-operation step, its referenced workflow resources, and the
  registered generic operation contract
- **Output:** immutable compiled model-operation declaration
- **Responsibility:** Resolve the explicit slot, resources, schemas, controls, and outcomes
  without consulting a built-in route or hidden default.

## `ValidateRendererContractVersionAction`

- **Input:** configured renderer version and renderer registry
- **Output:** renderer evidence
- **Responsibility:** Select one exact supported renderer contract.

## `ResolveConfiguredToolchainPresetRootAction`

- **Input:** validated bootstrap-root registry and its direct `paths.toolchainPreset` capability
- **Output:** exact toolchain-preset-registry capability
- **Responsibility:** Resolve the sole configured preset package registry directly; derive no
  child registry and never search or fall back to source examples.

## `BuildToolchainPresetIdLedgerAction`

- **Input:** validated bootstrap-root registry and optional prior validated preset registry/ID
  ledger
- **Output:** current preset ID ledger
- **Responsibility:** Initialize every namespace at one, or retain prior next
  ordinals/tombstones for refresh; bind it to the already available bootstrap-root registry, not
  later project discovery.

## `ValidateToolchainPresetIdLedgerAction`

- **Input:** current/optional prior ledgers and every retained/new/retired preset identity
- **Output:** preset-ID-ledger evidence
- **Responsibility:** Prove direct-equality retention, monotonic per-namespace allocation, total
  tombstone accounting, no reuse, and exact prior/successor joins.

## `ParseToolchainPresetIdLedgerAction`

- **Input:** bounded canonical ledger bytes
- **Output:** unvalidated preset ID ledger
- **Responsibility:** Parse one persisted multi-namespace ledger without trusting ownership or
  ordinals.

## `SerializeToolchainPresetIdLedgerAction`

- **Input:** validated final preset ID ledger
- **Output:** canonical ledger bytes
- **Responsibility:** Serialize ownership, next ordinals, and tombstones in namespace order.

## `BuildToolchainPresetCaptureBudgetSessionAction`

- **Input:** bootstrap-attempt identity and configured/hard entry/depth/source-byte/time/memory
  ceilings
- **Output:** run-local provisional capture-budget session
- **Responsibility:** Initialize bounded provisional reservations/counters after inventory-entry
  IDs exist; this session is never persisted as canonical authority.

## `ValidateToolchainPresetCaptureBudgetSessionAction`

- **Input:** complete provisional session, sorted inventory, capture observations, and hard
  ceilings
- **Output:** closed session evidence
- **Responsibility:** Prove exactly one terminal provisional reservation per regular-file entry,
  no reservation for other nodes, exact totals, and no unaccounted read.

## `AssignToolchainPresetBudgetLedgerStateIdAction`

- **Input:** complete closed provisional session, captured owner/byte set, optional prior closed
  budget ledger, and current preset ID ledger
- **Output:** retained/new preset-budget-ledger identity plus successor ledger
- **Responsibility:** After capture, retain the prior identity only when policy, owner set,
  terminal outcomes, and direct bytes all match; otherwise allocate once in
  `budget_ledger_state`.

## `AssignToolchainPresetReservationIdAction`

- **Input:** one provisional reservation in canonical inventory order, optional exact prior
  reservation for the same retained entry, and current candidate ledger ordinal/tombstones
- **Output:** retained/new stable reservation ID plus next ordinal/tombstones
- **Responsibility:** Retain only the exact prior owner/outcome/byte binding; otherwise consume
  one monotonic reservation ordinal.

## `RetireRemovedToolchainPresetReservationAction`

- **Input:** one unmatched prior reservation and current candidate tombstones
- **Output:** next reservation tombstones
- **Responsibility:** Retire exactly one removed/superseded reservation ID and never make it
  reusable.

## `BuildToolchainPresetSourceBudgetLedgerAction`

- **Input:** chosen identity, validated complete provisional session, complete
  provisional-to-stable reservation map, next reservation ordinal/tombstones, optional prior
  ledger, and successor preset ID ledger
- **Output:** immutable candidate preset-budget ledger
- **Responsibility:** Assemble stable retained/new/retired canonical reservations with exact
  totals in inventory order; perform no allocation or retirement itself and preserve no
  bootstrap-attempt identity.

## `EnumerateToolchainPresetResourcesAction`

- **Input:** toolchain-presets-root capability and entry/depth/time ceilings
- **Output:** bounded unordered raw inventory
- **Responsibility:** Enumerate every encountered directory, regular file, symlink, special
  node, and engine-locked metadata candidate without following links, filtering, sorting,
  assigning IDs, or claiming validity.

## `ValidateToolchainPresetResourcePathAction`

- **Input:** one raw inventory entry and bootstrap-root/portable-filesystem policy
- **Output:** contained path evidence or blocking node diagnostic
- **Responsibility:** Prove one engine-owned relative path is UTF-8/NFC, normalized, contained,
  host-representable, non-aliased, and of its observed no-follow node type.

## `ValidateToolchainPresetInventoryCollisionAction`

- **Input:** complete raw inventory and all path evidence
- **Output:** collision evidence
- **Responsibility:** Reject duplicate, normalization-equivalent, case-fold, and portable-name
  collisions across the complete inventory.

## `SortToolchainPresetInventoryAction`

- **Input:** collision-valid raw inventory
- **Output:** stable ordered inventory
- **Responsibility:** Sort once by normalized Unicode-scalar relative path; assign no identity.

## `AssignToolchainPresetInventoryEntryIdAction`

- **Input:** one ordered position, optional directly equal prior entry, and current preset ID
  ledger
- **Output:** retained/new inventory-entry identity plus successor ledger
- **Responsibility:** Retain only an exact normalized-path/node/metadata match; otherwise
  allocate once in `inventory_entry`, with no path/content-derived ID.

## `BuildToolchainPresetInventoryEntryAction`

- **Input:** identity, observed metadata, and path evidence/diagnostic
- **Output:** immutable inventory entry
- **Responsibility:** Record exactly what was encountered without interpreting file content.

## `ReserveToolchainPresetSourceBytesAction`

- **Input:** one regular-file inventory entry and current provisional capture-budget session
- **Output:** single-entry provisional reservation and next session
- **Responsibility:** Reserve the reported length once or emit a closed budget diagnostic.

## `CaptureToolchainPresetResourceAction`

- **Input:** one contained regular-file entry, its exact reservation, and same no-follow
  descriptor identity
- **Output:** raw immutable-byte capture observation
- **Responsibility:** Read bounded bytes exactly once and report
  entry/descriptor/length/byte-handle facts; assign no resource/source-map ID and never accept a
  model path or source-example fallback.

## `CommitToolchainPresetSourceDebitAction`

- **Input:** provisional reservation, stable complete read observation, and current
  capture-budget session
- **Output:** committed debit and next session
- **Responsibility:** Commit exact actual bytes only when identity/type/length and reservation
  remain equal.

## `ReleaseToolchainPresetSourceReservationAction`

- **Input:** failed/changed read observation, provisional reservation, and current
  capture-budget session
- **Output:** released reservation and next session
- **Responsibility:** Close one failed reservation without treating its bytes as captured.

## `AssignToolchainPresetResourceIdAction`

- **Input:** stable raw capture observation, committed debit, optional directly equal prior
  captured blob, and current preset ID ledger
- **Output:** retained/new resource identity plus successor ledger
- **Responsibility:** Retain only after direct raw-byte and metadata equality; otherwise
  allocate once in `resource`, independent of filename or document metadata.

## `AssignToolchainPresetSourceMapIdAction`

- **Input:** resource identity, optional retained resource/source-map join, and current preset
  ID ledger
- **Output:** retained/new source-map identity plus successor ledger
- **Responsibility:** Retain the prior map only with its exact retained resource; otherwise
  allocate once in `source_map`.

## `BuildToolchainPresetCapturedBlobAction`

- **Input:** resource/source-map identities, stable raw capture observation, exact inventory
  entry, and committed debit
- **Output:** canonical captured preset blob
- **Responsibility:** Bind the immutable bytes to engine identities only after the read and
  debit succeed.

## `BuildToolchainPresetSourceMapAction`

- **Input:** source-map/resource identities, canonical captured blob, exact inventory metadata,
  and committed debit
- **Output:** immutable whole-resource source map
- **Responsibility:** Bind only byte range `0..byteLength` to the captured blob; later
  package/asset parser coordinates live in immutable parser-validation evidence and never mutate
  this map.

## `ClassifyToolchainPresetResourceRoleAction`

- **Input:** captured blob, locked media/extension registry, and optional later package
  declaration joins
- **Output:** package-document candidate, one closed typed asset candidate, or
  unsupported-resource diagnostic
- **Responsibility:** Classify only `package_document`, `parser_query`, `grammar`,
  `adapter_descriptor`, or `schema`; every other/ambiguous media-role combination blocks and
  package identity is never inferred from filename.

## `ClassifyPresetDocumentVersionAction`

- **Input:** one captured package-document YAML/JSON candidate and fixed format sniffer
- **Output:** v1 document candidate or legacy/unknown diagnostic
- **Responsibility:** Classify transport/version only; it is never run on a
  parser/query/grammar/adapter asset and a filename cannot create preset identity.

## `RejectLegacyPresetDocumentAction`

- **Input:** one legacy top-level shape or template inventory
- **Output:** rejection evidence
- **Responsibility:** Emit `PRESET_LEGACY_SCHEMA_UNSUPPORTED`; runtime never invokes migration.

## `ReadPresetAction`

- **Input:** one captured v1 candidate blob
- **Output:** raw preset resource
- **Responsibility:** Decode the immutable captured resource without reopening its path.

## `ParsePresetAction`

- **Input:** raw preset resource
- **Output:** raw preset object
- **Responsibility:** Parse YAML/JSON using fixed semantics.

## `ValidatePresetSchemaAction`

- **Input:** raw preset object
- **Output:** schema-valid preset
- **Responsibility:** Apply only the closed preset schema.

## `RejectPresetPlaceholderAction`

- **Input:** one schema-valid preset
- **Output:** placeholder-free preset evidence
- **Responsibility:** Reject unresolved placeholders.

## `BuildPresetResourceDeclarationIndexAction`

- **Input:** complete set of placeholder-free schema-valid package documents
- **Output:** preset resource-declaration index candidate
- **Responsibility:** Project every explicit locator plus declared stable resource
  ID/version/role/media/format and owning package; infer nothing from an asset filename.

## `ValidatePresetResourceDeclarationIndexAction`

- **Input:** declaration-index candidate, complete captured inventory paths, package identities,
  and locator policy
- **Output:** declaration-index evidence
- **Responsibility:** Require one-to-one contained normalized locator ownership, unique stable
  identity/version, role/media compatibility, no duplicate/missing/extra locator, and no path
  escape.

## `JoinToolchainPresetAssetDeclarationAction`

- **Input:** one captured typed asset candidate, its exact inventory entry/path evidence, and
  validated declaration index
- **Output:** exact asset-declaration join
- **Responsibility:** Match the declaration's locator exactly once and copy declared
  identity/version/role/media/format; the locator locates bytes but never becomes identity.

## `AssignToolchainPresetAssetIdAction`

- **Input:** resource identity, typed asset candidate, optional retained resource/asset join,
  and current preset ID ledger
- **Output:** retained/new preset-asset identity plus successor ledger
- **Responsibility:** Retain only an exact prior typed-asset join; otherwise allocate once in
  `asset`, independent of filename and package declarations.

## `BuildToolchainPresetAssetRecordAction`

- **Input:** asset/resource identities, exact asset-declaration join, blob/debit/source-map
  evidence, and locked asset-format descriptor
- **Output:** immutable asset record
- **Responsibility:** Bind one non-document resource to declared identity/version and captured
  bytes without inferring identity from its locator or parsing it as a package.

## `ValidateToolchainPresetAssetAction`

- **Input:** one asset record and its exact parser/query/grammar/adapter/schema validator
- **Output:** resource-asset evidence
- **Responsibility:** Validate bounded syntax, required captures/exports, dialect/version, and
  absence of undeclared includes or path escape.

## `ResolvePresetResourceReferenceAction`

- **Input:** one schema-valid package resource reference and complete validated asset registry
- **Output:** exact asset-reference evidence
- **Responsibility:** Resolve one declared stable resource ID/version/role exactly once; reject
  filename-only, missing, extra, or role-incompatible assets.

## `BuildToolchainPresetPackageRecordAction`

- **Input:** one placeholder-free schema-valid package document, its captured
  resource/source-map evidence, and all exact resolved asset-reference evidence
- **Output:** immutable package record
- **Responsibility:** Bind declared stable preset ID/exact version/layer to its package document
  and exact asset IDs without composing or inferring from filename.

## `ValidateToolchainPresetPackageRecordAction`

- **Input:** one package record, package schema/placeholder/resource evidence, and global
  identity/layer registries
- **Output:** package-record evidence
- **Responsibility:** Prove document ownership, exact metadata equality, closed resource joins,
  unique stable identity/version, and absence of unreferenced embedded operational resources.

## `ValidateWritableKindReferenceCoverageAction`

- **Input:** one model-writable file kind and registered content extractors/fallback
  scanner/resolver
- **Output:** content-surface evidence
- **Responsibility:** Disable model create/patch/replace unless every string/path surface has
  deterministic extraction or conservative blocking coverage.

## `CompilePathPatternAction`

- **Input:** one schema-valid `PathPattern`
- **Output:** compiled matcher/path language
- **Responsibility:** Compile one exact/glob/RE2 pattern or diagnose it.

## `ValidatePathPatternBaseBindingAction`

- **Input:** one pattern, canonical workspace/environment/project/source-root registry, and
  optional exact command-cwd evidence
- **Output:** base-binding evidence
- **Responsibility:** Enforce base-specific iff rules and resolve exactly one contained base
  without ambient context.

## `ValidatePathPatternRuleIdAction`

- **Input:** one path-pattern ID and compiled preset closure
- **Output:** rule-ID evidence
- **Responsibility:** Prove global uniqueness and version-stable ownership of one rule ID.

## `ValidateFileKindExtensionRuleAction`

- **Input:** one file kind's extension set, `extensionRuleId`, case flag, and compiled preset
  closure
- **Output:** extension-rule evidence
- **Responsibility:** Require a stable globally unique rule ID, nonempty unique longest-suffix
  set, and explicit case semantics.

## `ValidatePresetPathTemplateAction`

- **Input:** one path template, owning file kind, option-rule/role/name-transform registries,
  and bound root/placement policy
- **Output:** path-template evidence
- **Responsibility:** Prove option-rule/template/transform IDs and fields are closed, extension
  agrees with the kind, and its strategy can yield only paths inside allowed roots.

## `ValidateFileKindInferenceAmbiguityAction`

- **Input:** compiled file-kind languages, priorities, roots, and intent domains
- **Output:** inference-uniqueness evidence
- **Responsibility:** Reject an equal-priority overlapping inference domain.

## `ValidatePresetVersionPinAction`

- **Input:** one preset reference
- **Output:** version evidence
- **Responsibility:** Require one exact supported version.

## `ValidatePresetLayerEdgeAction`

- **Input:** one composition edge
- **Output:** layer-order evidence
- **Responsibility:** Validate one layer dependency.

## `ValidatePresetDuplicateIdentityAction`

- **Input:** one preset identity and closure
- **Output:** uniqueness evidence
- **Responsibility:** Reject duplicate/conflicting inclusion.

## `DetectPresetCompositionCycleAction`

- **Input:** preset dependency graph
- **Output:** acyclicity evidence
- **Responsibility:** Detect composition cycles only.

## `TopologicallyOrderPresetCompositionAction`

- **Input:** acyclic validated preset graph and closed layer-rank table
- **Output:** ordered validated presets
- **Responsibility:** Apply dependency-first Kahn ordering with `(layerRank, Unicode-scalar
  presetId, exact version)` as the stable ready-set tie-break; do not merge values.

## `CompilePresetSetAction`

- **Input:** validated project toolchain layer and its ordered exact inherited preset closure
- **Output:** merged preset-policy candidate with unresolved source-root templates
- **Responsibility:** Apply the layer's closed inheritance/merge rules once without inventing
  packages, precedence, or project-specific root IDs.

## `ValidateCompiledPresetSetSafetyAction`

- **Input:** merged preset-policy candidate, project-toolchain-layer evidence, ordered
  composition-graph evidence, field-level source evidence, and compiler-locked merge/safety
  policy
- **Output:** safety-valid merged preset policy and merged-policy safety evidence
- **Responsibility:** Prove the effective merged result preserves every locked rule, uses only
  the declared precedence and merge operators, contains no conflicting effective assignment, and
  does not weaken path, command, capability, sandbox, network, resource, or effect limits;
  reject rather than repairing, defaulting, or evaluating safety against an unmerged layer.

## `BuildToolchainPresetEntryAccountAction`

- **Input:** one inventory entry and exactly one terminal
  directory/exclusion/blocked/captured-document/captured-asset disposition
- **Output:** immutable entry-account record
- **Responsibility:** Account for one encountered entry exactly once; a blocking record remains
  blocking rather than being silently filtered.

## `AssignToolchainPresetInventoryStateIdAction`

- **Input:** root identity, complete unidentified inventory content, optional prior inventory,
  closed budget ledger, and current preset ID ledger
- **Output:** retained/new inventory-state identity plus successor ledger
- **Responsibility:** Retain only when the complete canonical inventory projection compares
  directly equal; otherwise allocate once in `inventory_state`, never from a path or byte
  fingerprint.

## `BuildToolchainPresetInventoryStateAction`

- **Input:** inventory-state/root identities, stable entries, closed budget ledger, captured
  blobs/source maps, complete entry accounts, and final successor preset ID ledger
- **Output:** immutable inventory state
- **Responsibility:** Assemble restart-safe inventory/accounting and its exact allocation
  authority without validating package composition.

## `ValidateToolchainPresetInventoryStateAction`

- **Input:** inventory state, optional prior state, root/path/collision/read/budget evidence,
  ID-ledger evidence, and hard limits
- **Output:** inventory-state evidence
- **Responsibility:** Prove total one-to-one entry accounting, retained/new/retired identity
  rules, closed reservations, exact blob/debit joins, and no blocking node or unclassified
  captured resource.

## `AssignToolchainPresetRegistryStateIdAction`

- **Input:** validated inventory state, complete validated package/asset/declaration/reference
  candidate content, optional prior registry, and current preset ID ledger
- **Output:** retained/new toolchain-preset-registry identity plus successor ledger
- **Responsibility:** Reuse the prior registry only when every complete typed
  package/asset/reference field and raw byte compares directly equal; otherwise allocate once in
  `registry_state`.

## `BuildToolchainPresetRegistryStateAction`

- **Input:** registry identity, validated inventory state, final successor preset ID ledger, all
  validated exact package records, all validated asset records, and reference joins
- **Output:** immutable toolchain-preset registry candidate
- **Responsibility:** Assemble the sole restart-safe package/resource/allocation authority
  without compiling environments.

## `ValidateToolchainPresetRegistryStateAction`

- **Input:** registry candidate, optional prior registry,
  inventory/package/asset/schema/reference/ID-ledger evidence, and closed preset-registry
  contracts
- **Output:** registry evidence
- **Responsibility:** Prove complete resource/identity accounting, exact package/asset joins, no
  orphan or multiply owned asset, root containment, and closure of every package-declared
  dependency and asset reference without consulting project environments, project-toolchain
  inheritance, or any later selection.

## `ValidateEnvironmentRootContainmentAction`

- **Input:** one configured environment root and canonical workspace
- **Output:** contained environment root
- **Responsibility:** Prove one environment root is relative and non-escaping.

## `EnumerateManifestCandidatesAction`

- **Input:** contained environment roots plus compiled discovery rules
- **Output:** manifest candidates
- **Responsibility:** Enumerate possible manifests only.

## `ValidateManifestContainmentAction`

- **Input:** one manifest candidate and owning contained environment
- **Output:** manifest-containment evidence
- **Responsibility:** Prove one manifest/project root cannot escape its environment.

## `ParseProjectManifestAction`

- **Input:** one containment-valid manifest and one registered adapter
- **Output:** project fragment
- **Responsibility:** Parse one manifest only.

## `AssembleProjectRegistryAction`

- **Input:** validated project fragments
- **Output:** repository project facts
- **Responsibility:** Assemble non-conflicting ownership records.

## `ResolveSourceRootSelectorAction`

- **Input:** one preset-owned source-root selector and assembled project/manifest facts
- **Output:** ordered identified source roots
- **Responsibility:** Resolve semantic roles such as Java main/test/resources to exact
  engine-owned `sourceRootId`s without returning raw model paths.

## `MaterializeSourceRootPathPatternAction`

- **Input:** one source-root template and one matching identified source root
- **Output:** bound source-root pattern
- **Responsibility:** Create `base: source_root`, copy the exact root ID, and derive the
  instance rule ID as the unambiguous tuple `(templateRuleId, sourceRootId)`.

## `BuildCompiledEnvironmentPolicyAction`

- **Input:** safety-valid merged preset policy, merged-policy safety evidence, all bound
  source-root patterns, resolved project/environment bases, and binding evidence
- **Output:** compiled environment policy
- **Responsibility:** Replace every template with its complete deterministic binding set; retain
  no unresolved template and accept no unvalidated merged-policy candidate.

## `ValidateCompiledEnvironmentPolicyAction`

- **Input:** compiled environment policy, project/source-root registry, and preset closure
- **Output:** environment-policy evidence
- **Responsibility:** Prove total template resolution, base containment, rule-ID tuple
  uniqueness, and no unresolved/extra binding.

## `AssignRepositoryFactRegistryStateIdAction`

- **Input:** prospective bootstrap-authority-state ID and singleton repository-fact component
  descriptor
- **Output:** owner-local repository-fact-registry identity
- **Responsibility:** Construct the registered bootstrap-component tuple without hashing facts
  or consuming a generic state ledger.

## `BuildRepositoryFactRegistryAction`

- **Input:** registry identity plus project, manifest, dependency, command, file, and preset
  facts
- **Output:** typed repository fact-registry candidate
- **Responsibility:** Assemble one complete ordered fact input state.

## `ValidateRepositoryFactRegistryAction`

- **Input:** registry candidate, project/environment/file/command/preset authorities, and fact
  schema
- **Output:** fact-registry evidence
- **Responsibility:** Prove unique fact/value IDs, typed values, evidence joins, complete
  configured fact coverage, and gate-policy legality.

## `CompareRepositoryFactValueAction`

- **Input:** one persisted registered fact and one freshly rebuilt fact
- **Output:** equality/transition evidence
- **Responsibility:** Compare one typed value under its gate policy.

## `ValidateEnvironmentMatchAction`

- **Input:** config, compiled policy, project facts
- **Output:** resolved environments
- **Responsibility:** Detect conflicts and ambiguities.

## `AssignPathTokenGrammarStateIdAction`

- **Input:** prospective bootstrap-authority-state ID, singleton base-grammar component
  descriptor, and optional historical parent grammar ID
- **Output:** owner-local path-token-grammar identity
- **Responsibility:** Construct the registered bootstrap-component tuple without deriving it
  from grammar content or consuming a generic state ledger.

## `BuildSupersetPathTokenGrammarAction`

- **Input:** assigned grammar identity and exactly one closed build variant: either the
  validated identity-free **base** grammar blueprint plus its validated `leaf_dependencies`
  resolution map, or an already validated identified base/parent grammar plus identified
  reference-manifest names/reference-state identity; each variant also carries its exact
  compiled environments, manifests, reserved names, and root registry
- **Output:** version-bound base or feature superset path-token grammar
- **Responsibility:** For the base variant, resolve every blueprint reference to its exact
  canonical component ID.
- For the feature variant, extend only the identified parent with the identified
  reference-manifest inputs.
- Union every detectable extension/name/path/URI lexeme rule without an operation allowlist, and
  reject an unresolved handle, absent parent identity, or cross-variant field rather than
  copying it.

## `ValidateSupersetPathTokenGrammarAction`

- **Input:** grammar, exact input registries, and scanner contract
- **Output:** grammar evidence
- **Responsibility:** Prove complete input coverage, canonical ordering/deduplication, closed
  lexer rules, and exact state/version bindings.

## `ValidateDependencyRegistrySourceAction`

- **Input:** one schema-valid registry-source descriptor and engine trust/credential adapter
  registries
- **Output:** registry-source evidence
- **Responsibility:** Validate unique ID, ecosystem, canonical HTTPS endpoint, trust policy,
  optional credential policy, and prerelease rule without contacting it.

## `ResolveDependencyGrammarAction`

- **Input:** one exact package-name/version grammar ID and built-in grammar registry
- **Output:** immutable dependency grammar
- **Responsibility:** Resolve and compile one versioned non-backtracking grammar or diagnose
  absence.

## `ValidateDependencyDenyRuleAction`

- **Input:** one exact/RE2 package deny rule and ecosystem case policy
- **Output:** dependency-deny evidence
- **Responsibility:** Compile one stable rule ID with full-scalar semantics.

## `AssignDependencyPolicyRegistryIdAction`

- **Input:** validated dependency config, prospective bootstrap-authority-state ID, and
  singleton dependency-policy component descriptor
- **Output:** owner-local dependency-policy-registry identity
- **Responsibility:** Construct the registered bootstrap-component tuple without hashing policy
  content or consuming a generic state ledger.

## `BuildDependencyPolicyRegistryAction`

- **Input:** registry identity and all registry-source/grammar/deny/scope evidence
- **Output:** dependency-policy-registry candidate
- **Responsibility:** Assemble the closed ecosystem authorities without performing package
  lookup or mutation.

## `ValidateDependencyPolicyRegistryAction`

- **Input:** registry candidate and configured environment ecosystems
- **Output:** dependency-policy evidence
- **Responsibility:** Prove unique IDs, total source/grammar joins, allowed-scope closure, and
  environment coverage.

## `ResolveFileIntentCapabilityRegistryAction`

- **Input:** exact built-in registry version and locked execution policy
- **Output:** immutable file-intent-capability registry
- **Responsibility:** Resolve the closed intent/capability/implication/sequence matrix without
  project input.

## `ValidateFileIntentCapabilityRegistryAction`

- **Input:** registry and closed intent/operation enums
- **Output:** file-intent policy evidence
- **Responsibility:** Prove every intent is covered once, required sets are satisfiable,
  implications are closed, and no operation obtains an undeclared capability.

## `ResolveFactTransitionRuleRegistryAction`

- **Input:** exact built-in/preset transition-rule references
- **Output:** immutable fact-transition-rule registry
- **Responsibility:** Resolve only version-pinned closed transition variants.

## `ValidateFactTransitionRuleRegistryAction`

- **Input:** transition registry, repository fact variants, command/file operation enums, and
  environment ecosystems
- **Output:** fact-transition policy evidence
- **Responsibility:** Prove unique IDs and total compatible before/after/operation coverage.

## `ProbeCommandCapabilityAction`

- **Input:** one project and command descriptor
- **Output:** command capability evidence
- **Responsibility:** Prove one named capability exists.

## `ValidateCommandWorkingDirectoryAction`

- **Input:** one command descriptor and owning project
- **Output:** working-directory evidence
- **Responsibility:** Prove the resolved command directory is contained by that project.

## `ResolveCommandExecutableAction`

- **Input:** one command descriptor and engine executable/adapter allowlist
- **Output:** executable capability
- **Responsibility:** Resolve one exact non-shell executable through an allowed adapter.

## `ValidateCommandPlaceholderContractAction`

- **Input:** one command descriptor and typed placeholder registry
- **Output:** placeholder evidence
- **Responsibility:** Prove every argv placeholder is declared once, type-compatible,
  engine-bindable, and used only as a whole argv element.

## `ValidateCommandMutabilityAliasAction`

- **Input:** one resolved command capability and manifest semantics
- **Output:** mutability evidence
- **Responsibility:** Reject validation/read-only aliases that resolve to install, add,
  dependency mutation, or another stronger effect.

## `ValidateCommandQuotaCapabilityAction`

- **Input:** one sandbox adapter and engine command quotas
- **Output:** quota-capability evidence
- **Responsibility:** Prove entry/bytes/per-file/private-temp limits are enforceable during
  writes.

## `ValidateCommandEffectDisjointnessAction`

- **Input:** one command's compiled persistent and ephemeral pattern sets
- **Output:** disjointness evidence
- **Responsibility:** Prove their path-language intersection is empty.

## `ValidateCommandEphemeralRootAction`

- **Input:** one ephemeral pattern and compiled root registry
- **Output:** ephemeral-root evidence
- **Responsibility:** Restrict it to generated/cache/private-temp roots.

## `AssembleCommandRegistryAction`

- **Input:** capability, cwd, executable, placeholder, mutability, compiled persistent/ephemeral
  patterns, effect-disjointness/ephemeral-root evidence, sandbox-capability evidence, and
  quota-capability evidence
- **Output:** available command registry
- **Responsibility:** Assemble only completely proven command capabilities.

## `ValidateCommandRegistryAction`

- **Input:** command-registry candidate and all descriptor evidence
- **Output:** command-registry evidence
- **Responsibility:** Prove unique IDs/versions and exact
  executable/argv/cwd/limit/environment/network/mutability/sandbox bindings.

## `SerializeCommandRegistryAction`

- **Input:** validated command registry
- **Output:** canonical registry bytes
- **Responsibility:** Serialize the restart-safe command authority.

## `ResolveConfiguredPrinciplesRootAction`

- **Input:** validated bootstrap-root registry and its direct `paths.principles` capability
- **Output:** exact principles-root capability
- **Responsibility:** Resolve the sole configured project-principles root directly; never search
  or fall back.

## `ResolveProjectToolchainLayerPathAction`

- **Input:** exact principles-root capability and portable-filesystem policy
- **Output:** exact no-follow `toolchain.yaml` descriptor
- **Responsibility:** Resolve only `<paths.principles>/toolchain.yaml`, rejecting absence,
  alias/case ambiguity, links, special nodes, or any independently supplied path.

## `CaptureProjectToolchainLayerAction`

- **Input:** exact layer descriptor, no-follow filesystem port, and byte ceiling
- **Output:** immutable captured project-toolchain bytes
- **Responsibility:** Read the exact descriptor and prove unchanged identity/length without
  parsing YAML or reading preset resources.

## `ParseProjectToolchainLayerAction`

- **Input:** captured project-toolchain bytes and fixed YAML 1.2 parser
- **Output:** raw project-toolchain value
- **Responsibility:** Parse only YAML structure without resolving inheritance or applying
  policy.

## `ValidateProjectToolchainLayerSchemaAction`

- **Input:** raw project-toolchain value and closed layer schema/version
- **Output:** schema-valid project toolchain layer
- **Responsibility:** Reject unknown fields, unsupported versions, ranges/latest, placeholders,
  and untyped command/effect shapes without resolving inheritance or deciding merged safety
  policy.

## `ResolveProjectToolchainInheritanceAction`

- **Input:** schema-valid project layer and completely accounted preset package registry
- **Output:** ordered exact direct inherited-preset bindings
- **Responsibility:** Resolve every directly pinned package identity/version exactly once,
  rejecting missing, conflicting, or duplicate references without traversing or validating the
  composition graph.

## `BuildProjectToolchainLayerAction`

- **Input:** exact layer descriptor, schema-valid project layer, ordered direct inherited-preset
  bindings, configured environments, and all schema/inheritance evidence
- **Output:** identity-free project-toolchain-layer candidate
- **Responsibility:** Bind the exact source, environments, direct inherited preset
  identities/versions, and validated overrides without assigning a bootstrap-component identity
  or compiling another policy.

## `ValidateProjectToolchainLayerAction`

- **Input:** project-toolchain-layer candidate, exact principles/preset roots, complete preset
  registry, configured environments, closed merge-operator/type registry, and all
  source/schema/inheritance evidence
- **Output:** project-toolchain-layer evidence
- **Responsibility:** Prove exact source/root ownership, total configured-environment and
  direct-inheritance joins, and that every override names one registered field/operator with a
  schema-compatible operand; perform no composition and make no claim that the eventual merged
  result preserves locked safety rules.

## `BuildPrincipleIdLedgerAction`

- **Input:** validated bootstrap-root registry and optional prior validated principle
  registry/ID ledger
- **Output:** current principle ID ledger
- **Responsibility:** Initialize every namespace at one, or retain prior next
  ordinals/tombstones for refresh; bind it to the already available bootstrap-root registry.

## `ValidatePrincipleIdLedgerAction`

- **Input:** current/optional prior ledgers and every retained/new/retired principle identity
- **Output:** principle-ID-ledger evidence
- **Responsibility:** Prove direct-equality retention, monotonic per-namespace allocation, total
  tombstone accounting, no reuse, and exact prior/successor joins.

## `ParsePrincipleIdLedgerAction`

- **Input:** bounded canonical ledger bytes
- **Output:** unvalidated principle ID ledger
- **Responsibility:** Parse one persisted multi-namespace ledger without trusting ownership or
  ordinals.

## `SerializePrincipleIdLedgerAction`

- **Input:** validated final principle ID ledger
- **Output:** canonical ledger bytes
- **Responsibility:** Serialize ownership, next ordinals, and tombstones in namespace order.

## `BuildPrincipleCaptureBudgetSessionAction`

- **Input:** bootstrap-attempt identity and configured/hard entry/source-byte/time/memory/chunk
  ceilings
- **Output:** run-local provisional capture-budget session
- **Responsibility:** Initialize bounded provisional reservations/counters after inventory-entry
  IDs exist; this session is never persisted as canonical authority.

## `ValidatePrincipleCaptureBudgetSessionAction`

- **Input:** complete provisional session, complete classified/sorted inventory, semantic-source
  capture observations, and hard ceilings
- **Output:** closed session evidence
- **Responsibility:** Prove exactly one terminal provisional reservation per validated
  semantic-Markdown regular-file entry, no reservation or semantic read for the mechanical
  `toolchain.yaml` member, directories, or blocking entries, exact totals, and no unaccounted
  semantic-source read.

## `AssignPrincipleBudgetLedgerStateIdAction`

- **Input:** complete closed provisional session, captured owner/byte set, optional prior closed
  budget ledger, and current principle ID ledger
- **Output:** retained/new principle-budget-ledger identity plus successor ledger
- **Responsibility:** After capture, retain the prior identity only when policy, owner set,
  terminal outcomes, and direct bytes all match; otherwise allocate once in
  `budget_ledger_state`.

## `AssignPrincipleReservationIdAction`

- **Input:** one provisional reservation in canonical inventory order, optional exact prior
  reservation for the same retained entry, and current candidate ledger ordinal/tombstones
- **Output:** retained/new stable reservation ID plus next ordinal/tombstones
- **Responsibility:** Retain only the exact prior owner/outcome/byte binding; otherwise consume
  one monotonic reservation ordinal.

## `RetireRemovedPrincipleReservationAction`

- **Input:** one unmatched prior reservation and current candidate tombstones
- **Output:** next reservation tombstones
- **Responsibility:** Retire exactly one removed/superseded reservation ID and never make it
  reusable.

## `BuildPrincipleSourceBudgetLedgerAction`

- **Input:** chosen identity, validated complete provisional session, complete
  provisional-to-stable reservation map, next reservation ordinal/tombstones, optional prior
  ledger, and successor principle ID ledger
- **Output:** immutable candidate principle-budget ledger
- **Responsibility:** Assemble stable retained/new/retired canonical reservations with exact
  totals in inventory order; perform no allocation or retirement itself and preserve no
  bootstrap-attempt identity.

## `EnumeratePrincipleSourcesAction`

- **Input:** principles-root capability and entry/depth/time ceilings
- **Output:** bounded unordered raw principles-root inventory
- **Responsibility:** Enumerate every encountered directory, regular file, link, and special
  node without following, filtering, sorting, assigning IDs, or interpreting text; the exact
  toolchain file remains present for total accounting.

## `ClassifyPrinciplesRootEntryAction`

- **Input:** one raw inventory entry, exact project-toolchain descriptor, and locked
  semantic-source policy
- **Output:** mechanical-toolchain member, semantic-Markdown candidate, directory, or blocking
  diagnostic
- **Responsibility:** Classify exact `toolchain.yaml` separately, admit only normalized `*.md`
  regular files to semantic capture, and reject aliases, unsupported regular files, links, and
  special nodes.

## `ValidatePrincipleSourcePathAction`

- **Input:** one semantic-Markdown candidate and bootstrap-root/portable-filesystem policy
- **Output:** contained semantic-source path evidence
- **Responsibility:** Validate the engine-owned relative Markdown path, normalization,
  containment, representability, and non-aliasing without exposing a project-operation
  capability or admitting `toolchain.yaml`.

## `ValidatePrincipleInventoryCollisionAction`

- **Input:** complete raw inventory and all path evidence
- **Output:** collision evidence
- **Responsibility:** Reject duplicate, normalization-equivalent, case-fold, and portable-name
  collisions.

## `SortPrincipleInventoryAction`

- **Input:** collision-valid raw inventory
- **Output:** stable ordered inventory
- **Responsibility:** Sort once by normalized Unicode-scalar relative path; assign no IDs.

## `AssignPrincipleInventoryEntryIdAction`

- **Input:** one ordered position, optional directly equal prior entry, and current principle ID
  ledger
- **Output:** retained/new inventory-entry identity plus successor ledger
- **Responsibility:** Retain only an exact normalized-path/node/metadata match; otherwise
  allocate once in `inventory_entry`.

## `BuildPrincipleInventoryEntryAction`

- **Input:** entry identity, observed metadata, and path evidence/diagnostic
- **Output:** immutable principle inventory entry
- **Responsibility:** Record one encountered node without decoding or categorizing content.

## `ReservePrincipleSourceBytesAction`

- **Input:** one contained semantic-Markdown inventory entry with classification/path evidence
  and current provisional capture-budget session
- **Output:** provisional reservation and next session
- **Responsibility:** Reserve that semantic source's reported bytes once or emit a closed budget
  diagnostic; reject the mechanical `toolchain.yaml` member and every non-semantic entry.

## `ClassifyPrincipleCategoryFromFilenameAction`

- **Input:** one validated filename and configured basename-hint table
- **Output:** known or custom category hint
- **Responsibility:** Use only the filename mapping; never inspect body text to choose a
  category.

## `CapturePrincipleSourceAction`

- **Input:** one contained semantic-Markdown inventory entry, exact reservation,
  classification/path evidence, and same no-follow descriptor identity
- **Output:** raw immutable-byte capture observation
- **Responsibility:** Read that bounded semantic source exactly once and report
  entry/descriptor/length/byte-handle facts without assigning a source or source-map ID; never
  read `toolchain.yaml` through the semantic principle lane.

## `CommitPrincipleSourceDebitAction`

- **Input:** provisional reservation, stable complete read observation, and current
  capture-budget session
- **Output:** committed debit and next session
- **Responsibility:** Commit actual bytes only when identity/type/length and reservation remain
  exact.

## `ReleasePrincipleSourceReservationAction`

- **Input:** failed/changed read observation, provisional reservation, and current
  capture-budget session
- **Output:** released reservation and next session
- **Responsibility:** Close one failed reservation without capturing partial text.

## `AssignPrincipleSourceIdAction`

- **Input:** stable raw capture observation, committed debit, optional directly equal prior
  source, and current principle ID ledger
- **Output:** retained/new principle-source identity plus successor ledger
- **Responsibility:** Retain only after direct raw-byte and metadata equality; otherwise
  allocate once in `source`, independent of filename/text.

## `BuildPrincipleCapturedSourceAction`

- **Input:** source identity, stable raw capture observation, exact inventory entry, and
  committed debit
- **Output:** canonical captured principle source
- **Responsibility:** Bind the immutable bytes to the engine source identity after the
  read/debit succeeds; assign no source-map ID.

## `DecodePrincipleFreeTextAction`

- **Input:** canonical captured source and UTF-8 policy
- **Output:** decoded raw text plus byte/line source-map candidate
- **Responsibility:** Accept arbitrary free text; require no front matter, headings, template
  expansion, placeholder resolution, or content schema.

## `AssignPrincipleSourceMapIdAction`

- **Input:** source identity, optional retained source/map join, and current principle ID ledger
- **Output:** retained/new principle-source-map identity plus successor ledger
- **Responsibility:** Retain only with the exact retained source; otherwise allocate once in
  `source_map`.

## `BuildPrincipleSourceMapAction`

- **Input:** source-map identity, decoded raw text, exact byte offsets, and line-boundary
  observations
- **Output:** immutable principle source map
- **Responsibility:** Bind every line/byte span to captured bytes without normalizing body text.

## `AssignPrincipleModuleIdAction`

- **Input:** source identity, optional retained source/module join, and current principle ID
  ledger
- **Output:** retained/new principle-module identity plus successor ledger
- **Responsibility:** Retain only an exact prior source/category mapping; otherwise allocate
  once in `module`; infer no meaning.

## `BuildPrincipleModuleAction`

- **Input:** module/source identities, filename category hint, exact blob/debit/source map
- **Output:** opaque principle module
- **Responsibility:** Bind free-text bytes to transport/category metadata only.

## `PartitionPrincipleTextAction`

- **Input:** one module/source map and chunk limits
- **Output:** deterministic boundary candidates
- **Responsibility:** Select whole-file/paragraph/line/byte transport boundaries without
  assigning semantic meaning; no-heading text remains valid.

## `AssignPrincipleChunkIdAction`

- **Input:** one stable boundary position, optional retained module/span join, and current
  principle ID ledger
- **Output:** retained/new principle-chunk identity plus successor ledger
- **Responsibility:** Retain only an exact module/span join; otherwise allocate once in `chunk`.

## `BuildPrincipleChunkAction`

- **Input:** chunk identity, module, exact source span, and captured bytes
- **Output:** immutable principle chunk
- **Responsibility:** Bind one exact raw span and boundary kind; summarize nothing.

## `BuildPrincipleEntryAccountAction`

- **Input:** one inventory entry and exactly one
  `directory_accounted`/`mechanical_toolchain_layer_excluded`/`blocking`/`captured_source`
  disposition with its classification and capture evidence
- **Output:** immutable entry-account record
- **Responsibility:** Account for every encountered entry once; bind the exact `toolchain.yaml`
  descriptor only to `mechanical_toolchain_layer_excluded`, bind captured sources only to
  validated semantic Markdown, and keep unsupported regular files, links, and special nodes
  blocking.

## `AssignPrincipleInventoryStateIdAction`

- **Input:** root identity, complete unidentified inventory content, optional prior inventory,
  closed budget ledger, and current principle ID ledger
- **Output:** retained/new inventory-state identity plus successor ledger
- **Responsibility:** Retain only when the complete canonical inventory projection compares
  directly equal; otherwise allocate once in `inventory_state`, never from paths, text, or a
  fingerprint.

## `BuildPrincipleInventoryStateAction`

- **Input:** inventory-state/root identities, exact project-toolchain-layer path identity and
  mechanical exclusion account, stable entries, closed semantic-source budget ledger, canonical
  captured sources, source maps, complete entry accounts, and final successor principle ID
  ledger
- **Output:** immutable principle inventory state
- **Responsibility:** Assemble restart-safe total root accounting while keeping the exact
  mechanical layer identity separate from semantic source/module/chunk content.

## `ValidatePrincipleInventoryStateAction`

- **Input:** inventory state, optional prior state, exact project-toolchain descriptor, and
  root/classification/path/collision/read/budget/source-map/ID-ledger evidence
- **Output:** inventory-state evidence
- **Responsibility:** Prove every encountered node has one terminal account, exact
  `toolchain.yaml` has exactly one mechanical exclusion and no semantic reservation/captured
  source/source map, every validated semantic Markdown file has one closed capture outcome,
  retained/new/retired identity rules hold, byte/span joins are exact, and no blocked or orphan
  source is accepted.

## `AssignPrincipleRegistryStateIdAction`

- **Input:** complete candidate content, optional prior registry, and current principle ID
  ledger
- **Output:** retained/new principle-registry identity/revision plus successor ledger
- **Responsibility:** Reuse the prior registry only under direct equality of every typed
  field/raw byte; otherwise allocate once in `registry_state`, without hashing content.

## `BuildPrincipleRegistryStateAction`

- **Input:** state identity, validated inventory state, final successor principle ID ledger,
  ordered modules/chunks, and category hints
- **Output:** principle-registry candidate
- **Responsibility:** Assemble the immutable source/allocation registry without compiling prose
  into rules.

## `ValidatePrincipleRegistryStateAction`

- **Input:** registry candidate, optional prior registry, inventory/source-map/budget/ID-ledger
  evidence, exact mechanical-toolchain exclusion account, and category table
- **Output:** principle-registry evidence
- **Responsibility:** Prove complete module/chunk/source/identity accounting, exact spans,
  unique IDs, filename-only category provenance, and that no semantic source, module, or chunk
  is owned by or references the mechanical `toolchain.yaml` member.

## `SelectApplicablePrinciplesAction`

- **Input:** exact registry, stage, environment, task/file kinds, and category-hint table
- **Output:** complete ordered chunk/span selection candidate
- **Responsibility:** Select all raw chunks in eligible categories in stable order; never assign
  an ID or use a model to rank/omit them.

## `AssignPrincipleSelectionIdAction`

- **Input:** exact immutable principle-registry revision, stage, validated
  `ImmutableUnitOwnerId`, and consumer ordinal
- **Output:** closed owner-local principle-selection identity tuple
- **Responsibility:** Construct and validate `(registry state/revision, stage, immutable unit
  owner, ordinal)`; use no allocator, prose, selected content, or process-local state.

## `BuildApplicablePrincipleSelectionAction`

- **Input:** selection identity, complete candidate, exact registry/stage/consumer bindings
- **Output:** applicable-principle selection
- **Responsibility:** Bind the selected chunks/spans without interpreting them.

## `ValidateApplicablePrincipleSelectionAction`

- **Input:** applicable selection and registry/category table
- **Output:** principle-selection evidence
- **Responsibility:** Prove registry/revision/category/chunk/span/consumer joins,
  all-eligible-chunk coverage and stable ordering without summary, omission or a size-fit gate.

## `BuildPrincipleGuidanceAction`

- **Input:** validated selection and exact raw source spans
- **Output:** complete immutable model guidance
- **Responsibility:** Render registered IDs/category hints/raw excerpts/citations; never reveal
  an operational source path.

## `ComparePrincipleRegistryStateAction`

- **Input:** persisted bound registry and freshly captured registry
- **Output:** direct equality/change evidence
- **Responsibility:** Compare complete typed metadata and raw bytes directly, never by
  fingerprint.

## `CreateRunMetadataAction`

- **Input:** invocation plus resolved environment
- **Output:** initial workflow metadata
- **Responsibility:** Create feature-run state without artifact hashes.

## `BuildIdentityFreeSupersetPathTokenGrammarCandidateAction`

- **Input:** validated grammar values plus run-local references to the exact
  environment/repository-fact/root candidates and optional already canonical reference authority
- **Output:** identity-free base-grammar blueprint
- **Responsibility:** Build the aggregate grammar value with no grammar ID and no
  not-yet-materialized cross-component ID; generic dependencies are represented only by typed
  candidate references.

## `ValidateIdentityFreeSupersetPathTokenGrammarCandidateAction`

- **Input:** grammar blueprint, candidate handles, component descriptors, and exact value-input
  evidence
- **Output:** grammar-blueprint evidence
- **Responsibility:** Prove every generic dependency is represented once by a
  type/ordinal-matching run-local handle, every specialized/fixed reference is already
  canonical, and no canonical generic ID or unresolved value is embedded.

## `BuildIdentityFreeCompiledEnginePolicyCandidateAction`

- **Input:** validated config/logging fragment, specialized preset/principle states,
  operations/renderers/readers/parsers/limits, the grammar blueprint handle, and run-local
  references to every required generic leaf component
- **Output:** identity-free compiled-policy blueprint
- **Responsibility:** Assemble the complete aggregate policy value without a policy ID and
  without copying a not-yet-materialized generic component ID.

## `ValidateIdentityFreeCompiledEnginePolicyCandidateAction`

- **Input:** compiled-policy blueprint, grammar-blueprint evidence, component descriptors, all
  referenced leaf candidates, and specialized/fixed authorities
- **Output:** compiled-policy-blueprint evidence
- **Responsibility:** Prove complete one-to-one dependency coverage, exact types/ordinals, an
  acyclic leaf-to-grammar-to-policy dependency order, and absence of canonical generic IDs or
  serializable handles.

## `BuildBootstrapOperationalCandidateAction`

- **Input:** validated config/root, specialized preset/principle candidates and ledgers,
  identity-free typed **leaf** payloads for the workflow-definition registry, project-toolchain
  layer, and every required
  root/project/discovery-file/repository-fact/dependency/file-intent/fact-transition/log-event/portability/environment/command
  component, the validated base-grammar and compiled-policy blueprints,
  operations/renderers/readers/parsers, and hard limits
- **Output:** noncanonical bootstrap operational candidate
- **Responsibility:** Assemble the complete handle/DataKey/schema-bound leaf and aggregate
  blueprints needed for selector resolution and deterministic reference preactivation; every
  generic canonical ID field and cross-component canonical generic ID is structurally absent.

## `ValidateBootstrapOperationalCandidateAction`

- **Input:** operational candidate, compiler-locked component-type/dependency registry, all leaf
  evidence, both aggregate-blueprint evidence records, and specialized ledger/capability
  evidence
- **Output:** validated bootstrap operational candidate
- **Responsibility:** Prove exactly one handle/payload/schema DataKey join per required
  singleton/ordered member, the closed acyclic leaf-to-grammar-to-policy graph, complete
  authority capability closure, disjoint specialized/owner-local/generic identity domains, and
  that no run-local handle is serializable, loggable as canonical, or model-visible.

## `AssignBootstrapComponentIdAction`

- **Input:** execution-local candidate bootstrap-authority-state ID, one exact component-type
  descriptor, and canonical component ordinal
- **Output:** owner-local bootstrap-component identity
- **Responsibility:** Construct `(bootstrapAuthorityStateId, componentTypeId, ordinal)` without
  consuming a state ledger, model scalar, content, or path.

## `MaterializeBootstrapCandidateComponentAction`

- **Input:** one validated typed **leaf** component candidate, matching handle/DataKey/schema
  evidence, and assigned owner-local bootstrap-component ID
- **Output:** identified canonical leaf component candidate plus its `materialized_leaf` binding
- **Responsibility:** Replace one run-local leaf handle with its authorized identity without
  changing the component value or assigning another ID; reject specialized preset/principle
  states and the aggregate grammar/policy blueprints, whose canonical values require
  materialized dependencies.

## `BindDerivedBootstrapCandidateComponentAction`

- **Input:** one validated aggregate blueprint handle, its assigned owner-local component ID,
  the validated canonical grammar or compiled-policy value built from it, and its complete
  dependency-resolution evidence
- **Output:** one `validated_derived_aggregate` binding
- **Responsibility:** Bind one derived aggregate handle to the exact canonical component it
  produced without constructing, validating, or changing that value.

## `BuildBootstrapCandidateDependencyResolutionMapAction`

- **Input:** validated operational candidate, exact binding records produced so far, and one
  requested closed phase (`leaf_dependencies`, `base_grammar_resolved`, or `complete`)
- **Output:** phase-discriminated dependency-resolution-map candidate
- **Responsibility:** Assemble bindings and the phase's exact unresolved-aggregate handle list
  without resolving, validating, or assigning an identity.

## `ValidateBootstrapCandidateDependencyResolutionMapAction`

- **Input:** map candidate, validated operational candidate, immediately prior validated phase
  when applicable, component descriptors, and all binding/value evidence
- **Output:** validated phase-specific dependency-resolution map or diagnostic
- **Responsibility:** Prove the exact bootstrap attempt/state owner,
  handle/type/ordinal/identity joins, no duplicate/orphan/specialized binding, strict phase
  extension, leaf-only coverage at phase one, grammar inclusion at phase two, and total
  one-to-one generic-handle coverage with no unresolved handle at `complete`.

## `AssembleCompiledEnginePolicyAction`

- **Input:** assigned owner-local `compiled_engine_policy` component ID, validated identity-free
  compiled-policy blueprint and validated `base_grammar_resolved` dependency-resolution map,
  exact config location, validated bootstrap-root registry/config including the canonical
  compiled feature-logging fragment, materialized workflow-definition registry and
  project-toolchain layer, toolchain-preset registry, materialized environment/portability/root
  registries, operations/renderer, readers/parsers,
  command/dependency/file-intent/fact-transition/log-event registries, validated
  principle-registry state, limits, and already materialized/validated base path-token grammar
- **Output:** identified compiled-engine-policy candidate
- **Responsibility:** Resolve the blueprint's references and bind every independently validated
  bootstrap authority—including the workflow-definition and project-toolchain identities—the
  restart-reconstructible logging fragment, and its owner-local policy ID; perform no
  validation, discovery, or generic state allocation and retain no handle.

## `ValidateCompiledEnginePolicyAction`

- **Input:** compiled-engine-policy candidate and required-authority schema
- **Output:** compiled-policy evidence
- **Responsibility:** Prove all IDs/versions resolve exactly once and every configured
  environment has complete required capabilities.

## `AssignBootstrapAuthorityStateIdAction`

- **Input:** feature scope, validated current feature `StateIdLedger`, and matching single-use
  namespace capability
- **Output:** bootstrap-authority-state reservation plus successor ledger
- **Responsibility:** Reserve one engine state ID without hashing authority content.

## `BuildBootstrapAuthorityStateCoreAction`

- **Input:** state identity, validated compiled policy, exact
  bootstrap-root/workflow-definition/project-toolchain/toolchain-preset/root/project/portability/environment/discovery-file/repository-fact/command/dependency/file-intent/fact-transition/log-event
  registries, principle-registry state, and base grammar
- **Output:** unlinked bootstrap-authority core candidate
- **Responsibility:** Bundle the identified component values under the prospective state ID
  without fabricating parent/change evidence or yet producing a canonical state.

## `ValidateBootstrapAuthorityStateCoreAction`

- **Input:** unlinked core candidate and all component evidence
- **Output:** bootstrap-authority-core evidence
- **Responsibility:** Prove component IDs/values and grammar bindings are exact, internally
  closed, and all owner-local generic component IDs name the prospective authority ID.

## `CompareBootstrapAuthorityStateAction`

- **Input:** freshly validated bootstrap candidate, current persisted bootstrap authority,
  locked component-type/ordinal/dependency registry, and validated aggregate-blueprint
  projections
- **Output:** closed `BootstrapAuthorityComparisonResult`:
  `BootstrapCandidateDirectEqualityEvidence` or run-local `BootstrapCandidateChangeEvidence`
- **Responsibility:** Compare by stable `(componentTypeId, componentOrdinal)` and direct
  canonical-ID-erased typed value.
- Resolve aggregate blueprint references by candidate coordinate rather than by nonexistent
  successor IDs, recording current identity plus a closed candidate handle/specialized-state
  reference for each difference.
- Produce complete equality evidence only when every projected coordinate is equal; never
  fabricate an empty change plan or successor ID, compare a hash, or persist a handle.

## `ClassifyBootstrapAuthorityChangeAction`

- **Input:** exact run-local candidate-change evidence including direct changed-subfield
  evidence, current feature `boundWorkflowIds`, and locked component/subfield-to-impact registry
- **Output:** candidate `BootstrapAuthorityChangePlan`
- **Responsibility:** Assign exactly one coordinate record to every changed component and a
  nonempty ordered set of unique `(impact, rule, changedFieldSelectors, evidence)` entries
  inside it; compare each bound `WorkflowId` only by its stable compiled semantic authority,
  excluding source inventory ordinal, registry identity, and validation evidence, so only a
  missing/semantically changed bound graph is administrative; retain aggregate-component
  secondary impacts, derive complete obligations, and select the earliest owner by fixed
  dominance `administrative > reference ingestion > specification contract > planning >
  runtime-only`; mixed changes never use last-match-wins.

## `ValidateBootstrapAuthorityChangePlanAction`

- **Input:** candidate change plan, exact candidate component/subfield differences, locked
  impact/dominance/obligation registries
- **Output:** validated bootstrap-authority change plan
- **Responsibility:** Prove total one-to-one coordinate assignment, total changed-subfield
  coverage within each coordinate, nonempty unique/ranked impacts, impact-rule/evidence
  validity, no extra/missing field or coordinate, dominant/earliest-owner correctness,
  administrative dominance, unioned downstream obligations, and `transitionFeatureLogging` iff
  any nested logging impact exists.

## `RouteBootstrapAuthorityChangeAction`

- **Input:** exactly one comparison branch—either `BootstrapCandidateDirectEqualityEvidence`, or
  its exact `BootstrapCandidateChangeEvidence` plus validated change plan—together with current
  workflow stage/authority IDs, open clarification projection, descendant state/approval set,
  and implementation watermark
- **Output:** closed bootstrap-authority change route plan
- **Responsibility:** Select equality reuse only from the equality branch; otherwise select
  explicit planning deferral, administrative block, compatible refresh, reference ingestion,
  owning Spec/Plan output, or rework/reconciliation from the validated change plan and locked
  `(earliestOwner,currentStage,open-stage,watermark)` table.
- Perform no mutation and never fabricate an empty plan for equality.

## `ValidateBootstrapAuthorityChangeRouteAction`

- **Input:** route candidate, the same closed equality-or-change comparison branch, current
  workflow/clarification/descendant/runtime authorities, and locked route table
- **Output:** bootstrap-route evidence
- **Responsibility:** Prove equality-coordinate coverage or preserve every changed-plan
  obligation, choose the earliest legal owner, include committed-runtime reconciliation when
  required, and never bypass an open clarification gate.
- Require `NoBootstrapAuthorityChangeRoute` only with complete direct-equality evidence; require
  `DeferredPlanningBootstrapRoute` only with a planning-owned change in `specifying |
  spec_clarification_pending`, no adoption, and a complete fresh PlanInput-gate recheck before
  any plan model call.

## `BindMaterializedBootstrapChangeEvidenceAction`

- **Input:** run-local candidate-change evidence, its exact validated change plan, validated
  `complete` dependency-resolution map, validated successor core candidate/evidence, and current
  authority
- **Output:** canonical materialized bootstrap-change evidence
- **Responsibility:** Replace every leaf or aggregate candidate handle with the exact
  owner-local successor identity, preserve already identified preset/principle references,
  retain removed/current identities and comparison evidence, and prove the resulting ordered
  differences exactly explain the current-to-successor core change.

## `ValidateMaterializedBootstrapChangeEvidenceAction`

- **Input:** canonical materialized change evidence, current authority, validated successor
  core, locked component/impact registries, and all direct comparison evidence
- **Output:** bootstrap-change validation evidence
- **Responsibility:** Prove total one-to-one coordinate coverage, correct added/modified/removed
  identities, exact validated change-plan equality, no handle/run-local field, and no
  unexplained component value or pointer change.

## `BuildInitialBootstrapAuthorityStateAction`

- **Input:** validated initial core and compiler-locked initial-lineage variant
- **Output:** initial bootstrap-authority state candidate
- **Responsibility:** Wrap one new feature's core with `kind: initial`; accept no parent or
  change evidence.

## `BuildSuccessorBootstrapAuthorityStateAction`

- **Input:** validated successor core, exact current parent authority, and validated
  materialized change evidence
- **Output:** successor bootstrap-authority state candidate
- **Responsibility:** Attach the parent ID and total change evidence only after both core and
  evidence validate; change no component value.

## `ValidateBootstrapAuthorityStateAction`

- **Input:** initial/successor state candidate, core evidence, optional exact parent authority,
  and optional materialized-change evidence
- **Output:** bootstrap-authority evidence
- **Responsibility:** Prove the closed lineage variant, exact ID/core equality, parent/evidence
  presence together for successors, current/successor joins, and no parent cycle.

## `ResolveBootstrapAuthorityStatePathAction`

- **Input:** bootstrap-state identity and workflow bootstrap-authority collection root
- **Output:** versioned engine-owned state path
- **Responsibility:** Derive one immutable state path without accepting a path from
  config/model/user.

## `ParseBootstrapAuthorityStateAction`

- **Input:** bounded raw canonical authority bytes and recorded serializer contract
- **Output:** unvalidated bootstrap-authority candidate
- **Responsibility:** Parse one persisted immutable authority state; trust no nested component
  ID/value.

## `SerializeBootstrapAuthorityStateAction`

- **Input:** validated bootstrap-authority state
- **Output:** canonical authority bytes
- **Responsibility:** Serialize one restart authority under the recorded renderer/serializer
  contract.
