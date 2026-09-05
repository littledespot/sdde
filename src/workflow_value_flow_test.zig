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
const gate = @import("domain/workflow_gate.zig");

const input_schema = values.schema(.workflow_invocation, execution.Invocation, 1, 1024);
const level_schema = values.schema(.canonical_log_level, log_policy.CanonicalizedLevel, 1, 256);
const evidence_schema = values.schema(.workflow_operation_registry_evidence, gate.Decision, 1, 32);
const schemas = [_]data.Schema{ level_schema, input_schema, evidence_schema };
const gate_contract: gate.Contract = .{
    .id = .{ .bytes = "test.current-input@1" },
    .issuer = .{ .bytes = "test.validate@1" },
    .evidence = evidence_schema.key,
    .authority = &.{input_schema.key},
};

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
    try std.testing.expectEqual(workflow.OutcomeTag.failed, runner.bindings().invokeInvocation().status());
    try std.testing.expectEqual(@as(usize, 0), control.invocations);
}

test "compiler rejects missing duplicate and invalid data schemas" {
    var control: Control = .{};
    var fixture = try Fixture.init(&control, linear_yaml);
    defer fixture.deinit();
    fixture.registry.data_schemas = &.{};
    try std.testing.expect(!fixture.registry.validate());
    fixture.registry.data_schemas = &.{ input_schema, level_schema, evidence_schema, level_schema };
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
    for (&entries) |*entry| entry.binding.context = &control;
    fixture.registry.operations = &entries;
    try std.testing.expect(fixture.registry.validate());
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

test "unrelated YAML workflows enforce current evidence and cannot route around rejection" {
    inline for (.{ "guarded-preview", "release-audit" }) |id| {
        inline for (.{ gate.Decision.accepted, gate.Decision.rejected }) |decision| {
            var control: Control = .{ .decision = decision };
            const yaml = try std.mem.replaceOwned(u8, std.testing.allocator, guarded_yaml, "guarded-preview", id);
            defer std.testing.allocator.free(yaml);
            var fixture = try Fixture.init(&control, yaml);
            defer fixture.deinit();
            var runner = fixture.runner(&control);
            defer runner.deinit();
            var children: EngineBindings = .{ .runner = &runner, .graph = fixture.graph };
            const expected: workflow.OutcomeTag = if (decision == .accepted) .ok else .blocked;
            try std.testing.expectEqual(expected, engine.run(children.bind()).execution);
            try std.testing.expectEqual(@as(usize, if (decision == .accepted) 1 else 0), control.observations);
        }
    }
}

test "authority replacement invalidates evidence even for identical bytes and explicit validation renews it" {
    var control: Control = .{};
    var fixture = try Fixture.init(&control, guarded_yaml);
    defer fixture.deinit();
    var runner = fixture.runner(&control);
    defer runner.deinit();
    try prepareGate(&runner);
    const refresh: pipeline.NodeContract = .{ .id = "test.refresh@1", .kind = .action, .requires = &.{input_schema.key}, .produces = &.{}, .replaces = &.{input_schema.key}, .side_effect = .none };
    const input = try runner.envelope.view(refresh);
    const current = try values.read(&input, input_schema, execution.Invocation);
    var delta: pipeline.NodeDelta = .{};
    defer runner.envelope.discard(&delta);
    delta.data_replacements[@intFromEnum(input_schema.key)] = try values.create(std.testing.allocator, input_schema, execution.Invocation, current.*);
    try runner.envelope.apply(refresh, &delta, .ok);
    const stale = runner.bindings().invokeStep(.{ .bytes = "guarded" });
    try std.testing.expectEqual(gate.Rejection.stale_authority, stale.rejected.gate);
    try std.testing.expectEqual(@as(usize, 0), control.observations);

    const invalidate: pipeline.NodeContract = .{ .id = "test.invalidate-proof@1", .kind = .action, .requires = &.{}, .produces = &.{}, .invalidates = &.{evidence_schema.key}, .side_effect = .none };
    var invalidation: pipeline.NodeDelta = .{ .data_invalidations = .initOne(evidence_schema.key) };
    try runner.envelope.apply(invalidate, &invalidation, .ok);
    try std.testing.expectEqual(workflow.OutcomeTag.ok, runner.bindings().invokeStep(.{ .bytes = "validate" }).status());
    try std.testing.expectEqual(workflow.OutcomeTag.ok, runner.bindings().invokeStep(.{ .bytes = "guarded" }).status());
    try std.testing.expectEqual(@as(usize, 1), control.observations);
}

test "a logging barrier rejection cannot continue from the evidence issuer through YAML" {
    var control: Control = .{ .block_logging = true };
    var fixture = try Fixture.init(&control, guarded_yaml);
    defer fixture.deinit();
    var runner = fixture.runner(&control);
    defer runner.deinit();
    var children: EngineBindings = .{ .runner = &runner, .graph = fixture.graph };
    try std.testing.expectEqual(workflow.OutcomeTag.blocked, engine.run(children.bind()).execution);
    try std.testing.expectEqual(@as(usize, 0), control.observations);
}

test "missing foreign and unsuccessful evidence cannot authorize execution" {
    inline for (.{ gate.Rejection.missing_evidence, .missing_authority, .foreign_issuer, .rejected_evidence }) |reason| {
        var control: Control = .{};
        var fixture = try Fixture.init(&control, guarded_yaml);
        defer fixture.deinit();
        var runner = fixture.runner(&control);
        defer runner.deinit();
        try prepareGate(&runner);
        var delta: pipeline.NodeDelta = .{};
        defer runner.envelope.discard(&delta);
        if (reason == .missing_evidence or reason == .missing_authority) {
            const key = if (reason == .missing_evidence) evidence_schema.key else input_schema.key;
            const contract: pipeline.NodeContract = .{ .id = "test.remove@1", .kind = .action, .requires = &.{}, .produces = &.{}, .invalidates = &.{key}, .side_effect = .none };
            delta.data_invalidations.insert(key);
            try runner.envelope.apply(contract, &delta, .ok);
        } else {
            const contract: pipeline.NodeContract = .{ .id = if (reason == .foreign_issuer) "test.foreign@1" else gate_contract.issuer.bytes, .kind = .action, .requires = &.{input_schema.key}, .produces = &.{}, .replaces = &.{evidence_schema.key}, .side_effect = .none };
            delta.data_replacements[@intFromEnum(evidence_schema.key)] = try values.create(std.testing.allocator, evidence_schema, gate.Decision, .accepted);
            try runner.envelope.apply(contract, &delta, if (reason == .rejected_evidence) .failed else .ok);
        }
        const result = runner.bindings().invokeStep(.{ .bytes = "guarded" });
        try std.testing.expectEqual(@as(gate.Rejection, reason), result.rejected.gate);
        try std.testing.expectEqual(@as(usize, 0), control.observations);
    }
}

test "gate boundary preserves cancellation and deadlines before and after checking evidence" {
    inline for (.{ pipeline.RuntimeStatus.cancelled, .deadline_exhausted }) |terminal| {
        for (0..3) |checks| {
            var control: Control = .{};
            var fixture = try Fixture.init(&control, guarded_yaml);
            defer fixture.deinit();
            var runner = fixture.runner(&control);
            defer runner.deinit();
            try prepareGate(&runner);
            var countdown: GateCountdown = .{ .remaining = checks, .terminal = terminal };
            runner.runtime = .{ .context = &countdown, .status_fn = GateCountdown.status };
            const result = runner.bindings().invokeStep(.{ .bytes = "guarded" });
            try std.testing.expect(result == .rejected);
            try std.testing.expectEqual(if (terminal == .cancelled) workflow.OutcomeTag.cancelled else .failed, result.status());
            try std.testing.expectEqual(@as(usize, 0), control.observations);
        }
    }
}

fn prepareGate(runner: *runner_module.Runner) !void {
    try std.testing.expectEqual(workflow.OutcomeTag.ok, runner.bindings().invokeInvocation().status());
    try std.testing.expectEqual(workflow.OutcomeTag.ok, runner.bindings().invokeStep(.{ .bytes = "normalize" }).status());
    try std.testing.expectEqual(workflow.OutcomeTag.ok, runner.bindings().invokeStep(.{ .bytes = "validate" }).status());
}

test "gate registration rejects ambiguous issuers missing authority and invalid evidence schemas" {
    var control: Control = .{};
    var fixture = try Fixture.init(&control, guarded_yaml);
    defer fixture.deinit();
    const Invalid = enum { duplicate_id, duplicate_evidence, empty_authority, duplicate_authority, evidence_as_authority, unknown_issuer, missing_input, foreign_producer, evidence_schema };
    inline for (std.meta.tags(Invalid)) |reason| {
        var registry = fixture.registry;
        var contracts = [_]gate.Contract{ gate_contract, gate_contract };
        var entries = operation_entries;
        for (&entries) |*entry| entry.binding.context = &control;
        registry.operations = &entries;
        registry.gates = contracts[0..1];
        try std.testing.expect(registry.validate());
        switch (reason) {
            .duplicate_id => registry.gates = &contracts,
            .duplicate_evidence => {
                contracts[1].id.bytes = "test.second@1";
                registry.gates = &contracts;
            },
            .empty_authority => contracts[0].authority = &.{},
            .duplicate_authority => contracts[0].authority = &.{ input_schema.key, input_schema.key },
            .evidence_as_authority => contracts[0].authority = &.{evidence_schema.key},
            .unknown_issuer => contracts[0].issuer.bytes = "test.missing@1",
            .missing_input => contracts[0].authority = &.{level_schema.key},
            .foreign_producer => entries[4].contract.produces = &.{evidence_schema.key},
            .evidence_schema => registry.data_schemas = &.{ input_schema, level_schema, values.schema(evidence_schema.key, bool, 1, 32) },
        }
        try std.testing.expect(!registry.validate());
    }
}

test "compiler requires explicit evidence production before protected operations" {
    var control: Control = .{};
    const yaml = try std.mem.replaceOwned(u8, std.testing.allocator, guarded_yaml, "  normalize: { use: test.normalize@1, on: { ok: validate } }\n  validate: { use: test.validate@1, on: { ok: guarded, blocked: bypass } }", "  normalize: { use: test.normalize@1, on: { ok: guarded } }");
    defer std.testing.allocator.free(yaml);
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, Fixture.init(&control, yaml));
}

test "runner rejects changed gate contracts policy ceilings and compiled capability claims" {
    const Drift = enum { gate_authority, policy_ceiling, compiled_capabilities };
    inline for (std.meta.tags(Drift)) |drift| {
        var control: Control = .{};
        var fixture = try Fixture.init(&control, guarded_yaml);
        defer fixture.deinit();
        var runner = fixture.runner(&control);
        defer runner.deinit();
        try prepareGate(&runner);
        var changed_gate = gate_contract;
        var changed_policy = fixture.registry.policies[0];
        var changed_entries = operation_entries;
        for (&changed_entries) |*entry| entry.binding.context = &control;
        var graph = fixture.graph.*;
        const steps = try fixture.arena.allocator().dupe(compilation.CompiledStep, graph.authority.steps);
        switch (drift) {
            .gate_authority => {
                changed_gate.authority = &.{level_schema.key};
                changed_entries[6].contract.requires = &.{ input_schema.key, level_schema.key };
                fixture.registry.operations = &changed_entries;
                fixture.registry.gates = (&changed_gate)[0..1];
            },
            .policy_ceiling => {
                changed_policy.allowed_capabilities = &.{"model-provider"};
                fixture.registry.policies = (&changed_policy)[0..1];
            },
            .compiled_capabilities => {
                for (steps) |*step| if (std.mem.eql(u8, step.id.bytes, "guarded")) {
                    step.capabilities = &.{"model-provider"};
                };
                graph.authority.steps = steps;
                runner.selected.graph = &graph;
            },
        }
        try std.testing.expect(fixture.registry.validate());
        const result = runner.bindings().invokeStep(.{ .bytes = "guarded" });
        try std.testing.expect(result.rejected == .authority);
        try std.testing.expectEqual(@as(usize, 0), control.observations);
    }
}

test "rejected deltas and exhausted generations preserve previously validated gate authority" {
    inline for (.{ false, true }) |exhausted| {
        var control: Control = .{};
        var fixture = try Fixture.init(&control, guarded_yaml);
        defer fixture.deinit();
        var runner = fixture.runner(&control);
        defer runner.deinit();
        try prepareGate(&runner);
        const contract: pipeline.NodeContract = .{ .id = "test.replace@1", .kind = .action, .requires = &.{input_schema.key}, .produces = &.{}, .replaces = &.{input_schema.key}, .side_effect = .none };
        const input = try runner.envelope.view(contract);
        const current = try values.read(&input, input_schema, execution.Invocation);
        var delta: pipeline.NodeDelta = .{};
        defer runner.envelope.discard(&delta);
        var schema = input_schema;
        if (exhausted) runner.envelope.generation = std.math.maxInt(u64) else schema.version += 1;
        const before = runner.envelope.generation;
        delta.data_replacements[@intFromEnum(input_schema.key)] = try values.create(std.testing.allocator, schema, execution.Invocation, current.*);
        try std.testing.expectError(if (exhausted) error.DataGenerationExhausted else error.DataSchemaMismatch, runner.envelope.apply(contract, &delta, .ok));
        try std.testing.expectEqual(before, runner.envelope.generation);
        try std.testing.expectEqual(@as(?gate.Rejection, null), runner.envelope.checkGate(gate_contract));
    }
}

const GateCountdown = struct {
    remaining: usize,
    terminal: pipeline.RuntimeStatus,
    fn status(context: ?*anyopaque) pipeline.RuntimeStatus {
        const self: *GateCountdown = @ptrCast(@alignCast(context.?));
        if (self.remaining == 0) return self.terminal;
        self.remaining -= 1;
        return .active;
    }
};

const Fault = enum { none, schema_version, throw_after_allocation, cancel_after_allocation, deadline_after_allocation, undeclared_outcome };
const Control = struct {
    decision: gate.Decision = .accepted,
    block_logging: bool = false,
    fault: Fault = .none,
    branch: workflow.OutcomeTag = .ok,
    status: pipeline.RuntimeStatus = .active,
    invocations: usize = 0,
    observations: usize = 0,
    observed: ?telemetry.CanonicalLogLevel = null,
    inputs_hidden: bool = false,

    fn invoke(context: ?*Control, input: registry_module.Input) registry_module.Error!execution.Candidate {
        const self = context.?;
        self.invocations += 1;
        const invocation = (parse_invocation.Action{}).execute(input.invocation.arguments) catch return error.OperationExecutionFailed;
        if (invocation.arguments.len != 1) return error.OperationExecutionFailed;
        var delta: pipeline.NodeDelta = .{};
        delta.data_writes[@intFromEnum(input_schema.key)] = values.create(std.testing.allocator, input_schema, execution.Invocation, invocation) catch return error.OperationExecutionFailed;
        return .{ .outcome = .ok, .delta = delta };
    }

    fn normalize(context: ?*Control, input: registry_module.Input) registry_module.Error!execution.Candidate {
        const self = context.?;
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

    fn replace(_: ?*Control, input: registry_module.Input) registry_module.Error!execution.Candidate {
        const current = values.read(&input.step.data, level_schema, log_policy.CanonicalizedLevel) catch return error.OperationExecutionFailed;
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(level_schema.key)] = values.create(std.testing.allocator, level_schema, log_policy.CanonicalizedLevel, current.*) catch return error.OperationExecutionFailed;
        return .{ .outcome = .ok, .delta = delta };
    }

    fn route(context: ?*Control, input: registry_module.Input) registry_module.Error!execution.Candidate {
        const self = context.?;
        if (input.step.data.contains(.canonical_log_level)) return error.OperationExecutionFailed;
        return .{ .outcome = self.branch, .delta = .{} };
    }

    fn observe(context: ?*Control, input: registry_module.Input) registry_module.Error!execution.Candidate {
        const self = context.?;
        const level = values.read(&input.step.data, level_schema, log_policy.CanonicalizedLevel) catch return error.OperationExecutionFailed;
        self.observations += 1;
        self.observed = level.threshold;
        self.inputs_hidden = !input.step.data.contains(.workflow_invocation);
        return .{ .outcome = .ok, .delta = .{} };
    }

    fn clear(_: ?*Control, _: registry_module.Input) registry_module.Error!execution.Candidate {
        return .{ .outcome = .ok, .delta = .{ .data_invalidations = .initOne(.workflow_invocation) } };
    }

    fn validate(context: ?*Control, input: registry_module.Input) registry_module.Error!execution.Candidate {
        _ = values.read(&input.step.data, input_schema, execution.Invocation) catch return error.OperationExecutionFailed;
        var delta: pipeline.NodeDelta = .{};
        input.step.log.log(&delta, .{ .event_type = .action_completed }) catch return error.OperationExecutionFailed;
        delta.data_writes[@intFromEnum(evidence_schema.key)] = values.create(std.testing.allocator, evidence_schema, gate.Decision, context.?.decision) catch return error.OperationExecutionFailed;
        return .{ .outcome = .ok, .delta = delta };
    }

    fn runtimeStatus(context: ?*anyopaque) pipeline.RuntimeStatus {
        const self: *Control = @ptrCast(@alignCast(context.?));
        return self.status;
    }

    fn log(context: *anyopaque, _: telemetry.WorkflowTelemetryFact) log_stream.Outcome {
        const self: *Control = @ptrCast(@alignCast(context));
        if (self.block_logging) return .{ .blocked = .LOG_SINK_FAILURE };
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
        for (entries) |*entry| entry.binding.context = control;
        const registry: registry_module.Registry = .{
            .operations = entries,
            .data_schemas = &schemas,
            .gates = &.{gate_contract},
            .policies = &.{.{ .id = "test.safe@1", .allowed_capabilities = &.{}, .allowed_terminal_outcomes = &.{.ok}, .total_model_token_budget = .{ .value = 100 } }},
        };
        var parser: parser_adapter.Adapter = .{};
        const raw = try (parse.Action{ .parser = parser.parser() }).execute(arena.allocator(), &.{.{ .ordinal = 1, .bytes = yaml }});
        const definitions = try (validate_schema.Action{}).execute(arena.allocator(), raw);
        var result_schema_parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
        const graphs = try (compile.Action{ .registry = &registry, .result_schema_compiler = result_schema_parser.compiler() }).execute(arena.allocator(), definitions, .{ .capability = undefined, .descriptors = &.{}, .accounts = &.{}, .definition_ordinals = &.{}, .resource_ordinals = &.{} }, .{ .bindings = &.{}, .resource_ordinals = &.{} }, &.{});
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
    .{ .contract = .{ .id = "test.input@1", .kind = .invocation, .produces = &.{.workflow_invocation}, .outcomes = &.{.ok}, .side_effect = .none }, .binding = @import("application/workflow_operation_binding.zig").bind(Control, null, Control.invoke) },
    .{ .contract = .{ .id = "test.normalize@1", .kind = .step, .requires = &.{.workflow_invocation}, .produces = &.{.canonical_log_level}, .outcomes = &.{.ok}, .side_effect = .none }, .binding = @import("application/workflow_operation_binding.zig").bind(Control, null, Control.normalize) },
    .{ .contract = .{ .id = "test.replace@1", .kind = .step, .optional = &.{.canonical_log_level}, .replaces = &.{.canonical_log_level}, .outcomes = &.{.ok}, .side_effect = .none }, .binding = @import("application/workflow_operation_binding.zig").bind(Control, null, Control.replace) },
    .{ .contract = .{ .id = "test.route@1", .kind = .step, .requires = &.{.workflow_invocation}, .optional = &.{.canonical_log_level}, .outcomes = &.{ .ok, .invalid }, .side_effect = .none }, .binding = @import("application/workflow_operation_binding.zig").bind(Control, null, Control.route) },
    .{ .contract = .{ .id = "test.observe@1", .kind = .step, .requires = &.{.canonical_log_level}, .outcomes = &.{.ok}, .side_effect = .none }, .binding = @import("application/workflow_operation_binding.zig").bind(Control, null, Control.observe) },
    .{ .contract = .{ .id = "test.clear@1", .kind = .step, .invalidates = &.{.workflow_invocation}, .outcomes = &.{.ok}, .side_effect = .none }, .binding = @import("application/workflow_operation_binding.zig").bind(Control, null, Control.clear) },
    .{ .contract = .{ .id = "test.validate@1", .kind = .step, .requires = &.{.workflow_invocation}, .produces = &.{.workflow_operation_registry_evidence}, .outcomes = &.{ .ok, .blocked }, .side_effect = .none }, .binding = @import("application/workflow_operation_binding.zig").bind(Control, null, Control.validate) },
    .{ .contract = .{ .id = "test.guarded@1", .kind = .step, .requires = &.{.canonical_log_level}, .gates = &.{"test.current-input@1"}, .outcomes = &.{ .ok, .blocked }, .side_effect = .none }, .binding = @import("application/workflow_operation_binding.zig").bind(Control, null, Control.observe) },
};

const guarded_yaml =
    \\schema: workflow/v1
    \\id: guarded-preview
    \\version: 1
    \\shortcode: GPRE
    \\invoke: test.input@1
    \\policy: test.safe@1
    \\start: normalize
    \\steps:
    \\  normalize: { use: test.normalize@1, on: { ok: validate } }
    \\  validate: { use: test.validate@1, on: { ok: guarded, blocked: bypass } }
    \\  guarded: { use: test.guarded@1, on: { ok: end.ok, blocked: bypass } }
    \\  bypass: { use: test.observe@1, on: { ok: end.ok } }
;

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
