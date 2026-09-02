const std = @import("std");
const decode_toolkit = @import("actions/config/decode_sddtoolkit_config.zig");
const compile = @import("actions/workflow/compile_workflow_graphs.zig");
const derive = @import("actions/provider/derive_provider_requirement.zig");
const locate_provider_config = @import("actions/provider/locate_llm_provider_config.zig");
const read_provider_config = @import("actions/provider/read_llm_provider_config.zig");
const provider_bootstrap = @import("application/model_provider_bootstrap_orchestrator.zig");
const provider_bootstrap_runner = @import("application/model_provider_bootstrap_runner.zig");
const provider_config_runner = @import("application/llm_provider_config_runner.zig");
const bootstrap_error = @import("domain/bootstrap_error.zig");
const bootstrap_root_registry = @import("domain/bootstrap_root_registry.zig");
const bootstrap_roots = @import("domain/bootstrap_roots.zig");
const contracts = @import("domain/llm_provider_contracts.zig");
const identity = @import("domain/llm_provider_identity.zig");
const provider_config = @import("domain/llm_provider_config.zig");
const requirement = @import("domain/model_provider_requirement.zig");
const pipeline = @import("domain/pipeline.zig");
const telemetry = @import("domain/telemetry.zig");
const workflow = @import("domain/workflow.zig");
const compilation = @import("domain/workflow_compilation.zig");
const definition = @import("domain/workflow_definition.zig");
const execution = @import("domain/workflow_execution.zig");
const provider_source = @import("ports/llm_provider_config_source.zig");

test "compiler-owned model-provider capability alone activates the requirement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const capable = try compileOne(arena.allocator(), &compiler_registry, "test.model@1");
    try std.testing.expectEqual(requirement.Requirement.required, deriveGraph(&capable));

    const capability_free = try compileOne(arena.allocator(), &compiler_registry, "test.noop@1");
    try std.testing.expectEqual(requirement.Requirement.not_required, deriveGraph(&capability_free));

    var denied = compiler_registry;
    denied.policies = &.{.{
        .id = "test.safe@1",
        .allowed_capabilities = &.{},
        .allowed_terminal_outcomes = &.{.ok},
    }};
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        compileOne(arena.allocator(), &denied, "test.model@1"),
    );
}

test "conditional runner skips F0008 for a capability-free selected workflow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const graph = try compileOne(arena.allocator(), &compiler_registry, "test.noop@1");
    const selected = selectedWorkflow(&graph);

    var toolkit = try decodeToolkit(model_config);
    defer toolkit.deinit();
    const root_owner = try testRootRegistry(std.testing.allocator);
    defer bootstrap_root_registry.deinitOwner(root_owner);
    var source: FakeProviderConfigSource = .{ .bytes = "not json" };
    var config_child_runner = provider_config_runner.Runner.init(
        std.testing.allocator,
        .{},
        bootstrap_root_registry.registry(root_owner).llmProviderConfig(),
        locate_provider_config.Action{ .locator = source.locator() },
        read_provider_config.Action{},
    );
    defer config_child_runner.deinit();
    var runner = provider_bootstrap_runner.Runner.init(
        std.testing.allocator,
        .{},
        &selected,
        &toolkit.value().models,
        &config_child_runner,
        &compiled_provider_contracts,
    );
    defer runner.deinit();
    var outcome = provider_bootstrap.run(runner.childBindings());
    defer outcome.deinit();

    try std.testing.expect(outcome == .not_required);
    try std.testing.expectEqual(@as(usize, 0), source.locate_calls);
    try std.testing.expectEqual(@as(usize, 0), source.read_calls);
}

test "conditional runner captures once and publishes one immutable run authority" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const graph = try compileOne(arena.allocator(), &compiler_registry, "test.model@1");
    const selected = selectedWorkflow(&graph);

    var toolkit = try decodeToolkit(model_config);
    defer toolkit.deinit();
    const root_owner = try testRootRegistry(std.testing.allocator);
    defer bootstrap_root_registry.deinitOwner(root_owner);
    var source: FakeProviderConfigSource = .{ .bytes = provider_document };
    var config_child_runner = provider_config_runner.Runner.init(
        std.testing.allocator,
        .{},
        bootstrap_root_registry.registry(root_owner).llmProviderConfig(),
        locate_provider_config.Action{ .locator = source.locator() },
        read_provider_config.Action{},
    );
    defer config_child_runner.deinit();
    var runner = provider_bootstrap_runner.Runner.init(
        std.testing.allocator,
        .{},
        &selected,
        &toolkit.value().models,
        &config_child_runner,
        &compiled_provider_contracts,
    );
    defer runner.deinit();
    var outcome = provider_bootstrap.run(runner.childBindings());
    defer outcome.deinit();

    try std.testing.expect(outcome == .ready);
    try std.testing.expectEqual(@as(usize, 1), source.locate_calls);
    try std.testing.expectEqual(@as(usize, 1), source.read_calls);
    source.bytes = "changed after capture";

    const entry = outcome.ready.registry().resolve(
        provider_id,
        identity.ModelId.parse("model-a").?,
    ).?;
    try std.testing.expect(outcome.ready.allowlist().resolveSlot("implementation").?.registry_entry_id.eql(
        entry.id,
    ));
    try std.testing.expectEqual(@as(usize, 1), source.read_calls);
}

test "conditional runner maps each provider preparation boundary exactly" {
    inline for (.{
        .{ .document = "{", .toolkit = model_config, .failure = bootstrap_error.PublicError.LLM_PROVIDER_CONFIG_PARSE_ERROR },
        .{ .document = unsupported_provider_document, .toolkit = model_config, .failure = bootstrap_error.PublicError.LLM_PROVIDER_REGISTRY_INVALID },
        .{ .document = provider_document, .toolkit = missing_model_config, .failure = bootstrap_error.PublicError.LLM_PROVIDER_MODEL_BINDING_INVALID },
    }) |scenario| {
        try expectPreparationFailure(scenario.document, scenario.toolkit, scenario.failure);
    }
}

fn compileOne(
    allocator: std.mem.Allocator,
    registry: *const compilation.CompilerRegistry,
    contract_id: []const u8,
) !compilation.CompiledWorkflow {
    const nodes = try allocator.alloc(workflow.DeclarativeNode, 1);
    nodes[0] = .{
        .id = workflow.WorkflowNodeId.parse("run").?,
        .contract_id = workflow.RegisteredRef.parse(contract_id).?,
        .parameters = &.{},
    };
    const transitions = try allocator.alloc(workflow.Transition, 1);
    transitions[0] = .{
        .from = nodes[0].id,
        .outcome = .ok,
        .target = .{ .terminal = .ok },
    };
    const definitions = try allocator.alloc(definition.Definition, 1);
    definitions[0] = .{
        .source_ordinal = 1,
        .workflow_id = workflow.WorkflowId.parse("model-provider").?,
        .workflow_version = 1,
        .shortcode = telemetry.WorkflowShortcode.parse("TEST") catch unreachable,
        .invocation_contract_id = workflow.RegisteredRef.parse("test.empty@1").?,
        .policy_profile_id = workflow.RegisteredRef.parse("test.safe@1").?,
        .entry_node_id = nodes[0].id,
        .nodes = nodes,
        .transitions = transitions,
    };
    const graphs = try (compile.Action{ .registry = registry }).execute(allocator, definitions);
    return graphs[0];
}

fn deriveGraph(graph: *const compilation.CompiledWorkflow) requirement.Requirement {
    const selected = selectedWorkflow(graph);
    return (derive.Action{}).execute(&selected);
}

fn selectedWorkflow(graph: *const compilation.CompiledWorkflow) execution.SelectedWorkflow {
    return .{
        .invocation = .{ .workflow_id = graph.authority.workflow_id, .arguments = &.{} },
        .graph = graph,
    };
}

fn expectPreparationFailure(
    document_bytes: []const u8,
    toolkit_bytes: []const u8,
    expected: bootstrap_error.PublicError,
) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const graph = try compileOne(arena.allocator(), &compiler_registry, "test.model@1");
    const selected = selectedWorkflow(&graph);
    var toolkit = try decodeToolkit(toolkit_bytes);
    defer toolkit.deinit();
    const root_owner = try testRootRegistry(std.testing.allocator);
    defer bootstrap_root_registry.deinitOwner(root_owner);
    var source: FakeProviderConfigSource = .{ .bytes = document_bytes };
    var config_child_runner = provider_config_runner.Runner.init(
        std.testing.allocator,
        .{},
        bootstrap_root_registry.registry(root_owner).llmProviderConfig(),
        locate_provider_config.Action{ .locator = source.locator() },
        read_provider_config.Action{},
    );
    defer config_child_runner.deinit();
    var runner = provider_bootstrap_runner.Runner.init(
        std.testing.allocator,
        .{},
        &selected,
        &toolkit.value().models,
        &config_child_runner,
        &compiled_provider_contracts,
    );
    defer runner.deinit();
    var outcome = provider_bootstrap.run(runner.childBindings());
    defer outcome.deinit();

    try std.testing.expectEqual(expected, outcome.failed);
}

fn decodeToolkit(bytes: []const u8) !@import("domain/config.zig").Owned {
    return (decode_toolkit.Action{}).execute(std.testing.allocator, bytes);
}

const FakeProviderConfigSource = struct {
    bytes: []const u8,
    locate_calls: usize = 0,
    read_calls: usize = 0,

    fn locator(self: *FakeProviderConfigSource) provider_source.Locator {
        return .{ .context = self, .locate_fn = locate };
    }

    fn locate(
        context: *anyopaque,
        _: *const bootstrap_root_registry.LLMProviderConfigCapability,
        _: std.mem.Allocator,
        _: pipeline.NodeRuntime,
    ) provider_source.Error!provider_source.ExactFile {
        const self: *FakeProviderConfigSource = @ptrCast(@alignCast(context));
        self.locate_calls += 1;
        return .{
            .identity = .{ .filesystem_id = 1, .file_id = 2 },
            .context = self,
            .vtable = &fake_file_vtable,
        };
    }
};

const fake_file_vtable: provider_source.ExactFile.VTable = .{
    .read = fakeRead,
    .deinit = fakeDeinit,
};

fn fakeRead(
    context: *anyopaque,
    allocator: std.mem.Allocator,
    max_bytes: usize,
    _: pipeline.NodeRuntime,
) provider_source.Error!provider_config.Raw {
    const self: *FakeProviderConfigSource = @ptrCast(@alignCast(context));
    self.read_calls += 1;
    if (self.bytes.len > max_bytes) return error.LLMProviderConfigReadFailure;
    return .{ .bytes = allocator.dupe(u8, self.bytes) catch {
        return error.LLMProviderConfigReadFailure;
    } };
}

fn fakeDeinit(_: *anyopaque, _: std.mem.Allocator) void {}

fn testRootRegistry(allocator: std.mem.Allocator) !*bootstrap_root_registry.Owner {
    var configured: [bootstrap_roots.PathKey.count]bootstrap_roots.ValidatedConfiguredRoot = undefined;
    const paths = [_][]const u8{
        "specs",
        "references",
        "specs/archive",
        ".sdd/workflows",
        ".sdd/presets",
        ".sdd/principles",
        ".sdd/templates",
    };
    for (&configured, 0..) |*value, index| {
        const key: bootstrap_roots.PathKey = @enumFromInt(index);
        value.* = .{
            .path_key = key,
            .root_role = key.role(),
            .canonical_project_root = "/project",
            .configured_relative_path = paths[index],
            .canonical_path = switch (key) {
                .specs => "/project/specs",
                .references => "/project/references",
                .specs_archive => "/project/specs/archive",
                .workflows => "/project/.sdd/workflows",
                .toolchain_preset => "/project/.sdd/presets",
                .principles => "/project/.sdd/principles",
                .templates => "/project/.sdd/templates",
            },
            .access_class = key.accessClass(),
            .existence_policy = key.existencePolicy(),
            .observation = if (key == .workflows)
                .{ .directory = .{ .filesystem_id = 1, .file_id = 3 } }
            else
                .absent,
        };
    }
    return bootstrap_root_registry.createValidated(allocator, .{
        .id = .{
            .canonical_project_root = "/project",
            .contract_version = bootstrap_roots.bootstrap_root_contract_version,
        },
        .config_location = .{
            .canonical_project_root = "/project",
            .canonical_config_path = "/project/.sddtoolkit.json",
            .no_follow_file_identity = .{ .filesystem_id = 1, .file_id = 1 },
        },
        .configured_roots = configured,
        .llm_provider_config_path = .{
            .relative_path = ".sddproviders.json",
            .canonical_project_root = "/project",
            .canonical_path = "/project/.sddproviders.json",
        },
    });
}

const compiler_registry: compilation.CompilerRegistry = .{
    .invocations = &.{.{
        .id = "test.empty@1",
        .capability_free = true,
        .produces = &.{},
    }},
    .nodes = &.{
        .{
            .id = "test.model@1",
            .parameters = &.{},
            .requires = &.{},
            .produces = &.{},
            .outcomes = &.{.ok},
            .side_effect = pipeline.SideEffect.none,
            .capabilities = &.{requirement.capability_id},
        },
        .{
            .id = "test.noop@1",
            .parameters = &.{},
            .requires = &.{},
            .produces = &.{},
            .outcomes = &.{.ok},
            .side_effect = pipeline.SideEffect.none,
        },
    },
    .policies = &.{.{
        .id = "test.safe@1",
        .allowed_capabilities = &.{requirement.capability_id},
        .allowed_terminal_outcomes = &.{.ok},
    }},
    .gates = &.{},
    .capabilities = &.{requirement.capability_id},
};

const provider_id = identity.ProviderId.parse("compiled-provider").?;
const compiled_provider_contracts: contracts.Registry = .{ .entries = &.{.{
    .provider = provider_id,
    .model = identity.ModelId.parse("model-a").?,
    .implementation_id = contracts.RegisteredProviderImplementationId.init(1).?,
    .config_schema = .empty_object,
    .supported_reasoning_efforts = &.{"low"},
}} };

const provider_document =
    \\{"providers":[{"provider":"compiled-provider","models":[{"model":"model-a","config":{}}]}]}
;

const unsupported_provider_document =
    \\{"providers":[{"provider":"unsupported-provider","models":[]}]}
;

const model_config = toolkitPrefix() ++
    \\{"implementation":{"provider":"compiled-provider","model":"model-a","reasoningEffort":"low"}}
++ toolkitSuffix();

const missing_model_config = toolkitPrefix() ++
    \\{"implementation":{"provider":"compiled-provider","model":"missing"}}
++ toolkitSuffix();

fn toolkitPrefix() []const u8 {
    return
    \\{"logs":{"level":"info","console":false,"promptCapture":[]},"models":{"slots":
    ;
}

fn toolkitSuffix() []const u8 {
    return
    \\},"paths":{"specs":"specs","references":"references","specsArchive":"specs/archive","workflows":"workflows","toolchainPreset":"presets","principles":"principles","templates":"templates","providers":".sddproviders.json"}}
    ;
}
