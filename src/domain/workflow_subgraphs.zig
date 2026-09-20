//! Compile local composition into ordinary operations. The runtime never calls subgraphs.
const std = @import("std");
const d = @import("workflow_definition.zig");
const w = @import("workflow.zig");
pub const Error = std.mem.Allocator.Error || error{InvalidWorkflowSubgraph};
pub const Expansion = struct { start: w.WorkflowStepId, steps: []const w.DeclarativeStep };

pub fn expand(allocator: std.mem.Allocator, source: d.Definition) Error!Expansion {
    if (source.steps.len + source.calls.len == 0 or source.steps.len + source.calls.len > d.max_steps or source.subgraphs.len > d.max_subgraphs) return invalid();
    for (source.subgraphs, 0..) |subgraph, index| {
        for (source.subgraphs[0..index]) |prior| if (same(prior.id.bytes, subgraph.id.bytes)) return invalid();
    }
    // Normalize the root once; every composition level uses the same expander.
    const root = try allocator.alloc(d.SubgraphStep, source.steps.len + source.calls.len);
    for (source.steps, root[0..source.steps.len]) |step, *copy| copy.* = .{
        .id = step.id,
        .source = step.source,
        .target = .{ .operation = step.operation_id },
        .parameters = try literals(allocator, step.parameters),
        .outcomes = step.outcomes,
    };
    for (source.calls, root[source.steps.len..]) |call, *copy| copy.* = .{
        .id = call.id,
        .source = call.source,
        .target = .{ .subgraph = call.subgraph },
        .parameters = try literals(allocator, call.parameters),
        .outcomes = call.outcomes,
    };
    var compiler: Compiler = .{ .allocator = allocator, .subgraphs = source.subgraphs };
    const result = try compiler.scope(root, source.start_step_id, &.{}, null, &.{});
    for (compiler.used[0..source.subgraphs.len]) |used| if (!used) return invalid();
    const sorted = try allocator.dupe(w.DeclarativeStep, result.steps);
    std.mem.sort(w.DeclarativeStep, sorted, {}, stepLessThan);
    for (sorted, 0..) |step, index| if (index > 0 and same(step.id.bytes, sorted[index - 1].id.bytes)) return invalid();
    return .{ .start = result.start, .steps = sorted };
}

const Compiler = struct {
    allocator: std.mem.Allocator,
    subgraphs: []const d.Subgraph,
    active: [d.max_subgraphs]bool = @splat(false),
    used: [d.max_subgraphs]bool = @splat(false),

    fn scope(self: *Compiler, local: []const d.SubgraphStep, start: w.WorkflowStepId, bindings: []const w.ParameterBinding, prefix: ?w.WorkflowStepId, parents: []const @import("workflow_source.zig").Entry) Error!Expansion {
        if (local.len == 0 or local.len > d.max_steps) return invalid();
        try validateParameters(local, bindings);
        const parts = try self.allocator.alloc(Expansion, local.len);
        var count: usize = 0;
        for (local, parts, 0..) |step, *part, index| {
            for (local[0..index]) |prior| if (same(prior.id.bytes, step.id.bytes)) return invalid();
            const id = try qualified(self.allocator, prefix, step.id);
            const chain = if (step.source) |entry| try std.mem.concat(self.allocator, @import("workflow_source.zig").Entry, &.{ parents, &.{entry} }) else parents;
            const parameters = try self.allocator.alloc(w.ParameterBinding, step.parameters.len);
            for (step.parameters, parameters) |parameter, *bound| bound.* = .{
                .id = parameter.id,
                .value = switch (parameter.value) {
                    .literal => |value| value,
                    .parameter => |reference| try binding(bindings, reference),
                },
            };
            std.mem.sort(w.ParameterBinding, parameters, {}, parameterLessThan);
            part.* = switch (step.target) {
                .operation => |operation| value: {
                    const operations = try self.allocator.alloc(w.DeclarativeStep, 1);
                    operations[0] = .{ .source_chain = chain, .id = id, .operation_id = operation, .parameters = parameters, .outcomes = step.outcomes };
                    break :value .{ .start = id, .steps = operations };
                },
                .subgraph => |called| value: {
                    const selected = for (self.subgraphs, 0..) |subgraph, selected| {
                        if (same(subgraph.id.bytes, called.bytes)) break selected;
                    } else return invalid();
                    if (self.active[selected]) return invalid();
                    self.active[selected] = true;
                    defer self.active[selected] = false;
                    self.used[selected] = true;
                    const subgraph = self.subgraphs[selected];
                    try validateExits(subgraph.steps, step.outcomes);
                    break :value try self.scope(subgraph.steps, subgraph.start, parameters, id, chain);
                },
            };
            if (part.steps.len > d.max_steps - count) return invalid();
            count += part.steps.len;
        }
        const operations = try self.allocator.alloc(w.DeclarativeStep, count);
        var cursor: usize = 0;
        for (local, parts) |step, part| {
            for (part.steps) |operation| {
                const outcomes = try self.allocator.dupe(w.OutcomeTransition, operation.outcomes);
                for (outcomes) |*edge| {
                    // Child internal edges are already resolved. Only its exits belong
                    // to the caller's scope; ordinary operations have local edges.
                    if (step.target == .operation) {
                        edge.target = try resolve(local, parts, edge.target);
                    } else if (edge.target == .terminal) {
                        edge.target = try resolve(local, parts, try exitTarget(step.outcomes, edge.target.terminal));
                    }
                }
                operations[cursor] = operation;
                operations[cursor].outcomes = outcomes;
                cursor += 1;
            }
        }
        return .{ .start = (try resolve(local, parts, .{ .step = start })).step, .steps = operations };
    }
};

fn resolve(local: []const d.SubgraphStep, parts: []const Expansion, target: w.TransitionTarget) Error!w.TransitionTarget {
    return switch (target) {
        .terminal => target,
        .step => |id| for (local, parts) |step, part| {
            if (same(id.bytes, step.id.bytes)) break .{ .step = part.start };
        } else invalid(),
    };
}

fn qualified(allocator: std.mem.Allocator, prefix: ?w.WorkflowStepId, id: w.WorkflowStepId) Error!w.WorkflowStepId {
    const parent = prefix orelse return id;
    const bytes = try std.fmt.allocPrint(allocator, "g{d}-{s}-{s}", .{ parent.bytes.len, parent.bytes, id.bytes });
    return w.WorkflowStepId.parse(bytes) orelse invalid();
}

fn literals(allocator: std.mem.Allocator, parameters: []const w.ParameterBinding) Error![]const d.SubgraphParameter {
    const result = try allocator.alloc(d.SubgraphParameter, parameters.len);
    for (parameters, result) |parameter, *copy| copy.* = .{ .id = parameter.id, .value = .{ .literal = parameter.value } };
    return result;
}

fn binding(bindings: []const w.ParameterBinding, id: w.WorkflowParameterId) Error!w.ParameterValue {
    var result: ?w.ParameterValue = null;
    for (bindings) |parameter| if (same(parameter.id.bytes, id.bytes)) {
        if (result != null) return invalid();
        result = parameter.value;
    };
    return result orelse invalid();
}

fn exitTarget(outcomes: []const w.OutcomeTransition, outcome: w.OutcomeTag) Error!w.TransitionTarget {
    var result: ?w.TransitionTarget = null;
    for (outcomes) |edge| if (edge.outcome == outcome) {
        if (result != null) return invalid();
        result = edge.target;
    };
    const target = result orelse return invalid();
    if (target == .terminal and target.terminal != outcome) return invalid();
    return target;
}

fn validateParameters(steps: []const d.SubgraphStep, bindings: []const w.ParameterBinding) Error!void {
    for (bindings) |parameter| {
        var used = false;
        for (steps) |step| for (step.parameters) |reference| {
            if (reference.value == .parameter and same(reference.value.parameter.bytes, parameter.id.bytes)) used = true;
        };
        if (!used) return invalid();
        _ = try binding(bindings, parameter.id);
    }
    for (steps) |step| for (step.parameters) |parameter| if (parameter.value == .parameter) {
        _ = try binding(bindings, parameter.value.parameter);
    };
}

fn validateExits(steps: []const d.SubgraphStep, outcomes: []const w.OutcomeTransition) Error!void {
    var exits = [_]bool{false} ** @typeInfo(w.OutcomeTag).@"enum".fields.len;
    for (steps) |step| for (step.outcomes) |edge| if (edge.target == .terminal) {
        if (edge.target.terminal != edge.outcome) return invalid();
        exits[@intFromEnum(edge.target.terminal)] = true;
        _ = try exitTarget(outcomes, edge.target.terminal);
    };
    for (outcomes) |edge| if (!exits[@intFromEnum(edge.outcome)]) return invalid();
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
