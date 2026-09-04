const std = @import("std");
const advance_attempt = @import("../actions/model/advance_model_attempt_accounting.zig");
const accounting = @import("../domain/runner_repair_accounting.zig");
const identity = @import("../domain/model_request_identity.zig");
const operation = @import("../domain/llm_provider_operation.zig");
const pipeline = @import("../domain/pipeline.zig");

pub const Runner = struct {
    current_owner: *accounting.Owner,
    advance_action: advance_attempt.Action = .{},

    pub fn init(
        allocator: std.mem.Allocator,
        stage_run_epoch_id: identity.StageRunEpochId,
    ) accounting.Error!Runner {
        return .{ .current_owner = try accounting.createInitial(allocator, stage_run_epoch_id) };
    }

    pub fn deinit(self: *Runner) void {
        accounting.deinitOwner(self.current_owner);
        self.* = undefined;
    }

    pub fn reserve(
        self: *Runner,
        expected_accounting_revision: accounting.Revision,
        current_requests: *const identity.ModelRequestIdentityLedger,
        expected_request_revision: identity.LedgerRevision,
        request_id: *const identity.ModelRequestId,
        maximum: accounting.MaximumAttempts,
    ) (advance_attempt.Error || accounting.Error)!operation.ModelAttemptOrdinal {
        var envelope = pipeline.PipelineEnvelope.init(&.{.model_request_identity_ledger});
        envelope.validateInvocation(advance_attempt.Action.contract) catch {
            return error.ModelRequestUnavailableForAttempt;
        };
        const delta = try self.advance_action.execute(
            accounting.accounting(self.current_owner),
            expected_accounting_revision,
            current_requests,
            expected_request_revision,
            request_id,
            maximum,
        );
        envelope = envelope.apply(
            advance_attempt.Action.contract,
            delta,
        ) catch return error.ModelRequestUnavailableForAttempt;
        const transition = switch (delta.runner_accounting_transition.?) {
            .increment_model_attempt => |value| value,
        };
        const successor = try accounting.apply(accounting.accounting(self.current_owner), transition);
        errdefer accounting.deinitOwner(successor);
        std.debug.assert(envelope.contains(.model_request_identity_ledger));
        const previous_owner = self.current_owner;
        self.current_owner = successor;
        accounting.deinitOwner(previous_owner);
        return transition.ordinal();
    }

    pub fn current(self: *const Runner) *const accounting.RunnerRepairAccounting {
        return accounting.accounting(self.current_owner);
    }
};
