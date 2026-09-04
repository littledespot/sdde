const std = @import("std");
const reserve_action = @import("actions/model/reserve_workflow_token_budget.zig");
const reconcile_action = @import("actions/model/reconcile_workflow_token_usage.zig");
const token_runner = @import("application/workflow_token_accounting_runner.zig");
const request_runner = @import("application/model_request_identity_runner.zig");
const binding = @import("domain/llm_provider_binding.zig");
const identity = @import("domain/model_request_identity.zig");
const operation = @import("domain/llm_provider_operation.zig");
const accounting = @import("domain/workflow_token_accounting.zig");
const pipeline = @import("domain/pipeline.zig");
const workflow = @import("domain/workflow.zig");

test "workflow executions initialize independent total-token ledgers" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var first = token_runner.Runner.init(std.testing.allocator, .{ .value = 100 });
    defer first.deinit();
    var second = token_runner.Runner.init(std.testing.allocator, .{ .value = 100 });
    defer second.deinit();

    try first.reserve(.initial, fixture.inferenceId(1), fixture.countEvidence(1, 20), 30);
    try std.testing.expectEqual(@as(u64, 50), first.current().reserved());
    try std.testing.expectEqual(@as(u64, 0), second.current().reserved());
    try std.testing.expectEqual(@as(u64, 100), second.current().totalTokenBudget().value);
}

test "reservation blocks before exceeding the execution budget" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var runner = token_runner.Runner.init(std.testing.allocator, .{ .value = 50 });
    defer runner.deinit();

    try runner.reserve(.initial, fixture.inferenceId(1), fixture.countEvidence(1, 20), 30);
    try std.testing.expectError(
        error.WorkflowTokenBudgetExceeded,
        runner.reserve(.{ .value = 1 }, fixture.inferenceId(2), fixture.countEvidence(2, 1), 1),
    );
    try std.testing.expectEqual(@as(u64, 1), runner.current().revision().value);
    try std.testing.expectEqual(@as(u64, 50), runner.current().reserved());

    var overflow = token_runner.Runner.init(std.testing.allocator, .{ .value = std.math.maxInt(u64) });
    defer overflow.deinit();
    try std.testing.expectError(
        error.WorkflowTokenBudgetExceeded,
        overflow.reserve(.initial, fixture.inferenceId(3), fixture.countEvidence(3, std.math.maxInt(u64)), 1),
    );
    try std.testing.expect(accounting.TotalTokenBudget.init(0) == null);
}

test "exact usage commits while not-sent releases and ambiguous delivery retains" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var runner = token_runner.Runner.init(std.testing.allocator, .{ .value = 200 });
    defer runner.deinit();

    const exact = fixture.inferenceId(1);
    try runner.reserve(.initial, exact, fixture.countEvidence(1, 20), 30);
    try runner.reconcile(.{ .value = 1 }, exact, .{ .exact_usage = operation.ProviderUsage.init(20, 10, 30).? });
    try std.testing.expectEqual(@as(u64, 30), runner.current().committed());
    try std.testing.expectEqual(@as(u64, 0), runner.current().reserved());
    try std.testing.expectError(
        error.TokenReservationAlreadyReconciled,
        runner.reconcile(.{ .value = 2 }, exact, .not_sent),
    );

    const not_sent = fixture.inferenceId(2);
    try runner.reserve(.{ .value = 2 }, not_sent, fixture.countEvidence(2, 15), 25);
    try runner.reconcile(.{ .value = 3 }, not_sent, .not_sent);
    try std.testing.expectEqual(@as(u64, 0), runner.current().reserved());

    const ambiguous = fixture.inferenceId(3);
    try runner.reserve(.{ .value = 4 }, ambiguous, fixture.countEvidence(3, 10), 20);
    try runner.reconcile(.{ .value = 5 }, ambiguous, .retain);
    try std.testing.expectEqual(@as(u64, 30), runner.current().reserved());
    try std.testing.expectEqual(@as(u64, 30), runner.current().committed());
}

test "reservation rejects mismatched count evidence and invalid exact usage" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var runner = token_runner.Runner.init(std.testing.allocator, .{ .value = 100 });
    defer runner.deinit();

    try std.testing.expectError(
        error.InvalidTokenReservation,
        runner.reserve(.initial, fixture.inferenceId(1), fixture.countEvidence(2, 10), 20),
    );
    const inference = fixture.inferenceId(1);
    try runner.reserve(.initial, inference, fixture.countEvidence(1, 10), 20);
    try std.testing.expectError(
        error.InvalidProviderTokenUsage,
        runner.reconcile(.{ .value = 1 }, inference, .{ .exact_usage = .{
            .input_tokens = 10,
            .output_tokens = 30,
            .total_tokens = 40,
        } }),
    );
}

test "token actions only propose their declared runner transitions" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var ledger = accounting.Ledger.init(std.testing.allocator, .{ .value = 100 }).?;
    defer ledger.deinit();
    const inference = fixture.inferenceId(1);
    const reserve_delta = try (reserve_action.Action{}).execute(
        &ledger,
        .initial,
        inference,
        fixture.countEvidence(1, 10),
        20,
    );
    try std.testing.expectEqual(@as(u64, 0), ledger.revision().value);
    const empty = pipeline.DataShape.init(&.{});
    _ = try empty.applyDelta(reserve_action.Action.contract, &reserve_delta);
    const reservation = switch (reserve_delta.runner_accounting_transition.?) {
        .reserve_workflow_tokens => |value| value,
        else => unreachable,
    };
    try ledger.applyReservation(reservation);

    const reconcile_delta = try (reconcile_action.Action{}).execute(
        &ledger,
        .{ .value = 1 },
        inference,
        .not_sent,
    );
    _ = try empty.applyDelta(reconcile_action.Action.contract, &reconcile_delta);
    try std.testing.expectEqual(@as(u64, 1), ledger.revision().value);
}

const Fixture = struct {
    requests: request_runner.Runner,
    request: *const identity.ModelRequestId,

    fn init() !Fixture {
        var requests = request_runner.Runner.init(std.testing.allocator);
        errdefer requests.deinit();
        try requests.initialize(.{ .bytes = "epoch-1" }, identity.RequestPurposeRegistry.all());
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

    fn countEvidence(self: *const Fixture, attempt: u32, input_tokens: u64) operation.ExactInputTokenCountEvidence {
        return .{
            .count_operation_id = .{
                .model_request_id = self.request,
                .model_attempt_ordinal = operation.ModelAttemptOrdinal.init(attempt).?,
                .kind = .input_token_count,
            },
            .binding_id = bindingId(),
            .model_visible_input_id = operation.ModelVisibleInputId.parse("input-1").?,
            .input_tokens = input_tokens,
        };
    }

    fn inferenceId(self: *const Fixture, attempt: u32) operation.ProviderOperationId {
        return .{
            .model_request_id = self.request,
            .model_attempt_ordinal = operation.ModelAttemptOrdinal.init(attempt).?,
            .kind = .inference,
        };
    }
};

fn bindingId() binding.ProviderModelBindingId {
    return .{
        .operation_id = .{
            .workflow_id = workflow.WorkflowId.parse("arbitrary-flow").?,
            .workflow_version = 1,
            .workflow_step_id = workflow.WorkflowStepId.parse("generate").?,
        },
        .slot_id = @import("domain/llm_provider_identity.zig").ModelSlotId.parse("slot").?,
        .registry_entry_id = .{ .ordinal = 1 },
        .reasoning_effort = null,
    };
}
