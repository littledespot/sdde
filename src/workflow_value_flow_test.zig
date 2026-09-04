const std = @import("std");
const pipeline = @import("domain/pipeline.zig");
const data = @import("domain/pipeline_data.zig");
const execution = @import("domain/workflow_execution.zig");
const workflow = @import("domain/workflow.zig");
const compilation = @import("domain/workflow_compilation.zig");
const log_policy = @import("domain/log_policy.zig");
const log_stream = @import("domain/feature_log_stream.zig");
const telemetry = @import("domain/telemetry.zig");
const values = @import("application/pipeline_values.zig");
const runner_module = @import("application/workflow_pipeline_runner.zig");
const engine = @import("application/workflow_engine_orchestrator.zig");
const bindings = @import("application/workflow_engine_child_bindings.zig");
const registry_module = @import("ports/workflow_operation_registry.zig");
const parse = @import("actions/workflow/parse_workflow_definitions.zig");
const validate_schema = @import("actions/workflow/validate_workflow_definition_schema.zig");
const compile = @import("actions/workflow/compile_workflow_graphs.zig");
const validate_graphs = @import("actions/workflow/validate_compiled_workflow_graphs.zig");
const parser_adapter = @import("adapters/parsers/workflow_definitions.zig");
const parse_invocation = @import("actions/workflow/parse_workflow_invocation.zig");

const input_schema = values.schema(.workflow_invocation, execution.Invocation, 1, 1024);
const level_schema = values.schema(.canonical_log_level, log_policy.CanonicalizedLevel, 1, 256);
const schemas = [_]data.Schema{ level_schema, input_schema };

test "unrelated YAML workflows carry typed invocation values through replacement and branch merges" {
    inline for (.{ linear_yaml, branching_yaml }) |yaml| {
        inline for (.{ workflow.OutcomeTag.ok, .invalid }) |branch| {
            var control: Control = .{ .branch = branch };
            var fixture = try Fixture.init(&control, yaml);
            defer fixture.deinit();
            try std.testing.expectEqual(@as(usize, 2), fixture.graph.authority.data_schemas.len);
            var runner = fixture.runner(&control);
            defer runner.deinit();
            var children: EngineBindings = .{ .runner = &runner, .graph = fixture.graph };
            try std.testing.expectEqual(workflow.OutcomeTag.ok, engine.run(children.bind()).execution);
            try std.testing.expectEqual(@as(usize, 1), control.observations);
            try std.testing.expect(control.inputs_hidden);
            try std.testing.expectEqual(telemetry.CanonicalLogLevel.warning, control.observed.?);
            const cleared: pipeline.NodeContract = .{ .id = "test.cleared@1", .kind = .action, .requires = &.{.workflow_invocation}, .produces = &.{}, .side_effect = .none };
            try std.testing.expectError(error.MissingRequiredData, runner.envelope.view(cleared));
        }
    }
}

test "runtime rejects schema drift and releases candidates on cancellation invalid output and errors" {
    inline for (.{ Fault.schema_version, .throw_after_allocation, .cancel_after_allocation, .deadline_after_allocation, .undeclared_outcome }) |fault| {
        var control: Control = .{ .fault = fault };
        var fixture = try Fixture.init(&control, linear_yaml);
        defer fixture.deinit();
        var runner = fixture.runner(&control);
        defer runner.deinit();
        var children: EngineBindings = .{ .runner = &runner, .graph = fixture.graph };
        const expected: workflow.OutcomeTag = switch (@as(Fault, fault)) {
            .schema_version => .invalid,
            .cancel_after_allocation => .cancelled,
            .throw_after_allocation, .deadline_after_allocation, .undeclared_outcome => .failed,
            .none => unreachable,
        };
        try std.testing.expectEqual(expected, engine.run(children.bind()).execution);
        try std.testing.expectEqual(@as(usize, 0), control.observations);
        const missing: pipeline.NodeContract = .{ .id = "test.missing@1", .kind = .action, .requires = &.{.canonical_log_level}, .produces = &.{}, .side_effect = .none };
        try std.testing.expectError(error.MissingRequiredData, runner.envelope.view(missing));
    }
    var control: Control = .{};
    var fixture = try Fixture.init(&control, linear_yaml);
    defer fixture.deinit();
    var changed_schemas = schemas;
    changed_schemas[0].version += 1;
    fixture.registry.data_schemas = &changed_schemas;
    var runner = fixture.runner(&control);
    defer runner.deinit();
    try std.testing.expectEqual(workflow.OutcomeTag.failed, runner.bindings().invokeInvocation().outcome);
    try std.testing.expectEqual(@as(usize, 0), control.invocations);
}

test "compiler rejects missing duplicate and invalid data schemas" {
    var control: Control = .{};
    var fixture = try Fixture.init(&control, linear_yaml);
    defer fixture.deinit();
    fixture.registry.data_schemas = &.{};
    try std.testing.expect(!fixture.registry.validate());
    fixture.registry.data_schemas = &.{ input_schema, level_schema, level_schema };
    try std.testing.expect(!fixture.registry.validate());
    var invalid = schemas;
    invalid[0].maximum_bytes = 0;
    fixture.registry.data_schemas = &invalid;
    try std.testing.expect(!fixture.registry.validate());
    var graph = fixture.graph.*;
    graph.authority.data_schemas = &.{input_schema};
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, (validate_graphs.Action{}).execute(fixture.arena.allocator(), &.{graph}));
    fixture.registry.data_schemas = &schemas;
    var entries = operation_entries;
    fixture.registry.operations = &entries;
    entries[1].contract.optional = entries[1].contract.requires;
    try std.testing.expect(!fixture.registry.validate());
    entries[1].contract.optional = &.{ .canonical_log_level, .canonical_log_level };
    try std.testing.expect(!fixture.registry.validate());
}

test "runner checks required inputs before invoking an operation" {
    var control: Control = .{};
    var fixture = try Fixture.init(&control, linear_yaml);
    defer fixture.deinit();
    var runner = fixture.runner(&control);
    defer runner.deinit();
    try std.testing.expectEqual(workflow.OutcomeTag.invalid, runner.bindings().invokeStep(.{ .bytes = "observe" }).outcome);
    try std.testing.expectEqual(@as(usize, 0), control.observations);
}

const Fault = enum { none, schema_version, throw_after_allocation, cancel_after_allocation, deadline_after_allocation, undeclared_outcome };
const Control = struct {
    fault: Fault = .none,
    branch: workflow.OutcomeTag = .ok,
    status: pipeline.RuntimeStatus = .active,
    invocations: usize = 0,
    observations: usize = 0,
    observed: ?telemetry.CanonicalLogLevel = null,
    inputs_hidden: bool = false,

    fn invoke(context: ?*anyopaque, input: registry_module.Input) registry_module.Error!execution.Candidate {
        const self: *Control = @ptrCast(@alignCast(context.?));
        self.invocations += 1;
        const invocation = (parse_invocation.Action{}).execute(input.invocation.arguments) catch return error.OperationExecutionFailed;
        if (invocation.arguments.len != 1) return error.OperationExecutionFailed;
        var delta: pipeline.NodeDelta = .{};
        delta.data_writes[@intFromEnum(input_schema.key)] = values.create(std.testing.allocator, input_schema, execution.Invocation, invocation) catch return error.OperationExecutionFailed;
        return .{ .outcome = .ok, .delta = delta };
    }

    fn normalize(context: ?*anyopaque, input: registry_module.Input) registry_module.Error!execution.Candidate {
        const self: *Control = @ptrCast(@alignCast(context.?));
        const invocation = values.read(&input.step.data, input_schema, execution.Invocation) catch return error.OperationExecutionFailed;
        const level = log_policy.canonicalizeConfiguredLevel(invocation.arguments[0]) catch return error.OperationExecutionFailed;
        var schema = level_schema;
        if (self.fault == .schema_version) schema.version += 1;
        const value = values.create(std.testing.allocator, schema, log_policy.CanonicalizedLevel, level) catch return error.OperationExecutionFailed;
        errdefer values.destroy(value);
        if (self.fault == .throw_after_allocation) return error.OperationExecutionFailed;
        if (self.fault == .cancel_after_allocation) self.status = .cancelled;
        if (self.fault == .deadline_after_allocation) self.status = .deadline_exhausted;
        var delta: pipeline.NodeDelta = .{};
        delta.data_writes[@intFromEnum(level_schema.key)] = value;
        return .{ .outcome = if (self.fault == .undeclared_outcome) .blocked else .ok, .delta = delta };
    }

    fn replace(_: ?*anyopaque, input: registry_module.Input) registry_module.Error!execution.Candidate {
        const current = values.read(&input.step.data, level_schema, log_policy.CanonicalizedLevel) catch return error.OperationExecutionFailed;
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(level_schema.key)] = values.create(std.testing.allocator, level_schema, log_policy.CanonicalizedLevel, current.*) catch return error.OperationExecutionFailed;
        return .{ .outcome = .ok, .delta = delta };
    }

    fn route(context: ?*anyopaque, input: registry_module.Input) registry_module.Error!execution.Candidate {
        const self: *Control = @ptrCast(@alignCast(context.?));
        if (input.step.data.contains(.canonical_log_level)) return error.OperationExecutionFailed;
        return .{ .outcome = self.branch, .delta = .{} };
    }

    fn observe(context: ?*anyopaque, input: registry_module.Input) registry_module.Error!execution.Candidate {
        const self: *Control = @ptrCast(@alignCast(context.?));
        const level = values.read(&input.step.data, level_schema, log_policy.CanonicalizedLevel) catch return error.OperationExecutionFailed;
        self.observations += 1;
        self.observed = level.threshold;
        self.inputs_hidden = !input.step.data.contains(.workflow_invocation);
        return .{ .outcome = .ok, .delta = .{} };
    }

    fn clear(_: ?*anyopaque, _: registry_module.Input) registry_module.Error!execution.Candidate {
        return .{ .outcome = .ok, .delta = .{ .data_invalidations = .initOne(.workflow_invocation) } };
    }

    fn runtimeStatus(context: ?*anyopaque) pipeline.RuntimeStatus {
        const self: *Control = @ptrCast(@alignCast(context.?));
        return self.status;
    }

    fn log(_: *anyopaque, _: telemetry.WorkflowTelemetryFact) log_stream.Outcome {
        return .dropped;
    }
};

const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    graph: *const compilation.CompiledWorkflow,
    registry: registry_module.Registry,

    fn init(control: *Control, yaml: []const u8) !Fixture {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        errdefer arena.deinit();
        const entries = try arena.allocator().dupe(registry_module.Entry, &operation_entries);
        for (entries) |*entry| entry.context = control;
        const registry: registry_module.Registry = .{
            .operations = entries,
            .data_schemas = &schemas,
            .gates = &.{},
            .capabilities = &.{},
            .policies = &.{.{ .id = "test.safe@1", .allowed_capabilities = &.{}, .allowed_terminal_outcomes = &.{.ok}, .total_model_token_budget = .{ .value = 100 } }},
        };
        var parser: parser_adapter.Adapter = .{};
        const raw = try (parse.Action{ .parser = parser.parser() }).execute(arena.allocator(), &.{.{ .ordinal = 1, .bytes = yaml }});
        const definitions = try (validate_schema.Action{}).execute(arena.allocator(), raw);
        const graphs = try (compile.Action{ .registry = &registry }).execute(arena.allocator(), definitions, .{ .capability = undefined, .descriptors = &.{}, .accounts = &.{}, .definition_ordinals = &.{}, .resource_ordinals = &.{} }, .{ .bindings = &.{}, .resource_ordinals = &.{} }, &.{});
        _ = try (validate_graphs.Action{}).execute(arena.allocator(), graphs);
        return .{ .arena = arena, .graph = &graphs[0], .registry = registry };
    }

    fn runner(self: *const Fixture, control: *Control) runner_module.Runner {
        return runner_module.Runner.init(std.testing.allocator, .{ .graph = self.graph, .invocation = .{ .workflow_id = self.graph.authority.workflow_id, .arguments = &.{ "context", "WARN" } } }, &self.registry, .{ .context = control, .process_fn = Control.log }, .{ .context = control, .status_fn = Control.runtimeStatus }, null);
    }

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
    }
};

const EngineBindings = struct {
    runner: *runner_module.Runner,
    graph: *const compilation.CompiledWorkflow,
    fn bind(self: *EngineBindings) bindings.ChildBindings {
        return .{ .context = self, .vtable = &vtable };
    }
    fn selection(_: *anyopaque) bindings.SelectionStepOutcome {
        return .ok;
    }
    fn preparation(_: *anyopaque) bindings.PreparationOutcome {
        return .ok;
    }
    fn graphView(context: *const anyopaque) *const compilation.CompiledWorkflow {
        const self: *const EngineBindings = @ptrCast(@alignCast(context));
        return self.graph;
    }
    fn invoke(context: *anyopaque) execution.Applied {
        const self: *EngineBindings = @ptrCast(@alignCast(context));
        return self.runner.bindings().invokeInvocation();
    }
    fn step(context: *anyopaque, id: workflow.WorkflowStepId) execution.Applied {
        const self: *EngineBindings = @ptrCast(@alignCast(context));
        return self.runner.bindings().invokeStep(id);
    }
    const vtable: bindings.ChildBindings.VTable = .{ .validate_operation_registry = selection, .parse_invocation = selection, .select_workflow = selection, .prepare_workflow = preparation, .selected_graph = graphView, .invoke_invocation = invoke, .invoke_step = step };
};

const operation_entries = [_]registry_module.Entry{
    .{ .contract = .{ .id = "test.input@1", .kind = .invocation, .produces = &.{.workflow_invocation}, .outcomes = &.{.ok}, .side_effect = .none }, .invoke_fn = Control.invoke },
    .{ .contract = .{ .id = "test.normalize@1", .kind = .step, .requires = &.{.workflow_invocation}, .produces = &.{.canonical_log_level}, .outcomes = &.{.ok}, .side_effect = .none }, .invoke_fn = Control.normalize },
    .{ .contract = .{ .id = "test.replace@1", .kind = .step, .optional = &.{.canonical_log_level}, .replaces = &.{.canonical_log_level}, .outcomes = &.{.ok}, .side_effect = .none }, .invoke_fn = Control.replace },
    .{ .contract = .{ .id = "test.route@1", .kind = .step, .requires = &.{.workflow_invocation}, .optional = &.{.canonical_log_level}, .outcomes = &.{ .ok, .invalid }, .side_effect = .none }, .invoke_fn = Control.route },
    .{ .contract = .{ .id = "test.observe@1", .kind = .step, .requires = &.{.canonical_log_level}, .outcomes = &.{.ok}, .side_effect = .none }, .invoke_fn = Control.observe },
    .{ .contract = .{ .id = "test.clear@1", .kind = .step, .invalidates = &.{.workflow_invocation}, .outcomes = &.{.ok}, .side_effect = .none }, .invoke_fn = Control.clear },
};

const linear_yaml =
    \\schema: workflow/v1
    \\id: log-preview
    \\version: 1
    \\shortcode: PREV
    \\invoke: test.input@1
    \\policy: test.safe@1
    \\start: normalize
    \\steps:
    \\  normalize: { use: test.normalize@1, on: { ok: replace } }
    \\  replace: { use: test.replace@1, on: { ok: observe } }
    \\  observe: { use: test.observe@1, on: { ok: clear } }
    \\  clear: { use: test.clear@1, on: { ok: end.ok } }
;

const branching_yaml =
    \\schema: workflow/v1
    \\id: settings-audit
    \\version: 1
    \\shortcode: AUDT
    \\invoke: test.input@1
    \\policy: test.safe@1
    \\start: route
    \\steps:
    \\  route: { use: test.route@1, on: { ok: left, invalid: right } }
    \\  left: { use: test.normalize@1, on: { ok: observe } }
    \\  right: { use: test.normalize@1, on: { ok: observe } }
    \\  observe: { use: test.observe@1, on: { ok: clear } }
    \\  clear: { use: test.clear@1, on: { ok: end.ok } }
;
