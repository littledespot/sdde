const accounting = @import("../../domain/model_attempt_accounting.zig");
const identity = @import("../../domain/model_request_identity.zig");
const pipeline = @import("../../domain/pipeline.zig");
const provider_lifecycle = @import("../../domain/provider_operation_lifecycle.zig");

pub const Error = accounting.ProposalError || accounting.RequestError;

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "advance-model-attempt-accounting",
        .kind = .action,
        .requires = &.{.model_request_identity_ledger},
        .produces = &.{},
        .side_effect = .none,
        .runner_accounting = .increment_model_attempt,
    };

    pub fn execute(
        _: Action,
        current_accounting: *const accounting.RunnerModelAttemptAccounting,
        expected_accounting_revision: accounting.Revision,
        current_requests: *const identity.ModelRequestIdentityLedger,
        operations: *const provider_lifecycle.Ledger,
        expected_request_revision: identity.LedgerRevision,
        request_id: *const identity.ModelRequestId,
        attempt: accounting.Attempt,
    ) Error!pipeline.NodeDelta {
        const canonical_request_id = try accounting.validateRequest(current_accounting, current_requests, operations, expected_request_revision, request_id);
        const transition = try accounting.propose(
            current_accounting,
            expected_accounting_revision,
            canonical_request_id,
            attempt,
        );
        var delta: pipeline.NodeDelta = .{};
        delta.runner_accounting_transition = .{ .increment_model_attempt = transition };
        return delta;
    }
};
