const std = @import("std");
const retry = @import("domain/workflow_retry.zig");

test "protocol assignment history survives new request ordinals and separates units parents and executions" {
    const identity = @import("domain/model_request_identity.zig");
    const epoch = try @import("domain/execution_reference.zig").create(std.testing.allocator);
    defer epoch.release();
    var first: identity.ModelRequestId = .{
        .stage_run_epoch_id = .{ .reference = epoch },
        .immutable_unit_owner_id = .{ .reference_global = .{ .reference_state_id = .{ .bytes = "source" }, .unit_slot_id = .{ .bytes = "one" } } },
        .model_operation_id = .{ .workflow_id = .{ .bytes = "review" }, .workflow_version = 1, .workflow_step_id = .{ .bytes = "prepare" } },
        .purpose = .initial_generation,
        .request_ordinal = .{ .value = 1 },
    };
    var reassigned = first;
    reassigned.request_ordinal.value = 999;
    var other = first;
    other.immutable_unit_owner_id.reference_global.unit_slot_id.bytes = "two";
    var state = retry.State.init(std.testing.allocator);
    defer state.deinit();
    const operation: @import("domain/workflow.zig").WorkflowStepId = .{ .bytes = "account" };
    for ([_]*const identity.ModelRequestId{ &first, &reassigned }) |id| {
        _ = try state.beginAssignmentAttempt(operation, .{ .value = 1 }, .{ .request = id, .record = .{ .value = 1 } });
    }
    try std.testing.expectEqualDeep(retry.AttemptResult{ .exhausted = 2 }, try state.beginAssignmentAttempt(operation, .{ .value = 1 }, .{ .request = &reassigned, .record = .{ .value = 2 } }));
    try std.testing.expectEqualDeep(retry.AttemptResult{ .allowed = 1 }, try state.beginAssignmentAttempt(operation, .{ .value = 1 }, .{ .request = &other, .record = .{ .value = 3 } }));
    const parent = permit(1, 1, 1);
    try apply(&state, .{ .authorized = parent });
    try apply(&state, .{ .merged = .{ .permit = parent, .revision_after = 2, .validation = .dependent_review } });
    try std.testing.expectError(error.InvalidRepairProgress, state.beginAssignmentAttempt(operation, .{ .value = 1 }, .{ .request = &first, .record = .{ .value = 4 } }));
    try std.testing.expectEqualDeep(retry.AttemptResult{ .allowed = 1 }, try state.beginAssignmentAttempt(operation, .{ .value = 1 }, .{ .request = &first, .record = .{ .value = 4 }, .parent = parent.key }));
    try std.testing.expectEqualDeep(parent, state.currentDependentPermit().?);
    var fresh = retry.State.init(std.testing.allocator);
    defer fresh.deinit();
    try std.testing.expectEqualDeep(retry.AttemptResult{ .allowed = 1 }, try fresh.beginAssignmentAttempt(operation, .{ .value = 1 }, .{ .request = &first, .record = .{ .value = 1 } }));
    const rows = try state.observeAssignments(std.testing.allocator, operation);
    defer std.testing.allocator.free(rows);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqual(@as(usize, 1), rows[0].request.value);
    try std.testing.expectEqual(@as(u64, 2), rows[0].completed_executions);
}

fn permit(target: u8, revision: u64, authorization: u8) retry.Permit {
    return .{ .key = .{ .scope = @splat(1), .target = @splat(target), .family = @splat(2) }, .authorization = @splat(authorization), .revision = revision, .maximum_targets = 8 };
}

fn apply(state: *retry.State, transition: retry.Transition) retry.StateError!void {
    try state.commit(try state.prepare(transition));
}

fn finish(state: *retry.State, value: retry.Permit, result: retry.Validation) !void {
    try apply(state, .{ .merged = .{ .permit = value, .revision_after = value.revision + 1 } });
    try apply(state, .{ .validated = .{ .permit = value, .revision = value.revision + 1, .result = result } });
}

test "successful independent repairs continue beyond an operation-wide allowance" {
    var state = retry.State.init(std.testing.allocator);
    defer state.deinit();
    for (0..7) |index| {
        const value = permit(@intCast(index + 1), index + 1, @intCast(index + 1));
        try apply(&state, .{ .authorized = value });
        try std.testing.expectEqualDeep(retry.AttemptResult{ .allowed = 1 }, try state.beginAttempt(.{ .bytes = "repair-account" }, .{ .value = 1 }, value));
        try std.testing.expectEqualDeep(retry.AttemptResult{ .allowed = 1 }, try state.beginAttempt(.{ .bytes = "repair-merge" }, .{ .value = 2 }, value));
        try finish(&state, value, .resolved);
        try std.testing.expect(state.currentPermit() == null);
    }
    const counts = try state.observe(std.testing.allocator, .{ .bytes = "repair-account" });
    defer {
        for (counts) |count| count.deinit(std.testing.allocator);
        std.testing.allocator.free(counts);
    }
    try std.testing.expectEqual(@as(usize, 7), counts.len);
    for (counts, 1..) |count, ordinal| {
        try std.testing.expectEqualStrings(&std.fmt.bytesToHex(permit(@intCast(ordinal), 1, 1).key.target, .lower), count.key.target);
        try std.testing.expectEqual(@as(u64, 1), count.completed_executions);
    }
}

test "unchanged and alternating invalid values cannot reset the same defect allowance" {
    var state = retry.State.init(std.testing.allocator);
    defer state.deinit();
    for (0..2) |index| {
        // Native callers may change observed values; neither those values nor
        // new authorization IDs and revisions change the stable defect key.
        const value = permit(1, index + 1, @intCast(index + 1));
        try apply(&state, .{ .authorized = value });
        try std.testing.expectEqualDeep(retry.AttemptResult{ .allowed = index + 1 }, try state.beginAttempt(.{ .bytes = "repair-account" }, .{ .value = 1 }, value));
        try finish(&state, value, .recurring);
    }
    const next = permit(1, 3, 3);
    try apply(&state, .{ .authorized = next });
    try std.testing.expectEqualDeep(retry.AttemptResult{ .exhausted = 2 }, try state.beginAttempt(.{ .bytes = "repair-account" }, .{ .value = 1 }, next));
    try std.testing.expectError(error.InvalidRepairProgress, state.beginAttempt(.{ .bytes = "repair-account" }, .{ .value = 2 }, next));
}

test "a resolved defect returning after another target retains its history" {
    var state = retry.State.init(std.testing.allocator);
    defer state.deinit();
    for ([_]u8{ 1, 2, 1 }, 0..) |target, index| {
        const value = permit(target, index + 1, @intCast(index + 1));
        try apply(&state, .{ .authorized = value });
        try std.testing.expectEqualDeep(retry.AttemptResult{ .allowed = if (index == 2) 2 else 1 }, try state.beginAttempt(.{ .bytes = "repair-account" }, .{ .value = 1 }, value));
        try finish(&state, value, .resolved);
    }
    const returned = permit(1, 4, 4);
    try apply(&state, .{ .authorized = returned });
    try std.testing.expectEqualDeep(retry.AttemptResult{ .exhausted = 2 }, try state.beginAttempt(.{ .bytes = "repair-account" }, .{ .value = 1 }, returned));
    const counts = try state.observe(std.testing.allocator, .{ .bytes = "repair-account" });
    defer {
        for (counts) |count| count.deinit(std.testing.allocator);
        std.testing.allocator.free(counts);
    }
    try std.testing.expectEqual(@as(usize, 2), counts.len);
    try std.testing.expectEqual(@as(u64, 2), counts[0].completed_executions);
    try std.testing.expectEqual(@as(u64, 1), counts[1].completed_executions);
}

test "authorization merge and validation require exact ordered association" {
    var state = retry.State.init(std.testing.allocator);
    defer state.deinit();
    const first = permit(1, 1, 1);
    const next = permit(2, 2, 2);
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .merged = .{ .permit = first, .revision_after = 2 } }));
    try apply(&state, .{ .authorized = first });
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .authorized = next }));
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .validated = .{ .permit = first, .revision = 2, .result = .resolved } }));
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .merged = .{ .permit = first, .revision_after = 3 } }));
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .merged = .{ .permit = permit(1, 1, 2), .revision_after = 2 } }));
    try apply(&state, .{ .merged = .{ .permit = first, .revision_after = 2 } });
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .merged = .{ .permit = first, .revision_after = 2 } }));
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .authorized = next }));
    try std.testing.expectError(error.InvalidRepairProgress, state.beginAttempt(.{ .bytes = "repair-account" }, .{ .value = 1 }, first));
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .validated = .{ .permit = first, .revision = 3, .result = .resolved } }));
    try apply(&state, .{ .validated = .{ .permit = first, .revision = 2, .result = .recurring } });
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .authorized = next }));
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .authorized = first }));
    try apply(&state, .{ .authorized = permit(1, 2, 2) });
}

test "native population remains frozen and successful repairs cannot grow it" {
    var state = retry.State.init(std.testing.allocator);
    defer state.deinit();
    var first = permit(1, 1, 1);
    first.maximum_targets = 1;
    try apply(&state, .{ .authorized = first });
    try finish(&state, first, .resolved);
    var another = permit(2, 2, 2);
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .authorized = another }));
    another.maximum_targets = 1;
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .authorized = another }));
    another.key = first.key;
    try apply(&state, .{ .authorized = another });
}

test "prepared transitions allocate before commit and reject stale application" {
    var state = retry.State.init(std.testing.allocator);
    defer state.deinit();
    const first = permit(1, 1, 1);
    const prepared = try state.prepare(.{ .authorized = first });
    try std.testing.expect(state.active == null);
    try state.commit(prepared);
    try std.testing.expectError(error.InvalidRepairProgress, state.commit(prepared));
    const merge = try state.prepare(.{ .merged_validated = .{ .permit = first, .revision_after = 2, .result = .resolved } });
    _ = try state.beginAttempt(.{ .bytes = "repair-account" }, .{ .value = 1 }, first);
    try std.testing.expectError(error.InvalidRepairProgress, state.commit(merge));
    try state.commit(try state.prepare(.{ .merged_validated = .{ .permit = first, .revision_after = 2, .result = .resolved } }));
    try apply(&state, .{ .authorized = permit(2, 2, 2) });
}

test "dependent semantic review keeps its parent pending across bounded child repairs" {
    const epoch = try @import("domain/execution_reference.zig").create(std.testing.allocator);
    defer epoch.release();
    const request = dependentRequest(epoch);
    var state = retry.State.init(std.testing.allocator);
    defer state.deinit();
    const parent = permit(1, 1, 1);
    try apply(&state, .{ .authorized = parent });
    try state.commit(try state.prepare(.{ .merged = .{ .permit = parent, .revision_after = 2, .validation = .dependent_review } }));
    try std.testing.expectEqualDeep(retry.AttemptResult{ .allowed = 1 }, try state.beginAssignmentAttempt(.{ .bytes = "review" }, .{ .value = 1 }, .{ .request = &request, .record = .{ .value = 1 }, .parent = parent.key }));
    const child = permit(2, 2, 2);
    try apply(&state, .{ .authorized = child });
    try std.testing.expect(state.currentDependentPermit() == null);
    try std.testing.expectError(error.InvalidRepairProgress, state.beginAssignmentAttempt(.{ .bytes = "review" }, .{ .value = 1 }, .{ .request = &request, .record = .{ .value = 1 }, .parent = parent.key }));
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .validated = .{ .permit = parent, .revision = 2, .result = .resolved } }));
    try apply(&state, .{ .merged = .{ .permit = child, .revision_after = 3 } });
    try apply(&state, .{ .validated = .{ .permit = child, .revision = 3, .result = .recurring } });
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .authorized = permit(3, 3, 3) }));
    const corrected = permit(2, 3, 3);
    try apply(&state, .{ .authorized = corrected });
    try finish(&state, corrected, .resolved);
    try std.testing.expectEqualDeep(parent, state.currentPermit().?);
    try std.testing.expectEqualDeep(retry.AttemptResult{ .allowed = 2 }, try state.beginAssignmentAttempt(.{ .bytes = "review" }, .{ .value = 1 }, .{ .request = &request, .record = .{ .value = 1 }, .parent = parent.key }));
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .authorized = permit(1, 4, 4) }));
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .validated = .{ .permit = parent, .revision = 1, .result = .resolved } }));
    try apply(&state, .{ .validated = .{ .permit = parent, .revision = 4, .result = .resolved } });
    try std.testing.expect(state.currentPermit() == null);
    try apply(&state, .{ .authorized = permit(3, 4, 4) });
    const observed = try state.observeAssignments(std.testing.allocator, .{ .bytes = "review" });
    defer std.testing.allocator.free(observed);
    try std.testing.expectEqual(@as(usize, 1), observed.len);
    try std.testing.expectEqual(@as(usize, 1), observed[0].request.value);
    try std.testing.expectEqual(@as(u64, 2), observed[0].completed_executions);
}

test "dependent request attempts require a merged semantic parent and retain recurrence counts" {
    const epoch = try @import("domain/execution_reference.zig").create(std.testing.allocator);
    defer epoch.release();
    const request = dependentRequest(epoch);
    var state = retry.State.init(std.testing.allocator);
    defer state.deinit();
    for ([_]u8{ 1, 2, 1 }, 0..) |target, index| {
        const parent = permit(target, index + 1, @intCast(index + 1));
        try apply(&state, .{ .authorized = parent });
        try std.testing.expect(state.currentDependentPermit() == null);
        try std.testing.expectError(error.InvalidRepairProgress, state.beginAssignmentAttempt(.{ .bytes = "account" }, .{ .value = 1 }, .{ .request = &request, .record = .{ .value = 1 }, .parent = parent.key }));
        try apply(&state, .{ .merged = .{ .permit = parent, .revision_after = parent.revision + 1, .validation = .dependent_review } });
        try std.testing.expectEqualDeep(parent, state.currentDependentPermit().?);
        try std.testing.expectError(error.InvalidRepairProgress, state.beginAttempt(.{ .bytes = "merge" }, .{ .value = 1 }, parent));
        try std.testing.expectError(error.InvalidRepairProgress, state.beginAssignmentAttempt(.{ .bytes = "account" }, .{ .value = 1 }, .{ .request = &request, .record = .{ .value = 1 }, .parent = (permit(7, parent.revision, 7)).key }));
        const attempts: retry.AttemptResult = if (index == 2) .{ .exhausted = 2 } else .{ .allowed = 1 };
        try std.testing.expectEqualDeep(attempts, try state.beginAssignmentAttempt(.{ .bytes = "account" }, .{ .value = 1 }, .{ .request = &request, .record = .{ .value = 1 }, .parent = parent.key }));
        if (index != 2) {
            try std.testing.expectEqualDeep(retry.AttemptResult{ .allowed = 2 }, try state.beginAssignmentAttempt(.{ .bytes = "account" }, .{ .value = 1 }, .{ .request = &request, .record = .{ .value = 1 }, .parent = parent.key }));
            try std.testing.expectEqualDeep(retry.AttemptResult{ .exhausted = 2 }, try state.beginAssignmentAttempt(.{ .bytes = "account" }, .{ .value = 1 }, .{ .request = &request, .record = .{ .value = 1 }, .parent = parent.key }));
        }
        try apply(&state, .{ .validated = .{ .permit = parent, .revision = parent.revision + 1, .result = .resolved } });
        try std.testing.expect(state.currentDependentPermit() == null);
    }
    const native = permit(3, 4, 4);
    try apply(&state, .{ .authorized = native });
    try apply(&state, .{ .merged = .{ .permit = native, .revision_after = 5 } });
    try std.testing.expect(state.currentDependentPermit() == null);
    try std.testing.expectError(error.InvalidRepairProgress, state.beginAssignmentAttempt(.{ .bytes = "account" }, .{ .value = 1 }, .{ .request = &request, .record = .{ .value = 1 }, .parent = native.key }));
}

fn allocatingScenario(allocator: std.mem.Allocator) !void {
    const epoch = try @import("domain/execution_reference.zig").create(allocator);
    defer epoch.release();
    const request = dependentRequest(epoch);
    var state = retry.State.init(allocator);
    defer state.deinit();
    _ = try state.beginAssignmentAttempt(.{ .bytes = "request-account" }, .{ .value = 1 }, .{ .request = &request, .record = .{ .value = 1 } });
    const assignments = try state.observeAssignments(allocator, .{ .bytes = "request-account" });
    defer allocator.free(assignments);
    for (0..3) |index| {
        const value = permit(@intCast(index + 1), index + 1, @intCast(index + 1));
        try apply(&state, .{ .authorized = value });
        _ = try state.beginAttempt(.{ .bytes = "repair-account" }, .{ .value = 1 }, value);
        _ = try state.beginAttempt(.{ .bytes = "repair-merge" }, .{ .value = 1 }, value);
        try finish(&state, value, .resolved);
    }
    const parent = permit(4, 4, 4);
    try apply(&state, .{ .authorized = parent });
    try state.commit(try state.prepare(.{ .merged = .{ .permit = parent, .revision_after = 5, .validation = .dependent_review } }));
    const child = permit(5, 5, 5);
    try apply(&state, .{ .authorized = child });
    _ = try state.beginAttempt(.{ .bytes = "repair-account" }, .{ .value = 1 }, child);
    try finish(&state, child, .resolved);
    try apply(&state, .{ .validated = .{ .permit = parent, .revision = 5, .result = .resolved } });
    const observations = try state.observe(allocator, .{ .bytes = "repair-account" });
    defer {
        for (observations) |observation| observation.deinit(allocator);
        allocator.free(observations);
    }
}

test "repair progress releases every allocation on failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocatingScenario, .{});
}

test "native progress effects require their exact registered role" {
    const pipeline = @import("domain/pipeline.zig");
    const shape = pipeline.DataShape.init(&.{});
    var contract: pipeline.NodeContract = .{ .id = "test.authorize", .kind = .action, .requires = &.{}, .produces = &.{}, .side_effect = .none };
    var delta: pipeline.NodeDelta = .{ .repair_transition = .{ .authorized = permit(1, 1, 1) } };
    try std.testing.expectError(error.UndeclaredRepairTransition, shape.applyDelta(contract, &delta));
    contract.repair_role = .authorize;
    _ = try shape.applyDelta(contract, &delta);
    contract.repair_role = .merge;
    try std.testing.expectError(error.UndeclaredRepairTransition, shape.applyDelta(contract, &delta));
    delta.repair_transition = .{ .merged = .{ .permit = permit(1, 1, 1), .revision_after = 2 } };
    _ = try shape.applyDelta(contract, &delta);
    contract.repair_role = .validate;
    try std.testing.expectError(error.UndeclaredRepairTransition, shape.applyDelta(contract, &delta));
}

fn dependentRequest(epoch: @import("domain/execution_reference.zig").Ref) @import("domain/model_request_identity.zig").ModelRequestId {
    return .{
        .stage_run_epoch_id = .{ .reference = epoch },
        .immutable_unit_owner_id = .{ .reference_global = .{ .reference_state_id = .{ .bytes = "source" }, .unit_slot_id = .{ .bytes = "one" } } },
        .model_operation_id = .{ .workflow_id = .{ .bytes = "review" }, .workflow_version = 1, .workflow_step_id = .{ .bytes = "prepare" } },
        .purpose = .initial_generation,
        .request_ordinal = .{ .value = 1 },
    };
}
