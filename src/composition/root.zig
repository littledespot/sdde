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

pub fn run(io: std.Io, allocator: std.mem.Allocator, arguments: []const []const u8, environment: *const std.process.Environ.Map) run_outcome.Outcome {
    return runInvocationInProjectWithRuntime(io, allocator, .cwd(), arguments, .{}, environment);
}

fn runInvocationInProject(
    io: std.Io,
    allocator: std.mem.Allocator,
    project_root: std.Io.Dir,
    arguments: []const []const u8,
) run_outcome.Outcome {
    return runInvocationInProjectWithRuntime(io, allocator, project_root, arguments, .{}, null);
}

fn runInvocationInProjectWithRuntime(io: std.Io, allocator: std.mem.Allocator, project_root: std.Io.Dir, arguments: []const []const u8, runtime: pipeline.NodeRuntime, environment: ?*const std.process.Environ.Map) run_outcome.Outcome {
    var toolchain_source_adapter = toolchain_authority_source.Adapter.init(io, project_root);
    var toolchain_parser_adapter: toolchain_documents.Adapter = .{};
    var reference_adapter: @import("../adapters/filesystem/reference_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project_root };
    var feature_adapter: @import("../adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project_root };
    var native_bindings: @import("native_workflow_operations.zig").Assembly = undefined;
    var feature_inputs: @import("../adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project_root };
    var feature_outputs: @import("../adapters/filesystem/workflow_output.zig").Adapter = .{ .io = io, .project_root = project_root };
    var reference_contents: @import("../adapters/filesystem/reference_corpus_source.zig").Adapter = .{ .io = io, .project_root = project_root };
    var markdown_reader: @import("../adapters/parsers/markdown_reference.zig").Adapter = .{ .io = io };
    var reference_ids: @import("../adapters/system/reference_state_identity.zig").Adapter = .{ .io = io };
    native_bindings.init(allocator, toolchain_source_adapter.projectCapturer(), toolchain_source_adapter.presetEnumerator(), toolchain_source_adapter.presetCapturer(), toolchain_parser_adapter.parser(), policy_registry, .{ .normalize_fn = @import("unicode_normalization").nfc }, reference_adapter.inspector(), feature_adapter.inspector(), feature_inputs.capturer(), @import("../adapters/parsers/clarification_inputs.zig").stateParser(), @import("../adapters/parsers/clarification_inputs.zig").formParser(), reference_contents.enumerator(), reference_contents.capturer(), markdown_reader.decoderPort(), .{ .fold_fn = @import("unicode_normalization").caseFold }, reference_ids.source(), .{ .boundary_fn = @import("unicode_normalization").lexicalBoundary });
    var boot = runInProjectWithRegistry(io, allocator, project_root, runtime, &native_bindings.registry);
    native_bindings.publish_output.action.writer = feature_outputs.port();
    native_bindings.capture_workflow_state.action.source = feature_inputs.workflowStateCapturer();
    if (boot == .ready) native_bindings.bindRoots(boot.ready.roots.registry());
    defer boot.deinit();
    var provider_bootstrap = model_provider_bootstrap.Assembly.init(
        io,
        allocator,
        project_root,
        .{},
        &@import("provider_model_contracts.zig").registry,
    );
    var provider_clock: @import("../adapters/system/provider_operation_clock.zig").Adapter = .{ .io = io };
    var provider_runtime: @import("model_provider_runtime.zig").Assembly = .{
        .environment = environment,
        .operations = &native_bindings.model_requests,
        .authorization = .{ .allocator = allocator },
        .transport = .{ .io = io, .clock = provider_clock.clock(), .runtime = runtime },
    };
    defer provider_runtime.deinit();
    return runBootstrappedInvocation(
        allocator,
        &boot,
        arguments,
        &native_bindings.registry,
        provider_bootstrap.bind(),
        runtime,
        provider_clock.clock(),
        &provider_runtime,
    );
}

fn runBootstrappedInvocation(
    allocator: std.mem.Allocator,
    boot: *bootstrap_orchestrator.Outcome,
    arguments: []const []const u8,
    operation_registry: *const workflow_operation_registry.Registry,
    provider_bootstrap: model_provider_bootstrap_binding.Binding,
    runtime: pipeline.NodeRuntime,
    provider_clock: ?@import("../ports/provider_authorization_lease.zig").Clock,
    provider_runtime: ?*@import("model_provider_runtime.zig").Assembly,
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
            invocation.provider_clock = provider_clock;
            invocation.provider_runtime = provider_runtime;
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

pub fn runInProjectWithRegistry(
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

const policy_registry = @import("toolchain_policy_registry.zig").registry;

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
    try std.testing.expectEqual(workflow_execution.Outcome.ok, outcome.executionStatus().?);
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
            null,
            null,
        );

        try std.testing.expectEqual(@as(usize, 1), probe.prepare_calls);
        try std.testing.expectEqualStrings("hello", probe.selected_workflow_id.?);
        switch (mode) {
            .not_required, .ready => {
                try std.testing.expectEqual(workflow_execution.Outcome.ok, outcome.executionStatus().?);
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
                try std.testing.expectEqual(workflow_execution.Outcome.cancelled, outcome.executionStatus().?);
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
        null,
        null,
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
            try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{id}).executionStatus().?);
        }
        try std.testing.expectEqual(workflow.OutcomeTag.failed, runInvocationInProject(io, std.testing.allocator, project.dir, &.{"toolchain-check"}).executionStatus().?);
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
            try std.mem.replaceOwned(u8, std.testing.allocator, fixture, "capture-project: { use: capture-project-toolchain", "capture-project: { use: core.noop")
        else
            try std.mem.replaceOwned(u8, std.testing.allocator, fixture, "policy: core.toolchain@1", "policy: core.capability-free@1");
        defer std.testing.allocator.free(yaml);
        // Keep the replacement operation's outcome set exact so this case
        // specifically exercises the missing project-capture input.
        const exact = if (missing_input)
            try std.mem.replaceOwned(u8, std.testing.allocator, yaml, "capture-project: { use: core.noop, on: { ok: inventory-presets, failed: end.failed } }", "capture-project: { use: core.noop, on: { ok: inventory-presets } }")
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
    \\invoke: core.empty-invocation
    \\policy: core.capability-free@1
    \\start: run
    \\steps:
    \\  run:
    \\    use: core.noop
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
    var reference_ids: @import("../adapters/system/reference_state_identity.zig").Adapter = .{ .io = io };
    operations.init(std.testing.allocator, source.projectCapturer(), source.presetEnumerator(), source.presetCapturer(), parser.parser(), policy_registry, .{ .normalize_fn = @import("unicode_normalization").nfc }, reference_adapter.inspector(), feature_adapter.inspector(), feature_inputs.capturer(), @import("../adapters/parsers/clarification_inputs.zig").stateParser(), @import("../adapters/parsers/clarification_inputs.zig").formParser(), reference_contents.enumerator(), reference_contents.capturer(), markdown_reader.decoderPort(), .{ .fold_fn = @import("unicode_normalization").caseFold }, reference_ids.source(), .{ .boundary_fn = @import("unicode_normalization").lexicalBoundary });
    var boot = runInProjectWithRegistry(io, std.testing.allocator, project_root, .{}, &operations.registry);
    defer boot.deinit();
    try std.testing.expect(boot == .ready);
    operations.bindRoots(boot.ready.roots.registry());
    var provider = model_provider_bootstrap.Assembly.init(io, std.testing.allocator, project_root, .{}, &llm_provider_contracts.Registry.empty);
    var invocation = engine_invocation.Assembly.init(std.testing.allocator, &boot.ready, &.{"toolchain-check"}, &operations.registry, provider.bind(), runtime);
    defer invocation.deinit();
    const result = workflow_engine.run(invocation.bindings()).executionStatus().?;
    const read_contract: pipeline.NodeContract = .{ .id = "test-toolchain-consumer", .kind = .action, .requires = &.{.valid_toolchain}, .produces = &.{}, .side_effect = .none };
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
        try std.testing.expectEqual(workflow.OutcomeTag.ok, result.executionStatus().?);
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
    try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{"hello"}).executionStatus().?);
    try std.testing.expectEqual(workflow.OutcomeTag.failed, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "Hello/日本語", "--reference", "missing" }).executionStatus().?);
    // The same contracts work under a different workflow ID; no name dispatch.
    const changed = try std.mem.replaceOwned(u8, std.testing.allocator, @embedFile("../test_fixtures/reference-preflight.workflow.yaml"), "id: reference-preflight", "id: documentation-check");
    defer std.testing.allocator.free(changed);
    try project.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/preflight.workflow.yaml", .data = changed });
    try project.dir.createDirPath(io, "references/manual");
    try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "documentation-check", "--feature", "Hello/日本語", "--reference", "manual" }).executionStatus().?);
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
    for (arguments) |args| try std.testing.expectEqual(workflow.OutcomeTag.failed, runInvocationInProject(io, std.testing.allocator, project.dir, args).executionStatus().?);
    var unreadable = try project.dir.openDir(io, "references/real", .{ .iterate = true });
    defer unreadable.close(io);
    try unreadable.setPermissions(io, .fromMode(0o000));
    defer unreadable.setPermissions(io, .fromMode(0o700)) catch @panic("restore test directory permissions");
    try std.testing.expectEqual(workflow.OutcomeTag.failed, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "Hello/日本語", "--reference", "real" }).executionStatus().?);
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
            try std.mem.replaceOwned(u8, std.testing.allocator, original, "use: validate-reference-selector", "use: normalize-reference-selector")
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
        const result = runInvocationInProjectWithRuntime(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "Hello/日本語", "--reference", "hello" }, control.runtime(), null);
        try std.testing.expect(result.executionStatus() != null);
        if (result.executionStatus().? == .ok) {
            try std.testing.expect(checks > 3);
            return;
        }
        try std.testing.expectEqual(workflow.OutcomeTag.cancelled, result.executionStatus().?);
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
    const stories = try std.Io.Dir.cwd().readFileAlloc(io, "test/e2e/wf-001-hello-world/reference/stories.md", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(stories);
    try project.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = stories });
}

test "native YAML compiles selected naming rules and scans text without artifact writes" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try writeReferenceIngestionFixture(io, project.dir);
    const yaml = try @import("../test_fixtures/path_token_workflow.zig").yaml(std.testing.allocator);
    defer std.testing.allocator.free(yaml);
    const renamed = try std.mem.replaceOwned(u8, std.testing.allocator, yaml, "id: reference-ingestion", "id: lexical-check");
    defer std.testing.allocator.free(renamed);
    try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/preflight.workflow.yaml", .data = renamed });
    try project.dir.createDirPath(io, ".sdd/principles");
    try project.dir.createDirPath(io, ".sdd/presets");
    try project.dir.writeFile(io, .{ .sub_path = ".sdd/principles/toolchain.yaml", .data = "schema: project-toolchain/v1\npresets: []\npolicies: [project.zig@1]\n" });
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const closed = try @import("../test_fixtures/clarification_inputs.zig").closed(arena.allocator(), "S01", true);
    try writeClarificationCapture(io, project.dir, closed);
    for ([_][]const u8{ "Use stories.md and src/main.zig?", "Ordinary business text", "\xff" }) |text| {
        try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/sample.txt", .data = text });
        const result = runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "lexical-check", "--feature", "Chosen/Café", "--reference", "first" });
        try std.testing.expectEqual(if (std.unicode.utf8ValidateSlice(text)) workflow.OutcomeTag.ok else .failed, result.executionStatus().?);
        try std.testing.expectError(error.FileNotFound, project.dir.openFile(io, "requirements/current/Chosen/Café/spec.md", .{}));
        const retained = try project.dir.readFileAlloc(io, "requirements/current/Chosen/Café/clarify/S01.md", arena.allocator(), .limited(16384));
        try std.testing.expectEqualSlices(u8, closed.forms[0].bytes, retained);
    }
    try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/sample.txt", .data = "Ordinary text" });
    for ([_][2][]const u8{
        .{ "use: compile-naming-policy", "use: core.noop" },
        .{ "use: build-superset-path-token-grammar", "use: core.noop" },
        .{ "with: { text: sample }", "with: { text: sample, extensions: .zig }" },
        .{ "with: { text: sample }", "with: {}" },
    }) |change| {
        const broken = try std.mem.replaceOwned(u8, std.testing.allocator, renamed, change[0], change[1]);
        defer std.testing.allocator.free(broken);
        try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/preflight.workflow.yaml", .data = broken });
        try std.testing.expect(runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "lexical-check", "--feature", "Chosen/Café", "--reference", "first" }) == .bootstrap_failed);
    }
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
        try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-ingestion", "--feature", "Chosen/Café", "--reference", "first" }).executionStatus().?);
        try std.testing.expectError(error.FileNotFound, project.dir.openDir(io, "requirements", .{}));
        try std.testing.expectError(error.FileNotFound, project.dir.openDir(io, "engine/workflows/features", .{}));
    }
    const renamed = try std.mem.replaceOwned(u8, std.testing.allocator, @embedFile("../test_fixtures/reference-ingestion.workflow.yaml"), "id: reference-ingestion", "id: document-evidence");
    defer std.testing.allocator.free(renamed);
    try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/preflight.workflow.yaml", .data = renamed });
    try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "document-evidence", "--feature", "Chosen/Café", "--reference", "first" }).executionStatus().?);
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
        try std.testing.expectEqual(workflow.OutcomeTag.failed, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-ingestion", "--feature", "Chosen/Café", "--reference", "first" }).executionStatus().?);
        try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{"hello"}).executionStatus().?);
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
        .{ "use: capture-reference-sources", "use: core.noop" },
        .{ "use: validate-reference-inventory", "use: core.noop" },
        .{ "use: assign-reference-identities", "use: core.noop" },
        .{ "use: build-reference-chunks", "use: core.noop" },
        .{ "use: validate-reference-chunks", "use: validate-source-citations" },
        .{ "use: validate-reference-chunks", "use: parse-reference-extraction-results" },
        .{ "use: validate-reference-chunks", "use: scan-reference-passive-literals" },
        .{ "use: validate-reference-chunks", "use: assign-passive-literal-identities" },
        .{ "use: validate-reference-chunks", "use: validate-reference-passive-literals" },
        .{ "use: validate-reference-chunks", "use: validate-reference-extraction-text" },
        .{ "use: validate-reference-chunks", "use: extract-structured-reference-facts" },
        .{ "use: validate-reference-chunks", "use: assign-structured-token-candidate-identities" },
        .{ "use: validate-reference-chunks", "use: validate-reference-selections" },
        .{ "use: validate-reference-chunks", "use: assign-preserved-token-identities" },
        .{ "use: validate-reference-chunks", "use: build-preserved-token-claims" },
        .{ "use: validate-reference-chunks", "use: validate-reference-claims" },
        .{ "use: validate-reference-chunks", "use: assign-reference-claim-identities" },
        .{ "use: validate-reference-chunks", "use: build-reference-extraction-ledger" },
        .{ "use: validate-reference-chunks", "use: validate-reference-extraction-accounting" },
        .{ "use: assign-reference-identities", "use: assign-reference-identities\n    with: { state-id: invented }" },
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
        const result = runInvocationInProjectWithRuntime(io, std.testing.allocator, project.dir, &.{ "reference-ingestion", "--feature", "Chosen/Café", "--reference", "first" }, control.runtime(), null);
        try std.testing.expect(result.executionStatus() != null);
        try std.testing.expectError(error.FileNotFound, project.dir.openDir(io, "requirements", .{}));
        if (result.executionStatus().? == .ok) return;
        try std.testing.expectEqual(workflow.OutcomeTag.cancelled, result.executionStatus().?);
    }
    return error.ReferenceIngestionNeverCompleted;
}

const ReferenceCitationTestProducer = struct {
    invalid: bool,
    observed: usize = 0,
    const bindings = @import("../application/reference_evidence_workflow.zig");
    const evidence = @import("../domain/reference_evidence.zig");
    const values = @import("../application/pipeline_values.zig");
    fn propose(context: ?*@This(), input: workflow_operation_registry.Input) workflow_operation_registry.Error!workflow_execution.Candidate {
        const source = values.read(&input.step.data, bindings.inputs_schema, evidence.Inputs) catch return error.OperationExecutionFailed;
        const chunk = source.chunks.entries[0];
        const proposal: evidence.CitationProposal = .{
            .source_id = chunk.source_id,
            .block_id = chunk.block_id,
            .location = chunk.span,
            .verbatim = if (context.?.invalid) "not in the source" else null,
        };
        return @import("../application/workflow_candidate.zig").publish(std.testing.allocator, bindings.proposals_schema, evidence.CitationProposals, .{
            .scope = .{ .state_id = source.corpus.state_id, .chunk_id = chunk.id },
            .entries = &.{proposal},
        });
    }
    fn observe(context: ?*@This(), input: workflow_operation_registry.Input) workflow_operation_registry.Error!workflow_execution.Candidate {
        const result = values.read(&input.step.data, bindings.citations_schema, evidence.ValidatedCitations) catch return error.OperationExecutionFailed;
        if (result.entries.len != 1) return error.OperationExecutionFailed;
        context.?.observed += 1;
        return .{ .outcome = .ok, .delta = .{} };
    }
};

const ReferenceExtractionTestProducer = struct {
    mode: enum { claims, no_claim, blocked, malformed, missing, duplicate, invalid_citation, unbound, passive, unknown_literal, legacy, preserved, missing_classification, positive_empty_preserved, irrelevant, reconciled, conflict, bad_reconciliation },
    observed: usize = 0,
    const bindings = @import("../application/reference_extraction_workflow.zig");
    const extraction = @import("../domain/reference_extraction.zig");
    const owned = @import("../domain/reference_candidate_value.zig");
    fn propose(context: ?*@This(), input: workflow_operation_registry.Input) workflow_operation_registry.Error!workflow_execution.Candidate {
        const allocator = std.testing.allocator;
        const source = ReferenceCitationTestProducer.values.read(&input.step.data, ReferenceCitationTestProducer.bindings.inputs_schema, ReferenceCitationTestProducer.evidence.Inputs) catch return error.OperationExecutionFailed;
        var arena: std.heap.ArenaAllocator = .init(allocator);
        defer arena.deinit();
        const scratch = arena.allocator();
        const entries = scratch.alloc(extraction.RawResult, if (context.?.mode == .missing) 0 else source.chunks.entries.len) catch return error.OperationExecutionFailed;
        for (entries, 0..) |*entry, index| {
            const chunk = source.chunks.entries[if (context.?.mode == .duplicate) 0 else index];
            var citation_chunk = chunk;
            if (context.?.mode == .invalid_citation) citation_chunk.span.end.line += 1;
            entry.* = .{
                .scope = .{ .state_id = source.corpus.state_id, .chunk_id = chunk.id },
                .result = switch (context.?.mode) {
                    .blocked => .{ .blocked = .extraction_failed },
                    .malformed => .{ .response = "{\"kind\":\"claims\",\"claim_id\":1}" },
                    .no_claim => .{ .response = @import("../reference_extraction_test.zig").no_claim },
                    .unbound => .{ .response = @import("../reference_extraction_test.zig").reply(scratch, citation_chunk, "Read src/main.zig.") catch return error.OperationExecutionFailed },
                    .passive, .unknown_literal => response: {
                        const registry = ReferenceCitationTestProducer.values.read(&input.step.data, @import("../application/passive_literal_workflow.zig").registry_schema, @import("../domain/passive_literals.zig").Registry) catch return error.OperationExecutionFailed;
                        var ordinal: u32 = if (context.?.mode == .unknown_literal) std.math.maxInt(u32) else 0;
                        if (context.?.mode == .passive) for (registry.occurrences) |occurrence| {
                            if (occurrence.origin == .reference_name and occurrence.origin.reference_name.ordinal == chunk.source_id.ordinal) {
                                ordinal = occurrence.id.ordinal;
                                break;
                            }
                        };
                        break :response .{ .response = @import("../reference_extraction_test.zig").passiveReply(scratch, citation_chunk, ordinal) catch return error.OperationExecutionFailed };
                    },
                    .legacy => .{ .response = "{\"kind\":\"no_feature_claim\",\"reason\":\"Old raw text\",\"token_classifications\":[]}" },
                    .preserved, .missing_classification, .positive_empty_preserved, .irrelevant => response: {
                        const token_values = @import("../application/structured_token_workflow.zig");
                        const token_fixture = @import("../test_fixtures/reference_tokens.zig");
                        const candidates = ReferenceCitationTestProducer.values.read(&input.step.data, token_values.candidates_schema, extraction.tokens.Candidates) catch return error.OperationExecutionFailed;
                        const choices = token_fixture.classifications(scratch, candidates.*, chunk) catch return error.OperationExecutionFailed;
                        const decisions = scratch.dupe(extraction.tokens.Classification, choices) catch return error.OperationExecutionFailed;
                        if (context.?.mode == .irrelevant) for (decisions) |*decision| {
                            decision.* = .{ .irrelevant = decision.id() };
                        };
                        const body = if (context.?.mode == .positive_empty_preserved or context.?.mode == .irrelevant) @import("../reference_extraction_test.zig").no_claim else @import("../reference_extraction_test.zig").reply(scratch, chunk, "A supported candidate.") catch return error.OperationExecutionFailed;
                        break :response .{ .response = token_fixture.wire(scratch, body, if (context.?.mode == .missing_classification) &.{} else decisions) catch return error.OperationExecutionFailed };
                    },
                    .claims, .missing, .duplicate, .invalid_citation, .reconciled, .conflict, .bad_reconciliation => .{ .response = @import("../reference_extraction_test.zig").reply(scratch, citation_chunk, "Scripted unreviewed claim.") catch return error.OperationExecutionFailed },
                },
            };
            switch (context.?.mode) {
                .claims, .no_claim, .passive, .invalid_citation, .duplicate => {
                    const token_fixture = @import("../test_fixtures/reference_tokens.zig");
                    const candidates = ReferenceCitationTestProducer.values.read(&input.step.data, @import("../application/structured_token_workflow.zig").candidates_schema, extraction.tokens.Candidates) catch return error.OperationExecutionFailed;
                    const choices = token_fixture.classifications(scratch, candidates.*, chunk) catch return error.OperationExecutionFailed;
                    const decisions = scratch.dupe(extraction.tokens.Classification, choices) catch return error.OperationExecutionFailed;
                    if (context.?.mode == .no_claim) for (decisions) |*decision| {
                        decision.* = .{ .irrelevant = decision.id() };
                    };
                    entry.result.response = token_fixture.wire(scratch, entry.result.response, decisions) catch return error.OperationExecutionFailed;
                },
                else => {},
            }
        }
        const owner = owned.capture(allocator, .{ .entries = entries }) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        return bindings.publish(allocator, bindings.raw_schema, owner, .ok);
    }
    fn observe(context: ?*@This(), input: workflow_operation_registry.Input) workflow_operation_registry.Error!workflow_execution.Candidate {
        const result = try bindings.read(&input.step.data, bindings.accounted_schema, .accounted);
        if (result.payload().accounted.outcome != .complete) return error.OperationExecutionFailed;
        context.?.observed += 1;
        return .{ .outcome = .ok, .delta = .{} };
    }
};

const ReferenceReconciliationTestProducer = struct {
    mode: @FieldType(ReferenceExtractionTestProducer, "mode"),
    observed: usize = 0,
    const native = @import("../application/reference_reconciliation_workflow.zig");
    const fixture = @import("../test_fixtures/reference_reconciliation.zig");
    const prior = @import("../application/reference_extraction_workflow.zig");
    fn propose(context: ?*@This(), input: workflow_operation_registry.Input) workflow_operation_registry.Error!workflow_execution.Candidate {
        const allocator = std.testing.allocator;
        const current = try prior.read(&input.step.data, native.input_schema, .reconciliation_input);
        const packet = current.payload().reconciliation_input;
        var arena: std.heap.ArenaAllocator = .init(allocator);
        defer arena.deinit();
        const scratch = arena.allocator();
        const response = if (packet.purpose == .summary)
            @import("../domain/model_candidate_json.zig").encodeSelected(@FieldType(fixture.r.Parsed, "proposal"), scratch, .{ .summary = fixture.summary(scratch, packet) catch return error.OperationExecutionFailed }) catch return error.OperationExecutionFailed
        else final: {
            var proposal = if (context.?.mode == .conflict) @import("../reference_reconciliation_test.zig").conflicting(scratch, packet) catch return error.OperationExecutionFailed else fixture.global(scratch, packet) catch return error.OperationExecutionFailed;
            if (context.?.mode == .bad_reconciliation) proposal.claim_dispositions = proposal.claim_dispositions[1..];
            break :final @import("../domain/model_candidate_json.zig").encodeSelected(@FieldType(fixture.r.Parsed, "proposal"), scratch, .{ .global = proposal }) catch return error.OperationExecutionFailed;
        };
        const owner = try native.capture(allocator, current, response);
        errdefer @import("../domain/reference_candidate_value.zig").destroy(owner);
        return prior.publish(allocator, native.raw_schema, owner, .ok);
    }
    fn observe(context: ?*@This(), input: workflow_operation_registry.Input) workflow_operation_registry.Error!workflow_execution.Candidate {
        const result = try prior.read(&input.step.data, native.accounted_schema, .reconciliation_accounted);
        if (result.payload().reconciliation_accounted.outcome != .complete) return error.OperationExecutionFailed;
        const authority = @import("../application/required_authority_workflow.zig");
        const ledger = @import("../application/required_authority_values.zig").read(&input.step.data, authority.ledger_schema, .ledger) catch return error.OperationExecutionFailed;
        if (ledger.requirements.len < 3 or ledger.inputs.projection != .specification or ledger.inputs.evidence.len != 0) return error.OperationExecutionFailed;
        if (!ledger.inputs.references.?.records.assignments.checked.prior.prior.input.progress.plan.layout.items.state_id.eql(result.payload().reconciliation_accounted.records.assignments.checked.prior.prior.input.progress.plan.layout.items.state_id)) return error.OperationExecutionFailed;
        context.?.observed += 1;
        return .{ .outcome = .ok, .delta = .{} };
    }
};

test "native YAML validates citations extraction and reconciliation before continuation" {
    const io = std.testing.io;
    const binding = @import("../application/workflow_operation_binding.zig");
    const scenarios = [_]?@FieldType(ReferenceExtractionTestProducer, "mode"){ null, null, .claims, .no_claim, .blocked, .malformed, .missing, .duplicate, .invalid_citation, .unbound, .passive, .unknown_literal, .legacy, .preserved, .missing_classification, .positive_empty_preserved, .irrelevant, .reconciled, .conflict, .bad_reconciliation };
    for (scenarios, 0..) |mode, scenario| {
        const invalid = scenario == 1;
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try writeReferenceIngestionFixture(io, project.dir);
        const reconcile = mode == .reconciled or mode == .conflict or mode == .bad_reconciliation;
        if (reconcile) {
            try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = "A submitted request requires confirmation.\n" });
            try project.dir.writeFile(io, .{ .sub_path = "source-material/first/second.md", .data = "The request requires approval.\n" });
        }
        if (mode == .preserved or mode == .missing_classification or mode == .positive_empty_preserved or mode == .irrelevant) try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = "Display `Hello, World!` and retain `Cafe\u{301}`.\n" });
        const suffix = if (mode != null) "use: assign-structured-token-candidate-identities, on: { ok: propose-extraction, failed: end.failed } }\n" ++
            "  propose-extraction: { use: test.propose-extraction, on: { ok: parse-extraction } }\n" ++
            "  parse-extraction: { use: parse-reference-extraction-results, on: { ok: validate-text, failed: end.failed } }\n" ++
            "  validate-text: { use: validate-reference-extraction-text, on: { ok: validate-classifications, failed: end.failed } }\n" ++
            "  validate-classifications: { use: validate-reference-selections, on: { ok: assign-tokens, invalid: end.invalid, failed: end.failed } }\n" ++
            "  assign-tokens: { use: assign-preserved-token-identities, on: { ok: build-token-claims, failed: end.failed } }\n" ++
            "  build-token-claims: { use: build-preserved-token-claims, on: { ok: validate-claims, failed: end.failed } }\n" ++
            "  validate-claims: { use: validate-reference-claims, on: { ok: assign-claims, invalid: end.invalid, failed: end.failed } }\n" ++
            "  assign-claims: { use: assign-reference-claim-identities, on: { ok: build-ledger, failed: end.failed } }\n" ++
            "  build-ledger: { use: build-reference-extraction-ledger, on: { ok: account-extraction, failed: end.failed } }\n" ++
            "  account-extraction: { use: validate-reference-extraction-accounting, on: { ok: observe-extraction, blocked: end.blocked, failed: end.failed } }\n" ++
            "  observe-extraction: { use: test.observe-extraction, on: { ok: end.ok } }" else "use: validate-reference-chunks\n    on: { ok: propose-citations, failed: end.failed }\n" ++
            "  propose-citations: { use: test.propose-citations, on: { ok: validate-citations } }\n" ++
            "  validate-citations: { use: validate-source-citations, on: { ok: observe-citations, failed: end.failed } }\n" ++
            "  observe-citations: { use: test.observe-citations, on: { ok: end.ok } }";
        const preparation = try @import("../test_fixtures/reference_tokens_workflow.zig").yaml(std.testing.allocator);
        defer std.testing.allocator.free(preparation);
        const yaml = try std.mem.replaceOwned(u8, std.testing.allocator, if (mode != null) preparation else @embedFile("../test_fixtures/reference-ingestion.workflow.yaml"), if (mode != null) "use: assign-structured-token-candidate-identities, on: { ok: end.ok, failed: end.failed } }" else "use: validate-reference-chunks\n    on: { ok: end.ok, failed: end.failed }", suffix);
        defer std.testing.allocator.free(yaml);
        const reconciliation_suffix = try @import("../test_fixtures/reference_reconciliation_workflow.zig").suffix(std.testing.allocator, 3);
        defer std.testing.allocator.free(reconciliation_suffix);
        const complete_yaml = if (reconcile) try std.mem.replaceOwned(u8, std.testing.allocator, yaml, "  observe-extraction: { use: test.observe-extraction, on: { ok: end.ok } }", reconciliation_suffix) else try std.testing.allocator.dupe(u8, yaml);
        defer std.testing.allocator.free(complete_yaml);
        try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/preflight.workflow.yaml", .data = complete_yaml });
        if (mode != null) {
            try project.dir.createDirPath(io, ".sdd/principles");
            try project.dir.createDirPath(io, ".sdd/presets");
            try project.dir.writeFile(io, .{ .sub_path = ".sdd/principles/toolchain.yaml", .data = "schema: project-toolchain/v1\npresets: []\npolicies: [project.zig@1]\n" });
        }
        if (mode == .duplicate) try project.dir.writeFile(io, .{ .sub_path = "source-material/first/second.md", .data = "Another independent requirement.\n" });
        var project_source = toolchain_authority_source.Adapter.init(io, project.dir);
        var document_parser: toolchain_documents.Adapter = .{};
        var reference_source: @import("../adapters/filesystem/reference_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var feature_source: @import("../adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var feature_inputs: @import("../adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var reference_contents: @import("../adapters/filesystem/reference_corpus_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var markdown_reader: @import("../adapters/parsers/markdown_reference.zig").Adapter = .{ .io = io };
        var reference_ids: @import("../adapters/system/reference_state_identity.zig").Adapter = .{ .io = io };
        var native: @import("native_workflow_operations.zig").Assembly = undefined;
        native.init(std.testing.allocator, project_source.projectCapturer(), project_source.presetEnumerator(), project_source.presetCapturer(), document_parser.parser(), policy_registry, .{ .normalize_fn = @import("unicode_normalization").nfc }, reference_source.inspector(), feature_source.inspector(), feature_inputs.capturer(), @import("../adapters/parsers/clarification_inputs.zig").stateParser(), @import("../adapters/parsers/clarification_inputs.zig").formParser(), reference_contents.enumerator(), reference_contents.capturer(), markdown_reader.decoderPort(), .{ .fold_fn = @import("unicode_normalization").caseFold }, reference_ids.source(), .{ .boundary_fn = @import("unicode_normalization").lexicalBoundary });
        var producer: ReferenceCitationTestProducer = .{ .invalid = invalid };
        var extraction_producer: ReferenceExtractionTestProducer = .{ .mode = mode orelse .claims };
        var reconciliation_producer: ReferenceReconciliationTestProducer = .{ .mode = mode orelse .claims };
        var protected_arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer protected_arena.deinit();
        const closed = try @import("../test_fixtures/clarification_inputs.zig").closed(protected_arena.allocator(), "S01", true);
        try writeClarificationCapture(io, project.dir, closed);
        const entries = native.entries ++ [_]workflow_operation_registry.Entry{
            .{ .contract = .{ .id = "test.propose-citations", .kind = .step, .requires = &.{.citable_reference_inputs}, .produces = &.{.reference_citation_proposals}, .outcomes = &.{.ok}, .side_effect = .none }, .binding = binding.bind(ReferenceCitationTestProducer, &producer, ReferenceCitationTestProducer.propose) },
            .{ .contract = .{ .id = "test.observe-citations", .kind = .step, .requires = &.{.validated_source_citations}, .outcomes = &.{.ok}, .side_effect = .none }, .binding = binding.bind(ReferenceCitationTestProducer, &producer, ReferenceCitationTestProducer.observe) },
            .{ .contract = .{ .id = "test.propose-extraction", .kind = .step, .requires = &.{ .citable_reference_inputs, .reference_passive_literals, .structured_token_candidates }, .produces = &.{.raw_reference_extraction}, .outcomes = &.{.ok}, .side_effect = .none }, .binding = binding.bind(ReferenceExtractionTestProducer, &extraction_producer, ReferenceExtractionTestProducer.propose) },
            .{ .contract = .{ .id = "test.observe-extraction", .kind = .step, .requires = &.{.accounted_reference_extraction}, .outcomes = &.{.ok}, .side_effect = .none }, .binding = binding.bind(ReferenceExtractionTestProducer, &extraction_producer, ReferenceExtractionTestProducer.observe) },
            .{ .contract = .{ .id = "test.propose-reconciliation", .kind = .step, .requires = &.{.reference_reconciliation_input}, .produces = &.{.raw_reference_reconciliation}, .outcomes = &.{.ok}, .side_effect = .none }, .binding = binding.bind(ReferenceReconciliationTestProducer, &reconciliation_producer, ReferenceReconciliationTestProducer.propose) },
            .{ .contract = .{ .id = "test.observe-reconciliation", .kind = .step, .requires = &.{ .accounted_reference_reconciliation, .required_authority_ledger }, .outcomes = &.{.ok}, .side_effect = .none }, .binding = binding.bind(ReferenceReconciliationTestProducer, &reconciliation_producer, ReferenceReconciliationTestProducer.observe) },
        };
        native.registry.operations = &entries;
        var boot = runInProjectWithRegistry(io, std.testing.allocator, project.dir, .{}, &native.registry);
        defer boot.deinit();
        try std.testing.expect(boot == .ready);
        native.bindRoots(boot.ready.roots.registry());
        var providers = model_provider_bootstrap.Assembly.init(io, std.testing.allocator, project.dir, .{}, &llm_provider_contracts.Registry.empty);
        const result = runBootstrappedInvocation(std.testing.allocator, &boot, &.{ "reference-ingestion", "--feature", "Chosen/Café", "--reference", "first" }, &native.registry, providers.bind(), .{}, null, null);
        const expected: workflow.OutcomeTag = if (mode) |selected| switch (selected) {
            .claims, .no_claim, .passive, .preserved, .irrelevant, .reconciled => .ok,
            .blocked, .conflict => .blocked,
            .missing_classification, .positive_empty_preserved, .invalid_citation => .invalid,
            .malformed, .missing, .duplicate, .unbound, .unknown_literal, .legacy, .bad_reconciliation => .failed,
        } else if (invalid) .failed else .ok;
        try std.testing.expectEqual(expected, result.executionStatus().?);
        try std.testing.expectEqual(@as(usize, if (expected == .ok) 1 else 0), if (reconcile) reconciliation_producer.observed else if (mode != null) extraction_producer.observed else producer.observed);
        const retained = try project.dir.readFileAlloc(io, "requirements/current/Chosen/Café/clarify/S01.md", protected_arena.allocator(), .limited(16384));
        try std.testing.expectEqualSlices(u8, closed.forms[0].bytes, retained);
        try std.testing.expectError(error.FileNotFound, project.dir.openFile(io, "requirements/current/Chosen/Café/spec.md", .{}));
        if (mode == .reconciled) {
            for ([_][2][]const u8{
                .{ "with: { group-size: 2 }", "with: { group-size: 1 }" },
                .{ "with: { group-size: 2 }", "with: {}" },
                .{ "use: validate-reference-reconciliation-summary", "use: assign-reference-summary-identities" },
                .{ "use: validate-reference-conflict-proposals", "use: assign-reference-reconciliation-identities" },
            }) |change| {
                const invalid_yaml = try std.mem.replaceOwned(u8, std.testing.allocator, complete_yaml, change[0], change[1]);
                defer std.testing.allocator.free(invalid_yaml);
                try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/preflight.workflow.yaml", .data = invalid_yaml });
                var rejected = runInProjectWithRegistry(io, std.testing.allocator, project.dir, .{}, &native.registry);
                defer rejected.deinit();
                try std.testing.expect(rejected != .ready);
            }
        }
    }
}

test "configured specification generation YAML executes native references models and authority gates" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const faults = [_]@import("../test_fixtures/spec_generation_driver.zig").Fault{
        .{ .stage = .extraction, .shape = .empty },
        .{ .stage = .reconciliation, .shape = .empty },
        .{ .stage = .generation, .shape = .empty },
        .{ .stage = .repair, .shape = .empty },
        .{ .stage = .support, .shape = .empty },
        .{ .stage = .extraction, .shape = .nested_empty },
        .{ .stage = .reconciliation, .shape = .nested_empty },
        .{ .stage = .generation, .shape = .nested_empty },
        .{ .stage = .repair, .shape = .nested_empty },
        .{ .stage = .generation, .shape = .mixed_variant },
        .{ .stage = .generation, .shape = .empty, .repetition = .persistent },
        .{ .stage = .repair, .shape = .empty, .repetition = .persistent },
        .{ .stage = .extraction, .shape = .alternating_protocol, .repetition = .{ .every_request = 2 } },
        .{ .stage = .reconciliation, .shape = .alternating_protocol, .repetition = .{ .every_request = 2 } },
        .{ .stage = .generation, .shape = .alternating_protocol, .repetition = .{ .every_request = 2 } },
    };
    const classification_repair_start = 14 + faults.len;
    const citation_repair_start = classification_repair_start + 3;
    for (0..citation_repair_start + 3) |scenario| {
        const citation_scenario = scenario >= citation_repair_start;
        const classification_scenario = scenario >= classification_repair_start and !citation_scenario;
        const fault: ?@TypeOf(faults[0]) = if (scenario >= 14 and !classification_scenario and !citation_scenario) faults[scenario - 14] else null;
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try writeReferenceIngestionFixture(io, project.dir);
        try project.dir.createDirPath(io, ".sdd/principles");
        try project.dir.createDirPath(io, ".sdd/presets");
        try project.dir.createDirPath(io, "engine/workflows/spec");
        try project.dir.writeFile(io, .{ .sub_path = ".sdd/principles/toolchain.yaml", .data = "schema: project-toolchain/v1\npresets: []\npolicies: [project.zig@1]\n" });
        if (scenario == 1 or (scenario >= 8 and scenario != 12)) try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = "A librarian renews a loan.\n" ** 70 ++ "Display `Loan renewed!`.\n" });
        const definition = try std.Io.Dir.cwd().readFileAlloc(io, "design/workflows/spec.workflow.yaml", allocator, .limited(1_048_576));
        defer allocator.free(definition);
        try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/preflight.workflow.yaml", .data = definition });
        const protocol_prompt = try std.Io.Dir.cwd().readFileAlloc(io, "design/workflows/spec/protocol.prompt.md", allocator, .limited(1_048_576));
        defer allocator.free(protocol_prompt);
        try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/spec/protocol.prompt.md", .data = protocol_prompt });
        inline for (.{ "extraction", "reconciliation", "generation", "support", "repair" }) |name| inline for (.{ "prompt.md", "schema.json" }) |extension| {
            const bytes = try std.Io.Dir.cwd().readFileAlloc(io, "design/workflows/spec/" ++ name ++ "." ++ extension, allocator, .limited(1_048_576));
            defer allocator.free(bytes);
            try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/spec/" ++ name ++ "." ++ extension, .data = bytes });
        };
        var project_source = toolchain_authority_source.Adapter.init(io, project.dir);
        var document_parser: toolchain_documents.Adapter = .{};
        var reference_source: @import("../adapters/filesystem/reference_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var feature_source: @import("../adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var feature_inputs: @import("../adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var reference_contents: @import("../adapters/filesystem/reference_corpus_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var markdown_reader: @import("../adapters/parsers/markdown_reference.zig").Adapter = .{ .io = io };
        var reference_ids: @import("../adapters/system/reference_state_identity.zig").Adapter = .{ .io = io };
        var native: @import("native_workflow_operations.zig").Assembly = undefined;
        native.init(allocator, project_source.projectCapturer(), project_source.presetEnumerator(), project_source.presetCapturer(), document_parser.parser(), policy_registry, .{ .normalize_fn = @import("unicode_normalization").nfc }, reference_source.inspector(), feature_source.inspector(), feature_inputs.capturer(), @import("../adapters/parsers/clarification_inputs.zig").stateParser(), @import("../adapters/parsers/clarification_inputs.zig").formParser(), reference_contents.enumerator(), reference_contents.capturer(), markdown_reader.decoderPort(), .{ .fold_fn = @import("unicode_normalization").caseFold }, reference_ids.source(), .{ .boundary_fn = @import("unicode_normalization").lexicalBoundary });
        var boot = runInProjectWithRegistry(io, allocator, project.dir, .{}, &native.registry);
        defer boot.deinit();
        var feature_outputs: @import("../adapters/filesystem/workflow_output.zig").Adapter = .{ .io = io, .project_root = project.dir };
        native.publish_output.action.writer = feature_outputs.port();
        native.capture_workflow_state.action.source = feature_inputs.workflowStateCapturer();
        if (boot != .ready) std.debug.print("generation bootstrap: {any}\n", .{boot});
        try std.testing.expect(boot == .ready);
        native.bindRoots(boot.ready.roots.registry());
        var services = try @import("../model_request_workflow_test.zig").providerServices(allocator, null, "spec_generation");
        defer services.deinit();
        const graph = boot.ready.workflows.registry().resolve(.{ .bytes = "spec-generation" }).?;
        var runner = @import("../application/workflow_pipeline_runner.zig").Runner.init(allocator, .{ .invocation = .{ .workflow_id = graph.authority.workflow_id, .arguments = &.{ "--feature", "chosen", "--reference", "first" } }, .graph = graph }, &native.registry, boot.ready.logs.barrier(), .{}, &services);
        defer runner.deinit();
        var clock: @import("../provider_authorization_test_fixture.zig").TestClock = .{};
        runner.provider_clock = clock.port();
        var authorization: @import("../adapters/provider/fake_provider_authorization.zig").FakeProviderAuthorization = .{ .allocator = allocator };
        native.model_requests.prepare_authorization.action = .{ .authorization = authorization.port() };
        var fake = @import("../model_request_workflow_test.zig").invocationProvider(&runner, allocator);
        native.model_requests.invoke_model.action = .{ .provider = fake.interface() };
        var driver: @import("../test_fixtures/spec_generation_driver.zig").Driver = .{ .runner = &runner, .fake = &fake, .malformed = scenario == 2, .uncertain = scenario == 3, .malformed_once = scenario == 4 or scenario == 9, .repair = scenario == 5 or scenario == 6 or scenario == 8, .failed_repair = scenario == 6, .omit_exact = scenario == 7, .brief_uncertain = scenario == 10, .entities_required = scenario == 11 };
        if (fault) |selected_fault| {
            driver.fault = selected_fault;
            driver.repair = selected_fault.stage == .repair;
        }
        driver.generation_gap = scenario == 12 or scenario == 13;
        driver.missing_classifications = classification_scenario;
        driver.malformed_classification_repair_once = scenario == classification_repair_start + 1;
        driver.failed_classification_repair = scenario == classification_repair_start + 2;
        driver.citation_fault = if (citation_scenario) (if (scenario == citation_repair_start + 1) .missing else .unknown) else null;
        driver.failed_citation_repair = scenario == citation_repair_start + 2;
        const result = driver.run();
        const expected: workflow.OutcomeTag = if (scenario == 2 or scenario == 6 or driver.failed_classification_repair or driver.failed_citation_repair or (fault != null and fault.?.repetition == .persistent)) .failed else if (scenario == 3 or scenario == 10 or driver.generation_gap) .needs_user else if (scenario == 7) .invalid else .ok;
        try std.testing.expectEqual(expected, result.executionStatus().?);
        if (citation_scenario) {
            try std.testing.expectEqual(@as(usize, 2), driver.citation_repair_calls);
            const diagnostic = try @import("../application/candidate_validation_diagnostics.zig").read(&.{ .slots = runner.envelope.slots });
            if (driver.failed_citation_repair) {
                try std.testing.expect(diagnostic != null and diagnostic.? == .source_selections);
                const rejected = diagnostic.?.source_selections;
                try std.testing.expectEqual(.unknown_selection, rejected.issue.reason);
                try std.testing.expect(rejected.origin != null);
                var diagnostic_arena: std.heap.ArenaAllocator = .init(allocator);
                defer diagnostic_arena.deinit();
                const retained = try diagnostic.?.copy(diagnostic_arena.allocator());
                try std.testing.expectEqualDeep(rejected.origin, retained.origin());
                var matching: usize = 0;
                const identities = try @import("../application/pipeline_values.zig").read(&.{ .slots = runner.envelope.slots }, @import("../application/model_request_workflow.zig").ledger_schema, @import("../domain/model_request_identity.zig").ModelRequestIdentityLedger);
                for (runner.tokenLedger().accounted_operations.items) |operation| if (rejected.origin.?.matches(identities, operation)) {
                    try std.testing.expect(operation.model_request_id.purpose == .atomic_repair);
                    matching += 1;
                };
                try std.testing.expectEqual(@as(usize, 1), matching);
            } else try std.testing.expect(diagnostic == null);
        }
        if (classification_scenario) {
            try std.testing.expectEqual(@as(usize, if (scenario == classification_repair_start) 1 else 2), driver.classification_repair_calls);
            const diagnostic = try @import("../application/candidate_validation_diagnostics.zig").read(&.{ .slots = runner.envelope.slots });
            if (driver.failed_classification_repair) {
                try std.testing.expect(diagnostic != null and diagnostic.? == .token_classifications);
                try std.testing.expect(diagnostic.?.token_classifications.issues.missing.len != 0);
            } else try std.testing.expect(diagnostic == null);
        }
        if (fault) |selected_fault| switch (selected_fault.repetition) {
            .once => try std.testing.expectEqual(@as(usize, 1), driver.fault_calls),
            .every_request => |count| {
                // Distinct logical requests traverse the same correction step.
                try std.testing.expect(driver.fault_requests >= 2);
                try std.testing.expectEqual(driver.fault_requests * count, driver.fault_calls);
            },
            .persistent => {
                const exhausted = result.execution_rejected.retry_limit;
                var matched = false;
                for (graph.authority.steps) |step| if (std.mem.eql(u8, step.id.bytes, exhausted.operation().bytes)) {
                    try std.testing.expectEqualStrings("advance-model-attempt-accounting", step.operation_id.bytes);
                    try std.testing.expectEqual(step.retry_authority.?.limit.value, exhausted.limit.value);
                    try std.testing.expectEqual(@as(u64, exhausted.limit.value) + 1, exhausted.completed_executions);
                    try std.testing.expectEqual(exhausted.completed_executions, driver.fault_calls);
                    matched = true;
                };
                try std.testing.expect(matched);
            },
        };
        if (expected == .ok) {
            const content = try @import("../application/required_authority_values.zig").read(&.{ .slots = runner.envelope.slots }, @import("../application/required_authority_workflow.zig").content_schema, .content);
            try std.testing.expect(content.records.len != 0);
            try std.testing.expectEqual(@as(@TypeOf(content.entities.disposition), if (scenario == 11) .required else .not_applicable), content.entities.disposition);
            try std.testing.expect(runner.envelope.checkGate(@import("../application/required_authority_workflow.zig").gate_contract) == null);
            try std.testing.expect(runner.envelope.slots[@intFromEnum(pipeline.DataKey.prepared_model_request)] == null);
            const rendered = try @import("../application/specification_values.zig").storage.read(&.{ .slots = runner.envelope.slots }, @import("../application/specification_rendering_workflow.zig").rendered_schema, .rendered);
            var arena: std.heap.ArenaAllocator = .init(allocator);
            defer arena.deinit();
            _ = try @import("../domain/specification_markdown.zig").parse(arena.allocator(), rendered);
            try std.testing.expect((try @import("../application/pipeline_values.zig").read(&.{ .slots = runner.envelope.slots }, @import("../application/specification_rendering_workflow.zig").validated_schema, bool)).*);
        }
        if (driver.generation_gap) {
            const views = try @import("../application/pipeline_values.zig").read(&.{ .slots = runner.envelope.slots }, @import("../application/clarification_refresh_workflow.zig").views_schema, []const @import("../domain/clarification_views.zig").View);
            try std.testing.expectEqual(@as(usize, 1), views.len);
            try std.testing.expectEqualStrings("S01.md", &views.*[0].id.filename());
            try std.testing.expect(views.*[0].content == .replace);
            const bytes = try project.dir.readFileAlloc(io, "requirements/current/chosen/clarify/S01.md", allocator, .limited(16_384));
            defer allocator.free(bytes);
            try std.testing.expectEqualStrings(views.*[0].content.replace, bytes);
            const persisted = try project.dir.readFileAlloc(io, "engine/workflows/features/chosen/state/clarifications.json", allocator, .limited(8_388_608));
            defer allocator.free(persisted);
            var parsed = try std.json.parseFromSlice(@import("../domain/clarification_inputs.zig").State, allocator, persisted, .{});
            defer parsed.deinit();
            try std.testing.expectEqual(@as(usize, 1), parsed.value.records.len);
            try std.testing.expectEqualStrings("specification", parsed.value.records[0].subject.requirement);
        }
        if (expected == .ok) {
            const bytes = try project.dir.readFileAlloc(io, "requirements/current/chosen/spec.md", allocator, .limited(8_388_608));
            defer allocator.free(bytes);
            const rendered = try @import("../application/specification_values.zig").storage.read(&.{ .slots = runner.envelope.slots }, @import("../application/specification_rendering_workflow.zig").rendered_schema, .rendered);
            try std.testing.expectEqualStrings(rendered, bytes);
            if (classification_scenario or citation_scenario) {
                // Capturing repaired candidates must not exempt their source
                // authority from the ordinary stale-generation gate.
                const source_schema = @import("../application/reference_evidence_workflow.zig").inputs_schema;
                const pipeline_values = @import("../application/pipeline_values.zig");
                const source = try pipeline_values.read(&.{ .slots = runner.envelope.slots }, source_schema, @import("../domain/reference_evidence.zig").Inputs);
                var changed: pipeline.NodeDelta = .{};
                defer runner.envelope.discard(&changed);
                changed.data_replacements[@intFromEnum(source_schema.key)] = try pipeline_values.create(allocator, source_schema, @import("../domain/reference_evidence.zig").Inputs, source.*);
                try runner.envelope.apply(.{ .id = "test.refresh-source", .kind = .action, .requires = &.{.citable_reference_inputs}, .produces = &.{}, .replaces = &.{.citable_reference_inputs}, .side_effect = .none }, &changed, .ok);
                try std.testing.expectEqual(@import("../domain/workflow_gate.zig").Rejection.stale_authority, runner.envelope.checkGate(@import("../application/required_authority_workflow.zig").gate_contract).?);
            }
        } else try std.testing.expectError(error.FileNotFound, project.dir.openFile(io, "requirements/current/chosen/spec.md", .{}));
    }
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
        try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "feature-input-preflight", "--feature", "Chosen/Café", "--reference", "first" }).executionStatus().?);
        try std.testing.expectError(error.FileNotFound, project.dir.openDir(io, "requirements", .{}));
        try std.testing.expectError(error.FileNotFound, project.dir.openDir(io, "engine/workflows/features", .{}));
    }
    // Unselected invalid content is not read, even though its reader is registered.
    try project.dir.createDirPath(io, "requirements/current/Chosen/Café/clarify");
    try project.dir.writeFile(io, .{ .sub_path = "requirements/current/Chosen/Café/clarify/unknown.txt", .data = "unrecognized" });
    try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{"hello"}).executionStatus().?);
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
            try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "feature-input-preflight", "--feature", "Chosen/Café", "--reference", reference }).executionStatus().?);
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
        try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "arbitrary-preparation", "--feature", "Chosen/Café", "--reference", "first" }).executionStatus().?);
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
        try std.testing.expectEqual(workflow.OutcomeTag.failed, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "feature-input-preflight", "--feature", "Chosen/Café", "--reference", "first" }).executionStatus().?);
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
        try std.testing.expectEqual(workflow.OutcomeTag.failed, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "feature-input-preflight", "--feature", "Chosen/Café", "--reference", "first" }).executionStatus().?);
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

test "clarification publication refreshes stable paths and protects concurrent closes across stages" {
    const c = @import("../domain/clarification_inputs.zig");
    const fixture = @import("../test_fixtures/clarification_inputs.zig");
    const forms = @import("../domain/clarification_form.zig");
    const refresh = @import("../domain/clarification_refresh.zig");
    const parser = @import("../adapters/parsers/clarification_inputs.zig");
    const io = std.testing.io;
    for ([_][]const u8{ "S01", "P01", "T01" }) |name| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try writeFeatureInputFixture(io, project.dir);
        try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/preflight.workflow.yaml", .data = output_test_bootstrap });
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        for (0..3) |iteration| {
            var boot = runInProject(io, std.testing.allocator, project.dir);
            defer boot.deinit();
            try std.testing.expect(boot == .ready);
            const registry = boot.ready.roots.registry();
            const selected = try @import("../domain/feature_directory.zig").validate(a, .{ .bytes = "Chosen/Café" }, registry.featureDirectoryRoots());
            var inspector_adapter: @import("../adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
            var inspector = inspector_adapter.inspector();
            inspector.capability = registry.featureDirectoryRead();
            const observed = try inspector.inspect(a, selected);
            const paths = try @import("../domain/workflow_artifact_registry.zig").resolveFeaturePaths(a, registry.featureArtifactRoots(), selected);
            var source_adapter: @import("../adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
            var source = source_adapter.capturer();
            source.capability = registry.featureInputRead();
            const captured = try source.capture(a, observed, paths);
            const parsed = try (@import("../actions/clarification/parse_clarification_state.zig").Action{ .parser = parser.stateParser() }).execute(a, captured);
            const state = try c.validate(parsed, selected.feature_id);
            const inputs = try (@import("../actions/clarification/validate_clarification_forms.zig").Action{ .parser = parser.formParser() }).execute(a, state, captured);
            const record = fixture.record(name);
            const need: refresh.Need = .{ .stage = c.Id.parse(name).?.stage, .subject = record.subject, .authority = record.authority, .question = record.question, .why_required = record.why_required, .answer_schema = record.answer_schema };
            const next = try refresh.refresh(a, inputs, .{ .feature = selected.feature_id, .entries = &.{need} });
            const views = try @import("../domain/clarification_views.zig").render(a, next, inputs.protected_forms);
            const prepared = try (@import("../actions/clarification/prepare_clarification_output.zig").Action{}).execute(a, observed, paths, captured, inputs, .{ .ready = next }, views);
            const form_path = try std.mem.concat(a, u8, &.{ selected.project_relative_path, "/clarify/", name, ".md" });
            var writer_adapter: @import("../adapters/filesystem/workflow_output.zig").Adapter = .{ .io = io, .project_root = project.dir };
            var writer = writer_adapter.port();
            try std.testing.expectError(error.OutputWriteFailed, writer.publish(a, prepared));
            writer.capability = registry.featureOutputWrite();
            if (iteration == 2) {
                const old = state.value.?;
                // Even an invalid/empty concurrent close is never overwritten.
                const closed = try forms.render(a, old.records[0], fixture.binding(old, old.records[0]), .closed, "");
                try project.dir.writeFile(io, .{ .sub_path = form_path, .data = closed });
                try std.testing.expectError(error.OutputChanged, writer.publish(a, prepared));
                try std.testing.expectEqualStrings(closed, try project.dir.readFileAlloc(io, form_path, a, .limited(c.max_form_bytes)));
                try std.testing.expectEqualStrings(captured.state.?, try project.dir.readFileAlloc(io, paths.get(.clarification_state).project_relative, a, .limited(c.max_state_bytes)));
            } else {
                try writer.publish(a, prepared);
                try std.testing.expectEqualStrings(views[0].content.replace, try project.dir.readFileAlloc(io, form_path, a, .limited(c.max_form_bytes)));
                try std.testing.expectEqualStrings(name, next.value.?.records[0].id);
                try std.testing.expectEqual(@as(usize, 1), next.value.?.records.len);
                const old = next.value.?;
                try project.dir.writeFile(io, .{ .sub_path = form_path, .data = try forms.render(a, old.records[0], fixture.binding(old, old.records[0]), .open, "An unsubmitted long draft that will disappear completely on rerun." ** 8) });
            }
            try std.testing.expectError(error.FileNotFound, project.dir.openFile(io, paths.get(.specification).project_relative, .{}));
            try std.testing.expectError(error.FileNotFound, project.dir.openFile(io, paths.get(.workflow_state).project_relative, .{}));
        }
    }
}

test "registered output writer validates the complete set and never writes completion after a failed file" {
    const output = @import("../domain/workflow_output.zig");
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try writeFeatureInputFixture(io, project.dir);
    try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/preflight.workflow.yaml", .data = output_test_bootstrap });
    try project.dir.createDirPath(io, "requirements/current/Chosen/Café/spec.md");
    var boot = runInProject(io, std.testing.allocator, project.dir);
    defer boot.deinit();
    try std.testing.expect(boot == .ready);
    const registry = boot.ready.roots.registry();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const selected = try @import("../domain/feature_directory.zig").validate(a, .{ .bytes = "Chosen/Café" }, registry.featureDirectoryRoots());
    var inspector_adapter: @import("../adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
    var inspector = inspector_adapter.inspector();
    inspector.capability = registry.featureDirectoryRead();
    const observed = try inspector.inspect(a, selected);
    const paths = try @import("../domain/workflow_artifact_registry.zig").resolveFeaturePaths(a, registry.featureArtifactRoots(), selected);
    const view: output.File = .{ .target = .{ .artifact = .reference_context }, .bytes = "reference view\n" };
    const state: output.File = .{ .target = .{ .artifact = .workflow_state }, .bytes = "test completion\n" };
    var prepared: output.Prepared = .{ .feature = observed, .paths = paths, .prior = .{ .state = null, .forms = &.{} }, .prior_workflow_state = .{ .captured = null }, .files = &.{ state, view } };
    var writer_adapter: @import("../adapters/filesystem/workflow_output.zig").Adapter = .{ .io = io, .project_root = project.dir };
    var writer = writer_adapter.port();
    writer.capability = registry.featureOutputWrite();
    try std.testing.expectError(error.InvalidWorkflowOutput, writer.publish(a, prepared));
    prepared.files = &.{ view, view };
    try std.testing.expectError(error.InvalidWorkflowOutput, writer.publish(a, prepared));
    try std.testing.expectError(error.FileNotFound, project.dir.openFile(io, paths.get(.reference_context).project_relative, .{}));
    prepared.files = &.{ view, .{ .target = .{ .artifact = .specification }, .bytes = "test view\n" }, state };
    try std.testing.expectError(error.OutputWriteFailed, writer.publish(a, prepared));
    try std.testing.expectEqualStrings(view.bytes, try project.dir.readFileAlloc(io, paths.get(.reference_context).project_relative, a, .limited(128)));
    try std.testing.expectError(error.FileNotFound, project.dir.openFile(io, paths.get(.workflow_state).project_relative, .{}));
    // A new validated output replaces prior bytes completely, without a journal.
    prepared.files = &.{.{ .target = view.target, .bytes = "x\n" }};
    try writer.publish(a, prepared);
    try std.testing.expectEqualStrings("x\n", try project.dir.readFileAlloc(io, paths.get(.reference_context).project_relative, a, .limited(128)));
}

// Writer tests need configured roots, not the native input-preflight graph.
test "every registered publication write failure prevents completion and a fresh run replaces the complete set" {
    const access = @import("../adapters/filesystem/file_access.zig");
    const output = @import("../domain/workflow_output.zig");
    const Failing = struct {
        var calls: usize = 0;
        var fail_at: ?usize = null;
        fn replace(io: std.Io, allocator: std.mem.Allocator, parent: std.Io.Dir, name: []const u8, expected: access.Expected, bytes: []const u8) access.Error!void {
            const index = calls;
            calls += 1;
            if (fail_at == index) return error.FileUnavailable;
            return access.replace(io, allocator, parent, name, expected, bytes);
        }
    };
    const io = std.testing.io;
    const files = [_]output.File{
        .{ .target = .{ .artifact = .specification }, .bytes = "specification\n" },
        .{ .target = .{ .artifact = .reference_context }, .bytes = "reference\n" },
        .{ .target = .{ .artifact = .clarification_state }, .bytes = "state\n" },
        .{ .target = .{ .artifact = .workflow_state }, .bytes = "completion\n" },
    };
    for (0..files.len) |failure_index| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try writeFeatureInputFixture(io, project.dir);
        try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/preflight.workflow.yaml", .data = output_test_bootstrap });
        for (0..2) |run_index| {
            var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
            defer arena.deinit();
            const a = arena.allocator();
            // Fresh bootstrap and physical observations after abandoned output.
            var boot = runInProject(io, std.testing.allocator, project.dir);
            defer boot.deinit();
            try std.testing.expect(boot == .ready);
            const registry = boot.ready.roots.registry();
            const selected = try @import("../domain/feature_directory.zig").validate(a, .{ .bytes = "Chosen/Café" }, registry.featureDirectoryRoots());
            var inspector_adapter: @import("../adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
            var inspector = inspector_adapter.inspector();
            inspector.capability = registry.featureDirectoryRead();
            const observed = try inspector.inspect(a, selected);
            const paths = try @import("../domain/workflow_artifact_registry.zig").resolveFeaturePaths(a, registry.featureArtifactRoots(), selected);
            var source: @import("../adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
            var capture = source.capturer();
            capture.capability = registry.featureInputRead();
            var capture_state = source.workflowStateCapturer();
            capture_state.capability = registry.featureInputRead();
            var prepared: output.Prepared = .{ .feature = observed, .paths = paths, .prior = try capture.capture(a, observed, paths), .prior_workflow_state = .{ .captured = try capture_state.capture(a, observed, paths) }, .files = &files };
            var adapter: @import("../adapters/filesystem/workflow_output.zig").Writer(Failing.replace) = .{ .io = io, .project_root = project.dir };
            var writer = adapter.port();
            writer.capability = registry.featureOutputWrite();
            Failing.calls = 0;
            Failing.fail_at = if (run_index == 0) failure_index else null;
            if (run_index == 0) {
                prepared.prior_workflow_state = .unselected;
                try std.testing.expectError(error.InvalidWorkflowOutput, writer.publish(a, prepared));
                prepared.prior_workflow_state = .{ .captured = "foreign previous state" };
                try std.testing.expectError(error.OutputChanged, writer.publish(a, prepared));
                try std.testing.expectEqual(@as(usize, 0), Failing.calls);
                prepared.prior_workflow_state = .{ .captured = null };
                try std.testing.expectError(error.OutputWriteFailed, writer.publish(a, prepared));
                for (files, 0..) |file, index| {
                    const path = try output.path(a, paths, file.target);
                    if (index < failure_index) {
                        try std.testing.expectEqualStrings(file.bytes, try project.dir.readFileAlloc(io, path.project_relative, a, .limited(128)));
                    } else try std.testing.expectError(error.FileNotFound, project.dir.access(io, path.project_relative, .{}));
                }
            } else {
                try writer.publish(a, prepared);
                try std.testing.expectEqual(files.len, Failing.calls);
                for (files) |file| {
                    const path = try output.path(a, paths, file.target);
                    try std.testing.expectEqualStrings(file.bytes, try project.dir.readFileAlloc(io, path.project_relative, a, .limited(128)));
                }
            }
        }
    }
}

const output_test_bootstrap =
    \\schema: workflow/v1
    \\id: output-test
    \\version: 1
    \\shortcode: OUTP
    \\invoke: core.empty-invocation
    \\policy: core.capability-free@1
    \\start: run
    \\steps:
    \\  run: { use: core.noop, on: { ok: end.ok } }
;

test "feature input preparation cancellation never creates artifacts" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try writeFeatureInputFixture(io, project.dir);
    for (0..256) |checks| {
        var control: RuntimeAfterObservations = .{ .active_observations_remaining = checks, .terminal = .cancelled };
        const result = runInvocationInProjectWithRuntime(io, std.testing.allocator, project.dir, &.{ "feature-input-preflight", "--feature", "Chosen/Café", "--reference", "first" }, control.runtime(), null);
        try std.testing.expect(result.executionStatus() != null);
        try std.testing.expectError(error.FileNotFound, project.dir.openDir(io, "requirements", .{}));
        try std.testing.expectError(error.FileNotFound, project.dir.openDir(io, "engine/workflows/features", .{}));
        if (result.executionStatus().? == .ok) return;
        try std.testing.expectEqual(workflow.OutcomeTag.cancelled, result.executionStatus().?);
    }
    return error.FeatureInputsNeverCompleted;
}

test "feature input compiler requires declared read capability and predecessor data" {
    const io = std.testing.io;
    for ([_][2][]const u8{
        .{ "policy: core.feature-input-read@1", "policy: core.directory-read@1" },
        .{ "use: resolve-feature-artifact-paths", "use: core.noop" },
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
        try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, arguments).executionStatus().?);
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
        var reference_ids: @import("../adapters/system/reference_state_identity.zig").Adapter = .{ .io = io };
        native.init(std.testing.allocator, project_source.projectCapturer(), project_source.presetEnumerator(), project_source.presetCapturer(), document_parser.parser(), policy_registry, .{ .normalize_fn = @import("unicode_normalization").nfc }, reference_source.inspector(), feature_source.inspector(), feature_inputs.capturer(), @import("../adapters/parsers/clarification_inputs.zig").stateParser(), @import("../adapters/parsers/clarification_inputs.zig").formParser(), reference_contents.enumerator(), reference_contents.capturer(), markdown_reader.decoderPort(), .{ .fold_fn = @import("unicode_normalization").caseFold }, reference_ids.source(), .{ .boundary_fn = @import("unicode_normalization").lexicalBoundary });
        var boot = runInProjectWithRegistry(io, std.testing.allocator, project.dir, .{}, &native.registry);
        defer boot.deinit();
        try std.testing.expect(boot == .ready);
        var adapter: @import("../adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var inspector = adapter.inspector();
        inspector.capability = boot.ready.roots.registry().featureDirectoryRead();
        const observed = try inspector.inspect(std.testing.allocator, selected);
        try std.testing.expect(observed.observation == .directory);
        for ([_][]const u8{ "first", "second", "first" }) |reference| {
            try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "Chosen/Café", "--reference", reference }).executionStatus().?);
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
        try std.testing.expectEqual(workflow.OutcomeTag.failed, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", feature_path, "--reference", "source" }).executionStatus().?);
    }
    // On a case-insensitive filesystem, an existing alias must be rejected.
    // On a case-sensitive filesystem, the spelling is a distinct absent target.
    const alias_exists = if (project.dir.access(io, "specs/real", .{})) |_| true else |err| switch (err) {
        error.FileNotFound => false,
        else => return err,
    };
    const alias_result = runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "real/child", "--reference", "source" });
    try std.testing.expectEqual(if (alias_exists) workflow.OutcomeTag.failed else workflow.OutcomeTag.ok, alias_result.executionStatus().?);
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
    var reference_ids: @import("../adapters/system/reference_state_identity.zig").Adapter = .{ .io = io };
    native.init(std.testing.allocator, project_source.projectCapturer(), project_source.presetEnumerator(), project_source.presetCapturer(), document_parser.parser(), policy_registry, .{ .normalize_fn = @import("unicode_normalization").nfc }, reference_source.inspector(), feature_source.inspector(), feature_inputs.capturer(), @import("../adapters/parsers/clarification_inputs.zig").stateParser(), @import("../adapters/parsers/clarification_inputs.zig").formParser(), reference_contents.enumerator(), reference_contents.capturer(), markdown_reader.decoderPort(), .{ .fold_fn = @import("unicode_normalization").caseFold }, reference_ids.source(), .{ .boundary_fn = @import("unicode_normalization").lexicalBoundary });
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
        .{ "use: normalize-feature-directory", "use: normalize-reference-selector" },
        .{ "use: validate-feature-directory", "use: validate-feature-directory\n    with: { unexpected: true }" },
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
    \\invoke: core.empty-invocation
    \\policy: core.capability-free@1
    \\start: run
    \\steps:
    \\  run:
    \\    use: core.noop
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
    .operation_id = workflow.OperationId.parse("test.model").?,
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
        .invocation_operation_id = workflow.OperationId.parse("test.empty").?,
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
        try std.testing.expectEqualStrings("core.noop", graph.?.authority.steps[0].operation_id.bytes);
        try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project_root.dir, &.{"hello"}).executionStatus().?);
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
                .id = "core.empty-invocation",
                .kind = .invocation,
                .outcomes = &.{.ok},
                .side_effect = .none,
            },
            .binding = @import("../application/workflow_operation_binding.zig").bind(OperationObservation, &self.observation, invokeOperation),
        };
        self.operation_entries[1] = .{
            .contract = .{
                .id = "core.noop",
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
