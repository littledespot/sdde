const std = @import("std");
const advance_attempt = @import("actions/model/advance_model_attempt_accounting.zig");
const attempt_runner = @import("model_attempt_test_fixture.zig");
const request_runner = @import("model_request_identity_runner_test_fixture.zig");
const binding = @import("domain/llm_provider_binding.zig");
const identity = @import("domain/model_request_identity.zig");
const pipeline = @import("domain/pipeline.zig");
const accounting = @import("domain/model_attempt_accounting.zig");
const workflow = @import("domain/workflow.zig");
const workflow_retry = @import("domain/workflow_retry.zig");

test "initial attempt is separate from explicitly bounded retries" {
    var requests = request_runner.Runner.init(std.testing.allocator);
    defer requests.deinit();
    try requests.initialize(identity.RequestPurposeRegistry.all());
    const request = try requests.assign(
        .initial,
        unitOwner("cluster-1"),
        modelOperation("generate"),
        .initial_generation,
    );

    var attempts = try attempt_runner.Runner.init(std.testing.allocator, requests.ledger().?.stageRunEpochId());
    defer attempts.deinit();
    try expectOrdinal(1, try attempts.reserve(.initial, requests.ledger().?, requests.providerOperations().current(), .{ .value = 1 }, request, .initial));
    try expectOrdinal(2, try attempts.reserve(.{ .value = 1 }, requests.ledger().?, requests.providerOperations().current(), .{ .value = 1 }, request, .{ .retry = .{ .authority = retryAuthority(2), .completed_retries = 0 } }));
    try expectOrdinal(3, try attempts.reserve(.{ .value = 2 }, requests.ledger().?, requests.providerOperations().current(), .{ .value = 1 }, request, .{ .retry = .{ .authority = retryAuthority(2), .completed_retries = 1 } }));
    try std.testing.expectError(
        error.ModelRetryLimitExhausted,
        attempts.reserve(.{ .value = 3 }, requests.ledger().?, requests.providerOperations().current(), .{ .value = 1 }, request, .{ .retry = .{ .authority = retryAuthority(2), .completed_retries = 2 } }),
    );
    try std.testing.expectEqual(@as(u32, 3), attempts.current().attemptsReserved(request));
}

test "attempt classification rejects hidden retry and repeated initial" {
    var requests = request_runner.Runner.init(std.testing.allocator);
    defer requests.deinit();
    try requests.initialize(identity.RequestPurposeRegistry.all());
    const request = try requests.assign(
        .initial,
        unitOwner("cluster-1"),
        modelOperation("generate"),
        .initial_generation,
    );
    var attempts = try attempt_runner.Runner.init(std.testing.allocator, requests.ledger().?.stageRunEpochId());
    defer attempts.deinit();

    try std.testing.expectError(
        error.InvalidAttemptClassification,
        attempts.reserve(.initial, requests.ledger().?, requests.providerOperations().current(), .{ .value = 1 }, request, .{ .retry = .{ .authority = retryAuthority(1), .completed_retries = 0 } }),
    );
    _ = try attempts.reserve(.initial, requests.ledger().?, requests.providerOperations().current(), .{ .value = 1 }, request, .initial);
    try std.testing.expectError(
        error.InvalidAttemptClassification,
        attempts.reserve(.{ .value = 1 }, requests.ledger().?, requests.providerOperations().current(), .{ .value = 1 }, request, .initial),
    );
    try std.testing.expectError(
        error.ModelRetryLimitExhausted,
        attempts.reserve(.{ .value = 1 }, requests.ledger().?, requests.providerOperations().current(), .{ .value = 1 }, request, .{ .retry = .{ .authority = retryAuthority(0), .completed_retries = 0 } }),
    );

    var foreign = retryAuthority(2);
    foreign.workflow_id = workflow.WorkflowId.parse("foreign-flow").?;
    try std.testing.expectError(
        error.InvalidAttemptClassification,
        attempts.reserve(.{ .value = 1 }, requests.ledger().?, requests.providerOperations().current(), .{ .value = 1 }, request, .{ .retry = .{ .authority = foreign, .completed_retries = 0 } }),
    );
    var wrong_operation = retryAuthority(2);
    wrong_operation.operation_instance_id = .{ .bytes = "" };
    try std.testing.expectError(
        error.InvalidAttemptClassification,
        attempts.reserve(.{ .value = 1 }, requests.ledger().?, requests.providerOperations().current(), .{ .value = 1 }, request, .{ .retry = .{ .authority = wrong_operation, .completed_retries = 0 } }),
    );
    try std.testing.expectEqual(@as(u64, 1), attempts.current().revision().value);
}

test "a retry runs only while the retries already made are under the limit, at any count" {
    var requests = request_runner.Runner.init(std.testing.allocator);
    defer requests.deinit();
    try requests.initialize(identity.RequestPurposeRegistry.all());
    const request = try requests.assign(.initial, unitOwner("cluster-1"), modelOperation("generate"), .initial_generation);
    var attempts = try attempt_runner.Runner.init(std.testing.allocator, requests.ledger().?.stageRunEpochId());
    defer attempts.deinit();
    var revision: u64 = 0;
    try expectOrdinal(1, try attempts.reserve(.{ .value = revision }, requests.ledger().?, requests.providerOperations().current(), .{ .value = 1 }, request, .initial));
    revision += 1;
    // Limit 1 allows one retry: the retry after no completed retries runs, the next does not.
    try expectOrdinal(2, try attempts.reserve(.{ .value = revision }, requests.ledger().?, requests.providerOperations().current(), .{ .value = 1 }, request, .{ .retry = .{ .authority = retryAuthority(1), .completed_retries = 0 } }));
    revision += 1;
    // The widest limit admits the last retry below it, and a count at the limit or at the top of u64 never wraps to admitted.
    const widest = std.math.maxInt(u32);
    try expectOrdinal(3, try attempts.reserve(.{ .value = revision }, requests.ledger().?, requests.providerOperations().current(), .{ .value = 1 }, request, .{ .retry = .{ .authority = retryAuthority(widest), .completed_retries = widest - 1 } }));
    revision += 1;
    for ([_]struct { limit: u32, completed: u64 }{
        .{ .limit = 1, .completed = 1 },
        .{ .limit = 1, .completed = std.math.maxInt(u64) },
        .{ .limit = widest, .completed = widest },
        .{ .limit = widest, .completed = std.math.maxInt(u64) },
    }) |case| {
        try std.testing.expectError(
            error.ModelRetryLimitExhausted,
            attempts.reserve(.{ .value = revision }, requests.ledger().?, requests.providerOperations().current(), .{ .value = 1 }, request, .{ .retry = .{ .authority = retryAuthority(case.limit), .completed_retries = case.completed } }),
        );
    }
    try std.testing.expectEqual(@as(u32, 3), attempts.current().attemptsReserved(request));
}

test "attempt and request revisions plus lifecycle reject stale or terminal reservations" {
    var requests = request_runner.Runner.init(std.testing.allocator);
    defer requests.deinit();
    try requests.initialize(identity.RequestPurposeRegistry.all());
    const request = try requests.assign(
        .initial,
        unitOwner("cluster-1"),
        modelOperation("generate"),
        .initial_generation,
    );
    var attempts = try attempt_runner.Runner.init(std.testing.allocator, requests.ledger().?.stageRunEpochId());
    defer attempts.deinit();

    try std.testing.expectError(
        error.ModelAttemptAccountingRevisionConflict,
        attempts.reserve(.{ .value = 1 }, requests.ledger().?, requests.providerOperations().current(), .{ .value = 1 }, request, .initial),
    );
    _ = try requests.assign(
        .{ .value = 1 },
        unitOwner("cluster-2"),
        modelOperation("generate"),
        .initial_generation,
    );
    try std.testing.expectError(
        error.ModelRequestLedgerRevisionConflict,
        attempts.reserve(.initial, requests.ledger().?, requests.providerOperations().current(), .{ .value = 1 }, request, .initial),
    );
    try requests.advance(.{ .value = 2 }, request, .assigned, .{ .terminal = .not_invoked_authorization_failure });
    try std.testing.expectError(
        error.ModelRequestUnavailableForAttempt,
        attempts.reserve(.initial, requests.ledger().?, requests.providerOperations().current(), .{ .value = 3 }, request, .initial),
    );
}

test "attempt action proposes one runner-applied transition" {
    var requests = request_runner.Runner.init(std.testing.allocator);
    defer requests.deinit();
    try requests.initialize(identity.RequestPurposeRegistry.all());
    const request = try requests.assign(
        .initial,
        unitOwner("cluster-1"),
        modelOperation("generate"),
        .initial_generation,
    );
    const owner = try accounting.createInitial(std.testing.allocator, requests.ledger().?.stageRunEpochId());
    defer accounting.deinitOwner(owner);
    const current = accounting.accounting(owner);
    const delta = try (advance_attempt.Action{}).execute(
        current,
        .initial,
        requests.ledger().?,
        requests.providerOperations().current(),
        .{ .value = 1 },
        request,
        .initial,
    );

    const envelope = pipeline.DataShape.init(&.{.model_request_identity_ledger});
    _ = try envelope.applyDelta(advance_attempt.Action.contract, &delta);
    const transition = switch (delta.runner_accounting_transition.?) {
        .increment_model_attempt => |value| value,
        else => unreachable,
    };
    var forged = transition;
    forged.next_request_value = 2;
    try std.testing.expectError(error.ModelAttemptValueConflict, accounting.apply(current, forged));
    const successor = try accounting.apply(current, transition);
    defer accounting.deinitOwner(successor);
    try std.testing.expectEqual(@as(u32, 1), accounting.accounting(successor).attemptsReserved(request));
}

test "attempt reservation rejects a request from another stage epoch" {
    var requests = request_runner.Runner.init(std.testing.allocator);
    defer requests.deinit();
    try requests.initialize(identity.RequestPurposeRegistry.all());
    var foreign_requests = request_runner.Runner.init(std.testing.allocator);
    defer foreign_requests.deinit();
    try foreign_requests.initialize(identity.RequestPurposeRegistry.all());
    const foreign = try foreign_requests.assign(
        .initial,
        unitOwner("cluster-1"),
        modelOperation("generate"),
        .initial_generation,
    );
    var attempts = try attempt_runner.Runner.init(std.testing.allocator, requests.ledger().?.stageRunEpochId());
    defer attempts.deinit();
    try std.testing.expectError(
        error.ModelRequestUnavailableForAttempt,
        attempts.reserve(.initial, foreign_requests.ledger().?, foreign_requests.providerOperations().current(), .{ .value = 1 }, foreign, .initial),
    );
    const forged = try accounting.propose(attempts.current(), .initial, foreign, .initial);
    try std.testing.expectError(error.ModelAttemptAccountingEpochConflict, accounting.apply(attempts.current(), forged));
}

test "attempt accounting allocation failures keep the current owner and release every owner" {
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(accountingAllocationCase, .{});
}

/// Drives the accounting owner's two builders: the initial owner and two successors (the second
/// links a previous owner that already links one). Whichever allocation fails, the runner still
/// holds the accounting it held before the call, and the leak check proves each partial owner and
/// each retained previous owner was released.
fn accountingAllocationCase(allocator: std.mem.Allocator) !void {
    var requests = request_runner.Runner.init(allocator);
    defer requests.deinit();
    try requests.initialize(identity.RequestPurposeRegistry.all());
    const request = try requests.assign(.initial, unitOwner("cluster-1"), modelOperation("generate"), .initial_generation);
    var attempts = try attempt_runner.Runner.init(allocator, requests.ledger().?.stageRunEpochId());
    defer attempts.deinit();

    const first_before = attempts.current();
    _ = attempts.reserve(.initial, requests.ledger().?, requests.providerOperations().current(), .{ .value = 1 }, request, .initial) catch |err| {
        try expectAccounting(&attempts, first_before, 0, request, 0);
        return err;
    };
    try expectAccounting(&attempts, null, 1, request, 1);

    const second_before = attempts.current();
    _ = attempts.reserve(.{ .value = 1 }, requests.ledger().?, requests.providerOperations().current(), .{ .value = 1 }, request, .{ .retry = .{ .authority = retryAuthority(2), .completed_retries = 0 } }) catch |err| {
        try expectAccounting(&attempts, second_before, 1, request, 1);
        return err;
    };
    try expectAccounting(&attempts, null, 2, request, 2);

    const third_before = attempts.current();
    _ = attempts.reserve(.{ .value = 2 }, requests.ledger().?, requests.providerOperations().current(), .{ .value = 1 }, request, .{ .retry = .{ .authority = retryAuthority(2), .completed_retries = 1 } }) catch |err| {
        try expectAccounting(&attempts, third_before, 2, request, 2);
        return err;
    };
    try expectAccounting(&attempts, null, 3, request, 3);
}

/// The runner's accounting is `same` when one is given, at `revision` with `reserved` attempts
/// for `request`.
fn expectAccounting(
    attempts: *const attempt_runner.Runner,
    same: ?*const accounting.RunnerModelAttemptAccounting,
    revision: u64,
    request: *const identity.ModelRequestId,
    reserved: u32,
) !void {
    const current = attempts.current();
    if (same) |expected| try std.testing.expect(current == expected);
    try std.testing.expectEqual(revision, current.revision().value);
    try std.testing.expectEqual(reserved, current.attemptsReserved(request));
}

fn expectOrdinal(expected: u32, actual: @import("domain/llm_provider_operation.zig").ModelAttemptOrdinal) !void {
    try std.testing.expectEqual(expected, actual.value);
}

fn retryAuthority(limit: u32) workflow_retry.CompiledAuthority {
    return .{
        .workflow_id = workflow.WorkflowId.parse("arbitrary-flow").?,
        .workflow_version = 1,
        .operation_instance_id = workflow.WorkflowStepId.parse("account").?,
        .limit = .{ .value = limit },
    };
}

fn unitOwner(cluster_id: []const u8) identity.ImmutableUnitOwnerId {
    return .{ .task_cluster = .{
        .plan_state_id = .{ .bytes = "plan-state-1" },
        .obligation_cluster_id = .{ .bytes = cluster_id },
    } };
}

fn modelOperation(step_id: []const u8) binding.WorkflowModelOperationId {
    return .{
        .workflow_id = workflow.WorkflowId.parse("arbitrary-flow").?,
        .workflow_version = 1,
        .workflow_step_id = workflow.WorkflowStepId.parse(step_id).?,
    };
}
