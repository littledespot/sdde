const std = @import("std");
const pipeline = @import("../domain/pipeline.zig");
const config = @import("../domain/config.zig");
const bootstrap_root_registry = @import("../domain/bootstrap_root_registry.zig");
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
const validate_path_policy = @import("../actions/bootstrap/validate_configured_root_path_policy.zig");
const validate_provider_path_policy = @import("../actions/bootstrap/validate_llm_provider_config_path_policy.zig");
const resolve_root = @import("../actions/bootstrap/resolve_configured_base_root.zig");
const resolve_provider_path = @import("../actions/bootstrap/resolve_llm_provider_config_path.zig");
const validate_root = @import("../actions/bootstrap/validate_configured_base_root.zig");
const build_registry_id = @import("../actions/bootstrap/build_bootstrap_root_registry_id.zig");
const build_registry = @import("../actions/bootstrap/build_bootstrap_root_registry.zig");
const validate_registry = @import("../actions/bootstrap/validate_bootstrap_root_registry.zig");
const build_workflow_layout = @import("../actions/workflow/build_workflow_authority_layout.zig");
const enumerate_workflow_resources = @import("../actions/workflow/enumerate_workflow_authority_resources.zig");
const normalize_workflow_entries = @import("../actions/workflow/normalize_workflow_authority_entries.zig");
const build_workflow_accounts = @import("../actions/workflow/build_workflow_authority_entry_accounts.zig");
const build_workflow_inventory = @import("../actions/workflow/build_workflow_authority_inventory.zig");
const validate_workflow_inventory = @import("../actions/workflow/validate_workflow_authority_inventory.zig");
const capture_workflows = @import("../actions/workflow/capture_workflow_definitions.zig");
const parse_workflows = @import("../actions/workflow/parse_workflow_definitions.zig");
const validate_workflow_schema = @import("../actions/workflow/validate_workflow_definition_schema.zig");
const resolve_workflow_resources = @import("../actions/workflow/resolve_workflow_resources.zig");
const capture_workflow_resources = @import("../actions/workflow/capture_workflow_resources.zig");
const validate_workflow_operations = @import("../actions/workflow/validate_workflow_operation_registry.zig");
const compile_workflows = @import("../actions/workflow/compile_workflow_graphs.zig");
const validate_workflow_graphs = @import("../actions/workflow/validate_compiled_workflow_graphs.zig");
const build_workflow_registry = @import("../actions/workflow/build_workflow_definition_registry.zig");
const validate_workflow_registry = @import("../actions/workflow/validate_workflow_definition_registry.zig");
const workflow = @import("../domain/workflow.zig");
const workflow_compilation = @import("../domain/workflow_compilation.zig");
const workflow_execution = @import("../domain/workflow_execution.zig");
const telemetry = @import("../domain/telemetry.zig");
const model_provider_requirement = @import("../domain/model_provider_requirement.zig");
const llm_provider_identity = @import("../domain/llm_provider_identity.zig");
const bootstrap_orchestrator = @import("../application/bootstrap_orchestrator.zig");
const bootstrap_runner = @import("../application/bootstrap_runner.zig");
const bootstrap_execution = @import("../application/bootstrap_execution.zig");
const bootstrap_config_runner = @import("../application/bootstrap_config_runner.zig");
const bootstrap_root_runner = @import("../application/bootstrap_root_runner.zig");
const bootstrap_workflow_runner = @import("../application/bootstrap_workflow_runner.zig");
const llm_provider_contracts = @import("../domain/llm_provider_contracts.zig");
const llm_provider_registry = @import("../domain/llm_provider_registry.zig");
const repository_model_allowlist = @import("../domain/repository_model_allowlist.zig");
const toolchain = @import("../domain/toolchain.zig");
const run_outcome = @import("../domain/run_outcome.zig");
const workflow_engine = @import("../application/workflow_engine_orchestrator.zig");
const model_provider_bootstrap_binding = @import("../application/model_provider_bootstrap_binding.zig");
const model_provider_bootstrap_orchestrator = @import("../application/model_provider_bootstrap_orchestrator.zig");
const model_provider_bootstrap_services = @import("../application/model_provider_bootstrap_services.zig");
const llm_provider_registry_service = @import("../application/llm_provider_registry_service.zig");
const core_workflow_operations = @import("core_workflow_operations.zig");
const workflow_artifacts = @import("../domain/workflow_artifact_registry.zig");
const log_binding = @import("../domain/feature_log_binding.zig");
const log_limits = @import("../domain/feature_log_limits.zig");
const feature_log_sink = @import("../adapters/filesystem/feature_log_sink.zig");
const active_feature_log_runtime = @import("active_feature_log_runtime.zig");
const feature_log_finalization_runner = @import("../application/feature_log_finalization_runner.zig");
const model_provider_bootstrap = @import("model_provider_bootstrap.zig");
const engine_invocation = @import("engine_invocation.zig");
const workflow_operation_registry = @import("../ports/workflow_operation_registry.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, arguments: []const []const u8) run_outcome.Outcome {
    return runInvocationInProject(io, allocator, .cwd(), arguments);
}

fn runInvocationInProject(
    io: std.Io,
    allocator: std.mem.Allocator,
    project_root: std.Io.Dir,
    arguments: []const []const u8,
) run_outcome.Outcome {
    return runInvocationInProjectWithRuntime(io, allocator, project_root, arguments, .{});
}

fn runInvocationInProjectWithRuntime(io: std.Io, allocator: std.mem.Allocator, project_root: std.Io.Dir, arguments: []const []const u8, runtime: pipeline.NodeRuntime) run_outcome.Outcome {
    var toolchain_source_adapter = toolchain_authority_source.Adapter.init(io, project_root);
    var toolchain_parser_adapter: toolchain_documents.Adapter = .{};
    var reference_adapter: @import("../adapters/filesystem/reference_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project_root };
    var feature_adapter: @import("../adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project_root };
    var native_bindings: @import("native_workflow_operations.zig").Assembly = undefined;
    native_bindings.init(allocator, toolchain_source_adapter.projectCapturer(), toolchain_source_adapter.presetEnumerator(), toolchain_source_adapter.presetCapturer(), toolchain_parser_adapter.parser(), policy_registry, .{ .normalize_fn = @import("unicode_normalization").nfc }, reference_adapter.inspector(), feature_adapter.inspector());
    var boot = runInProjectWithRegistry(io, allocator, project_root, runtime, &native_bindings.registry);
    if (boot == .ready) native_bindings.bindRoots(boot.ready.roots.registry());
    defer boot.deinit();
    var provider_bootstrap = model_provider_bootstrap.Assembly.init(
        io,
        allocator,
        project_root,
        .{},
        &llm_provider_contracts.Registry.empty,
    );
    return runBootstrappedInvocation(
        allocator,
        &boot,
        arguments,
        &native_bindings.registry,
        provider_bootstrap.bind(),
        runtime,
    );
}

fn runBootstrappedInvocation(
    allocator: std.mem.Allocator,
    boot: *bootstrap_orchestrator.Outcome,
    arguments: []const []const u8,
    operation_registry: *const workflow_operation_registry.Registry,
    provider_bootstrap: model_provider_bootstrap_binding.Binding,
    runtime: pipeline.NodeRuntime,
) run_outcome.Outcome {
    return switch (boot.*) {
        .failed => |failure| .{ .bootstrap_failed = failure },
        .cancelled => .{ .execution = .cancelled },
        .ready => |*services| execute: {
            var invocation = engine_invocation.Assembly.init(
                allocator,
                services,
                arguments,
                operation_registry,
                provider_bootstrap,
                runtime,
            );
            defer invocation.deinit();
            break :execute workflow_engine.run(invocation.bindings());
        },
    };
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
    return runInProjectWithRegistry(io, allocator, project_root, runtime, &core_workflow_operations.registry);
}

fn runInProjectWithRegistry(
    io: std.Io,
    allocator: std.mem.Allocator,
    project_root: std.Io.Dir,
    runtime: pipeline.NodeRuntime,
    operation_registry: *const workflow_operation_registry.Registry,
) bootstrap_orchestrator.Outcome {
    var source_adapter = engine_config_source.Adapter.init(io, project_root);
    var root_adapter = bootstrap_root_inspector.Adapter.init(io, project_root);
    var workflow_source_adapter = workflow_authority_source.Adapter.init(io, project_root);
    var workflow_parser_adapter: workflow_definitions.Adapter = .{};
    var result_schema_adapter: @import("../adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const policy_resolver = workspace_path_policy.Resolver.init(io, project_root);
    const active_path_policy = policy_resolver.resolve(allocator) catch {
        return .{ .failed = .BOOTSTRAP_ROOT_RESOLUTION_ERROR };
    };
    var execution_state: bootstrap_execution.State = .{ .runtime = runtime };
    var config_pipeline = bootstrap_config_runner.Runner.init(
        allocator,
        &execution_state,
        locate.Action{ .locator = source_adapter.locator() },
        read.Action{},
        decode.Action{},
        canonicalize_log_level.Action{},
        validate_logging_policy.Action{},
    );
    defer config_pipeline.deinit();
    var root_pipeline = bootstrap_root_runner.Runner.init(
        allocator,
        &execution_state,
        &config_pipeline,
        validate_path_policy.Action{ .policy = active_path_policy },
        validate_provider_path_policy.Action{ .policy = active_path_policy },
        resolve_root.Action{ .policy = active_path_policy },
        resolve_provider_path.Action{ .policy = active_path_policy },
        validate_root.Action{ .inspector = root_adapter.inspector() },
        build_registry_id.Action{},
        build_registry.Action{},
        validate_registry.Action{},
    );
    defer root_pipeline.deinit();
    var workflow_pipeline = bootstrap_workflow_runner.Runner.init(
        allocator,
        &execution_state,
        &root_pipeline,
        build_workflow_layout.Action{},
        enumerate_workflow_resources.Action{ .source = workflow_source_adapter.enumerator() },
        normalize_workflow_entries.Action{},
        build_workflow_accounts.Action{},
        build_workflow_inventory.Action{},
        validate_workflow_inventory.Action{},
        capture_workflows.Action{ .source = workflow_source_adapter.capturer() },
        parse_workflows.Action{ .parser = workflow_parser_adapter.parser() },
        validate_workflow_schema.Action{},
        resolve_workflow_resources.Action{},
        capture_workflow_resources.Action{ .source = workflow_source_adapter.capturer() },
        validate_workflow_operations.Action{},
        compile_workflows.Action{ .registry = operation_registry, .result_schema_compiler = result_schema_adapter.compiler() },
        validate_workflow_graphs.Action{},
        build_workflow_registry.Action{},
        validate_workflow_registry.Action{},
    );
    defer workflow_pipeline.deinit();

    var runner: bootstrap_runner.Runner = .{
        .config = &config_pipeline,
        .roots = &root_pipeline,
        .workflows = &workflow_pipeline,
    };

    return bootstrap_orchestrator.run(runner.bindings());
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
    try std.testing.expect(!@hasField(@TypeOf(outcome.ready), "toolchain"));
    try std.testing.expect(
        outcome.ready.roots.registry() == outcome.ready.roots.registry(),
    );
}

test "provider bootstrap assembly loads only the configured F0008 path" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    const config_with_nested_provider =
        \\{
        \\  "logs": { "level": "debug", "console": false, "promptCapture": [] },
        \\  "models": { "slots": {
        \\    "implementation": { "provider": "compiled-provider", "model": "model-a" }
        \\  } },
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
        .data = test_provider_document,
    });

    var boot = runInProject(io, std.testing.allocator, project_root.dir);
    defer boot.deinit();
    try std.testing.expect(boot == .ready);

    var assembly = model_provider_bootstrap.Assembly.init(
        io,
        std.testing.allocator,
        project_root.dir,
        .{},
        &test_provider_contracts,
    );
    const selected = testModelSelectedWorkflow();
    var outcome = assembly.bind().invoke(
        &selected,
        &boot.ready.config.config().models,
        boot.ready.roots.registry().llmProviderConfig(),
    );
    defer outcome.deinit();
    try std.testing.expect(outcome == .ready);
    try std.testing.expect(outcome.ready.registry().resolve(
        test_provider_id,
        llm_provider_identity.ModelId.parse("model-a").?,
    ) != null);
    try std.testing.expect(outcome.ready.allowlist().resolveSlot(
        llm_provider_identity.ModelSlotId.parse("implementation").?,
    ) != null);

    var control: RuntimeAfterObservations = .{
        .active_observations_remaining = 3,
        .terminal = .cancelled,
    };
    var cancelled_assembly = model_provider_bootstrap.Assembly.init(
        io,
        std.testing.allocator,
        project_root.dir,
        control.runtime(),
        &test_provider_contracts,
    );
    var cancelled = cancelled_assembly.bind().invoke(
        &selected,
        &boot.ready.config.config().models,
        boot.ready.roots.registry().llmProviderConfig(),
    );
    defer cancelled.deinit();
    try std.testing.expect(cancelled == .cancelled);
}

test "capability-free invocation does not probe a missing provider document" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{
        .sub_path = ".sddtoolkit.json",
        .data = valid_config,
    });
    try project_root.dir.createDirPath(io, ".sdd/workflows");
    try project_root.dir.writeFile(io, .{
        .sub_path = ".sdd/workflows/hello.workflow.yaml",
        .data = valid_workflow,
    });

    const outcome = runInvocationInProject(
        io,
        std.testing.allocator,
        project_root.dir,
        &.{"hello"},
    );
    try std.testing.expectEqual(workflow_execution.Outcome.ok, outcome.execution);
}

test "invocation runner handles every provider preparation outcome before workflow execution" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{
        .sub_path = ".sddtoolkit.json",
        .data = valid_config,
    });
    try project_root.dir.createDirPath(io, ".sdd/workflows");
    try project_root.dir.writeFile(io, .{
        .sub_path = ".sdd/workflows/hello.workflow.yaml",
        .data = valid_workflow,
    });

    var boot = runInProject(io, std.testing.allocator, project_root.dir);
    defer boot.deinit();
    try std.testing.expect(boot == .ready);

    inline for (.{
        PreparationMode.not_required,
        PreparationMode.ready,
        PreparationMode.failed,
        PreparationMode.cancelled,
    }) |mode| {
        var probe: InvocationPreparationProbe = .{ .mode = mode };
        const outcome = runBootstrappedInvocation(
            std.testing.allocator,
            &boot,
            &.{"hello"},
            probe.registry(),
            probe.providerBinding(),
            .{},
        );

        try std.testing.expectEqual(@as(usize, 1), probe.prepare_calls);
        try std.testing.expectEqualStrings("hello", probe.selected_workflow_id.?);
        switch (mode) {
            .not_required, .ready => {
                try std.testing.expectEqual(workflow_execution.Outcome.ok, outcome.execution);
                try std.testing.expectEqual(@as(usize, 1), probe.observation.invocation_calls);
                try std.testing.expectEqual(@as(usize, 1), probe.observation.step_calls);
            },
            .failed => {
                try std.testing.expectEqual(
                    @import("../domain/bootstrap_error.zig").PublicError.LLM_PROVIDER_CONFIG_PARSE_ERROR,
                    outcome.bootstrap_failed,
                );
                try std.testing.expectEqual(@as(usize, 0), probe.observation.invocation_calls);
                try std.testing.expectEqual(@as(usize, 0), probe.observation.step_calls);
            },
            .cancelled => {
                try std.testing.expectEqual(workflow_execution.Outcome.cancelled, outcome.execution);
                try std.testing.expectEqual(@as(usize, 0), probe.observation.invocation_calls);
                try std.testing.expectEqual(@as(usize, 0), probe.observation.step_calls);
            },
        }
    }

    var invalid_probe: InvocationPreparationProbe = .{ .mode = .not_required };
    const invalid = runBootstrappedInvocation(
        std.testing.allocator,
        &boot,
        &.{"absent-workflow"},
        invalid_probe.registry(),
        invalid_probe.providerBinding(),
        .{},
    );
    try std.testing.expect(invalid == .invocation_invalid);
    try std.testing.expectEqual(@as(usize, 0), invalid_probe.prepare_calls);
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
    try expectToolchainRun(io, project_root.dir, .ok, &.{ "base@1.0.0", "app@1.0.0" }, 2);
}

test "unrelated workflows do not load toolchain documents even with a toolchain workflow installed" {
    const io = std.testing.io;
    inline for (.{ false, true }) |malformed| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try project.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
        try project.dir.createDirPath(io, ".sdd/workflows");
        try project.dir.createDirPath(io, ".sdd/principles");
        try project.dir.createDirPath(io, ".sdd/presets");
        try project.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/hello.workflow.yaml", .data = valid_workflow });
        try project.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/toolchain.workflow.yaml", .data = @embedFile("../test_fixtures/toolchain.workflow.yaml") });
        const audit = try std.mem.replaceOwned(u8, std.testing.allocator, valid_workflow, "hello", "independent-audit");
        defer std.testing.allocator.free(audit);
        const unique = try std.mem.replaceOwned(u8, std.testing.allocator, audit, "HELO", "AUDT");
        defer std.testing.allocator.free(unique);
        try project.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/audit.workflow.yaml", .data = unique });
        if (malformed) {
            try project.dir.writeFile(io, .{ .sub_path = ".sdd/principles/toolchain.yaml", .data = "not a toolchain" });
            try project.dir.writeFile(io, .{ .sub_path = ".sdd/presets/invalid.toolchain-preset.yaml", .data = "not a preset" });
        }
        inline for (.{ "hello", "independent-audit" }) |id| {
            try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{id}).execution);
        }
        try std.testing.expectEqual(workflow.OutcomeTag.failed, runInvocationInProject(io, std.testing.allocator, project.dir, &.{"toolchain-check"}).execution);
    }
}

test "toolchain YAML rejects denied capabilities and missing data predecessors before execution" {
    const io = std.testing.io;
    inline for (.{ false, true }) |missing_input| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try project.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
        try project.dir.createDirPath(io, ".sdd/workflows");
        const fixture = @embedFile("../test_fixtures/toolchain.workflow.yaml");
        const yaml = if (missing_input)
            try std.mem.replaceOwned(u8, std.testing.allocator, fixture, "capture-project: { use: capture-project-toolchain@1", "capture-project: { use: core.noop@1")
        else
            try std.mem.replaceOwned(u8, std.testing.allocator, fixture, "policy: core.toolchain@1", "policy: core.capability-free@1");
        defer std.testing.allocator.free(yaml);
        // Keep the replacement operation's outcome set exact so this case
        // specifically exercises the missing project-capture input.
        const exact = if (missing_input)
            try std.mem.replaceOwned(u8, std.testing.allocator, yaml, "capture-project: { use: core.noop@1, on: { ok: inventory-presets, failed: end.failed } }", "capture-project: { use: core.noop@1, on: { ok: inventory-presets } }")
        else
            try std.testing.allocator.dupe(u8, yaml);
        defer std.testing.allocator.free(exact);
        try project.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/toolchain.workflow.yaml", .data = exact });
        const result = runInvocationInProject(io, std.testing.allocator, project.dir, &.{"toolchain-check"});
        try std.testing.expectEqual(@import("../domain/bootstrap_error.zig").PublicError.WORKFLOW_GRAPH_COMPILE_INVALID, result.bootstrap_failed);
    }
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
    try expectToolchainRun(io, project_root.dir, .failed, &.{}, 0);
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
    try expectToolchainRun(io, project_root.dir, .failed, &.{}, 0);
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
        try expectToolchainRun(io, project_root.dir, .failed, &.{}, 0);
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
    try expectToolchainRun(io, project_root.dir, .failed, &.{}, 0);
}

const valid_workflow =
    \\schema: workflow/v1
    \\id: hello
    \\version: 1
    \\shortcode: HELO
    \\invoke: core.empty-invocation@1
    \\policy: core.capability-free@1
    \\start: run
    \\steps:
    \\  run:
    \\    use: core.noop@1
    \\    on: { ok: end.ok }
;

fn expectToolchainRun(io: std.Io, project_root: std.Io.Dir, expected: workflow.OutcomeTag, expected_packages: []const []const u8, expected_policies: usize) !void {
    try std.testing.expectEqual(expected, try inspectToolchainRun(io, project_root, .{}, expected_packages, expected_policies));
}

fn inspectToolchainRun(io: std.Io, project_root: std.Io.Dir, runtime: pipeline.NodeRuntime, expected_packages: []const []const u8, expected_policies: usize) !workflow.OutcomeTag {
    try project_root.writeFile(io, .{ .sub_path = ".sdd/workflows/toolchain.workflow.yaml", .data = @embedFile("../test_fixtures/toolchain.workflow.yaml") });
    var source = toolchain_authority_source.Adapter.init(io, project_root);
    var parser: toolchain_documents.Adapter = .{};
    var reference_adapter: @import("../adapters/filesystem/reference_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project_root };
    var feature_adapter: @import("../adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project_root };
    var operations: @import("native_workflow_operations.zig").Assembly = undefined;
    operations.init(std.testing.allocator, source.projectCapturer(), source.presetEnumerator(), source.presetCapturer(), parser.parser(), policy_registry, .{ .normalize_fn = @import("unicode_normalization").nfc }, reference_adapter.inspector(), feature_adapter.inspector());
    var boot = runInProjectWithRegistry(io, std.testing.allocator, project_root, .{}, &operations.registry);
    defer boot.deinit();
    try std.testing.expect(boot == .ready);
    operations.bindRoots(boot.ready.roots.registry());
    var provider = model_provider_bootstrap.Assembly.init(io, std.testing.allocator, project_root, .{}, &llm_provider_contracts.Registry.empty);
    var invocation = engine_invocation.Assembly.init(std.testing.allocator, &boot.ready, &.{"toolchain-check"}, &operations.registry, provider.bind(), runtime);
    defer invocation.deinit();
    const result = workflow_engine.run(invocation.bindings()).execution;
    const read_contract: pipeline.NodeContract = .{ .id = "test-toolchain-consumer@1", .kind = .action, .requires = &.{.valid_toolchain}, .produces = &.{}, .side_effect = .none };
    if (result != .ok) {
        if (invocation.pipeline_runner) |*runner| try std.testing.expectError(error.MissingRequiredData, runner.envelope.view(read_contract));
        return result;
    }
    const view = try invocation.pipeline_runner.?.envelope.view(read_contract);
    const valid = try @import("../application/pipeline_values.zig").read(&view, @import("../application/toolchain_workflow_values.zig").valid, @import("../domain/toolchain_safety.zig").ValidToolchain);
    const service = @import("../application/toolchain_service.zig").ToolChainService.init(valid);
    try std.testing.expect(service.toolchain() == valid);
    try std.testing.expectEqual(expected_packages.len, valid.packages().len);
    for (expected_packages, valid.packages()) |expected_package, package| try std.testing.expectEqualStrings(expected_package, package);
    try std.testing.expectEqual(expected_policies, valid.policies().len);
    try std.testing.expectEqualStrings("core.safety@1", valid.policies()[0].id);
    return result;
}

test "selected toolchain cancellation stops at every runtime boundary without publishing a partial result" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
    try project.dir.createDirPath(io, ".sdd/workflows");
    try writeValidToolchain(io, project.dir);
    for (0..256) |checks| {
        var control: RuntimeAfterObservations = .{ .active_observations_remaining = checks, .terminal = .cancelled };
        const result = try inspectToolchainRun(io, project.dir, control.runtime(), &.{}, 1);
        if (result == .ok) {
            try std.testing.expect(checks > 9);
            return;
        }
        try std.testing.expectEqual(workflow.OutcomeTag.cancelled, result);
    }
    return error.ToolchainNeverCompleted;
}
fn writeReferencePreflightFixture(io: std.Io, project: std.Io.Dir) !void {
    try project.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
    try project.createDirPath(io, ".sdd/workflows");
    try project.writeFile(io, .{ .sub_path = ".sdd/workflows/preflight.workflow.yaml", .data = @embedFile("../test_fixtures/reference-preflight.workflow.yaml") });
    try project.writeFile(io, .{ .sub_path = ".sdd/workflows/hello.workflow.yaml", .data = valid_workflow });
}

test "reference preflight uses ordinary YAML and leaves reference and artifact trees unchanged" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try writeReferencePreflightFixture(io, project.dir);
    try project.dir.createDirPath(io, "references/Café/日本語");
    try project.dir.writeFile(io, .{ .sub_path = "references/Café/日本語/stories.md", .data = "Hello, World!\n" });
    for ([_][]const u8{ "Café/日本語", "./Cafe\u{301}\\日本語" }) |selector| {
        const result = runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "Hello/日本語", "--reference", selector });
        try std.testing.expectEqual(workflow.OutcomeTag.ok, result.execution);
    }
    const bytes = try project.dir.readFileAlloc(io, "references/Café/日本語/stories.md", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("Hello, World!\n", bytes);
    try std.testing.expectError(error.FileNotFound, project.dir.openDir(io, "specs", .{}));
    try std.testing.expectError(error.FileNotFound, project.dir.openDir(io, ".sdd/workflows/features", .{}));
    try std.testing.expectError(error.FileNotFound, project.dir.openDir(io, ".sdd/workflows/transactions", .{}));
}

test "unrelated workflows never require the installed reference operations to run" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try writeReferencePreflightFixture(io, project.dir);
    try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{"hello"}).execution);
    try std.testing.expectEqual(workflow.OutcomeTag.failed, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "Hello/日本語", "--reference", "missing" }).execution);
    // The same contracts work under a different workflow ID; no name dispatch.
    const changed = try std.mem.replaceOwned(u8, std.testing.allocator, @embedFile("../test_fixtures/reference-preflight.workflow.yaml"), "id: reference-preflight", "id: documentation-check");
    defer std.testing.allocator.free(changed);
    try project.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/preflight.workflow.yaml", .data = changed });
    try project.dir.createDirPath(io, "references/manual");
    try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "documentation-check", "--feature", "Hello/日本語", "--reference", "manual" }).execution);
}

test "reference preflight rejects missing arguments files unreadable directories and symlink ancestors" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try writeReferencePreflightFixture(io, project.dir);
    try project.dir.createDirPath(io, "references/real/child");
    try project.dir.createDirPath(io, "outside/child");
    try project.dir.writeFile(io, .{ .sub_path = "references/file", .data = "not a directory" });
    try project.dir.symLink(io, "real", "references/alias", .{ .is_directory = true });
    try project.dir.symLink(io, "../outside", "references/escape", .{ .is_directory = true });
    const arguments = [_][]const []const u8{
        &.{"reference-preflight"},
        &.{ "reference-preflight", "--feature", "Hello/日本語", "--reference", "missing" },
        &.{ "reference-preflight", "--feature", "Hello/日本語", "--reference", "file" },
        &.{ "reference-preflight", "--feature", "Hello/日本語", "--reference", "../outside" },
        &.{ "reference-preflight", "--feature", "Hello/日本語", "--reference", "alias/child" },
        &.{ "reference-preflight", "--feature", "Hello/日本語", "--reference", "escape/child" },
    };
    for (arguments) |args| try std.testing.expectEqual(workflow.OutcomeTag.failed, runInvocationInProject(io, std.testing.allocator, project.dir, args).execution);
    var unreadable = try project.dir.openDir(io, "references/real", .{ .iterate = true });
    defer unreadable.close(io);
    try unreadable.setPermissions(io, .fromMode(0o000));
    defer unreadable.setPermissions(io, .fromMode(0o700)) catch @panic("restore test directory permissions");
    try std.testing.expectEqual(workflow.OutcomeTag.failed, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "Hello/日本語", "--reference", "real" }).execution);
}

test "reference inspection rejects wrong root capabilities and stale physical roots" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
    try project.dir.createDirPath(io, ".sdd/workflows");
    try project.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/hello.workflow.yaml", .data = valid_workflow });
    try project.dir.createDirPath(io, "references/hello");
    var boot = runInProject(io, std.testing.allocator, project.dir);
    defer boot.deinit();
    try std.testing.expect(boot == .ready);
    var adapter: @import("../adapters/filesystem/reference_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
    var inspector = adapter.inspector();
    try std.testing.expectError(error.ReferenceDirectoryUnavailable, inspector.inspect(std.testing.allocator, .{ .bytes = "hello" }));
    inspector.capability = boot.ready.roots.registry().workflowAuthority();
    try std.testing.expectError(error.ReferenceDirectoryUnavailable, inspector.inspect(std.testing.allocator, .{ .bytes = "hello" }));
    inspector.capability = boot.ready.roots.registry().referenceSources();
    const observed = try inspector.inspect(std.testing.allocator, .{ .bytes = "hello" });
    defer std.testing.allocator.free(observed.project_relative_path);
    try std.testing.expectEqualStrings("references/hello", observed.project_relative_path);
    try project.dir.rename("references", project.dir, "old-references", io);
    try project.dir.createDirPath(io, "references/hello");
    try std.testing.expectError(error.ReferenceDirectoryUnavailable, inspector.inspect(std.testing.allocator, .{ .bytes = "hello" }));
}

test "reference compiler rejects a missing validated selector or read capability" {
    const io = std.testing.io;
    for ([_]bool{ false, true }) |missing_input| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try writeReferencePreflightFixture(io, project.dir);
        const original = @embedFile("../test_fixtures/reference-preflight.workflow.yaml");
        const changed = if (missing_input)
            try std.mem.replaceOwned(u8, std.testing.allocator, original, "use: validate-reference-selector@1", "use: normalize-reference-selector@1")
        else
            try std.mem.replaceOwned(u8, std.testing.allocator, original, "policy: core.directory-read@1", "policy: core.capability-free@1");
        defer std.testing.allocator.free(changed);
        try project.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/preflight.workflow.yaml", .data = changed });
        const result = runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "Hello/日本語", "--reference", "anything" });
        try std.testing.expect(result == .bootstrap_failed);
    }
}

test "reference preflight cancellation stops safely at each runtime checkpoint" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try writeReferencePreflightFixture(io, project.dir);
    try project.dir.createDirPath(io, "references/hello");
    for (0..256) |checks| {
        var control: RuntimeAfterObservations = .{ .active_observations_remaining = checks, .terminal = .cancelled };
        const result = runInvocationInProjectWithRuntime(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "Hello/日本語", "--reference", "hello" }, control.runtime());
        try std.testing.expect(result == .execution);
        if (result.execution == .ok) {
            try std.testing.expect(checks > 3);
            return;
        }
        try std.testing.expectEqual(workflow.OutcomeTag.cancelled, result.execution);
    }
    return error.ReferencePreflightNeverCompleted;
}

const second_workflow_same_shortcode =
    \\schema: workflow/v1
    \\id: goodbye
    \\version: 1
    \\shortcode: HELO
    \\invoke: core.empty-invocation@1
    \\policy: core.capability-free@1
    \\start: run
    \\steps:
    \\  run:
    \\    use: core.noop@1
    \\    on: { ok: end.ok }
;

const test_provider_id = llm_provider_identity.ProviderId.parse("compiled-provider").?;
const test_provider_contracts: llm_provider_contracts.Registry = .{ .entries = &.{.{
    .provider = test_provider_id,
    .model = llm_provider_identity.ModelId.parse("model-a").?,
    .implementation_id = llm_provider_contracts.RegisteredProviderImplementationId.init(1).?,
    .config_schema = .empty_object,
    .capabilities = @import("../model_contract_test_fixture.zig").capabilities,
}} };
const test_provider_document =
    \\{"providers":[{"provider":"compiled-provider","models":[{"model":"model-a","config":{}}]}]}
;
const test_model_step: workflow_compilation.CompiledStep = .{
    .id = workflow.WorkflowStepId.parse("run").?,
    .operation_id = workflow.RegisteredRef.parse("test.model@1").?,
    .parameters = &.{.{
        .id = workflow.WorkflowParameterId.parse("slot").?,
        .value = .{ .model_slot = llm_provider_identity.ModelSlotId.parse("implementation").? },
    }},
    .requires = &.{},
    .produces = &.{},
    .replaces = &.{},
    .invalidates = &.{},
    .outcomes = &.{.ok},
    .side_effect = .none,
    .gates = &.{},
    .capabilities = &.{model_provider_requirement.capability_id},
    .retry_authority = null,
};
const test_model_transition: workflow.Transition = .{
    .from = test_model_step.id,
    .outcome = .ok,
    .target = .{ .terminal = .ok },
};
const test_model_graph: workflow_compilation.CompiledWorkflow = .{
    .source_ordinal = 1,
    .shortcode = telemetry.WorkflowShortcode.parse("TEST") catch unreachable,
    .authority = .{
        .workflow_id = workflow.WorkflowId.parse("model-flow").?,
        .workflow_version = 1,
        .invocation_operation_id = workflow.RegisteredRef.parse("test.empty@1").?,
        .policy_profile_id = workflow.RegisteredRef.parse("test.safe@1").?,
        .total_model_token_budget = .{ .value = 1000 },
        .start_step_id = test_model_step.id,
        .invocation_outputs = &.{},
        .resources = &.{},
        .steps = &.{test_model_step},
        .transitions = &.{test_model_transition},
        .maximum_step_executions = 1,
    },
};

fn testModelSelectedWorkflow() workflow_execution.SelectedWorkflow {
    return .{
        .invocation = .{
            .workflow_id = test_model_graph.authority.workflow_id,
            .arguments = &.{},
        },
        .graph = &test_model_graph,
    };
}

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
    for ([_][]const u8{ "nested", "transactions", "Transactions", "utilities", "nested/features" }) |directory| {
        var project_root = std.testing.tmpDir(.{});
        defer project_root.cleanup();
        try project_root.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
        const parent = try std.fmt.allocPrint(std.testing.allocator, ".sdd/workflows/{s}", .{directory});
        defer std.testing.allocator.free(parent);
        try project_root.dir.createDirPath(io, parent);
        const filename = try std.fmt.allocPrint(std.testing.allocator, "{s}/arbitrary-name.workflow.yaml", .{parent});
        defer std.testing.allocator.free(filename);
        try project_root.dir.writeFile(io, .{ .sub_path = filename, .data = valid_workflow });
        // Only this exact root subtree is excluded from workflow discovery.
        try project_root.dir.createDirPath(io, ".sdd/workflows/features/private");
        try project_root.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/features/private/state.json", .data = "not workflow input" });

        var outcome = runInProject(io, std.testing.allocator, project_root.dir);
        defer outcome.deinit();
        try std.testing.expect(outcome == .ready);
        const registry = outcome.ready.workflows.registry();
        try std.testing.expectEqual(@as(usize, 1), registry.count());
        const graph = registry.resolve(workflow.WorkflowId.parse("hello").?);
        try std.testing.expect(graph != null);
        try std.testing.expectEqualStrings("core.noop@1", graph.?.authority.steps[0].operation_id.bytes);
        try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project_root.dir, &.{"hello"}).execution);
    }
}

test "ordinary workflow directories cannot hide undeclared files or symlinks" {
    const io = std.testing.io;
    for ([_][]const u8{ "transactions", "utilities", "nested/features" }) |directory| {
        for ([_]bool{ false, true }) |linked| {
            var project_root = std.testing.tmpDir(.{});
            defer project_root.cleanup();
            try project_root.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
            const parent = try std.fmt.allocPrint(std.testing.allocator, ".sdd/workflows/{s}", .{directory});
            defer std.testing.allocator.free(parent);
            try project_root.dir.createDirPath(io, parent);
            try project_root.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/hello.workflow.yaml", .data = valid_workflow });
            const filename = try std.fmt.allocPrint(std.testing.allocator, "{s}/unregistered.json", .{parent});
            defer std.testing.allocator.free(filename);
            if (linked) {
                try project_root.dir.symLink(io, "../hello.workflow.yaml", filename, .{});
            } else {
                try project_root.dir.writeFile(io, .{ .sub_path = filename, .data = "{}" });
            }
            var outcome = runInProject(io, std.testing.allocator, project_root.dir);
            defer outcome.deinit();
            try std.testing.expectEqual(@import("../domain/bootstrap_error.zig").PublicError.WORKFLOW_AUTHORITY_INVENTORY_INVALID, outcome.failed);
        }
    }
}

test "reserved feature roots still reject files symlinks and case aliases" {
    const io = std.testing.io;
    const InvalidRoot = enum { file, symlink, case_alias };
    for (std.enums.values(InvalidRoot)) |kind| {
        var project_root = std.testing.tmpDir(.{});
        defer project_root.cleanup();
        try project_root.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
        try project_root.dir.createDirPath(io, ".sdd/workflows");
        switch (kind) {
            .file => try project_root.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/features", .data = "{}" }),
            .symlink => try project_root.dir.symLink(io, "../outside", ".sdd/workflows/features", .{}),
            .case_alias => try project_root.dir.createDirPath(io, ".sdd/workflows/Features"),
        }
        var outcome = runInProject(io, std.testing.allocator, project_root.dir);
        defer outcome.deinit();
        try std.testing.expectEqual(@import("../domain/bootstrap_error.zig").PublicError.WORKFLOW_AUTHORITY_INVENTORY_INVALID, outcome.failed);
    }
}

test "duplicate workflow shortcodes reject the complete registry" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
    try project_root.dir.createDirPath(io, ".sdd/workflows");
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
    try createFeatureLogLayout(io, project_root.dir, std.Io.File.Permissions.fromMode(0o700));
    var boot = runInProject(io, std.testing.allocator, project_root.dir);
    defer boot.deinit();
    try std.testing.expect(boot == .ready);
    const candidate: log_binding.BindingCandidate = .{
        .log_policy_id = @import("../domain/telemetry.zig").Identifier.validate("LOGPOL-1").?,
        .binding_id = @import("../domain/telemetry.zig").Identifier.validate("LOGBIND-1").?,
        .run_id = @import("../domain/telemetry.zig").Identifier.validate("RUN-1").?,
        .feature_id = @import("../domain/feature_identity.zig").FeatureId.parse("F0002").?,
    };
    const binding_owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(binding_owner);
    const artifact_owner = try workflow_artifacts.createValidated(
        std.testing.allocator,
        boot.ready.roots.registry(),
        log_binding.binding(binding_owner),
    );
    defer workflow_artifacts.deinitOwner(artifact_owner);
    var sink = try feature_log_sink.Adapter.init(
        io,
        project_root.dir,
        workflow_artifacts.registry(artifact_owner),
        log_binding.binding(binding_owner),
    );
    defer sink.deinit();
    try project_root.dir.access(io, "specs/F0002/logs/events/RUN-1/LOGBIND-1", .{});
    try project_root.dir.access(io, "specs/F0002/logs/prompts/RUN-1/LOGBIND-1", .{});

    const active_runtime = try active_feature_log_runtime.create(
        std.testing.allocator,
        io,
        project_root.dir,
        boot.ready.logs.policy(),
        workflow_artifacts.registry(artifact_owner),
        log_binding.binding(binding_owner),
    );
    defer active_feature_log_runtime.deinit(active_runtime);
    const shortcode = try @import("../domain/telemetry.zig").WorkflowShortcode.parse("TEST");
    try std.testing.expect(boot.ready.logs.activate(
        active_feature_log_runtime.runner(active_runtime).childBindings(),
        shortcode,
    ) == .ok);
    const persisted = boot.ready.logs.barrier().process(.{
        .workflow_shortcode = shortcode,
        .fact = .{ .event_type = .run_started },
    });
    try std.testing.expect(persisted == .persisted);
    try project_root.dir.access(io, "specs/F0002/logs/events/RUN-1/LOGBIND-1/0001.log", .{});
    var finalization_execution: feature_log_finalization_runner.Runner = .{
        .target = active_feature_log_runtime.runner(active_runtime),
        .mode = .active,
        .shortcode = shortcode,
    };
    try std.testing.expect(boot.ready.logs.finalizeActive(finalization_execution.childBindings()) == .ok);
    const bytes = try project_root.dir.readFileAlloc(
        io,
        "specs/F0002/logs/events/RUN-1/LOGBIND-1/0001.log",
        std.testing.allocator,
        .limited(log_limits.max_segment_bytes),
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
        if (insecure_layout) {
            try createFeatureLogLayout(io, project_root.dir, std.Io.File.Permissions.fromMode(0o755));
        } else {
            try project_root.dir.createDir(io, "specs", std.Io.File.Permissions.fromMode(0o700));
        }
        var boot = runInProject(io, std.testing.allocator, project_root.dir);
        defer boot.deinit();
        try std.testing.expect(boot == .ready);
        const candidate: log_binding.BindingCandidate = .{
            .log_policy_id = @import("../domain/telemetry.zig").Identifier.validate("LOGPOL-1").?,
            .binding_id = @import("../domain/telemetry.zig").Identifier.validate("LOGBIND-1").?,
            .run_id = @import("../domain/telemetry.zig").Identifier.validate("RUN-1").?,
            .feature_id = @import("../domain/feature_identity.zig").FeatureId.parse("F0002").?,
        };
        const binding_owner = try log_binding.createValidated(std.testing.allocator, candidate);
        defer log_binding.deinitOwner(binding_owner);
        const artifact_owner = try workflow_artifacts.createValidated(
            std.testing.allocator,
            boot.ready.roots.registry(),
            log_binding.binding(binding_owner),
        );
        defer workflow_artifacts.deinitOwner(artifact_owner);
        const result = feature_log_sink.Adapter.init(
            io,
            project_root.dir,
            workflow_artifacts.registry(artifact_owner),
            log_binding.binding(binding_owner),
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
    var boot = runInProject(io, std.testing.allocator, project_root.dir);
    defer boot.deinit();
    try std.testing.expect(boot == .ready);
    const candidate: log_binding.BindingCandidate = .{
        .log_policy_id = @import("../domain/telemetry.zig").Identifier.validate("LOGPOL-1").?,
        .binding_id = @import("../domain/telemetry.zig").Identifier.validate("LOGBIND-1").?,
        .run_id = @import("../domain/telemetry.zig").Identifier.validate("RUN-1").?,
        .feature_id = @import("../domain/feature_identity.zig").FeatureId.parse("F0002").?,
    };
    const binding_owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(binding_owner);
    try std.testing.expectError(
        error.InvalidWorkflowArtifactRegistry,
        workflow_artifacts.createValidated(
            std.testing.allocator,
            boot.ready.roots.registry(),
            log_binding.binding(binding_owner),
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

const PreparationMode = enum { not_required, ready, failed, cancelled };

const InvocationPreparationProbe = struct {
    mode: PreparationMode,
    prepare_calls: usize = 0,
    observation: OperationObservation = .{},
    selected_workflow_id: ?[]const u8 = null,
    prepared_registry: ?*const llm_provider_registry.ValidatedLLMProviderRegistry = null,
    operation_entries: [2]workflow_operation_registry.Entry = undefined,
    operation_registry: workflow_operation_registry.Registry = undefined,

    fn providerBinding(self: *InvocationPreparationProbe) model_provider_bootstrap_binding.Binding {
        return .{ .context = self, .invoke_fn = prepareProvider };
    }

    fn registry(self: *InvocationPreparationProbe) *const workflow_operation_registry.Registry {
        self.observation.requires_provider = self.mode == .ready;
        self.operation_entries[0] = .{
            .contract = .{
                .id = "core.empty-invocation@1",
                .kind = .invocation,
                .outcomes = &.{.ok},
                .side_effect = .none,
            },
            .binding = @import("../application/workflow_operation_binding.zig").bind(OperationObservation, &self.observation, invokeOperation),
        };
        self.operation_entries[1] = .{
            .contract = .{
                .id = "core.noop@1",
                .kind = .step,
                .outcomes = &.{.ok},
                .side_effect = .none,
            },
            .binding = @import("../application/workflow_operation_binding.zig").bind(OperationObservation, &self.observation, invokeOperation),
        };
        self.operation_registry = .{
            .operations = &self.operation_entries,
            .policies = core_workflow_operations.registry.policies,
            .gates = &.{},
        };
        return &self.operation_registry;
    }

    fn prepareProvider(
        context: *anyopaque,
        selected: *const workflow_execution.SelectedWorkflow,
        models: *const config.ModelsConfig,
        _: *const bootstrap_root_registry.LLMProviderConfigCapability,
    ) model_provider_bootstrap_orchestrator.Outcome {
        const self: *InvocationPreparationProbe = @ptrCast(@alignCast(context));
        self.prepare_calls += 1;
        self.selected_workflow_id = selected.graph.authority.workflow_id.bytes;
        return switch (self.mode) {
            .not_required => .not_required,
            .failed => .{ .failed = .LLM_PROVIDER_CONFIG_PARSE_ERROR },
            .cancelled => .cancelled,
            .ready => ready: {
                var candidate = llm_provider_registry.Candidate.init(std.testing.allocator, 0) catch unreachable;
                defer candidate.deinit();
                const registry_owner = llm_provider_registry.createValidated(
                    std.testing.allocator,
                    candidate,
                    llm_provider_contracts.Registry.empty,
                ) catch unreachable;
                const allowlist_owner = repository_model_allowlist.createValidated(
                    std.testing.allocator,
                    models,
                    llm_provider_registry.registry(registry_owner),
                ) catch {
                    llm_provider_registry.deinitOwner(registry_owner);
                    unreachable;
                };
                self.prepared_registry = llm_provider_registry.registry(registry_owner);
                self.observation.provider_ready = self.prepared_registry.?.count() == 0;
                break :ready .{ .ready = model_provider_bootstrap_services.ModelProviderBootstrapServices.init(
                    llm_provider_registry_service.LLMProviderRegistryService.init(registry_owner),
                    allowlist_owner,
                ) };
            },
        };
    }

    fn invokeOperation(
        context: ?*OperationObservation,
        input: workflow_operation_registry.Input,
    ) workflow_operation_registry.Error!workflow_execution.Candidate {
        const self = context.?;
        switch (input) {
            .invocation => self.invocation_calls += 1,
            .step => {
                self.step_calls += 1;
                if (self.requires_provider and !self.provider_ready) {
                    return error.OperationExecutionFailed;
                }
            },
        }
        return .{ .outcome = .ok, .delta = .{} };
    }
};

const OperationObservation = struct {
    invocation_calls: usize = 0,
    step_calls: usize = 0,
    requires_provider: bool = false,
    provider_ready: bool = false,
};

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
