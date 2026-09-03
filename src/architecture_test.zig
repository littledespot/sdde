const std = @import("std");
const bootstrap_root_registry = @import("domain/bootstrap_root_registry.zig");
const bootstrap_root_registry_service = @import("application/bootstrap_root_registry_service.zig");
const workflow_registry = @import("domain/workflow_registry.zig");
const workflow_registry_service = @import("application/workflow_definition_registry_service.zig");
const toolchain_safety = @import("domain/toolchain_safety.zig");
const llm_provider_registry = @import("domain/llm_provider_registry.zig");
const repository_model_allowlist = @import("domain/repository_model_allowlist.zig");
const llm_provider_registry_service = @import("application/llm_provider_registry_service.zig");
const derive_provider_requirement = @import("actions/provider/derive_provider_requirement.zig");
const workflow_execution = @import("domain/workflow_execution.zig");

test "every action imports only standard domain and port modules" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var actions = try std.Io.Dir.cwd().openDir(io, "src/actions", .{ .iterate = true });
    defer actions.close(io);

    var walker = try actions.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) {
            continue;
        }

        const source = try entry.dir.readFileAlloc(
            io,
            entry.basename,
            allocator,
            .limited(1024 * 1024),
        );
        defer allocator.free(source);
        try expectAllowedActionImports(source);
        try expectSingleActionContract(source);
    }
}

test "every orchestrator and coordinator is capability free" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var application = try std.Io.Dir.cwd().openDir(io, "src/application", .{ .iterate = true });
    defer application.close(io);

    var iterator = application.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file or
            (!std.mem.endsWith(u8, entry.name, "_orchestrator.zig") and
                !std.mem.endsWith(u8, entry.name, "_coordinator.zig")))
        {
            continue;
        }
        const source = try application.readFileAlloc(
            io,
            entry.name,
            allocator,
            .limited(1024 * 1024),
        );
        defer allocator.free(source);
        try expectAbsent(source, "/actions/");
        try expectAbsent(source, "/adapters/");
        try expectAbsent(source, "/ports/");
        try expectAbsent(source, "std.Io");
    }
}

test "every application runner is infrastructure independent" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var application = try std.Io.Dir.cwd().openDir(io, "src/application", .{ .iterate = true });
    defer application.close(io);

    var iterator = application.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, "_runner.zig")) continue;
        const source = try application.readFileAlloc(io, entry.name, allocator, .limited(1024 * 1024));
        defer allocator.free(source);
        try expectAbsent(source, "/adapters/");
        try expectAbsent(source, "std.Io");
    }
}

test "domain and port dependency direction is enforced repository wide" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    inline for (.{ "src/domain", "src/ports" }) |directory_path| {
        var directory = try std.Io.Dir.cwd().openDir(io, directory_path, .{ .iterate = true });
        defer directory.close(io);
        var walker = try directory.walk(allocator);
        defer walker.deinit();
        while (try walker.next(io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
            const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(1024 * 1024));
            defer allocator.free(source);
            try expectAbsent(source, "/actions/");
            try expectAbsent(source, "/application/");
            try expectAbsent(source, "/adapters/");
            try expectAbsent(source, "../actions/");
            try expectAbsent(source, "../application/");
            try expectAbsent(source, "../adapters/");
        }
    }
}

test "bootstrap orchestrator imports only binding and result contracts" {
    const source = @embedFile("application/bootstrap_orchestrator.zig");
    try expectAbsent(source, "/actions/");
    try expectAbsent(source, "/adapters/");
    try expectAbsent(source, "std.Io");
}

test "public root does not re-export ports or infrastructure adapters" {
    const source = @embedFile("root.zig");
    try expectAbsent(source, "adapters/");
    try expectAbsent(source, "ports/");
    try expectAbsent(source, "bootstrap_roots");
}

test "validated bootstrap registry authority is opaque" {
    switch (@typeInfo(bootstrap_root_registry.BootstrapRootRegistry)) {
        .@"opaque" => {},
        else => return error.RegistryAuthorityMustBeOpaque,
    }
    switch (@typeInfo(bootstrap_root_registry.ConfiguredBaseRootCapability)) {
        .@"opaque" => {},
        else => return error.RootCapabilityMustBeOpaque,
    }
    switch (@typeInfo(bootstrap_root_registry.LLMProviderConfigCapability)) {
        .@"opaque" => {},
        else => return error.ProviderConfigCapabilityMustBeOpaque,
    }

    const service_source = @embedFile("application/bootstrap_root_registry_service.zig");
    try expectAbsent(service_source, "bootstrap_roots");
    try expectAbsent(service_source, "ValidatedConfiguredRoot");

    const inspector_source = @embedFile("adapters/filesystem/bootstrap_root_inspector.zig");
    try expectAbsent(inspector_source, "workspacePathPolicy");

    const init_type = @typeInfo(@TypeOf(
        bootstrap_root_registry_service.BootstrapRootRegistryService.init,
    )).@"fn";
    try std.testing.expectEqual(@as(usize, 1), init_type.params.len);
    try std.testing.expect(init_type.params[0].type.? == *bootstrap_root_registry.Owner);

    const provider_service = @embedFile("application/llm_provider_config_service.zig");
    try expectAbsent(provider_service, "std.Io");
    try expectAbsent(provider_service, "std.json");
    const root_domain = @embedFile("domain/bootstrap_root_registry.zig");
    const provider_adapter = @embedFile("adapters/filesystem/llm_provider_config_source.zig");
    try std.testing.expect(std.mem.indexOf(u8, root_domain, "bindLLMProviderConfigSource") != null);
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(
        provider_adapter,
        "bindLLMProviderConfigSource",
    ));
}

test "configuration domain ownership is independent of the JSON parser" {
    const source = @embedFile("domain/config.zig");
    try expectAbsent(source, "std.json.Parsed");
    try expectAbsent(source, "PublicError");
    try expectAbsent(source, "Registry");
}

test "provider config orchestration is capability free and runner owned" {
    const orchestrator = @embedFile("application/llm_provider_config_orchestrator.zig");
    try expectAbsent(orchestrator, "/actions/");
    try expectAbsent(orchestrator, "/adapters/");
    try expectAbsent(orchestrator, "/ports/");
    try expectAbsent(orchestrator, "std.Io");

    const runner = @embedFile("application/llm_provider_config_runner.zig");
    try expectAbsent(runner, "/adapters/");
    try expectAbsent(runner, "std.Io");
    try std.testing.expect(std.mem.indexOf(u8, runner, "envelope.apply") != null);

    const composition = @embedFile("composition/model_provider_bootstrap.zig");
    try std.testing.expect(std.mem.indexOf(u8, composition, "llm_provider_config_source.Adapter.init") != null);
    try std.testing.expect(std.mem.indexOf(u8, composition, "llm_provider_config_runner.Runner.init") != null);
}

test "conditional provider bootstrap has one orchestration and capture authority" {
    const orchestrator = @embedFile("application/model_provider_bootstrap_orchestrator.zig");
    try expectAbsent(orchestrator, "/actions/");
    try expectAbsent(orchestrator, "/adapters/");
    try expectAbsent(orchestrator, "/ports/");
    try expectAbsent(orchestrator, "std.Io");

    const runner = @embedFile("application/model_provider_bootstrap_runner.zig");
    try expectAbsent(runner, "/adapters/");
    try expectAbsent(runner, "/ports/");
    try expectAbsent(runner, "std.Io");
    try expectAbsent(runner, "locate_llm_provider_config.zig");
    try expectAbsent(runner, "read_llm_provider_config.zig");
    try std.testing.expectEqual(
        @as(usize, 1),
        countOccurrences(runner, "config_orchestrator.run("),
    );
    try std.testing.expect(std.mem.indexOf(u8, runner, "envelope.apply") != null);

    const services = @embedFile("application/model_provider_bootstrap_services.zig");
    try expectAbsent(services, "std.json");
    try expectAbsent(services, "llm_provider_document");
    try expectAbsent(services, "config.zig");

    const binding = @embedFile("application/model_provider_bootstrap_binding.zig");
    try expectAbsent(binding, "/adapters/");
    try expectAbsent(binding, "std.Io");

    const assembly = @embedFile("composition/model_provider_bootstrap.zig");
    try std.testing.expectEqual(
        @as(usize, 1),
        countOccurrences(assembly, "llm_provider_config_source.Adapter.init("),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        countOccurrences(assembly, "orchestrator.run("),
    );

    const workflow_engine = @embedFile("application/workflow_engine_orchestrator.zig");
    try expectAbsent(workflow_engine, "/adapters/");
    try expectAbsent(workflow_engine, "std.Io");
    const select_index = std.mem.indexOf(u8, workflow_engine, "invokeSelectWorkflow()") orelse {
        return error.MissingWorkflowSelection;
    };
    const prepare_index = std.mem.indexOf(u8, workflow_engine, "invokePrepareWorkflow()") orelse {
        return error.MissingProviderBootstrapInvocation;
    };
    const execute_index = std.mem.indexOf(u8, workflow_engine, "invokeInvocation()") orelse {
        return error.MissingWorkflowExecution;
    };
    try std.testing.expect(select_index < prepare_index);
    try std.testing.expect(prepare_index < execute_index);

    const root = @embedFile("composition/root.zig");
    try expectAbsent(root, "loadLLMProviderConfigInProject");
    try expectAbsent(root, "llm_provider_config_orchestrator.zig");
}

test "provider catalogue and repository allowlist have one immutable authority each" {
    switch (@typeInfo(llm_provider_registry.ValidatedLLMProviderRegistry)) {
        .@"opaque" => {},
        else => return error.LLMProviderRegistryMustBeOpaque,
    }
    switch (@typeInfo(repository_model_allowlist.ValidatedRepositoryModelAllowlist)) {
        .@"opaque" => {},
        else => return error.RepositoryModelAllowlistMustBeOpaque,
    }

    const service = @embedFile("application/llm_provider_registry_service.zig");
    try expectAbsent(service, "std.json");
    try expectAbsent(service, "llm_provider_document");
    try expectAbsent(service, "config.zig");
    const init_type = @typeInfo(@TypeOf(
        llm_provider_registry_service.LLMProviderRegistryService.init,
    )).@"fn";
    try std.testing.expectEqual(@as(usize, 1), init_type.params.len);
    try std.testing.expect(init_type.params[0].type.? == *llm_provider_registry.Owner);

    const registry = @embedFile("domain/llm_provider_registry.zig");
    try expectAbsent(registry, "/adapters/");
    try expectAbsent(registry, "/ports/");
    try expectAbsent(registry, "anyopaque");

    const allowlist_fields = @typeInfo(repository_model_allowlist.Entry).@"struct".fields;
    try std.testing.expectEqual(@as(usize, 3), allowlist_fields.len);
    try std.testing.expectEqualStrings("slot_name", allowlist_fields[0].name);
    try std.testing.expectEqualStrings("registry_entry_id", allowlist_fields[1].name);
    try std.testing.expectEqualStrings("reasoning_effort", allowlist_fields[2].name);
    try std.testing.expect(allowlist_fields[1].type == llm_provider_registry.RegistryEntryId);

    const allowlist = @embedFile("domain/repository_model_allowlist.zig");
    try expectAbsent(allowlist, "ValidatedProviderConfig");
    try expectAbsent(allowlist, "ProviderModelContract");
    try expectAbsent(allowlist, "/adapters/");
    try expectAbsent(allowlist, "/ports/");
}

test "provider requirement derives only from one exactly selected compiled workflow" {
    const action_source = @embedFile("actions/provider/derive_provider_requirement.zig");
    try expectAbsent(action_source, "/adapters/");
    try expectAbsent(action_source, "/ports/");
    try expectAbsent(action_source, "std.Io");
    try expectAbsent(action_source, "config.zig");
    try expectAbsent(action_source, "sddproviders");
    try expectAbsent(action_source, "\"specify\"");
    try expectAbsent(action_source, "\"implement\"");

    const execute_type = @typeInfo(@TypeOf(derive_provider_requirement.Action.execute)).@"fn";
    try std.testing.expectEqual(@as(usize, 2), execute_type.params.len);
    try std.testing.expect(execute_type.params[1].type.? == *const workflow_execution.SelectedWorkflow);
    try std.testing.expectEqualSlices(
        @import("domain/pipeline.zig").DataKey,
        &.{.selected_compiled_workflow},
        derive_provider_requirement.Action.contract.requires,
    );
    try std.testing.expectEqualSlices(
        @import("domain/pipeline.zig").DataKey,
        &.{.model_provider_requirement},
        derive_provider_requirement.Action.contract.produces,
    );
}

test "workflow compiler and service preserve their authority boundaries" {
    switch (@typeInfo(workflow_registry.ValidatedWorkflowDefinitionRegistry)) {
        .@"opaque" => {},
        else => return error.WorkflowRegistryAuthorityMustBeOpaque,
    }
    const compiler = @embedFile("actions/workflow/compile_workflow_graphs.zig");
    try expectAbsent(compiler, "adapters/");
    try expectAbsent(compiler, "filesystem");
    try expectAbsent(compiler, "std.Io");
    try std.testing.expect(std.mem.indexOf(u8, compiler, "resolveOperation") != null);
    try expectAbsent(compiler, "spec.section.generate");
    try expectAbsent(compiler, "implementation.operation.generate");

    const operation_port = @embedFile("ports/workflow_operation_registry.zig");
    try std.testing.expect(std.mem.indexOf(u8, operation_port, "operations: []const Entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, operation_port, "contract.kind == .invocation") != null);
    try std.testing.expect(std.mem.indexOf(u8, operation_port, "contract.kind != .step") != null);
    try expectAbsent(operation_port, "CompilerRegistry");
    try expectAbsent(operation_port, "NodeImplementation");

    const operation_bindings = @embedFile("composition/core_workflow_operations.zig");
    try expectAbsent(operation_bindings, "specify");
    try expectAbsent(operation_bindings, "plan");
    try expectAbsent(operation_bindings, "tasks");
    try expectAbsent(operation_bindings, "implement");

    const workflow_runner = @embedFile("application/workflow_pipeline_runner.zig");
    try std.testing.expectEqual(@as(usize, 2), countOccurrences(workflow_runner, "resolveOperation"));
    try expectAbsent(workflow_runner, "resolveInvocation");
    try expectAbsent(workflow_runner, "resolveNode");
    try expectAbsent(workflow_runner, "workflow_node_implementation");

    const service = @embedFile("application/workflow_definition_registry_service.zig");
    try expectAbsent(service, "Inventory");
    try expectAbsent(service, "RawDefinition");
    const init_type = @typeInfo(@TypeOf(
        workflow_registry_service.WorkflowDefinitionRegistryService.init,
    )).@"fn";
    try std.testing.expectEqual(@as(usize, 1), init_type.params.len);

    const domain = @embedFile("domain/bootstrap_root_registry.zig");
    const adapter = @embedFile("adapters/filesystem/workflow_authority_source.zig");
    try std.testing.expect(std.mem.indexOf(u8, domain, "bindWorkflowAuthorityAdapter") != null);
    try std.testing.expectEqual(@as(usize, 2), countOccurrences(
        adapter,
        "bindWorkflowAuthorityAdapter",
    ));

    const parser_action = @embedFile("actions/workflow/parse_workflow_definitions.zig");
    try std.testing.expect(std.mem.indexOf(u8, parser_action, "workflow_definition_parser.zig") != null);
    try expectAbsent(parser_action, "std.json");
    try expectAbsent(parser_action, "bounded_yaml_syntax");
    try expectAbsent(parser_action, "/adapters/");
    const parser_adapter = @embedFile("adapters/parsers/workflow_definitions.zig");
    try std.testing.expect(std.mem.indexOf(u8, parser_adapter, "bounded_yaml_syntax") != null);
    try std.testing.expect(std.mem.indexOf(u8, parser_adapter, "workflow_definition_parser.zig") != null);
    const workflow_domain = @embedFile("domain/workflow_registry.zig");
    try expectAbsent(workflow_domain, "std.json");
    try expectAbsent(workflow_domain, "bounded_yaml_syntax");
    try expectAbsent(workflow_domain, "validInventoryPath");
    try expectAbsent(workflow_domain, "classifyInventoryDescriptor");
    try expectAbsent(workflow_domain, "RawNode");
    try expectAbsent(workflow_domain, "CompilerRegistry");

    const vocabulary = @embedFile("domain/workflow.zig");
    try expectAbsent(vocabulary, "InventoryDescriptor");
    try expectAbsent(vocabulary, "RawDefinition");
    try expectAbsent(vocabulary, "CompiledWorkflow");
    try expectAbsent(vocabulary, "ValidatedWorkflowDefinitionRegistry");

    const inventory_domain = @embedFile("domain/workflow_inventory.zig");
    try expectAbsent(inventory_domain, "RawDefinition");
    try expectAbsent(inventory_domain, "CompilerRegistry");
    try expectAbsent(inventory_domain, "CompiledWorkflow");

    const definition_domain = @embedFile("domain/workflow_definition.zig");
    try expectAbsent(definition_domain, "InventoryDescriptor");
    try expectAbsent(definition_domain, "CompilerRegistry");
    try expectAbsent(definition_domain, "ValidatedWorkflowDefinitionRegistry");

    const compilation_domain = @embedFile("domain/workflow_compilation.zig");
    try expectAbsent(compilation_domain, "InventoryDescriptor");
    try expectAbsent(compilation_domain, "RawDefinition");
    try expectAbsent(compilation_domain, "ValidatedWorkflowDefinitionRegistry");

    const capture = @embedFile("actions/workflow/capture_workflow_definitions.zig");
    const budget_index = std.mem.indexOf(u8, capture, "validateCaptureBudget") orelse return error.MissingWorkflowCaptureBudget;
    const read_index = std.mem.indexOf(u8, capture, "source.capture") orelse return error.MissingWorkflowCapture;
    try std.testing.expect(budget_index < read_index);
}

test "toolchain safety authority is opaque and path handoff has one adapter consumer" {
    switch (@typeInfo(toolchain_safety.ValidToolchain)) {
        .@"opaque" => {},
        else => return error.ValidToolchainMustBeOpaque,
    }
    const domain = @embedFile("domain/bootstrap_root_registry.zig");
    const adapter = @embedFile("adapters/filesystem/toolchain_authority_source.zig");
    try std.testing.expect(std.mem.indexOf(u8, domain, "bindToolchainAuthorityAdapter") != null);
    try std.testing.expectEqual(@as(usize, 3), countOccurrences(adapter, "bindToolchainAuthorityAdapter"));
    const service = @embedFile("application/toolchain_service.zig");
    try expectAbsent(service, "RawDocument");
    try expectAbsent(service, "std.Io");
    const runner = @embedFile("application/bootstrap_runner.zig");
    try expectAbsent(runner, "invokeBootstrapToolchain");
    const capture = @embedFile("actions/toolchain/capture_toolchain_presets.zig");
    const budget_index = std.mem.indexOf(u8, capture, "validateCaptureBudget") orelse return error.MissingCaptureBudget;
    const read_index = std.mem.indexOf(u8, capture, "capturePreset") orelse return error.MissingPresetCapture;
    try std.testing.expect(budget_index < read_index);
    const parser = @embedFile("actions/toolchain/parse_toolchain_documents.zig");
    try expectAbsent(parser, "validateCaptureBudget");

    const contracts = @embedFile("domain/toolchain.zig");
    try expectAbsent(contracts, "validateCaptureBudget(");
    try expectAbsent(contracts, "parseProject(");
    try expectAbsent(contracts, "parseRegistry(");
    try expectAbsent(contracts, "validateCompleteRegistry(");
    try expectAbsent(contracts, "pub fn resolve(");
    try expectAbsent(contracts, "pub fn compose(");
    try expectAbsent(contracts, "pub fn validate(");
    try expectAbsent(contracts, "pub const Owner");

    const accounting = @embedFile("domain/toolchain_accounting.zig");
    try expectAbsent(accounting, "parseProject(");
    try expectAbsent(accounting, "resolve(");
    try expectAbsent(accounting, "compose(");
    const schema = @embedFile("domain/toolchain_schema.zig");
    try expectAbsent(schema, "validateCaptureBudget(");
    try expectAbsent(schema, "validateCompleteRegistry(");
    try expectAbsent(schema, "compose(");
    const inheritance = @embedFile("domain/toolchain_inheritance.zig");
    try expectAbsent(inheritance, "parseProject(");
    try expectAbsent(inheritance, "compose(");
    const composition = @embedFile("domain/toolchain_composition.zig");
    try expectAbsent(composition, "parseProject(");
    try expectAbsent(composition, "resolve(");
    try expectAbsent(composition, "pub fn validate(");
    const safety = @embedFile("domain/toolchain_safety.zig");
    try expectAbsent(safety, "parseProject(");
    try expectAbsent(safety, "validateCompleteRegistry(");
    try expectAbsent(safety, "compose(");
}

test "bootstrap source ports and workflow inventory stages remain single purpose" {
    const workflow_ports = @embedFile("ports/workflow_authority_source.zig");
    try expectAbsent(workflow_ports, "pub const Source");
    try std.testing.expect(std.mem.indexOf(u8, workflow_ports, "pub const Enumerator") != null);
    try std.testing.expect(std.mem.indexOf(u8, workflow_ports, "pub const Capturer") != null);

    const toolchain_ports = @embedFile("ports/toolchain_authority_source.zig");
    try expectAbsent(toolchain_ports, "pub const Source");
    try std.testing.expect(std.mem.indexOf(u8, toolchain_ports, "pub const ProjectCapturer") != null);
    try std.testing.expect(std.mem.indexOf(u8, toolchain_ports, "pub const PresetEnumerator") != null);
    try std.testing.expect(std.mem.indexOf(u8, toolchain_ports, "pub const PresetCapturer") != null);

    const runner = @embedFile("application/bootstrap_runner.zig");
    try expectAbsent(runner, "inventory_workflow_authority.zig");
    const inventory_stages = [_][]const u8{
        @embedFile("actions/workflow/enumerate_workflow_authority_resources.zig"),
        @embedFile("actions/workflow/normalize_workflow_authority_entries.zig"),
        @embedFile("actions/workflow/build_workflow_authority_entry_accounts.zig"),
        @embedFile("actions/workflow/build_workflow_authority_inventory.zig"),
        @embedFile("actions/workflow/validate_workflow_authority_inventory.zig"),
    };
    for (inventory_stages) |source| {
        try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "pub fn execute("));
    }
}

test "bootstrap dispatcher delegates to focused runners" {
    const dispatcher = @embedFile("application/bootstrap_runner.zig");
    try expectAbsent(dispatcher, "/actions/");
    try expectAbsent(dispatcher, "/adapters/");
    try expectAbsent(dispatcher, "std.Io");

    const config_runner = @embedFile("application/bootstrap_config_runner.zig");
    try expectAbsent(config_runner, "/actions/bootstrap/");
    try expectAbsent(config_runner, "/actions/workflow/");
    try expectAbsent(config_runner, "/actions/toolchain/");

    const root_runner = @embedFile("application/bootstrap_root_runner.zig");
    try expectAbsent(root_runner, "/actions/config/");
    try expectAbsent(root_runner, "/actions/workflow/");
    try expectAbsent(root_runner, "/actions/toolchain/");

    const workflow_runner = @embedFile("application/bootstrap_workflow_runner.zig");
    try expectAbsent(workflow_runner, "/actions/config/");
    try expectAbsent(workflow_runner, "/actions/bootstrap/");
    try expectAbsent(workflow_runner, "/actions/toolchain/");

    const toolchain_runner = @embedFile("application/bootstrap_toolchain_runner.zig");
    try expectAbsent(toolchain_runner, "/actions/config/");
    try expectAbsent(toolchain_runner, "/actions/bootstrap/");
    try expectAbsent(toolchain_runner, "/actions/workflow/");
}

test "configured path policy and resolution have distinct action owners" {
    const runner = @embedFile("application/bootstrap_root_runner.zig");
    try expectAbsent(runner, "validate_engine_path_policy.zig");
    try std.testing.expect(std.mem.indexOf(u8, runner, "validate_configured_root_path_policy.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, runner, "validate_llm_provider_config_path_policy.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, runner, "resolve_configured_base_root.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, runner, "resolve_llm_provider_config_path.zig") != null);

    const root_resolution = @embedFile("actions/bootstrap/resolve_configured_base_root.zig");
    try expectAbsent(root_resolution, "LLMProviderConfig");
    const provider_resolution = @embedFile("actions/bootstrap/resolve_llm_provider_config_path.zig");
    try expectAbsent(provider_resolution, "PathKey");
}

test "feature log paths have one opaque artifact authority and one sink consumer" {
    const artifacts = @import("domain/workflow_artifact_registry.zig");
    switch (@typeInfo(artifacts.WorkflowArtifactRegistry)) {
        .@"opaque" => {},
        else => return error.WorkflowArtifactRegistryMustBeOpaque,
    }
    const root_domain = @embedFile("domain/bootstrap_root_registry.zig");
    const artifact_domain = @embedFile("domain/workflow_artifact_registry.zig");
    const sink = @embedFile("adapters/filesystem/feature_log_sink.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(root_domain, "bindSpecsArtifactRegistry("));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(artifact_domain, "bindSpecsArtifactRegistry("));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(sink, "bindFeatureLogSinkAdapter"));
    try expectAbsent(root_domain, "physical_identity: ?roots.PhysicalDirectoryIdentity");
    try expectAbsent(sink, "createDirPathOpen");
}

test "feature logging lifecycle coordinates bindings without filesystem authority" {
    const lifecycle = @embedFile("application/feature_log_runtime_lifecycle.zig");
    try expectAbsent(lifecycle, "/adapters/");
    try expectAbsent(lifecycle, "std.Io");
    try expectAbsent(lifecycle, "createDir");
    const invocation_assembly = @embedFile("composition/engine_invocation.zig");
    try std.testing.expect(std.mem.indexOf(u8, invocation_assembly, "services.logs.barrier()") != null);
    const composition = @embedFile("composition/root.zig");
    try expectAbsent(composition, "feature_log_lifecycle.Lifecycle");
    try expectAbsent(composition, "unbound_telemetry_barrier");
}

test "feature logging policy execution and filesystem operations have focused owners" {
    const port = @embedFile("ports/feature_log_sink.zig");
    try expectAbsent(port, "pub const Sink");
    try expectAbsent(port, "pub const VTable");

    const runner = @embedFile("application/feature_log_runner.zig");
    try expectAbsent(runner, "feature_log_sink.zig");
    try expectAbsent(runner, "trusted_log_clock.zig");
    try expectAbsent(runner, "console_log_sink.zig");
    try expectAbsent(runner, "emergency_log_sink.zig");
    try expectAbsent(runner, "transaction_stabilizer.zig");
    try expectAbsent(runner, "serialize_feature_log_record.zig");
    try expectAbsent(runner, "fn terminalEvent");
    try expectAbsent(runner, "fn promptSelected");
    try expectAbsent(runner, "fn updateState");
    try std.testing.expect(std.mem.indexOf(u8, runner, "feature_log_child_bindings.zig") != null);
    const orchestrator = @embedFile("application/feature_log_orchestrator.zig");
    try expectAbsent(orchestrator, "/actions/");
    try expectAbsent(orchestrator, "/adapters/");
    try expectAbsent(orchestrator, "/ports/");
    const transition = @embedFile("application/feature_log_policy_transition_coordinator.zig");
    try expectAbsent(transition, "feature_log_runner.zig");
    const finalization = @embedFile("application/feature_log_finalization_coordinator.zig");
    try expectAbsent(finalization, "feature_log_runner.zig");
    const retention = @embedFile("application/feature_log_retention_coordinator.zig");
    try expectAbsent(retention, "feature_log_runner.zig");

    const domain_modules = [_][]const u8{
        @embedFile("domain/feature_log_binding.zig"),
        @embedFile("domain/feature_log_stream.zig"),
        @embedFile("domain/feature_log_retention.zig"),
        @embedFile("domain/log_event_registry.zig"),
        @embedFile("domain/log_policy.zig"),
        @embedFile("domain/sanitized_prompt_log.zig"),
    };
    for (domain_modules) |source| {
        try expectAbsent(source, "BarrierOutcome");
    }

    const adapter = @embedFile("adapters/filesystem/feature_log_sink.zig");
    try expectAbsent(adapter, ".iterate(");
    try expectAbsent(adapter, ".openFile(");
    try expectAbsent(adapter, ".createFile(");
    try expectAbsent(adapter, "validateEncodedRow");
    try expectAbsent(adapter, "allocRemaining");
    try std.testing.expect(std.mem.indexOf(u8, adapter, "feature_log_lock.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, adapter, "feature_log_recovery.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, adapter, "feature_log_retention_store.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, adapter, "feature_log_segment_store.zig") != null);

    const recovery = @embedFile("adapters/filesystem/feature_log_recovery.zig");
    try std.testing.expect(std.mem.indexOf(u8, recovery, "domain/feature_log_format.zig") != null);
    try expectAbsent(recovery, "fn cellAt");
    try expectAbsent(recovery, "fn parseUtc");
}

test "workflow engine owns selection while composition binds focused runners" {
    const composition = @embedFile("composition/root.zig");
    try expectAbsent(composition, "parse_workflow_invocation.zig");
    try expectAbsent(composition, "select_compiled_workflow.zig");
    const orchestrator = @embedFile("application/workflow_engine_orchestrator.zig");
    try expectAbsent(orchestrator, "/actions/");
    try std.testing.expect(std.mem.indexOf(u8, orchestrator, "invokeParseInvocation()") != null);
    try std.testing.expect(std.mem.indexOf(u8, orchestrator, "invokeSelectWorkflow()") != null);
    const selection_runner = @embedFile("application/workflow_selection_runner.zig");
    try std.testing.expect(std.mem.indexOf(u8, selection_runner, "parse_workflow_invocation.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, selection_runner, "select_compiled_workflow.zig") != null);
}

test "active feature logging concrete assembly remains in composition" {
    const assembly = @embedFile("composition/active_feature_log_runtime.zig");
    try std.testing.expect(std.mem.indexOf(u8, assembly, "adapters/filesystem/feature_log_sink.zig") != null);
    const service = @embedFile("application/log_service.zig");
    try expectAbsent(service, "/adapters/");
    try expectAbsent(service, "std.Io");
}

test "generic workflow engine is capability free and workflow-name agnostic" {
    const orchestrator = @embedFile("application/workflow_engine_orchestrator.zig");
    try expectAbsent(orchestrator, "/actions/");
    try expectAbsent(orchestrator, "/adapters/");
    try expectAbsent(orchestrator, "/ports/");
    try expectAbsent(orchestrator, "std.Io");
    try expectAbsent(orchestrator, "\"specify\"");
    try expectAbsent(orchestrator, "\"implement\"");
    const runner = @embedFile("application/workflow_pipeline_runner.zig");
    try expectAbsent(runner, "\"specify\"");
    try expectAbsent(runner, "\"implement\"");
    try expectAbsent(runner, "/adapters/");
}

test "feature service filenames and headings end in Service" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var features = try std.Io.Dir.cwd().openDir(io, "design/features", .{ .iterate = true });
    defer features.close(io);

    var iterator = features.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file or
            !std.mem.startsWith(u8, entry.name, "F") or
            !std.mem.endsWith(u8, entry.name, ".md"))
        {
            continue;
        }

        try std.testing.expect(std.mem.endsWith(u8, entry.name, "Service.md"));
        const source = try features.readFileAlloc(
            io,
            entry.name,
            allocator,
            .limited(1024 * 1024),
        );
        defer allocator.free(source);
        const heading_end = std.mem.indexOfScalar(u8, source, '\n') orelse source.len;
        const heading = std.mem.trimEnd(u8, source[0..heading_end], "\r");
        try std.testing.expect(std.mem.endsWith(u8, heading, "Service"));
    }
}

fn expectAbsent(source: []const u8, forbidden: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, source, forbidden) == null);
}

fn expectAllowedActionImports(source: []const u8) !void {
    const prefix = "@import(\"";
    var remaining = source;
    while (std.mem.indexOf(u8, remaining, prefix)) |import_start| {
        const path_start = import_start + prefix.len;
        const path_end = std.mem.indexOfScalarPos(u8, remaining, path_start, '"') orelse {
            return error.UnterminatedImport;
        };
        const path = remaining[path_start..path_end];
        try std.testing.expect(
            std.mem.eql(u8, path, "std") or
                std.mem.eql(u8, path, "builtin") or
                std.mem.startsWith(u8, path, "../../domain/") or
                std.mem.startsWith(u8, path, "../../ports/"),
        );
        remaining = remaining[path_end + 1 ..];
    }
}

fn expectSingleActionContract(source: []const u8) !void {
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "pub const Action = struct"));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "pub const contract: pipeline.NodeContract"));
}

fn countOccurrences(source: []const u8, needle: []const u8) usize {
    var count: usize = 0;
    var remaining = source;
    while (std.mem.indexOf(u8, remaining, needle)) |index| {
        count += 1;
        remaining = remaining[index + needle.len ..];
    }
    return count;
}
