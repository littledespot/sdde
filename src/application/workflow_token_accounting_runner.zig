const std = @import("std");
const check_action = @import("../actions/model/check_workflow_token_budget.zig");
const reconcile_action = @import("../actions/model/reconcile_workflow_token_usage.zig");
const operation = @import("../domain/llm_provider_operation.zig");
const pipeline = @import("../domain/pipeline.zig");
const accounting = @import("../domain/workflow_token_accounting.zig");

pub const Runner = struct {
    ledger: accounting.Ledger,
    check_action: check_action.Action = .{},
    reconcile_action: reconcile_action.Action = .{},

    pub fn init(allocator: std.mem.Allocator, budget: accounting.TotalTokenBudget) Runner {
        return .{ .ledger = accounting.Ledger.init(allocator, budget) orelse unreachable };
    }

    pub fn deinit(self: *Runner) void {
        self.ledger.deinit();
        self.* = undefined;
    }

    pub fn check(self: *const Runner) accounting.BudgetError!void {
        try self.check_action.execute(&self.ledger);
    }

    // Usage survives the error from an over-budget response. The response
    // must not become candidate success, and later calls fail check().
    pub fn reconcile(
        self: *Runner,
        expected_revision: accounting.Revision,
        inference_operation_id: operation.ProviderOperationId,
        resolution: accounting.Reconciliation,
    ) (accounting.Error || accounting.BudgetError)!void {
        var envelope = pipeline.DataShape.init(&.{});
        const delta = try self.reconcile_action.execute(
            &self.ledger,
            expected_revision,
            inference_operation_id,
            resolution,
        );
        envelope = envelope.applyDelta(reconcile_action.Action.contract, &delta) catch
            return error.InvalidProviderTokenUsage;
        const transition = switch (delta.runner_accounting_transition.?) {
            .reconcile_workflow_tokens => |value| value,
            else => unreachable,
        };
        switch (try self.ledger.applyReconciliation(transition)) {
            .available, .exhausted => {},
            .exceeded => return error.WorkflowTokenBudgetExceeded,
            .usage_unavailable => return error.ProviderTokenUsageUnavailable,
        }
    }

    pub fn current(self: *const Runner) *const accounting.Ledger {
        return &self.ledger;
    }
};
