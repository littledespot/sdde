const std = @import("std");
const advance_attempt = @import("actions/model/advance_model_attempt_accounting.zig");
const attempt_runner = @import("application/model_attempt_accounting_runner.zig");
const request_runner = @import("application/model_request_identity_runner.zig");
const binding = @import("domain/llm_provider_binding.zig");
const identity = @import("domain/model_request_identity.zig");
const pipeline = @import("domain/pipeline.zig");
const accounting = @import("domain/model_attempt_accounting.zig");
const workflow = @import("domain/workflow.zig");
const workflow_retry = @import("domain/workflow_retry.zig");

test "initial attempt is separate from explicitly bounded retries" {
    var requests = request_runner.Runner.init(std.testing.allocator);
    defer requests.deinit();
    try requests.initialize(.{ .bytes = "epoch-1" }, identity.RequestPurposeRegistry.all());
    const request = try requests.assign(
        .initial,
        unitOwner("cluster-1"),
        modelOperation("generate"),
        .initial_generation,
    );

    var attempts = try attempt_runner.Runner.init(std.testing.allocator, .{ .bytes = "epoch-1" });
    defer attempts.deinit();
    try expectOrdinal(1, try attempts.reserve(.initial, requests.ledger().?, .{ .value = 1 }, request, .initial));
    try expectOrdinal(2, try attempts.reserve(.{ .value = 1 }, requests.ledger().?, .{ .value = 1 }, request, .{ .retry = retryAuthority(2) }));
    try expectOrdinal(3, try attempts.reserve(.{ .value = 2 }, requests.ledger().?, .{ .value = 1 }, request, .{ .retry = retryAuthority(2) }));
    try std.testing.expectError(
        error.ModelRetryLimitExhausted,
        attempts.reserve(.{ .value = 3 }, requests.ledger().?, .{ .value = 1 }, request, .{ .retry = retryAuthority(2) }),
    );
    try std.testing.expectEqual(@as(u32, 3), attempts.current().attemptsReserved(request));
}

test "attempt classification rejects hidden retry and repeated initial" {
    var requests = request_runner.Runner.init(std.testing.allocator);
    defer requests.deinit();
    try requests.initialize(.{ .bytes = "epoch-1" }, identity.RequestPurposeRegistry.all());
    const request = try requests.assign(
        .initial,
        unitOwner("cluster-1"),
        modelOperation("generate"),
        .initial_generation,
    );
    var attempts = try attempt_runner.Runner.init(std.testing.allocator, .{ .bytes = "epoch-1" });
    defer attempts.deinit();

    try std.testing.expectError(
        error.InvalidAttemptClassification,
        attempts.reserve(.initial, requests.ledger().?, .{ .value = 1 }, request, .{ .retry = retryAuthority(1) }),
    );
    _ = try attempts.reserve(.initial, requests.ledger().?, .{ .value = 1 }, request, .initial);
    try std.testing.expectError(
        error.InvalidAttemptClassification,
        attempts.reserve(.{ .value = 1 }, requests.ledger().?, .{ .value = 1 }, request, .initial),
    );
    try std.testing.expectError(
        error.ModelRetryLimitExhausted,
        attempts.reserve(.{ .value = 1 }, requests.ledger().?, .{ .value = 1 }, request, .{ .retry = retryAuthority(0) }),
    );

    var foreign = retryAuthority(2);
    foreign.workflow_id = workflow.WorkflowId.parse("foreign-flow").?;
    try std.testing.expectError(
        error.InvalidAttemptClassification,
        attempts.reserve(.{ .value = 1 }, requests.ledger().?, .{ .value = 1 }, request, .{ .retry = foreign }),
    );
    var wrong_operation = retryAuthority(2);
    wrong_operation.operation_instance_id = workflow.WorkflowStepId.parse("repair").?;
    try std.testing.expectError(
        error.InvalidAttemptClassification,
        attempts.reserve(.{ .value = 1 }, requests.ledger().?, .{ .value = 1 }, request, .{ .retry = wrong_operation }),
    );
    try std.testing.expectEqual(@as(u64, 1), attempts.current().revision().value);
}

test "attempt and request revisions plus lifecycle reject stale or terminal reservations" {
    var requests = request_runner.Runner.init(std.testing.allocator);
    defer requests.deinit();
    try requests.initialize(.{ .bytes = "epoch-1" }, identity.RequestPurposeRegistry.all());
    const request = try requests.assign(
        .initial,
        unitOwner("cluster-1"),
        modelOperation("generate"),
        .initial_generation,
    );
    var attempts = try attempt_runner.Runner.init(std.testing.allocator, .{ .bytes = "epoch-1" });
    defer attempts.deinit();

    try std.testing.expectError(
        error.ModelAttemptAccountingRevisionConflict,
        attempts.reserve(.{ .value = 1 }, requests.ledger().?, .{ .value = 1 }, request, .initial),
    );
    _ = try requests.assign(
        .{ .value = 1 },
        unitOwner("cluster-2"),
        modelOperation("generate"),
        .initial_generation,
    );
    try std.testing.expectError(
        error.ModelRequestLedgerRevisionConflict,
        attempts.reserve(.initial, requests.ledger().?, .{ .value = 1 }, request, .initial),
    );
    try requests.advance(.{ .value = 2 }, request, .assigned, .{ .terminal = .not_invoked_authorization_failure });
    try std.testing.expectError(
        error.ModelRequestUnavailableForAttempt,
        attempts.reserve(.initial, requests.ledger().?, .{ .value = 3 }, request, .initial),
    );
}

test "attempt action proposes one runner-applied transition" {
    var requests = request_runner.Runner.init(std.testing.allocator);
    defer requests.deinit();
    try requests.initialize(.{ .bytes = "epoch-1" }, identity.RequestPurposeRegistry.all());
    const request = try requests.assign(
        .initial,
        unitOwner("cluster-1"),
        modelOperation("generate"),
        .initial_generation,
    );
    const owner = try accounting.createInitial(std.testing.allocator, .{ .bytes = "epoch-1" });
    defer accounting.deinitOwner(owner);
    const current = accounting.accounting(owner);
    const delta = try (advance_attempt.Action{}).execute(
        current,
        .initial,
        requests.ledger().?,
        .{ .value = 1 },
        request,
        .initial,
    );

    const envelope = pipeline.PipelineEnvelope.init(&.{.model_request_identity_ledger});
    _ = try envelope.apply(advance_attempt.Action.contract, delta);
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
    var foreign_requests = request_runner.Runner.init(std.testing.allocator);
    defer foreign_requests.deinit();
    try foreign_requests.initialize(.{ .bytes = "epoch-2" }, identity.RequestPurposeRegistry.all());
    const foreign = try foreign_requests.assign(
        .initial,
        unitOwner("cluster-1"),
        modelOperation("generate"),
        .initial_generation,
    );
    var attempts = try attempt_runner.Runner.init(std.testing.allocator, .{ .bytes = "epoch-1" });
    defer attempts.deinit();
    try std.testing.expectError(
        error.ModelRequestUnavailableForAttempt,
        attempts.reserve(.initial, foreign_requests.ledger().?, .{ .value = 1 }, foreign, .initial),
    );
}

fn expectOrdinal(expected: u32, actual: @import("domain/llm_provider_operation.zig").ModelAttemptOrdinal) !void {
    try std.testing.expectEqual(expected, actual.value);
}

fn retryAuthority(limit: u32) workflow_retry.CompiledAuthority {
    return .{
        .workflow_id = workflow.WorkflowId.parse("arbitrary-flow").?,
        .workflow_version = 1,
        .operation_instance_id = workflow.WorkflowStepId.parse("generate").?,
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
