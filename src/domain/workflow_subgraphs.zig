//! Pure expansion of definition-local reuse into ordinary operation steps.
//! Operation contracts and graph validators remain the policy owners.
const std = @import("std");
const d = @import("workflow_definition.zig");
const w = @import("workflow.zig");
pub const Error = std.mem.Allocator.Error || error{InvalidWorkflowSubgraph};
pub const Expansion = struct { start: w.WorkflowStepId, steps: []const w.DeclarativeStep };

pub fn expand(allocator: std.mem.Allocator, source: d.Definition) Error!Expansion {
    if (source.steps.len + source.calls.len == 0 or source.steps.len + source.calls.len > d.max_steps or source.subgraphs.len > d.max_subgraphs) return invalid();
    for (source.subgraphs, 0..) |subgraph, index| {
        if (subgraph.steps.len == 0 or subgraph.steps.len > d.max_steps) return invalid();
        for (source.subgraphs[0..index]) |prior| if (same(prior.id.bytes, subgraph.id.bytes)) return invalid();
        var used = false;
        for (source.calls) |call| if (same(call.subgraph.bytes, subgraph.id.bytes)) {
            used = true;
        };
        if (!used) return invalid();
    }
    var steps: std.ArrayList(w.DeclarativeStep) = .empty;
    for (source.steps) |step| {
        for (source.calls) |call| if (same(step.id.bytes, call.id.bytes)) return invalid();
        var copy = step;
        const outcomes = try allocator.dupe(w.OutcomeTransition, step.outcomes);
        for (outcomes) |*edge| edge.target = try topTarget(allocator, source, edge.target);
        copy.outcomes = outcomes;
        try steps.append(allocator, copy);
    }
    for (source.calls, 0..) |call, index| {
        for (source.calls[0..index]) |prior| if (same(prior.id.bytes, call.id.bytes)) return invalid();
        const subgraph = try find(source, call.subgraph);
        try validateBindings(subgraph, call);
        if (subgraph.steps.len > d.max_steps - steps.items.len) return invalid();
        for (subgraph.steps) |local| {
            const parameters = try allocator.alloc(w.ParameterBinding, local.parameters.len);
            for (local.parameters, parameters) |parameter, *bound| {
                bound.* = .{ .id = parameter.id, .value = switch (parameter.value) {
                    .literal => |value| value,
                    .parameter => |id| try binding(call.parameters, id),
                } };
            }
            std.mem.sort(w.ParameterBinding, parameters, {}, parameterLessThan);
            const outcomes = try allocator.dupe(w.OutcomeTransition, local.outcomes);
            for (outcomes) |*edge| edge.target = switch (edge.target) {
                .step => |id| .{ .step = try localId(allocator, call, subgraph, id) },
                .terminal => |exit| try topTarget(allocator, source, try exitTarget(call, exit)),
            };
            try steps.append(allocator, .{
                .id = try localId(allocator, call, subgraph, local.id),
                .operation_id = local.operation_id,
                .parameters = parameters,
                .outcomes = outcomes,
            });
        }
    }
    std.mem.sort(w.DeclarativeStep, steps.items, {}, stepLessThan);
    for (steps.items, 0..) |step, index| if (index > 0 and same(step.id.bytes, steps.items[index - 1].id.bytes)) return invalid();
    const start = try topTarget(allocator, source, .{ .step = source.start_step_id });
    return .{ .start = start.step, .steps = try steps.toOwnedSlice(allocator) };
}

fn find(source: d.Definition, id: d.SubgraphId) Error!d.Subgraph {
    for (source.subgraphs) |subgraph| if (same(subgraph.id.bytes, id.bytes)) return subgraph;
    return invalid();
}

fn topTarget(allocator: std.mem.Allocator, source: d.Definition, target: w.TransitionTarget) Error!w.TransitionTarget {
    return switch (target) {
        .terminal => target,
        .step => |id| value: {
            for (source.steps) |step| if (same(step.id.bytes, id.bytes)) break :value target;
            for (source.calls) |call| if (same(call.id.bytes, id.bytes)) {
                const subgraph = try find(source, call.subgraph);
                break :value .{ .step = try localId(allocator, call, subgraph, subgraph.start) };
            };
            return invalid();
        },
    };
}

fn localId(allocator: std.mem.Allocator, call: d.SubgraphCall, subgraph: d.Subgraph, id: w.WorkflowStepId) Error!w.WorkflowStepId {
    var count: usize = 0;
    for (subgraph.steps) |step| if (same(step.id.bytes, id.bytes)) {
        count += 1;
    };
    if (count != 1) return invalid();
    // Length-delimited call identity prevents ambiguity between nested names.
    const bytes = try std.fmt.allocPrint(allocator, "g{d}-{s}-{s}", .{ call.id.bytes.len, call.id.bytes, id.bytes });
    return w.WorkflowStepId.parse(bytes) orelse invalid();
}

fn binding(bindings: []const w.ParameterBinding, id: w.WorkflowParameterId) Error!w.ParameterValue {
    var result: ?w.ParameterValue = null;
    for (bindings) |parameter| if (same(parameter.id.bytes, id.bytes)) {
        if (result != null) return invalid();
        result = parameter.value;
    };
    return result orelse invalid();
}

fn exitTarget(call: d.SubgraphCall, outcome: w.OutcomeTag) Error!w.TransitionTarget {
    var result: ?w.TransitionTarget = null;
    for (call.outcomes) |edge| if (edge.outcome == outcome) {
        if (result != null) return invalid();
        result = edge.target;
    };
    const target = result orelse return invalid();
    if (target == .terminal and target.terminal != outcome) return invalid();
    return target;
}

fn validateBindings(subgraph: d.Subgraph, call: d.SubgraphCall) Error!void {
    for (call.parameters) |parameter| {
        var used = false;
        for (subgraph.steps) |step| for (step.parameters) |reference| {
            if (reference.value == .parameter and same(reference.value.parameter.bytes, parameter.id.bytes)) used = true;
        };
        if (!used) return invalid();
        _ = try binding(call.parameters, parameter.id);
    }
    var exits = [_]bool{false} ** @typeInfo(w.OutcomeTag).@"enum".fields.len;
    for (subgraph.steps) |step| {
        for (step.parameters) |parameter| if (parameter.value == .parameter) {
            _ = try binding(call.parameters, parameter.value.parameter);
        };
        for (step.outcomes) |edge| if (edge.target == .terminal) {
            if (edge.target.terminal != edge.outcome) return invalid();
            exits[@intFromEnum(edge.target.terminal)] = true;
            _ = try exitTarget(call, edge.target.terminal);
        };
    }
    for (call.outcomes) |edge| if (!exits[@intFromEnum(edge.outcome)]) return invalid();
}

fn same(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn parameterLessThan(_: void, a: w.ParameterBinding, b: w.ParameterBinding) bool {
    return std.mem.order(u8, a.id.bytes, b.id.bytes) == .lt;
}
fn stepLessThan(_: void, a: w.DeclarativeStep, b: w.DeclarativeStep) bool {
    return std.mem.order(u8, a.id.bytes, b.id.bytes) == .lt;
}
fn invalid() Error {
    return error.InvalidWorkflowSubgraph;
}
