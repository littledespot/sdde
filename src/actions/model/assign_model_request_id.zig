const binding = @import("../../domain/llm_provider_binding.zig");
const identity = @import("../../domain/model_request_identity.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "assign-model-request-id@1",
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
        unit_owner_id: identity.ImmutableUnitOwnerId,
        model_operation_id: binding.WorkflowModelOperationId,
        purpose: identity.RequestPurposeBinding,
    ) identity.Error!identity.Assignment {
        return identity.createSuccessor(
            current,
            expected_revision,
            unit_owner_id,
            model_operation_id,
            purpose,
        );
    }
};
