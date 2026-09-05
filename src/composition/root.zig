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
    var feature_inputs: @import("../adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project_root };
    var reference_contents: @import("../adapters/filesystem/reference_corpus_source.zig").Adapter = .{ .io = io, .project_root = project_root };
    var markdown_reader: @import("../adapters/parsers/markdown_reference.zig").Adapter = .{ .io = io };
    native_bindings.init(allocator, toolchain_source_adapter.projectCapturer(), toolchain_source_adapter.presetEnumerator(), toolchain_source_adapter.presetCapturer(), toolchain_parser_adapter.parser(), policy_registry, .{ .normalize_fn = @import("unicode_normalization").nfc }, reference_adapter.inspector(), feature_adapter.inspector(), feature_inputs.capturer(), @import("../adapters/parsers/clarification_inputs.zig").stateParser(), @import("../adapters/parsers/clarification_inputs.zig").formParser(), reference_contents.enumerator(), reference_contents.capturer(), markdown_reader.decoderPort(), .{ .fold_fn = @import("unicode_normalization").caseFold });
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
    var feature_inputs: @import("../adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project_root };
    var reference_contents: @import("../adapters/filesystem/reference_corpus_source.zig").Adapter = .{ .io = io, .project_root = project_root };
    var markdown_reader: @import("../adapters/parsers/markdown_reference.zig").Adapter = .{ .io = io };
    operations.init(std.testing.allocator, source.projectCapturer(), source.presetEnumerator(), source.presetCapturer(), parser.parser(), policy_registry, .{ .normalize_fn = @import("unicode_normalization").nfc }, reference_adapter.inspector(), feature_adapter.inspector(), feature_inputs.capturer(), @import("../adapters/parsers/clarification_inputs.zig").stateParser(), @import("../adapters/parsers/clarification_inputs.zig").formParser(), reference_contents.enumerator(), reference_contents.capturer(), markdown_reader.decoderPort(), .{ .fold_fn = @import("unicode_normalization").caseFold });
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

fn writeReferenceIngestionFixture(io: std.Io, project: std.Io.Dir) !void {
    try writeFeatureInputFixture(io, project);
    const existing = try project.readFileAlloc(io, ".sddtoolkit.json", std.testing.allocator, .limited(16384));
    defer std.testing.allocator.free(existing);
    const changed = try std.mem.replaceOwned(u8, std.testing.allocator, existing, "\"references\": \"references\"", "\"references\": \"source-material\"");
    defer std.testing.allocator.free(changed);
    try project.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = changed });
    try project.writeFile(io, .{ .sub_path = "engine/workflows/preflight.workflow.yaml", .data = @embedFile("../test_fixtures/reference-ingestion.workflow.yaml") });
    try project.createDirPath(io, "source-material/first");
    const stories = try std.Io.Dir.cwd().readFileAlloc(io, "test/evaluation/wf-001-hello-world/reference/stories.md", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(stories);
    try project.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = stories });
}

test "reference ingestion YAML reads configured source content without creating outputs" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try writeReferenceIngestionFixture(io, project.dir);
    try project.dir.createDirPath(io, "source-material/first/nested");
    try project.dir.writeFile(io, .{ .sub_path = "source-material/first/nested/Café.md", .data = "# Other evidence\nKeep exact bytes.\n" });
    try project.dir.writeFile(io, .{ .sub_path = "source-material/first/.hidden.md", .data = "Hidden reference evidence.\n" });
    for (0..2) |_| {
        try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-ingestion", "--feature", "Chosen/Café", "--reference", "first" }).execution);
        try std.testing.expectError(error.FileNotFound, project.dir.openDir(io, "requirements", .{}));
        try std.testing.expectError(error.FileNotFound, project.dir.openDir(io, "engine/workflows/features", .{}));
    }
    const renamed = try std.mem.replaceOwned(u8, std.testing.allocator, @embedFile("../test_fixtures/reference-ingestion.workflow.yaml"), "id: reference-ingestion", "id: document-evidence");
    defer std.testing.allocator.free(renamed);
    try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/preflight.workflow.yaml", .data = renamed });
    try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "document-evidence", "--feature", "Chosen/Café", "--reference", "first" }).execution);
}

test "reference failures are not skipped and cannot change closed clarification files" {
    const io = std.testing.io;
    for ([_]enum { unsupported, malformed, disguised, symlink, hidden, oversized, unreadable }{
        .unsupported, .malformed, .disguised, .symlink, .hidden, .oversized, .unreadable,
    }) |failure| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try writeReferenceIngestionFixture(io, project.dir);
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        const clarifications = try @import("../test_fixtures/clarification_inputs.zig").closed(allocator, "S01", true);
        try writeClarificationCapture(io, project.dir, clarifications);
        const oversized = try allocator.alloc(u8, if (failure == .oversized) 1024 * 1024 + 1 else 0);
        @memset(oversized, 'x');
        const invalid_bytes = switch (failure) {
            .malformed => "\xff",
            .disguised => "%PDF-1.7",
            .oversized => oversized,
            else => "not supported",
        };
        if (failure == .symlink) {
            try project.dir.symLink(io, "missing", "source-material/first/alias.md", .{});
        } else if (failure == .hidden) {
            // A non-Markdown hidden entry must also be accounted, never filtered.
            try project.dir.writeFile(io, .{ .sub_path = "source-material/first/.unknown", .data = invalid_bytes });
        } else {
            try project.dir.writeFile(io, .{ .sub_path = if (failure == .unsupported) "source-material/first/data.json" else "source-material/first/other.md", .data = invalid_bytes });
        }
        var inaccessible = try project.dir.openDir(io, "source-material/first", .{});
        defer inaccessible.close(io);
        var locked: ?std.Io.Dir = null;
        if (failure == .unreadable) {
            try inaccessible.createDir(io, "locked", .default_dir);
            locked = try inaccessible.openDir(io, "locked", .{});
            try locked.?.setPermissions(io, .fromMode(0o000));
        }
        defer if (locked) |directory| {
            directory.setPermissions(io, .fromMode(0o700)) catch @panic("restore test directory permissions");
            directory.close(io);
        };
        try std.testing.expectEqual(workflow.OutcomeTag.failed, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-ingestion", "--feature", "Chosen/Café", "--reference", "first" }).execution);
        try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{"hello"}).execution);
        const retained = try project.dir.readFileAlloc(io, "requirements/current/Chosen/Café/clarify/S01.md", allocator, .limited(16384));
        try std.testing.expectEqualSlices(u8, clarifications.forms[0].bytes, retained);
        try std.testing.expectError(error.FileNotFound, project.dir.openFile(io, "requirements/current/Chosen/Café/spec.md", .{}));
    }
}

test "reference capture is immutable and rejects corpus changes after inventory" {
    const io = std.testing.io;
    const ingestion = @import("../domain/reference_ingestion.zig");
    for ([_]enum { content, addition, directory, immutable }{ .content, .addition, .directory, .immutable }) |change| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try project.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
        try project.dir.createDirPath(io, ".sdd/workflows");
        try project.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/hello.workflow.yaml", .data = valid_workflow });
        try project.dir.createDirPath(io, "references/chosen/nested");
        try project.dir.writeFile(io, .{ .sub_path = "references/chosen/nested/source.md", .data = "Original\r\nCafé\n" });
        var boot = runInProject(io, std.testing.allocator, project.dir);
        defer boot.deinit();
        try std.testing.expect(boot == .ready);
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        const registry = boot.ready.roots.registry();
        var inspector_adapter: @import("../adapters/filesystem/reference_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var inspector = inspector_adapter.inspector();
        inspector.capability = registry.referenceSources();
        const selected = try inspector.inspect(allocator, .{ .bytes = "chosen" });
        var adapter: @import("../adapters/filesystem/reference_corpus_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var enumerator = adapter.enumerator();
        try std.testing.expectError(error.ReferenceUnavailable, enumerator.enumerate(allocator, selected));
        enumerator.capability = registry.referenceContentRead();
        const inventory = try (@import("../actions/reference/validate_reference_inventory.zig").Action{
            .normalizer = .{ .normalize_fn = @import("unicode_normalization").nfc },
            .case_folder = .{ .fold_fn = @import("unicode_normalization").caseFold },
        }).execute(allocator, try enumerator.enumerate(allocator, selected));
        var capture = adapter.capturer();
        capture.capability = registry.referenceContentRead();
        switch (change) {
            .content => try project.dir.writeFile(io, .{ .sub_path = "references/chosen/nested/source.md", .data = "Changed\n" }),
            .addition => try project.dir.writeFile(io, .{ .sub_path = "references/chosen/added.md", .data = "New\n" }),
            .directory => {
                try project.dir.rename("references/chosen/nested", project.dir, "references/chosen/old", io);
                try project.dir.createDirPath(io, "references/chosen/nested");
            },
            .immutable => {
                const captured = try capture.capture(allocator, inventory);
                try project.dir.writeFile(io, .{ .sub_path = "references/chosen/nested/source.md", .data = "Replaced after capture\n" });
                var decoder: @import("../adapters/parsers/markdown_reference.zig").Adapter = .{ .io = io };
                const decoded = try (@import("../actions/reference/decode_reference_markdown.zig").Action{ .decoder = decoder.decoderPort() }).execute(allocator, captured);
                const result: ingestion.Inputs = try (@import("../actions/reference/validate_reference_accounting.zig").Action{}).execute(allocator, decoded);
                try std.testing.expectEqualStrings("Original\r\nCafé\n", result.documents[0].bytes);
                try std.testing.expectEqualStrings("nested/source.md", result.documents[0].path.bytes);
                continue;
            },
        }
        try std.testing.expectError(error.ReferenceInventoryChanged, capture.capture(allocator, inventory));
    }
}

test "reference ingestion compiler enforces inputs and content-read capability" {
    const io = std.testing.io;
    for ([_][2][]const u8{
        .{ "policy: core.reference-ingestion@1", "policy: core.feature-input-read@1" },
        .{ "use: capture-reference-sources@1", "use: core.noop@1" },
        .{ "use: validate-reference-inventory@1", "use: core.noop@1" },
    }) |edit| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try writeReferenceIngestionFixture(io, project.dir);
        const changed = try std.mem.replaceOwned(u8, std.testing.allocator, @embedFile("../test_fixtures/reference-ingestion.workflow.yaml"), edit[0], edit[1]);
        defer std.testing.allocator.free(changed);
        try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/preflight.workflow.yaml", .data = changed });
        try std.testing.expect(runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-ingestion", "--feature", "Chosen/Café", "--reference", "first" }) == .bootstrap_failed);
    }
}

test "reference ingestion cancellation does not create artifacts" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try writeReferenceIngestionFixture(io, project.dir);
    for (0..512) |checks| {
        var control: RuntimeAfterObservations = .{ .active_observations_remaining = checks, .terminal = .cancelled };
        const result = runInvocationInProjectWithRuntime(io, std.testing.allocator, project.dir, &.{ "reference-ingestion", "--feature", "Chosen/Café", "--reference", "first" }, control.runtime());
        try std.testing.expect(result == .execution);
        try std.testing.expectError(error.FileNotFound, project.dir.openDir(io, "requirements", .{}));
        if (result.execution == .ok) return;
        try std.testing.expectEqual(workflow.OutcomeTag.cancelled, result.execution);
    }
    return error.ReferenceIngestionNeverCompleted;
}

fn writeFeatureInputFixture(io: std.Io, project: std.Io.Dir) !void {
    const allocator = std.testing.allocator;
    const specs_config = try std.mem.replaceOwned(u8, allocator, valid_config, "\"specs\": \"specs\"", "\"specs\": \"requirements/current\"");
    defer allocator.free(specs_config);
    const archive_config = try std.mem.replaceOwned(u8, allocator, specs_config, "specs/archive", "requirements/archive");
    defer allocator.free(archive_config);
    const configuration = try std.mem.replaceOwned(u8, allocator, archive_config, ".sdd/workflows", "engine/workflows");
    defer allocator.free(configuration);
    try project.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = configuration });
    try project.createDirPath(io, "engine/workflows");
    try project.writeFile(io, .{ .sub_path = "engine/workflows/preflight.workflow.yaml", .data = @embedFile("../test_fixtures/feature-input-preflight.workflow.yaml") });
    try project.writeFile(io, .{ .sub_path = "engine/workflows/hello.workflow.yaml", .data = valid_workflow });
    try project.createDirPath(io, "references/first");
    try project.createDirPath(io, "references/second");
}

fn writeClarificationCapture(io: std.Io, project: std.Io.Dir, captures: @import("../domain/clarification_inputs.zig").Captures) !void {
    try project.createDirPath(io, "engine/workflows/features/Chosen/Café/state");
    if (captures.state) |bytes| try project.writeFile(io, .{ .sub_path = "engine/workflows/features/Chosen/Café/state/clarifications.json", .data = bytes });
    try project.createDirPath(io, "requirements/current/Chosen/Café/clarify");
    var folder = try project.openDir(io, "requirements/current/Chosen/Café/clarify", .{});
    defer folder.close(io);
    for (captures.forms) |form| try folder.writeFile(io, .{ .sub_path = &form.id.filename(), .data = form.bytes });
}

test "feature input YAML is read-only for new targets and unrelated workflows" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try writeFeatureInputFixture(io, project.dir);
    for (0..2) |_| {
        try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "feature-input-preflight", "--feature", "Chosen/Café", "--reference", "first" }).execution);
        try std.testing.expectError(error.FileNotFound, project.dir.openDir(io, "requirements", .{}));
        try std.testing.expectError(error.FileNotFound, project.dir.openDir(io, "engine/workflows/features", .{}));
    }
    // Unselected invalid content is not read, even though its reader is registered.
    try project.dir.createDirPath(io, "requirements/current/Chosen/Café/clarify");
    try project.dir.writeFile(io, .{ .sub_path = "requirements/current/Chosen/Café/clarify/unknown.txt", .data = "unrecognized" });
    try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{"hello"}).execution);
}

test "feature input reruns retain submitted and recorded closed files with configured roots" {
    const io = std.testing.io;
    for ([_]bool{ false, true }) |recorded| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try writeFeatureInputFixture(io, project.dir);
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const captures = try @import("../test_fixtures/clarification_inputs.zig").closed(arena.allocator(), "S01", recorded);
        try writeClarificationCapture(io, project.dir, captures);
        try project.dir.writeFile(io, .{ .sub_path = "requirements/current/Chosen/Café/spec.md", .data = "existing user-edited spec\n" });
        try project.dir.writeFile(io, .{ .sub_path = "requirements/current/Chosen/Café/reference-context.md", .data = "existing reference view\n" });
        // This operation does not import stage state or generated views as authority.
        try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/features/Chosen/Café/state/workflow.json", .data = "not required by this read-only operation" });
        for ([_][]const u8{ "first", "second", "first" }) |reference| {
            try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "feature-input-preflight", "--feature", "Chosen/Café", "--reference", reference }).execution);
            const closed = try project.dir.readFileAlloc(io, "requirements/current/Chosen/Café/clarify/S01.md", arena.allocator(), .limited(16384));
            try std.testing.expectEqualSlices(u8, captures.forms[0].bytes, closed);
            const state = try project.dir.readFileAlloc(io, "engine/workflows/features/Chosen/Café/state/clarifications.json", arena.allocator(), .limited(8 * 1024 * 1024));
            try std.testing.expectEqualSlices(u8, captures.state.?, state);
            const spec = try project.dir.readFileAlloc(io, "requirements/current/Chosen/Café/spec.md", arena.allocator(), .limited(128));
            try std.testing.expectEqualStrings("existing user-edited spec\n", spec);
        }
        // The compiled operations do not depend on the workflow's name.
        const renamed = try std.mem.replaceOwned(u8, arena.allocator(), @embedFile("../test_fixtures/feature-input-preflight.workflow.yaml"), "id: feature-input-preflight", "id: arbitrary-preparation");
        try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/preflight.workflow.yaml", .data = renamed });
        try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "arbitrary-preparation", "--feature", "Chosen/Café", "--reference", "first" }).execution);
    }
}

test "feature input failures preserve invalid stale and changed close submissions" {
    const io = std.testing.io;
    for ([_]enum { malformed_form, stale_form, changed_answer, missing_form, malformed_state, wrong_feature, orphan_form }{
        .malformed_form, .stale_form, .changed_answer, .missing_form, .malformed_state, .wrong_feature, .orphan_form,
    }) |failure| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try writeFeatureInputFixture(io, project.dir);
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        var captures = try @import("../test_fixtures/clarification_inputs.zig").closed(allocator, "S01", failure != .stale_form);
        const original = captures.forms[0];
        const bytes = switch (failure) {
            .malformed_form => "requestedStatus: closed\nAnswer: preserve this invalid submission.\n",
            .stale_form => try std.mem.replaceOwned(u8, allocator, original.bytes, "recordRevision: 1", "recordRevision: 2"),
            .changed_answer => try std.mem.replaceOwned(u8, allocator, original.bytes, "Approved Café", "Different Café"),
            else => original.bytes,
        };
        captures.forms = if (failure == .missing_form) &.{} else &.{.{ .id = original.id, .bytes = bytes }};
        if (failure == .malformed_state) captures.state = "{}";
        if (failure == .wrong_feature) captures.state = try std.mem.replaceOwned(u8, allocator, captures.state.?, "Chosen/Café", "Unrelated");
        if (failure == .orphan_form) captures.state = null;
        try writeClarificationCapture(io, project.dir, captures);
        try std.testing.expectEqual(workflow.OutcomeTag.failed, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "feature-input-preflight", "--feature", "Chosen/Café", "--reference", "first" }).execution);
        if (failure == .missing_form) {
            try std.testing.expectError(error.FileNotFound, project.dir.openFile(io, "requirements/current/Chosen/Café/clarify/S01.md", .{}));
        } else {
            const retained = try project.dir.readFileAlloc(io, "requirements/current/Chosen/Café/clarify/S01.md", allocator, .limited(16384));
            try std.testing.expectEqualSlices(u8, bytes, retained);
        }
        try std.testing.expectError(error.FileNotFound, project.dir.openFile(io, "requirements/current/Chosen/Café/spec.md", .{}));
    }
}

test "feature input capture rejects unknown entries directories and symlink paths" {
    const io = std.testing.io;
    for ([_]enum { unknown, nested, collection_file, collection_link, form_link, dangling_form, state_link, state_parent_link, alias_form }{
        .unknown, .nested, .collection_file, .collection_link, .form_link, .dangling_form, .state_link, .state_parent_link, .alias_form,
    }) |failure| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try writeFeatureInputFixture(io, project.dir);
        try project.dir.createDirPath(io, "requirements/current/Chosen/Café");
        try project.dir.createDirPath(io, "engine/workflows/features/Chosen/Café");
        try project.dir.createDirPath(io, "outside");
        try project.dir.writeFile(io, .{ .sub_path = "outside/data", .data = "must not be imported" });
        switch (failure) {
            .collection_file => try project.dir.writeFile(io, .{ .sub_path = "requirements/current/Chosen/Café/clarify", .data = "not a directory" }),
            .collection_link => try project.dir.symLink(io, "../../../../outside", "requirements/current/Chosen/Café/clarify", .{ .is_directory = true }),
            .state_parent_link => try project.dir.symLink(io, "../../../../../outside", "engine/workflows/features/Chosen/Café/state", .{ .is_directory = true }),
            .state_link => {
                try project.dir.createDirPath(io, "engine/workflows/features/Chosen/Café/state");
                try project.dir.symLink(io, "../../../../../../outside/data", "engine/workflows/features/Chosen/Café/state/clarifications.json", .{});
            },
            else => {
                try project.dir.createDirPath(io, "requirements/current/Chosen/Café/clarify");
                switch (failure) {
                    .unknown => try project.dir.writeFile(io, .{ .sub_path = "requirements/current/Chosen/Café/clarify/notes.txt", .data = "unknown" }),
                    .nested => try project.dir.createDirPath(io, "requirements/current/Chosen/Café/clarify/nested"),
                    .form_link => try project.dir.symLink(io, "../../../../../outside/data", "requirements/current/Chosen/Café/clarify/S01.md", .{}),
                    .dangling_form => try project.dir.symLink(io, "missing.md", "requirements/current/Chosen/Café/clarify/S01.md", .{}),
                    .alias_form => try project.dir.writeFile(io, .{ .sub_path = "requirements/current/Chosen/Café/clarify/s01.md", .data = "alias" }),
                    else => unreachable,
                }
            },
        }
        try std.testing.expectEqual(workflow.OutcomeTag.failed, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "feature-input-preflight", "--feature", "Chosen/Café", "--reference", "first" }).execution);
    }
}

test "feature input capture rechecks target binding paths and physical root observations" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
    try project.dir.createDirPath(io, ".sdd/workflows");
    try project.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/hello.workflow.yaml", .data = valid_workflow });
    try project.dir.createDirPath(io, "specs/chosen");
    var boot = runInProject(io, std.testing.allocator, project.dir);
    defer boot.deinit();
    try std.testing.expect(boot == .ready);
    const registry = boot.ready.roots.registry();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const selected = try @import("../domain/feature_directory.zig").validate(allocator, .{ .bytes = "chosen" }, registry.featureDirectoryRoots());
    var inspector_adapter: @import("../adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
    var inspector = inspector_adapter.inspector();
    inspector.capability = registry.featureDirectoryRead();
    const observed = try inspector.inspect(allocator, selected);
    const artifacts = @import("../domain/workflow_artifact_registry.zig");
    const paths = try artifacts.resolveFeaturePaths(allocator, registry.featureArtifactRoots(), selected);
    var adapter: @import("../adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
    var source = adapter.capturer();
    try std.testing.expectError(error.FeatureInputUnavailable, source.capture(allocator, observed, paths));
    source.capability = registry.featureInputRead();
    const empty = try source.capture(allocator, observed, paths);
    try std.testing.expect(empty.state == null and empty.forms.len == 0);
    var forged = paths;
    forged.entries[@intFromEnum(artifacts.Artifact.clarification_state)].root_relative = "features/someone-else/state/clarifications.json";
    try std.testing.expectError(error.FeatureInputUnavailable, source.capture(allocator, observed, forged));
    var wrong_target = observed;
    wrong_target.selector.feature_id.bytes = "someone-else";
    try std.testing.expectError(error.FeatureInputUnavailable, source.capture(allocator, wrong_target, paths));
    try project.dir.rename("specs/chosen", project.dir, "specs/old-chosen", io);
    try project.dir.createDirPath(io, "specs/chosen");
    try std.testing.expectError(error.FeatureInputUnavailable, source.capture(allocator, observed, paths));
}

test "feature input preparation cancellation never creates artifacts" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try writeFeatureInputFixture(io, project.dir);
    for (0..256) |checks| {
        var control: RuntimeAfterObservations = .{ .active_observations_remaining = checks, .terminal = .cancelled };
        const result = runInvocationInProjectWithRuntime(io, std.testing.allocator, project.dir, &.{ "feature-input-preflight", "--feature", "Chosen/Café", "--reference", "first" }, control.runtime());
        try std.testing.expect(result == .execution);
        try std.testing.expectError(error.FileNotFound, project.dir.openDir(io, "requirements", .{}));
        try std.testing.expectError(error.FileNotFound, project.dir.openDir(io, "engine/workflows/features", .{}));
        if (result.execution == .ok) return;
        try std.testing.expectEqual(workflow.OutcomeTag.cancelled, result.execution);
    }
    return error.FeatureInputsNeverCompleted;
}

test "feature input compiler requires declared read capability and predecessor data" {
    const io = std.testing.io;
    for ([_][2][]const u8{
        .{ "policy: core.feature-input-read@1", "policy: core.directory-read@1" },
        .{ "use: resolve-feature-artifact-paths@1", "use: core.noop@1" },
    }) |edit| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try writeFeatureInputFixture(io, project.dir);
        const changed = try std.mem.replaceOwned(u8, std.testing.allocator, @embedFile("../test_fixtures/feature-input-preflight.workflow.yaml"), edit[0], edit[1]);
        defer std.testing.allocator.free(changed);
        try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/preflight.workflow.yaml", .data = changed });
        try std.testing.expect(runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "feature-input-preflight", "--feature", "Chosen/Café", "--reference", "first" }) == .bootstrap_failed);
    }
}

test "feature preflight uses configured specs roots and preserves selected files across reference changes" {
    const io = std.testing.io;
    const feature = @import("../domain/feature_directory.zig");
    for ([_][]const u8{ "specs", "requirements/current" }) |specs_root| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try writeReferencePreflightFixture(io, project.dir);
        const root_value = try std.fmt.allocPrint(std.testing.allocator, "\"specs\": \"{s}\"", .{specs_root});
        defer std.testing.allocator.free(root_value);
        const root_config = try std.mem.replaceOwned(u8, std.testing.allocator, valid_config, "\"specs\": \"specs\"", root_value);
        defer std.testing.allocator.free(root_config);
        const archive_path = try std.mem.concat(std.testing.allocator, u8, &.{ specs_root, "/archive" });
        defer std.testing.allocator.free(archive_path);
        const configuration = try std.mem.replaceOwned(u8, std.testing.allocator, root_config, "specs/archive", archive_path);
        defer std.testing.allocator.free(configuration);
        try project.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = configuration });
        try project.dir.createDirPath(io, "references/first");
        try project.dir.createDirPath(io, "references/second");
        // Missing configured root and target are observations, never mkdir.
        const arguments: []const []const u8 = &.{ "reference-preflight", "--feature", "Chosen/Café", "--reference", "first" };
        try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, arguments).execution);
        try std.testing.expectError(error.FileNotFound, project.dir.access(io, specs_root, .{}));

        // Selected content, including a user-closed clarification, is untouched.
        const selected = try feature.validate(std.testing.allocator, .{ .bytes = "Chosen/Café" }, .{ .specs = specs_root, .archive = "elsewhere/archive" });
        defer std.testing.allocator.free(selected.project_relative_path);
        try project.dir.createDirPath(io, selected.project_relative_path);
        var target = try project.dir.openDir(io, selected.project_relative_path, .{});
        defer target.close(io);
        try target.createDir(io, "clarify", .default_dir);
        try target.writeFile(io, .{ .sub_path = "spec.md", .data = "existing spec\n" });
        try target.writeFile(io, .{ .sub_path = "clarify/S01.md", .data = "Status: closed\nAnswer: keep exactly\n" });
        try target.writeFile(io, .{ .sub_path = "unrelated.txt", .data = "unrelated\n" });
        var project_source = toolchain_authority_source.Adapter.init(io, project.dir);
        var document_parser: toolchain_documents.Adapter = .{};
        var reference_source: @import("../adapters/filesystem/reference_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var feature_source: @import("../adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var native: @import("native_workflow_operations.zig").Assembly = undefined;
        var feature_inputs: @import("../adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var reference_contents: @import("../adapters/filesystem/reference_corpus_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var markdown_reader: @import("../adapters/parsers/markdown_reference.zig").Adapter = .{ .io = io };
        native.init(std.testing.allocator, project_source.projectCapturer(), project_source.presetEnumerator(), project_source.presetCapturer(), document_parser.parser(), policy_registry, .{ .normalize_fn = @import("unicode_normalization").nfc }, reference_source.inspector(), feature_source.inspector(), feature_inputs.capturer(), @import("../adapters/parsers/clarification_inputs.zig").stateParser(), @import("../adapters/parsers/clarification_inputs.zig").formParser(), reference_contents.enumerator(), reference_contents.capturer(), markdown_reader.decoderPort(), .{ .fold_fn = @import("unicode_normalization").caseFold });
        var boot = runInProjectWithRegistry(io, std.testing.allocator, project.dir, .{}, &native.registry);
        defer boot.deinit();
        try std.testing.expect(boot == .ready);
        var adapter: @import("../adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var inspector = adapter.inspector();
        inspector.capability = boot.ready.roots.registry().featureDirectoryRead();
        const observed = try inspector.inspect(std.testing.allocator, selected);
        try std.testing.expect(observed.observation == .directory);
        for ([_][]const u8{ "first", "second", "first" }) |reference| {
            try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "Chosen/Café", "--reference", reference }).execution);
            const again = try inspector.inspect(std.testing.allocator, selected);
            try std.testing.expect(observed.observation.directory.eql(again.observation.directory));
        }
        const untouched = .{ .{ "spec.md", "existing spec\n" }, .{ "clarify/S01.md", "Status: closed\nAnswer: keep exactly\n" }, .{ "unrelated.txt", "unrelated\n" } };
        inline for (untouched) |file| {
            const bytes = try target.readFileAlloc(io, file[0], std.testing.allocator, .limited(256));
            defer std.testing.allocator.free(bytes);
            try std.testing.expectEqualStrings(file[1], bytes);
        }
        const missing = try feature.validate(std.testing.allocator, .{ .bytes = "Uncreated/child" }, boot.ready.roots.registry().featureDirectoryRoots());
        defer std.testing.allocator.free(missing.project_relative_path);
        try std.testing.expect((try inspector.inspect(std.testing.allocator, missing)).observation == .absent);
        try std.testing.expectError(error.FileNotFound, project.dir.access(io, missing.project_relative_path, .{}));
    }
}

test "feature preflight rejects archive traversal files and symlink ancestors without output" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try writeReferencePreflightFixture(io, project.dir);
    try project.dir.createDirPath(io, "references/source");
    try project.dir.createDirPath(io, "specs/Real/child");
    try project.dir.createDirPath(io, "outside/child");
    try project.dir.writeFile(io, .{ .sub_path = "specs/file", .data = "not a directory" });
    try project.dir.symLink(io, "Real", "specs/linked", .{ .is_directory = true });
    try project.dir.symLink(io, "../outside", "specs/escape", .{ .is_directory = true });
    try project.dir.symLink(io, "missing", "specs/dangling", .{ .is_directory = true });
    for ([_][]const u8{ "archive", "ARCHIVE/child", "../outside", "/outside", "file", "file/child", "linked/child", "escape/child", "dangling/child" }) |feature_path| {
        try std.testing.expectEqual(workflow.OutcomeTag.failed, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", feature_path, "--reference", "source" }).execution);
    }
    // On a case-insensitive filesystem, an existing alias must be rejected.
    // On a case-sensitive filesystem, the spelling is a distinct absent target.
    const alias_exists = if (project.dir.access(io, "specs/real", .{})) |_| true else |err| switch (err) {
        error.FileNotFound => false,
        else => return err,
    };
    const alias_result = runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "real/child", "--reference", "source" });
    try std.testing.expectEqual(if (alias_exists) workflow.OutcomeTag.failed else workflow.OutcomeTag.ok, alias_result.execution);
    try std.testing.expectError(error.FileNotFound, project.dir.access(io, ".sdd/workflows/features", .{}));
    try std.testing.expectError(error.FileNotFound, project.dir.access(io, "specs/Real/child/spec.md", .{}));
}

test "feature inspection rejects missing authority stale roots and forged resolved paths" {
    const io = std.testing.io;
    const feature = @import("../domain/feature_directory.zig");
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try writeReferencePreflightFixture(io, project.dir);
    try project.dir.createDirPath(io, "specs/chosen");
    var project_source = toolchain_authority_source.Adapter.init(io, project.dir);
    var document_parser: toolchain_documents.Adapter = .{};
    var reference_source: @import("../adapters/filesystem/reference_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
    var feature_source: @import("../adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
    var native: @import("native_workflow_operations.zig").Assembly = undefined;
    var feature_inputs: @import("../adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
    var reference_contents: @import("../adapters/filesystem/reference_corpus_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
    var markdown_reader: @import("../adapters/parsers/markdown_reference.zig").Adapter = .{ .io = io };
    native.init(std.testing.allocator, project_source.projectCapturer(), project_source.presetEnumerator(), project_source.presetCapturer(), document_parser.parser(), policy_registry, .{ .normalize_fn = @import("unicode_normalization").nfc }, reference_source.inspector(), feature_source.inspector(), feature_inputs.capturer(), @import("../adapters/parsers/clarification_inputs.zig").stateParser(), @import("../adapters/parsers/clarification_inputs.zig").formParser(), reference_contents.enumerator(), reference_contents.capturer(), markdown_reader.decoderPort(), .{ .fold_fn = @import("unicode_normalization").caseFold });
    var boot = runInProjectWithRegistry(io, std.testing.allocator, project.dir, .{}, &native.registry);
    defer boot.deinit();
    try std.testing.expect(boot == .ready);
    const registry = boot.ready.roots.registry();
    const selected = try feature.validate(std.testing.allocator, .{ .bytes = "chosen" }, registry.featureDirectoryRoots());
    defer std.testing.allocator.free(selected.project_relative_path);
    var adapter: @import("../adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
    var inspector = adapter.inspector();
    try std.testing.expectError(error.FeatureDirectoryUnavailable, inspector.inspect(std.testing.allocator, selected));
    inspector.capability = registry.featureDirectoryRead();
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, inspector.inspect(failing.allocator(), selected));
    _ = try inspector.inspect(std.testing.allocator, selected);
    try std.testing.expectError(error.FeatureDirectoryUnavailable, inspector.inspect(std.testing.allocator, .{ .feature_id = selected.feature_id, .project_relative_path = "elsewhere/chosen" }));
    try project.dir.rename("specs", project.dir, "previous-specs", io);
    try std.testing.expectError(error.FeatureDirectoryUnavailable, inspector.inspect(std.testing.allocator, selected));
    try project.dir.createDirPath(io, "specs/chosen");
    try std.testing.expectError(error.FeatureDirectoryUnavailable, inspector.inspect(std.testing.allocator, selected));
}

test "feature YAML rejects missing typed input unknown parameters and insufficient read authority" {
    const io = std.testing.io;
    const changes = .{
        .{ "use: normalize-feature-directory@1", "use: normalize-reference-selector@1" },
        .{ "use: validate-feature-directory@1", "use: validate-feature-directory@1\n    with: { unexpected: true }" },
        .{ "policy: core.directory-read@1", "policy: core.reference-read@1" },
    };
    inline for (changes) |change| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try writeReferencePreflightFixture(io, project.dir);
        const changed = try std.mem.replaceOwned(u8, std.testing.allocator, @embedFile("../test_fixtures/reference-preflight.workflow.yaml"), change[0], change[1]);
        defer std.testing.allocator.free(changed);
        try project.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/preflight.workflow.yaml", .data = changed });
        try std.testing.expect(runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "chosen", "--reference", "source" }) == .bootstrap_failed);
    }
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
