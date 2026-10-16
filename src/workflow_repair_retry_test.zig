const std = @import("std");
const retry = @import("domain/workflow_retry.zig");

test "unchanged canonical replacements exhaust actual repair attempts without acceptance" {
    const atomic = @import("domain/atomic_repair.zig");
    const Replacement = union(enum) { narrative: []const u8, selection: []const u32 };
    const Contract = atomic.Contract(enum { subject }, Replacement, struct { source: u32 }, enum { rejected });
    for ([_]Replacement{ .{ .narrative = "Preserve the specified duty." }, .{ .selection = &.{ 2, 7 } } }) |expected| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const owner: @import("domain/model_request_identity.zig").ImmutableUnitOwnerId = .{ .reference_global = .{ .reference_state_id = .{ .bytes = "source" }, .unit_slot_id = .{ .bytes = "subject" } } };
        var authorization = try Contract.authorize(a, owner, 1, .subject, expected, .{ .source = 3 }, .rejected);
        authorization.retry = permit(3, 1, 4);
        const same = try Contract.copyReplacement(a, expected);
        const merged = try Contract.checkMerge(a, .{ .normalizer = .{ .normalize_fn = identityNormalize }, .original_sources = &.{} }, owner, 1, expected, .{ .source = 3 }, authorization, same, null);
        try std.testing.expect(!merged.changed);
        const transition = try merged.transition(.dependent_review);
        try std.testing.expect(!transition.merged.changed);
        const combined = try merged.validatedTransition(.resolved);
        try std.testing.expect(!combined.merged_validated.changed);
        for ([_]retry.Transition{ transition, combined }) |unchanged| {
            var state = retry.State.init(std.testing.allocator);
            defer state.deinit();
            try apply(&state, .{ .authorized = authorization.retry.? });
            try std.testing.expectError(error.InvalidRepairProgress, state.prepare(unchanged));
            try std.testing.expectError(error.InvalidRepairProgress, state.unchangedExhaustion(unchanged));
            _ = try state.beginAttempt(.{ .bytes = "merge" }, .{ .value = 8 }, authorization.retry.?);
            var foreign = unchanged;
            switch (foreign) {
                .merged => |*value| value.permit.authorization[0] ^= 1,
                .merged_validated => |*value| value.permit.authorization[0] ^= 1,
                else => unreachable,
            }
            try std.testing.expectError(error.InvalidRepairProgress, state.unchangedExhaustion(foreign));
            var stale = unchanged;
            switch (stale) {
                .merged => |*value| value.revision_after += 1,
                .merged_validated => |*value| value.revision_after += 1,
                else => unreachable,
            }
            try std.testing.expectError(error.InvalidRepairProgress, state.unchangedExhaustion(stale));
            try std.testing.expectError(error.InvalidRepairProgress, state.beginAttempt(.{ .bytes = "merge" }, .{ .value = 7 }, authorization.retry.?));
            try std.testing.expect(state.terminal_exhaustion == null);
            const revision = state.revision;
            const exhausted = (try state.unchangedExhaustion(unchanged)).?;
            try std.testing.expectEqual(.unchanged_repair, exhausted.reason);
            try std.testing.expectEqual(@as(u64, 1), exhausted.completed_executions);
            try std.testing.expectEqual(@as(u32, 8), exhausted.limit.value);
            try std.testing.expectEqualDeep(authorization.retry.?.key, exhausted.defect.?);
            try std.testing.expectEqual(revision, state.revision);
            try std.testing.expectEqualDeep(authorization.retry.?, state.currentPermit().?);
            try std.testing.expect(!state.permitsContinuation(authorization.retry.?, authorization.retry.?.key));
            try std.testing.expectError(error.InvalidRepairProgress, state.beginAttempt(.{ .bytes = "merge" }, .{ .value = 8 }, authorization.retry.?));
            try std.testing.expectError(error.InvalidRepairProgress, state.prepare(.{ .authorized = permit(4, 1, 5) }));
        }
        var unbound = merged;
        unbound.retry = null;
        try std.testing.expectError(error.InvalidAtomicRepair, unbound.transition(.native));
        const changed: Replacement = switch (expected) {
            .narrative => .{ .narrative = "Preserve the corrected duty." },
            .selection => .{ .selection = &.{ 2, 8 } },
        };
        const different = try Contract.checkMerge(a, .{ .normalizer = .{ .normalize_fn = identityNormalize }, .original_sources = &.{} }, owner, 1, expected, .{ .source = 3 }, authorization, changed, null);
        try std.testing.expect(different.changed);
        var state = retry.State.init(std.testing.allocator);
        defer state.deinit();
        try apply(&state, .{ .authorized = authorization.retry.? });
        const changed_transition = try different.transition(.native);
        try std.testing.expectEqual(@as(?retry.Exhaustion, null), try state.unchangedExhaustion(changed_transition));
        try apply(&state, changed_transition);
        try std.testing.expect(state.currentPermit() != null);
        try apply(&state, .{ .validated = .{ .permit = authorization.retry.?, .revision = 2, .result = .recurring } });
        try std.testing.expect(state.currentPermit() != null);
        try std.testing.expectError(error.InvalidAtomicRepair, Contract.checkMerge(a, .{ .normalizer = .{ .normalize_fn = identityNormalize }, .original_sources = &.{} }, owner, 1, changed, .{ .source = 3 }, authorization, same, null));
    }
}

test "unchanged repair exhausts the exact authorization's latest admitted allowance owner" {
    const current = permit(3, 1, 4);
    const unchanged: retry.Transition = .{ .merged = .{ .permit = current, .revision_after = 2, .changed = false } };
    for ([_]bool{ false, true }) |merge_owns_allowance| {
        var state = retry.State.init(std.testing.allocator);
        defer state.deinit();
        try apply(&state, .{ .authorized = current });
        // The account owner can admit a protocol correction before a merge
        // that has no separate retry descriptor of its own.
        _ = try state.beginAttempt(.{ .bytes = "account" }, .{ .value = 3 }, current);
        _ = try state.beginAttempt(.{ .bytes = "account" }, .{ .value = 3 }, current);
        if (merge_owns_allowance) _ = try state.beginAttempt(.{ .bytes = "merge" }, .{ .value = 8 }, current);
        const revision = state.revision;
        const exhausted = (try state.unchangedExhaustion(unchanged)).?;
        try std.testing.expectEqualStrings(if (merge_owns_allowance) "merge" else "account", exhausted.operation().bytes);
        try std.testing.expectEqual(@as(u32, if (merge_owns_allowance) 8 else 3), exhausted.limit.value);
        try std.testing.expectEqual(@as(u64, if (merge_owns_allowance) 1 else 2), exhausted.completed_executions);
        try std.testing.expectEqualDeep(current.key, exhausted.defect.?);
        try std.testing.expectEqual(.unchanged_repair, exhausted.reason);
        try std.testing.expectEqual(revision, state.revision);
    }
}

test "new repair authorizations cannot borrow an earlier authorization's admitted attempt" {
    var state = retry.State.init(std.testing.allocator);
    defer state.deinit();
    const original = permit(3, 1, 4);
    try apply(&state, .{ .authorized = original });
    _ = try state.beginAttempt(.{ .bytes = "account" }, .{ .value = 3 }, original);
    try apply(&state, .{ .merged = .{ .permit = original, .revision_after = 2, .changed = true } });
    try apply(&state, .{ .validated = .{ .permit = original, .revision = 2, .result = .recurring } });
    const next = permit(3, 2, 5);
    try apply(&state, .{ .authorized = next });
    const unchanged: retry.Transition = .{ .merged = .{ .permit = next, .revision_after = 3, .changed = false } };
    try std.testing.expectError(error.InvalidRepairProgress, state.unchangedExhaustion(unchanged));
    try std.testing.expectError(error.InvalidRepairProgress, state.beginAttempt(.{ .bytes = "account" }, .{ .value = 3 }, original));
    try std.testing.expectError(error.InvalidRepairProgress, state.unchangedExhaustion(.{ .merged = .{ .permit = original, .revision_after = 2, .changed = false } }));
    try std.testing.expect(state.terminal_exhaustion == null);
    try std.testing.expectEqual(@as(u64, 1), state.completedAttempts(.{ .bytes = "account" }, next.key));
    _ = try state.beginAttempt(.{ .bytes = "account" }, .{ .value = 3 }, next);
    const exhausted = (try state.unchangedExhaustion(unchanged)).?;
    try std.testing.expectEqual(@as(u64, 2), exhausted.completed_executions);
    try std.testing.expectEqualStrings("account", exhausted.operation().bytes);
}

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
    try apply(&state, .{ .merged = .{ .permit = parent, .changed = true, .revision_after = 2, .validation = .dependent_review } });
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
    try apply(state, .{ .merged = .{ .permit = value, .changed = true, .revision_after = value.revision + 1 } });
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

test "alternating changed invalid values cannot reset the same defect allowance" {
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
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .merged = .{ .permit = first, .changed = true, .revision_after = 2 } }));
    try apply(&state, .{ .authorized = first });
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .authorized = next }));
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .validated = .{ .permit = first, .revision = 2, .result = .resolved } }));
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .merged = .{ .permit = first, .changed = true, .revision_after = 3 } }));
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .merged = .{ .permit = permit(1, 1, 2), .changed = true, .revision_after = 2 } }));
    try apply(&state, .{ .merged = .{ .permit = first, .changed = true, .revision_after = 2 } });
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .merged = .{ .permit = first, .changed = true, .revision_after = 2 } }));
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
    const merge = try state.prepare(.{ .merged_validated = .{ .permit = first, .changed = true, .revision_after = 2, .result = .resolved } });
    _ = try state.beginAttempt(.{ .bytes = "repair-account" }, .{ .value = 1 }, first);
    try std.testing.expectError(error.InvalidRepairProgress, state.commit(merge));
    try state.commit(try state.prepare(.{ .merged_validated = .{ .permit = first, .changed = true, .revision_after = 2, .result = .resolved } }));
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
    try state.commit(try state.prepare(.{ .merged = .{ .permit = parent, .changed = true, .revision_after = 2, .validation = .dependent_review } }));
    try std.testing.expectEqualDeep(retry.AttemptResult{ .allowed = 1 }, try state.beginAssignmentAttempt(.{ .bytes = "review" }, .{ .value = 1 }, .{ .request = &request, .record = .{ .value = 1 }, .parent = parent.key }));
    const child = permit(2, 2, 2);
    try apply(&state, .{ .authorized = child });
    try std.testing.expect(state.currentDependentPermit() == null);
    try std.testing.expectError(error.InvalidRepairProgress, state.beginAssignmentAttempt(.{ .bytes = "review" }, .{ .value = 1 }, .{ .request = &request, .record = .{ .value = 1 }, .parent = parent.key }));
    try std.testing.expectError(error.InvalidRepairProgress, apply(&state, .{ .validated = .{ .permit = parent, .revision = 2, .result = .resolved } }));
    try apply(&state, .{ .merged = .{ .permit = child, .changed = true, .revision_after = 3 } });
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
        try apply(&state, .{ .merged = .{ .permit = parent, .changed = true, .revision_after = parent.revision + 1, .validation = .dependent_review } });
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
    try apply(&state, .{ .merged = .{ .permit = native, .changed = true, .revision_after = 5 } });
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
    try state.commit(try state.prepare(.{ .merged = .{ .permit = parent, .changed = true, .revision_after = 5, .validation = .dependent_review } }));
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
    delta.repair_transition = .{ .merged = .{ .permit = permit(1, 1, 1), .changed = true, .revision_after = 2 } };
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

test "native repair digests keep numeric array wire shape for UTF8 and binary bytes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const json = @import("domain/canonical_json.zig");
    const strict = @import("domain/strict_json.zig");
    for ([_]u8{ 0, 'a', 255 }) |byte| {
        const permit_value: retry.Permit = .{ .key = .{ .scope = @splat(byte), .target = @splat(byte), .family = @splat(byte) }, .authorization = @splat(byte), .revision = 2, .maximum_targets = 3 };
        const bytes = try json.encode(retry.Permit, a, permit_value);
        try std.testing.expectEqualDeep(permit_value, try strict.decode(retry.Permit, a, bytes, .{ .maximum_depth = 8 }));
        const transition: retry.Transition = .{ .merged = .{ .permit = permit_value, .revision_after = 3, .changed = false } };
        const encoded = try json.encode(retry.Transition, a, transition);
        try std.testing.expectEqualDeep(transition, try strict.decode(retry.Transition, a, encoded, .{ .maximum_depth = 12 }));
        var document = try strict.decode(std.json.Value, a, encoded, .{ .maximum_depth = 12 });
        const merged = document.object.getPtr("merged").?;
        _ = merged.object.swapRemove("changed");
        const missing_change = try std.json.Stringify.valueAlloc(a, document, .{});
        try std.testing.expectError(error.InvalidJsonDocument, strict.decode(retry.Transition, a, missing_change, .{ .maximum_depth = 12 }));
        try merged.object.put(a, "changed", .{ .bool = false });
        try merged.object.put(a, "accepted", .{ .bool = true });
        const unknown = try std.json.Stringify.valueAlloc(a, document, .{});
        try std.testing.expectError(error.InvalidJsonDocument, strict.decode(retry.Transition, a, unknown, .{ .maximum_depth = 12 }));
        const Snapshot = @import("domain/atomic_repair.zig").Snapshot;
        const stamp: Snapshot = .{ .bytes = @splat(byte) };
        try std.testing.expectEqualDeep(stamp, try strict.decode(Snapshot, a, try json.encode(Snapshot, a, stamp), .{ .maximum_depth = 8 }));
    }
    const wrong = "{\"bytes\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}";
    try std.testing.expectError(error.InvalidJsonDocument, strict.decode(@import("domain/atomic_repair.zig").Snapshot, a, wrong, .{ .maximum_depth = 8 }));
}

// This generic retry fixture contains no declared text fields. The pure port is
// nevertheless explicit; production Unicode behavior is covered with real text
// values by the atomic merge regressions in reference_extraction_test.zig.
fn identityNormalize(a: std.mem.Allocator, bytes: []const u8, _: usize) @import("ports/unicode_normalizer.zig").Error![]u8 {
    return a.dupe(u8, bytes);
}

test "composition repair presentation hides rejected wire while retaining native CAS and selected field metadata" {
    const atomic = @import("domain/atomic_repair.zig");
    const typed = @import("domain/typed_text.zig");
    const packets = @import("domain/model_input_packet.zig");
    const Replacement = union(enum) { value: typed.BusinessText };
    const Rule = struct { observed: Replacement, diagnostic: []const u8 };
    const Contract = atomic.Contract(enum { subject }, Replacement, struct { source: u32 }, Rule);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const expected: Replacement = .{ .value = .{ .segments = &.{.{ .exact_copy = .{ .claim_id = .{ .ordinal = 7 } } }} } };
    const owner: @import("domain/model_request_identity.zig").ImmutableUnitOwnerId = .{ .reference_global = .{ .reference_state_id = .{ .bytes = "source" }, .unit_slot_id = .{ .bytes = "subject" } } };
    var authorization = try Contract.authorize(a, owner, 1, .subject, expected, .{ .source = 3 }, .{ .observed = expected, .diagnostic = "RAW_RULE_MUST_STAY_NATIVE" });
    authorization.retry = try atomic.permit(enum { subject }, enum { composition }, a, owner, .subject, .composition, authorization.id, 1, 1);
    const before = try atomic.snapshot(Contract.Authorization, a, authorization);
    const raw = try packets.create(a, "{\"catalogue\":[7],\"source\":\"Native source evidence.\"}", owner, .initial_generation, .{ .bytes = "initial" });
    const witnessed = try packets.withOriginalSourceTexts(a, raw, &.{.{ .source_id = .{ .ordinal = 1 }, .bytes = "Native source evidence." }});
    const stale_fields = try packets.withFieldPolicies(a, witnessed, &.{.{ .field = .entity_name, .path = &.{.{ .property = "old_field" }} }});
    const base = try packets.withPresentationOmissions(a, stale_fields, &.{.{ .requires = .exact_copy, .path = &.{.{ .property = "catalogue" }} }});
    defer packets.release(base);
    defer packets.release(stale_fields);
    defer packets.release(witnessed);
    defer packets.release(raw);
    for ([_]@FieldType(typed.Issue, "reason"){ .reference_only, .prohibited_exact, .prohibited_passive, .prohibited_source, .embedded_insertion_syntax }) |reason| {
        const issue: typed.Issue = .{ .reason = reason, .field = .spec_title, .first_node = 0, .last_node = 0, .rejected_exact = .{ .claim_id = .{ .ordinal = 7 } } };
        const request = try Contract.packet(std.testing.allocator, authorization, base, .{ .bytes = "replacement" }, null, .{ .presentation = .{ .composition = .{ .rendered_text = "The original business value.", .issue = issue } }, .fields = .{ .replacement = .{ .inherited = .spec_title } } });
        defer packets.release(request);
        const body = (try std.json.parseFromSlice(std.json.Value, a, request.body(), .{})).value;
        const repair = body.object.get("repair").?.object;
        try std.testing.expect(!repair.contains("current_value"));
        const rule = repair.get("rule").?.object;
        try std.testing.expectEqualStrings("The original business value.", rule.get("rendered_text").?.string);
        try std.testing.expect(!rule.contains("observed"));
        try std.testing.expect(!rule.get("issue").?.object.contains("rejected_exact"));
        try std.testing.expect(std.mem.indexOf(u8, request.body(), "RAW_RULE_MUST_STAY_NATIVE") == null);
        try std.testing.expectEqualDeep(authorization.retry, request.repairPermit());
        try std.testing.expectEqualDeep(base.originalSources(), request.originalSources());
        try std.testing.expectEqual(@as(usize, 1), request.fieldPolicies().len);
        try std.testing.expectEqual(.spec_title, request.fieldPolicies()[0].field);
        try std.testing.expectEqualStrings("segments", request.fieldPolicies()[0].path[0].property);
        try std.testing.expectEqual(@as(usize, 1), request.presentationOmissions().len);
        try std.testing.expectEqualStrings("input", request.presentationOmissions()[0].path[0].property);
        try std.testing.expectEqualStrings("catalogue", request.presentationOmissions()[0].path[1].property);
        try std.testing.expectEqualDeep(before, try atomic.snapshot(Contract.Authorization, a, authorization));
        const canonical: typed.CanonicalText = .{ .normalizer = .{ .normalize_fn = identityNormalize }, .original_sources = &.{} };
        const same = try Contract.checkMerge(a, canonical, owner, 1, expected, .{ .source = 3 }, authorization, expected, null);
        try std.testing.expect(!same.changed);
        const changed: Replacement = .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "A corrected business value." } }} } };
        try std.testing.expect((try Contract.checkMerge(a, canonical, owner, 1, expected, .{ .source = 3 }, authorization, changed, null)).changed);
        try std.testing.expectError(error.InvalidAtomicRepair, Contract.checkMerge(a, canonical, owner, 1, changed, .{ .source = 3 }, authorization, changed, null));
    }
    const structured = try Contract.packet(a, authorization, base, .{ .bytes = "replacement" }, null, .{ .presentation = .structured, .fields = .{ .replacement = .{ .inherited = .spec_title } } });
    defer packets.release(structured);
    const body = (try std.json.parseFromSlice(std.json.Value, a, structured.body(), .{})).value;
    try std.testing.expect(body.object.get("repair").?.object.contains("current_value"));
    const issue: typed.Issue = .{ .reason = .reference_only, .field = .spec_story, .first_node = 0, .last_node = 0 };
    try std.testing.expectError(error.InvalidAtomicRepair, Contract.packet(a, authorization, base, .{ .bytes = "replacement" }, null, .{ .presentation = .{ .composition = .{ .rendered_text = "Source value.", .issue = issue } }, .fields = .{ .replacement = .{ .inherited = .spec_title } } }));
    try std.testing.expectError(error.InvalidAtomicRepair, Contract.packet(a, authorization, base, .{ .bytes = "replacement" }, null, .{ .presentation = .structured, .fields = .{ .replacement = .{} } }));
    const selected = try @import("domain/model_candidate_json.zig").selectedFieldBindings(Replacement, a, .value, .{ .inherited = .spec_title });
    const selected_request = try Contract.packet(std.testing.allocator, authorization, base, .{ .bytes = "replacement" }, null, .{ .presentation = .structured, .fields = .{ .selected = selected } });
    defer packets.release(selected_request);
    try std.testing.expectEqualDeep(selected, selected_request.fieldPolicies());
    try std.testing.expect(selected.ptr != selected_request.fieldPolicies().ptr);
    const duplicate = [_]@import("domain/model_text_field.zig").Binding{ selected[0], selected[0] };
    try std.testing.expectError(error.InvalidAtomicRepair, Contract.packet(a, authorization, base, .{ .bytes = "replacement" }, null, .{ .presentation = .structured, .fields = .{ .selected = &duplicate } }));
}
