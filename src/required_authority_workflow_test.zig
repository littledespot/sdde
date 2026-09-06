const std = @import("std");
const a = @import("domain/required_authority.zig");
const test_data = @import("required_authority_test.zig");
const native = @import("application/required_authority_workflow.zig");
const owned = @import("application/required_authority_values.zig");
const values = @import("application/pipeline_values.zig");
const pipeline = @import("domain/pipeline.zig");
const execution = @import("domain/workflow_execution.zig");
const workflow = @import("domain/workflow.zig");
const compilation = @import("domain/workflow_compilation.zig");
const operations = @import("ports/workflow_operation_registry.zig");
const binding = @import("application/workflow_operation_binding.zig");
const core = @import("composition/core_workflow_operations.zig");
const runner_module = @import("application/workflow_pipeline_runner.zig");
const children = @import("application/workflow_engine_child_bindings.zig");

const yaml =
    \\schema: workflow/v1
    \\id: authority-review
    \\version: 1
    \\shortcode: AUTH
    \\invoke: core.empty-invocation
    \\policy: core.capability-free@1
    \\start: inputs
    \\steps:
    \\  inputs: { use: test.authority-inputs, on: { ok: build } }
    \\  build: { use: build-required-authority-ledger, on: { ok: observe, blocked: end.blocked } }
    \\  observe: { use: test.authority-observation, on: { ok: parse } }
    \\  parse: { use: parse-required-authority-observations, on: { ok: reconcile, blocked: end.blocked } }
    \\  reconcile: { use: reconcile-required-authorities, on: { ok: validate, needs_user: validate, blocked: validate } }
    \\  validate: { use: validate-required-authority-reconciliation, on: { ok: protected, needs_user: end.needs_user, blocked: end.blocked } }
    \\  protected: { use: test.authority-protected, on: { ok: end.ok } }
;
const Fault = enum { none, missing_support, conflict, stale, unknown, malformed };
const Script = struct {
    allocator: std.mem.Allocator,
    kind: a.Kind = .feature_intent,
    fault: Fault = .none,
    calls: usize = 0,
    fn inputs(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        var source = test_data.fixture(owner.arena.allocator(), self.kind) catch return error.OperationExecutionFailed;
        switch (self.fault) {
            .none, .malformed => {},
            .missing_support => source.evidence = &.{},
            .conflict => {
                source.forced_gaps = owner.arena.allocator().dupe(a.ForcedGap, &.{.{ .requirement = source.seeds[0].id, .reason = .conflicting }}) catch return error.OperationExecutionFailed;
            },
            .stale => source.candidates = &.{},
            .unknown => {
                const seeds = owner.arena.allocator().dupe(a.Seed, source.seeds) catch return error.OperationExecutionFailed;
                seeds[0].id.contract_version = 999;
                source.seeds = seeds;
                source.evidence = &.{};
                source.candidates = &.{};
            },
        }
        owner.payload = .{ .inputs = source };
        return owned.publish(self.allocator, native.inputs_schema, owner, .ok) catch return error.OperationExecutionFailed;
    }
    fn observation(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        const source = owned.read(&input.step.data, native.inputs_schema, .inputs) catch return error.OperationExecutionFailed;
        const observations = test_data.observe(owner.arena.allocator(), source) catch return error.OperationExecutionFailed;
        owner.payload = .{ .raw = if (self.fault == .malformed) "{\"score\":100,\"passed\":true}" else std.json.Stringify.valueAlloc(owner.arena.allocator(), observations, .{}) catch return error.OperationExecutionFailed };
        return owned.publish(self.allocator, native.raw_schema, owner, .ok) catch return error.OperationExecutionFailed;
    }
    fn protected(context: ?*@This(), _: operations.Input) operations.Error!execution.Candidate {
        context.?.calls += 1;
        return .{ .outcome = .ok, .delta = .{} };
    }
};

const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    script: Script,
    build: native.Build,
    parse: native.Parse,
    reconcile: native.Reconcile,
    validate: native.Validate,
    registry: operations.Registry,
    fn init(self: *Fixture, allocator: std.mem.Allocator, kind: a.Kind, fault: Fault) !void {
        self.* = .{ .arena = .init(allocator), .script = .{ .allocator = allocator, .kind = kind, .fault = fault }, .build = .{ .allocator = allocator }, .parse = .{ .allocator = allocator }, .reconcile = .{ .allocator = allocator }, .validate = .{ .allocator = allocator }, .registry = undefined };
        errdefer self.arena.deinit();
        const entry = @import("composition/native_workflow_operations.zig").entry;
        const entries = core.entries ++ [_]operations.Entry{
            entry(native.Build, &self.build),                                                                                                                                                                                        entry(native.Parse, &self.parse),                                                                                                                                                                                                                                                        entry(native.Reconcile, &self.reconcile),                                                                                                                                                                                      entry(native.Validate, &self.validate),
            .{ .contract = .{ .id = "test.authority-inputs", .kind = .step, .produces = &.{.required_authority_inputs}, .outcomes = &.{.ok}, .side_effect = .none }, .binding = binding.bind(Script, &self.script, Script.inputs) }, .{ .contract = .{ .id = "test.authority-observation", .kind = .step, .requires = &.{.required_authority_inputs}, .produces = &.{.raw_required_authority_observations}, .outcomes = &.{.ok}, .side_effect = .none }, .binding = binding.bind(Script, &self.script, Script.observation) }, .{ .contract = .{ .id = "test.authority-protected", .kind = .step, .gates = &.{native.gate_contract.id.bytes}, .outcomes = &.{.ok}, .side_effect = .none }, .binding = binding.bind(Script, &self.script, Script.protected) },
        };
        self.registry = .{ .operations = try self.arena.allocator().dupe(operations.Entry, &entries), .data_schemas = &native.schemas, .gates = &.{native.gate_contract}, .policies = &core.profiles };
        try std.testing.expect(self.registry.validate());
    }
    fn compile(self: *Fixture, bytes: []const u8) !*const compilation.CompiledWorkflow {
        const allocator = self.arena.allocator();
        var parser: @import("adapters/parsers/workflow_definitions.zig").Adapter = .{};
        const raw = try (@import("actions/workflow/parse_workflow_definitions.zig").Action{ .parser = parser.parser() }).execute(allocator, &.{.{ .ordinal = 1, .bytes = bytes }});
        const definitions = try (@import("actions/workflow/validate_workflow_definition_schema.zig").Action{}).execute(allocator, raw);
        var schemas: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
        const graphs = try (@import("actions/workflow/compile_workflow_graphs.zig").Action{ .registry = &self.registry, .result_schema_compiler = schemas.compiler() }).execute(allocator, definitions, .{ .capability = undefined, .descriptors = &.{}, .accounts = &.{}, .definition_ordinals = &.{}, .resource_ordinals = &.{} }, .{ .bindings = &.{}, .resource_ordinals = &.{} }, &.{});
        _ = try (@import("actions/workflow/validate_compiled_workflow_graphs.zig").Action{}).execute(allocator, graphs);
        return &graphs[0];
    }
    fn runner(self: *Fixture, graph: *const compilation.CompiledWorkflow) runner_module.Runner {
        return runner_module.Runner.init(self.script.allocator, .{ .graph = graph, .invocation = .{ .workflow_id = graph.authority.workflow_id, .arguments = &.{} } }, &self.registry, .{ .context = &self.script, .process_fn = log }, .{}, null);
    }
    fn log(_: *anyopaque, _: @import("domain/telemetry.zig").WorkflowTelemetryFact) @import("domain/feature_log_stream.zig").Outcome {
        return .dropped;
    }
};

const Harness = struct {
    runner: *runner_module.Runner,
    graph: *const compilation.CompiledWorkflow,
    fn run(self: *Harness) workflow.OutcomeTag {
        return @import("application/workflow_engine_orchestrator.zig").run(.{ .context = self, .vtable = &.{ .validate_operation_registry = selection, .parse_invocation = selection, .select_workflow = selection, .prepare_workflow = preparation, .selected_graph = graphView, .invoke_invocation = invoke, .invoke_step = step } }).executionStatus().?;
    }
    fn selection(_: *anyopaque) children.SelectionStepOutcome {
        return .ok;
    }
    fn preparation(_: *anyopaque) children.PreparationOutcome {
        return .ok;
    }
    fn graphView(context: *const anyopaque) *const compilation.CompiledWorkflow {
        const self: *const Harness = @ptrCast(@alignCast(context));
        return self.graph;
    }
    fn invoke(context: *anyopaque) execution.Applied {
        const self: *Harness = @ptrCast(@alignCast(context));
        return self.runner.bindings().invokeInvocation();
    }
    fn step(context: *anyopaque, id: workflow.WorkflowStepId) execution.Applied {
        const self: *Harness = @ptrCast(@alignCast(context));
        return self.runner.bindings().invokeStep(id);
    }
};

test "unrelated compiled YAML workflows use native authority operations and preserve every gap" {
    for ([_]a.Kind{ .feature_intent, .design_decision, .executable_decomposition }) |kind| for (std.enums.values(Fault)) |fault| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator, kind, fault);
        defer fixture.arena.deinit();
        const name = try std.mem.replaceOwned(u8, fixture.arena.allocator(), @tagName(kind), "_", "-");
        const bytes = try std.mem.replaceOwned(u8, fixture.arena.allocator(), yaml, "authority-review", name);
        const graph = try fixture.compile(bytes);
        var runner = fixture.runner(graph);
        defer runner.deinit();
        var harness: Harness = .{ .runner = &runner, .graph = graph };
        const expected: workflow.OutcomeTag = switch (fault) {
            .none => .ok,
            .unknown, .malformed => .blocked,
            .missing_support, .conflict, .stale => .needs_user,
        };
        try std.testing.expectEqual(expected, harness.run());
        try std.testing.expectEqual(@as(usize, if (fault == .none) 1 else 0), fixture.script.calls);
    };
}

test "YAML cannot skip validation or route a rejected authority gate into protected work" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .feature_intent, .missing_support);
    defer fixture.arena.deinit();
    const bypass = try std.mem.replaceOwned(u8, fixture.arena.allocator(), yaml, "ok: protected, needs_user: end.needs_user, blocked: end.blocked", "ok: protected, needs_user: protected, blocked: protected");
    const graph = try fixture.compile(bypass);
    var runner = fixture.runner(graph);
    defer runner.deinit();
    var harness: Harness = .{ .runner = &runner, .graph = graph };
    try std.testing.expectEqual(.blocked, harness.run());
    try std.testing.expectEqual(@as(usize, 0), fixture.script.calls);
    const skipped = try std.mem.replaceOwned(u8, fixture.arena.allocator(), yaml, "ok: validate, needs_user: validate, blocked: validate", "ok: protected, needs_user: protected, blocked: protected");
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, fixture.compile(skipped));
}

test "authority gate tracks every current input generation and cannot be issued by another operation" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .feature_intent, .none);
    defer fixture.arena.deinit();
    const graph = try fixture.compile(yaml);
    var runner = fixture.runner(graph);
    defer runner.deinit();
    var harness: Harness = .{ .runner = &runner, .graph = graph };
    try std.testing.expectEqual(.ok, harness.run());
    const key = native.inputs_schema.key;
    const prior = runner.envelope.slots[@intFromEnum(key)].?;
    const owner = try owned.create(std.testing.allocator, .{ .slots = runner.envelope.slots });
    owner.payload = owned.payload(try values.read(&.{ .slots = runner.envelope.slots }, native.inputs_schema, owned.Value)).*;
    var changed = try owned.publish(std.testing.allocator, native.inputs_schema, owner, .ok);
    defer runner.envelope.discard(&changed.delta);
    changed.delta.data_replacements[@intFromEnum(key)] = changed.delta.data_writes[@intFromEnum(key)];
    changed.delta.data_writes[@intFromEnum(key)] = null;
    try runner.envelope.apply(.{ .id = "test.refresh", .kind = .action, .requires = &.{key}, .produces = &.{}, .replaces = &.{key}, .side_effect = .none }, &changed.delta, .ok);
    try std.testing.expect(prior != runner.envelope.slots[@intFromEnum(key)].?);
    try std.testing.expectEqual(.stale_authority, runner.bindings().invokeStep(.{ .bytes = "protected" }).rejected.gate);
    try std.testing.expectEqual(@as(usize, 1), fixture.script.calls);
    const entries = try fixture.arena.allocator().dupe(operations.Entry, fixture.registry.operations);
    entries[0].contract.produces = &.{.required_authority_gate};
    fixture.registry.operations = entries;
    try std.testing.expect(!fixture.registry.validate());
}

test "native authority bindings release inputs and partial results at every allocation failure" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .feature_intent, .none);
    defer fixture.arena.deinit();
    const graph = try fixture.compile(yaml);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationRun, .{ &fixture, graph });
}

test "malformed authority result cannot downgrade contract rejection to a clarification" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator, .feature_intent, .none);
    defer fixture.arena.deinit();
    const graph = try fixture.compile(yaml);
    var runner = fixture.runner(graph);
    defer runner.deinit();
    var harness: Harness = .{ .runner = &runner, .graph = graph };
    try std.testing.expectEqual(.ok, harness.run());
    var view = try runner.envelope.view(native.Validate.Action.contract);
    var result = try owned.read(&view, native.result_schema, .result);
    result.continuation = .needs_user;
    const owner = try owned.create(std.testing.allocator, view);
    var transferred = false;
    defer if (!transferred) owned.destroy(owner);
    owner.payload = .{ .result = result };
    var forged = try owned.publish(std.testing.allocator, native.result_schema, owner, .ok);
    transferred = true;
    defer runner.envelope.discard(&forged.delta);
    view.slots[@intFromEnum(native.result_schema.key)] = forged.delta.data_writes[@intFromEnum(native.result_schema.key)];
    const step = for (graph.authority.steps) |*step| {
        if (std.mem.eql(u8, step.id.bytes, "validate")) break step;
    } else return error.ExpectedValidationStep;
    var rejected = try native.Validate.invoke(&fixture.validate, .{ .step = .{ .data = view, .step = step, .resources = &.{}, .model_binding = null, .log = .init(graph.shortcode) } });
    defer runner.envelope.discard(&rejected.delta);
    try std.testing.expectEqual(.blocked, rejected.outcome);
    const decision = try values.read(&.{ .slots = rejected.delta.data_writes }, native.gate_schema, @import("domain/workflow_gate.zig").Decision);
    try std.testing.expectEqual(.rejected, decision.*);
}

fn allocationRun(allocator: std.mem.Allocator, fixture: *Fixture, graph: *const compilation.CompiledWorkflow) !void {
    fixture.script.allocator = allocator;
    fixture.script.calls = 0;
    fixture.build.allocator = allocator;
    fixture.parse.allocator = allocator;
    fixture.reconcile.allocator = allocator;
    fixture.validate.allocator = allocator;
    var runner = fixture.runner(graph);
    defer runner.deinit();
    var harness: Harness = .{ .runner = &runner, .graph = graph };
    const outcome = harness.run();
    if (outcome == .failed) return error.OutOfMemory;
    try std.testing.expectEqual(.ok, outcome);
    try std.testing.expectEqual(@as(usize, 1), fixture.script.calls);
}
