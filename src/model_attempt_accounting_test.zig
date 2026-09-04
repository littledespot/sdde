const std = @import("std");
const advance_attempt = @import("actions/model/advance_model_attempt_accounting.zig");
const attempt_runner = @import("application/model_attempt_accounting_runner.zig");
const request_runner = @import("application/model_request_identity_runner.zig");
const binding = @import("domain/llm_provider_binding.zig");
const identity = @import("domain/model_request_identity.zig");
const pipeline = @import("domain/pipeline.zig");
const accounting = @import("domain/runner_repair_accounting.zig");
const workflow = @import("domain/workflow.zig");

test "runner reserves request-local attempt ordinals in one stage accounting ledger" {
    var requests = request_runner.Runner.init(std.testing.allocator);
    defer requests.deinit();
    try requests.initialize(.{ .bytes = "epoch-1" }, identity.RequestPurposeRegistry.all());
    const first = try requests.assign(
        .initial,
        unitOwner("cluster-1"),
        modelOperation("generate"),
        .initial_generation,
    );
    const second = try requests.assign(
        .{ .value = 1 },
        unitOwner("cluster-2"),
        modelOperation("generate"),
        .initial_generation,
    );

    var attempts = try attempt_runner.Runner.init(std.testing.allocator, .{ .bytes = "epoch-1" });
    defer attempts.deinit();
    const maximum = accounting.MaximumAttempts.init(4, 3).?;
    try expectOrdinal(1, try attempts.reserve(.initial, requests.ledger().?, .{ .value = 2 }, first, maximum));
    try expectOrdinal(2, try attempts.reserve(.{ .value = 1 }, requests.ledger().?, .{ .value = 2 }, first, maximum));
    try expectOrdinal(1, try attempts.reserve(.{ .value = 2 }, requests.ledger().?, .{ .value = 2 }, second, maximum));

    var copied_first = first.*;
    try expectOrdinal(3, try attempts.reserve(
        .{ .value = 3 },
        requests.ledger().?,
        .{ .value = 2 },
        &copied_first,
        maximum,
    ));
    try std.testing.expectEqual(@as(u64, 4), attempts.current().revision().value);
    try std.testing.expectEqual(@as(u32, 3), attempts.current().attemptsReserved(first));
    try std.testing.expectEqual(@as(u32, 1), attempts.current().attemptsReserved(second));
}

test "configured and hard attempt ceilings use their strict minimum atomically" {
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
    const maximum = accounting.MaximumAttempts.init(3, 2).?;
    try std.testing.expectEqual(@as(u32, 2), maximum.effective());
    try std.testing.expectEqual(@as(u32, 2), accounting.MaximumAttempts.init(2, 3).?.effective());
    _ = try attempts.reserve(.initial, requests.ledger().?, .{ .value = 1 }, request, maximum);
    _ = try attempts.reserve(.{ .value = 1 }, requests.ledger().?, .{ .value = 1 }, request, maximum);
    try std.testing.expectError(
        error.ModelAttemptCeilingExhausted,
        attempts.reserve(.{ .value = 2 }, requests.ledger().?, .{ .value = 1 }, request, maximum),
    );
    try std.testing.expectError(
        error.InvalidMaximumAttempts,
        attempts.reserve(
            .{ .value = 2 },
            requests.ledger().?,
            .{ .value = 1 },
            request,
            .{ .configured = 0, .hard = 2 },
        ),
    );
    try std.testing.expect(accounting.MaximumAttempts.init(1, 0) == null);
    try std.testing.expectEqual(@as(u64, 2), attempts.current().revision().value);
    try std.testing.expectEqual(@as(u32, 2), attempts.current().attemptsReserved(request));
}

test "accounting and request CAS plus request lifecycle reject invalid reservations" {
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
    const maximum = accounting.MaximumAttempts.init(2, 2).?;

    try std.testing.expectError(
        error.RepairAccountingRevisionConflict,
        attempts.reserve(.{ .value = 1 }, requests.ledger().?, .{ .value = 1 }, request, maximum),
    );
    _ = try requests.assign(
        .{ .value = 1 },
        unitOwner("cluster-2"),
        modelOperation("generate"),
        .initial_generation,
    );
    try std.testing.expectError(
        error.ModelRequestLedgerRevisionConflict,
        attempts.reserve(.initial, requests.ledger().?, .{ .value = 1 }, request, maximum),
    );
    try requests.advance(.{ .value = 2 }, request, .assigned, .{ .terminal = .not_invoked_attempt_ceiling });
    try std.testing.expectError(
        error.ModelRequestUnavailableForAttempt,
        attempts.reserve(.initial, requests.ledger().?, .{ .value = 3 }, request, maximum),
    );
    try std.testing.expectEqual(@as(u64, 0), attempts.current().revision().value);
    try std.testing.expectEqual(@as(u32, 0), attempts.current().attemptsReserved(request));
}

test "one logical request keeps its accounting identity across lifecycle snapshots" {
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
    const maximum = accounting.MaximumAttempts.init(3, 3).?;

    try expectOrdinal(1, try attempts.reserve(.initial, requests.ledger().?, .{ .value = 1 }, request, maximum));
    try requests.advance(.{ .value = 1 }, request, .assigned, .invoked);
    try std.testing.expect(requests.ledger().?.canonicalRequestId(request).? == request);
    try expectOrdinal(2, try attempts.reserve(
        .{ .value = 1 },
        requests.ledger().?,
        .{ .value = 2 },
        request,
        maximum,
    ));
    try std.testing.expectEqual(@as(u32, 2), attempts.current().attemptsReserved(request));
}

test "attempt action only proposes the exact declared runner accounting delta" {
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
        accounting.MaximumAttempts.init(2, 2).?,
    );

    try std.testing.expectEqual(@as(u64, 0), current.revision().value);
    try std.testing.expectEqual(@as(u32, 0), current.attemptsReserved(request));
    const envelope = pipeline.PipelineEnvelope.init(&.{.model_request_identity_ledger});
    _ = try envelope.apply(advance_attempt.Action.contract, delta);
    try std.testing.expectError(
        error.MissingRunnerAccountingTransition,
        envelope.apply(
            advance_attempt.Action.contract,
            pipeline.NodeDelta.successful(advance_attempt.Action.contract),
        ),
    );
    const ordinary: pipeline.NodeContract = .{
        .id = "ordinary@1",
        .kind = .action,
        .requires = &.{.model_request_identity_ledger},
        .produces = &.{},
        .side_effect = .none,
    };
    try std.testing.expectError(
        error.UndeclaredRunnerAccountingTransition,
        envelope.apply(ordinary, delta),
    );

    const transition = switch (delta.runner_accounting_transition.?) {
        .increment_model_attempt => |value| value,
    };
    var forged = transition;
    forged.next_request_value = 2;
    try std.testing.expectError(error.ModelAttemptValueConflict, accounting.apply(current, forged));
    const successor = try accounting.apply(current, transition);
    defer accounting.deinitOwner(successor);
    try std.testing.expectEqual(@as(u32, 0), current.attemptsReserved(request));
    try std.testing.expectEqual(@as(u32, 1), accounting.accounting(successor).attemptsReserved(request));
    try std.testing.expectError(
        error.RepairAccountingRevisionConflict,
        accounting.apply(accounting.accounting(successor), transition),
    );
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
        attempts.reserve(
            .initial,
            foreign_requests.ledger().?,
            .{ .value = 1 },
            foreign,
            accounting.MaximumAttempts.init(2, 2).?,
        ),
    );
    try std.testing.expectEqual(@as(u64, 0), attempts.current().revision().value);
}

fn expectOrdinal(expected: u32, actual: @import("domain/llm_provider_operation.zig").ModelAttemptOrdinal) !void {
    try std.testing.expectEqual(expected, actual.value);
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
