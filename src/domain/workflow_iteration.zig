//! Finite native work is bounded by validated data, independently of retries.
const std = @import("std");
const pipeline = @import("pipeline.zig");
const workflow = @import("workflow.zig");

pub const Descriptor = struct {
    kind: enum { initialize, advance },
    scope: pipeline.DataKey,
    progress: pipeline.DataKey,
    outcome: workflow.OutcomeTag = .ok,
};

/// Facts supplied by a registered native owner, accepted only with its delta.
pub const Transition = struct { limit: usize, before: usize, after: usize };
pub const Error = error{InvalidNativeIteration};

pub fn validContract(contract: @import("workflow_operation.zig").Contract, capabilities: []const []const u8) bool {
    if (contract.iteration == null) return true;
    return contract.kind == .step and valid(contract.iteration.?, contract.requires, contract.produces, contract.replaces, contract.invalidates, contract.outcomes) and
        capabilities.len == 0 and contract.side_effect == .none and contract.runner_accounting == .none and
        contract.repair_role == .none and contract.retry_limit == null;
}

pub fn validProjection(step: @import("workflow_compilation.zig").CompiledStep) bool {
    if (step.iteration == null) return true;
    return valid(step.iteration.?, step.requires, step.produces, step.replaces, step.invalidates, step.outcomes) and
        step.capabilities.len == 0 and step.side_effect == .none and step.runner_accounting == .none and
        step.repair_role == .none and step.retry_authority == null;
}

fn valid(descriptor: Descriptor, requires: []const pipeline.DataKey, produces: []const pipeline.DataKey, replaces: []const pipeline.DataKey, invalidates: []const pipeline.DataKey, outcomes: []const workflow.OutcomeTag) bool {
    if (descriptor.scope == descriptor.progress or !contains(requires, descriptor.scope) or
        contains(produces, descriptor.scope) or contains(replaces, descriptor.scope) or contains(invalidates, descriptor.scope) or
        contains(invalidates, descriptor.progress) or std.mem.indexOfScalar(workflow.OutcomeTag, outcomes, descriptor.outcome) == null or
        (descriptor.outcome != .ok and descriptor.outcome != .more)) return false;
    return switch (descriptor.kind) {
        .initialize => contains(produces, descriptor.progress) and !contains(requires, descriptor.progress) and !contains(replaces, descriptor.progress),
        .advance => contains(requires, descriptor.progress) and contains(replaces, descriptor.progress) and !contains(produces, descriptor.progress),
    };
}

fn contains(keys: []const pipeline.DataKey, key: pipeline.DataKey) bool {
    return std.mem.indexOfScalar(pipeline.DataKey, keys, key) != null;
}

const Entry = struct {
    scope: pipeline.DataKey,
    scope_generation: u64,
    progress_generation: u64,
    limit: usize,
    completed: usize,
};

pub const Pending = struct {
    progress: pipeline.DataKey,
    previous: ?Entry,
    next: Entry,
};

pub const State = struct {
    entries: [@import("pipeline_data.zig").key_count]?Entry = @splat(null),

    pub fn prepare(self: *const State, descriptor: Descriptor, transition: Transition, scope_generation: u64, progress_generation: ?u64) Error!Pending {
        if (scope_generation == 0 or descriptor.scope == descriptor.progress) return error.InvalidNativeIteration;
        const previous = self.entries[@intFromEnum(descriptor.progress)];
        switch (descriptor.kind) {
            .initialize => {
                if (transition.before != 0 or transition.after != 0 or progress_generation != null) return error.InvalidNativeIteration;
                if (previous) |prior| {
                    if (prior.scope != descriptor.scope or scope_generation <= prior.scope_generation) return error.InvalidNativeIteration;
                }
            },
            .advance => {
                const prior = previous orelse return error.InvalidNativeIteration;
                if (prior.scope != descriptor.scope or prior.scope_generation != scope_generation or
                    progress_generation == null or prior.progress_generation != progress_generation.? or
                    transition.limit != prior.limit or transition.before != prior.completed or
                    transition.after > transition.limit or transition.after != (std.math.add(usize, transition.before, 1) catch return error.InvalidNativeIteration)) return error.InvalidNativeIteration;
            },
        }
        return .{ .progress = descriptor.progress, .previous = previous, .next = .{
            .scope = descriptor.scope,
            .scope_generation = scope_generation,
            .progress_generation = 0,
            .limit = transition.limit,
            .completed = transition.after,
        } };
    }

    /// Allocation-free commit follows successful envelope application.
    pub fn commit(self: *State, pending: Pending, progress_generation: u64) Error!void {
        const slot = &self.entries[@intFromEnum(pending.progress)];
        if (!std.meta.eql(slot.*, pending.previous) or progress_generation == 0 or
            (if (pending.previous) |previous| progress_generation <= previous.progress_generation else false)) return error.InvalidNativeIteration;
        var next = pending.next;
        next.progress_generation = progress_generation;
        slot.* = next;
    }
};

const test_initialize: Descriptor = .{ .kind = .initialize, .scope = .raw_engine_config, .progress = .engine_config };
const test_advance: Descriptor = .{ .kind = .advance, .scope = test_initialize.scope, .progress = test_initialize.progress };

test "native iteration freezes its actual population and advances once per accepted generation" {
    var state: State = .{};
    const initialization = try state.prepare(test_initialize, .{ .limit = 2, .before = 0, .after = 0 }, 1, null);
    try std.testing.expectError(error.InvalidNativeIteration, state.prepare(test_advance, .{ .limit = 2, .before = 0, .after = 1 }, 1, 2));
    try state.commit(initialization, 2);
    const first = try state.prepare(test_advance, .{ .limit = 2, .before = 0, .after = 1 }, 1, 2);
    // Merely preparing a candidate does not advance the committed cursor.
    _ = try state.prepare(test_advance, .{ .limit = 2, .before = 0, .after = 1 }, 1, 2);
    try state.commit(first, 3);
    try std.testing.expectError(error.InvalidNativeIteration, state.commit(first, 4));
    const last = try state.prepare(test_advance, .{ .limit = 2, .before = 1, .after = 2 }, 1, 3);
    try state.commit(last, 4);
    try std.testing.expectError(error.InvalidNativeIteration, state.prepare(test_advance, .{ .limit = 2, .before = 2, .after = 3 }, 1, 4));
}

test "native iteration rejects reset replay changed populations stale generations and absent progress" {
    var state: State = .{};
    try state.commit(try state.prepare(test_initialize, .{ .limit = 2, .before = 0, .after = 0 }, 1, null), 2);
    for ([_]Transition{
        .{ .limit = 3, .before = 0, .after = 1 },
        .{ .limit = 2, .before = 0, .after = 0 },
        .{ .limit = 2, .before = 0, .after = 2 },
        .{ .limit = 2, .before = 1, .after = 2 },
    }) |transition| try std.testing.expectError(error.InvalidNativeIteration, state.prepare(test_advance, transition, 1, 2));
    const transition: Transition = .{ .limit = 2, .before = 0, .after = 1 };
    try std.testing.expectError(error.InvalidNativeIteration, state.prepare(test_advance, transition, 2, 2));
    try std.testing.expectError(error.InvalidNativeIteration, state.prepare(test_advance, transition, 1, 3));
    try std.testing.expectError(error.InvalidNativeIteration, state.prepare(test_advance, transition, 1, null));
    try std.testing.expectError(error.InvalidNativeIteration, state.prepare(test_initialize, .{ .limit = 2, .before = 0, .after = 0 }, 1, null));
    try std.testing.expectError(error.InvalidNativeIteration, state.prepare(test_initialize, .{ .limit = 2, .before = 0, .after = 0 }, 3, 2));
    try state.commit(try state.prepare(test_initialize, .{ .limit = 1, .before = 0, .after = 0 }, 3, null), 4);
    try state.commit(try state.prepare(test_advance, .{ .limit = 1, .before = 0, .after = 1 }, 3, 4), 5);
}

test "zero native population completes without an advance" {
    var state: State = .{};
    try state.commit(try state.prepare(test_initialize, .{ .limit = 0, .before = 0, .after = 0 }, 1, null), 2);
    try std.testing.expectError(error.InvalidNativeIteration, state.prepare(test_advance, .{ .limit = 0, .before = 0, .after = 1 }, 1, 2));
}
