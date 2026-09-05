const std = @import("std");
const check_action = @import("actions/model/check_workflow_token_budget.zig");
const reconcile_action = @import("actions/model/reconcile_workflow_token_usage.zig");
const token_runner = @import("application/workflow_token_accounting_runner.zig");
const request_runner = @import("application/model_request_identity_runner.zig");
const identity = @import("domain/model_request_identity.zig");
const operation = @import("domain/llm_provider_operation.zig");
const accounting = @import("domain/workflow_token_accounting.zig");
const pipeline = @import("domain/pipeline.zig");
const workflow = @import("domain/workflow.zig");

test "actual usage accumulates across retries and executions remain isolated" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var first = token_runner.Runner.init(std.testing.allocator, .{ .value = 100 });
    defer first.deinit();
    var second = token_runner.Runner.init(std.testing.allocator, .{ .value = 100 });
    defer second.deinit();

    try first.check();
    try first.reconcile(.initial, fixture.inferenceId(1), usage(20, 10));
    try first.check();
    try first.reconcile(.{ .value = 1 }, fixture.inferenceId(2), usage(30, 5));
    try std.testing.expectEqual(@as(u128, 65), first.current().committed());
    try std.testing.expectEqual(@as(u128, 0), second.current().committed());
    try second.check();
}

test "overshooting call records all usage before error and blocks subsequent calls" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var runner = token_runner.Runner.init(std.testing.allocator, .{ .value = 50 });
    defer runner.deinit();

    try runner.check();
    try runner.reconcile(.initial, fixture.inferenceId(1), usage(20, 10));
    try runner.check(); // No maximum-output reservation or estimate.
    try std.testing.expectError(error.WorkflowTokenBudgetExceeded, runner.reconcile(.{ .value = 1 }, fixture.inferenceId(2), usage(15, 25)));
    try std.testing.expectEqual(@as(u128, 70), runner.current().committed());
    try std.testing.expectEqual(@as(u64, 2), runner.current().revision().value);
    try std.testing.expectError(error.WorkflowTokenBudgetExceeded, runner.check());
    try std.testing.expectError(error.TokenUsageAlreadyAccounted, runner.reconcile(.{ .value = 2 }, fixture.inferenceId(2), usage(15, 25)));
    try std.testing.expectEqual(@as(u128, 70), runner.current().committed());
}

test "exact budget permits the current result but no subsequent model call" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var runner = token_runner.Runner.init(std.testing.allocator, .{ .value = 50 });
    defer runner.deinit();
    try runner.reconcile(.initial, fixture.inferenceId(1), usage(20, 30));
    try std.testing.expectEqual(accounting.BudgetStatus.exhausted, runner.current().status());
    try std.testing.expectError(error.WorkflowTokenBudgetExceeded, runner.check());
}

test "unknown usage blocks without inventing a charge and not-sent adds none" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var runner = token_runner.Runner.init(std.testing.allocator, .{ .value = 100 });
    defer runner.deinit();
    try runner.reconcile(.initial, fixture.inferenceId(1), .not_sent);
    try runner.check();
    try std.testing.expectError(error.ProviderTokenUsageUnavailable, runner.reconcile(.{ .value = 1 }, fixture.inferenceId(2), .unavailable));
    try std.testing.expectEqual(@as(u128, 0), runner.current().committed());
    try std.testing.expectError(error.ProviderTokenUsageUnavailable, runner.check());
}

test "usage validation rejects malformed totals count operations stale and duplicate reports" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var runner = token_runner.Runner.init(std.testing.allocator, .{ .value = 100 });
    defer runner.deinit();
    const id = fixture.inferenceId(1);
    for ([_]u64{ 0, 10, 29, 31 }) |total| {
        try std.testing.expectError(error.InvalidProviderTokenUsage, runner.reconcile(.initial, id, .{ .exact_usage = .{
            .input_tokens = 20,
            .output_tokens = 10,
            .total_tokens = total,
        } }));
    }
    try std.testing.expect(operation.ProviderUsage.init(std.math.maxInt(u64), 1, std.math.maxInt(u64)) == null);
    var invalid = id;
    invalid.kind = .input_token_count;
    try std.testing.expectError(error.InvalidTokenAccountingOperation, runner.reconcile(.initial, invalid, usage(0, 0)));
    invalid = id;
    invalid.model_attempt_ordinal.value = 0;
    try std.testing.expectError(error.InvalidTokenAccountingOperation, runner.reconcile(.initial, invalid, .not_sent));
    try runner.reconcile(.initial, id, usage(20, 10));
    try std.testing.expectError(error.TokenAccountingRevisionConflict, runner.reconcile(.initial, fixture.inferenceId(2), usage(1, 1)));
    try std.testing.expectError(error.TokenUsageAlreadyAccounted, runner.reconcile(.{ .value = 1 }, id, .not_sent));
    try std.testing.expectEqual(@as(u128, 30), runner.current().committed());
}

test "large actual totals cannot wrap into an available budget" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var runner = token_runner.Runner.init(std.testing.allocator, .{ .value = std.math.maxInt(u64) });
    defer runner.deinit();
    try runner.reconcile(.initial, fixture.inferenceId(1), usage(std.math.maxInt(u64) - 1, 0));
    try runner.check();
    try std.testing.expectError(error.WorkflowTokenBudgetExceeded, runner.reconcile(.{ .value = 1 }, fixture.inferenceId(2), usage(2, 1)));
    try std.testing.expectEqual(@as(u128, std.math.maxInt(u64)) + 2, runner.current().committed());
    try std.testing.expectError(error.WorkflowTokenBudgetExceeded, runner.check());
    try std.testing.expect(accounting.TotalTokenBudget.init(0) == null);
}

test "check is read-only and reconciliation only proposes its declared transition" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var ledger = accounting.Ledger.init(std.testing.allocator, .{ .value = 10 }).?;
    defer ledger.deinit();
    try (check_action.Action{}).execute(&ledger);
    const delta = try (reconcile_action.Action{}).execute(&ledger, .initial, fixture.inferenceId(1), usage(20, 10));
    try std.testing.expectEqual(@as(u64, 0), ledger.revision().value);
    try std.testing.expectEqual(@as(u128, 0), ledger.committed());
    const shape = pipeline.DataShape.init(&.{});
    _ = try shape.applyDelta(reconcile_action.Action.contract, &delta);
    try std.testing.expectError(error.UndeclaredRunnerAccountingTransition, shape.applyDelta(check_action.Action.contract, &delta));
    const transition = delta.runner_accounting_transition.?.reconcile_workflow_tokens;
    try std.testing.expectEqual(accounting.BudgetStatus.exceeded, try ledger.applyReconciliation(transition));
    try std.testing.expectEqual(@as(u128, 30), ledger.committed());
}

fn usage(input: u64, output: u64) accounting.Reconciliation {
    return .{ .exact_usage = operation.ProviderUsage.init(input, output, input + output).? };
}

const Fixture = struct {
    requests: request_runner.Runner,
    request: *const identity.ModelRequestId,

    fn init() !Fixture {
        var requests = request_runner.Runner.init(std.testing.allocator);
        errdefer requests.deinit();
        try requests.initialize(identity.RequestPurposeRegistry.all());
        const request = try requests.assign(
            .initial,
            .{ .task_cluster = .{
                .plan_state_id = .{ .bytes = "plan-state-1" },
                .obligation_cluster_id = .{ .bytes = "cluster-1" },
            } },
            .{
                .workflow_id = workflow.WorkflowId.parse("arbitrary-flow").?,
                .workflow_version = 1,
                .workflow_step_id = workflow.WorkflowStepId.parse("generate").?,
            },
            .initial_generation,
        );
        return .{ .requests = requests, .request = request };
    }

    fn deinit(self: *Fixture) void {
        self.requests.deinit();
        self.* = undefined;
    }

    fn inferenceId(self: *const Fixture, attempt: u32) operation.ProviderOperationId {
        return .{
            .model_request_id = self.request,
            .model_attempt_ordinal = operation.ModelAttemptOrdinal.init(attempt).?,
            .kind = .inference,
        };
    }
};
