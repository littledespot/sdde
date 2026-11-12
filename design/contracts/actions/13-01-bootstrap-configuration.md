# 13.1 Bootstrap and configuration actions

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.

One entry per registered operation; **Reads**, **Writes** and **Side effect** are its
`NodeContract`. Entries marked "Proposed, no code" name a responsibility no code registers.
[F0003](../../features/F0003-ToolChainService.md#3-closed-loading-and-publication-contract)
owns the current toolchain shapes.

> **ADR 0032 (not yet implemented).** The engine-startup and provider-bootstrap operations
> become the typed steps of [engine routines](../../decisions/0032-engine-routines.md), each
> keeping its rules and taking only the port it uses.

## Engine configuration

## `LocateExactEngineConfigAction` (`locate-exact-engine-config`)

- **Owner:** [`src/actions/config/locate_exact_engine_config.zig`](../../../src/actions/config/locate_exact_engine_config.zig)
- **Reads:** `invocation_working_directory` · **Writes:** `exact_engine_config_file` · **Side effect:** `filesystem_read`
- **Does:** Takes the invocation working directory as the project root and resolves only its
  exact `.sddtoolkit.json` child; never inspects an ancestor or descendant or accepts another name.
- **Rejects:** `EngineConfigReadError` (`ENGINE_CONFIG_READ_ERROR`) for every unsafe or unreadable result.

## `ReadEngineConfigAction` (`read-engine-config`)

- **Owner:** [`src/actions/config/read_engine_config.zig`](../../../src/actions/config/read_engine_config.zig)
- **Reads:** `exact_engine_config_file` · **Writes:** `raw_engine_config` · **Side effect:** `filesystem_read`
- **Does:** Reads that one file completely, at most 1,048,576 bytes.
- **Rejects:** `EngineConfigReadError` for every read or limit failure.

## `DecodeSDDToolKitConfigAction` (`decode-sddtoolkit-config`)

- **Owner:** [`src/actions/config/decode_sddtoolkit_config.zig`](../../../src/actions/config/decode_sddtoolkit_config.zig)
- **Reads:** `raw_engine_config` · **Writes:** `engine_config` · **Side effect:** `none`
- **Does:** Decodes the bytes strictly into the closed configuration contract
  ([§9](../09-configuration.md)); compiles no domain policy.
- **Rejects:** `EngineConfigParseError` (`ENGINE_CONFIG_PARSE_ERROR`) for malformed JSON,
  trailing content, unknown fields and wrong wire kinds.

## Bootstrap roots

[F0004](../../features/F0004-BootstrapRootRegistryService.md) owns the root registry.

## `ValidateConfiguredRootPathPolicyAction` (`validate-configured-root-path-policy`)

- **Owner:** [`src/actions/bootstrap/validate_configured_root_path_policy.zig`](../../../src/actions/bootstrap/validate_configured_root_path_policy.zig)
- **Reads:** `engine_config` · **Writes:** `configured_root_path_policy_set` · **Side effect:** `none`
- **Does:** Normalizes each configured directory path under the portable path rules.
- **Rejects:** `BootstrapRootResolutionError` for an empty, absolute, drive, empty-segment, `..`,
  backslash, encoded-separator, reserved-name, non-ASCII or over-limit path.

## `ValidateLLMProviderConfigPathPolicyAction` (`validate-llm-provider-config-path-policy`)

- **Owner:** [`src/actions/bootstrap/validate_llm_provider_config_path_policy.zig`](../../../src/actions/bootstrap/validate_llm_provider_config_path_policy.zig)
- **Reads:** `engine_config` · **Writes:** `llm_provider_config_path_policy` · **Side effect:** `none`
- **Does:** Normalizes the provider-document path under the same rules and requires the exact
  basename `.sddproviders.json`.
- **Rejects:** `BootstrapRootResolutionError`.

## `ResolveConfiguredBaseRootAction` (`resolve-configured-base-root`)

- **Owner:** [`src/actions/bootstrap/resolve_configured_base_root.zig`](../../../src/actions/bootstrap/resolve_configured_base_root.zig)
- **Reads:** `exact_engine_config_file`, `configured_root_path_policy_set` · **Writes:** `configured_root_candidate_set` · **Side effect:** `none`
- **Does:** Joins each normalized directory path to the project root without following aliases
  or deriving children.
- **Rejects:** `BootstrapRootResolutionError`.

## `ResolveLLMProviderConfigPathAction` (`resolve-llm-provider-config-path`)

- **Owner:** [`src/actions/bootstrap/resolve_llm_provider_config_path.zig`](../../../src/actions/bootstrap/resolve_llm_provider_config_path.zig)
- **Reads:** `exact_engine_config_file`, `llm_provider_config_path_policy` · **Writes:** `llm_provider_config_path_candidate` · **Side effect:** `none`
- **Does:** Joins the provider-document path to the project root the same way.
- **Rejects:** `BootstrapRootResolutionError`.

## `ValidateConfiguredBaseRootAction` (`validate-configured-base-root`)

- **Owner:** [`src/actions/bootstrap/validate_configured_base_root.zig`](../../../src/actions/bootstrap/validate_configured_base_root.zig)
- **Reads:** `configured_root_candidate_set` · **Writes:** `configured_root_capability_set` · **Side effect:** `filesystem_read`
- **Does:** Inspects each candidate through the root-inspector port and proves containment,
  access class and permitted existence and type before granting a root capability.
- **Rejects:** `BootstrapRootResolutionError`; `Cancelled`.

## `BuildBootstrapRootRegistryIdAction` (`build-bootstrap-root-registry-id`)

- **Owner:** [`src/actions/bootstrap/build_bootstrap_root_registry_id.zig`](../../../src/actions/bootstrap/build_bootstrap_root_registry_id.zig)
- **Reads:** `exact_engine_config_file`, `configured_root_capability_set` · **Writes:** `bootstrap_root_registry_id` · **Side effect:** `none`
- **Does:** Builds the registry identity from the canonical project root and contract version;
  inspects no content.
- **Rejects:** `BootstrapRootRegistryInvalid`.

## `BuildBootstrapRootRegistryAction` (`build-bootstrap-root-registry`)

- **Owner:** [`src/actions/bootstrap/build_bootstrap_root_registry.zig`](../../../src/actions/bootstrap/build_bootstrap_root_registry.zig)
- **Reads:** `bootstrap_root_registry_id`, `configured_root_capability_set`, `llm_provider_config_path_candidate` · **Writes:** `bootstrap_root_registry` · **Side effect:** `none`
- **Does:** Assembles the seven configured directory roots and the provider-document location;
  holds no preset-derived, generated or discovered root.
- **Rejects:** `BootstrapRootRegistryInvalid`.

## `ValidateBootstrapRootRegistryAction` (`validate-bootstrap-root-registry`)

- **Owner:** [`src/actions/bootstrap/validate_bootstrap_root_registry.zig`](../../../src/actions/bootstrap/validate_bootstrap_root_registry.zig)
- **Reads:** `bootstrap_root_registry` · **Writes:** `bootstrap_root_registry_evidence` · **Side effect:** `none`
- **Does:** Requires the seven directory roles and the `providers` file role exactly once.
- **Rejects:** `BootstrapRootRegistryInvalid` for a missing, unknown, duplicate, escaping or
  illegally overlapping location, with only the declared archive nesting exception.

## Provider configuration

[F0006](../../features/F0006-LLMProviderInterface.md) and
[F0008](../../features/F0008-LLMProviderConfigService.md) own the provider catalogue.

## `LocateLLMProviderConfigAction` (`locate-llm-provider-config`)

- **Owner:** [`src/actions/provider/locate_llm_provider_config.zig`](../../../src/actions/provider/locate_llm_provider_config.zig)
- **Reads:** `bootstrap_root_registry_evidence` · **Writes:** `exact_llm_provider_config_file` · **Side effect:** `filesystem_read`
- **Does:** Opens only the configured no-follow regular `.sddproviders.json`; reads no bytes and
  searches for no other file.
- **Rejects:** `LLMProviderConfigReadError`; `Cancelled`; `DeadlineExhausted`.

## `ReadLLMProviderConfigAction` (`read-llm-provider-config`)

- **Owner:** [`src/actions/provider/read_llm_provider_config.zig`](../../../src/actions/provider/read_llm_provider_config.zig)
- **Reads:** `exact_llm_provider_config_file` · **Writes:** `raw_llm_provider_config` · **Side effect:** `filesystem_read`
- **Does:** Captures the opened file once under F0008's 1,048,576-byte limit.
- **Rejects:** `LLMProviderConfigReadError`; `Cancelled`; `DeadlineExhausted`.

## `DecodeLLMProviderConfigAction` (`decode-llm-provider-config`)

- **Owner:** [`src/actions/provider/decode_llm_provider_config.zig`](../../../src/actions/provider/decode_llm_provider_config.zig)
- **Reads:** `raw_llm_provider_config` · **Writes:** `raw_llm_provider_document` · **Side effect:** `none`
- **Does:** Enforces strict UTF-8 JSON, the closed catalogue object, integer-only numbers,
  nesting and collection limits, and provider/model identity syntax; leaves each `config`
  untrusted.
- **Rejects:** `LLMProviderConfigParseError`.

## `BuildLLMProviderRegistryAction` (`build-llm-provider-registry`)

- **Owner:** [`src/actions/provider/build_llm_provider_registry.zig`](../../../src/actions/provider/build_llm_provider_registry.zig)
- **Reads:** `raw_llm_provider_document` · **Writes:** `llm_provider_registry_candidate` · **Side effect:** `none`
- **Does:** Joins every entry to one compiled contract (an exact model, or a Bedrock entry's
  family) and decodes its closed configuration variant.
- **Rejects:** `LLMProviderRegistryInvalid` for an unsupported, duplicate, partial or inconsistent
  entry; no partial registry.

## `ValidateLLMProviderRegistryAction` (`validate-llm-provider-registry`)

- **Owner:** [`src/actions/provider/validate_llm_provider_registry.zig`](../../../src/actions/provider/validate_llm_provider_registry.zig)
- **Reads:** `llm_provider_registry_candidate` · **Writes:** `llm_provider_registry` · **Side effect:** `none`
- **Does:** Rejoins every entry and proves bounds, unique identities, configuration variants,
  contract facts and deterministic order for the whole catalogue.
- **Rejects:** `LLMProviderRegistryInvalid`.

## `ValidateRepositoryModelAllowlistAction` (`validate-repository-model-allowlist`)

- **Owner:** [`src/actions/provider/validate_repository_model_allowlist.zig`](../../../src/actions/provider/validate_repository_model_allowlist.zig)
- **Reads:** `engine_config`, `llm_provider_registry` · **Writes:** `repository_model_allowlist` · **Side effect:** `none`
- **Does:** Resolves every `models.slots` tuple and option exactly, keeping slot identity, entry
  identity and validated options; several slots may share an entry, and unused entries gain no
  authority.
- **Rejects:** `LLMProviderModelBindingInvalid` (`LLM_PROVIDER_MODEL_BINDING_INVALID`).

## Workflow authority and registry

[F0005](../../features/F0005-WorkflowDefinitionRegistryService.md) owns the definition registry.

## `BuildWorkflowAuthorityLayoutAction` (`build-workflow-authority-layout`)

- **Owner:** [`src/actions/workflow/build_workflow_authority_layout.zig`](../../../src/actions/workflow/build_workflow_authority_layout.zig)
- **Reads:** `bootstrap_root_registry` · **Writes:** `workflow_authority_layout` · **Side effect:** `none`
- **Does:** Derives the `paths.workflows` inventory scope and the reserved `features/` child,
  whose root entry is accounted while its descendants are excluded; reads nothing.
- **Rejects:** `WorkflowAuthorityInventoryInvalid`.

## `EnumerateWorkflowAuthorityResourcesAction` (`enumerate-workflow-authority-resources`)

- **Owner:** [`src/actions/workflow/enumerate_workflow_authority_resources.zig`](../../../src/actions/workflow/enumerate_workflow_authority_resources.zig)
- **Reads:** `workflow_authority_layout` · **Writes:** `raw_workflow_authority_entries` · **Side effect:** `filesystem_read`
- **Does:** Enumerates every directory, file, link and special node in scope without following
  links, filtering, parsing or assigning identities.
- **Rejects:** `WorkflowAuthorityInventoryInvalid`; `Cancelled`.

## `NormalizeWorkflowAuthorityEntriesAction` (`normalize-workflow-authority-entries`)

- **Owner:** [`src/actions/workflow/normalize_workflow_authority_entries.zig`](../../../src/actions/workflow/normalize_workflow_authority_entries.zig)
- **Reads:** `raw_workflow_authority_entries` · **Writes:** `normalized_workflow_authority_entries` · **Side effect:** `none`
- **Does:** Normalizes each root-relative path, rejects collisions and sorts the inventory by
  normalized path.
- **Rejects:** `WorkflowAuthorityInventoryInvalid` for an escaping, absolute, empty or colliding
  path.

## `BuildWorkflowAuthorityEntryAccountsAction` (`build-workflow-authority-entry-accounts`)

- **Owner:** [`src/actions/workflow/build_workflow_authority_entry_accounts.zig`](../../../src/actions/workflow/build_workflow_authority_entry_accounts.zig)
- **Reads:** `normalized_workflow_authority_entries` · **Writes:** `workflow_authority_entry_accounts` · **Side effect:** `none`
- **Does:** Gives each entry exactly one disposition: directory, reserved child, definition
  (`*.workflow.yaml`) or declared-resource candidate.
- **Rejects:** `WorkflowAuthorityInventoryInvalid` for a link, special node or reserved-child
  conflict.

## `BuildWorkflowAuthorityInventoryAction` (`build-workflow-authority-inventory`)

- **Owner:** [`src/actions/workflow/build_workflow_authority_inventory.zig`](../../../src/actions/workflow/build_workflow_authority_inventory.zig)
- **Reads:** `workflow_authority_layout`, `normalized_workflow_authority_entries`, `workflow_authority_entry_accounts` · **Writes:** `workflow_authority_inventory_candidate` · **Side effect:** `none`
- **Does:** Assembles the inventory and its accounting without dropping a blocking entry.
- **Rejects:** none.

## `ValidateWorkflowAuthorityInventoryAction` (`validate-workflow-authority-inventory`)

- **Owner:** [`src/actions/workflow/validate_workflow_authority_inventory.zig`](../../../src/actions/workflow/validate_workflow_authority_inventory.zig)
- **Reads:** `workflow_authority_inventory_candidate` · **Writes:** `workflow_authority_inventory` · **Side effect:** `none`
- **Does:** Proves contiguous ordinals, one terminal account per entry, the reserved child's
  disposition and the absence of blocking entries.
- **Rejects:** `WorkflowAuthorityInventoryInvalid`.

## `CaptureWorkflowDefinitionsAction` (`capture-workflow-definitions`)

- **Owner:** [`src/actions/workflow/capture_workflow_definitions.zig`](../../../src/actions/workflow/capture_workflow_definitions.zig)
- **Reads:** `workflow_authority_inventory` · **Writes:** `workflow_definition_captures` · **Side effect:** `filesystem_read`
- **Does:** Reads each definition once through its descriptor, bound to its inventory ordinal;
  infers no workflow ID from a filename.
- **Rejects:** `WorkflowDefinitionReadError`; `Cancelled`.

## `ParseWorkflowDefinitionAction` (`parse-workflow-definitions`)

- **Owner:** [`src/actions/workflow/parse_workflow_definitions.zig`](../../../src/actions/workflow/parse_workflow_definitions.zig)
- **Reads:** `workflow_definition_captures` · **Writes:** `raw_workflow_definitions` · **Side effect:** `none`
- **Does:** Parses each captured definition through the definition-parser port without applying
  policy or resolving operations.
- **Rejects:** `WorkflowDefinitionParseError`.

## `ValidateWorkflowDefinitionSchemaAction` (`validate-workflow-definition-schema`)

- **Owner:** [`src/actions/workflow/validate_workflow_definition_schema.zig`](../../../src/actions/workflow/validate_workflow_definition_schema.zig)
- **Reads:** `raw_workflow_definitions` · **Writes:** `declarative_workflow_definitions` · **Side effect:** `none`
- **Does:** Applies the closed workflow-definition schema: workflow ID, version, logging
  shortcode, invocation and step operations, parameters, typed transitions and policy profile.
- **Rejects:** `WorkflowDefinitionSchemaInvalid` (`WORKFLOW_DEFINITION_SCHEMA_INVALID`) for
  scripts, adapter selectors, raw paths or commands, malformed or duplicate step IDs, unknown
  fields and capability claims.

## `ResolveWorkflowResourcesAction` (`resolve-workflow-resources`)

- **Owner:** [`src/actions/workflow/resolve_workflow_resources.zig`](../../../src/actions/workflow/resolve_workflow_resources.zig)
- **Reads:** `workflow_authority_inventory`, `declarative_workflow_definitions` · **Writes:** `workflow_resource_manifest` · **Side effect:** `none`
- **Does:** Binds every declared resource to exactly one non-definition file in the inventory;
  reads nothing.
- **Rejects:** `WorkflowAuthorityInventoryInvalid` for an undeclared file or an escaping,
  missing, ambiguous or doubly classified resource.

## `CaptureWorkflowResourcesAction` (`capture-workflow-resources`)

- **Owner:** [`src/actions/workflow/capture_workflow_resources.zig`](../../../src/actions/workflow/capture_workflow_resources.zig)
- **Reads:** `workflow_authority_inventory`, `workflow_resource_manifest` · **Writes:** `workflow_resource_captures` · **Side effect:** `filesystem_read`
- **Does:** Reads each bound resource once and proves its identity, type and length unchanged;
  infers no behaviour from a filename.
- **Rejects:** `WorkflowResourceReadError`; `Cancelled`.

## `CompileWorkflowGraphAction` (`compile-workflow-graphs`)

- **Owner:** [`src/actions/workflow/compile_workflow_graphs.zig`](../../../src/actions/workflow/compile_workflow_graphs.zig)
- **Reads:** `declarative_workflow_definitions`, `workflow_resource_manifest`, `workflow_resource_captures`, `workflow_operation_registry_evidence` · **Writes:** `compiled_workflow_graphs` · **Side effect:** `none`
- **Does:** Resolves every referenced operation, parameter, model operation and resource against
  the one operation registry and binds transitions, terminals, gates and capabilities; constructs
  no adapter and invokes nothing.
- **Rejects:** `WorkflowGraphCompileInvalid` (`WORKFLOW_GRAPH_COMPILE_INVALID`).

## `ValidateCompiledWorkflowGraphAction` (`validate-compiled-workflow-graphs`)

- **Owner:** [`src/actions/workflow/validate_compiled_workflow_graphs.zig`](../../../src/actions/workflow/validate_compiled_workflow_graphs.zig)
- **Reads:** `compiled_workflow_graphs` · **Writes:** `validated_workflow_graphs` · **Side effect:** `none`
- **Does:** Proves a capability-free invocation operation, graph closure, bounded cycles (every
  return to initialization consumes a retry guard), data flow, gate preservation and
  policy-permitted capabilities.
- **Rejects:** `WorkflowGraphCompileInvalid` for unknown operations, executable payloads,
  infrastructure selection and runner bypasses.

## `BuildWorkflowDefinitionRegistryAction` (`build-workflow-definition-registry`)

- **Owner:** [`src/actions/workflow/build_workflow_definition_registry.zig`](../../../src/actions/workflow/build_workflow_definition_registry.zig)
- **Reads:** `workflow_authority_inventory`, `workflow_definition_captures`, `workflow_resource_manifest`, `workflow_resource_captures`, `declarative_workflow_definitions`, `validated_workflow_graphs` · **Writes:** `workflow_definition_registry_candidate` · **Side effect:** `none`
- **Does:** Indexes the validated graphs by `WorkflowId`, keeping each source ordinal and logging
  shortcode.
- **Rejects:** `WorkflowRegistryInvalid`.

## `ValidateWorkflowDefinitionRegistryAction` (`validate-workflow-definition-registry`)

- **Owner:** [`src/actions/workflow/validate_workflow_definition_registry.zig`](../../../src/actions/workflow/validate_workflow_definition_registry.zig)
- **Reads:** `workflow_definition_registry_candidate` · **Writes:** `workflow_definition_registry` · **Side effect:** `none`
- **Does:** Proves total coverage of captured definitions and unique workflow IDs, logging
  shortcodes and source ordinals; the single uniqueness validator for shortcodes. Requires no
  particular workflow name or count.
- **Rejects:** `WorkflowRegistryInvalid`.

## Workflow selection and execution

## `ValidateWorkflowOperationRegistryAction` (`validate-workflow-operation-registry`)

- **Owner:** [`src/actions/workflow/validate_workflow_operation_registry.zig`](../../../src/actions/workflow/validate_workflow_operation_registry.zig)
- **Reads:** `workflow_operation_registry` · **Writes:** `workflow_operation_registry_evidence` · **Side effect:** `none`
- **Does:** Validates the composition root's operation registry before any invocation is parsed.
- **Rejects:** `WorkflowOperationRegistryInvalid`.

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

## `DeriveProviderRequirementAction` (`derive-provider-requirement`)

- **Owner:** [`src/actions/provider/derive_provider_requirement.zig`](../../../src/actions/provider/derive_provider_requirement.zig)
- **Reads:** `selected_compiled_workflow` · **Writes:** `model_provider_requirement` · **Side effect:** `none`
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
([§9](../09-configuration.md); the mid-run logging transition is an open decision in SPEC01).
The earlier feature state-ID ledger is superseded: no project state-ID ledger exists, and
identities are execution-local and published with the output
([§7.3](../07-domain-representations.md#73-canonical-state-and-model-request-identity)). The earlier preset tie-break `(layerRank, presetId,
version)` has no owner; the code orders the registry by layer, then package
(`validateRegistry` in the `prepare-toolchain` entry above), and Plan design decides any further rule.
