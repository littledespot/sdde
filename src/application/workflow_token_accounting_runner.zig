const std = @import("std");
const reserve_action = @import("../actions/model/reserve_workflow_token_budget.zig");
const reconcile_action = @import("../actions/model/reconcile_workflow_token_usage.zig");
const operation = @import("../domain/llm_provider_operation.zig");
const pipeline = @import("../domain/pipeline.zig");
const accounting = @import("../domain/workflow_token_accounting.zig");

pub const Runner = struct {
    ledger: accounting.Ledger,
    reserve_action: reserve_action.Action = .{},
    reconcile_action: reconcile_action.Action = .{},

    pub fn init(allocator: std.mem.Allocator, budget: accounting.TotalTokenBudget) Runner {
        return .{ .ledger = accounting.Ledger.init(allocator, budget) orelse unreachable };
    }

    pub fn deinit(self: *Runner) void {
        self.ledger.deinit();
        self.* = undefined;
    }

    pub fn reserve(
        self: *Runner,
        expected_revision: accounting.Revision,
        inference_operation_id: operation.ProviderOperationId,
        count_evidence: operation.ExactInputTokenCountEvidence,
        effective_maximum_output_tokens: u64,
    ) (reserve_action.Error || accounting.Error)!void {
        var envelope = pipeline.PipelineEnvelope.init(&.{});
        const delta = try self.reserve_action.execute(
            &self.ledger,
            expected_revision,
            inference_operation_id,
            count_evidence,
            effective_maximum_output_tokens,
        );
        envelope = envelope.apply(reserve_action.Action.contract, delta) catch {
            return error.InvalidTokenReservation;
        };
        const transition = switch (delta.runner_accounting_transition.?) {
            .reserve_workflow_tokens => |value| value,
            else => unreachable,
        };
        try self.ledger.applyReservation(transition);
    }

    pub fn reconcile(
        self: *Runner,
        expected_revision: accounting.Revision,
        inference_operation_id: operation.ProviderOperationId,
        resolution: accounting.Reconciliation,
    ) (reconcile_action.Error || accounting.Error)!void {
        var envelope = pipeline.PipelineEnvelope.init(&.{});
        const delta = try self.reconcile_action.execute(
            &self.ledger,
            expected_revision,
            inference_operation_id,
            resolution,
        );
        envelope = envelope.apply(reconcile_action.Action.contract, delta) catch {
            return error.InvalidProviderTokenUsage;
        };
        const transition = switch (delta.runner_accounting_transition.?) {
            .reconcile_workflow_tokens => |value| value,
            else => unreachable,
        };
        try self.ledger.applyReconciliation(transition);
    }

    pub fn current(self: *const Runner) *const accounting.Ledger {
        return &self.ledger;
    }
};
