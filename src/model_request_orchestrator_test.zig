const std = @import("std");
const execution = @import("domain/workflow_execution.zig");
const workflow = @import("domain/workflow.zig");
const orchestrator = @import("application/model_request_orchestrator.zig");
const bindings = @import("application/model_request_child_bindings.zig");
const kernel = @import("domain/model_request_kernel.zig");

const Stage = bindings.Stage;

/// One scripted answer: the `nth` invocation (0-based) of `stage` answers `applied`. With
/// `repeat`, every later invocation of the stage answers the same. Any other invocation is `ok`.
const Answer = struct {
    stage: Stage,
    nth: usize = 0,
    applied: execution.Applied,
    repeat: bool = false,
};

/// A spy child binding: it records the stage sequence the orchestrator asks for and answers
/// from its script. It holds no port, so it can only show what the orchestrator itself does.
const Spy = struct {
    answers: []const Answer = &.{},
    seen: std.ArrayList(Stage) = .empty,
    counts: std.EnumArray(Stage, usize) = .initFill(0),

    fn deinit(self: *Spy) void {
        self.seen.deinit(std.testing.allocator);
    }

    fn children(self: *Spy) bindings.ChildBindings {
        return .{ .context = self, .vtable = &vtable };
    }

    fn invoke(context: *anyopaque, stage: Stage) execution.Applied {
        const self: *Spy = @ptrCast(@alignCast(context));
        self.seen.append(std.testing.allocator, stage) catch @panic("allocation");
        const nth = self.counts.get(stage);
        self.counts.set(stage, nth + 1);
        for (self.answers) |answer| {
            if (answer.stage == stage and (answer.nth == nth or (answer.repeat and nth > answer.nth))) return answer.applied;
        }
        return .{ .outcome = .ok };
    }

    const vtable: bindings.ChildBindings.VTable = .{ .invoke_stage = invoke };
};

/// An answer no invocation reaches, for a script slot a case does not need.
const never: Answer = .{ .stage = .prepare_request, .nth = 1_000, .applied = .{ .outcome = .ok } };

fn outcome(tag: workflow.OutcomeTag) execution.Applied {
    return .{ .outcome = tag };
}

fn expectStages(spy: *const Spy, expected: []const Stage) !void {
    try std.testing.expectEqualSlices(Stage, expected, spy.seen.items);
}

const first_attempt = [_]Stage{
    .prepare_request,
    .advance_attempt,
    .assign_operation,
    .prepare_authorization,
    .check_phase,
    .advance_request,
    .advance_operation,
    .invoke_model,
    .validate_observation,
    .complete_operation,
    .admit_response,
};

test "an admitted request runs the stages in the fixed order and closes once" {
    var spy: Spy = .{};
    defer spy.deinit();
    const result = orchestrator.run(spy.children());
    try std.testing.expectEqual(outcome(.ok), result);
    try expectStages(&spy, &(first_attempt ++ [_]Stage{.close_request}));
}

test "a later attempt skips the request-lifecycle advance when the phase check says more" {
    var spy: Spy = .{ .answers = &.{.{ .stage = .check_phase, .applied = outcome(.more) }} };
    defer spy.deinit();
    try std.testing.expectEqual(outcome(.ok), orchestrator.run(spy.children()));
    try std.testing.expectEqual(@as(usize, 0), spy.counts.get(.advance_request));
    try std.testing.expectEqual(@as(usize, 1), spy.counts.get(.advance_operation));
}

test "an invalid response takes one protocol correction and returns to attempt accounting" {
    var spy: Spy = .{ .answers = &.{.{ .stage = .admit_response, .applied = outcome(.invalid) }} };
    defer spy.deinit();
    try std.testing.expectEqual(outcome(.ok), orchestrator.run(spy.children()));
    try expectStages(&spy, &(first_attempt ++ [_]Stage{ .check_runaway, .build_protocol_retry } ++
        [_]Stage{ .advance_attempt, .assign_operation, .prepare_authorization, .check_phase, .advance_request, .advance_operation, .invoke_model, .validate_observation, .complete_operation, .admit_response, .close_request }));
}

test "a runaway takes the re-send, not the correction" {
    var spy: Spy = .{ .answers = &.{
        .{ .stage = .admit_response, .applied = outcome(.invalid) },
        .{ .stage = .check_runaway, .applied = outcome(.more) },
    } };
    defer spy.deinit();
    try std.testing.expectEqual(outcome(.ok), orchestrator.run(spy.children()));
    try std.testing.expectEqual(@as(usize, 1), spy.counts.get(.build_runaway_resend));
    try std.testing.expectEqual(@as(usize, 0), spy.counts.get(.build_protocol_retry));
    try std.testing.expectEqual(@as(usize, 2), spy.counts.get(.advance_attempt));
}

test "a failed or cancelled model call still flows through observation, completion, admission and closure" {
    for ([_]workflow.OutcomeTag{ .failed, .cancelled }) |tag| {
        var spy: Spy = .{ .answers = &.{
            .{ .stage = .invoke_model, .applied = outcome(tag) },
            .{ .stage = .validate_observation, .applied = outcome(tag) },
            .{ .stage = .complete_operation, .applied = outcome(tag) },
            .{ .stage = .admit_response, .applied = outcome(tag) },
            .{ .stage = .close_request, .applied = outcome(tag) },
        } };
        defer spy.deinit();
        try std.testing.expectEqual(outcome(tag), orchestrator.run(spy.children()));
        try expectStages(&spy, &(first_attempt ++ [_]Stage{.close_request}));
    }
}

test "closure ends the request with its own outcome" {
    for ([_]workflow.OutcomeTag{ .ok, .invalid, .failed, .cancelled }) |tag| {
        var spy: Spy = .{ .answers = &.{.{ .stage = .close_request, .applied = outcome(tag) }} };
        defer spy.deinit();
        try std.testing.expectEqual(outcome(tag), orchestrator.run(spy.children()));
        try std.testing.expectEqual(Stage.close_request, spy.seen.items[spy.seen.items.len - 1]);
    }
}

test "a request that cannot be authorized terminates its operation and then itself, before any call" {
    for ([_]workflow.OutcomeTag{ .failed, .cancelled }) |tag| {
        var spy: Spy = .{ .answers = &.{
            .{ .stage = .prepare_authorization, .applied = outcome(tag) },
            .{ .stage = .terminate_operation, .applied = outcome(tag) },
            .{ .stage = .terminate_request, .applied = outcome(tag) },
        } };
        defer spy.deinit();
        try std.testing.expectEqual(outcome(tag), orchestrator.run(spy.children()));
        try expectStages(&spy, &.{ .prepare_request, .advance_attempt, .assign_operation, .prepare_authorization, .terminate_operation, .terminate_request });
    }
}

test "a stage that fails before the call ends the request without closing it" {
    for ([_]Stage{ .prepare_request, .advance_attempt, .assign_operation, .check_phase, .advance_request, .advance_operation }) |stage| {
        var spy: Spy = .{ .answers = &.{.{ .stage = stage, .applied = outcome(.failed) }} };
        defer spy.deinit();
        try std.testing.expectEqual(outcome(.failed), orchestrator.run(spy.children()));
        try std.testing.expectEqual(stage, spy.seen.items[spy.seen.items.len - 1]);
    }
}

test "a runner rejection ends the request at once and is returned unchanged" {
    const rejections = [_]execution.Rejection{ .cancelled, .deadline_exhausted, .authority, .{ .operation_failed = error.OperationExecutionFailed } };
    for (rejections) |rejection| {
        for ([_]Stage{ .prepare_request, .invoke_model, .admit_response, .close_request, .build_protocol_retry }) |stage| {
            // Only the correction stage needs an invalid response to be reached.
            const reach: Answer = if (stage == .build_protocol_retry) .{ .stage = .admit_response, .applied = outcome(.invalid) } else never;
            var spy: Spy = .{ .answers = &.{
                reach,
                .{ .stage = stage, .applied = .{ .rejected = rejection } },
            } };
            defer spy.deinit();
            const result = orchestrator.run(spy.children());
            try std.testing.expectEqualDeep(execution.Applied{ .rejected = rejection }, result);
            try std.testing.expectEqual(stage, spy.seen.items[spy.seen.items.len - 1]);
        }
    }
}

test "an outcome a stage's contract does not allow is an authority rejection and invokes nothing further" {
    const Case = struct { stage: Stage, tag: workflow.OutcomeTag, reach: Answer = never };
    const cases = [_]Case{
        .{ .stage = .prepare_request, .tag = .invalid },
        .{ .stage = .advance_attempt, .tag = .cancelled },
        .{ .stage = .check_phase, .tag = .cancelled },
        .{ .stage = .invoke_model, .tag = .invalid },
        .{ .stage = .invoke_model, .tag = .more },
        .{ .stage = .admit_response, .tag = .more },
        .{ .stage = .check_runaway, .tag = .failed, .reach = .{ .stage = .admit_response, .applied = .{ .outcome = .invalid } } },
        .{ .stage = .close_request, .tag = .more },
        .{ .stage = .terminate_operation, .tag = .ok, .reach = .{ .stage = .prepare_authorization, .applied = .{ .outcome = .failed } } },
    };
    for (cases) |case| {
        var spy: Spy = .{ .answers = &.{
            case.reach,
            .{ .stage = case.stage, .applied = outcome(case.tag) },
        } };
        defer spy.deinit();
        const result = orchestrator.run(spy.children());
        try std.testing.expectEqualDeep(execution.Applied{ .rejected = .authority }, result);
        try std.testing.expectEqual(case.stage, spy.seen.items[spy.seen.items.len - 1]);
    }
}

test "the orchestrator keeps no count of its own: only the runner bounds a request" {
    // An endless invalid response is the runner's to stop (its retry authority and the kernel
    // admission); a spy that never stops it proves the orchestrator adds no bound of its own.
    var spy: Spy = .{ .answers = &.{.{ .stage = .admit_response, .applied = outcome(.invalid), .repeat = true }} };
    defer spy.deinit();
    const stop_after = 1_000;
    var stopper: struct {
        spy: *Spy,
        fn invoke(context: *anyopaque, stage: Stage) execution.Applied {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (self.spy.seen.items.len >= stop_after) return .{ .rejected = .cancelled };
            return Spy.invoke(self.spy, stage);
        }
    } = .{ .spy = &spy };
    const result = orchestrator.run(.{ .context = &stopper, .vtable = &.{ .invoke_stage = @TypeOf(stopper).invoke } });
    try std.testing.expectEqualDeep(execution.Applied{ .rejected = .cancelled }, result);
    // Each pass through attempt accounting takes thirteen stages here, so a thousand stages are
    // dozens of attempts, far beyond any allowance: the orchestrator never stopped it.
    try std.testing.expect(spy.counts.get(.advance_attempt) > 50);
}

test "the transition table is closed: every stage is reached, every stage can finish, and a finish is a step outcome" {
    // Reachability from the first stage, and from every stage a path to a finish, by the table alone.
    var reached: std.EnumSet(Stage) = .initEmpty();
    reached.insert(.prepare_request);
    var changed = true;
    while (changed) {
        changed = false;
        for (std.enums.values(Stage)) |stage| if (reached.contains(stage)) for (std.enums.values(workflow.OutcomeTag)) |tag| {
            const following = kernel.next(stage, tag) orelse continue;
            switch (following) {
                .stage => |target| if (!reached.contains(target)) {
                    reached.insert(target);
                    changed = true;
                },
                .finish => |finish| try std.testing.expect(std.mem.indexOfScalar(workflow.OutcomeTag, &kernel.outcomes, finish) != null),
            }
        };
    }
    try std.testing.expectEqual(std.enums.values(Stage).len, reached.count());
    var finishes: std.EnumSet(Stage) = .initEmpty();
    changed = true;
    while (changed) {
        changed = false;
        for (std.enums.values(Stage)) |stage| if (!finishes.contains(stage)) for (std.enums.values(workflow.OutcomeTag)) |tag| {
            const following = kernel.next(stage, tag) orelse continue;
            if (following == .finish or finishes.contains(following.stage)) {
                finishes.insert(stage);
                changed = true;
                break;
            }
        };
    }
    try std.testing.expectEqual(std.enums.values(Stage).len, finishes.count());
}

test "a stage's registered outcomes must be exactly the ones the table follows" {
    try std.testing.expect(kernel.sameStageOutcomes(.check_phase, &.{ .ok, .more, .failed }));
    try std.testing.expect(kernel.sameStageOutcomes(.check_phase, &.{ .failed, .more, .ok }));
    // One outcome the table does not follow, one it follows that the contract lacks, and a stage
    // whose contract lists the outcomes of another.
    try std.testing.expect(!kernel.sameStageOutcomes(.check_phase, &.{ .ok, .more, .failed, .cancelled }));
    try std.testing.expect(!kernel.sameStageOutcomes(.check_phase, &.{ .ok, .failed }));
    try std.testing.expect(!kernel.sameStageOutcomes(.check_phase, &.{ .ok, .failed, .cancelled }));
    try std.testing.expect(!kernel.sameStageOutcomes(.close_request, &.{ .ok, .failed }));
}

test "a model call's action belongs to its caller's operation, or to the inference stage of a request-model step" {
    try std.testing.expect(kernel.callActionBelongsTo("invoke-model", "invoke-model"));
    try std.testing.expect(kernel.callActionBelongsTo(kernel.operation_id, Stage.invoke_model.name()));
    // Only the inference stage makes the call; no other stage and no other operation does.
    for (std.enums.values(Stage)) |stage| {
        try std.testing.expectEqual(stage == .invoke_model, kernel.callActionBelongsTo(kernel.operation_id, stage.name()));
    }
    try std.testing.expect(!kernel.callActionBelongsTo("retain-json-part", Stage.invoke_model.name()));
    try std.testing.expect(!kernel.callActionBelongsTo("invoke-model", kernel.operation_id));
}
