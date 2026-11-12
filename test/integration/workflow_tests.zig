//! Offline workflow scenarios with temporary projects and scripted providers.
const std = @import("std");
const pipeline = @import("../../src/domain/pipeline.zig");
const config = @import("../../src/domain/config.zig");
const bootstrap_root_registry = @import("../../src/domain/bootstrap_root_registry.zig");
const toolchain_authority_source = @import("../../src/adapters/filesystem/toolchain_authority_source.zig");
const toolchain_documents = @import("../../src/adapters/parsers/toolchain_documents.zig");
const read = @import("../../src/actions/config/read_engine_config.zig");
const decode = @import("../../src/actions/config/decode_sddtoolkit_config.zig");
const workflow = @import("../../src/domain/workflow.zig");
const workflow_compilation = @import("../../src/domain/workflow_compilation.zig");
const workflow_execution = @import("../../src/domain/workflow_execution.zig");
const telemetry = @import("../../src/domain/telemetry.zig");
const request_projection = @import("../../src/test_fixtures/request_projection.zig");
const model_provider_requirement = @import("../../src/domain/model_provider_requirement.zig");
const llm_provider_identity = @import("../../src/domain/llm_provider_identity.zig");
const bootstrap_orchestrator = @import("../../src/application/bootstrap_orchestrator.zig");
const llm_provider_contracts = @import("../../src/domain/llm_provider_contracts.zig");
const llm_provider_registry = @import("../../src/domain/llm_provider_registry.zig");
const repository_model_allowlist = @import("../../src/domain/repository_model_allowlist.zig");
const toolchain = @import("../../src/domain/toolchain.zig");
const run_outcome = @import("../../src/domain/run_outcome.zig");
const workflow_engine = @import("../../src/application/workflow_engine_orchestrator.zig");
const model_provider_bootstrap_binding = @import("../../src/application/model_provider_bootstrap_binding.zig");
const model_provider_bootstrap_orchestrator = @import("../../src/application/model_provider_bootstrap_orchestrator.zig");
const model_provider_bootstrap_services = @import("../../src/application/model_provider_bootstrap_services.zig");
const llm_provider_registry_service = @import("../../src/application/llm_provider_registry_service.zig");
const core_workflow_operations = @import("../../src/composition/core_workflow_operations.zig");
const workflow_artifacts = @import("../../src/domain/workflow_artifact_registry.zig");
const log_binding = @import("../../src/domain/feature_log_binding.zig");
const log_limits = @import("../../src/domain/feature_log_limits.zig");
const feature_log_sink = @import("../../src/adapters/filesystem/feature_log_sink.zig");
const active_feature_log_runtime = @import("../../src/composition/active_feature_log_runtime.zig");
const feature_log_finalization_runner = @import("../../src/application/feature_log_finalization_runner.zig");
const model_provider_bootstrap = @import("../../src/composition/model_provider_bootstrap.zig");
const engine_invocation = @import("../../src/composition/engine_invocation.zig");
const workflow_operation_registry = @import("../../src/ports/workflow_operation_registry.zig");

const composition = @import("../../src/composition/root.zig");
const runInProjectWithRegistry = composition.runInProjectWithRegistry;
const reportInvocation = composition.reportInvocation;
const policy_registry = @import("../../src/composition/toolchain_policy_registry.zig").registry;
const untraced_allocator = @import("../../src/test_fixtures/untraced_allocator.zig");

fn runInvocationInProject(
    io: std.Io,
    allocator: std.mem.Allocator,
    project_root: std.Io.Dir,
    arguments: []const []const u8,
) run_outcome.Outcome {
    return runInvocationInProjectWithRuntime(io, allocator, project_root, arguments, .{}, null);
}

// Tests that need only the native outcome use the same production invocation.
fn runInvocationInProjectWithRuntime(io: std.Io, allocator: std.mem.Allocator, project_root: std.Io.Dir, arguments: []const []const u8, runtime: pipeline.NodeRuntime, environment: ?*const std.process.Environ.Map) run_outcome.Outcome {
    var report = reportInvocation(io, allocator, project_root, arguments, runtime, environment) catch return .{ .execution = .failed };
    defer report.deinit();
    return report.outcome;
}

// Integration-test wiring for supplied operation registries and provider probes.
fn testBootstrappedInvocation(
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

const valid_config =
    \\{
    \\  "logs": { "level": "debug", "console": false },
    \\  "workflowTokenBudget": 100000,
    \\  "temperature": 0.1,
    \\  "temperatureRunawayRetry": 1,
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
        @import("../../src/domain/telemetry.zig").CanonicalLogLevel.debug,
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
        \\  "logs": { "level": "debug", "console": false },
        \\  "workflowTokenBudget": 100000,
        \\  "temperature": 0.1,
        \\  "temperatureRunawayRetry": 1,
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
        boot.ready.config.config().temperatures(),
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
        boot.ready.config.config().temperatures(),
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
        const outcome = testBootstrappedInvocation(
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
                try std.testing.expectEqual(workflow_execution.Outcome.ok, outcome.executionStatus().?);
                try std.testing.expectEqual(@as(usize, 1), probe.observation.invocation_calls);
                try std.testing.expectEqual(@as(usize, 1), probe.observation.step_calls);
            },
            .failed => {
                try std.testing.expectEqual(
                    @import("../../src/domain/bootstrap_error.zig").PublicError.LLM_PROVIDER_CONFIG_PARSE_ERROR,
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
    const invalid = testBootstrappedInvocation(
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
        try project.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/toolchain.workflow.yaml", .data = @embedFile("../../src/test_fixtures/toolchain.workflow.yaml") });
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
        const fixture = @embedFile("../../src/test_fixtures/toolchain.workflow.yaml");
        // The no-op's outcome set is exact, so this case specifically exercises the missing
        // `valid_toolchain` input of the step after it.
        const yaml = if (missing_input)
            try std.mem.replaceOwned(u8, std.testing.allocator, fixture, "toolchain: { use: prepare-toolchain, on: { ok: end.ok, failed: end.failed } }", "toolchain: { use: core.noop, on: { ok: naming } }\n  naming: { use: compile-naming-policy, on: { ok: end.ok, failed: end.failed } }")
        else
            try std.mem.replaceOwned(u8, std.testing.allocator, fixture, "policy: core.toolchain@1", "policy: core.capability-free@1");
        defer std.testing.allocator.free(yaml);
        try project.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/toolchain.workflow.yaml", .data = yaml });
        const result = runInvocationInProject(io, std.testing.allocator, project.dir, &.{"toolchain-check"});
        try std.testing.expectEqual(@import("../../src/domain/bootstrap_error.zig").PublicError.WORKFLOW_GRAPH_COMPILE_INVALID, result.bootstrap_failed);
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
    try project_root.writeFile(io, .{ .sub_path = ".sdd/workflows/toolchain.workflow.yaml", .data = @embedFile("../../src/test_fixtures/toolchain.workflow.yaml") });
    var source = toolchain_authority_source.Adapter.init(io, project_root);
    var parser: toolchain_documents.Adapter = .{};
    var reference_adapter: @import("../../src/adapters/filesystem/reference_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project_root };
    var feature_adapter: @import("../../src/adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project_root };
    var operations: @import("../../src/composition/native_workflow_operations.zig").Assembly = undefined;
    var feature_inputs: @import("../../src/adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project_root };
    var reference_contents: @import("../../src/adapters/filesystem/reference_corpus_source.zig").Adapter = .{ .io = io, .project_root = project_root };
    var markdown_reader: @import("../../src/adapters/parsers/markdown_reference.zig").Adapter = .{ .io = io };
    var reference_ids: @import("../../src/adapters/system/reference_state_identity.zig").Adapter = .{ .io = io };
    operations.init(std.testing.allocator, source.projectCapturer(), source.presetEnumerator(), source.presetCapturer(), parser.parser(), policy_registry, .{ .normalize_fn = @import("unicode_normalization").nfc }, reference_adapter.inspector(), feature_adapter.inspector(), feature_inputs.capturer(), @import("../../src/adapters/parsers/clarification_inputs.zig").stateParser(), @import("../../src/adapters/parsers/clarification_inputs.zig").formParser(), reference_contents.enumerator(), reference_contents.capturer(), markdown_reader.decoderPort(), .{ .fold_fn = @import("unicode_normalization").caseFold }, reference_ids.source(), .{ .boundary_fn = @import("unicode_normalization").lexicalBoundary });
    operations.prepare_inputs.action.state_source = feature_inputs.workflowStateCapturer();
    var boot = runInProjectWithRegistry(io, std.testing.allocator, project_root, .{}, &operations.registry);
    defer boot.deinit();
    try std.testing.expect(boot == .ready);
    operations.bindRoots(boot.ready.roots.registry());
    operations.bindWorkflows(boot.ready.workflows.registry());
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
    const valid = try @import("../../src/application/pipeline_values.zig").read(&view, @import("../../src/application/toolchain_workflow_values.zig").valid, @import("../../src/domain/toolchain_safety.zig").ValidToolchain);
    const service = @import("../../src/application/toolchain_service.zig").ToolChainService.init(valid);
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
    try project.writeFile(io, .{ .sub_path = ".sdd/workflows/preflight.workflow.yaml", .data = @embedFile("../../src/test_fixtures/reference-preflight.workflow.yaml") });
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
    const changed = try std.mem.replaceOwned(u8, std.testing.allocator, @embedFile("../../src/test_fixtures/reference-preflight.workflow.yaml"), "id: reference-preflight", "id: documentation-check");
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
    var adapter: @import("../../src/adapters/filesystem/reference_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
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

test "reference compiler rejects a read capability the policy denies" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try writeReferencePreflightFixture(io, project.dir);
    const original = @embedFile("../../src/test_fixtures/reference-preflight.workflow.yaml");
    const changed = try std.mem.replaceOwned(u8, std.testing.allocator, original, "policy: core.feature-input-read@1", "policy: core.capability-free@1");
    defer std.testing.allocator.free(changed);
    try project.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/preflight.workflow.yaml", .data = changed });
    const result = runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "Hello/日本語", "--reference", "anything" });
    try std.testing.expect(result == .bootstrap_failed);
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
    try project.writeFile(io, .{ .sub_path = "engine/workflows/preflight.workflow.yaml", .data = @embedFile("../../src/test_fixtures/reference-ingestion.workflow.yaml") });
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
    const yaml = try @import("../../src/test_fixtures/path_token_workflow.zig").yaml(std.testing.allocator);
    defer std.testing.allocator.free(yaml);
    const renamed = try std.mem.replaceOwned(u8, std.testing.allocator, yaml, "id: reference-ingestion", "id: lexical-check");
    defer std.testing.allocator.free(renamed);
    try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/preflight.workflow.yaml", .data = renamed });
    try project.dir.createDirPath(io, ".sdd/principles");
    try project.dir.createDirPath(io, ".sdd/presets");
    try project.dir.writeFile(io, .{ .sub_path = ".sdd/principles/toolchain.yaml", .data = "schema: project-toolchain/v1\npresets: []\npolicies: [project.zig@1]\n" });
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const closed = try @import("../../src/test_fixtures/clarification_inputs.zig").closed(arena.allocator(), "S01", true);
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
        .{ "use: prepare-reference-tokens", "use: core.noop" },
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
    const renamed = try std.mem.replaceOwned(u8, std.testing.allocator, @embedFile("../../src/test_fixtures/reference-ingestion.workflow.yaml"), "id: reference-ingestion", "id: document-evidence");
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
        const clarifications = try @import("../../src/test_fixtures/clarification_inputs.zig").closed(allocator, "S01", true);
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
    const ingestion = @import("../../src/domain/reference_ingestion.zig");
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
        var inspector_adapter: @import("../../src/adapters/filesystem/reference_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var inspector = inspector_adapter.inspector();
        inspector.capability = registry.referenceSources();
        const selected = try inspector.inspect(allocator, .{ .bytes = "chosen" });
        var adapter: @import("../../src/adapters/filesystem/reference_corpus_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var enumerator = adapter.enumerator();
        try std.testing.expectError(error.ReferenceUnavailable, enumerator.enumerate(allocator, selected));
        enumerator.capability = registry.referenceContentRead();
        const evidence_steps = @import("../../src/actions/reference/prepare_reference_evidence.zig").steps;
        const inventory = try evidence_steps.validateInventory(
            .{ .normalize_fn = @import("unicode_normalization").nfc },
            .{ .fold_fn = @import("unicode_normalization").caseFold },
            allocator,
            try enumerator.enumerate(allocator, selected),
        );
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
                var decoder: @import("../../src/adapters/parsers/markdown_reference.zig").Adapter = .{ .io = io };
                const decoded = try evidence_steps.decodeMarkdown(decoder.decoderPort(), allocator, captured);
                const result: ingestion.Inputs = try evidence_steps.validateAccounting(allocator, decoded);
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
        .{ "use: prepare-inputs", "use: core.noop" },
        .{ "use: prepare-reference-evidence", "use: validate-source-citations" },
        .{ "use: prepare-reference-evidence", "use: parse-reference-extraction-results" },
        .{ "use: prepare-reference-evidence", "use: prepare-reference-tokens" },
        .{ "use: prepare-reference-evidence", "use: validate-reference-extraction-text" },
        .{ "use: prepare-reference-evidence", "use: validate-reference-selections" },
        .{ "use: prepare-reference-evidence", "use: assign-preserved-token-identities" },
        .{ "use: prepare-reference-evidence", "use: build-preserved-token-claims" },
        .{ "use: prepare-reference-evidence", "use: validate-reference-claims" },
        .{ "use: prepare-reference-evidence", "use: assign-reference-claim-identities" },
        .{ "use: prepare-reference-evidence", "use: build-reference-extraction-ledger" },
        .{ "use: prepare-reference-evidence", "use: validate-reference-extraction-accounting" },
        .{ "use: prepare-reference-evidence", "use: prepare-reference-evidence\n    with: { state-id: invented }" },
    }) |edit| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try writeReferenceIngestionFixture(io, project.dir);
        const changed = try std.mem.replaceOwned(u8, std.testing.allocator, @embedFile("../../src/test_fixtures/reference-ingestion.workflow.yaml"), edit[0], edit[1]);
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
    const bindings = @import("../../src/application/reference_evidence_workflow.zig");
    const evidence = @import("../../src/domain/reference_evidence.zig");
    const values = @import("../../src/application/pipeline_values.zig");
    fn propose(context: ?*@This(), input: workflow_operation_registry.Input) workflow_operation_registry.Error!workflow_execution.Candidate {
        const source = values.read(&input.step.data, bindings.inputs_schema, evidence.Inputs) catch return error.OperationExecutionFailed;
        const chunk = source.chunks.entries[0];
        const proposal: evidence.CitationProposal = .{
            .source_id = chunk.source_id,
            .block_id = chunk.block_id,
            .location = chunk.span,
            .verbatim = if (context.?.invalid) "not in the source" else null,
        };
        return @import("../../src/application/workflow_candidate.zig").publish(std.testing.allocator, bindings.proposals_schema, evidence.CitationProposals, .{
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
    const bindings = @import("../../src/application/reference_extraction_workflow.zig");
    const extraction = @import("../../src/domain/reference_extraction.zig");
    const owned = @import("../../src/domain/reference_candidate_value.zig");
    fn propose(context: ?*@This(), input: workflow_operation_registry.Input) workflow_operation_registry.Error!workflow_execution.Candidate {
        const allocator = std.testing.allocator;
        const source = ReferenceCitationTestProducer.values.read(&input.step.data, ReferenceCitationTestProducer.bindings.inputs_schema, ReferenceCitationTestProducer.evidence.Inputs) catch return error.OperationExecutionFailed;
        var arena: std.heap.ArenaAllocator = .init(allocator);
        defer arena.deinit();
        const scratch = arena.allocator();
        const entries = scratch.alloc(extraction.RawResult, if (context.?.mode == .missing) 0 else source.chunks.entries.len) catch return error.OperationExecutionFailed;
        for (entries, 0..) |*entry, index| {
            const chunk = source.chunks.entries[if (context.?.mode == .duplicate) 0 else index];
            entry.* = .{
                .scope = .{ .state_id = source.corpus.state_id, .chunk_id = chunk.id },
                .result = switch (context.?.mode) {
                    .blocked => .{ .blocked = .extraction_failed },
                    .malformed => .{ .response = "{\"kind\":\"claims\",\"claim_id\":1}" },
                    .no_claim => .{ .response = @import("../../src/reference_extraction_test.zig").no_claim },
                    // Claim wording is quoted from the source (ADR 0036); the reason is model text.
                    .unbound => .{ .response = "{\"kind\":\"no_feature_claim\",\"reason\":{\"nodes\":\"Read src/main.zig.\"},\"token_classifications\":[]}" },
                    .passive, .unknown_literal => response: {
                        const registry = ReferenceCitationTestProducer.values.read(&input.step.data, @import("../../src/application/passive_literal_workflow.zig").registry_schema, @import("../../src/domain/passive_literals.zig").Registry) catch return error.OperationExecutionFailed;
                        var ordinal: u32 = if (context.?.mode == .unknown_literal) std.math.maxInt(u32) else 0;
                        if (context.?.mode == .passive) for (registry.occurrences) |occurrence| {
                            if (occurrence.origin.source_id.ordinal == chunk.source_id.ordinal and occurrence.origin.block_id.ordinal == chunk.block_id.ordinal) {
                                ordinal = occurrence.id.ordinal;
                                break;
                            }
                        };
                        break :response .{ .response = @import("../../src/reference_extraction_test.zig").passiveReply(scratch, ordinal) catch return error.OperationExecutionFailed };
                    },
                    .legacy => .{ .response = "{\"kind\":\"no_feature_claim\",\"reason\":\"Old raw text\",\"token_classifications\":[]}" },
                    .preserved, .missing_classification, .positive_empty_preserved, .irrelevant => response: {
                        const token_values = @import("../../src/application/structured_token_workflow.zig");
                        const token_fixture = @import("../../src/test_fixtures/reference_tokens.zig");
                        const candidates = ReferenceCitationTestProducer.values.read(&input.step.data, token_values.candidates_schema, extraction.tokens.Candidates) catch return error.OperationExecutionFailed;
                        const choices = token_fixture.classifications(scratch, candidates.*, chunk) catch return error.OperationExecutionFailed;
                        const decisions = scratch.dupe(extraction.tokens.Classification, choices) catch return error.OperationExecutionFailed;
                        if (context.?.mode == .irrelevant) for (decisions) |*decision| {
                            decision.* = .{ .irrelevant = decision.id() };
                        };
                        const body = if (context.?.mode == .positive_empty_preserved or context.?.mode == .irrelevant) @import("../../src/reference_extraction_test.zig").no_claim else @import("../../src/reference_extraction_test.zig").reply(scratch, source.*, chunk) catch return error.OperationExecutionFailed;
                        break :response .{ .response = token_fixture.wire(scratch, body, if (context.?.mode == .missing_classification) &.{} else decisions) catch return error.OperationExecutionFailed };
                    },
                    // A citation outside the supplied lines bypasses admission here.
                    .invalid_citation => .{ .response = "{\"kind\":\"claims\",\"claims\":[{\"category\":\"business\",\"citations\":[999]}],\"token_classifications\":[]}" },
                    .claims, .missing, .duplicate, .reconciled, .conflict, .bad_reconciliation => .{ .response = @import("../../src/reference_extraction_test.zig").reply(scratch, source.*, chunk) catch return error.OperationExecutionFailed },
                },
            };
            switch (context.?.mode) {
                .claims, .no_claim, .passive, .invalid_citation, .duplicate => {
                    const token_fixture = @import("../../src/test_fixtures/reference_tokens.zig");
                    const candidates = ReferenceCitationTestProducer.values.read(&input.step.data, @import("../../src/application/structured_token_workflow.zig").candidates_schema, extraction.tokens.Candidates) catch return error.OperationExecutionFailed;
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
    const native = @import("../../src/application/reference_reconciliation_workflow.zig");
    const fixture = @import("../../src/test_fixtures/reference_reconciliation.zig");
    const prior = @import("../../src/application/reference_extraction_workflow.zig");
    fn propose(context: ?*@This(), input: workflow_operation_registry.Input) workflow_operation_registry.Error!workflow_execution.Candidate {
        const allocator = std.testing.allocator;
        const current = try prior.read(&input.step.data, native.input_schema, .reconciliation_input);
        const packet = current.payload().reconciliation_input;
        const owner = @import("../../src/domain/reference_candidate_value.zig").create(allocator, current) catch return error.OperationExecutionFailed;
        errdefer @import("../../src/domain/reference_candidate_value.zig").destroy(owner);
        const scratch = owner.arena.allocator();
        const proposal: @FieldType(fixture.r.Parsed, "proposal") = if (packet.purpose == .summary)
            .{ .summary = fixture.summary(scratch, packet) catch return error.OperationExecutionFailed }
        else final: {
            var value = if (context.?.mode == .conflict) @import("../../src/reference_reconciliation_test.zig").conflicting(scratch, packet) catch return error.OperationExecutionFailed else fixture.global(scratch, packet) catch return error.OperationExecutionFailed;
            if (context.?.mode == .bad_reconciliation) value.claim_dispositions = value.claim_dispositions[1..];
            break :final .{ .global = value };
        };
        owner.payload = .{ .reconciliation_parsed = .{ .input = packet, .proposal = proposal } };
        return prior.publish(allocator, native.parsed_schema, owner, .ok);
    }
    fn observe(context: ?*@This(), input: workflow_operation_registry.Input) workflow_operation_registry.Error!workflow_execution.Candidate {
        const result = try prior.read(&input.step.data, native.accounted_schema, .reconciliation_accounted);
        if (result.payload().reconciliation_accounted.outcome != .complete) return error.OperationExecutionFailed;
        const authority = @import("../../src/application/required_authority_workflow.zig");
        const ledger = @import("../../src/application/required_authority_values.zig").read(&input.step.data, authority.ledger_schema, .ledger) catch return error.OperationExecutionFailed;
        if (ledger.requirements.len < 3 or ledger.inputs.projection != .source_readiness or ledger.inputs.evidence.len != 0) return error.OperationExecutionFailed;
        if (!ledger.inputs.references.?.items.state_id.eql(result.payload().reconciliation_accounted.records.assignments.checked.prior.prior.input.progress.plan.layout.items.state_id)) return error.OperationExecutionFailed;
        context.?.observed += 1;
        return .{ .outcome = .ok, .delta = .{} };
    }
};

test "native YAML validates citations extraction and reconciliation before continuation" {
    const io = std.testing.io;
    const binding = @import("../../src/application/workflow_operation_binding.zig");
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
        if (mode == .passive) try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = "Read stories.md.\n" });
        if (mode == .preserved or mode == .missing_classification or mode == .positive_empty_preserved or mode == .irrelevant) try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = "Display `Hello, World!` and retain `Cafe\u{301}`.\n" });
        const suffix = if (mode != null) "use: prepare-reference-tokens, on: { ok: propose-extraction, failed: end.failed } }\n" ++
            "  propose-extraction: { use: test.propose-extraction, on: { ok: parse-extraction } }\n" ++
            "  parse-extraction: { use: parse-reference-extraction-results, on: { ok: validate-text, failed: end.failed } }\n" ++
            "  validate-text: { use: validate-reference-extraction-text, on: { ok: validate-classifications, invalid: end.invalid, failed: end.failed } }\n" ++
            "  validate-classifications: { use: validate-reference-selections, on: { ok: assign-tokens, invalid: end.invalid, failed: end.failed } }\n" ++
            "  assign-tokens: { use: assign-preserved-token-identities, on: { ok: build-token-claims, failed: end.failed } }\n" ++
            "  build-token-claims: { use: build-preserved-token-claims, on: { ok: validate-claims, failed: end.failed } }\n" ++
            "  validate-claims: { use: validate-reference-claims, on: { ok: assign-claims, failed: end.failed } }\n" ++
            "  assign-claims: { use: assign-reference-claim-identities, on: { ok: build-ledger, failed: end.failed } }\n" ++
            "  build-ledger: { use: build-reference-extraction-ledger, on: { ok: account-extraction, failed: end.failed } }\n" ++
            "  account-extraction: { use: validate-reference-extraction-accounting, on: { ok: observe-extraction, blocked: end.blocked, failed: end.failed } }\n" ++
            "  observe-extraction: { use: test.observe-extraction, on: { ok: end.ok } }" else "use: prepare-reference-evidence\n    on: { ok: propose-citations, failed: end.failed }\n" ++
            "  propose-citations: { use: test.propose-citations, on: { ok: validate-citations } }\n" ++
            "  validate-citations: { use: validate-source-citations, on: { ok: observe-citations, failed: end.failed } }\n" ++
            "  observe-citations: { use: test.observe-citations, on: { ok: end.ok } }";
        const preparation = try @import("../../src/test_fixtures/path_token_workflow.zig").prepared(std.testing.allocator);
        defer std.testing.allocator.free(preparation);
        const yaml = try std.mem.replaceOwned(u8, std.testing.allocator, if (mode != null) preparation else @embedFile("../../src/test_fixtures/reference-ingestion.workflow.yaml"), if (mode != null) "use: prepare-reference-tokens, on: { ok: end.ok, failed: end.failed } }" else "use: prepare-reference-evidence\n    on: { ok: end.ok, failed: end.failed }", suffix);
        defer std.testing.allocator.free(yaml);
        const reconciliation_suffix = try @import("../../src/test_fixtures/reference_reconciliation_workflow.zig").suffix(std.testing.allocator, 3);
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
        var reference_source: @import("../../src/adapters/filesystem/reference_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var feature_source: @import("../../src/adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var feature_inputs: @import("../../src/adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var reference_contents: @import("../../src/adapters/filesystem/reference_corpus_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var markdown_reader: @import("../../src/adapters/parsers/markdown_reference.zig").Adapter = .{ .io = io };
        var reference_ids: @import("../../src/adapters/system/reference_state_identity.zig").Adapter = .{ .io = io };
        var native: @import("../../src/composition/native_workflow_operations.zig").Assembly = undefined;
        native.init(std.testing.allocator, project_source.projectCapturer(), project_source.presetEnumerator(), project_source.presetCapturer(), document_parser.parser(), policy_registry, .{ .normalize_fn = @import("unicode_normalization").nfc }, reference_source.inspector(), feature_source.inspector(), feature_inputs.capturer(), @import("../../src/adapters/parsers/clarification_inputs.zig").stateParser(), @import("../../src/adapters/parsers/clarification_inputs.zig").formParser(), reference_contents.enumerator(), reference_contents.capturer(), markdown_reader.decoderPort(), .{ .fold_fn = @import("unicode_normalization").caseFold }, reference_ids.source(), .{ .boundary_fn = @import("unicode_normalization").lexicalBoundary });
        native.prepare_inputs.action.state_source = feature_inputs.workflowStateCapturer();
        var producer: ReferenceCitationTestProducer = .{ .invalid = invalid };
        var extraction_producer: ReferenceExtractionTestProducer = .{ .mode = mode orelse .claims };
        var reconciliation_producer: ReferenceReconciliationTestProducer = .{ .mode = mode orelse .claims };
        var protected_arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer protected_arena.deinit();
        const closed = try @import("../../src/test_fixtures/clarification_inputs.zig").closed(protected_arena.allocator(), "S01", true);
        try writeClarificationCapture(io, project.dir, closed);
        const entries = native.entries ++ [_]workflow_operation_registry.Entry{
            .{ .contract = .{ .id = "test.propose-citations", .kind = .step, .requires = &.{.citable_reference_inputs}, .produces = &.{.reference_citation_proposals}, .outcomes = &.{.ok}, .side_effect = .none }, .binding = binding.bind(ReferenceCitationTestProducer, &producer, ReferenceCitationTestProducer.propose) },
            .{ .contract = .{ .id = "test.observe-citations", .kind = .step, .requires = &.{.validated_source_citations}, .outcomes = &.{.ok}, .side_effect = .none }, .binding = binding.bind(ReferenceCitationTestProducer, &producer, ReferenceCitationTestProducer.observe) },
            .{ .contract = .{ .id = "test.propose-extraction", .kind = .step, .requires = &.{ .citable_reference_inputs, .reference_passive_literals, .structured_token_candidates }, .produces = &.{.raw_reference_extraction}, .outcomes = &.{.ok}, .side_effect = .none }, .binding = binding.bind(ReferenceExtractionTestProducer, &extraction_producer, ReferenceExtractionTestProducer.propose) },
            .{ .contract = .{ .id = "test.observe-extraction", .kind = .step, .requires = &.{.accounted_reference_extraction}, .outcomes = &.{.ok}, .side_effect = .none }, .binding = binding.bind(ReferenceExtractionTestProducer, &extraction_producer, ReferenceExtractionTestProducer.observe) },
            .{ .contract = .{ .id = "test.propose-reconciliation", .kind = .step, .requires = &.{.reference_reconciliation_input}, .produces = &.{.parsed_reference_reconciliation}, .outcomes = &.{.ok}, .side_effect = .none }, .binding = binding.bind(ReferenceReconciliationTestProducer, &reconciliation_producer, ReferenceReconciliationTestProducer.propose) },
            .{ .contract = .{ .id = "test.observe-reconciliation", .kind = .step, .requires = &.{ .accounted_reference_reconciliation, .required_authority_ledger }, .outcomes = &.{.ok}, .side_effect = .none }, .binding = binding.bind(ReferenceReconciliationTestProducer, &reconciliation_producer, ReferenceReconciliationTestProducer.observe) },
        };
        native.registry.operations = &entries;
        var boot = runInProjectWithRegistry(io, std.testing.allocator, project.dir, .{}, &native.registry);
        defer boot.deinit();
        try std.testing.expect(boot == .ready);
        native.bindRoots(boot.ready.roots.registry());
        native.bindWorkflows(boot.ready.workflows.registry());
        var principle_source: @import("../../src/adapters/filesystem/principle_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
        native.bindConfiguration(boot.ready.config.config());
        native.bindPrinciples(boot.ready.roots.registry().projectPrinciples(), principle_source.reader(), principle_source.enumerator(), principle_source.capturer());
        var providers = model_provider_bootstrap.Assembly.init(io, std.testing.allocator, project.dir, .{}, &llm_provider_contracts.Registry.empty);
        const result = testBootstrappedInvocation(std.testing.allocator, &boot, &.{ "reference-ingestion", "--feature", "Chosen/Café", "--reference", "first" }, &native.registry, providers.bind(), .{});
        const expected: workflow.OutcomeTag = if (mode) |selected| switch (selected) {
            .claims, .no_claim, .passive, .preserved, .irrelevant, .reconciled => .ok,
            .blocked, .conflict => .blocked,
            .missing_classification, .positive_empty_preserved, .bad_reconciliation, .unbound, .unknown_literal => .invalid,
            // Admission restricts citations to supplied lines, so an unknown one is a defect.
            .malformed, .missing, .duplicate, .legacy, .invalid_citation => .failed,
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
    try testSpecificationWorkflows(.existing);
}

test "request projection records every provider invocation, keyed and deterministic" {
    try untraced_allocator.run(checkRequestProjection, .{});
}

test "an outcome link request is projected as a closed choice with its own prompt, once per pending edge case" {
    try untraced_allocator.run(checkLinkProjection, .{});
}

fn checkLinkProjection(allocator: std.mem.Allocator) !void {
    const io = std.testing.io;
    var freeze = std.testing.tmpDir(.{});
    defer freeze.cleanup();
    var sink: request_projection.Sink = .{ .allocator = allocator, .io = io, .root = freeze.dir };
    defer sink.entries.deinit(allocator);
    try runSpecificationWorkflows(allocator, .scenario_links, &sink);
    // The first scenario links natively and asks nothing. The second asks once per pending edge
    // case, after every other request of its run, and each request offers its own edge case.
    const native = sink.entries.items[0].scenario;
    var calls: usize = 0;
    for (sink.entries.items) |entry| calls += @intFromBool(entry.scenario == native + 1);
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const prompt = try std.Io.Dir.cwd().readFileAlloc(io, "design/workflows/spec/links.prompt.md", a, .limited(1_048_576));
    var asked: usize = 0;
    var bodies: std.ArrayList([]const u8) = .empty;
    for (1..calls + 1) |call| {
        const path = try std.fmt.allocPrint(a, "scenario_links/scenario-{d:0>3}/call-{d:0>4}.json", .{ native + 1, call });
        const projection = try request_projection.Projection.decode(a, try freeze.dir.readFileAlloc(io, path, a, .limited(16 * 1024 * 1024)));
        const schema = (try std.json.parseFromSlice(std.json.Value, a, projection.schema, .{})).value;
        const properties = if (schema == .object) schema.object.get("properties") else null;
        const criterion = if (properties) |members| members.object.get("criterion") else null;
        if (criterion == null) {
            // Every link request follows every other request of the run.
            try std.testing.expectEqual(@as(usize, 0), asked);
            continue;
        }
        asked += 1;
        const offered = criterion.?.object.get("enum").?.array.items;
        try std.testing.expectEqual(@as(usize, 2), offered.len);
        try std.testing.expectEqual(@as(i64, 1), offered[0].integer);
        try std.testing.expectEqual(@as(i64, 2), offered[1].integer);
        var found_prompt = false;
        var body: ?[]const u8 = null;
        for (projection.content) |part| {
            found_prompt = found_prompt or std.mem.eql(u8, part.bytes(), prompt);
            if (std.mem.indexOf(u8, part.bytes(), "acceptance_criteria") != null) body = part.bytes();
        }
        try std.testing.expect(found_prompt);
        for (bodies.items) |earlier| try std.testing.expect(!std.mem.eql(u8, earlier, body.?));
        try bodies.append(a, body.?);
    }
    try std.testing.expect(asked >= 2);
}

fn checkRequestProjection(allocator: std.mem.Allocator) !void {
    const io = std.testing.io;
    var freeze = std.testing.tmpDir(.{});
    defer freeze.cleanup();
    var first: request_projection.Sink = .{ .allocator = allocator, .io = io, .root = freeze.dir };
    defer first.entries.deinit(allocator);
    var second: request_projection.Sink = .{ .allocator = allocator, .io = io };
    defer second.deinit();
    try runSpecificationWorkflows(allocator, .source_preservation, &first);
    try runSpecificationWorkflows(allocator, .source_preservation, &second);
    // The same scenarios project byte-identical requests.
    try std.testing.expect(first.entries.items.len != 0);
    try std.testing.expectEqualDeep(first.entries.items, second.entries.items);
    // Each invocation is keyed by its call order within its scenario.
    for (first.entries.items, 0..) |entry, index| try std.testing.expectEqual(if (index != 0 and first.entries.items[index - 1].scenario == entry.scenario) first.entries.items[index - 1].call + 1 else 1, entry.call);
    // Extraction, reconciliation, generation, repair and review are all projected.
    const Kind = struct { owner: std.meta.Tag(@import("../../src/domain/model_request_identity.zig").ImmutableUnitOwnerId), purpose: @import("../../src/domain/model_request_identity.zig").RequestPurposeKind };
    for ([_]Kind{
        .{ .owner = .reference_chunk, .purpose = .initial_generation },
        .{ .owner = .reference_global, .purpose = .initial_generation },
        .{ .owner = .specification_unit, .purpose = .initial_generation },
        .{ .owner = .semantic_review, .purpose = .semantic_review },
    }) |kind| {
        const found = for (first.entries.items) |entry| {
            if (entry.owner == kind.owner and entry.purpose == kind.purpose) break true;
        } else false;
        if (!found) std.debug.print("request projection lacks {s}/{s}\n", .{ @tagName(kind.owner), @tagName(kind.purpose) });
        try std.testing.expect(found);
    }
    const repaired = for (first.entries.items) |entry| {
        if (entry.purpose == .atomic_repair) break true;
    } else false;
    try std.testing.expect(repaired);
    // Each reconciliation phase (dispositions, signals, conflicts) is its own global
    // unit, whose first request opens its ordinals.
    var phases: usize = 0;
    for (first.entries.items) |entry| {
        if (entry.scenario == first.entries.items[0].scenario and entry.owner == .reference_global and entry.purpose == .initial_generation and entry.request == 1 and entry.attempt == 1) phases += 1;
    }
    try std.testing.expect(phases >= 3);
    // A written projection keeps the request's model-visible members and omits the
    // three that refactors change by design.
    const entry = first.entries.items[0];
    const path = try std.fmt.allocPrint(allocator, "source_preservation/scenario-{d:0>3}/call-{d:0>4}.json", .{ entry.scenario, entry.call });
    defer allocator.free(path);
    const bytes = try freeze.dir.readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024));
    defer allocator.free(bytes);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    try std.testing.expectEqualSlices(u8, &entry.digest, &digest);
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const projection = try request_projection.Projection.decode(arena.allocator(), bytes);
    try std.testing.expect(projection.content.len != 0 and projection.protocol_prompt.len != 0 and projection.schema.len != 0);
    // An omitted member is unknown to the closed projection.
    const versioned = try std.mem.concat(arena.allocator(), u8, &.{ "{\"version\":\"model-request-debug/v13\",", bytes[1..] });
    try std.testing.expectError(error.InvalidJsonDocument, request_projection.Projection.decode(arena.allocator(), versioned));
    // The manifest counts what the freeze holds, so an empty or partial freeze never
    // diffs clean.
    try first.writeManifest(freeze.dir);
    const manifest_bytes = try freeze.dir.readFileAlloc(io, "manifest.json", allocator, .limited(4096));
    defer allocator.free(manifest_bytes);
    const manifest = try request_projection.Manifest.decode(arena.allocator(), manifest_bytes);
    var scenarios: usize = 0;
    for (first.entries.items, 0..) |item, index| scenarios += @intFromBool(index == 0 or first.entries.items[index - 1].scenario != item.scenario);
    try std.testing.expectEqual(@as(usize, 1), manifest.groups);
    try std.testing.expectEqual(scenarios, manifest.scenarios);
    try std.testing.expectEqual(first.entries.items.len, manifest.calls);
}

test "configured source preservation reviews before generation and repairs through the shared model slot" {
    try testSpecificationWorkflows(.source_preservation);
}

test "configured native summary reuse advances a fresh validated plan after pre-generation source repair" {
    try testSpecificationWorkflows(.reuse_regeneration);
}

test "an edge case links natively, by one closed model choice, or blocks the run when no criterion of its batch can serve it" {
    try testSpecificationWorkflows(.scenario_links);
}

const step_trace = @import("../../src/test_fixtures/workflow_step_trace.zig");

/// Records one scenario's step trace and totals beneath `.zig-cache` as
/// structural-equivalence evidence (ADR 0030 "Freeze first"); nothing asserts it.
fn writeStepTrace(io: std.Io, allocator: std.mem.Allocator, project: std.Io.Dir, case: []const u8, scenario: usize, trace: *step_trace.Trace, driver: *const @import("../../src/test_fixtures/spec_generation_driver.zig").Driver, runner: *@import("../../src/application/workflow_pipeline_runner.zig").Runner, result: @import("../../src/domain/run_outcome.zig").Outcome) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ledger = runner.tokenLedger();
    var rejection: std.Io.Writer.Allocating = .init(a);
    const rejected: ?[]const u8 = if (result == .execution_rejected) written: {
        step_trace.writeRejection(&rejection.writer, result.execution_rejected) catch return error.OutOfMemory;
        break :written rejection.written();
    } else null;
    const requests = try a.alloc(step_trace.RequestAttempt, ledger.accounted_operations.items.len);
    for (requests, ledger.accounted_operations.items) |*request, accounted| {
        const id = accounted.id.model_request_id;
        var site: std.Io.Writer.Allocating = .init(a);
        for (runner.selected.graph.authority.steps) |*step| if (std.mem.eql(u8, step.id.bytes, id.model_operation_id.workflow_step_id.bytes)) {
            step_trace.writeCallSite(&site.writer, step) catch |err| return switch (err) {
                error.WriteFailed => error.OutOfMemory,
                error.UnwrappedRequestLifecycle => error.UnwrappedRequestLifecycle,
            };
            break;
        };
        request.* = .{
            .call_site = site.written(),
            .purpose = @tagName(id.purpose),
            .request = id.request_ordinal.value,
            .attempt = accounted.id.model_attempt_ordinal.value,
            .reconciliation = @tagName(accounted.reconciliation),
        };
    }
    const identity = try stateId(runner);
    var observed: std.ArrayList(step_trace.File) = .empty;
    for ([_][]const u8{ "requirements", "engine/workflows/features" }) |root| try observed.appendSlice(a, try step_trace.files(io, a, project, root, identity));
    try step_trace.write(io, a, trace, .{
        .workflow = "spec-generation",
        .case = case,
        .scenario = scenario,
        .outcome = if (result.executionStatus()) |status| @tagName(status) else @tagName(result),
        .rejection = rejected,
        .steps = trace.steps,
        .trace_sha256 = try step_trace.hash(a, trace.written()),
        .model_invocations = driver.fake.invocation_call_count,
        .driver_calls = driver.calls,
        .accounted_operations = ledger.accounted_operations.items.len,
        .committed_tokens = ledger.committed(),
        .requests = requests,
        .files = try step_trace.hashed(a, observed.items),
    }, observed.items);
}

/// The run's random reference state ID, which rendered views cite.
fn stateId(runner: *@import("../../src/application/workflow_pipeline_runner.zig").Runner) !?[]const u8 {
    const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
    if (!view.contains(.citable_reference_inputs)) return null;
    const inputs = try @import("../../src/application/pipeline_values.zig").read(&view, @import("../../src/application/reference_evidence_workflow.zig").inputs_schema, @import("../../src/domain/reference_evidence.zig").Inputs);
    return inputs.corpus.state_id.bytes;
}

const SpecificationCases = enum { existing, source_preservation, reuse_regeneration, scenario_links };
/// The applicability sources' level-1 title heading (ADR 0048).
const applicability_heading = "# Required output\n";

// Every scenario allocates through one leak-checked untraced allocator; the
// sweep's allocations would otherwise each pay for a stack trace.
fn testSpecificationWorkflows(workflow_cases: SpecificationCases) !void {
    return untraced_allocator.run(runSpecificationWorkflows, .{ workflow_cases, null });
}

/// `projection` collects the request projection; without one, a sink
/// that writes a freeze only when the environment names one.
fn runSpecificationWorkflows(allocator: std.mem.Allocator, workflow_cases: SpecificationCases, projection: ?*request_projection.Sink) !void {
    const io = std.testing.io;
    var environment_sink: ?request_projection.Sink = if (projection == null) try request_projection.Sink.fromEnvironment(allocator, io) else null;
    defer if (environment_sink) |*sink| sink.deinit();
    const sink = projection orelse &environment_sink.?;
    // Each case group writes its own subdirectory, so groups sharing a freeze never
    // overwrite each other's scenario numbers.
    sink.group = @tagName(workflow_cases);
    const faults = [_]@import("../../src/test_fixtures/spec_generation_driver.zig").Fault{
        .{ .stage = .generation, .shape = .inconclusive },
        .{ .stage = .extraction, .shape = .alternating_missing, .repetition = .{ .every_request = 2 } },
        .{ .stage = .reconciliation, .shape = .missing_answer },
        .{ .stage = .generation, .shape = .missing_answer },
        .{ .stage = .repair, .shape = .missing_answer },
        .{ .stage = .repair, .shape = .missing_answer, .repetition = .persistent },
        .{ .stage = .repair, .shape = .missing_answer, .repetition = .{ .recover_then_exhaust = 2 } },
        .{ .stage = .extraction, .shape = .empty },
        .{ .stage = .reconciliation, .shape = .empty },
        .{ .stage = .generation, .shape = .empty },
        .{ .stage = .repair, .shape = .empty },
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
        // ADR 0038 Decision 3: a batch whose requirement claims no scenario names is
        // admitted, and the engine inserts one criterion per uncovered claim, whose claim it
        // fixes; the run publishes with no correction, in one batch or in every batch.
        .{ .stage = .records, .shape = .uncovered_scenario, .repetition = .{ .first_request = 1 } },
        .{ .stage = .records, .shape = .uncovered_scenario, .repetition = .{ .every_request = 1 } },
        // ADR 0038 Decision 5: a wholly taken statement is deleted natively and publishes
        // with no correction. Every scripted records batch has one claim, so a partly
        // taken one is proven at response admission instead.
        .{ .stage = .records, .shape = .shared_statement, .repetition = .{ .first_request = 1 } },
        // The same holds for a wholly taken statement whose text is only the exact value
        // another record holds: its text defect is no defect of the response.
        .{ .stage = .records, .shape = .bare_statement, .repetition = .{ .every_request = 1 } },
        // ADR 0035: a record that repeats another's content, groups and evidence is a
        // duplicate; it is deleted natively and the run publishes with no correction.
        .{ .stage = .records, .shape = .duplicate_record, .repetition = .{ .first_request = 1 } },
        // ADR 0039: a records runaway is re-sent once; a re-send that runs away
        // fails typed, and a re-sent response takes the same admission and validation,
        // here an uncovered claim's criterion insert.
        .{ .stage = .records, .shape = .runaway, .repetition = .{ .first_request = 1 } },
        .{ .stage = .records, .shape = .runaway, .repetition = .persistent },
        .{ .stage = .records, .shape = .runaway_uncovered, .repetition = .{ .first_request = 2 } },
    };
    const classification_repair_start = 14 + faults.len;
    const reconciliation_start = classification_repair_start + 3;
    const reconciliation_faults = std.meta.tags(@import("../../src/test_fixtures/spec_generation_responses.zig").ReconciliationFault);
    const repeated_start = reconciliation_start + reconciliation_faults.len;
    const protocol_text_start = repeated_start + 2;
    const protocol_selection_scenario = protocol_text_start + 2;
    const protocol_content_start = protocol_selection_scenario + 1;
    const omission_scenario = protocol_content_start + 2;
    const extraction_omission_start = omission_scenario + 3;
    const source_gap_start = extraction_omission_start + 2;
    const evidence_start = source_gap_start + 2;
    const disposition_start = evidence_start + 3;
    const source_repair_start = disposition_start + 4;
    const source_losses = std.meta.tags(@import("../../src/test_fixtures/spec_generation_responses.zig").SourceLoss);
    // Appended `.empty` cases: one keeps a finer extraction composition selector;
    // each later one adds one preservation-comparison membership fault.
    const loss_faults = [_]@import("../../src/test_fixtures/spec_generation_driver.zig").Fault{
        .{ .stage = .loss_review, .shape = .review_partial_assignment, .repetition = .{ .first_request = 1 } },
        .{ .stage = .loss_review, .shape = .review_repeated_member, .repetition = .{ .first_request = 1 } },
        .{ .stage = .loss_review, .shape = .review_partial_assignment, .repetition = .persistent },
    };
    const source_repairs = source_losses.* ++ .{.empty} ++ [_]@TypeOf(source_losses[0]){.empty} ** loss_faults.len;
    const finer_composition_scenario = source_repair_start + source_losses.len;
    const loss_fault_start = finer_composition_scenario + 1;
    const summary_start = source_repair_start + source_repairs.len;
    const global_start = summary_start + 4;
    const brief_start = global_start + 4;
    const applicability_start = brief_start + 4;
    const applicability_cases = std.meta.tags(@import("../../src/test_fixtures/spec_generation_responses.zig").Applicability);
    const timing = @import("../../src/test_fixtures/scenario_timing.zig");
    const membership_start = applicability_start + applicability_cases.len * 2;
    const preservation_start = membership_start + 8;
    // ADR 0038 Decision 7: an edge case's outcome link is native, a model's closed choice, or a
    // blocked run. The last two use three source groups: the choice case makes one request per
    // group, answered alternately, and the blocked case leaves criteria in only the first group.
    const link_start = preservation_start + 3;
    var costs: [link_start + 3]?timing.Sample = @splat(null);
    const case_range_begin: usize = switch (workflow_cases) {
        .existing => 0,
        .source_preservation => preservation_start,
        .reuse_regeneration => preservation_start + 1,
        .scenario_links => link_start,
    };
    const case_range_end: usize = switch (workflow_cases) {
        .existing => preservation_start,
        .source_preservation => link_start,
        .reuse_regeneration => preservation_start + 2,
        .scenario_links => costs.len,
    };
    defer timing.report(io, "specification-generation", costs[case_range_begin..case_range_end]) catch |err| std.debug.panic("scenario timing report failed: {s}", .{@errorName(err)});
    for (case_range_begin..case_range_end) |scenario| {
        var cost = timing.Timer.start(io, &costs[scenario]);
        defer cost.finish();
        var assertion_context: []const u8 = "setup";
        errdefer |err| std.debug.print("specification-generation scenario {d} failed in {s}/{s}: {s}\n", .{ scenario, @tagName(cost.phase), assertion_context, @errorName(err) });
        const applicability = if (scenario >= applicability_start and scenario < membership_start) applicability_cases[(scenario - applicability_start) % applicability_cases.len] else null;
        const other_applicability = scenario >= applicability_start + applicability_cases.len;
        const membership_scenario = scenario >= membership_start and scenario < preservation_start;
        const link_scenario = scenario >= link_start;
        const preservation_scenario = scenario >= preservation_start and !link_scenario;
        const brief_scenario = scenario >= brief_start and scenario < applicability_start;
        const global_scenario = scenario >= global_start and scenario < brief_start;
        const summary_scenario = scenario >= summary_start and scenario < global_start;
        const source_repair_scenario = scenario >= source_repair_start and scenario < summary_start;
        const disposition_scenario = scenario >= disposition_start and scenario < source_repair_start;
        const evidence_scenario = scenario >= evidence_start and scenario < disposition_start;
        const source_gaps = scenario >= source_gap_start and scenario < evidence_start;
        const candidate_omission = scenario >= omission_scenario and scenario < extraction_omission_start;
        const extraction_omission = scenario >= extraction_omission_start and scenario < source_gap_start;
        const reconciliation_scenario = scenario >= reconciliation_start and scenario < repeated_start;
        const classification_scenario = scenario >= classification_repair_start and scenario < reconciliation_start;
        const repeated_scenario = scenario >= repeated_start and scenario < protocol_text_start;
        const protocol_text_scenario = scenario >= protocol_text_start and scenario < protocol_selection_scenario;
        const protocol_content_scenario = scenario >= protocol_content_start and scenario < omission_scenario;
        const fault: ?@TypeOf(faults[0]) = if (brief_scenario) .{ .stage = .generation, .shape = .forbidden_provenance, .repetition = if (scenario - brief_start < 2) .persistent else .{ .first_request = 2 } } else if (scenario >= 14 and scenario < classification_repair_start) faults[scenario - 14] else null;
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try writeReferenceIngestionFixture(io, project.dir);
        if (preservation_scenario) {
            const configuration = try project.dir.readFileAlloc(io, ".sddtoolkit.json", allocator, .limited(1_048_576));
            defer allocator.free(configuration);
            const configured = try std.mem.concat(allocator, u8, &.{ "{\"validation\":{\"sourcePreservationCheck\":true},", configuration[1..] });
            defer allocator.free(configured);
            try project.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = configured });
        }
        try project.dir.createDirPath(io, ".sdd/principles");
        try project.dir.createDirPath(io, ".sdd/presets");
        try project.dir.createDirPath(io, "engine/workflows/spec");
        try project.dir.writeFile(io, .{ .sub_path = ".sdd/principles/toolchain.yaml", .data = "schema: project-toolchain/v1\npresets: []\npolicies: [project.zig@1]\n" });
        if (scenario <= 1 or scenario == 3) try project.dir.writeFile(io, .{ .sub_path = ".sdd/principles/core.md", .data = if (scenario == 1) "Delete loan receipts after thirty days.\n" else "Display time in UTC.\n" });
        // Every source set below opens with a level-1 title heading (ADR 0048).
        if (scenario == 1 or (scenario >= 8 and scenario != 12)) try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = "# Loan renewal\n" ++ "A librarian renews a loan.\n" ** 70 ++ "Display `Loan renewed!`.\n" });
        if (preservation_scenario) try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = if (scenario == preservation_start + 2) "# Loan renewal\nRenew eligible loans and retain the deadline when renewal is refused.\n" else "# Startup display\nStart successfully and display the current UTC date and time.\n" });
        if (link_scenario) {
            const several = scenario != link_start;
            try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = if (several) "# Loan renewal\nRenew the loan.\n" else "# Loan renewal\nA librarian renews an eligible loan and sees the new return deadline.\n" });
            if (several) {
                try project.dir.writeFile(io, .{ .sub_path = "source-material/first/receipt.md", .data = "Issue a receipt.\n" });
                try project.dir.writeFile(io, .{ .sub_path = "source-material/first/confirmation.md", .data = "Confirm the renewal.\n" });
            }
        }
        if (membership_scenario) try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = if ((scenario - membership_start) % 4 >= 2)
            "# Library loans\nMOCK Track library loans and display their return deadlines.\n"
        else
            "# Customer invoices\nMOCK Track customer invoices and display the outstanding balance.\n" });
        if (extraction_omission) try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = if (scenario == extraction_omission_start) "# Startup display\nOn startup display `Hello, World!` and the current UTC date and time.\n" else "# Loan renewal\nAfter renewal display `Loan renewed!` and the new return deadline.\n" });
        if (candidate_omission) try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = if (scenario == omission_scenario) "# Startup display\nA visitor sees the current UTC date and time on startup. Display `Hello, World!`.\n" else if (scenario == omission_scenario + 1) "# Loan renewal\nA librarian renews a loan and sees the new return deadline. Display `Loan renewed!`.\n" else "# Booking confirmation\nA traveller confirms a booking and sees its arrival date. Display `Booking confirmed!`.\n" });
        if (source_gaps) try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = if (scenario == source_gap_start) "# Startup display\nOn startup display `Hello, World!` and the current UTC date and time.\n" else "# Loan renewal\nAfter renewal display `Loan renewed!` and the new return deadline.\n" });
        if (evidence_scenario) try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = if (scenario == evidence_start + 1) "# Loan renewal\nAfter renewal display `Loan renewed!` and the new return deadline.\n" else "# Startup display\nOn startup display `Hello, World!` and the current UTC date and time.\n" });
        if (summary_scenario or global_scenario) try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = if ((scenario - summary_start) % 2 == 0) "# Startup display\nOn startup display `Hello, World!` and the current UTC date and time.\n" else "# Loan renewal\nAfter renewal display `Loan renewed!` and label the deadline `Return by`.\n" });
        if (brief_scenario) try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = if ((scenario - brief_start) % 2 == 0) "# Startup display\nOn startup display `Hello, World!` and the current UTC date and time.\n" else "# Loan renewal\nAfter renewal display `Loan renewed!` and label the deadline `Return by`.\n" });
        if (applicability) |mode| {
            const source = try std.mem.concat(allocator, u8, &.{ applicability_heading, mode.source(other_applicability) });
            defer allocator.free(source);
            try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = source });
            if (mode == .no_entities) try project.dir.writeFile(io, .{ .sub_path = ".sdd/principles/core.md", .data = if (other_applicability) "Display only the digest.\n" else "Display only the greeting.\n" });
        }
        if (disposition_scenario) try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = if ((scenario - disposition_start) % 2 == 0) "# Startup display\nOn startup display `Hello, World!` and the current UTC date and time.\n" else "# Loan renewal\nAfter renewal display `Loan renewed!` and the new return deadline.\n" });
        // Keep the omitted claim and its exact token in the selected producer's
        // chunk so the empty -> claim -> classification recovery is exercised.
        // A discarded token reaches generation only on a line no claim quotes (ADR 0036).
        if (source_repair_scenario) try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = switch (source_repairs[scenario - source_repair_start]) {
            .partial => "# Loan renewal\nMOCK librarian renews an eligible loan and sees the new return deadline.\n",
            .classification => "# Loan renewal\nA librarian renews a loan and sees the new return deadline.\nDisplay `Loan renewed!`.\n",
            else => "# Loan renewal\nA librarian renews a loan and sees the new return deadline. Display `Loan renewed!`.\n",
        } });
        if (reconciliation_scenario) switch (reconciliation_faults[scenario - reconciliation_start]) {
            .occupied_summary, .occupied_signals, .misbound_summary => try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = "# Loan renewal\nDisplay `Loan renewed!`.\n" }),
            .misbound_signals => try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = "# Startup display\nOn startup display `Hello, World!` and the current UTC date and time.\n" }),
            .occupied_conflict => {
                try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = "# Loan renewal\nRenew the loan.\n" });
                try project.dir.writeFile(io, .{ .sub_path = "source-material/first/conflict.md", .data = "Reject the renewal.\n" });
            },
            .permuted_disposition, .permuted_conflict_disposition => {
                try project.dir.writeFile(io, .{ .sub_path = "source-material/first/stories.md", .data = "# Loan renewal\nRenew the loan.\n" });
                try project.dir.writeFile(io, .{ .sub_path = "source-material/first/receipt.md", .data = "Issue a receipt.\n" });
                try project.dir.writeFile(io, .{ .sub_path = "source-material/first/confirmation.md", .data = "Confirm the renewal.\n" });
            },
            else => {},
        };
        const definition = try std.Io.Dir.cwd().readFileAlloc(io, "design/workflows/spec.workflow.yaml", allocator, .limited(1_048_576));
        defer allocator.free(definition);
        // These cases exercise two independent model-summary request lifecycles.
        // Two-claim partitions supply another leaf instead of a reusable parent.
        const two_summary_requests = summary_scenario or (brief_scenario and (scenario - brief_start) % 2 == 0);
        const configured_definition = if (two_summary_requests) try std.mem.replaceOwned(u8, allocator, definition, "group-size: 8", "group-size: 2") else definition;
        defer if (two_summary_requests) allocator.free(configured_definition);
        try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/preflight.workflow.yaml", .data = configured_definition });
        inline for (.{ "protocol.prompt.md", "extraction-content.prompt.md", "extraction.context.json", "extraction-classifications.prompt.md", "extraction.composition.json", "extraction.schema.json", "reconciliation.prompt.md", "reconciliation.schema.json", "reconciliation-summary.composition.json", "reconciliation-dispositions.prompt.md", "reconciliation-signals.prompt.md", "reconciliation-conflicts.prompt.md", "generation.prompt.md", "generation.context.json", "entities.prompt.md", "records.prompt.md", "generation.schema.json", "support.prompt.md", "support-loss.prompt.md", "support.schema.json", "links.prompt.md", "links.schema.json", "repair.prompt.md", "packet-guidance.json" }) |name| {
            const bytes = try std.Io.Dir.cwd().readFileAlloc(io, "design/workflows/spec/" ++ name, allocator, .limited(1_048_576));
            defer allocator.free(bytes);
            // A finer required-object selector must survive the native extraction
            // handoff and subsequent source repair, not merely JSON assembly.
            const finer = scenario == finer_composition_scenario and std.mem.eql(u8, name, "extraction.composition.json");
            const configured = if (finer) try std.mem.replaceOwned(u8, allocator, bytes, "\"/reason\"", "\"/reason/nodes\"") else bytes;
            defer if (finer) allocator.free(configured);
            try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/spec/" ++ name, .data = configured });
        }
        var project_source = toolchain_authority_source.Adapter.init(io, project.dir);
        var document_parser: toolchain_documents.Adapter = .{};
        var reference_source: @import("../../src/adapters/filesystem/reference_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var feature_source: @import("../../src/adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var feature_inputs: @import("../../src/adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var reference_contents: @import("../../src/adapters/filesystem/reference_corpus_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var markdown_reader: @import("../../src/adapters/parsers/markdown_reference.zig").Adapter = .{ .io = io };
        // Counted state namespaces keep model-visible request bytes reproducible for the
        // request projection; the random adapter is covered by the other suites.
        var reference_ids: @import("../../src/reference_evidence_test.zig").IdSource = .{};
        var native: @import("../../src/composition/native_workflow_operations.zig").Assembly = undefined;
        native.init(allocator, project_source.projectCapturer(), project_source.presetEnumerator(), project_source.presetCapturer(), document_parser.parser(), policy_registry, .{ .normalize_fn = @import("unicode_normalization").nfc }, reference_source.inspector(), feature_source.inspector(), feature_inputs.capturer(), @import("../../src/adapters/parsers/clarification_inputs.zig").stateParser(), @import("../../src/adapters/parsers/clarification_inputs.zig").formParser(), reference_contents.enumerator(), reference_contents.capturer(), markdown_reader.decoderPort(), .{ .fold_fn = @import("unicode_normalization").caseFold }, reference_ids.port(), .{ .boundary_fn = @import("unicode_normalization").lexicalBoundary });
        cost.enter(.bootstrap);
        var boot = runInProjectWithRegistry(io, allocator, project.dir, .{}, &native.registry);
        cost.enter(.runner);
        defer boot.deinit();
        var feature_outputs: @import("../../src/adapters/filesystem/workflow_output.zig").Adapter = .{ .io = io, .project_root = project.dir };
        native.publish_output.action.writer = feature_outputs.port();
        native.prepare_inputs.action.state_source = feature_inputs.workflowStateCapturer();
        if (boot != .ready) std.debug.print("generation bootstrap: {any}\n", .{boot});
        try std.testing.expect(boot == .ready);
        try std.testing.expectEqual(preservation_scenario, boot.ready.config.config().validation.sourcePreservationCheck);
        var logging: @import("../../src/composition/feature_logging_runtime.zig").Assembly = .{
            .allocator = allocator,
            .io = io,
            .project = project.dir,
            .roots = boot.ready.roots.registry(),
            .logs = &boot.ready.logs,
            .inputs = &feature_inputs,
            .outputs = &feature_outputs,
        };
        defer logging.deinit();
        native.activate_feature_logging.activator = logging.activator();
        native.bindRoots(boot.ready.roots.registry());
        native.bindWorkflows(boot.ready.workflows.registry());
        var principle_source: @import("../../src/adapters/filesystem/principle_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
        native.bindConfiguration(boot.ready.config.config());
        native.bindPrinciples(boot.ready.roots.registry().projectPrinciples(), principle_source.reader(), principle_source.enumerator(), principle_source.capturer());
        var services = try @import("../../src/model_request_workflow_test.zig").providerServices(allocator, null, &.{ "spec_generation", "repair" }, false);
        defer services.deinit();
        const graph = boot.ready.workflows.registry().resolve(.{ .bytes = "spec-generation" }).?;
        if (scenario == 0) try verifyAuthoringDiagnosticParent(io, allocator, project.dir, graph, boot.ready.roots.registry().llmProviderConfig());
        var runner = @import("../../src/application/workflow_pipeline_runner.zig").Runner.init(allocator, .{ .invocation = .{ .workflow_id = graph.authority.workflow_id, .arguments = &.{ "--feature", "chosen", "--reference", "first" } }, .graph = graph }, &native.registry, boot.ready.logs.barrier(), .{}, &services, boot.ready.config.config().workflowTokenBudget);
        defer runner.deinit();
        runner.publication_finalizer = logging.finalizer();
        var clock: @import("../../src/provider_authorization_test_fixture.zig").TestClock = .{};
        runner.provider_clock = clock.port();
        var authorization: @import("../../src/adapters/provider/fake_provider_authorization.zig").FakeProviderAuthorization = .{ .allocator = allocator };
        native.model_requests.prepare_authorization.action = .{ .authorization = authorization.port() };
        var fake = @import("../../src/model_request_workflow_test.zig").invocationProvider(&runner, allocator);
        var recorder: request_projection.Recorder = .{ .sink = sink, .scenario = scenario, .inner = fake.interface() };
        native.model_requests.invoke_model.action = .{ .provider = recorder.interface() };
        var driver: @import("../../src/test_fixtures/spec_generation_driver.zig").Driver = .{ .runner = &runner, .fake = &fake, .allocator = allocator, .malformed = scenario == 2, .uncertain = scenario == 3, .malformed_once = scenario == 4 or scenario == 9, .repair = scenario == 5 or scenario == 6 or scenario == 8, .failed_repair = scenario == 6, .omit_exact = scenario == 7, .entities_required = scenario == 11 };
        driver.repeated_provenance_fault = scenario == 6;
        driver.finalizer = logging.finalizer();
        if (fault) |selected_fault| {
            driver.fault = selected_fault;
            driver.repair = selected_fault.stage == .repair;
            if (selected_fault.stage == .repair and selected_fault.shape == .missing_answer) {
                driver.repeated_provenance_fault = selected_fault.repetition == .persistent;
                driver.repair_across_units = selected_fault.repetition == .recover_then_exhaust;
                driver.measurement_prefix = if (selected_fault.repetition == .persistent) ".zig-cache/provenance-answer-exhaustion" else ".zig-cache/provenance-answer-recovery";
            }
            if (selected_fault.shape == .alternating_missing) driver.measurement_prefix = ".zig-cache/r37-recovery";
        }
        if (applicability) |mode| {
            driver.applicability = mode;
            driver.brief_text = .{ mode.source(other_applicability), mode.source(other_applicability) };
            driver.entities_required = mode == .entities;
            if (!other_applicability) driver.measurement_prefix = switch (mode) {
                .no_entities => ".zig-cache/phase4-complete",
                .unjustified => ".zig-cache/phase4-unjustified",
                .missing_text => ".zig-cache/phase4-question",
                else => null,
            };
        }
        if (scenario == 0) driver.fault = .{ .stage = .support, .shape = .empty, .repetition = .{ .every_request = 1 } };
        if (scenario == 1) {
            driver.support_fault = .foreign_source_single;
        }
        if (scenario <= 1) driver.measurement_prefix = if (scenario == 0) ".zig-cache/chunk13-compatible-request" else ".zig-cache/chunk13-conflict-request";
        driver.generation_gap = scenario == 12 or scenario == 13;
        if (candidate_omission) driver.candidate_omissions = if (scenario == omission_scenario) .functional else .acceptance_and_functional;
        driver.extraction_omission = extraction_omission;
        driver.source_gaps = source_gaps;
        if (source_gaps) driver.measurement_prefix = if (scenario == source_gap_start) ".zig-cache/review-decision-greeting" else ".zig-cache/review-decision-loan";
        if (evidence_scenario) driver.evidence_fault = if (scenario == evidence_start + 2) .empty_correction else .recover;
        if (extraction_omission) driver.malformed_once = true;
        driver.missing_classifications = classification_scenario;
        driver.malformed_classification_repair_once = scenario == classification_repair_start + 1;
        driver.failed_classification_repair = scenario == classification_repair_start + 2;
        if (reconciliation_scenario) driver.reconciliation_fault = reconciliation_faults[scenario - reconciliation_start];
        if (repeated_scenario) {
            driver.reconciliation_fault = .self_relation;
            driver.reconciliation_repair_fault = if (scenario == repeated_start) .unchanged else .alternating;
        }
        if (protocol_text_scenario) {
            driver.reconciliation_fault = .signal_text;
            driver.reconciliation_protocol_fault = .envelope_once;
            if (scenario == protocol_text_start + 1) driver.reconciliation_repair_fault = .unchanged_text;
        }
        if (scenario == protocol_selection_scenario) {
            driver.reconciliation_fault = .mixed_selection;
            driver.reconciliation_protocol_fault = .envelope_then_json;
        }
        if (protocol_content_scenario) {
            driver.reconciliation_fault = .signal_coverage;
            driver.reconciliation_protocol_fault = if (scenario == protocol_content_start) .foreign_content_once else .foreign_content_always;
        }
        if (disposition_scenario) driver.disposition_sequence = if (scenario - disposition_start < 2) .exhaust else .recover;
        if (source_repair_scenario) {
            driver.source_loss = source_repairs[scenario - source_repair_start];
            if (driver.source_loss == .false_conflict) driver.measurement_prefix = ".zig-cache/r41-recovery";
            if (driver.source_loss == .false_conflict_questions) driver.measurement_prefix = ".zig-cache/fix002-question-conflict";
            if (scenario >= loss_fault_start) driver.fault = loss_faults[scenario - loss_fault_start];
        }
        if (preservation_scenario and scenario != preservation_start) driver.source_loss = .partial;
        if (summary_scenario) {
            driver.summary_sequence = if (scenario - summary_start < 2) .exhaust else .recover;
            if (scenario == summary_start) driver.measurement_prefix = ".zig-cache/r35-request";
            driver.malformed_once = true;
        }
        if (global_scenario) {
            driver.global_sequence = if (scenario - global_start < 2) .exhaust else .recover;
            driver.measurement_prefix = if (scenario == global_start) ".zig-cache/r36-failure" else if (scenario == global_start + 2) ".zig-cache/r36-recovery" else null;
            driver.malformed_once = true;
        }
        if (brief_scenario) {
            if (scenario == brief_start) driver.measurement_prefix = ".zig-cache/r40-request";
            // Model provenance remains forbidden during correction. Native
            // binding supplies evidence after the semantic fields are admitted.
            const summary_first = (scenario - brief_start) % 2 == 0;
            if (summary_first) driver.summary_sequence = .recover else driver.support_fault = .foreign_source_single;
            driver.brief_text = if (summary_first) .{ "Display the greeting and current UTC date and time on startup.", "Show the current UTC date and time." } else .{ "Confirm loan renewal and display the return deadline.", "Show the new return deadline." };
        }
        cost.enter(.execution);
        if (link_scenario) driver.edge_cases = switch (scenario - link_start) {
            0 => .native,
            1 => .chosen,
            else => .unlinked,
        };
        if (membership_scenario) {
            // This positive/retry matrix has one business group. Feature-wide
            // entities own their applicability and records; record batches cannot
            // repair entity membership. Native deletion needs no model response.
            driver.contradict_entities = true;
            if (scenario < membership_start + 2) driver.measurement_prefix = if (scenario == membership_start) ".zig-cache/membership-extra" else ".zig-cache/membership-missing";
            driver.failed_repair = scenario >= membership_start + 4;
            driver.entities_required = (scenario - membership_start) % 2 == 1;
        }
        var trace: step_trace.Trace = .init(allocator);
        defer trace.deinit();
        driver.trace = &trace;
        const result = driver.run();
        cost.enter(.assertions);
        assertion_context = "request-projection";
        try std.testing.expectEqual(fake.invocation_call_count, recorder.recorded);
        assertion_context = "step-trace";
        try writeStepTrace(io, allocator, project.dir, @tagName(workflow_cases), scenario, &trace, &driver, &runner, result);
        assertion_context = "workflow-outcome";
        if (workflow_cases == .reuse_regeneration) {
            try std.testing.expectEqual(workflow.OutcomeTag.ok, result.executionStatus().?);
            try std.testing.expectEqual(@as(usize, 2), driver.carried_summaries);
            try std.testing.expectEqual(@as(usize, 1), driver.source_repair_calls);
            const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
            try std.testing.expect(view.contains(.published_workflow_output));
            try std.testing.expect(!view.contains(.validated_reference_summary) and !view.contains(.reference_summary_identities));
            try std.testing.expectEqual(driver.calls, runner.tokenLedger().accounted_operations.items.len);
        }
        if (global_scenario) try @import("../../src/test_fixtures/global_protocol_sequence.zig").verify(&driver, result);
        if (summary_scenario) try @import("../../src/test_fixtures/summary_protocol_sequence.zig").verify(&driver, result);
        const retained_repaired_source = reconciliation_scenario and (driver.reconciliation_fault == .cycle or driver.reconciliation_fault == .permuted_disposition);
        const repaired_signal_coverage = driver.reconciliation_fault == .signal_coverage and driver.reconciliation_protocol_fault != .foreign_content_always;
        const expected: workflow.OutcomeTag = if (link_scenario) (if (driver.edge_cases == .unlinked) .blocked else .ok) else if (membership_scenario) (if (driver.failed_repair and driver.entities_required) .failed else .ok) else if (applicability != null) .ok else if (source_repair_scenario) (if (driver.source_loss == .false_conflict_questions or driver.source_loss == .unchanged_conflict or (driver.fault != null and driver.fault.?.repetition == .persistent)) .failed else .ok) else if (candidate_omission or extraction_omission or (fault != null and fault.?.shape == .inconclusive)) .invalid else if (driver.global_sequence == .exhaust or driver.summary_sequence == .exhaust or driver.disposition_sequence == .exhaust or driver.support_fault == .question_native_exhaust or driver.support_fault == .question_mixed_exhaust or driver.reconciliation_fault == .occupied_conflict or driver.reconciliation_protocol_fault == .foreign_content_always or scenario == protocol_selection_scenario or scenario == 2 or scenario == 6 or repeated_scenario or driver.reconciliation_repair_fault == .unchanged_text or driver.failed_classification_repair or (fault != null and (fault.?.repetition == .persistent or fault.?.repetition == .recover_then_exhaust))) .failed else if (driver.generation_gap or driver.reconciliation_fault == .conflict_coverage or driver.reconciliation_fault == .conflict_text or driver.reconciliation_fault == .permuted_conflict_disposition) .needs_user else if (scenario == 7) .blocked else .ok;
        if (expected != result.executionStatus().?) std.debug.print("scenario {d}: {any}; operation: {s}; candidate: {any}\n", .{ scenario, result, driver.rejected_operation orelse "none", try @import("../../src/application/candidate_validation_diagnostics.zig").read(&.{ .slots = runner.envelope.slots }) });
        try std.testing.expectEqual(expected, result.executionStatus().?);
        if (scenario == 0) {
            try std.testing.expectEqual(@as(usize, 1), driver.carried_summaries);
            const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
            try std.testing.expect(view.contains(.published_workflow_output));
            try std.testing.expect(!view.contains(.validated_reference_summary) and !view.contains(.reference_summary_identities));
        }
        if (link_scenario) {
            const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
            const refusal = "- **EXPECTED OUTCOME** The request is refused.";
            switch (driver.edge_cases.?) {
                // The run stops before any request, and the typed gap names the edge case's group.
                .unlinked => {
                    try std.testing.expectEqual(@as(usize, 0), driver.link_calls);
                    try std.testing.expect(!view.contains(.published_workflow_output));
                    const gap = (try @import("../../src/application/candidate_validation_diagnostics.zig").read(&view)).?.source_catalogue;
                    try std.testing.expectEqual(.edge_case_without_criterion, gap.reason);
                    try std.testing.expectEqual(@as(usize, 1), gap.eligible_signals.len);
                    try std.testing.expect(gap.valid());
                },
                .native, .chosen => {
                    const chosen = driver.edge_cases.? == .chosen;
                    // One criterion needs no request. With two, each group's edge case makes its own
                    // closed request, so the loop runs once per group.
                    const groups = (try @import("../../src/application/specification_workflow.zig").readSession(&view)).record_group_count;
                    try std.testing.expectEqual(if (chosen) groups else 0, driver.link_calls);
                    try std.testing.expect(!chosen or groups > 1);
                    try std.testing.expect(view.contains(.published_workflow_output));
                    const rendered = try @import("../../src/application/specification_values.zig").storage.read(&view, @import("../../src/application/specification_rendering_workflow.zig").rendered_schema, .rendered);
                    // The printed outcome is the linked criterion's Then: the one the model named for
                    // that edge case. The answers alternate between the last and the first criterion
                    // offered, so the refusal prints for the first, third, ... edge case only.
                    const refusals: usize = if (chosen) (groups + 1) / 2 else 0;
                    try std.testing.expectEqual(refusals, std.mem.count(u8, rendered, refusal));
                    try std.testing.expectEqual(if (chosen) groups else 1, std.mem.count(u8, rendered, "- **EXPECTED OUTCOME** "));
                    const content = try @import("../../src/application/required_authority_values.zig").read(&view, @import("../../src/application/required_authority_workflow.zig").content_schema, .content);
                    var linked: usize = 0;
                    for (content.records) |record| {
                        if (record.proposal.content != .edge_case) continue;
                        const target = record.outcome_of.?;
                        const criterion = for (content.records) |other| {
                            if (std.meta.eql(other.id, target)) break other;
                        } else return error.DanglingOutcomeLink;
                        const then = criterion.proposal.content.acceptance_criterion.then.segments;
                        const refused = then.len == 1 and then[0] == .literal and std.mem.eql(u8, then[0].literal.value, "The request is refused.");
                        // Edge cases are in authoring order, which is the order they were asked.
                        try std.testing.expectEqual(chosen and linked % 2 == 0, refused);
                        linked += 1;
                    }
                    try std.testing.expectEqual(if (chosen) groups else 1, linked);
                    // The persisted state holds the link as the criterion's ID, and readback
                    // rejects a dangling link, a missing link and a link on any other record.
                    const specification_state = @import("../../src/domain/specification_state.zig");
                    const contracts = boot.ready.workflows.registry().contractSource();
                    const saved = try project.dir.readFileAlloc(io, "engine/workflows/features/chosen/state/workflow.json", allocator, .limited(64 * 1024 * 1024));
                    defer allocator.free(saved);
                    var readback: std.heap.ArenaAllocator = .init(allocator);
                    defer readback.deinit();
                    _ = (try specification_state.parse(readback.allocator(), saved, .{ .bytes = "chosen" }, contracts)).specified() orelse return error.ExpectedSpecifiedState;
                    const link = if (chosen) "\"outcome_of\":{\"kind\":\"acceptance_criterion\",\"ordinal\":2}" else "\"outcome_of\":{\"kind\":\"acceptance_criterion\",\"ordinal\":1}";
                    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, saved, link));
                    for ([_][2][]const u8{
                        .{ link, "\"outcome_of\":{\"kind\":\"acceptance_criterion\",\"ordinal\":9}" },
                        .{ link, "\"outcome_of\":null" },
                        .{ "\"outcome_of\":null", "\"outcome_of\":{\"kind\":\"acceptance_criterion\",\"ordinal\":1}" },
                    }) |forgery| {
                        const forged = try std.mem.replaceOwned(u8, readback.allocator(), saved, forgery[0], forgery[1]);
                        try std.testing.expect(!std.mem.eql(u8, forged, saved));
                        try std.testing.expectError(error.InvalidSpecificationState, specification_state.parse(readback.allocator(), forged, .{ .bytes = "chosen" }, contracts));
                    }
                },
            }
        }
        if (preservation_scenario) {
            try std.testing.expect(driver.initial_source_review_calls != 0);
            try std.testing.expectEqual(@as(usize, if (scenario == preservation_start) 0 else 1), driver.source_repair_calls);
            try std.testing.expect(runner.repair_retry.currentPermit() == null);
        }
        if (driver.reconciliation_fault == .mixed_selection and driver.reconciliation_protocol_fault == null) {
            const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
            try std.testing.expect(view.contains(.published_workflow_output));
            try std.testing.expect(driver.generation_calls > 0);
        }
        if (repaired_signal_coverage or retained_repaired_source) {
            const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
            try std.testing.expect(driver.generation_calls != 0);
            try std.testing.expect(view.contains(.published_workflow_output));
            const accounted = (try @import("../../src/application/reference_extraction_workflow.zig").read(&view, @import("../../src/application/reference_reconciliation_workflow.zig").accounted_schema, .reconciliation_accounted)).payload().reconciliation_accounted;
            const inputs = (try @import("../../src/application/pipeline_values.zig").read(&view, @import("../../src/application/reference_evidence_workflow.zig").inputs_schema, @import("../../src/domain/reference_evidence.zig").Inputs)).*;
            const refs = @import("../../src/domain/reference_support.zig");
            const records = refs.records(accounted);
            try @import("../../src/domain/specification_source_binding.zig").validate(records, inputs);
            if (retained_repaired_source) {
                var historical: usize = 0;
                for (records.signals) |signal| if (!try refs.eligibleSelection(records.dispositions, signal.value.claim_ids)) {
                    historical += 1;
                };
                try std.testing.expect(historical > 0);
            }
        }
        if (membership_scenario) {
            const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
            const current = try @import("../../src/application/specification_workflow.zig").readSession(&view);
            try std.testing.expectEqual(@as(usize, 1), current.record_group_count);
            if (driver.failed_repair and driver.entities_required) {
                const entity_index = @import("../../src/domain/specification_session.zig").entities_index;
                try std.testing.expect(current.units[entity_index] == null);
                try std.testing.expectEqual(entity_index, current.completed);
                const parsed = try @import("../../src/application/specification_values.zig").storage.read(&view, @import("../../src/application/specification_workflow.zig").parsed_schema, .parsed);
                try std.testing.expect(parsed.response == .content and parsed.response.content == .entities);
                try std.testing.expectEqual(.required, parsed.response.content.entities.disposition);
                try std.testing.expectEqual(@as(usize, 1), parsed.response.content.entities.basis.source_group_ids.len);
                try std.testing.expectEqual(@as(usize, 1), parsed.response.content.entities.records.len);
                const inserted = parsed.last_repair orelse return error.MissingNativeEntityInsertion;
                try std.testing.expectEqual(.insert, inserted.operation);
                try std.testing.expect(inserted.changed);
                const rejected = (try @import("../../src/application/candidate_validation_diagnostics.zig").read(&view)).?.specification;
                try std.testing.expectEqual(.entities, rejected.issue.unit);
                // Membership was corrected, but the insertion's invalid scalar
                // still fails within the feature entity owner's bounded repair.
                try std.testing.expect(rejected.issue.membership == null);
                try std.testing.expectEqual(.typed_text, rejected.issue.rule);
                try std.testing.expect(rejected.issue.text_issue != null);
                try std.testing.expect(rejected.issue.repair_target != null);
                try std.testing.expect(rejected.origin != null);
                try std.testing.expect(result == .execution_rejected and result.execution_rejected == .retry_limit);
                try std.testing.expect(!view.contains(.identified_specification_content));
                try std.testing.expect(!view.contains(.clarification_needs));
                try std.testing.expect(!view.contains(.published_workflow_output));
            } else {
                try std.testing.expect(view.contains(.published_workflow_output));
                const entities = current.units[@import("../../src/domain/specification_session.zig").entities_index] orelse return error.MissingAdmittedEntityUnit;
                try std.testing.expectEqual(@as(usize, 1), entities.response.content.entities.basis.source_group_ids.len);
                if (!driver.entities_required) {
                    const deleted = entities.last_repair orelse return error.MissingNativeEntityDeletion;
                    try std.testing.expectEqual(.delete, deleted.operation);
                    try std.testing.expect(deleted.changed);
                    try std.testing.expectEqual(deleted.revision_before + 1, deleted.revision_after);
                    try std.testing.expect(deleted.origin == null);
                    try std.testing.expect(entities.origins.initial != null);
                    try std.testing.expectEqual(@as(usize, 0), entities.origins.fields.len);
                    try std.testing.expectEqual(.not_applicable, entities.response.content.entities.disposition);
                    try std.testing.expectEqual(@as(usize, 0), entities.response.content.entities.records.len);
                    try std.testing.expectEqualDeep(current.units[0].?.response.content.brief.description, entities.response.content.entities.basis);
                    var owner_arena: std.heap.ArenaAllocator = .init(allocator);
                    defer owner_arena.deinit();
                    const owner = try @import("../../src/domain/specification_session.zig").ownerFor(owner_arena.allocator(), current, @import("../../src/domain/specification_session.zig").entities_index);
                    try std.testing.expect(@import("../../src/domain/model_request_identity.zig").unitOwnerEql(owner, deleted.owner));
                    // The model-only failure flag has no effect on a native
                    // deletion: no atomic replacement request is sent.
                    for (runner.tokenLedger().accounted_operations.items) |operation| try std.testing.expect(operation.id.model_request_id.purpose != .atomic_repair);
                    try std.testing.expect(runner.repair_retry.currentPermit() == null);
                }
                var readback: std.heap.ArenaAllocator = .init(allocator);
                defer readback.deinit();
                const saved = try project.dir.readFileAlloc(io, "engine/workflows/features/chosen/state/workflow.json", readback.allocator(), .limited(64 * 1024 * 1024));
                const state = @import("../../src/domain/specification_state.zig");
                var restored = (try state.parse(readback.allocator(), saved, .{ .bytes = "chosen" }, boot.ready.workflows.registry().contractSource())).specified() orelse return error.MissingPublishedSpecification;
                restored.content.entities.disposition = if (driver.entities_required) .not_applicable else .required;
                try std.testing.expectError(error.InvalidSpecificationState, state.validate(readback.allocator(), restored, .{ .bytes = "chosen" }, boot.ready.workflows.registry().contractSource()));
            }
            try std.testing.expectEqual(driver.calls, runner.tokenLedger().accounted_operations.items.len);
            try std.testing.expectEqual(@as(u128, driver.calls) * (fake.invocation_plan.complete.input_tokens + fake.invocation_plan.complete.output_tokens), runner.tokenLedger().committed());
        }
        // Production event evidence is independent of the driver's observations.
        // A pre-write intent row never substitutes for the returned publication result.
        {
            assertion_context = "production-events";
            const paths = @import("../../src/domain/workflow_artifact_registry.zig").bindFeatureLogSinkAdapter(@import("../../src/domain/workflow_artifact_registry.zig").registry(logging.artifact_owner.?), @import("../../src/domain/feature_log_binding.zig").binding(logging.binding_owner.?)).?;
            const path = try std.fmt.allocPrint(allocator, "{s}/{s}/0001.log", .{ paths.specs_root_path, paths.event_binding_path });
            defer allocator.free(path);
            const logged = try project.dir.readFileAlloc(io, path, allocator, .limited(@import("../../src/domain/feature_log_limits.zig").max_segment_bytes));
            defer allocator.free(logged);
            const publication = expected == .ok or expected == .needs_user;
            try std.testing.expectEqual(driver.calls, std.mem.count(u8, logged, "|model.requested|"));
            try std.testing.expectEqual(driver.calls, std.mem.count(u8, logged, "|model.completed|"));
            try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, logged, "|run.started|"));
            try std.testing.expectEqual(@as(usize, if (publication) 1 else 0), std.mem.count(u8, logged, "|publication.prepared|"));
            try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, logged, "|run.completed|"));
            const finished = std.mem.count(u8, logged, "|action.completed|") + std.mem.count(u8, logged, "|action.invalid|") + std.mem.count(u8, logged, "|action.failed|");
            try std.testing.expectEqual(finished + @as(usize, if (publication) 1 else 0), std.mem.count(u8, logged, "|action.started|"));
            if (result == .execution_rejected and result.execution_rejected == .retry_limit) try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, logged, "|retry.exhausted|"));
            if (driver.support_merges != 0 or driver.reconciliation_merges != 0) try std.testing.expect(std.mem.indexOf(u8, logged, "|repair.requested|") != null);
            try std.testing.expect(std.mem.indexOf(u8, logged, "segment_trailer|") != null);
            try std.testing.expect(logging.finalized and boot.ready.logs.lifecycle.active == null);
        }
        assertion_context = "stage-specific-evidence";
        if (scenario <= 1) {
            // Ready sources take no review; with post-generation review removed,
            // these runs make no semantic review request at all, so the scripted
            // support faults never fire.
            try std.testing.expectEqual(@as(usize, 0), driver.initial_source_review_calls);
            try std.testing.expectEqual(@as(usize, 0), driver.support_repair_calls + driver.support_merges + driver.fault_calls);
            for (runner.tokenLedger().accounted_operations.items) |operation| try std.testing.expect(operation.id.model_request_id.purpose != .semantic_review);
            try verifyPublication(io, allocator, project.dir, &runner, &driver, boot.ready.workflows.registry().contractSource());
            // The captured principle corpus is carried in state for the next
            // capture; Spec doesn't assess it.
            var readback: std.heap.ArenaAllocator = .init(allocator);
            defer readback.deinit();
            const bytes = try project.dir.readFileAlloc(io, "engine/workflows/features/chosen/state/workflow.json", readback.allocator(), .limited(64 * 1024 * 1024));
            const state = (try @import("../../src/domain/specification_state.zig").parse(readback.allocator(), bytes, .{ .bytes = "chosen" }, boot.ready.workflows.registry().contractSource())).specified().?;
            try std.testing.expect(state.principle_registry.sources.len > 0 and state.principle_registry.chunks.len > 0);
        }
        if (applicability) |mode| {
            try std.testing.expectEqual(driver.calls, runner.tokenLedger().accounted_operations.items.len);
            try std.testing.expectEqual(@as(u128, driver.calls) * (fake.invocation_plan.complete.input_tokens + fake.invocation_plan.complete.output_tokens), runner.tokenLedger().committed());
            // No review follows generation, so nothing changes the native
            // entity decision or manufactures a clarification.
            try std.testing.expectEqual(@as(usize, 0), driver.support_merges);
            try verifyPublication(io, allocator, project.dir, &runner, &driver, boot.ready.workflows.registry().contractSource());
            var readback: std.heap.ArenaAllocator = .init(allocator);
            defer readback.deinit();
            const a = readback.allocator();
            const saved = try project.dir.readFileAlloc(io, "engine/workflows/features/chosen/state/workflow.json", a, .limited(64 * 1024 * 1024));
            const restored = try @import("../../src/domain/specification_state.zig").parse(a, saved, .{ .bytes = "chosen" }, boot.ready.workflows.registry().contractSource());
            const state = restored.specified() orelse return error.ExpectedSpecifiedState;
            const reference = state.reference;
            try std.testing.expectEqual(@as(usize, 0), reference.conflicts.len);
            const published = try project.dir.readFileAlloc(io, "requirements/current/chosen/spec.md", a, .limited(8_388_608));
            assertion_context = "applicability original source and rendered content";
            const captured = reference.inputs.corpus.sources[0].bytes;
            try std.testing.expect(std.mem.startsWith(u8, captured, applicability_heading));
            try std.testing.expectEqualStrings(mode.source(other_applicability), captured[applicability_heading.len..]);
            var expected_source: std.Io.Writer.Allocating = .init(a);
            try @import("../../src/domain/specification_markdown.zig").literal(&expected_source.writer, mode.source(other_applicability), .block_start);
            try std.testing.expect(std.mem.indexOf(u8, published, expected_source.written()) != null);
            // ADR 0048: the stored and published title is the source's level-1 heading, and
            // readback rejects a stored title the captured sources don't yield.
            try std.testing.expectEqualStrings("Required output", state.content.display_name.bytes);
            try std.testing.expect(std.mem.startsWith(u8, published, "# Feature Specification: Required output\n"));
            const forged = try std.mem.replaceOwned(u8, a, saved, "\"display_name\":{\"bytes\":\"Required output\"", "\"display_name\":{\"bytes\":\"Required outputs\"");
            try std.testing.expect(!std.mem.eql(u8, forged, saved));
            try std.testing.expectError(error.InvalidSpecificationState, @import("../../src/domain/specification_state.zig").parse(a, forged, .{ .bytes = "chosen" }, boot.ready.workflows.registry().contractSource()));
            try std.testing.expect(@import("../../src/domain/specification.zig").hasRecords(state.content, .functional_requirement));
            try std.testing.expect(@import("../../src/domain/specification.zig").hasRecords(state.content, .acceptance_criterion));
            try std.testing.expectEqual(@as(@TypeOf(state.content.entities.disposition), if (mode == .entities) .required else .not_applicable), state.content.entities.disposition);
            try std.testing.expectError(error.FileNotFound, project.dir.access(io, "requirements/current/chosen/clarify/S01.md", .{}));
        }
        if (scenario == 3) try verifyPublication(io, allocator, project.dir, &runner, &driver, boot.ready.workflows.registry().contractSource());
        if (disposition_scenario) {
            try driver.verifyDispositionSequence(result);
            if (expected == .ok) {
                var readback: std.heap.ArenaAllocator = .init(allocator);
                defer readback.deinit();
                const bytes = try project.dir.readFileAlloc(io, "engine/workflows/features/chosen/state/workflow.json", readback.allocator(), .limited(64 * 1024 * 1024));
                const state = (try @import("../../src/domain/specification_state.zig").parse(readback.allocator(), bytes, .{ .bytes = "chosen" }, boot.ready.workflows.registry().contractSource())).specified().?;
                // Two semantic repair subjects plus the native token remain
                // fully accounted after the semantic-only disposition repair.
                try std.testing.expectEqual(@as(usize, 3), state.reference.extraction.claims.len);
                try std.testing.expectEqual(@as(usize, 3), state.reference.dispositions.len);
                try std.testing.expectEqual(@as(usize, 3), state.reference.signals.len);
                try std.testing.expectEqual(@as(usize, 1), state.coverage.obligations.len);
                try std.testing.expect(state.coverage.obligations[0].exact_targets.len > 0);
            } else try std.testing.expectError(error.FileNotFound, project.dir.access(io, "engine/workflows/features/chosen/state/workflow.json", .{}));
        }
        if (source_repair_scenario) {
            const pre_generation = switch (driver.source_loss.?) {
                .empty, .false_conflict, .unchanged_conflict, .false_conflict_questions => true,
                .partial, .classification, .signal, .unchanged => false,
            };
            if (pre_generation) {
                const questions = driver.source_loss == .false_conflict_questions;
                const loss_fault: ?@TypeOf(loss_faults[0]) = if (scenario >= loss_fault_start) loss_faults[scenario - loss_fault_start] else null;
                // Exhausted comparison correction stops before the source repair it localizes.
                const loss_exhausted = loss_fault != null and loss_fault.?.repetition == .persistent;
                try std.testing.expectEqual(@as(usize, if (questions or loss_exhausted) 0 else 1), driver.source_repair_calls);
                try std.testing.expectEqual(@as(usize, 0), driver.admitted_losses.get(.candidate));
                if (questions) {
                    try std.testing.expectEqual(@as(usize, 0), driver.loss_calls + driver.support_merges + driver.support_repair_calls);
                    try std.testing.expectEqual(@as(usize, 0), driver.generation_calls);
                } else {
                    try std.testing.expect(driver.loss_calls > 0);
                    // A comparison omitted at response admission is corrected once
                    // and admitted; it never reaches native loss rejection.
                    try std.testing.expectEqual(driver.loss_calls, driver.admitted_losses.get(if (driver.source_loss == .empty) .extraction_claim else .reconciliation_conflict) + driver.fault_calls);
                    if (loss_fault != null) {
                        try std.testing.expectEqual(@as(usize, 1), driver.fault_requests);
                        var attempts: u32 = 0;
                        for (runner.tokenLedger().accounted_operations.items) |operation| if (operation.id.model_request_id == driver.fault_request.?) {
                            attempts += 1;
                            try std.testing.expectEqual(attempts, operation.id.model_attempt_ordinal.value);
                        };
                        if (loss_exhausted) {
                            // Required policy: exhaustion is terminal, never advice.
                            try std.testing.expect(result == .execution_rejected and result.execution_rejected == .retry_limit);
                            const exhausted = result.execution_rejected.retry_limit;
                            try std.testing.expectEqual(@as(u64, exhausted.limit.value) + 1, exhausted.completed_executions);
                            try std.testing.expectEqual(exhausted.completed_executions, driver.fault_calls);
                            try std.testing.expectEqual(@as(u32, @intCast(driver.fault_calls)), attempts);
                        } else {
                            try std.testing.expectEqual(@as(usize, 1), driver.fault_calls);
                            try std.testing.expectEqual(@as(u32, 2), attempts);
                        }
                    } else try std.testing.expectEqual(@as(usize, 0), driver.fault_calls);
                }
                const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
                if (driver.source_loss == .unchanged_conflict) {
                    try std.testing.expect(result == .execution_rejected and result.execution_rejected == .retry_limit);
                    try std.testing.expectEqual(.unchanged_repair, result.execution_rejected.retry_limit.reason);
                    try std.testing.expectEqual(@as(u64, 1), result.execution_rejected.retry_limit.completed_executions);
                    try std.testing.expectEqual(@as(usize, 0), driver.reconciliation_merges);
                } else if (driver.source_loss == .empty and !loss_exhausted) {
                    try std.testing.expectEqual(@as(usize, 1), driver.classification_repair_calls);
                    try std.testing.expect(driver.classification_failure_origin == null);
                    try std.testing.expect(driver.dependent_source_review_calls > 0);
                    try std.testing.expect(driver.source_only_readiness_evidence > 0);
                    try std.testing.expect(runner.repair_retry.currentPermit() == null);
                    try std.testing.expect(view.contains(.published_workflow_output));
                } else if (driver.source_loss == .false_conflict) {
                    try std.testing.expectEqual(@as(usize, 1), driver.reconciliation_repair_calls);
                    try std.testing.expect(driver.dependent_source_review_calls > 0);
                    try std.testing.expect(driver.source_only_readiness_evidence > 0);
                    try std.testing.expect(runner.repair_retry.currentPermit() == null);
                    const references = (try @import("../../src/application/specification_workflow.zig").readContext(&view)).references.records;
                    try std.testing.expectEqual(@as(usize, 0), references.conflicts.len);
                    try std.testing.expect(view.contains(.published_workflow_output));
                }
                if (expected == .failed) {
                    try std.testing.expect(!view.contains(.clarification_needs) and !view.contains(.published_workflow_output));
                    try std.testing.expectError(error.FileNotFound, project.dir.access(io, "requirements/current/chosen/spec.md", .{}));
                }
            } else {
                // These coherent, natively admitted references reached generation.
                // No review follows it, so the scripted loss is never reported
                // and nothing restarts its producer.
                try verifyPublication(io, allocator, project.dir, &runner, &driver, boot.ready.workflows.registry().contractSource());
                try std.testing.expectEqual(@as(usize, 0), driver.classification_repair_calls + driver.reconciliation_repair_calls);
            }
            try std.testing.expectEqual(driver.calls, runner.tokenLedger().accounted_operations.items.len);
            try std.testing.expectEqual(@as(u128, driver.calls) * (fake.invocation_plan.complete.input_tokens + fake.invocation_plan.complete.output_tokens), runner.tokenLedger().committed());
        }
        if (extraction_omission) {
            const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
            const owned = @import("../../src/application/required_authority_values.zig");
            const authority = @import("../../src/application/required_authority_workflow.zig");
            const decision = try owned.read(&view, authority.result_schema, .result);
            try std.testing.expectEqual(.invalid, decision.continuation);
            for (decision.entries) |entry| try std.testing.expect(entry.candidate_defect != null);
            const diagnostic = (try @import("../../src/application/candidate_validation_diagnostics.zig").read(&view)).?;
            try std.testing.expectEqual(.unlocalized_omission, diagnostic.support_findings.repair_rejection.?);
            try std.testing.expectEqualDeep((try owned.read(&view, authority.inputs_schema, .inputs)).evidence, diagnostic.support_findings.evidence);
            var diagnostic_arena: std.heap.ArenaAllocator = .init(allocator);
            defer diagnostic_arena.deinit();
            const copied = try diagnostic.copy(diagnostic_arena.allocator());
            try std.testing.expectEqualDeep(diagnostic, copied);
            try std.testing.expect(driver.initial_source_review_calls > 0);
            try std.testing.expectEqual(driver.calls, runner.tokenLedger().accounted_operations.items.len);
            try std.testing.expectEqual(@as(usize, 0), driver.support_repair_calls);
            try std.testing.expect(!view.contains(.clarification_needs) and !view.contains(.published_workflow_output));
            try std.testing.expectError(error.FileNotFound, project.dir.access(io, "requirements/current/chosen/spec.md", .{}));
            try std.testing.expectError(error.FileNotFound, project.dir.access(io, "engine/workflows/features/chosen/state/clarifications.json", .{}));
        }
        if (source_gaps) {
            // Ready sources take no review, so a source gap the model would invent
            // after generation has no request to appear in.
            try verifyPublication(io, allocator, project.dir, &runner, &driver, boot.ready.workflows.registry().contractSource());
            try std.testing.expectEqual(@as(usize, 0), driver.support_repair_calls + driver.support_merges + driver.initial_source_review_calls);
        }
        if (evidence_scenario) {
            const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
            try std.testing.expectEqual(@as(usize, 0), driver.support_repair_calls + driver.support_merges);
            try std.testing.expectEqual(driver.calls, runner.tokenLedger().accounted_operations.items.len);
            _ = view;
            try verifyPublication(io, allocator, project.dir, &runner, &driver, boot.ready.workflows.registry().contractSource());
        }
        if (expected == .needs_user) {
            var notice_arena: std.heap.ArenaAllocator = .init(allocator);
            defer notice_arena.deinit();
            const notices = try @import("../../src/application/workflow_clarification_report.zig").capture(notice_arena.allocator(), &.{ .slots = runner.envelope.slots });
            try std.testing.expect(notices.len > 0);
            const state_bytes = try project.dir.readFileAlloc(io, "engine/workflows/features/chosen/state/clarifications.json", allocator, .limited(8_388_608));
            defer allocator.free(state_bytes);
            var state = try std.json.parseFromSlice(@import("../../src/domain/clarification_inputs.zig").State, allocator, state_bytes, .{});
            defer state.deinit();
            var open_count: usize = 0;
            for (state.value.records) |record| if (record.status == .open) {
                const name = notices[open_count].id.filename();
                try std.testing.expectEqualStrings(record.id, name[0..3]);
                try project.dir.access(io, notices[open_count].path.project_relative, .{});
                open_count += 1;
            };
            try std.testing.expectEqual(open_count, notices.len);
        }
        if (scenario == 6) {
            const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
            try std.testing.expect(result == .execution_rejected and result.execution_rejected == .retry_limit);
            const diagnostic = (try @import("../../src/application/candidate_validation_diagnostics.zig").read(&view)).?;
            try std.testing.expect(diagnostic == .specification);
            try std.testing.expectEqual(.typed_text, diagnostic.specification.issue.rule);
            try std.testing.expect(diagnostic.specification.issue.field == .target and diagnostic.specification.issue.field.target == .value);
            try std.testing.expect(!view.contains(.specification_publication_state));
            const ledger = runner.tokenLedger();
            try std.testing.expect(ledger.accounted_operations.items.len >= 2);
            const last = ledger.accounted_operations.items[ledger.accounted_operations.items.len - 1].id;
            const previous = ledger.accounted_operations.items[ledger.accounted_operations.items.len - 2].id;
            try std.testing.expectEqual(@import("../../src/domain/model_request_identity.zig").RequestPurposeKind.atomic_repair, std.meta.activeTag(last.model_request_id.purpose));
            try std.testing.expectEqual(previous.model_request_id, last.model_request_id);
            try std.testing.expect(previous.model_attempt_ordinal.value >= 1);
            try std.testing.expectEqual(previous.model_attempt_ordinal.value + 1, last.model_attempt_ordinal.value);
        }
        if (scenario == 7) {
            const diagnostic = (try @import("../../src/application/candidate_validation_diagnostics.zig").read(&.{ .slots = runner.envelope.slots })).?;
            try std.testing.expect(diagnostic == .coverage);
            try std.testing.expectEqual(.no_independent_supported_target, diagnostic.coverage.blocked.?);
        }
        if (reconciliation_scenario) {
            const diagnostic = try @import("../../src/application/candidate_validation_diagnostics.zig").read(&.{ .slots = runner.envelope.slots });
            // Empty selections fail protocol admission. Persistent foreign
            // conflict handles exhaust without entering native reconciliation.
            const occupied = driver.reconciliation_fault == .occupied_conflict;
            if (occupied) {
                try std.testing.expect(diagnostic == null);
                try std.testing.expect(result == .execution_rejected and result.execution_rejected == .retry_limit);
                try std.testing.expectEqual(@as(usize, 0), driver.reconciliation_repair_calls);
                try std.testing.expectEqual(@as(usize, 0), driver.reconciliation_merges);
                try std.testing.expect(runner.envelope.slots[@intFromEnum(pipeline.DataKey.accounted_reference_reconciliation)] == null);
                try std.testing.expect(runner.envelope.slots[@intFromEnum(pipeline.DataKey.published_workflow_output)] == null);
                try std.testing.expectError(error.FileNotFound, project.dir.access(io, "requirements/current/chosen/spec.md", .{}));
            } else if (expected == .needs_user) {
                try std.testing.expect(diagnostic != null and diagnostic.? == .support_findings);
            } else try std.testing.expect(diagnostic == null);
            if (driver.reconciliation_fault == .occupied_summary or driver.reconciliation_fault == .occupied_signals) {
                try std.testing.expectEqual(@as(usize, 0), driver.reconciliation_repair_calls);
                try std.testing.expectEqual(@as(usize, 0), driver.reconciliation_merges);
            }
            if (driver.reconciliation_fault == .permuted_disposition or driver.reconciliation_fault == .permuted_conflict_disposition or driver.reconciliation_fault == .duplicate_disposition) {
                // A repeated disposition record is corrected at admission,
                // as one more attempt of the dispositions request, never repaired.
                try std.testing.expectEqual(@as(usize, 0), driver.reconciliation_repair_calls);
                try std.testing.expectEqual(@as(usize, 0), driver.reconciliation_merges);
                var corrected: usize = 0;
                for (runner.tokenLedger().accounted_operations.items) |operation| {
                    const owner = operation.id.model_request_id.immutable_unit_owner_id;
                    if (owner == .reference_global and operation.id.model_attempt_ordinal.value > 1 and std.mem.indexOf(u8, owner.reference_global.unit_slot_id.bytes, "-dispositions-") != null) corrected += 1;
                }
                try std.testing.expectEqual(@as(usize, 1), corrected);
            }
            if (driver.reconciliation_fault == .misbound_summary or driver.reconciliation_fault == .misbound_signals) {
                try std.testing.expectEqual(@as(usize, 0), driver.reconciliation_repair_calls);
                try std.testing.expectEqual(@as(usize, 0), driver.reconciliation_merges);
                try std.testing.expectEqual(workflow.OutcomeTag.ok, result.executionStatus().?);
                try std.testing.expect(driver.generation_calls > 0);
                const ledger = runner.tokenLedger();
                try std.testing.expectEqual(driver.calls, ledger.accounted_operations.items.len);
                try std.testing.expectEqual(@as(u128, driver.calls) * (fake.invocation_plan.complete.input_tokens + fake.invocation_plan.complete.output_tokens), ledger.committed());
                var corrections: usize = 0;
                for (ledger.accounted_operations.items) |operation| if (operation.id.model_attempt_ordinal.value > 1) {
                    try std.testing.expectEqual(@as(u32, 2), operation.id.model_attempt_ordinal.value);
                    corrections += 1;
                };
                try std.testing.expectEqual(@as(usize, if (driver.reconciliation_fault == .misbound_signals) 2 else 1), corrections);
                var readback: std.heap.ArenaAllocator = .init(allocator);
                defer readback.deinit();
                const saved = try project.dir.readFileAlloc(io, "engine/workflows/features/chosen/state/workflow.json", readback.allocator(), .limited(64 * 1024 * 1024));
                const restored = try @import("../../src/domain/specification_state.zig").parse(readback.allocator(), saved, .{ .bytes = "chosen" }, boot.ready.workflows.registry().contractSource());
                try std.testing.expect(restored.specified() != null);
            }
            if (driver.reconciliation_fault == .cycle or driver.reconciliation_fault == .permuted_disposition) {
                const accounted = try @import("../../src/application/reference_extraction_workflow.zig").read(&.{ .slots = runner.envelope.slots }, @import("../../src/application/reference_reconciliation_workflow.zig").accounted_schema, .reconciliation_accounted);
                try std.testing.expectEqual(.complete, accounted.payload().reconciliation_accounted.outcome);
                try std.testing.expectEqual(@as(u64, if (driver.reconciliation_fault == .cycle) 2 else 1), accounted.payload().reconciliation_accounted.records.assignments.checked.prior.prior.source.revision);
                // Rebuilt catalogues retain current complete groups; historical
                // groups remain evidence without authorizing feature content.
                try std.testing.expectEqual(workflow.OutcomeTag.ok, result.executionStatus().?);
                // No authority projection follows generation.
                try std.testing.expect(runner.envelope.slots[@intFromEnum(pipeline.DataKey.required_authority_inputs)] == null);
            }
            // Conflict representation repair retains the real source conflict.
            if (driver.reconciliation_fault == .conflict_coverage or driver.reconciliation_fault == .conflict_text or driver.reconciliation_fault == .permuted_conflict_disposition) {
                const accounted = try @import("../../src/application/reference_extraction_workflow.zig").read(&.{ .slots = runner.envelope.slots }, @import("../../src/application/reference_reconciliation_workflow.zig").accounted_schema, .reconciliation_accounted);
                try std.testing.expectEqual(.blocked, accounted.payload().reconciliation_accounted.outcome);
                try std.testing.expect(accounted.payload().reconciliation_accounted.records.conflicts.len > 0);
            }
        }

        if (scenario == protocol_selection_scenario) {
            try std.testing.expect(result == .execution_rejected and result.execution_rejected == .retry_limit);
            try std.testing.expectEqual(@as(usize, 2), driver.reconciliation_repair_calls);
            try std.testing.expectEqual(@as(usize, 0), driver.reconciliation_merges);
            const diagnostic = (try @import("../../src/application/candidate_validation_diagnostics.zig").read(&.{ .slots = runner.envelope.slots })).?.reconciliation;
            try std.testing.expectEqual(@as(u64, 1), diagnostic.revision);
            try std.testing.expectEqual(.content, diagnostic.issue.rule);
            try std.testing.expect(diagnostic.relations.content == null and diagnostic.relations.selection.len != 0);
            const latest = @import("../../src/application/model_request_workflow.zig").readCurrent(&.{ .slots = runner.envelope.slots }, @import("../../src/application/model_request_workflow.zig").prepared_schema) catch unreachable;
            try std.testing.expect(latest.id().purpose == .atomic_repair);
            const latest_origin = @import("../../src/domain/model_request_identity.zig").ledger(runner.model_accounting.?.requests).indexOf(latest.id()).?;
            try std.testing.expect(diagnostic.origin.?.request.value != latest_origin.value);
            try std.testing.expectEqual(@as(u32, 1), diagnostic.origin.?.attempt.value);
            try std.testing.expectEqual(@as(u32, 2), @import("../../src/domain/model_attempt_accounting.zig").latestAttempt(runner.model_accounting.?.attempts).ordinal().value);
            try std.testing.expect(runner.envelope.slots[@intFromEnum(@import("../../src/application/reference_reconciliation_workflow.zig").accounted_schema.key)] == null);
        }
        if (protocol_text_scenario) {
            try std.testing.expectEqual(@as(usize, 2), driver.reconciliation_repair_calls);
            try std.testing.expectEqual(@as(usize, if (scenario == protocol_text_start + 1) 0 else 1), driver.reconciliation_merges);
            try std.testing.expectEqual(@as(usize, 0), driver.unchanged_reconciliation_merges);
            if (scenario == protocol_text_start + 1) {
                try std.testing.expect(result == .execution_rejected and result.execution_rejected == .retry_limit);
                const diagnostic = (try @import("../../src/application/candidate_validation_diagnostics.zig").read(&.{ .slots = runner.envelope.slots })).?.reconciliation;
                try std.testing.expectEqual(.unchanged_repair, result.execution_rejected.retry_limit.reason);
                try std.testing.expectEqual(@as(u64, 1), result.execution_rejected.retry_limit.completed_executions);
                try std.testing.expectEqual(@as(u64, 1), diagnostic.revision);
                try std.testing.expectEqual(@as(u32, 1), diagnostic.origin.?.attempt.value);
                try std.testing.expectEqual(.invalid_scalar, diagnostic.issue.expected.text_issue.reason);
                var observations: std.heap.ArenaAllocator = .init(allocator);
                defer observations.deinit();
                const merges = try @import("../../src/application/candidate_repair_observations.zig").read(observations.allocator(), &.{ .slots = runner.envelope.slots });
                try std.testing.expectEqual(@as(usize, 0), merges.len);
                try std.testing.expect(runner.repair_retry.currentPermit() != null);
            }
        }

        if (protocol_content_scenario) {
            try std.testing.expectEqual(@as(usize, 2), driver.reconciliation_repair_calls);
            // A forbidden native-content response consumes a correction; only
            // the accepted semantic response may merge and rebuild the source catalogue.
            try std.testing.expectEqual(@as(usize, if (driver.reconciliation_protocol_fault == .foreign_content_once) 1 else 0), driver.reconciliation_merges);
            var attempts: usize = 0;
            var request: ?*const @import("../../src/domain/model_request_identity.zig").ModelRequestId = null;
            for (runner.tokenLedger().accounted_operations.items) |operation| {
                const id = operation.id.model_request_id;
                if (id.immutable_unit_owner_id != .reference_global or id.purpose != .atomic_repair) continue;
                if (request) |prior| try std.testing.expectEqualDeep(prior.*, id.*);
                request = id;
                attempts += 1;
            }
            try std.testing.expectEqual(@as(usize, 2), attempts);
            if (driver.reconciliation_protocol_fault == .foreign_content_always) {
                try std.testing.expect(result == .execution_rejected and result.execution_rejected == .retry_limit);
                try std.testing.expectEqual(@as(u32, 1), result.execution_rejected.retry_limit.limit.value);
                try std.testing.expectEqual(@as(u64, 2), result.execution_rejected.retry_limit.completed_executions);
                const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
                try std.testing.expect(!view.contains(.published_workflow_output));
                try std.testing.expectError(error.FileNotFound, project.dir.access(io, "requirements/current/chosen/spec.md", .{}));
            }
        }

        if (repeated_scenario) {
            try std.testing.expect(result == .execution_rejected and result.execution_rejected == .retry_limit);
            const diagnostic = (try @import("../../src/application/candidate_validation_diagnostics.zig").read(&.{ .slots = runner.envelope.slots })).?;
            try std.testing.expect(diagnostic == .reconciliation);
            try std.testing.expectEqual(@as(u64, 1), diagnostic.reconciliation.revision);
            try std.testing.expectEqual(@as(usize, 0), driver.reconciliation_merges);
            try std.testing.expectEqual(@as(usize, 2), driver.reconciliation_repair_calls);
            try std.testing.expectEqual(@as(u32, 1), result.execution_rejected.retry_limit.limit.value);
            try std.testing.expectEqual(@as(u64, 2), result.execution_rejected.retry_limit.completed_executions);
            // Self/foreign relation IDs fail protocol admission, so even
            // the repeated response consumes the numeric correction bound.
            try std.testing.expectEqual(.retry_limit, result.execution_rejected.retry_limit.reason);
            const origin = diagnostic.origin().?;
            const identities = try @import("../../src/application/pipeline_values.zig").read(&.{ .slots = runner.envelope.slots }, @import("../../src/application/model_request_workflow.zig").ledger_schema, @import("../../src/domain/model_request_identity.zig").ModelRequestIdentityLedger);
            var matches: usize = 0;
            for (runner.tokenLedger().accounted_operations.items) |operation| if (origin.matches(identities, operation.id)) {
                try std.testing.expectEqual(.initial_generation, std.meta.activeTag(operation.id.model_request_id.purpose));
                matches += 1;
            };
            try std.testing.expectEqual(@as(usize, 1), matches);
        }
        if (classification_scenario) {
            assertion_context = "classification-send-count";
            try std.testing.expectEqual(@as(usize, if (driver.malformed_classification_repair_once) 2 else 1), driver.classification_repair_calls);
            const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
            const diagnostic = try @import("../../src/application/candidate_validation_diagnostics.zig").read(&view);
            if (driver.failed_classification_repair) {
                assertion_context = "classification-native-candidate";
                const extraction = @import("../../src/application/reference_extraction_workflow.zig");
                const retained = (try extraction.read(&view, extraction.text_schema, .text_validated)).payload().text_validated;
                errdefer std.debug.print("classification-failure result={s}/{s} reason={s} completed={d} sends={d} diagnostic={s} missing={d} origin_null={} revision={d} last_repair={} permit={} published={} clarifications={}\n", .{
                    @tagName(result),
                    if (result == .execution_rejected) @tagName(result.execution_rejected) else "none",
                    if (result == .execution_rejected and result.execution_rejected == .retry_limit) @tagName(result.execution_rejected.retry_limit.reason) else "none",
                    if (result == .execution_rejected and result.execution_rejected == .retry_limit) result.execution_rejected.retry_limit.completed_executions else 0,
                    driver.classification_repair_calls,
                    if (diagnostic) |value| @tagName(value) else "none",
                    if (diagnostic != null and diagnostic.? == .token_classifications) diagnostic.?.token_classifications.issues.missing.len else 0,
                    diagnostic != null and diagnostic.? == .token_classifications and diagnostic.?.token_classifications.origin == null,
                    retained.revision,
                    retained.last_repair != null,
                    runner.repair_retry.currentPermit() != null,
                    view.contains(.published_workflow_output),
                    view.contains(.clarification_needs),
                });
                // Repeating the rejected empty classifications exhausts the
                // active defect without applying a candidate or new revision.
                assertion_context = "classification-unchanged-outcome";
                try std.testing.expect(result == .execution_rejected and result.execution_rejected == .retry_limit);
                try std.testing.expectEqual(.unchanged_repair, result.execution_rejected.retry_limit.reason);
                try std.testing.expectEqual(@as(u64, 1), result.execution_rejected.retry_limit.completed_executions);
                assertion_context = "classification-diagnostic-kind";
                try std.testing.expect(diagnostic != null and diagnostic.? == .token_classifications);
                assertion_context = "classification-missing-entry";
                try std.testing.expect(diagnostic.?.token_classifications.issues.missing.len != 0);
                // Missing entries have no producer; the separate original
                // collection receipt remains unchanged and is never rebased.
                assertion_context = "classification-missing-origin";
                try std.testing.expect(diagnostic.?.token_classifications.origin == null);
                // Observers attribute the producerless rejection to the assembled candidate.
                assertion_context = "classification-candidate-attribution";
                try std.testing.expectEqual(.candidate, diagnostic.?.attribution());
                try std.testing.expectEqual(diagnostic.?.token_classifications.revision, retained.revision);
                assertion_context = "classification-no-applied-repair";
                try std.testing.expect(retained.last_repair == null);
                var retained_collections: usize = 0;
                for (retained.entries) |entry| if (entry.scope.chunk_id.eql(diagnostic.?.token_classifications.scope.chunk_id)) {
                    try std.testing.expectEqual(@as(usize, 0), entry.token_classifications.len);
                    try std.testing.expectEqualDeep(driver.classification_original_origin, if (entry.producers) |producers| producers.classifications else entry.origin);
                    retained_collections += 1;
                };
                try std.testing.expectEqual(@as(usize, 1), retained_collections);
                assertion_context = "classification-active-permit";
                try std.testing.expect(runner.repair_retry.currentPermit() != null);
                assertion_context = "classification-no-publication";
                try std.testing.expect(!view.contains(.published_workflow_output) and !view.contains(.clarification_needs));
                try std.testing.expectError(error.FileNotFound, project.dir.access(io, "requirements/current/chosen/spec.md", .{}));
                try std.testing.expectError(error.FileNotFound, project.dir.access(io, "engine/workflows/features/chosen/state/workflow.json", .{}));
            } else try std.testing.expect(diagnostic == null);
        }
        assertion_context = "later-stage-evidence";
        if (driver.repeated_provenance_fault and fault != null) {
            const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
            const ledger = runner.tokenLedger();
            try std.testing.expectEqual(driver.calls, ledger.accounted_operations.items.len);
            try std.testing.expectEqual(@as(u128, driver.calls) * (fake.invocation_plan.complete.input_tokens + fake.invocation_plan.complete.output_tokens), ledger.committed());
            var attempts: u32 = 0;
            for (ledger.accounted_operations.items) |entry| if (entry.id.model_request_id == driver.fault_request.?) {
                attempts += 1;
                try std.testing.expectEqual(attempts, entry.id.model_attempt_ordinal.value);
            };
            try std.testing.expectEqual(@as(u32, 2), attempts);
            if (fault.?.repetition == .persistent or fault.?.repetition == .recover_then_exhaust) {
                const diagnostic = (try @import("../../src/application/candidate_validation_diagnostics.zig").read(&view)).?;
                try std.testing.expect(diagnostic == .specification);
                try std.testing.expectEqual(.typed_text, diagnostic.specification.issue.rule);
                try std.testing.expect(!view.contains(.specification_publication_state));
            } else {
                const session = try @import("../../src/application/specification_workflow.zig").readSession(&view);
                const brief = session.units[0].?.response.content.brief;
                inline for (.{ "description", "primary_goal" }) |field| {
                    const attributed = @field(brief, field);
                    try std.testing.expect(attributed.value.segments[0] == .literal);
                    try std.testing.expectEqual(@as(usize, 1), attributed.provenance.claim_ids.len);
                    try std.testing.expectEqualDeep(brief.description.provenance.claim_ids, attributed.provenance.claim_ids);
                }
            }
        }
        if (fault != null and (fault.?.shape == .shared_statement or fault.?.shape == .bare_statement)) {
            // The statement restating a requirement was deleted natively; the requirement stays.
            const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
            const session = try @import("../../src/application/specification_workflow.zig").readSession(&view);
            var requirements: usize = 0;
            for (session.record_batches) |batch| for (batch.response.content.records) |record| {
                if (record.content == .functional_requirement) requirements += 1;
                try std.testing.expect(if (fault.?.shape == .shared_statement) record.content != .business_rule else record.content != .user_visible_outcome);
            };
            try std.testing.expect(requirements != 0);
            // The statement was added to at least one batch, so the check is not vacuous.
            if (fault.?.shape == .bare_statement) try std.testing.expect(driver.bare_statements != 0);
        }
        if (fault != null and (fault.?.shape == .uncovered_scenario or fault.?.shape == .runaway_uncovered)) {
            // Every claim a behaviour statement names is named by a scenario of its batch, and
            // the scenarios the response lost came back as engine-bound criteria naming one
            // claim each: at least one insert per batch that lost its scenarios.
            const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
            const session = try @import("../../src/application/specification_workflow.zig").readSession(&view);
            for (session.record_batches) |batch| for (batch.response.content.records) |record| {
                switch (std.meta.activeTag(record.content).role()) {
                    .requirement, .behaviour => {},
                    .scope, .scenario, .entity => continue,
                }
                for (record.provenance.claim_ids) |claim| {
                    const named = for (batch.response.content.records) |other| {
                        if (std.meta.activeTag(other.content).role() == .scenario and @import("../../src/domain/reference_reconciliation.zig").contains(@import("../../src/domain/reference_identity.zig").ClaimId, other.provenance.claim_ids, claim)) break true;
                    } else false;
                    try std.testing.expect(named);
                }
            };
            try std.testing.expect(driver.uncovered_records != 0);
            try std.testing.expect(driver.scenario_inserts >= driver.uncovered_records);
        }
        if (fault != null and fault.?.shape == .duplicate_record) {
            // The repeat was deleted natively: no batch keeps two records of equal content.
            const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
            const session = try @import("../../src/application/specification_workflow.zig").readSession(&view);
            for (session.record_batches) |batch| for (batch.response.content.records, 0..) |record, index| {
                for (batch.response.content.records[0..index]) |prior| {
                    try std.testing.expect(!try @import("../../src/domain/specification_generation.zig").equalContent(allocator, prior.content, record.content));
                }
            };
            // The repeat was added to at least one batch, so the check is not vacuous.
            try std.testing.expect(driver.duplicate_records != 0);
        }
        if (fault) |selected_fault| switch (selected_fault.repetition) {
            .once => try std.testing.expectEqual(@as(usize, 1), driver.fault_calls),
            .first_request => |count| {
                try std.testing.expectEqual(@as(usize, 1), driver.fault_requests);
                try std.testing.expectEqual(@as(usize, count), driver.fault_calls);
            },
            .every_request => |count| {
                // Distinct logical requests traverse the same correction step.
                try std.testing.expect(driver.fault_requests >= 2);
                try std.testing.expectEqual(driver.fault_requests * count, driver.fault_calls);
            },
            .recover_then_exhaust => |recovered| {
                try std.testing.expectEqual(@as(usize, recovered) + 1, driver.fault_requests);
                try std.testing.expectEqual(@as(usize, recovered) + 2, driver.fault_calls);
                try std.testing.expect(driver.generation_calls >= 3);
                try std.testing.expect(result == .execution_rejected and result.execution_rejected == .retry_limit);
                const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
                try std.testing.expect(!view.contains(.published_workflow_output) and !view.contains(.clarification_needs));
                try std.testing.expectError(error.FileNotFound, project.dir.access(io, "requirements/current/chosen/spec.md", .{}));
            },
            .persistent => if (selected_fault.shape == .runaway) {
                // The runaway and its re-send both stopped; the request fails typed.
                try std.testing.expectEqual(@as(usize, 2), driver.fault_calls);
                try std.testing.expectEqual(.RunawayRepeated, runner.last_operation_rejection.?.cause);
                const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
                try std.testing.expect(!view.contains(.published_workflow_output));
            } else {
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
        if (brief_scenario) {
            const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
            const ledger = runner.tokenLedger();
            try std.testing.expectEqual(driver.calls, ledger.accounted_operations.items.len);
            try std.testing.expectEqual(@as(u128, driver.calls) * (fake.invocation_plan.complete.input_tokens + fake.invocation_plan.complete.output_tokens), ledger.committed());
            var attempts: u32 = 0;
            for (ledger.accounted_operations.items) |entry| if (entry.id.model_request_id == driver.fault_request.?) {
                attempts += 1;
                try std.testing.expectEqual(attempts, entry.id.model_attempt_ordinal.value);
            };
            try std.testing.expectEqual(@as(u32, 3), attempts);
            if ((scenario - brief_start) % 2 == 0) {
                try std.testing.expectEqual(@as(usize, 1), driver.reconciliation_merges);
            } else {
                // Ready sources take no review, before or after generation.
                try std.testing.expectEqual(@as(usize, 0), driver.support_merges + driver.support_repair_calls);
                for (ledger.accounted_operations.items) |entry| try std.testing.expect(entry.id.model_request_id.purpose != .semantic_review);
            }
            if (expected == .failed) {
                try std.testing.expect(!view.contains(.published_workflow_output));
                try std.testing.expectError(error.FileNotFound, project.dir.access(io, "requirements/current/chosen/spec.md", .{}));
            } else {
                const session = try @import("../../src/application/specification_workflow.zig").readSession(&view);
                try std.testing.expectEqual(@as(u32, 3), session.units[0].?.origins.initial.?.attempt.value);
                const brief_unit = session.units[0].?;
                try std.testing.expectEqual(@as(usize, 0), brief_unit.origins.fields.len);
                try std.testing.expect(brief_unit.last_repair == null);
                const context = try @import("../../src/application/specification_workflow.zig").readContext(&view);
                var projection_arena: std.heap.ArenaAllocator = .init(allocator);
                defer projection_arena.deinit();
                inline for (.{ "description", "primary_goal" }, 0..) |field, index| {
                    const projected = try @import("../../src/domain/specification_projection.zig").scalar(projection_arena.allocator(), context, @field(session.units[0].?.response.content.brief, field));
                    try std.testing.expectEqualStrings(driver.brief_text.?[index], projected.bytes);
                }
            }
        }
        if (scenario == 0) {
            try expectAuthoringCatalogueCalls(&runner, driver.generation_calls);
            try std.testing.expectEqual(@as(usize, 0), driver.initial_source_review_calls);
        }
        if (expected == .ok) {
            const content = try @import("../../src/application/required_authority_values.zig").read(&.{ .slots = runner.envelope.slots }, @import("../../src/application/required_authority_workflow.zig").content_schema, .content);
            try std.testing.expect(content.records.len != 0);
            try std.testing.expectEqual(@as(@TypeOf(content.entities.disposition), if (driver.entities_required) .required else .not_applicable), content.entities.disposition);
            // Publication needs no authority gate: review authority was retired
            // before generation, or never existed for ready sources.
            try std.testing.expect(runner.envelope.slots[@intFromEnum(pipeline.DataKey.required_authority_gate)] == null);
            try std.testing.expect(runner.envelope.slots[@intFromEnum(pipeline.DataKey.prepared_model_request)] == null);
            const rendered = try @import("../../src/application/specification_values.zig").storage.read(&.{ .slots = runner.envelope.slots }, @import("../../src/application/specification_rendering_workflow.zig").rendered_schema, .rendered);
            var arena: std.heap.ArenaAllocator = .init(allocator);
            defer arena.deinit();
            _ = try @import("../../src/domain/specification_markdown.zig").parse(arena.allocator(), rendered);
            try std.testing.expect((try @import("../../src/application/pipeline_values.zig").read(&.{ .slots = runner.envelope.slots }, @import("../../src/application/specification_rendering_workflow.zig").validated_schema, bool)).*);
        }
        if (driver.support_fault == .inconclusive) try verifyPublication(io, allocator, project.dir, &runner, &driver, boot.ready.workflows.registry().contractSource());
        if (fault != null and fault.?.shape == .inconclusive) {
            const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
            try std.testing.expect(!view.contains(.clarification_needs) and !view.contains(.published_workflow_output));
            try std.testing.expectError(error.FileNotFound, project.dir.access(io, "requirements/current/chosen/spec.md", .{}));
            try std.testing.expectEqual(@as(usize, 0), driver.support_repair_calls);
        }
        if (candidate_omission) {
            // These controls omit entire mandatory record families. Native
            // generation and state validation refuse them; no review follows.
            assertion_context = "native mandatory-family omission";
            const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
            try std.testing.expect(driver.generation_calls != 0);
            try std.testing.expectEqual(@as(usize, 0), driver.initial_source_review_calls + driver.loss_calls + driver.source_repair_calls + driver.support_repair_calls + driver.support_merges);
            try std.testing.expectEqual(@as(usize, 0), driver.classification_repair_calls + driver.reconciliation_repair_calls);
            try std.testing.expect(!view.contains(.published_workflow_output) and !view.contains(.clarification_needs) and !view.contains(.source_omission_repair));
            try std.testing.expectError(error.FileNotFound, project.dir.access(io, "requirements/current/chosen/spec.md", .{}));
            try std.testing.expectEqual(driver.calls, runner.tokenLedger().accounted_operations.items.len);
            try std.testing.expectEqual(@as(u128, driver.calls) * (fake.invocation_plan.complete.input_tokens + fake.invocation_plan.complete.output_tokens), runner.tokenLedger().committed());
        }
        if (expected == .needs_user) {
            var readback: std.heap.ArenaAllocator = .init(allocator);
            defer readback.deinit();
            const a = readback.allocator();
            const bytes = try project.dir.readFileAlloc(io, "requirements/current/chosen/spec.md", a, .limited(8_388_608));
            try std.testing.expect(std.mem.indexOf(u8, bytes, "Status: Incomplete") != null);
            try std.testing.expectError(error.InvalidSpecification, @import("../../src/domain/specification_markdown.zig").parse(a, bytes));
            const saved = try project.dir.readFileAlloc(io, "engine/workflows/features/chosen/state/workflow.json", a, .limited(64 * 1024 * 1024));
            const pending = try @import("../../src/domain/specification_state.zig").parse(a, saved, .{ .bytes = "chosen" }, boot.ready.workflows.registry().contractSource());
            try std.testing.expect(pending.value == .pending and pending.specified() == null);
            for (pending.value.pending.open_clarifications) |id| {
                const name = id.filename();
                const link = try std.fmt.allocPrint(a, "[{s}](clarify/{s})", .{ name[0..3], name });
                try std.testing.expect(std.mem.indexOf(u8, bytes, link) != null);
            }
            const prepared = try @import("../../src/application/pipeline_values.zig").read(&.{ .slots = runner.envelope.slots }, @import("../../src/application/workflow_output_binding.zig").prepared_schema, @import("../../src/domain/workflow_output.zig").Prepared);
            try std.testing.expectEqual(.workflow_state, prepared.files[prepared.files.len - 1].target.artifact);
            try std.testing.expectEqualStrings(bytes, prepared.files[0].bytes);
        }
        if (expected == .needs_user and !driver.generation_gap) {
            const refresh = @import("../../src/application/clarification_refresh_workflow.zig");
            const views = try @import("../../src/application/pipeline_values.zig").read(&.{ .slots = runner.envelope.slots }, refresh.views_schema, []const @import("../../src/domain/clarification_views.zig").View);
            try std.testing.expect(views.len > 0);
            if (scenario == 3) try std.testing.expect(views.len > 1);
            for (views.*) |form| {
                try std.testing.expect(form.content == .replace);
                const path = try std.fmt.allocPrint(allocator, "requirements/current/chosen/clarify/{s}", .{form.id.filename()});
                defer allocator.free(path);
                const bytes = try project.dir.readFileAlloc(io, path, allocator, .limited(16_384));
                defer allocator.free(bytes);
                try std.testing.expectEqualStrings(form.content.replace, bytes);
            }
            const persisted = try project.dir.readFileAlloc(io, "engine/workflows/features/chosen/state/clarifications.json", allocator, .limited(8_388_608));
            defer allocator.free(persisted);
            var parsed = try std.json.parseFromSlice(@import("../../src/domain/clarification_inputs.zig").State, allocator, persisted, .{});
            defer parsed.deinit();
            try std.testing.expectEqual(views.len, parsed.value.records.len);
        }
        if (driver.generation_gap) {
            const views = try @import("../../src/application/pipeline_values.zig").read(&.{ .slots = runner.envelope.slots }, @import("../../src/application/clarification_refresh_workflow.zig").views_schema, []const @import("../../src/domain/clarification_views.zig").View);
            try std.testing.expectEqual(@as(usize, 1), views.len);
            try std.testing.expectEqualStrings("S01.md", &views.*[0].id.filename());
            try std.testing.expect(views.*[0].content == .replace);
            const bytes = try project.dir.readFileAlloc(io, "requirements/current/chosen/clarify/S01.md", allocator, .limited(16_384));
            defer allocator.free(bytes);
            try std.testing.expectEqualStrings(views.*[0].content.replace, bytes);
            const persisted = try project.dir.readFileAlloc(io, "engine/workflows/features/chosen/state/clarifications.json", allocator, .limited(8_388_608));
            defer allocator.free(persisted);
            var parsed = try std.json.parseFromSlice(@import("../../src/domain/clarification_inputs.zig").State, allocator, persisted, .{});
            defer parsed.deinit();
            try std.testing.expectEqual(@as(usize, 1), parsed.value.records.len);
            try std.testing.expectEqualStrings("specification", parsed.value.records[0].subject.requirement);
        }
        if (expected == .ok) {
            const bytes = try project.dir.readFileAlloc(io, "requirements/current/chosen/spec.md", allocator, .limited(8_388_608));
            defer allocator.free(bytes);
            const rendered = try @import("../../src/application/specification_values.zig").storage.read(&.{ .slots = runner.envelope.slots }, @import("../../src/application/specification_rendering_workflow.zig").rendered_schema, .rendered);
            try std.testing.expectEqualStrings(rendered, bytes);
            if (fault != null and fault.?.shape == .alternating_missing) {
                var readback: std.heap.ArenaAllocator = .init(allocator);
                defer readback.deinit();
                const a = readback.allocator();
                const state_path = "engine/workflows/features/chosen/state/workflow.json";
                const saved = try project.dir.readFileAlloc(io, state_path, a, .limited(64 * 1024 * 1024));
                var restored = (try @import("../../src/domain/specification_state.zig").parse(a, saved, .{ .bytes = "chosen" }, boot.ready.workflows.registry().contractSource())).specified().?;
                try std.testing.expectEqualStrings("spec-generation", restored.reference.extraction_contract.?.workflow_id.bytes);
                restored.reference.extraction_contract.?.workflow_version += 1;
                try project.dir.writeFile(io, .{ .sub_path = state_path, .data = try std.json.Stringify.valueAlloc(a, restored, .{}) });
                // Publication changes previously absent filesystem roots. A new
                // invocation must bootstrap their current physical authority.
                var next_boot = runInProjectWithRegistry(io, allocator, project.dir, .{}, &native.registry);
                defer next_boot.deinit();
                try std.testing.expect(next_boot == .ready);
                native.bindRoots(next_boot.ready.roots.registry());
                native.bindWorkflows(next_boot.ready.workflows.registry());
                const next_graph = next_boot.ready.workflows.registry().resolve(graph.authority.workflow_id).?;
                var next_runner = @import("../../src/application/workflow_pipeline_runner.zig").Runner.init(allocator, .{ .invocation = runner.selected.invocation, .graph = next_graph }, &native.registry, next_boot.ready.logs.barrier(), .{}, &services, next_boot.ready.config.config().workflowTokenBudget);
                defer next_runner.deinit();
                var next_driver: @import("../../src/test_fixtures/spec_generation_driver.zig").Driver = .{ .runner = &next_runner, .fake = &fake, .allocator = allocator };
                const rejected = next_driver.run();
                if (rejected != .execution_rejected or rejected.execution_rejected != .operation_failed) std.debug.print("stale extraction contract rerun: outcome={s}, result={s}, operation={s}, calls={d}\n", .{ @tagName(rejected.executionStatus().?), @tagName(rejected), next_driver.rejected_operation orelse "none", next_driver.calls });
                try std.testing.expect(rejected == .execution_rejected and rejected.execution_rejected == .operation_failed);
                try std.testing.expectEqual(error.REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE, rejected.execution_rejected.operation_failed);
                try std.testing.expectEqualStrings("REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE", rejected.execution_rejected.diagnostic());
                try std.testing.expectEqual(@as(usize, 0), next_driver.calls);
                try std.testing.expectEqual(@as(u128, 0), next_runner.tokenLedger().committed());
            }
        } else if (expected != .needs_user) try std.testing.expectError(error.FileNotFound, project.dir.access(io, "requirements/current/chosen/spec.md", .{}));
        cost.passed();
    }
}

// Offline authorization preflight for the Phase 5 diagnostic launcher. Resolve
// the authentic extraction-parent preparation through the current compiled
// graph and production provider bootstrap; no request is dispatched.
fn verifyAuthoringDiagnosticParent(io: std.Io, allocator: std.mem.Allocator, project: std.Io.Dir, graph: *const workflow_compilation.CompiledWorkflow, provider_path: *const bootstrap_root_registry.LLMProviderConfigCapability) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const repository = std.Io.Dir.cwd();
    const config_bytes = try repository.readFileAlloc(io, "test/e2e/wf-001-hello-world/.sddtoolkit.json", a, .limited(1_048_576));
    var configuration = try (@import("../../src/actions/config/decode_sddtoolkit_config.zig").Action{}).execute(a, config_bytes);
    defer configuration.deinit();
    const provider_bytes = try repository.readFileAlloc(io, "test/e2e/config/.sddproviders.json", a, .limited(1_048_576));
    // This integration fixture explicitly configures this provider path; the
    // production bootstrap below still opens it through the validated capability.
    try project.writeFile(io, .{ .sub_path = ".sddproviders.json", .data = provider_bytes });
    var assembly = model_provider_bootstrap.Assembly.init(io, a, project, .{}, &@import("../../src/composition/provider_model_contracts.zig").registry);
    const selected: workflow_execution.SelectedWorkflow = .{ .invocation = .{ .workflow_id = graph.authority.workflow_id, .arguments = &.{} }, .graph = graph };
    var outcome = assembly.bind().invoke(&selected, &configuration.config.models, configuration.config.temperatures(), provider_path);
    defer outcome.deinit();
    try std.testing.expect(outcome == .ready);
    const step = for (graph.authority.steps) |*current| {
        if (std.mem.eql(u8, current.id.bytes, "g7-extract-content")) break current;
    } else return error.MissingDiagnosticParentStep;
    try std.testing.expectEqualStrings("prepare-model-request", step.operation_id.bytes);
    try std.testing.expectEqualStrings("spec_generation", step.model.?.slot.bytes);
    const binding = try (@import("../../src/actions/provider/resolve_provider_model_binding.zig").Action{}).execute(graph, step.id, outcome.ready.registry(), outcome.ready.allowlist());
    const configured = configuration.config.models.slots.map.get(binding.slot_id.bytes).?;
    try std.testing.expectEqualStrings(configured.provider, binding.registry_entry.provider.bytes);
    try std.testing.expectEqualStrings(configured.model, binding.registry_entry.model.bytes);
    try std.testing.expect(@import("../../src/domain/request_debugger.zig").sameOptional(configured.reasoningEffort, binding.reasoning_effort));
    try std.testing.expectEqualDeep(binding.registry_entry.capabilities.inferenceControls(configuration.config.temperatures()), binding.controls);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(graph.source.?.content, &digest, .{});
    const observed = .{
        .version = "authoring-diagnostic-parent-preflight/v1",
        .workflow = graph.authority.workflow_id.bytes,
        .workflow_version = graph.authority.workflow_version,
        .workflow_sha256 = std.fmt.bytesToHex(digest, .lower),
        .request_step = step.id.bytes,
        .operation = step.operation_id.bytes,
        .slot = binding.slot_id.bytes,
        .provider = binding.registry_entry.provider.bytes,
        .model = binding.registry_entry.model.bytes,
        .provider_config = binding.registry_entry.config,
        .reasoning_effort = binding.reasoning_effort,
        .response_mode = binding.registry_entry.responseMode(),
        .controls = binding.controls,
        .dispatched_calls = @as(u32, 0),
    };
    try repository.createDirPath(io, ".zig-cache/authoring-associations");
    try repository.writeFile(io, .{ .sub_path = ".zig-cache/authoring-associations/parent-preflight.json", .data = try std.json.Stringify.valueAlloc(a, observed, .{ .whitespace = .indent_2 }) });
}

fn expectAuthoringCatalogueCalls(runner: *@import("../../src/application/workflow_pipeline_runner.zig").Runner, actual: usize) !void {
    const context = try @import("../../src/application/specification_workflow.zig").readContext(&.{ .slots = runner.envelope.slots });
    const groups = try @import("../../src/domain/specification_source_binding.zig").recordCount(@import("../../src/domain/reference_support.zig").records(context.references));
    // The brief and entity tasks and every retained complete group are dispatched
    // once, including groups whose content-only record result is empty. The
    // engine composes the story without a request (ADR 0047).
    try std.testing.expectEqual(2 + groups, actual);
}

/// Spec publishes from generation and native checks alone (ADR 0023 removal amendment): spec.md has no
/// review status, reference-context has no review or principle section, and the
/// canonical state carries the principle registry this run captured.
fn verifyPublication(io: std.Io, allocator: std.mem.Allocator, project: std.Io.Dir, runner: *@import("../../src/application/workflow_pipeline_runner.zig").Runner, driver: *@import("../../src/test_fixtures/spec_generation_driver.zig").Driver, contracts: @import("../../src/ports/workflow_contract_source.zig").Source) !void {
    var check: []const u8 = "native operation counts";
    errdefer std.debug.print("publication check failed: {s}\n", .{check});
    const view: @import("../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
    try std.testing.expect(driver.generation_calls != 0);
    try std.testing.expectEqual(@as(usize, 0), driver.loss_calls + driver.source_repair_calls);
    try expectAuthoringCatalogueCalls(runner, driver.generation_calls);
    try std.testing.expect(runner.repair_retry.currentPermit() == null);
    try std.testing.expect(view.contains(.published_workflow_output));
    try std.testing.expect(!view.contains(.source_omission_repair));
    const needs = try @import("../../src/application/pipeline_values.zig").read(&view, @import("../../src/application/clarification_refresh_workflow.zig").needs_schema, @import("../../src/domain/clarification_refresh.zig").Needs);
    try std.testing.expectEqual(@as(usize, 0), needs.entries.len);
    check = "accounting";
    try std.testing.expectEqual(driver.calls, runner.tokenLedger().accounted_operations.items.len);
    try std.testing.expectEqual(@as(u128, driver.calls) * (driver.fake.invocation_plan.complete.input_tokens + driver.fake.invocation_plan.complete.output_tokens), runner.tokenLedger().committed());
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    check = "canonical persisted state";
    const bytes = try project.readFileAlloc(io, "engine/workflows/features/chosen/state/workflow.json", a, .limited(64 * 1024 * 1024));
    const restored = try @import("../../src/domain/specification_state.zig").parse(a, bytes, .{ .bytes = "chosen" }, contracts);
    const persisted = restored.specified() orelse return error.ExpectedSpecifiedState;
    try std.testing.expectEqualStrings("specification-state/v25", persisted.schema);
    const stale_state = try std.mem.replaceOwned(u8, a, bytes, "specification-state/v25", "specification-state/v24");
    try std.testing.expect(!std.mem.eql(u8, stale_state, bytes));
    try std.testing.expectError(error.InvalidSpecificationState, @import("../../src/domain/specification_state.zig").parse(a, stale_state, .{ .bytes = "chosen" }, contracts));
    const principles = @import("../../src/domain/principle_registry.zig");
    const live_registry = try @import("../../src/application/pipeline_values.zig").read(&view, @import("../../src/application/principle_workflow.zig").registry_schema, principles.Registry);
    try std.testing.expect(try principles.equal(a, live_registry.*, persisted.principle_registry));
    const published = try @import("../../src/application/required_authority_values.zig").read(&view, @import("../../src/application/required_authority_workflow.zig").content_schema, .content);
    try std.testing.expectEqualDeep(published, persisted.content);
    check = "published views carry no review";
    const specification = try project.readFileAlloc(io, "requirements/current/chosen/spec.md", a, .limited(8_388_608));
    const context_view = try project.readFileAlloc(io, "requirements/current/chosen/reference-context.md", a, .limited(8_388_608));
    try std.testing.expect(std.mem.indexOf(u8, specification, "Review status") == null);
    try std.testing.expect(std.mem.indexOf(u8, context_view, "## Review Status") == null);
    try std.testing.expect(std.mem.indexOf(u8, context_view, "## Principle Consistency") == null);
    check = "published criteria and requirements show their source lines";
    const parsed = try @import("../../src/domain/specification_markdown.zig").parse(a, specification);
    var shown: usize = 0;
    for (parsed.records) |record| {
        const family: @import("../../src/domain/specification.zig").Kind = record.content;
        if (family != .acceptance_criterion and family != .functional_requirement) continue;
        try std.testing.expect(record.sources.len != 0);
        const prefix = try std.mem.concat(a, u8, &.{ persisted.reference.directory.bytes, "/" });
        for (record.sources) |file| try std.testing.expect(std.mem.startsWith(u8, file.path, prefix) and file.path.len > prefix.len);
        shown += 1;
    }
    try std.testing.expect(shown != 0);
    check = "no manufactured persisted clarification";
    const clarifications = @import("../../src/domain/clarification_inputs.zig");
    const clarification_bytes = try project.readFileAlloc(io, "engine/workflows/features/chosen/state/clarifications.json", a, .limited(8_388_608));
    const clarification_state = try clarifications.validate(.{ .value = try @import("../../src/domain/strict_json.zig").decode(clarifications.State, a, clarification_bytes, .{ .maximum_bytes = clarifications.max_state_bytes, .maximum_depth = 64 }) }, .{ .bytes = "chosen" });
    try std.testing.expectEqual(@as(usize, 0), clarification_state.value.?.records.len);
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
    try project.writeFile(io, .{ .sub_path = "engine/workflows/preflight.workflow.yaml", .data = @embedFile("../../src/test_fixtures/reference-preflight.workflow.yaml") });
    try project.writeFile(io, .{ .sub_path = "engine/workflows/hello.workflow.yaml", .data = valid_workflow });
    try project.createDirPath(io, "references/first");
    try project.createDirPath(io, "references/second");
}

fn writeClarificationCapture(io: std.Io, project: std.Io.Dir, captures: @import("../../src/domain/clarification_inputs.zig").Captures) !void {
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
        try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "Chosen/Café", "--reference", "first" }).executionStatus().?);
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
        const captures = try @import("../../src/test_fixtures/clarification_inputs.zig").closed(arena.allocator(), "S01", recorded);
        try writeClarificationCapture(io, project.dir, captures);
        try project.dir.writeFile(io, .{ .sub_path = "requirements/current/Chosen/Café/spec.md", .data = "existing user-edited spec\n" });
        try project.dir.writeFile(io, .{ .sub_path = "requirements/current/Chosen/Café/reference-context.md", .data = "existing reference view\n" });
        for ([_][]const u8{ "first", "second", "first" }) |reference| {
            try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "Chosen/Café", "--reference", reference }).executionStatus().?);
            const closed = try project.dir.readFileAlloc(io, "requirements/current/Chosen/Café/clarify/S01.md", arena.allocator(), .limited(16384));
            try std.testing.expectEqualSlices(u8, captures.forms[0].bytes, closed);
            const state = try project.dir.readFileAlloc(io, "engine/workflows/features/Chosen/Café/state/clarifications.json", arena.allocator(), .limited(8 * 1024 * 1024));
            try std.testing.expectEqualSlices(u8, captures.state.?, state);
            const spec = try project.dir.readFileAlloc(io, "requirements/current/Chosen/Café/spec.md", arena.allocator(), .limited(128));
            try std.testing.expectEqualStrings("existing user-edited spec\n", spec);
        }
        // The compiled operations do not depend on the workflow's name.
        const renamed = try std.mem.replaceOwned(u8, arena.allocator(), @embedFile("../../src/test_fixtures/reference-preflight.workflow.yaml"), "id: reference-preflight", "id: arbitrary-preparation");
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
        var captures = try @import("../../src/test_fixtures/clarification_inputs.zig").closed(allocator, "S01", failure != .stale_form);
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
        try std.testing.expectEqual(workflow.OutcomeTag.failed, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "Chosen/Café", "--reference", "first" }).executionStatus().?);
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
        try std.testing.expectEqual(workflow.OutcomeTag.failed, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "Chosen/Café", "--reference", "first" }).executionStatus().?);
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
    const selected = try @import("../../src/domain/feature_directory.zig").validate(allocator, .{ .bytes = "chosen" }, registry.featureDirectoryRoots());
    var inspector_adapter: @import("../../src/adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
    var inspector = inspector_adapter.inspector();
    inspector.capability = registry.featureDirectoryRead();
    const observed = try inspector.inspect(allocator, selected);
    const artifacts = @import("../../src/domain/workflow_artifact_registry.zig");
    const paths = try artifacts.resolveFeaturePaths(allocator, registry.featureArtifactRoots(), selected);
    var adapter: @import("../../src/adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
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
    const c = @import("../../src/domain/clarification_inputs.zig");
    const fixture = @import("../../src/test_fixtures/clarification_inputs.zig");
    const forms = @import("../../src/domain/clarification_form.zig");
    const refresh = @import("../../src/domain/clarification_refresh.zig");
    const parser = @import("../../src/adapters/parsers/clarification_inputs.zig");
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
            const selected = try @import("../../src/domain/feature_directory.zig").validate(a, .{ .bytes = "Chosen/Café" }, registry.featureDirectoryRoots());
            var inspector_adapter: @import("../../src/adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
            var inspector = inspector_adapter.inspector();
            inspector.capability = registry.featureDirectoryRead();
            const observed = try inspector.inspect(a, selected);
            const paths = try @import("../../src/domain/workflow_artifact_registry.zig").resolveFeaturePaths(a, registry.featureArtifactRoots(), selected);
            var source_adapter: @import("../../src/adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
            var source = source_adapter.capturer();
            source.capability = registry.featureInputRead();
            const captured = try source.capture(a, observed, paths);
            const input_steps = @import("../../src/actions/specify/prepare_inputs.zig").steps;
            const parsed = try input_steps.parseClarificationState(parser.stateParser(), a, captured);
            const state = try c.validate(parsed, selected.feature_id);
            const inputs = try input_steps.validateClarificationForms(parser.formParser(), a, state, captured);
            const record = fixture.record(name);
            const need: refresh.Need = .{ .stage = c.Id.parse(name).?.stage, .subject = record.subject, .authority = record.authority, .question = record.question, .why_required = record.why_required, .answer_schema = record.answer_schema };
            const next = try refresh.refresh(a, inputs, .{ .feature = selected.feature_id, .entries = &.{need}, .original_sources = &.{} });
            const views = try @import("../../src/domain/clarification_views.zig").render(a, next, inputs.protected_forms);
            const prepared = try (@import("../../src/actions/clarification/prepare_clarification_output.zig").Action{}).execute(a, observed, paths, captured, inputs, .{ .ready = next }, views);
            const form_path = try std.mem.concat(a, u8, &.{ selected.project_relative_path, "/clarify/", name, ".md" });
            var writer_adapter: @import("../../src/adapters/filesystem/workflow_output.zig").Adapter = .{ .io = io, .project_root = project.dir };
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
                try std.testing.expectEqualStrings(name, next.state.value.?.records[0].id);
                try std.testing.expectEqual(@as(usize, 1), next.state.value.?.records.len);
                const old = next.state.value.?;
                try project.dir.writeFile(io, .{ .sub_path = form_path, .data = try forms.render(a, old.records[0], fixture.binding(old, old.records[0]), .open, "An unsubmitted long draft that will disappear completely on rerun." ** 8) });
            }
            try std.testing.expectError(error.FileNotFound, project.dir.openFile(io, paths.get(.specification).project_relative, .{}));
            try std.testing.expectError(error.FileNotFound, project.dir.openFile(io, paths.get(.workflow_state).project_relative, .{}));
        }
    }
}

test "registered output writer validates the complete set and never writes completion after a failed file" {
    const output = @import("../../src/domain/workflow_output.zig");
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
    const selected = try @import("../../src/domain/feature_directory.zig").validate(a, .{ .bytes = "Chosen/Café" }, registry.featureDirectoryRoots());
    var inspector_adapter: @import("../../src/adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
    var inspector = inspector_adapter.inspector();
    inspector.capability = registry.featureDirectoryRead();
    const observed = try inspector.inspect(a, selected);
    const paths = try @import("../../src/domain/workflow_artifact_registry.zig").resolveFeaturePaths(a, registry.featureArtifactRoots(), selected);
    const view: output.File = .{ .target = .{ .artifact = .reference_context }, .bytes = "reference view\n" };
    const state: output.File = .{ .target = .{ .artifact = .workflow_state }, .bytes = "test completion\n" };
    var prepared: output.Prepared = .{ .terminal_outcome = .ok, .feature = observed, .paths = paths, .prior = .{ .state = null, .forms = &.{} }, .prior_workflow_state = .{ .captured = null }, .files = &.{ state, view } };
    var writer_adapter: @import("../../src/adapters/filesystem/workflow_output.zig").Adapter = .{ .io = io, .project_root = project.dir };
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
    const access = @import("../../src/adapters/filesystem/file_access.zig");
    const output = @import("../../src/domain/workflow_output.zig");
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
    const completed = [_]output.File{
        .{ .target = .{ .artifact = .specification }, .bytes = "specification\n" },
        .{ .target = .{ .artifact = .reference_context }, .bytes = "reference\n" },
        .{ .target = .{ .artifact = .clarification_state }, .bytes = "state\n" },
        .{ .target = .{ .artifact = .workflow_state }, .bytes = "completion\n" },
    };
    const pending = [_]output.File{
        .{ .target = .{ .artifact = .specification }, .bytes = "incomplete specification\n" },
        .{ .target = .{ .artifact = .reference_context }, .bytes = "current reference\n" },
        .{ .target = .{ .form = .{ .stage = .spec, .ordinal = 1 } }, .bytes = "open question\n" },
        .{ .target = .{ .artifact = .clarification_state }, .bytes = "pending registry\n" },
        .{ .target = .{ .artifact = .workflow_state }, .bytes = "pending state\n" },
    };
    for ([_][]const output.File{ &completed, &pending }) |files| {
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
                const selected = try @import("../../src/domain/feature_directory.zig").validate(a, .{ .bytes = "Chosen/Café" }, registry.featureDirectoryRoots());
                var inspector_adapter: @import("../../src/adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
                var inspector = inspector_adapter.inspector();
                inspector.capability = registry.featureDirectoryRead();
                const observed = try inspector.inspect(a, selected);
                const paths = try @import("../../src/domain/workflow_artifact_registry.zig").resolveFeaturePaths(a, registry.featureArtifactRoots(), selected);
                var source: @import("../../src/adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
                var capture = source.capturer();
                capture.capability = registry.featureInputRead();
                var capture_state = source.workflowStateCapturer();
                capture_state.capability = registry.featureInputRead();
                var prepared: output.Prepared = .{ .terminal_outcome = .ok, .feature = observed, .paths = paths, .prior = try capture.capture(a, observed, paths), .prior_workflow_state = .{ .captured = try capture_state.capture(a, observed, paths) }, .files = files };
                var adapter: @import("../../src/adapters/filesystem/workflow_output.zig").Writer(Failing.replace) = .{ .io = io, .project_root = project.dir };
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
        const result = runInvocationInProjectWithRuntime(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "Chosen/Café", "--reference", "first" }, control.runtime(), null);
        try std.testing.expect(result.executionStatus() != null);
        try std.testing.expectError(error.FileNotFound, project.dir.openDir(io, "requirements", .{}));
        try std.testing.expectError(error.FileNotFound, project.dir.openDir(io, "engine/workflows/features", .{}));
        if (result.executionStatus().? == .ok) return;
        try std.testing.expectEqual(workflow.OutcomeTag.cancelled, result.executionStatus().?);
    }
    return error.FeatureInputsNeverCompleted;
}

test "feature input compiler requires the declared read capability" {
    const io = std.testing.io;
    for ([_][2][]const u8{
        .{ "policy: core.feature-input-read@1", "policy: core.directory-read@1" },
    }) |edit| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try writeFeatureInputFixture(io, project.dir);
        const changed = try std.mem.replaceOwned(u8, std.testing.allocator, @embedFile("../../src/test_fixtures/reference-preflight.workflow.yaml"), edit[0], edit[1]);
        defer std.testing.allocator.free(changed);
        try project.dir.writeFile(io, .{ .sub_path = "engine/workflows/preflight.workflow.yaml", .data = changed });
        try std.testing.expect(runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "Chosen/Café", "--reference", "first" }) == .bootstrap_failed);
    }
}

test "feature preflight uses configured specs roots and preserves selected files across reference changes" {
    const io = std.testing.io;
    const feature = @import("../../src/domain/feature_directory.zig");
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

        // Selected content is untouched; closed clarifications are covered by the feature input reruns.
        const selected = try feature.validate(std.testing.allocator, .{ .bytes = "Chosen/Café" }, .{ .specs = specs_root, .archive = "elsewhere/archive" });
        defer std.testing.allocator.free(selected.project_relative_path);
        try project.dir.createDirPath(io, selected.project_relative_path);
        var target = try project.dir.openDir(io, selected.project_relative_path, .{});
        defer target.close(io);
        try target.writeFile(io, .{ .sub_path = "spec.md", .data = "existing spec\n" });
        try target.writeFile(io, .{ .sub_path = "unrelated.txt", .data = "unrelated\n" });
        var project_source = toolchain_authority_source.Adapter.init(io, project.dir);
        var document_parser: toolchain_documents.Adapter = .{};
        var reference_source: @import("../../src/adapters/filesystem/reference_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var feature_source: @import("../../src/adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var native: @import("../../src/composition/native_workflow_operations.zig").Assembly = undefined;
        var feature_inputs: @import("../../src/adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var reference_contents: @import("../../src/adapters/filesystem/reference_corpus_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var markdown_reader: @import("../../src/adapters/parsers/markdown_reference.zig").Adapter = .{ .io = io };
        var reference_ids: @import("../../src/adapters/system/reference_state_identity.zig").Adapter = .{ .io = io };
        native.init(std.testing.allocator, project_source.projectCapturer(), project_source.presetEnumerator(), project_source.presetCapturer(), document_parser.parser(), policy_registry, .{ .normalize_fn = @import("unicode_normalization").nfc }, reference_source.inspector(), feature_source.inspector(), feature_inputs.capturer(), @import("../../src/adapters/parsers/clarification_inputs.zig").stateParser(), @import("../../src/adapters/parsers/clarification_inputs.zig").formParser(), reference_contents.enumerator(), reference_contents.capturer(), markdown_reader.decoderPort(), .{ .fold_fn = @import("unicode_normalization").caseFold }, reference_ids.source(), .{ .boundary_fn = @import("unicode_normalization").lexicalBoundary });
        native.prepare_inputs.action.state_source = feature_inputs.workflowStateCapturer();
        var boot = runInProjectWithRegistry(io, std.testing.allocator, project.dir, .{}, &native.registry);
        defer boot.deinit();
        try std.testing.expect(boot == .ready);
        var adapter: @import("../../src/adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var inspector = adapter.inspector();
        inspector.capability = boot.ready.roots.registry().featureDirectoryRead();
        const observed = try inspector.inspect(std.testing.allocator, selected);
        try std.testing.expect(observed.observation == .directory);
        for ([_][]const u8{ "first", "second", "first" }) |reference| {
            try std.testing.expectEqual(workflow.OutcomeTag.ok, runInvocationInProject(io, std.testing.allocator, project.dir, &.{ "reference-preflight", "--feature", "Chosen/Café", "--reference", reference }).executionStatus().?);
            const again = try inspector.inspect(std.testing.allocator, selected);
            try std.testing.expect(observed.observation.directory.eql(again.observation.directory));
        }
        const untouched = .{ .{ "spec.md", "existing spec\n" }, .{ "unrelated.txt", "unrelated\n" } };
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
    const feature = @import("../../src/domain/feature_directory.zig");
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try writeReferencePreflightFixture(io, project.dir);
    try project.dir.createDirPath(io, "specs/chosen");
    var project_source = toolchain_authority_source.Adapter.init(io, project.dir);
    var document_parser: toolchain_documents.Adapter = .{};
    var reference_source: @import("../../src/adapters/filesystem/reference_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
    var feature_source: @import("../../src/adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
    var native: @import("../../src/composition/native_workflow_operations.zig").Assembly = undefined;
    var feature_inputs: @import("../../src/adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
    var reference_contents: @import("../../src/adapters/filesystem/reference_corpus_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
    var markdown_reader: @import("../../src/adapters/parsers/markdown_reference.zig").Adapter = .{ .io = io };
    var reference_ids: @import("../../src/adapters/system/reference_state_identity.zig").Adapter = .{ .io = io };
    native.init(std.testing.allocator, project_source.projectCapturer(), project_source.presetEnumerator(), project_source.presetCapturer(), document_parser.parser(), policy_registry, .{ .normalize_fn = @import("unicode_normalization").nfc }, reference_source.inspector(), feature_source.inspector(), feature_inputs.capturer(), @import("../../src/adapters/parsers/clarification_inputs.zig").stateParser(), @import("../../src/adapters/parsers/clarification_inputs.zig").formParser(), reference_contents.enumerator(), reference_contents.capturer(), markdown_reader.decoderPort(), .{ .fold_fn = @import("unicode_normalization").caseFold }, reference_ids.source(), .{ .boundary_fn = @import("unicode_normalization").lexicalBoundary });
    native.prepare_inputs.action.state_source = feature_inputs.workflowStateCapturer();
    var boot = runInProjectWithRegistry(io, std.testing.allocator, project.dir, .{}, &native.registry);
    defer boot.deinit();
    try std.testing.expect(boot == .ready);
    const registry = boot.ready.roots.registry();
    const selected = try feature.validate(std.testing.allocator, .{ .bytes = "chosen" }, registry.featureDirectoryRoots());
    defer std.testing.allocator.free(selected.project_relative_path);
    var adapter: @import("../../src/adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = project.dir };
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

test "input stage YAML rejects unknown parameters and insufficient read authority" {
    const io = std.testing.io;
    const changes = .{
        .{ "use: prepare-inputs", "use: prepare-inputs\n    with: { unexpected: true }" },
        .{ "policy: core.feature-input-read@1", "policy: core.reference-read@1" },
    };
    inline for (changes) |change| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try writeReferencePreflightFixture(io, project.dir);
        const changed = try std.mem.replaceOwned(u8, std.testing.allocator, @embedFile("../../src/test_fixtures/reference-preflight.workflow.yaml"), change[0], change[1]);
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
    .facts = .deadline_only,
    .capabilities = @import("../../src/model_contract_test_fixture.zig").capabilities,
}} };
const test_provider_document =
    \\{"providers":[{"provider":"compiled-provider","models":[{"model":"model-a","json": false, "config":{"requestTimeoutMs":1000}}]}]}
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
            try std.testing.expectEqual(@import("../../src/domain/bootstrap_error.zig").PublicError.WORKFLOW_AUTHORITY_INVENTORY_INVALID, outcome.failed);
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
        try std.testing.expectEqual(@import("../../src/domain/bootstrap_error.zig").PublicError.WORKFLOW_AUTHORITY_INVENTORY_INVALID, outcome.failed);
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
        @import("../../src/domain/bootstrap_error.zig").PublicError.WORKFLOW_REGISTRY_INVALID,
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
        .log_policy_id = @import("../../src/domain/telemetry.zig").Identifier.validate("LOGPOL-1").?,
        .binding_id = @import("../../src/domain/telemetry.zig").Identifier.validate("LOGBIND-1").?,
        .run_id = @import("../../src/domain/telemetry.zig").Identifier.validate("RUN-1").?,
        .feature_id = @import("../../src/domain/feature_identity.zig").FeatureId.parse("F0002").?,
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
    const shortcode = try @import("../../src/domain/telemetry.zig").WorkflowShortcode.parse("TEST");
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
            .log_policy_id = @import("../../src/domain/telemetry.zig").Identifier.validate("LOGPOL-1").?,
            .binding_id = @import("../../src/domain/telemetry.zig").Identifier.validate("LOGBIND-1").?,
            .run_id = @import("../../src/domain/telemetry.zig").Identifier.validate("RUN-1").?,
            .feature_id = @import("../../src/domain/feature_identity.zig").FeatureId.parse("F0002").?,
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
        .log_policy_id = @import("../../src/domain/telemetry.zig").Identifier.validate("LOGPOL-1").?,
        .binding_id = @import("../../src/domain/telemetry.zig").Identifier.validate("LOGBIND-1").?,
        .run_id = @import("../../src/domain/telemetry.zig").Identifier.validate("RUN-1").?,
        .feature_id = @import("../../src/domain/feature_identity.zig").FeatureId.parse("F0002").?,
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
        @import("../../src/domain/bootstrap_error.zig").PublicError.WORKFLOW_AUTHORITY_INVENTORY_INVALID,
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
        @import("../../src/domain/bootstrap_error.zig").PublicError.BOOTSTRAP_ROOT_RESOLUTION_ERROR,
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
            .binding = @import("../../src/application/workflow_operation_binding.zig").bind(OperationObservation, &self.observation, invokeOperation),
        };
        self.operation_entries[1] = .{
            .contract = .{
                .id = "core.noop",
                .kind = .step,
                .outcomes = &.{.ok},
                .side_effect = .none,
            },
            .binding = @import("../../src/application/workflow_operation_binding.zig").bind(OperationObservation, &self.observation, invokeOperation),
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
        temperatures: @import("../../src/domain/model_controls.zig").Temperatures,
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
                    temperatures,
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
        @import("../../src/domain/bootstrap_error.zig").PublicError.ENGINE_CONFIG_READ_ERROR,
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
        @import("../../src/domain/bootstrap_error.zig").PublicError.ENGINE_CONFIG_PARSE_ERROR,
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
        @import("../../src/domain/bootstrap_error.zig").PublicError.BOOTSTRAP_ROOT_RESOLUTION_ERROR,
        outcome.failed,
    );
}

test "a complete root collision fails as a registry error" {
    const io = std.testing.io;
    const colliding_config =
        \\{
        \\  "logs": { "level": "debug", "console": false },
        \\  "workflowTokenBudget": 100000,
        \\  "temperature": 0.1,
        \\  "temperatureRunawayRetry": 1,
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
        @import("../../src/domain/bootstrap_error.zig").PublicError.BOOTSTRAP_ROOT_REGISTRY_INVALID,
        outcome.failed,
    );
}

test "normalization-equivalent absent roots fail as a registry error" {
    const io = std.testing.io;
    const colliding_config =
        \\{
        \\  "logs": { "level": "debug", "console": false },
        \\  "workflowTokenBudget": 100000,
        \\  "temperature": 0.1,
        \\  "temperatureRunawayRetry": 1,
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
        @import("../../src/domain/bootstrap_error.zig").PublicError.BOOTSTRAP_ROOT_REGISTRY_INVALID,
        outcome.failed,
    );
}

test "principle capture uses one no-follow root and the detailed and consolidated paths agree" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = valid_config });
    try project.dir.createDirPath(io, ".sdd/workflows");
    try project.dir.writeFile(io, .{ .sub_path = ".sdd/workflows/hello.workflow.yaml", .data = valid_workflow });
    try writeValidToolchain(io, project.dir);
    try project.dir.writeFile(io, .{ .sub_path = ".sdd/principles/core.md", .data = "Free-form policy.\nNo required heading or front matter." });
    var boot = runInProject(io, std.testing.allocator, project.dir);
    defer boot.deinit();
    try std.testing.expect(boot == .ready);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r = @import("../../src/domain/principle_registry.zig");
    var source: @import("../../src/adapters/filesystem/principle_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
    const capability = boot.ready.roots.registry().projectPrinciples();
    var reader = source.reader();
    reader.capability = capability;
    var enumerator = source.enumerator();
    enumerator.capability = capability;
    var capturer = source.capturer();
    capturer.capability = capability;
    const normalization: @import("../../src/ports/unicode_normalizer.zig").Normalizer = .{ .normalize_fn = @import("unicode_normalization").nfc };
    const folding: @import("../../src/ports/unicode_normalizer.zig").CaseFolder = .{ .fold_fn = @import("unicode_normalization").caseFold };
    const inventory = try r.classify(a, try enumerator.enumerate(a), normalization, folding);
    const low = try capturer.capture(a, inventory);
    const combined = try reader.read(a);
    try std.testing.expectEqualDeep(low, combined);
    try std.testing.expectEqual(@as(usize, 1), combined.sources.len);
    try std.testing.expectEqualStrings("Free-form policy.\nNo required heading or front matter.", combined.sources[0].bytes);
    const registry = try r.build(a, combined, null);
    const action: @import("../../src/actions/principle/capture_principle_registry.zig").Action = .{ .source = reader };
    try std.testing.expect(try r.equal(a, registry, try action.execute(a, null)));
    try project.dir.writeFile(io, .{ .sub_path = ".sdd/principles/core.md", .data = "Changed policy." });
    try std.testing.expectError(error.PrincipleSourceUnavailable, capturer.capture(a, inventory));
    const refreshed = try action.execute(a, registry);
    try std.testing.expectEqual(registry.id.revision + 1, refreshed.id.revision);
    try std.testing.expect(refreshed.sources[0].id.ordinal >= registry.next_source);
    reader.capability = boot.ready.roots.registry().referenceSources();
    try std.testing.expectError(error.PrincipleSourceUnavailable, reader.read(a));
    reader.capability = capability;
    try project.dir.symLink(io, "core.md", ".sdd/principles/alias.md", .{});
    try std.testing.expectError(error.InvalidPrincipleRegistry, reader.read(a));
}
