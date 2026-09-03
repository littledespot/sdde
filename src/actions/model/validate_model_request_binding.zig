const binding = @import("../../domain/llm_provider_binding.zig");
const identity = @import("../../domain/model_request_identity.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-model-request-binding@1",
        .kind = .action,
        .requires = &.{.model_request_identity_ledger},
        .produces = &.{},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        current: *const identity.ModelRequestIdentityLedger,
        expected_revision: identity.LedgerRevision,
        request_id: *const identity.ModelRequestId,
        unit_owner_id: identity.ImmutableUnitOwnerId,
        model_operation_id: binding.WorkflowModelOperationId,
        purpose: identity.RequestPurposeBinding,
    ) identity.ValidationError!*const identity.ModelRequestBindingEvidence {
        return identity.validateBinding(
            current,
            expected_revision,
            request_id,
            unit_owner_id,
            model_operation_id,
            purpose,
        );
    }
};
