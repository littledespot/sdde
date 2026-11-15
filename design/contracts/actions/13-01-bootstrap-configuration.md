# 13.1 Bootstrap and configuration actions

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.

One entry per registered operation or engine-routine step. A registered operation's **Reads**,
**Writes** and **Side effect** are its `NodeContract`; a routine step states what it takes and
returns as typed values, and its **Side effect**. Entries marked "Proposed, no code" name a
responsibility no code registers.
[F0003](../../features/F0003-ToolChainService.md#3-closed-loading-and-publication-contract)
owns the current toolchain shapes.

> **ADR 0032.** The engine-startup and provider-bootstrap operations are the typed steps of two
> [engine routines](../../decisions/0032-engine-routines.md), each keeping its rules and taking
> only the port it uses: [`startup_routine.zig`](../../../src/application/startup_routine.zig),
> reached only from the composition root, and
> [`model_provider_bootstrap_routine.zig`](../../../src/application/model_provider_bootstrap_routine.zig),
> reached only through the runner-owned provider-bootstrap binding. Each step's failure maps to
> its fixed public code (`code(step)`), including allocation failure and deadline exhaustion;
> explicit cancellation stays distinct. A failed run records the step it stopped at.

## Engine configuration

## `locateConfig` (startup step `locate_config`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig)
- **Takes:** the engine-config locator port · **Returns:** the exact config file · **Side effect:** `filesystem_read`
- **Does:** Takes the invocation working directory as the project root and resolves only its
  exact `.sddtoolkit.json` child; never inspects an ancestor or descendant or accepts another name.
- **Rejects:** `EngineConfigReadError` (`ENGINE_CONFIG_READ_ERROR`) for every unsafe or unreadable
  result; reports step `locate_config`.

## `readConfig` (startup step `read_config`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig)
- **Takes:** the exact config file · **Returns:** the raw config bytes · **Side effect:** `filesystem_read`
- **Does:** Reads that one file completely, at most 1,048,576 bytes.
- **Rejects:** `EngineConfigReadError` for every read or limit failure; reports step `read_config`.

## `decodeConfig` (startup step `decode_config`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig); logic in [`src/domain/engine_config_decode.zig`](../../../src/domain/engine_config_decode.zig)
- **Takes:** the raw config bytes · **Returns:** the owned engine configuration · **Side effect:** `none`
- **Does:** Decodes the bytes strictly into the closed configuration contract
  ([§9](../09-configuration.md)); compiles no domain policy.
- **Rejects:** `EngineConfigParseError` (`ENGINE_CONFIG_PARSE_ERROR`) for malformed JSON,
  trailing content, unknown fields and wrong wire kinds; reports step `decode_config`.

## Bootstrap roots

[F0004](../../features/F0004-BootstrapRootRegistryService.md) owns the root registry.

## `validateRootPaths` (startup step `validate_root_paths`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig); logic in [`src/domain/bootstrap_root_derivation.zig`](../../../src/domain/bootstrap_root_derivation.zig)
- **Takes:** the configured paths and the platform path policy · **Returns:** the seven normalized configured paths · **Side effect:** `none`
- **Does:** Normalizes each configured directory path under the portable path rules.
- **Rejects:** `BootstrapRootResolutionError` (`BOOTSTRAP_ROOT_RESOLUTION_ERROR`) for an empty,
  absolute, drive, empty-segment, `..`, backslash, encoded-separator, reserved-name, non-ASCII or
  over-limit path; reports step `validate_root_paths`.

## `validateProviderPath` (startup step `validate_provider_path`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig); logic in [`src/domain/bootstrap_root_derivation.zig`](../../../src/domain/bootstrap_root_derivation.zig)
- **Takes:** the configured provider-document path and the platform path policy · **Returns:** the normalized provider-document path · **Side effect:** `none`
- **Does:** Normalizes the provider-document path under the same rules and requires the exact
  basename `.sddproviders.json`.
- **Rejects:** `BootstrapRootResolutionError`; reports step `validate_provider_path`.

## `resolveRoots` (startup step `resolve_roots`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig); logic in [`src/domain/bootstrap_root_derivation.zig`](../../../src/domain/bootstrap_root_derivation.zig)
- **Takes:** the exact config file's canonical project root and the normalized paths · **Returns:** the seven configured root candidates · **Side effect:** `none`
- **Does:** Joins each normalized directory path to the project root without following aliases
  or deriving children.
- **Rejects:** `BootstrapRootResolutionError`; reports step `resolve_roots`.

## `resolveProviderPath` (startup step `resolve_provider_path`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig); logic in [`src/domain/bootstrap_root_derivation.zig`](../../../src/domain/bootstrap_root_derivation.zig)
- **Takes:** the canonical project root and the normalized provider-document path · **Returns:** the provider-document path candidate · **Side effect:** `none`
- **Does:** Joins the provider-document path to the project root the same way.
- **Rejects:** `BootstrapRootResolutionError`; reports step `resolve_provider_path`.

## `validateRoots` (startup step `validate_roots`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig)
- **Takes:** the root-inspector port and the configured root candidates · **Returns:** the validated configured roots (root capabilities) · **Side effect:** `filesystem_read`
- **Does:** Inspects each candidate through the root-inspector port and proves containment,
  access class and permitted existence and type before granting a root capability.
- **Rejects:** `BootstrapRootResolutionError`; `Cancelled`; reports step `validate_roots`.

## `buildRegistryId` (startup step `build_registry_id`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig); logic in [`src/domain/bootstrap_root_derivation.zig`](../../../src/domain/bootstrap_root_derivation.zig)
- **Takes:** the canonical project root · **Returns:** the bootstrap root registry ID · **Side effect:** `none`
- **Does:** Builds the registry identity from the canonical project root and contract version;
  inspects no content.
- **Rejects:** `BootstrapRootRegistryInvalid` (`BOOTSTRAP_ROOT_REGISTRY_INVALID`); reports step
  `build_registry_id`.

## `buildRootRegistry` (startup step `build_root_registry`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig); logic in [`src/domain/bootstrap_root_derivation.zig`](../../../src/domain/bootstrap_root_derivation.zig)
- **Takes:** the registry ID, the exact config file, the validated configured roots and the provider-document path candidate · **Returns:** the bootstrap root registry candidate · **Side effect:** `none`
- **Does:** Assembles the seven configured directory roots and the provider-document location;
  holds no preset-derived, generated or discovered root.
- **Rejects:** `BootstrapRootRegistryInvalid`; reports step `build_root_registry`.

## `validateRootRegistry` (startup step `validate_root_registry`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig); logic in [`src/domain/bootstrap_root_registry.zig`](../../../src/domain/bootstrap_root_registry.zig)
- **Takes:** the root registry candidate · **Returns:** the validated root registry owner · **Side effect:** `none`
- **Does:** Requires the seven directory roles and the `providers` file role exactly once.
- **Rejects:** `BootstrapRootRegistryInvalid` for a missing, unknown, duplicate, escaping or
  illegally overlapping location, with only the declared archive nesting exception; reports step
  `validate_root_registry`.

## Provider configuration

[F0006](../../features/F0006-LLMProviderInterface.md) and
[F0008](../../features/F0008-LLMProviderConfigService.md) own the provider catalogue. These are
the steps of the provider-bootstrap routine.

## `locateConfig` (provider routine step `locate_config`)

- **Owner:** [`src/application/model_provider_bootstrap_routine.zig`](../../../src/application/model_provider_bootstrap_routine.zig)
- **Takes:** the provider-config locator port and the root registry's provider-document path capability · **Returns:** the exact provider-config file · **Side effect:** `filesystem_read`
- **Does:** Opens only the configured no-follow regular `.sddproviders.json`; reads no bytes and
  searches for no other file.
- **Rejects:** `LLMProviderConfigReadError` (`LLM_PROVIDER_CONFIG_READ_ERROR`), which also covers
  deadline exhaustion; `Cancelled`; reports step `locate_config`.

## `readConfig` (provider routine step `read_config`)

- **Owner:** [`src/application/model_provider_bootstrap_routine.zig`](../../../src/application/model_provider_bootstrap_routine.zig)
- **Takes:** the exact provider-config file · **Returns:** the raw provider-config bytes · **Side effect:** `filesystem_read`
- **Does:** Captures the opened file once under F0008's 1,048,576-byte limit.
- **Rejects:** `LLMProviderConfigReadError`, which also covers deadline exhaustion; `Cancelled`;
  reports step `read_config`.

## `decodeConfig` (provider routine step `decode_config`)

- **Owner:** [`src/application/model_provider_bootstrap_routine.zig`](../../../src/application/model_provider_bootstrap_routine.zig); logic in [`src/domain/llm_provider_document_decode.zig`](../../../src/domain/llm_provider_document_decode.zig)
- **Takes:** the raw provider-config bytes · **Returns:** the owned raw provider document · **Side effect:** `none`
- **Does:** Enforces strict UTF-8 JSON, the closed catalogue object, integer-only numbers,
  nesting and collection limits, and provider/model identity syntax; leaves each `config`
  untrusted.
- **Rejects:** `LLMProviderConfigParseError` (`LLM_PROVIDER_CONFIG_PARSE_ERROR`); reports step
  `decode_config`.

## `buildRegistry` (provider routine step `build_registry`)

- **Owner:** [`src/application/model_provider_bootstrap_routine.zig`](../../../src/application/model_provider_bootstrap_routine.zig); logic in [`src/domain/llm_provider_registry_build.zig`](../../../src/domain/llm_provider_registry_build.zig)
- **Takes:** the raw provider document and the registered provider contracts · **Returns:** the provider registry candidate · **Side effect:** `none`
- **Does:** Joins every entry to one compiled contract (an exact model, or a Bedrock entry's
  family) and decodes its closed configuration variant.
- **Rejects:** `LLMProviderRegistryInvalid` (`LLM_PROVIDER_REGISTRY_INVALID`) for an unsupported,
  duplicate, partial or inconsistent entry; no partial registry; reports step `build_registry`.

## `validateRegistry` (provider routine step `validate_registry`)

- **Owner:** [`src/application/model_provider_bootstrap_routine.zig`](../../../src/application/model_provider_bootstrap_routine.zig); logic in [`src/domain/llm_provider_registry.zig`](../../../src/domain/llm_provider_registry.zig)
- **Takes:** the provider registry candidate and the registered provider contracts · **Returns:** the validated provider registry owner · **Side effect:** `none`
- **Does:** Rejoins every entry and proves bounds, unique identities, configuration variants,
  contract facts and deterministic order for the whole catalogue.
- **Rejects:** `LLMProviderRegistryInvalid`; reports step `validate_registry`.

## `validateAllowlist` (provider routine step `validate_allowlist`)

- **Owner:** [`src/application/model_provider_bootstrap_routine.zig`](../../../src/application/model_provider_bootstrap_routine.zig); logic in [`src/domain/repository_model_allowlist.zig`](../../../src/domain/repository_model_allowlist.zig)
- **Takes:** the configured `models` section, the configured temperatures and the validated provider registry · **Returns:** the repository model allowlist owner · **Side effect:** `none`
- **Does:** Resolves every `models.slots` tuple and option exactly, keeping slot identity, entry
  identity and validated options; several slots may share an entry, and unused entries gain no
  authority.
- **Rejects:** `LLMProviderModelBindingInvalid` (`LLM_PROVIDER_MODEL_BINDING_INVALID`); reports
  step `validate_allowlist`.

## Workflow authority and registry

[F0005](../../features/F0005-WorkflowDefinitionRegistryService.md) owns the definition registry.

## `buildWorkflowLayout` (startup step `build_workflow_layout`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig); logic in [`src/domain/workflow_authority_inventory_build.zig`](../../../src/domain/workflow_authority_inventory_build.zig)
- **Takes:** the validated root registry · **Returns:** the workflow authority layout · **Side effect:** `none`
- **Does:** Derives the `paths.workflows` inventory scope and the reserved `features/` child,
  whose root entry is accounted while its descendants are excluded; reads nothing.
- **Rejects:** none; only a deadline stop after it reports step `build_workflow_layout`
  (`WORKFLOW_AUTHORITY_INVENTORY_INVALID`).

## `enumerateWorkflowResources` (startup step `enumerate_workflow_resources`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig)
- **Takes:** the workflow-enumerator port and the layout · **Returns:** the raw inventory entries · **Side effect:** `filesystem_read`
- **Does:** Enumerates every directory, file, link and special node in scope without following
  links, filtering, parsing or assigning identities.
- **Rejects:** `WorkflowAuthorityInventoryInvalid`; `Cancelled`; reports step
  `enumerate_workflow_resources`.

## `normalizeWorkflowEntries` (startup step `normalize_workflow_entries`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig); logic in [`src/domain/workflow_authority_inventory_build.zig`](../../../src/domain/workflow_authority_inventory_build.zig)
- **Takes:** the raw inventory entries · **Returns:** the normalized entries, sorted by normalized path · **Side effect:** `none`
- **Does:** Normalizes each root-relative path, rejects collisions and sorts the inventory by
  normalized path.
- **Rejects:** `WorkflowAuthorityInventoryInvalid` for an escaping, absolute, empty or colliding
  path; reports step `normalize_workflow_entries`.

## `buildWorkflowAccounts` (startup step `build_workflow_accounts`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig); logic in [`src/domain/workflow_authority_inventory_build.zig`](../../../src/domain/workflow_authority_inventory_build.zig)
- **Takes:** the normalized entries · **Returns:** the entry account set · **Side effect:** `none`
- **Does:** Gives each entry exactly one disposition: directory, reserved child, definition
  (`*.workflow.yaml`) or declared-resource candidate.
- **Rejects:** `WorkflowAuthorityInventoryInvalid` for a link, special node or reserved-child
  conflict; reports step `build_workflow_accounts`.

## `buildWorkflowInventory` (startup step `build_workflow_inventory`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig); logic in [`src/domain/workflow_authority_inventory_build.zig`](../../../src/domain/workflow_authority_inventory_build.zig)
- **Takes:** the layout, the normalized entries and the account set · **Returns:** the candidate inventory · **Side effect:** `none`
- **Does:** Assembles the inventory and its accounting without dropping a blocking entry.
- **Rejects:** none.

## `validateWorkflowInventory` (startup step `validate_workflow_inventory`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig); logic in [`src/domain/workflow_authority_inventory_build.zig`](../../../src/domain/workflow_authority_inventory_build.zig)
- **Takes:** the candidate inventory · **Returns:** `ValidatedInventory`, the only form later steps accept · **Side effect:** `none`
- **Does:** Proves contiguous ordinals, one terminal account per entry, the reserved child's
  disposition and the absence of blocking entries.
- **Rejects:** `WorkflowAuthorityInventoryInvalid`; reports step `validate_workflow_inventory`.

## `captureWorkflows` (startup step `capture_workflows`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig)
- **Takes:** the workflow-capturer port and the `ValidatedInventory` · **Returns:** the definition captures · **Side effect:** `filesystem_read`
- **Does:** Reads each definition once through its descriptor, bound to its inventory ordinal;
  infers no workflow ID from a filename.
- **Rejects:** `WorkflowDefinitionReadError` (`WORKFLOW_DEFINITION_READ_ERROR`); `Cancelled`;
  reports step `capture_workflows`.

## `parseWorkflows` (startup step `parse_workflows`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig)
- **Takes:** the workflow-definition parser port and the definition captures · **Returns:** the raw workflow definitions · **Side effect:** `none`
- **Does:** Parses each captured definition through the definition-parser port without applying
  policy or resolving operations.
- **Rejects:** `WorkflowDefinitionParseError` (`WORKFLOW_DEFINITION_PARSE_ERROR`); reports step
  `parse_workflows`.

## `validateWorkflowSchema` (startup step `validate_workflow_schema`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig); logic in [`src/domain/workflow_definition_schema.zig`](../../../src/domain/workflow_definition_schema.zig)
- **Takes:** the raw workflow definitions · **Returns:** the validated declarative definitions · **Side effect:** `none`
- **Does:** Applies the closed workflow-definition schema: workflow ID, version, logging
  shortcode, invocation and step operations, parameters, typed transitions and policy profile.
- **Rejects:** `WorkflowDefinitionSchemaInvalid` (`WORKFLOW_DEFINITION_SCHEMA_INVALID`) for
  scripts, adapter selectors, raw paths or commands, malformed or duplicate step IDs, unknown
  fields and capability claims; reports step `validate_workflow_schema`.

## `resolveWorkflowResources` (startup step `resolve_workflow_resources`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig); logic in [`src/domain/workflow_resource_binding.zig`](../../../src/domain/workflow_resource_binding.zig)
- **Takes:** the `ValidatedInventory` and the validated definitions · **Returns:** the resource manifest · **Side effect:** `none`
- **Does:** Binds every declared resource to exactly one non-definition file in the inventory;
  reads nothing.
- **Rejects:** `WorkflowAuthorityInventoryInvalid` for an undeclared file or an escaping,
  missing, ambiguous or doubly classified resource; reports step `resolve_workflow_resources`.

## `captureWorkflowResources` (startup step `capture_workflow_resources`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig)
- **Takes:** the workflow-capturer port, the `ValidatedInventory` and the resource manifest · **Returns:** the resource captures · **Side effect:** `filesystem_read`
- **Does:** Reads each bound resource once and proves its identity, type and length unchanged;
  infers no behaviour from a filename.
- **Rejects:** `WorkflowResourceReadError` (public code `WORKFLOW_DEFINITION_READ_ERROR`);
  `Cancelled`; reports step `capture_workflow_resources`.

## `validateWorkflowOperations` (startup step `validate_workflow_operations`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig)
- **Takes:** the composition root's operation registry · **Returns:** `ValidatedOperations`, which compilation requires · **Side effect:** `none`
- **Does:** Validates the composition root's operation registry before any definition is compiled.
- **Rejects:** `WorkflowOperationRegistryInvalid` (public code `WORKFLOW_GRAPH_COMPILE_INVALID`);
  reports step `validate_workflow_operations`.

## `compileWorkflows` (startup step `compile_workflows`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig); logic in [`src/domain/workflow_graph_compilation.zig`](../../../src/domain/workflow_graph_compilation.zig)
- **Takes:** the result-schema compiler port, `ValidatedOperations`, the validated definitions, the `ValidatedInventory`, the resource manifest and the resource captures · **Returns:** the compiled workflow graphs · **Side effect:** `none`
- **Does:** Resolves every referenced operation, parameter, model operation and resource against
  the one operation registry and binds transitions, terminals, gates and capabilities; constructs
  no adapter and invokes nothing.
- **Rejects:** `WorkflowGraphCompileInvalid` (`WORKFLOW_GRAPH_COMPILE_INVALID`); reports step
  `compile_workflows`.

## `validateWorkflowGraphs` (startup step `validate_workflow_graphs`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig); logic in [`src/domain/workflow_graph_validation.zig`](../../../src/domain/workflow_graph_validation.zig)
- **Takes:** the compiled workflow graphs · **Returns:** `ValidatedGraphs` · **Side effect:** `none`
- **Does:** Proves a capability-free invocation operation, graph closure, bounded cycles (every
  return to initialization consumes a retry guard), data flow, gate preservation and
  policy-permitted capabilities.
- **Rejects:** `WorkflowGraphCompileInvalid` for unknown operations, executable payloads,
  infrastructure selection and runner bypasses; reports step `validate_workflow_graphs`.

## `buildWorkflowRegistry` (startup step `build_workflow_registry`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig)
- **Takes:** the `ValidatedInventory`, the definition captures, the resource manifest, the resource captures, the validated definitions and `ValidatedGraphs` · **Returns:** the workflow registry candidate · **Side effect:** `none`
- **Does:** Indexes the validated graphs by `WorkflowId`, keeping each source ordinal and logging
  shortcode.
- **Rejects:** `WorkflowRegistryInvalid` (`WORKFLOW_REGISTRY_INVALID`); reports step
  `build_workflow_registry`.

## `validateWorkflowRegistry` (startup step `validate_workflow_registry`)

- **Owner:** [`src/application/startup_routine.zig`](../../../src/application/startup_routine.zig); logic in [`src/domain/workflow_registry.zig`](../../../src/domain/workflow_registry.zig)
- **Takes:** the workflow registry candidate · **Returns:** the validated workflow registry owner · **Side effect:** `none`
- **Does:** Proves total coverage of captured definitions and unique workflow IDs, logging
  shortcodes and source ordinals; the single uniqueness validator for shortcodes. Requires no
  particular workflow name or count.
- **Rejects:** `WorkflowRegistryInvalid`; reports step `validate_workflow_registry`.

## Workflow selection and execution

## `ParseWorkflowInvocationAction` (`parse-workflow-invocation`)

- **Owner:** [`src/actions/workflow/parse_workflow_invocation.zig`](../../../src/actions/workflow/parse_workflow_invocation.zig)
- **Reads:** `workflow_operation_registry_evidence` · **Writes:** `workflow_invocation` · **Side effect:** `none`
- **Does:** Takes exactly one leading workflow selector and validates its syntax; keeps the
  remaining arguments unparsed. No default, filename inference or registry lookup.
- **Rejects:** `MissingWorkflowId`, `InvalidWorkflowId`, `TooManyArguments` (more than 64).

## `SelectCompiledWorkflowAction` (`select-compiled-workflow`)

- **Owner:** [`src/actions/workflow/select_compiled_workflow.zig`](../../../src/actions/workflow/select_compiled_workflow.zig)
- **Reads:** `workflow_definition_registry`, `workflow_invocation` · **Writes:** `selected_compiled_workflow` · **Side effect:** `none`
- **Does:** Resolves the requested workflow exactly once, with no default or workflow-specific
  branch.
- **Rejects:** `UnknownWorkflowId`.

## `deriveRequirement` (provider routine step `derive_requirement`)

- **Owner:** [`src/application/model_provider_bootstrap_routine.zig`](../../../src/application/model_provider_bootstrap_routine.zig); logic in [`src/domain/provider_requirement_derivation.zig`](../../../src/domain/provider_requirement_derivation.zig)
- **Takes:** the selected compiled workflow · **Returns:** the provider requirement · **Side effect:** `none`
- **Does:** Returns `required` when a compiled step has a typed model binding or the
  `model-provider` capability, otherwise `not_required`
  ([ADR 0004](../../decisions/0004-model-provider-bootstrap.md)); infers nothing from names,
  parameters or configuration.
- **Rejects:** none.

## `ResolveProviderModelBindingAction` (`resolve-provider-model-binding`)

- **Owner:** [`src/actions/provider/resolve_provider_model_binding.zig`](../../../src/actions/provider/resolve_provider_model_binding.zig)
- **Reads:** `selected_compiled_workflow`, `llm_provider_registry`, `repository_model_allowlist` · **Writes:** `validated_provider_model_binding` · **Side effect:** `none`
- **Does:** Resolves each compiled model operation's declared slot through the allowlist to one
  registry entry and its supported controls; never accepts a raw provider/model tuple.
- **Rejects:** `ProviderModelBindingInvalid`.

## `PublishWorkflowOutputAction` (`publish-workflow-output`)

- **Owner:** [`src/actions/workflow/publish_workflow_output.zig`](../../../src/actions/workflow/publish_workflow_output.zig)
- **Reads:** `prepared_workflow_output` · **Writes:** `published_workflow_output` · **Side effect:** `workflow_publication`
- **Does:** Writes the prepared whole-workflow output through the output port
  ([§25](../25-publication.md)).
- **Rejects:** `InvalidWorkflowOutput`, `OutputChanged`, `OutputWriteFailed`.

## Toolchain

[F0003](../../features/F0003-ToolChainService.md#workflow-bindings) owns the order and keys.
[ADR 0031](../../decisions/0031-stage-actions.md) made the nine former operations the internal
steps of one `prepare-toolchain` stage action; `compile-naming-policy` stays separate.

## `PrepareToolchainAction` (`prepare-toolchain`)

- **Owner:** [`src/actions/toolchain/prepare_toolchain.zig`](../../../src/actions/toolchain/prepare_toolchain.zig)
- **Reads:** none · **Writes:** `valid_toolchain` · **Side effect:** `filesystem_read`
- **Ports:** the toolchain source ports (project capture, preset inventory, preset capture) and the
  toolchain-parser port, so the binding derives `toolchain-read` and `toolchain-parser` only.
- **Outcomes:** `ok`, `failed`. Each internal step's success continues to the next and every
  failure ends the stage with the step's own error (`InvalidToolchain`). The stage records the
  step it stopped at in its diagnostic slot, which the binding hands the runner's step slot, and
  the runner records it as `step_id` in the failed action's event ([§27](../27-observability.md)).
  It checks the runtime between steps, so a cancelled run stops before the next step and the
  runner reports the runtime's own stop.
- **Does:** Runs these functions in order. Each keeps its former action's responsibility, input,
  output and rejection rules; intermediates are function-local values, and only the last step
  constructs `ValidToolchain`.
  1. `captureProject`: captures the exact `<paths.principles>/toolchain.yaml` through the toolchain
     source port. Rejects `InvalidToolchain`.
  2. `inventoryPresets`: inventories the preset documents. Rejects `InvalidToolchain`.
  3. `capturePresets`: checks the capture budget over the project layer and the whole inventory
     first, then captures each entry through the preset-capture port. Rejects `InvalidToolchain`.
  4. `parseDocuments`: parses the project layer and preset documents through the toolchain-parser
     port; applies no policy. The parser returns exactly one document per capture, project
     first. Rejects `InvalidToolchain`, including for a short or long result.
  5. `validateProject`: accepts exactly the `schema`, `presets` and `policies` fields, with
     bounded package and policy reference lists. Rejects `InvalidToolchain`.
  6. `validateRegistry`: reads each preset's five fields (schema, `package@version`, layer,
     `extends`, policies), sorts by layer then package, and checks the registry is complete for
     inheritance. Rejects `InvalidToolchain` for a malformed or duplicate package or too many
     presets.
  7. `resolveInheritance`: resolves the project layer's complete preset inheritance closure from
     `paths.toolchainPreset`. Rejects `InvalidToolchain` for a missing, conflicting, duplicate or
     cyclic reference.
  8. `compose`: keeps the inherited packages in resolved order and forms the stable union of their
     policies, then the project layer's, without duplicates. Rejects `InvalidToolchain`.
  9. `validateSafety`: proves the merged policy keeps every locked rule; the only constructor of
     `ValidToolchain`. Rejects `InvalidToolchain`.

## `CompileNamingPolicyAction` (`compile-naming-policy`)

- **Owner:** [`src/actions/toolchain/compile_naming_policy.zig`](../../../src/actions/toolchain/compile_naming_policy.zig)
- **Reads:** `valid_toolchain` · **Writes:** `compiled_naming_policy` · **Side effect:** `none`
- **Does:** Normalizes the toolchain's explicit naming rules for the shared lexical detector;
  infers no rule from package names or examples.
- **Rejects:** `InvalidNamingPolicy`, `StaleNamingPolicy`.

## Principles

[§9.4](../09-configuration.md#94-project-principle-resolution) owns principle capture. The
shipped Spec workflow runs the consolidated `capture-principle-registry`; the other four are
its detailed steps through the same source port. Capture reads no alternate root, excludes
`toolchain.yaml`, and is bounded to 1,024 entries, depth 16, five seconds, 1 MiB per source and
8 MiB in total; deterministic UTF-8 chunks cover every byte.

## `InventoryPrincipleSourcesAction` (`inventory-principle-sources`)

- **Owner:** [`src/actions/principle/inventory_principle_sources.zig`](../../../src/actions/principle/inventory_principle_sources.zig)
- **Reads:** none · **Writes:** `raw_principle_inventory` · **Side effect:** `filesystem_read`
- **Rejects:** `PrincipleSourceUnavailable`.

## `ValidatePrincipleInventoryAction` (`validate-principle-inventory`)

- **Owner:** [`src/actions/principle/validate_principle_inventory.zig`](../../../src/actions/principle/validate_principle_inventory.zig)
- **Reads:** `raw_principle_inventory` · **Writes:** `principle_inventory` · **Side effect:** `none`
- **Does:** Normalizes paths, rejects collisions and classifies semantic sources.
- **Rejects:** `InvalidPrincipleRegistry`.

## `CapturePrincipleSourcesAction` (`capture-principle-sources`)

- **Owner:** [`src/actions/principle/capture_principle_sources.zig`](../../../src/actions/principle/capture_principle_sources.zig)
- **Reads:** `principle_inventory` · **Writes:** `captured_principles` · **Side effect:** `filesystem_read`
- **Does:** Captures each semantic source once, within the bounds above.
- **Rejects:** `PrincipleSourceUnavailable`.

## `BuildPrincipleRegistryAction` (`build-principle-registry`)

- **Owner:** [`src/actions/principle/build_principle_registry.zig`](../../../src/actions/principle/build_principle_registry.zig)
- **Reads:** `captured_principles` (optional: `prior_principle_registry`) · **Writes:** `principle_registry` · **Side effect:** `none`
- **Does:** Assigns source and chunk identities, keeping a prior source's ID when its root,
  path, file observation and bytes are equal, and allocating the next ordinal otherwise.
- **Rejects:** `InvalidPrincipleRegistry`.

## `CapturePrincipleRegistryAction` (`capture-principle-registry`)

- **Owner:** [`src/actions/principle/capture_principle_registry.zig`](../../../src/actions/principle/capture_principle_registry.zig)
- **Reads:** none (optional: `prior_principle_registry`) · **Writes:** `principle_registry` · **Side effect:** `filesystem_read`
- **Does:** Runs inventory, validation, capture and registry construction in one operation
  through the same port and functions; invokes no other action.
- **Rejects:** `PrincipleSourceUnavailable`, `InvalidPrincipleRegistry`.

## Proposals named elsewhere

## `ValidateRendererContractVersionAction`

Proposed, no code: select one exact supported renderer contract version
([§23.1](../23-rendering.md#231-canonical-byte-contract)).

## `ClassifyBootstrapAuthorityChangeAction`

Proposed, no code: classify a changed bootstrap candidate into the closed change plan that
decides its route ([§9](../09-configuration.md)).

## `BuildRepositoryFactRegistryAction`

Proposed, no code: assemble one complete ordered repository fact input state from project,
manifest, dependency, command, file and preset facts ([§18](../18-plan.md)).

## `CompareRepositoryFactValueAction`

Proposed, no code: compare one recorded repository fact with its current value
([§24](../24-workflow-state.md)).

## `ProbeCommandCapabilityAction`

Proposed, no code: probe one configured command's declared capability
([§10](../10-toolchain-presets.md)).

## `ValidateCommandWorkingDirectoryAction`

Proposed, no code: prove one command's working directory is an allowed contained root
([§10](../10-toolchain-presets.md)).

## `ResolveCommandExecutableAction`

Proposed, no code: resolve one command's executable without a shell or search-path fallback
([§10](../10-toolchain-presets.md), [§26](../26-security.md)).

## `ValidateCommandPlaceholderContractAction`

Proposed, no code: prove every placeholder in a command descriptor is typed and bound
([§10](../10-toolchain-presets.md)).

## `ValidateCommandMutabilityAliasAction`

Proposed, no code: reject a command whose declared effects alias a protected path
([§10](../10-toolchain-presets.md)).

## `AssembleCommandRegistryAction`

Proposed, no code: assemble the validated command descriptors into the command registry
([§10](../10-toolchain-presets.md)).

## Other proposals

Proposed, no code — Plan, Tasks and Implement: project and manifest discovery, source-root
binding, compiled environment policy, repository facts, path patterns and file kinds, root
access, target-platform portability, dependency, file-intent and fact-transition registries,
the command registry and principle guidance for planning. [§18](../18-plan.md),
[§19](../19-tasks.md) and [§20](../20-implement.md) own them, with [§10](../10-toolchain-presets.md)
and [§11](../11-path-validation.md); Plan design writes their entries.

Proposed, no code — shared: the broader preset-registry design (identity ledgers, capture
budgets, package and asset records; [§10](../10-toolchain-presets.md)), the persisted bootstrap
authority state with its compiled engine policy and change routing
([§9](../09-configuration.md); the mid-run logging transition's successor is execution-local,
[ADR 0032](../../decisions/0032-engine-routines.md)).
The earlier feature state-ID ledger is superseded: no project state-ID ledger exists, and
identities are execution-local and published with the output
([§7.3](../07-domain-representations.md#73-canonical-state-and-model-request-identity)). The earlier preset tie-break `(layerRank, presetId,
version)` has no owner; the code orders the registry by layer, then package
(`validateRegistry` in the `prepare-toolchain` entry above), and Plan design decides any further rule.
