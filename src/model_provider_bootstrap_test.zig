const std = @import("std");
const decode_toolkit = @import("domain/engine_config_decode.zig");
const compile = @import("domain/workflow_graph_compilation.zig");
const routine = @import("application/model_provider_bootstrap_routine.zig");
const derivation = @import("domain/provider_requirement_derivation.zig");
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
const operations = @import("ports/workflow_operation_registry.zig");
const workflow_inventory = @import("domain/workflow_inventory.zig");

test "compiled binding requirements activate bootstrap without granting provider-call capability" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const capable = try compileOne(arena.allocator(), &operation_registry, "test.model");
    try std.testing.expectEqual(requirement.Requirement.required, deriveGraph(&capable));

    const capability_free = try compileOne(arena.allocator(), &operation_registry, "test.noop");
    try std.testing.expectEqual(requirement.Requirement.not_required, deriveGraph(&capability_free));

    const binding_only = try compileOne(arena.allocator(), &binding_only_registry, "test.model");
    try std.testing.expect(binding_only.authority.steps[0].model != null);
    try std.testing.expectEqual(@as(usize, 0), binding_only.authority.steps[0].capabilities.len);
    try std.testing.expectEqual(@as(usize, 0), binding_only.authority.allowed_capabilities.len);
    try std.testing.expectEqual(requirement.Requirement.required, deriveGraph(&binding_only));

    var denied = operation_registry;
    denied.policies = &.{.{
        .id = "test.safe@1",
        .allowed_capabilities = &.{},
        .allowed_terminal_outcomes = &.{.ok},
    }};
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        compileOne(arena.allocator(), &denied, "test.model"),
    );
}

test "routine skips the provider document for a capability-free selected workflow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const graph = try compileOne(arena.allocator(), &operation_registry, "test.noop");
    var world: World = .{ .bytes = "not json" };
    try world.init(&graph, model_config);
    defer world.deinit();
    var outcome = world.run(.{});
    defer outcome.deinit();

    try std.testing.expect(outcome == .not_required);
    try std.testing.expectEqual(@as(usize, 0), world.source.locate_calls);
    try std.testing.expectEqual(@as(usize, 0), world.source.read_calls);
    // Only the requirement was derived: the step the run stopped at is the first and only one.
    try std.testing.expectEqual(@as(?routine.Step, null), world.diagnostic.step);
}

test "routine captures once and publishes one immutable run authority" {
    for ([_]*const operations.Registry{ &operation_registry, &binding_only_registry }) |registered| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const graph = try compileOne(arena.allocator(), registered, "test.model");
        var world: World = .{ .bytes = provider_document };
        try world.init(&graph, model_config);
        defer world.deinit();
        var outcome = world.run(.{});
        defer outcome.deinit();

        try std.testing.expect(outcome == .ready);
        try std.testing.expectEqual(@as(usize, 1), world.source.locate_calls);
        try std.testing.expectEqual(@as(usize, 1), world.source.read_calls);
        world.source.bytes = "changed after capture";

        const registry = @import("domain/llm_provider_registry.zig").registry(outcome.ready.provider_registry);
        const entry = registry.resolve(provider_id, identity.ModelId.parse("model-a").?).?;
        const allowed = @import("domain/repository_model_allowlist.zig").allowlist(outcome.ready.allowlist);
        try std.testing.expect(allowed.resolveSlot(identity.ModelSlotId.parse("implementation").?).?.registry_entry_id.eql(entry.id));
        try std.testing.expectEqual(@as(usize, 1), world.source.read_calls);
    }
}

test "routine maps each provider preparation boundary exactly and names the failing step" {
    inline for (.{
        .{ .document = "{", .toolkit = model_config, .failure = bootstrap_error.PublicError.LLM_PROVIDER_CONFIG_PARSE_ERROR, .step = routine.Step.decode_config },
        .{ .document = unsupported_provider_document, .toolkit = model_config, .failure = bootstrap_error.PublicError.LLM_PROVIDER_REGISTRY_INVALID, .step = routine.Step.build_registry },
        .{ .document = provider_document, .toolkit = missing_model_config, .failure = bootstrap_error.PublicError.LLM_PROVIDER_MODEL_BINDING_INVALID, .step = routine.Step.validate_allowlist },
    }) |scenario| {
        try expectPreparationFailure(scenario.document, scenario.toolkit, scenario.failure, scenario.step);
    }
}

test "routine maps provider document location and read failures to the read code" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const graph = try compileOne(arena.allocator(), &operation_registry, "test.model");
    // An oversized document fails the read step; an unlocatable one fails the locate step.
    var oversized: World = .{ .bytes = &([_]u8{'a'} ** (provider_config.max_bytes + 1)) };
    try oversized.init(&graph, model_config);
    defer oversized.deinit();
    var read_outcome = oversized.run(.{});
    defer read_outcome.deinit();
    try std.testing.expectEqual(bootstrap_error.PublicError.LLM_PROVIDER_CONFIG_READ_ERROR, read_outcome.failed);
    try std.testing.expectEqual(@as(?routine.Step, .read_config), oversized.diagnostic.step);

    var unlocatable: World = .{ .bytes = provider_document, .fail_locate = true };
    try unlocatable.init(&graph, model_config);
    defer unlocatable.deinit();
    var locate_outcome = unlocatable.run(.{});
    defer locate_outcome.deinit();
    try std.testing.expectEqual(bootstrap_error.PublicError.LLM_PROVIDER_CONFIG_READ_ERROR, locate_outcome.failed);
    try std.testing.expectEqual(@as(?routine.Step, .locate_config), unlocatable.diagnostic.step);
    try std.testing.expectEqual(@as(usize, 0), unlocatable.source.read_calls);
}

/// The checkpoints of a full run, in order: before the first step, then after each of the seven.
const checkpoint_steps = [_]routine.Step{ .derive_requirement, .derive_requirement, .locate_config, .read_config, .decode_config, .build_registry, .validate_registry, .validate_allowlist };

test "routine checks cancellation and deadline between every pair of steps and keeps today's codes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const graph = try compileOne(arena.allocator(), &operation_registry, "test.model");
    for (checkpoint_steps, 1..) |step, checkpoint| {
        for ([_]pipeline.RuntimeStatus{ .cancelled, .deadline_exhausted }) |stop| {
            var countdown: Countdown = .{ .stop_at = checkpoint, .stop = stop };
            var world: World = .{ .bytes = provider_document };
            try world.init(&graph, model_config);
            defer world.deinit();
            var outcome = world.run(countdown.runtime());
            defer outcome.deinit();
            switch (stop) {
                .cancelled => try std.testing.expect(outcome == .cancelled),
                .deadline_exhausted => try std.testing.expectEqual(codeOf(step), outcome.failed),
                .active => unreachable,
            }
            try std.testing.expectEqual(@as(?routine.Step, step), world.diagnostic.step);
            try std.testing.expectEqual(checkpoint, countdown.checks);
            // The port steps that finished before the stop ran once each and none after it.
            try std.testing.expectEqual(@as(usize, if (checkpoint >= 3) 1 else 0), world.source.locate_calls);
            try std.testing.expectEqual(@as(usize, if (checkpoint >= 4) 1 else 0), world.source.read_calls);
        }
    }
}

fn codeOf(step: routine.Step) bootstrap_error.PublicError {
    return switch (step) {
        .derive_requirement, .build_registry, .validate_registry => .LLM_PROVIDER_REGISTRY_INVALID,
        .locate_config, .read_config => .LLM_PROVIDER_CONFIG_READ_ERROR,
        .decode_config => .LLM_PROVIDER_CONFIG_PARSE_ERROR,
        .validate_allowlist => .LLM_PROVIDER_MODEL_BINDING_INVALID,
    };
}

test "an explicit cancellation of the port steps stays cancellation and any other port failure is the read code" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const graph = try compileOne(arena.allocator(), &operation_registry, "test.model");
    var cancelled: World = .{ .bytes = provider_document, .locate_error = error.Cancelled };
    try cancelled.init(&graph, model_config);
    defer cancelled.deinit();
    var cancelled_outcome = cancelled.run(.{});
    defer cancelled_outcome.deinit();
    try std.testing.expect(cancelled_outcome == .cancelled);
    try std.testing.expectEqual(@as(?routine.Step, .locate_config), cancelled.diagnostic.step);

    var late: World = .{ .bytes = provider_document, .locate_error = error.DeadlineExhausted };
    try late.init(&graph, model_config);
    defer late.deinit();
    var late_outcome = late.run(.{});
    defer late_outcome.deinit();
    try std.testing.expectEqual(bootstrap_error.PublicError.LLM_PROVIDER_CONFIG_READ_ERROR, late_outcome.failed);
}

test "every allocation failure in a full run yields a failure that names a step, or the ready authority, and leaks nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const graph = try compileOne(arena.allocator(), &operation_registry, "test.model");
    var fail_index: usize = 0;
    var failures: usize = 0;
    while (true) : (fail_index += 1) {
        var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{ .fail_index = fail_index });
        var world: World = .{ .bytes = provider_document };
        try world.init(&graph, model_config);
        defer world.deinit();
        world.allocator = failing.allocator();
        var outcome = world.run(.{});
        defer outcome.deinit();
        switch (outcome) {
            .ready => break,
            .failed => {
                failures += 1;
                try std.testing.expect(world.diagnostic.step != null);
            },
            .not_required, .cancelled => return error.TestUnexpectedResult,
        }
    }
    try std.testing.expect(failures > 0);
}

fn compileOne(
    allocator: std.mem.Allocator,
    registry: *const operations.Registry,
    contract_id: []const u8,
) !compilation.CompiledWorkflow {
    const steps = try allocator.alloc(workflow.DeclarativeStep, 1);
    const model_parameters = [_]workflow.ParameterBinding{.{
        .id = workflow.WorkflowParameterId.parse("slot").?,
        .value = .{ .string = "implementation" },
    }};
    steps[0] = .{
        .id = workflow.WorkflowStepId.parse("run").?,
        .operation_id = workflow.OperationId.parse(contract_id).?,
        .parameters = if (registry.resolveOperation(.{ .bytes = contract_id }).?.contract.requiresModelBinding()) &model_parameters else &.{},
        .outcomes = &.{.{ .outcome = .ok, .target = .{ .terminal = .ok } }},
    };
    const definitions = try allocator.alloc(definition.Definition, 1);
    definitions[0] = .{
        .source_ordinal = 1,
        .workflow_id = workflow.WorkflowId.parse("model-provider").?,
        .workflow_version = 1,
        .shortcode = telemetry.WorkflowShortcode.parse("TEST") catch unreachable,
        .invocation_operation_id = workflow.OperationId.parse("test.empty").?,
        .policy_profile_id = workflow.RegisteredRef.parse("test.safe@1").?,
        .start_step_id = steps[0].id,
        .resources = &.{},
        .steps = steps,
    };
    const empty_inventory: workflow_inventory.Inventory = .{
        .capability = undefined,
        .descriptors = &.{},
        .accounts = &.{},
        .definition_ordinals = &.{},
        .resource_ordinals = &.{},
    };
    var result_schema_parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const graphs = try compile.compile(
        registry,
        result_schema_parser.compiler(),
        allocator,
        definitions,
        empty_inventory,
        .{ .bindings = &.{}, .resource_ordinals = &.{} },
        &.{},
    );
    return graphs[0];
}

fn deriveGraph(graph: *const compilation.CompiledWorkflow) requirement.Requirement {
    const selected = selectedWorkflow(graph);
    return derivation.derive(&selected);
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
    step: routine.Step,
) !void {
    for ([_]*const operations.Registry{ &operation_registry, &binding_only_registry }) |registered| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const graph = try compileOne(arena.allocator(), registered, "test.model");
        var world: World = .{ .bytes = document_bytes };
        try world.init(&graph, toolkit_bytes);
        defer world.deinit();
        var outcome = world.run(.{});
        defer outcome.deinit();

        try std.testing.expectEqual(expected, outcome.failed);
        try std.testing.expectEqual(@as(?routine.Step, step), world.diagnostic.step);
    }
}

fn decodeToolkit(bytes: []const u8) !@import("domain/config.zig").Owned {
    return decode_toolkit.decode(std.testing.allocator, bytes);
}

/// Reports a stop from its `stop_at`-th status check on.
const Countdown = struct {
    checks: usize = 0,
    stop_at: usize = std.math.maxInt(usize),
    stop: pipeline.RuntimeStatus = .cancelled,

    fn runtime(self: *Countdown) pipeline.NodeRuntime {
        return .{ .context = self, .status_fn = status };
    }

    fn status(context: ?*anyopaque) pipeline.RuntimeStatus {
        const self: *Countdown = @ptrCast(@alignCast(context.?));
        self.checks += 1;
        return if (self.checks >= self.stop_at) self.stop else .active;
    }
};

/// Everything one run needs: the fake port, the decoded configuration, the selected workflow and
/// the capability of a validated root registry.
const World = struct {
    bytes: []const u8,
    fail_locate: bool = false,
    locate_error: ?provider_source.Error = null,
    source: FakeProviderConfigSource = undefined,
    toolkit: @import("domain/config.zig").Owned = undefined,
    root_owner: *bootstrap_root_registry.Owner = undefined,
    selected: execution.SelectedWorkflow = undefined,
    allocator: std.mem.Allocator = std.testing.allocator,
    diagnostic: routine.Diagnostic = .{},

    fn init(self: *World, graph: *const compilation.CompiledWorkflow, toolkit_bytes: []const u8) !void {
        self.source = .{ .bytes = self.bytes, .fail_locate = self.fail_locate, .locate_error = self.locate_error };
        self.toolkit = try decodeToolkit(toolkit_bytes);
        errdefer self.toolkit.deinit();
        self.root_owner = try testRootRegistry(std.testing.allocator);
        self.selected = selectedWorkflow(graph);
    }

    fn deinit(self: *World) void {
        bootstrap_root_registry.deinitOwner(self.root_owner);
        self.toolkit.deinit();
    }

    fn run(self: *World, runtime: pipeline.NodeRuntime) routine.Outcome {
        return routine.run(
            .{ .locator = self.source.locator() },
            self.allocator,
            runtime,
            &self.diagnostic,
            .{
                .selected = &self.selected,
                .models = &self.toolkit.value().models,
                .temperatures = self.toolkit.value().temperatures(),
                .capability = bootstrap_root_registry.registry(self.root_owner).llmProviderConfig(),
                .registered = &compiled_provider_contracts,
            },
        );
    }
};

const FakeProviderConfigSource = struct {
    bytes: []const u8,
    fail_locate: bool = false,
    locate_error: ?provider_source.Error = null,
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
        if (self.locate_error) |failure| return failure;
        if (self.fail_locate) return error.LLMProviderConfigReadFailure;
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

const operation_registry: operations.Registry = .{
    .operations = &.{
        .{
            .contract = .{
                .id = "test.empty",
                .kind = .invocation,
                .outcomes = &.{.ok},
                .side_effect = .none,
            },
            .binding = @import("application/workflow_operation_binding.zig").bind(void, null, unusedOperation),
        },
        .{
            .contract = .{
                .id = "test.model",
                .kind = .step,
                .parameters = &([_]@import("domain/workflow_operation.zig").ParameterDescriptor{.{
                    .id = "slot",
                    .kind = .model_slot,
                    .required = true,
                    .workflow_definition_safe = true,
                }}),
                .outcomes = &.{.ok},
                .side_effect = .none,
            },
            .binding = @import("application/workflow_operation_binding.zig").bind(@import("workflow_binding_test_fixture.zig").ModelContext, &@import("workflow_binding_test_fixture.zig").model_context, @import("workflow_binding_test_fixture.zig").unusedModel),
        },
        .{
            .contract = .{
                .id = "test.noop",
                .kind = .step,
                .outcomes = &.{.ok},
                .side_effect = .none,
            },
            .binding = @import("application/workflow_operation_binding.zig").bind(void, null, unusedOperation),
        },
    },
    .policies = &.{.{
        .id = "test.safe@1",
        .allowed_capabilities = &.{requirement.capability_id},
        .allowed_terminal_outcomes = &.{.ok},
    }},
    .gates = &.{},
};

const binding_only_entries = blk: {
    var entries = operation_registry.operations[0..3].*;
    entries[1].binding = @import("application/workflow_operation_binding.zig").bind(void, null, unusedOperation);
    break :blk entries;
};
const binding_only_registry: operations.Registry = .{
    .operations = &binding_only_entries,
    .policies = &.{.{
        .id = "test.safe@1",
        .allowed_capabilities = &.{},
        .allowed_terminal_outcomes = &.{.ok},
    }},
    .gates = &.{},
};

fn unusedOperation(_: ?*void, _: operations.Input) operations.Error!execution.Candidate {
    return error.InvocationFailureUnrecorded;
}

const provider_id = identity.ProviderId.parse("compiled-provider").?;
const compiled_provider_contracts: contracts.Registry = .{ .entries = &.{.{
    .provider = provider_id,
    .model = identity.ModelId.parse("model-a").?,
    .implementation_id = contracts.RegisteredProviderImplementationId.init(1).?,
    .facts = .deadline_only,
    .capabilities = @import("model_contract_test_fixture.zig").capabilities,
    .supported_reasoning_efforts = &.{"low"},
}} };

const provider_document =
    \\{"providers":[{"provider":"compiled-provider","models":[{"model":"model-a","json": false, "config":{"requestTimeoutMs":1000}}]}]}
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
    \\{"logs":{"level":"info","console":false},"workflowTokenBudget":100000,"temperature":0.1,"temperatureRunawayRetry":1,"models":{"slots":
    ;
}

fn toolkitSuffix() []const u8 {
    return
    \\},"paths":{"specs":"specs","references":"references","specsArchive":"specs/archive","workflows":"workflows","toolchainPreset":"presets","principles":"principles","templates":"templates","providers":".sddproviders.json"}}
    ;
}
