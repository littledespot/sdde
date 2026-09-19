const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const workflow = @import("../../domain/workflow.zig");
const definition = @import("../../domain/workflow_definition.zig");
const compilation = @import("../../domain/workflow_compilation.zig");
const workflow_retry = @import("../../domain/workflow_retry.zig");

pub const Error = error{WorkflowGraphCompileInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-compiled-workflow-graphs",
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
    for (graph.authority.transitions) |transition| if (transition.target == .terminal and transition.target.terminal == .more) return invalid();
    if (workflow.OperationId.parse(graph.authority.invocation_operation_id.bytes) == null) return invalid();
    try validateDataSchemas(graph.authority);
    if (steps.len == 0 or steps.len > definition.max_steps or
        !compilation.publicationTerminates(graph.authority) or
        !compilation.validResourceBindings(graph.authority.resources) or
        !graph.authority.total_model_token_budget.isValid() or
        graph.authority.maximum_step_executions != (compilation.calculateExecutionLimit(steps) orelse return invalid())) return invalid();
    for (steps) |step| {
        if (!@import("../../domain/workflow_operation.zig").validRepair(step.repair_role, if (step.retry_authority) |value| value.scope else null, step.runner_accounting, step.side_effect)) return invalid();
        if (step.repair_role != .none and step.capabilities.len != 0) return invalid();
        if (workflow.WorkflowStepId.parse(step.id.bytes) == null or workflow.OperationId.parse(step.operation_id.bytes) == null) return invalid();
        if (!@import("../../domain/workflow_operation.zig").validAccounting(step.runner_accounting, step.requires, step.produces, step.side_effect, step.retry_authority != null)) return invalid();
        if (!@import("../../domain/workflow_capability.zig").permits(graph.authority.allowed_capabilities, step.capabilities)) return invalid();
        if (!@import("../../domain/workflow_model.zig").validProjection(step)) return invalid();
        if (!@import("../../domain/workflow_model_request_lifecycle.zig").validProjection(step)) return invalid();
        if (!@import("../../domain/workflow_provider_operation.zig").validProjection(step)) return invalid();
        if (!@import("../../domain/workflow_provider_authorization.zig").validProjection(step)) return invalid();
        if (!@import("../../domain/workflow_model_invocation.zig").validProjection(step)) return invalid();
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
    const flow = @import("../../domain/workflow_data_flow.zig").analyze(allocator, graph.authority) catch return invalid();
    allocator.free(flow);
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

test "bounded progress can never be a compiled workflow terminal state" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var step = testStep("start", null);
    step.outcomes = &.{ .ok, .more };
    const transitions = [_]workflow.Transition{
        .{ .from = step.id, .outcome = .ok, .target = .{ .terminal = .ok } },
        .{ .from = step.id, .outcome = .more, .target = .{ .terminal = .more } },
    };
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, (Action{}).execute(arena.allocator(), &.{testGraph(&.{step}, &transitions)}));
}

test "publication ends every outcome directly without a later pure or effectful operation" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var publication = testStep("publish", null);
    publication.side_effect = .workflow_publication;
    publication.outcomes = &.{ .ok, .needs_user, .failed };
    const terminal = [_]workflow.Transition{
        .{ .from = publication.id, .outcome = .ok, .target = .{ .terminal = .ok } },
        .{ .from = publication.id, .outcome = .needs_user, .target = .{ .terminal = .needs_user } },
        .{ .from = publication.id, .outcome = .failed, .target = .{ .terminal = .failed } },
    };
    var accepted = testGraph(&.{publication}, &terminal);
    accepted.authority.maximum_step_executions = compilation.calculateExecutionLimit(accepted.authority.steps).?;
    _ = try (Action{}).execute(a, &.{accepted});
    for ([_]pipeline.SideEffect{ .none, .filesystem_read, .filesystem_write, .model_call, .workflow_publication }) |effect| {
        var after = testStep("later", null);
        after.side_effect = effect;
        for (0..terminal.len) |redirected| {
            var transitions = terminal ++ [_]workflow.Transition{
                .{ .from = after.id, .outcome = .ok, .target = .{ .terminal = .ok } },
                .{ .from = after.id, .outcome = .failed, .target = .{ .terminal = .failed } },
            };
            transitions[redirected].target = .{ .step = after.id };
            var rejected = testGraph(&.{ publication, after }, &transitions);
            rejected.authority.maximum_step_executions = compilation.calculateExecutionLimit(rejected.authority.steps).?;
            try std.testing.expect(!compilation.publicationTerminates(rejected.authority));
            try std.testing.expectError(error.WorkflowGraphCompileInvalid, (Action{}).execute(a, &.{rejected}));
        }
    }
    var loop = terminal;
    loop[0].target = .{ .step = publication.id };
    accepted.authority.transitions = &loop;
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, (Action{}).execute(a, &.{accepted}));
    var wrong_terminal = terminal;
    wrong_terminal[1].target = .{ .terminal = .ok };
    accepted.authority.transitions = &wrong_terminal;
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, (Action{}).execute(a, &.{accepted}));
}

test "separate workflow branches may each select their own terminal publication" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const select = testStep("select", null);
    var first = testStep("first-output", null);
    first.side_effect = .workflow_publication;
    var second = testStep("second-output", null);
    second.side_effect = .workflow_publication;
    const transitions = [_]workflow.Transition{
        .{ .from = select.id, .outcome = .ok, .target = .{ .step = first.id } },
        .{ .from = select.id, .outcome = .failed, .target = .{ .step = second.id } },
        .{ .from = first.id, .outcome = .ok, .target = .{ .terminal = .ok } },
        .{ .from = first.id, .outcome = .failed, .target = .{ .terminal = .failed } },
        .{ .from = second.id, .outcome = .ok, .target = .{ .terminal = .ok } },
        .{ .from = second.id, .outcome = .failed, .target = .{ .terminal = .failed } },
    };
    var graph = testGraph(&.{ select, first, second }, &transitions);
    graph.authority.maximum_step_executions = compilation.calculateExecutionLimit(graph.authority.steps).?;
    _ = try (Action{}).execute(arena.allocator(), &.{graph});
}

fn testStep(id: []const u8, retry_limit: ?u32) compilation.CompiledStep {
    return .{
        .id = workflow.WorkflowStepId.parse(id).?,
        .operation_id = workflow.OperationId.parse("core.noop").?,
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
            .invocation_operation_id = workflow.OperationId.parse("core.empty").?,
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
