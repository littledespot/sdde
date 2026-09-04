const accounting = @import("../../domain/runner_repair_accounting.zig");
const identity = @import("../../domain/model_request_identity.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = accounting.ProposalError || error{
    ModelRequestLedgerRevisionConflict,
    ModelRequestUnavailableForAttempt,
};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "advance-model-attempt-accounting@1",
        .kind = .action,
        .requires = &.{.model_request_identity_ledger},
        .produces = &.{},
        .side_effect = .none,
        .runner_accounting = .increment_model_attempt,
    };

    pub fn execute(
        _: Action,
        current_accounting: *const accounting.RunnerRepairAccounting,
        expected_accounting_revision: accounting.Revision,
        current_requests: *const identity.ModelRequestIdentityLedger,
        expected_request_revision: identity.LedgerRevision,
        request_id: *const identity.ModelRequestId,
        maximum: accounting.MaximumAttempts,
    ) Error!pipeline.NodeDelta {
        if (!current_requests.revision().eql(expected_request_revision)) {
            return error.ModelRequestLedgerRevisionConflict;
        }
        const current_record = current_requests.record(request_id) orelse {
            return error.ModelRequestUnavailableForAttempt;
        };
        if (current_record.status == .terminal or
            !current_accounting.stageRunEpochId().eql(current_record.model_request_id.stage_run_epoch_id))
        {
            return error.ModelRequestUnavailableForAttempt;
        }
        const canonical_request_id = current_requests.canonicalRequestId(request_id) orelse {
            return error.ModelRequestUnavailableForAttempt;
        };
        const transition = try accounting.proposeModelAttempt(
            current_accounting,
            expected_accounting_revision,
            canonical_request_id,
            maximum,
        );
        var delta = pipeline.NodeDelta.successful(contract);
        delta.runner_accounting_transition = .{ .increment_model_attempt = transition };
        return delta;
    }
};
