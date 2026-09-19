//! Shared compiled data/composition flow. Pure facts from the existing graph;
//! used by graph admission and exact persisted-contract resolution.
const std = @import("std");
const pipeline = @import("pipeline.zig");
const compilation = @import("workflow_compilation.zig");
const composition_flow = @import("workflow_json_composition.zig");
pub const Error = std.mem.Allocator.Error || error{WorkflowGraphCompileInvalid};
const key_count = @typeInfo(pipeline.DataKey).@"enum".fields.len;
const KeyState = [key_count]bool;
pub const State = struct { keys: KeyState, composition: composition_flow.State = .{} };

/// Resolve the existing producers of a required key without inventing a second
/// execution or validation path. Branches may contribute different producers.
pub fn producers(allocator: std.mem.Allocator, authority: compilation.SemanticAuthority, consumer: usize, key: pipeline.DataKey) Error![]usize {
    const visited = try allocator.alloc(bool, authority.steps.len);
    defer allocator.free(visited);
    @memset(visited, false);
    var queue: std.ArrayList(usize) = .empty;
    defer queue.deinit(allocator);
    var found: std.ArrayList(usize) = .empty;
    errdefer found.deinit(allocator);
    try queue.append(allocator, consumer);
    var cursor: usize = 0;
    while (cursor < queue.items.len) : (cursor += 1) {
        for (authority.transitions) |edge| {
            if (edge.target != .step or !std.mem.eql(u8, edge.target.step.bytes, authority.steps[queue.items[cursor]].id.bytes)) continue;
            const index = stepIndex(authority.steps, edge.from.bytes) orelse return invalid();
            if (visited[index]) continue;
            visited[index] = true;
            const step = authority.steps[index];
            if (std.mem.indexOfScalar(pipeline.DataKey, step.invalidates, key) != null) return invalid();
            if (std.mem.indexOfScalar(pipeline.DataKey, step.produces, key) != null or std.mem.indexOfScalar(pipeline.DataKey, step.replaces, key) != null) {
                try found.append(allocator, index);
            } else try queue.append(allocator, index);
        }
    }
    std.mem.sort(usize, found.items, {}, std.sort.asc(usize));
    return try found.toOwnedSlice(allocator);
}

pub fn analyze(allocator: std.mem.Allocator, authority: compilation.SemanticAuthority) Error![]?State {
    const steps = authority.steps;
    const start = stepIndex(steps, authority.start_step_id.bytes) orelse return invalid();
    const inputs = try allocator.alloc(?State, steps.len);
    errdefer allocator.free(inputs);
    @memset(inputs, null);
    var initial = [_]bool{false} ** key_count;
    for (authority.invocation_outputs) |key| {
        if (initial[@intFromEnum(key)]) return invalid();
        initial[@intFromEnum(key)] = true;
    }
    inputs[start] = .{ .keys = initial };
    var queue: std.ArrayList(usize) = .empty;
    defer queue.deinit(allocator);
    try queue.append(allocator, start);
    var cursor: usize = 0;
    while (cursor < queue.items.len) : (cursor += 1) {
        const index = queue.items[cursor];
        const input = inputs[index].?;
        const output = try applyDataContract(input.keys, steps[index]);
        for (authority.transitions) |transition| {
            if (!std.mem.eql(u8, transition.from.bytes, steps[index].id.bytes)) continue;
            const composed = composition_flow.apply(input.composition, steps[index], authority.resources, transition.outcome) catch return invalid();
            if (transition.target == .terminal) {
                if (transition.target.terminal == .ok and composed.plan != null) return invalid();
                continue;
            }
            const target = stepIndex(steps, transition.target.step.bytes) orelse return invalid();
            if (inputs[target]) |existing| {
                if (!std.mem.eql(bool, &existing.keys, &output) or !existing.composition.eql(composed)) return invalid();
            } else {
                inputs[target] = .{ .keys = output, .composition = composed };
                try queue.append(allocator, target);
            }
        }
    }
    return inputs;
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
fn invalid() Error {
    return error.WorkflowGraphCompileInvalid;
}
