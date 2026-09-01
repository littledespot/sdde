const std = @import("std");
const pipeline = @import("../domain/pipeline.zig");
const engine_config_source = @import("../adapters/filesystem/engine_config_source.zig");
const bootstrap_root_inspector = @import("../adapters/filesystem/bootstrap_root_inspector.zig");
const workflow_authority_source = @import("../adapters/filesystem/workflow_authority_source.zig");
const workflow_definitions = @import("../adapters/parsers/workflow_definitions.zig");
const toolchain_authority_source = @import("../adapters/filesystem/toolchain_authority_source.zig");
const toolchain_documents = @import("../adapters/parsers/toolchain_documents.zig");
const workspace_path_policy = @import("../adapters/filesystem/workspace_path_policy.zig");
const locate = @import("../actions/config/locate_exact_engine_config.zig");
const read = @import("../actions/config/read_engine_config.zig");
const decode = @import("../actions/config/decode_sddtoolkit_config.zig");
const canonicalize_log_level = @import("../actions/log/canonicalize_log_level.zig");
const validate_logging_policy = @import("../actions/log/validate_logging_policy.zig");
const validate_path_policy = @import("../actions/bootstrap/validate_engine_path_policy.zig");
const resolve_root = @import("../actions/bootstrap/resolve_configured_base_root.zig");
const validate_root = @import("../actions/bootstrap/validate_configured_base_root.zig");
const build_registry_id = @import("../actions/bootstrap/build_bootstrap_root_registry_id.zig");
const build_registry = @import("../actions/bootstrap/build_bootstrap_root_registry.zig");
const validate_registry = @import("../actions/bootstrap/validate_bootstrap_root_registry.zig");
const build_workflow_layout = @import("../actions/workflow/build_workflow_authority_layout.zig");
const inventory_workflows = @import("../actions/workflow/inventory_workflow_authority.zig");
const capture_workflows = @import("../actions/workflow/capture_workflow_definitions.zig");
const parse_workflows = @import("../actions/workflow/parse_workflow_definitions.zig");
const validate_workflow_schema = @import("../actions/workflow/validate_workflow_definition_schema.zig");
const compile_workflows = @import("../actions/workflow/compile_workflow_graphs.zig");
const validate_workflow_graphs = @import("../actions/workflow/validate_compiled_workflow_graphs.zig");
const build_workflow_registry = @import("../actions/workflow/build_workflow_definition_registry.zig");
const validate_workflow_registry = @import("../actions/workflow/validate_workflow_definition_registry.zig");
const workflow = @import("../domain/workflow.zig");
const bootstrap_orchestrator = @import("../application/bootstrap_orchestrator.zig");
const bootstrap_runner = @import("../application/bootstrap_runner.zig");
const capture_project_toolchain = @import("../actions/toolchain/capture_project_toolchain.zig");
const inventory_toolchain_presets = @import("../actions/toolchain/inventory_toolchain_presets.zig");
const capture_toolchain_presets = @import("../actions/toolchain/capture_toolchain_presets.zig");
const parse_toolchain_documents = @import("../actions/toolchain/parse_toolchain_documents.zig");
const validate_project_toolchain_schema = @import("../actions/toolchain/validate_project_toolchain_schema.zig");
const validate_toolchain_preset_registry = @import("../actions/toolchain/validate_toolchain_preset_registry.zig");
const resolve_toolchain_inheritance = @import("../actions/toolchain/resolve_toolchain_inheritance.zig");
const compose_toolchain = @import("../actions/toolchain/compose_toolchain.zig");
const validate_toolchain_safety = @import("../actions/toolchain/validate_toolchain_safety.zig");
const toolchain = @import("../domain/toolchain.zig");
const run_outcome = @import("../domain/run_outcome.zig");
const parse_invocation = @import("../actions/workflow/parse_workflow_invocation.zig");
const select_workflow = @import("../actions/workflow/select_compiled_workflow.zig");
const workflow_pipeline_runner = @import("../application/workflow_pipeline_runner.zig");
const workflow_engine = @import("../application/workflow_engine_orchestrator.zig");
const core_workflow_nodes = @import("core_workflow_nodes.zig");
const workflow_artifacts = @import("../domain/workflow_artifact_registry.zig");
const feature_log_runtime = @import("../domain/feature_log_runtime.zig");
const feature_log_sink = @import("../adapters/filesystem/feature_log_sink.zig");
const active_feature_log_runtime = @import("active_feature_log_runtime.zig");
const stabilizer_port = @import("../ports/transaction_stabilizer.zig");
const llm_provider_config_source = @import("../adapters/filesystem/llm_provider_config_source.zig");
const locate_llm_provider_config = @import("../actions/provider/locate_llm_provider_config.zig");
const read_llm_provider_config = @import("../actions/provider/read_llm_provider_config.zig");
const llm_provider_config_runner = @import("../application/llm_provider_config_runner.zig");
const llm_provider_config_orchestrator = @import("../application/llm_provider_config_orchestrator.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, arguments: []const []const u8) run_outcome.Outcome {
    return runInvocationInProject(io, allocator, .cwd(), arguments);
}

fn runInvocationInProject(
    io: std.Io,
    allocator: std.mem.Allocator,
    project_root: std.Io.Dir,
    arguments: []const []const u8,
) run_outcome.Outcome {
    var boot = runInProject(io, allocator, project_root);
    defer boot.deinit();
    switch (boot) {
        .failed => |failure| return .{ .bootstrap_failed = failure },
        .cancelled => return .{ .execution = .cancelled },
        .ready => |*services| {
            if (!core_workflow_nodes.registry.matchesCompiler(core_workflow_nodes.compiler_registry)) {
                return .{ .execution = .failed };
            }
            const invocation = (parse_invocation.Action{}).execute(arguments) catch return .invocation_invalid;
            const selected = (select_workflow.Action{ .registry = services.workflows.registry() }).execute(invocation) catch {
                return .invocation_invalid;
            };
            var runner: workflow_pipeline_runner.Runner = .{
                .selected = selected,
                .implementations = core_workflow_nodes.registry,
                .barrier = services.logs.barrier(),
                .runtime = .{},
            };
            return .{ .execution = workflow_engine.run(selected.graph, runner.bindings()) };
        },
    }
}

fn runInProject(
    io: std.Io,
    allocator: std.mem.Allocator,
    project_root: std.Io.Dir,
) bootstrap_orchestrator.Outcome {
    return runInProjectWithRuntime(io, allocator, project_root, .{});
}

fn runInProjectWithRuntime(
    io: std.Io,
    allocator: std.mem.Allocator,
    project_root: std.Io.Dir,
    runtime: pipeline.NodeRuntime,
) bootstrap_orchestrator.Outcome {
    var source_adapter = engine_config_source.Adapter.init(io, project_root);
    var root_adapter = bootstrap_root_inspector.Adapter.init(io, project_root);
    var workflow_source_adapter = workflow_authority_source.Adapter.init(io, project_root);
    var workflow_parser_adapter: workflow_definitions.Adapter = .{};
    var toolchain_source_adapter = toolchain_authority_source.Adapter.init(io, project_root);
    var toolchain_parser_adapter: toolchain_documents.Adapter = .{};
    const policy_resolver = workspace_path_policy.Resolver.init(io, project_root);
    const active_path_policy = policy_resolver.resolve(allocator) catch {
        return .{ .failed = .BOOTSTRAP_ROOT_RESOLUTION_ERROR };
    };
    var runner = bootstrap_runner.Runner.init(
        allocator,
        locate.Action{ .locator = source_adapter.locator() },
        read.Action{},
        decode.Action{},
        canonicalize_log_level.Action{},
        validate_logging_policy.Action{},
        validate_path_policy.Action{ .policy = active_path_policy },
        resolve_root.Action{ .policy = active_path_policy },
        validate_root.Action{ .inspector = root_adapter.inspector() },
        build_registry_id.Action{},
        build_registry.Action{},
        validate_registry.Action{},
        build_workflow_layout.Action{},
        inventory_workflows.Action{ .source = workflow_source_adapter.source() },
        capture_workflows.Action{ .source = workflow_source_adapter.source() },
        parse_workflows.Action{ .parser = workflow_parser_adapter.parser() },
        validate_workflow_schema.Action{},
        compile_workflows.Action{ .registry = &core_workflow_nodes.compiler_registry },
        validate_workflow_graphs.Action{},
        build_workflow_registry.Action{},
        validate_workflow_registry.Action{},
        capture_project_toolchain.Action{ .source = toolchain_source_adapter.source() },
        inventory_toolchain_presets.Action{ .source = toolchain_source_adapter.source() },
        capture_toolchain_presets.Action{ .source = toolchain_source_adapter.source() },
        parse_toolchain_documents.Action{ .parser = toolchain_parser_adapter.parser() },
        validate_project_toolchain_schema.Action{},
        validate_toolchain_preset_registry.Action{},
        resolve_toolchain_inheritance.Action{},
        compose_toolchain.Action{},
        validate_toolchain_safety.Action{ .registry = policy_registry },
        runtime,
    );
    defer runner.deinit();

    return bootstrap_orchestrator.run(runner.bindings());
}

fn loadLLMProviderConfigInProject(
    io: std.Io,
    allocator: std.mem.Allocator,
    project_root: std.Io.Dir,
    capability: *const @import("../domain/bootstrap_root_registry.zig").LLMProviderConfigCapability,
    runtime: pipeline.NodeRuntime,
) llm_provider_config_orchestrator.Outcome {
    var source_adapter = llm_provider_config_source.Adapter.init(io, project_root);
    var runner = llm_provider_config_runner.Runner.init(
        allocator,
        runtime,
        capability,
        locate_llm_provider_config.Action{ .locator = source_adapter.locator() },
        read_llm_provider_config.Action{},
    );
    defer runner.deinit();
    return llm_provider_config_orchestrator.run(runner.childBindings());
}

const policy_registry: toolchain.PolicyRegistry = .{ .contracts = &.{
    .{ .id = "core.safety@1", .project_selectable = false, .locked_required = true },
    .{ .id = "project.zig@1", .project_selectable = true, .locked_required = false },
} };

const valid_config =
    \\{
    \\  "logs": { "level": "debug", "console": false, "promptCapture": [] },
    \\  "models": { "slots": {} },
    \\  "paths": {
    \\    "specs": "specs", "references": "references",
    \\    "specsArchive": "specs/archive", "workflows": ".sdd/workflows",
    \\    "toolchainPreset": ".sdd/presets",
    \\    "principles": ".sdd/principles", "templates": ".sdd/templates",
    \\    "providers": ".sddproviders.json"
    \\  }
    \\}
;

test "publishes config and the validated root registry together" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{
        .sub_path = ".sddtoolkit.json",
        .data = valid_config,
    });
    try project_root.dir.createDirPath(io, ".sdd/workflows");
    try writeValidToolchain(io, project_root.dir);

    var outcome = runInProject(io, std.testing.allocator, project_root.dir);
    defer outcome.deinit();
    try std.testing.expect(outcome == .ready);
    const first_config = outcome.ready.config.config();
    try std.testing.expect(!first_config.logs.console);
    try std.testing.expectEqual(
        @import("../domain/telemetry.zig").CanonicalLogLevel.debug,
        outcome.ready.logs.policy().level.threshold,
    );
    try std.testing.expect(first_config == outcome.ready.config.config());
    try std.testing.expect(outcome.ready.roots.registry().workflowAuthority().isPresent());
    try std.testing.expectEqual(@as(usize, 0), outcome.ready.workflows.registry().count());
    try std.testing.expectEqual(@as(usize, 0), outcome.ready.toolchain.toolchain().packages().len);
    try std.testing.expectEqualStrings("core.safety@1", outcome.ready.toolchain.toolchain().policies()[0].id);
    try std.testing.expect(
        outcome.ready.roots.registry() == outcome.ready.roots.registry(),
    );
}

test "loads provider bytes only from the configured F0008 path" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    const config_with_nested_provider =
        \\{
        \\  "logs": { "level": "debug", "console": false, "promptCapture": [] },
        \\  "models": { "slots": {} },
        \\  "paths": {
        \\    "specs": "specs", "references": "references",
        \\    "specsArchive": "specs/archive", "workflows": ".sdd/workflows",
        \\    "toolchainPreset": ".sdd/presets",
        \\    "principles": ".sdd/principles", "templates": ".sdd/templates",
        \\    "providers": "configuration/.sddproviders.json"
        \\  }
        \\}
    ;
    try project_root.dir.writeFile(io, .{
        .sub_path = ".sddtoolkit.json",
        .data = config_with_nested_provider,
    });
    try project_root.dir.createDirPath(io, ".sdd/workflows");
    try project_root.dir.createDirPath(io, "configuration");
    try project_root.dir.writeFile(io, .{
        .sub_path = ".sddproviders.json",
        .data = "fixed-location fallback",
    });
    try project_root.dir.writeFile(io, .{
        .sub_path = "configuration/.sddproviders.json",
        .data = "{\"providers\":[]}",
    });
    try writeValidToolchain(io, project_root.dir);

    var boot = runInProject(io, std.testing.allocator, project_root.dir);
    defer boot.deinit();
    try std.testing.expect(boot == .ready);

    var outcome = loadLLMProviderConfigInProject(
        io,
        std.testing.allocator,
        project_root.dir,
        boot.ready.roots.registry().llmProviderConfig(),
        .{},
    );
    defer outcome.deinit();
    try std.testing.expect(outcome == .ready);
    try std.testing.expectEqualStrings("{\"providers\":[]}", outcome.ready.bytes());

    var control: RuntimeAfterObservations = .{
        .active_observations_remaining = 3,
        .terminal = .cancelled,
    };
    var cancelled = loadLLMProviderConfigInProject(
        io,
        std.testing.allocator,
        project_root.dir,
        boot.ready.roots.registry().llmProviderConfig(),
        control.runtime(),
    );
    defer cancelled.deinit();
    try std.testing.expect(cancelled == .cancelled);
}

test "ordinary bootstrap does not probe a missing provider document" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{
        .sub_path = ".sddtoolkit.json",
        .data = valid_config,
    });
    try project_root.dir.createDirPath(io, ".sdd/workflows");
    try writeValidToolchain(io, project_root.dir);

    var boot = runInProject(io, std.testing.allocator, project_root.dir);
    defer boot.deinit();
    try std.testing.expect(boot == .ready);

    var outcome = loadLLMProviderConfigInProject(
        io,
        std.testing.allocator,
        project_root.dir,
        boot.ready.roots.registry().llmProviderConfig(),
        .{},
    );
    defer outcome.deinit();
    try std.testing.expect(outcome == .failed);
}

test "loads exact preset inheritance and publishes the safety-valid toolchain" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
    try project_root.dir.createDirPath(io, ".sdd/workflows");
    try project_root.dir.createDirPath(io, ".sdd/principles");
    try project_root.dir.createDirPath(io, ".sdd/presets");
    try project_root.dir.writeFile(io, .{ .sub_path = ".sdd/principles/toolchain.yaml", .data = "schema: project-toolchain/v1\npresets: [app@1.0.0]\npolicies: []\n" });
    try project_root.dir.writeFile(io, .{ .sub_path = ".sdd/presets/base.toolchain-preset.yaml", .data = "schema: toolchain-preset/v1\npackage: base@1.0.0\nlayer: language\nextends: []\npolicies: [project.zig@1]\n" });
    try project_root.dir.writeFile(io, .{ .sub_path = ".sdd/presets/app.toolchain-preset.yaml", .data = "schema: toolchain-preset/v1\npackage: app@1.0.0\nlayer: framework\nextends: [base@1.0.0]\npolicies: []\n" });
    var outcome = runInProject(io, std.testing.allocator, project_root.dir);
    defer outcome.deinit();
    try std.testing.expect(outcome == .ready);
    const valid = outcome.ready.toolchain.toolchain();
    try std.testing.expectEqualStrings("base@1.0.0", valid.packages()[0]);
    try std.testing.expectEqualStrings("app@1.0.0", valid.packages()[1]);
    try std.testing.expectEqual(@as(usize, 2), valid.policies().len);
}

test "one invalid unselected preset blocks complete toolchain publication" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
    try project_root.dir.createDirPath(io, ".sdd/workflows");
    try writeValidToolchain(io, project_root.dir);
    try project_root.dir.writeFile(io, .{
        .sub_path = ".sdd/presets/invalid.toolchain-preset.yaml",
        .data = "schema: toolchain-preset/v1\npackage: unused@1.0.0\nlayer: runtime\nextends: []\npolicies: []\nunknown: rejected\n",
    });
    var outcome = runInProject(io, std.testing.allocator, project_root.dir);
    defer outcome.deinit();
    try std.testing.expectEqual(@import("../domain/bootstrap_error.zig").PublicError.TOOLCHAIN_INVALID, outcome.failed);
}

test "one unselected preset with an unresolved dependency blocks the complete registry" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
    try project_root.dir.createDirPath(io, ".sdd/workflows");
    try writeValidToolchain(io, project_root.dir);
    try project_root.dir.writeFile(io, .{
        .sub_path = ".sdd/presets/unused.toolchain-preset.yaml",
        .data = "schema: toolchain-preset/v1\npackage: unused@1.0.0\nlayer: runtime\nextends: [missing@1.0.0]\npolicies: []\n",
    });
    var outcome = runInProject(io, std.testing.allocator, project_root.dir);
    defer outcome.deinit();
    try std.testing.expectEqual(@import("../domain/bootstrap_error.zig").PublicError.TOOLCHAIN_INVALID, outcome.failed);
}

test "toolchain loading rejects alternate project filenames and unsupported preset siblings" {
    const io = std.testing.io;
    inline for (.{ false, true }) |unsupported_preset_sibling| {
        var project_root = std.testing.tmpDir(.{});
        defer project_root.cleanup();
        try project_root.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
        try project_root.dir.createDirPath(io, ".sdd/workflows");
        try project_root.dir.createDirPath(io, ".sdd/principles");
        try project_root.dir.createDirPath(io, ".sdd/presets");
        if (unsupported_preset_sibling) {
            try project_root.dir.writeFile(io, .{
                .sub_path = ".sdd/principles/toolchain.yaml",
                .data = "schema: project-toolchain/v1\npresets: []\npolicies: []\n",
            });
            try project_root.dir.writeFile(io, .{
                .sub_path = ".sdd/presets/README.md",
                .data = "not preset authority",
            });
        } else {
            try project_root.dir.writeFile(io, .{
                .sub_path = ".sdd/principles/toolchain.yml",
                .data = "schema: project-toolchain/v1\npresets: []\npolicies: []\n",
            });
        }
        var outcome = runInProject(io, std.testing.allocator, project_root.dir);
        defer outcome.deinit();
        try std.testing.expectEqual(
            @import("../domain/bootstrap_error.zig").PublicError.TOOLCHAIN_INVALID,
            outcome.failed,
        );
    }
}

test "toolchain loading rejects a linked exact project document" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
    try project_root.dir.createDirPath(io, ".sdd/workflows");
    try project_root.dir.createDirPath(io, ".sdd/principles");
    try project_root.dir.createDirPath(io, ".sdd/presets");
    try project_root.dir.writeFile(io, .{
        .sub_path = ".sdd/principles/source.yaml",
        .data = "schema: project-toolchain/v1\npresets: []\npolicies: []\n",
    });
    try project_root.dir.symLink(
        io,
        "source.yaml",
        ".sdd/principles/toolchain.yaml",
        .{},
    );
    var outcome = runInProject(io, std.testing.allocator, project_root.dir);
    defer outcome.deinit();
    try std.testing.expectEqual(
        @import("../domain/bootstrap_error.zig").PublicError.TOOLCHAIN_INVALID,
        outcome.failed,
    );
}

const valid_workflow =
    \\schemaVersion: "1.0"
    \\workflowId: hello
    \\workflowVersion: 1
    \\workflowShortcode: HELO
    \\invocationContractNodeId: core.empty-invocation@1
    \\workflowPolicyProfileId: core.capability-free@1
    \\entryWorkflowNodeId: run
    \\nodes:
    \\  - workflowNodeId: run
    \\    pipelineNodeContractId: core.noop@1
    \\    parameters: []
    \\transitions:
    \\  - fromWorkflowNodeId: run
    \\    outcomeTag: ok
    \\    target:
    \\      kind: terminal
    \\      outcomeTag: ok
;
const second_workflow_same_shortcode =
    \\schemaVersion: "1.0"
    \\workflowId: goodbye
    \\workflowVersion: 1
    \\workflowShortcode: HELO
    \\invocationContractNodeId: core.empty-invocation@1
    \\workflowPolicyProfileId: core.capability-free@1
    \\entryWorkflowNodeId: run
    \\nodes:
    \\  - workflowNodeId: run
    \\    pipelineNodeContractId: core.noop@1
    \\    parameters: []
    \\transitions:
    \\  - fromWorkflowNodeId: run
    \\    outcomeTag: ok
    \\    target:
    \\      kind: terminal
    \\      outcomeTag: ok
;

fn writeValidToolchain(io: std.Io, project_root: std.Io.Dir) !void {
    try project_root.createDirPath(io, ".sdd/principles");
    try project_root.createDirPath(io, ".sdd/presets");
    try project_root.writeFile(io, .{
        .sub_path = ".sdd/principles/toolchain.yaml",
        .data = "schema: project-toolchain/v1\npresets: []\npolicies: []\n",
    });
}

fn createFeatureLogLayout(
    io: std.Io,
    project_root: std.Io.Dir,
    binding_permissions: std.Io.File.Permissions,
) !void {
    const owner_directory = std.Io.File.Permissions.fromMode(0o700);
    try project_root.createDir(io, "specs", owner_directory);
    try project_root.createDir(io, "specs/F0002", owner_directory);
    try project_root.createDir(io, "specs/F0002/logs", owner_directory);
    try project_root.createDir(io, "specs/F0002/logs/events", owner_directory);
    try project_root.createDir(io, "specs/F0002/logs/events/RUN-1", owner_directory);
    try project_root.createDir(io, "specs/F0002/logs/events/RUN-1/LOGBIND-1", binding_permissions);
    try project_root.createDir(io, "specs/F0002/logs/prompts", owner_directory);
    try project_root.createDir(io, "specs/F0002/logs/prompts/RUN-1", owner_directory);
    try project_root.createDir(io, "specs/F0002/logs/prompts/RUN-1/LOGBIND-1", binding_permissions);
}

test "loads and resolves a generic workflow definition from the configured root" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
    try project_root.dir.createDirPath(io, ".sdd/workflows/nested");
    try writeValidToolchain(io, project_root.dir);
    try project_root.dir.writeFile(io, .{
        .sub_path = ".sdd/workflows/nested/arbitrary-name.workflow.yaml",
        .data = valid_workflow,
    });

    var outcome = runInProject(io, std.testing.allocator, project_root.dir);
    defer outcome.deinit();
    try std.testing.expect(outcome == .ready);
    const registry = outcome.ready.workflows.registry();
    try std.testing.expectEqual(@as(usize, 1), registry.count());
    const graph = registry.resolve(workflow.WorkflowId.parse("hello").?);
    try std.testing.expect(graph != null);
    try std.testing.expectEqualStrings("core.noop@1", graph.?.authority.nodes[0].contract_id.bytes);
}

test "duplicate workflow shortcodes reject the complete registry" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
    try project_root.dir.createDirPath(io, ".sdd/workflows");
    try writeValidToolchain(io, project_root.dir);
    try project_root.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/hello.workflow.yaml", .data = valid_workflow });
    try project_root.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/goodbye.workflow.yaml", .data = second_workflow_same_shortcode });
    var outcome = runInProject(io, std.testing.allocator, project_root.dir);
    defer outcome.deinit();
    try std.testing.expectEqual(
        @import("../domain/bootstrap_error.zig").PublicError.WORKFLOW_REGISTRY_INVALID,
        outcome.failed,
    );
}

test "feature log storage opens only an activated layout from present artifact authority" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
    try project_root.dir.createDirPath(io, ".sdd/workflows");
    try writeValidToolchain(io, project_root.dir);
    try createFeatureLogLayout(io, project_root.dir, std.Io.File.Permissions.fromMode(0o700));
    var boot = runInProject(io, std.testing.allocator, project_root.dir);
    defer boot.deinit();
    try std.testing.expect(boot == .ready);
    const candidate: feature_log_runtime.BindingCandidate = .{
        .log_policy_id = @import("../domain/telemetry.zig").Identifier.validate("LOGPOL-1").?,
        .binding_id = @import("../domain/telemetry.zig").Identifier.validate("LOGBIND-1").?,
        .run_id = @import("../domain/telemetry.zig").Identifier.validate("RUN-1").?,
        .feature_id = @import("../domain/telemetry.zig").Identifier.validate("F0002").?,
    };
    const binding_owner = try feature_log_runtime.createValidatedBinding(std.testing.allocator, candidate);
    defer feature_log_runtime.deinitBindingOwner(binding_owner);
    const artifact_owner = try workflow_artifacts.createValidated(
        std.testing.allocator,
        boot.ready.roots.registry(),
        feature_log_runtime.binding(binding_owner),
    );
    defer workflow_artifacts.deinitOwner(artifact_owner);
    var sink = try feature_log_sink.Adapter.init(
        io,
        project_root.dir,
        workflow_artifacts.registry(artifact_owner),
        feature_log_runtime.binding(binding_owner),
    );
    defer sink.deinit();
    try project_root.dir.access(io, "specs/F0002/logs/events/RUN-1/LOGBIND-1", .{});
    try project_root.dir.access(io, "specs/F0002/logs/prompts/RUN-1/LOGBIND-1", .{});

    var stabilizer: TestStabilizer = .{};
    const active_runtime = try active_feature_log_runtime.create(
        std.testing.allocator,
        io,
        project_root.dir,
        boot.ready.logs.policy(),
        workflow_artifacts.registry(artifact_owner),
        feature_log_runtime.binding(binding_owner),
        stabilizer.port(),
    );
    defer active_feature_log_runtime.deinit(active_runtime);
    const shortcode = try @import("../domain/telemetry.zig").WorkflowShortcode.parse("TEST");
    try std.testing.expect(boot.ready.logs.activate(
        active_feature_log_runtime.runner(active_runtime),
        shortcode,
    ) == .ok);
    const persisted = boot.ready.logs.barrier().process(.{
        .workflow_shortcode = shortcode,
        .fact = .{ .event_type = .run_started },
    });
    try std.testing.expect(persisted == .persisted);
    try project_root.dir.access(io, "specs/F0002/logs/events/RUN-1/LOGBIND-1/0001.log", .{});
    try std.testing.expect(boot.ready.logs.finalizeActive(shortcode) == .ok);
    const bytes = try project_root.dir.readFileAlloc(
        io,
        "specs/F0002/logs/events/RUN-1/LOGBIND-1/0001.log",
        std.testing.allocator,
        .limited(@import("../domain/logging.zig").max_segment_bytes),
    );
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "segment_trailer|") != null);
}

test "feature log sink neither creates a missing activation layout nor accepts insecure directories" {
    const io = std.testing.io;
    inline for (.{ false, true }) |insecure_layout| {
        var project_root = std.testing.tmpDir(.{});
        defer project_root.cleanup();
        try project_root.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
        try project_root.dir.createDirPath(io, ".sdd/workflows");
        try writeValidToolchain(io, project_root.dir);
        if (insecure_layout) {
            try createFeatureLogLayout(io, project_root.dir, std.Io.File.Permissions.fromMode(0o755));
        } else {
            try project_root.dir.createDir(io, "specs", std.Io.File.Permissions.fromMode(0o700));
        }
        var boot = runInProject(io, std.testing.allocator, project_root.dir);
        defer boot.deinit();
        try std.testing.expect(boot == .ready);
        const candidate: feature_log_runtime.BindingCandidate = .{
            .log_policy_id = @import("../domain/telemetry.zig").Identifier.validate("LOGPOL-1").?,
            .binding_id = @import("../domain/telemetry.zig").Identifier.validate("LOGBIND-1").?,
            .run_id = @import("../domain/telemetry.zig").Identifier.validate("RUN-1").?,
            .feature_id = @import("../domain/telemetry.zig").Identifier.validate("F0002").?,
        };
        const binding_owner = try feature_log_runtime.createValidatedBinding(std.testing.allocator, candidate);
        defer feature_log_runtime.deinitBindingOwner(binding_owner);
        const artifact_owner = try workflow_artifacts.createValidated(
            std.testing.allocator,
            boot.ready.roots.registry(),
            feature_log_runtime.binding(binding_owner),
        );
        defer workflow_artifacts.deinitOwner(artifact_owner);
        const result = feature_log_sink.Adapter.init(
            io,
            project_root.dir,
            workflow_artifacts.registry(artifact_owner),
            feature_log_runtime.binding(binding_owner),
        );
        if (insecure_layout) {
            try std.testing.expectError(error.InsecurePermissions, result);
        } else {
            try std.testing.expectError(error.ArtifactStorageUnavailable, result);
            try std.testing.expectError(error.FileNotFound, project_root.dir.access(io, "specs/F0002", .{}));
        }
    }
}

test "absent optional specs root cannot mint workflow artifact authority" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
    try project_root.dir.createDirPath(io, ".sdd/workflows");
    try writeValidToolchain(io, project_root.dir);
    var boot = runInProject(io, std.testing.allocator, project_root.dir);
    defer boot.deinit();
    try std.testing.expect(boot == .ready);
    const candidate: feature_log_runtime.BindingCandidate = .{
        .log_policy_id = @import("../domain/telemetry.zig").Identifier.validate("LOGPOL-1").?,
        .binding_id = @import("../domain/telemetry.zig").Identifier.validate("LOGBIND-1").?,
        .run_id = @import("../domain/telemetry.zig").Identifier.validate("RUN-1").?,
        .feature_id = @import("../domain/telemetry.zig").Identifier.validate("F0002").?,
    };
    const binding_owner = try feature_log_runtime.createValidatedBinding(std.testing.allocator, candidate);
    defer feature_log_runtime.deinitBindingOwner(binding_owner);
    try std.testing.expectError(
        error.InvalidWorkflowArtifactRegistry,
        workflow_artifacts.createValidated(
            std.testing.allocator,
            boot.ready.roots.registry(),
            feature_log_runtime.binding(binding_owner),
        ),
    );
}

test "one unsupported workflow sibling blocks the complete registry" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
    try project_root.dir.createDirPath(io, ".sdd/workflows");
    try project_root.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/hello.workflow.yaml", .data = valid_workflow });
    try project_root.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/notes.txt", .data = "unsupported" });

    var outcome = runInProject(io, std.testing.allocator, project_root.dir);
    defer outcome.deinit();
    try std.testing.expectEqual(
        @import("../domain/bootstrap_error.zig").PublicError.WORKFLOW_AUTHORITY_INVENTORY_INVALID,
        outcome.failed,
    );
}

test "deadline exhaustion during root validation fails without publishing services" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{
        .sub_path = ".sddtoolkit.json",
        .data = valid_config,
    });
    try project_root.dir.createDirPath(io, ".sdd/workflows");

    var control: RuntimeAfterObservations = .{
        .active_observations_remaining = 10,
        .terminal = .deadline_exhausted,
    };
    var outcome = runInProjectWithRuntime(
        io,
        std.testing.allocator,
        project_root.dir,
        control.runtime(),
    );
    defer outcome.deinit();

    try std.testing.expectEqual(
        @import("../domain/bootstrap_error.zig").PublicError.BOOTSTRAP_ROOT_RESOLUTION_ERROR,
        outcome.failed,
    );
}

test "cancellation after config capture releases intermediates without publishing services" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{
        .sub_path = ".sddtoolkit.json",
        .data = valid_config,
    });
    try project_root.dir.createDirPath(io, ".sdd/workflows");

    var control: RuntimeAfterObservations = .{
        .active_observations_remaining = 4,
        .terminal = .cancelled,
    };
    var outcome = runInProjectWithRuntime(
        io,
        std.testing.allocator,
        project_root.dir,
        control.runtime(),
    );
    defer outcome.deinit();
    try std.testing.expect(outcome == .cancelled);
}

const RuntimeAfterObservations = struct {
    active_observations_remaining: usize,
    terminal: pipeline.RuntimeStatus,

    fn runtime(self: *RuntimeAfterObservations) pipeline.NodeRuntime {
        return .{ .context = self, .status_fn = status };
    }

    fn status(context: ?*anyopaque) pipeline.RuntimeStatus {
        const self: *RuntimeAfterObservations = @ptrCast(@alignCast(context.?));
        if (self.active_observations_remaining == 0) return self.terminal;
        self.active_observations_remaining -= 1;
        return .active;
    }
};

const TestStabilizer = struct {
    calls: usize = 0,

    fn port(self: *TestStabilizer) stabilizer_port.Stabilizer {
        return .{ .context = self, .stabilize_fn = stabilize };
    }

    fn stabilize(context: *anyopaque) stabilizer_port.Error!void {
        const self: *TestStabilizer = @ptrCast(@alignCast(context));
        self.calls += 1;
    }
};

test "missing exact config returns the public read error" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();

    var outcome = runInProject(io, std.testing.allocator, project_root.dir);
    defer outcome.deinit();
    try std.testing.expectEqual(
        @import("../domain/bootstrap_error.zig").PublicError.ENGINE_CONFIG_READ_ERROR,
        outcome.failed,
    );
}

test "malformed config returns the public parse error without publishing services" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{
        .sub_path = ".sddtoolkit.json",
        .data = "{",
    });

    var outcome = runInProject(io, std.testing.allocator, project_root.dir);
    defer outcome.deinit();
    try std.testing.expectEqual(
        @import("../domain/bootstrap_error.zig").PublicError.ENGINE_CONFIG_PARSE_ERROR,
        outcome.failed,
    );
}

test "missing workflow authority fails before publishing services" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{
        .sub_path = ".sddtoolkit.json",
        .data = valid_config,
    });

    var outcome = runInProject(io, std.testing.allocator, project_root.dir);
    defer outcome.deinit();
    try std.testing.expectEqual(
        @import("../domain/bootstrap_error.zig").PublicError.BOOTSTRAP_ROOT_RESOLUTION_ERROR,
        outcome.failed,
    );
}

test "a complete root collision fails as a registry error" {
    const io = std.testing.io;
    const colliding_config =
        \\{
        \\  "logs": { "level": "debug", "console": false, "promptCapture": [] },
        \\  "models": { "slots": {} },
        \\  "paths": {
        \\    "specs": "specs", "references": "SPECS",
        \\    "specsArchive": "specs/archive", "workflows": ".sdd/workflows",
        \\    "toolchainPreset": ".sdd/presets",
        \\    "principles": ".sdd/principles", "templates": ".sdd/templates",
        \\    "providers": ".sddproviders.json"
        \\  }
        \\}
    ;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{
        .sub_path = ".sddtoolkit.json",
        .data = colliding_config,
    });
    try project_root.dir.createDirPath(io, ".sdd/workflows");

    var outcome = runInProject(io, std.testing.allocator, project_root.dir);
    defer outcome.deinit();
    try std.testing.expectEqual(
        @import("../domain/bootstrap_error.zig").PublicError.BOOTSTRAP_ROOT_REGISTRY_INVALID,
        outcome.failed,
    );
}

test "normalization-equivalent absent roots fail as a registry error" {
    const io = std.testing.io;
    const colliding_config =
        \\{
        \\  "logs": { "level": "debug", "console": false, "promptCapture": [] },
        \\  "models": { "slots": {} },
        \\  "paths": {
        \\    "specs": "shared", "references": "shared/",
        \\    "specsArchive": "shared/archive", "workflows": ".sdd/workflows",
        \\    "toolchainPreset": ".sdd/presets",
        \\    "principles": ".sdd/principles", "templates": ".sdd/templates",
        \\    "providers": ".sddproviders.json"
        \\  }
        \\}
    ;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{
        .sub_path = ".sddtoolkit.json",
        .data = colliding_config,
    });
    try project_root.dir.createDirPath(io, ".sdd/workflows");

    var outcome = runInProject(io, std.testing.allocator, project_root.dir);
    defer outcome.deinit();
    try std.testing.expectEqual(
        @import("../domain/bootstrap_error.zig").PublicError.BOOTSTRAP_ROOT_REGISTRY_INVALID,
        outcome.failed,
    );
}
