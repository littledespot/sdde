const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const workflow = @import("../../domain/workflow.zig");
const definition = @import("../../domain/workflow_definition.zig");
const compilation = @import("../../domain/workflow_compilation.zig");
const workflow_retry = @import("../../domain/workflow_retry.zig");

pub const Error = error{WorkflowGraphCompileInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-compiled-workflow-graphs@1",
        .kind = .action,
        .requires = &.{.compiled_workflow_graphs},
        .produces = &.{.validated_workflow_graphs},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        allocator: std.mem.Allocator,
        graphs: []const compilation.CompiledWorkflow,
    ) Error!compilation.ValidatedGraphs {
        for (graphs) |graph| try validateGraph(allocator, graph);
        return .{ .values = graphs };
    }
};

const key_count = @typeInfo(pipeline.DataKey).@"enum".fields.len;
const KeyState = [key_count]bool;

fn validateGraph(allocator: std.mem.Allocator, graph: compilation.CompiledWorkflow) Error!void {
    const steps = graph.authority.steps;
    try validateDataSchemas(graph.authority);
    if (steps.len == 0 or steps.len > definition.max_steps or
        !graph.authority.total_model_token_budget.isValid() or
        graph.authority.maximum_step_executions != (compilation.calculateExecutionLimit(steps) orelse return invalid())) return invalid();
    for (steps) |step| {
        if (!@import("../../domain/workflow_capability.zig").permits(graph.authority.allowed_capabilities, step.capabilities)) return invalid();
        if (!@import("../../domain/workflow_model.zig").validProjection(step)) return invalid();
        const retry_parameter = findParameter(step.parameters, workflow_retry.parameter_id);
        if (step.retry_authority) |authority| {
            if (!authority.isValid() or
                !std.mem.eql(u8, authority.workflow_id.bytes, graph.authority.workflow_id.bytes) or
                authority.workflow_version != graph.authority.workflow_version or
                !std.mem.eql(u8, authority.operation_instance_id.bytes, step.id.bytes) or
                retry_parameter == null or retry_parameter.?.value != .integer or
                retry_parameter.?.value.integer < 0 or
                authority.limit.value != retry_parameter.?.value.integer)
            {
                return invalid();
            }
        } else if (retry_parameter != null) {
            return invalid();
        }
    }
    const start = stepIndex(steps, graph.authority.start_step_id.bytes) orelse return invalid();
    try validateReachability(allocator, steps, graph.authority.transitions, start);
    try validateTerminalReachability(allocator, steps, graph.authority.transitions);
    try validateBoundedCycles(allocator, steps, graph.authority.transitions);
    try validateDataFlow(allocator, graph, start);
}

fn validateDataSchemas(authority: compilation.SemanticAuthority) Error!void {
    var required: KeyState = @splat(false);
    for (authority.invocation_outputs) |key| required[@intFromEnum(key)] = true;
    for (authority.steps) |step| {
        for (step.gates) |gate| {
            required[@intFromEnum(gate.evidence)] = true;
            for (gate.authority) |key| required[@intFromEnum(key)] = true;
        }
        inline for (.{ step.requires, step.optional, step.produces, step.replaces, step.invalidates }) |keys| {
            for (keys) |key| required[@intFromEnum(key)] = true;
        }
    }
    var seen: KeyState = @splat(false);
    for (authority.data_schemas) |schema| {
        const index = @intFromEnum(schema.key);
        if (!schema.valid() or seen[index] or !required[index]) return invalid();
        seen[index] = true;
    }
    if (!std.mem.eql(bool, &required, &seen)) return invalid();
}

fn validateReachability(
    allocator: std.mem.Allocator,
    steps: []const compilation.CompiledStep,
    transitions: []const workflow.Transition,
    start: usize,
) Error!void {
    const reached = allocator.alloc(bool, steps.len) catch return invalid();
    @memset(reached, false);
    var queue: std.ArrayList(usize) = .empty;
    queue.append(allocator, start) catch return invalid();
    reached[start] = true;
    var cursor: usize = 0;
    while (cursor < queue.items.len) : (cursor += 1) {
        const index = queue.items[cursor];
        for (transitions) |transition| {
            if (!std.mem.eql(u8, transition.from.bytes, steps[index].id.bytes)) continue;
            if (transition.target == .step) {
                const target = stepIndex(steps, transition.target.step.bytes) orelse return invalid();
                if (!reached[target]) {
                    reached[target] = true;
                    queue.append(allocator, target) catch return invalid();
                }
            }
        }
    }
    for (reached) |value| if (!value) return invalid();
}

fn validateTerminalReachability(
    allocator: std.mem.Allocator,
    steps: []const compilation.CompiledStep,
    transitions: []const workflow.Transition,
) Error!void {
    const reaches_terminal = allocator.alloc(bool, steps.len) catch return invalid();
    @memset(reaches_terminal, false);
    for (steps, 0..) |step, index| {
        for (transitions) |transition| {
            if (std.mem.eql(u8, transition.from.bytes, step.id.bytes) and transition.target == .terminal) {
                reaches_terminal[index] = true;
                break;
            }
        }
    }
    var changed = true;
    while (changed) {
        changed = false;
        for (steps, 0..) |step, index| {
            if (reaches_terminal[index]) continue;
            for (transitions) |transition| {
                if (!std.mem.eql(u8, transition.from.bytes, step.id.bytes) or transition.target != .step) continue;
                const target = stepIndex(steps, transition.target.step.bytes) orelse return invalid();
                if (reaches_terminal[target]) {
                    reaches_terminal[index] = true;
                    changed = true;
                    break;
                }
            }
        }
    }
    for (reaches_terminal) |value| if (!value) return invalid();
}

fn validateBoundedCycles(
    allocator: std.mem.Allocator,
    steps: []const compilation.CompiledStep,
    transitions: []const workflow.Transition,
) Error!void {
    const colors = allocator.alloc(u2, steps.len) catch return invalid();
    @memset(colors, 0);
    for (steps, 0..) |step, index| {
        if (step.retry_authority != null or colors[index] != 0) continue;
        try visitUnguarded(steps, transitions, index, colors);
    }
}

fn visitUnguarded(
    steps: []const compilation.CompiledStep,
    transitions: []const workflow.Transition,
    index: usize,
    colors: []u2,
) Error!void {
    if (colors[index] == 1) return invalid();
    if (colors[index] == 2 or steps[index].retry_authority != null) return;
    colors[index] = 1;
    for (transitions) |transition| {
        if (!std.mem.eql(u8, transition.from.bytes, steps[index].id.bytes) or transition.target != .step) continue;
        const target = stepIndex(steps, transition.target.step.bytes) orelse return invalid();
        if (steps[target].retry_authority == null) try visitUnguarded(steps, transitions, target, colors);
    }
    colors[index] = 2;
}

fn validateDataFlow(allocator: std.mem.Allocator, graph: compilation.CompiledWorkflow, start: usize) Error!void {
    const steps = graph.authority.steps;
    const inputs = allocator.alloc(?KeyState, steps.len) catch return invalid();
    @memset(inputs, null);
    var initial = [_]bool{false} ** key_count;
    for (graph.authority.invocation_outputs) |key| {
        if (initial[@intFromEnum(key)]) return invalid();
        initial[@intFromEnum(key)] = true;
    }
    inputs[start] = initial;
    var queue: std.ArrayList(usize) = .empty;
    queue.append(allocator, start) catch return invalid();
    var cursor: usize = 0;
    while (cursor < queue.items.len) : (cursor += 1) {
        const index = queue.items[cursor];
        const output = try applyDataContract(inputs[index].?, steps[index]);
        for (graph.authority.transitions) |transition| {
            if (!std.mem.eql(u8, transition.from.bytes, steps[index].id.bytes) or transition.target != .step) continue;
            const target = stepIndex(steps, transition.target.step.bytes) orelse return invalid();
            if (inputs[target]) |existing| {
                if (!std.mem.eql(bool, &existing, &output)) return invalid();
            } else {
                inputs[target] = output;
                queue.append(allocator, target) catch return invalid();
            }
        }
    }
}

fn applyDataContract(input: KeyState, step: compilation.CompiledStep) Error!KeyState {
    var result = input;
    for (step.gates) |gate| {
        if (!input[@intFromEnum(gate.evidence)]) return invalid();
        for (gate.authority) |key| if (!input[@intFromEnum(key)]) return invalid();
    }
    for (step.requires) |key| if (!input[@intFromEnum(key)]) return invalid();
    for (step.produces) |key| {
        if (result[@intFromEnum(key)]) return invalid();
        result[@intFromEnum(key)] = true;
    }
    for (step.replaces) |key| if (!result[@intFromEnum(key)]) return invalid();
    for (step.invalidates) |key| {
        if (!result[@intFromEnum(key)]) return invalid();
        result[@intFromEnum(key)] = false;
    }
    return result;
}

fn stepIndex(steps: []const compilation.CompiledStep, expected: []const u8) ?usize {
    for (steps, 0..) |step, index| if (std.mem.eql(u8, step.id.bytes, expected)) return index;
    return null;
}
fn findParameter(parameters: []const compilation.CompiledParameter, id: []const u8) ?compilation.CompiledParameter {
    for (parameters) |parameter| if (std.mem.eql(u8, parameter.id.bytes, id)) return parameter;
    return null;
}
fn invalid() Error {
    return error.WorkflowGraphCompileInvalid;
}

fn testStep(id: []const u8, retry_limit: ?u32) compilation.CompiledStep {
    return .{
        .id = workflow.WorkflowStepId.parse(id).?,
        .operation_id = workflow.RegisteredRef.parse("core.noop@1").?,
        .parameters = if (retry_limit == null) &.{} else &test_retry_parameters,
        .requires = &.{},
        .produces = &.{},
        .replaces = &.{},
        .invalidates = &.{},
        .outcomes = &.{ .ok, .failed },
        .side_effect = .none,
        .gates = &.{},
        .capabilities = &.{},
        .retry_authority = if (retry_limit) |limit| .{
            .workflow_id = workflow.WorkflowId.parse("graph-test").?,
            .workflow_version = 1,
            .operation_instance_id = workflow.WorkflowStepId.parse(id).?,
            .limit = .{ .value = limit },
        } else null,
    };
}

const test_retry_parameters = [_]compilation.CompiledParameter{.{
    .id = workflow.WorkflowParameterId.parse(workflow_retry.parameter_id).?,
    .value = .{ .integer = 2 },
}};

fn testGraph(steps: []const compilation.CompiledStep, transitions: []const workflow.Transition) compilation.CompiledWorkflow {
    return .{
        .source_ordinal = 1,
        .shortcode = @import("../../domain/telemetry.zig").WorkflowShortcode.parse("TEST") catch unreachable,
        .authority = .{
            .workflow_id = workflow.WorkflowId.parse("graph-test").?,
            .workflow_version = 1,
            .invocation_operation_id = workflow.RegisteredRef.parse("core.empty@1").?,
            .policy_profile_id = workflow.RegisteredRef.parse("core.safe@1").?,
            .total_model_token_budget = .{ .value = 1 },
            .start_step_id = steps[0].id,
            .invocation_outputs = &.{},
            .resources = &.{},
            .steps = steps,
            .transitions = transitions,
            .maximum_step_executions = steps.len * 3,
        },
    };
}

test "accepts a guarded cycle and rejects the same unguarded cycle" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const guarded_steps = [_]compilation.CompiledStep{ testStep("guard", 2), testStep("work", null) };
    const transitions = [_]workflow.Transition{
        .{ .from = guarded_steps[0].id, .outcome = .ok, .target = .{ .step = guarded_steps[1].id } },
        .{ .from = guarded_steps[0].id, .outcome = .failed, .target = .{ .terminal = .failed } },
        .{ .from = guarded_steps[1].id, .outcome = .ok, .target = .{ .step = guarded_steps[0].id } },
        .{ .from = guarded_steps[1].id, .outcome = .failed, .target = .{ .terminal = .failed } },
    };
    _ = try (Action{}).execute(arena.allocator(), &.{testGraph(&guarded_steps, &transitions)});

    var wrong_bound = testGraph(&guarded_steps, &transitions);
    wrong_bound.authority.maximum_step_executions -= 1;
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        (Action{}).execute(arena.allocator(), &.{wrong_bound}),
    );

    var zero_budget = testGraph(&guarded_steps, &transitions);
    zero_budget.authority.total_model_token_budget = .{ .value = 0 };
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        (Action{}).execute(arena.allocator(), &.{zero_budget}),
    );

    var wrong_retry_steps = guarded_steps;
    wrong_retry_steps[0].retry_authority.?.operation_instance_id = workflow.WorkflowStepId.parse("work").?;
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        (Action{}).execute(arena.allocator(), &.{testGraph(&wrong_retry_steps, &transitions)}),
    );

    var mismatched_retry_steps = guarded_steps;
    mismatched_retry_steps[0].retry_authority.?.limit = .{ .value = 1 };
    var mismatched_retry_graph = testGraph(&mismatched_retry_steps, &transitions);
    mismatched_retry_graph.authority.maximum_step_executions = compilation.calculateExecutionLimit(&mismatched_retry_steps).?;
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        (Action{}).execute(arena.allocator(), &.{mismatched_retry_graph}),
    );

    var unguarded_steps = guarded_steps;
    unguarded_steps[0].retry_authority = null;
    unguarded_steps[0].parameters = &.{};
    var unguarded_graph = testGraph(&unguarded_steps, &transitions);
    unguarded_graph.authority.maximum_step_executions = compilation.calculateExecutionLimit(&unguarded_steps).?;
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        (Action{}).execute(arena.allocator(), &.{unguarded_graph}),
    );
}
