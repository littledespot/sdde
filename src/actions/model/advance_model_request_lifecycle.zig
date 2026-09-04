const identity = @import("../../domain/model_request_identity.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "advance-model-request-lifecycle@1",
        .kind = .action,
        .requires = &.{.model_request_identity_ledger},
        .produces = &.{},
        .replaces = &.{.model_request_identity_ledger},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        current: *const identity.ModelRequestIdentityLedger,
        expected_revision: identity.LedgerRevision,
        request_id: *const identity.ModelRequestId,
        expected_status: identity.RequestStatus,
        transition: identity.LifecycleTransition,
    ) identity.Error!*identity.Owner {
        return identity.createLifecycleSuccessor(
            current,
            expected_revision,
            request_id,
            expected_status,
            transition,
        );
    }
};
