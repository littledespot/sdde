//! Execution-local observation of the producing call, never request authority.
//! Value ordinals survive release of request bodies; the execution's existing
//! operation ledger owns correlation to provider, workflow step and usage.
const provider = @import("llm_provider_operation.zig");
const identity = @import("model_request_identity.zig");
pub const Origin = struct {
    request: identity.RecordIndex,
    attempt: provider.ModelAttemptOrdinal,
    kind: provider.ProviderOperationKind = .inference,

    pub fn from(ledger: *const identity.ModelRequestIdentityLedger, operation: provider.ProviderOperationId) ?Origin {
        return .{ .request = ledger.indexOf(operation.model_request_id) orelse return null, .attempt = operation.model_attempt_ordinal, .kind = operation.kind };
    }
    pub fn matches(self: Origin, ledger: *const identity.ModelRequestIdentityLedger, operation: provider.ProviderOperationId) bool {
        const index = ledger.indexOf(operation.model_request_id) orelse return false;
        return self.kind == operation.kind and self.request.value == index.value and self.attempt.value == operation.model_attempt_ordinal.value;
    }
    /// Observe the exact schema-admitted call only after the existing logical
    /// request ledger records acceptance. This does not create acceptance.
    pub fn fromAccepted(ledger: *const identity.ModelRequestIdentityLedger, proof: *const @import("model_payload_schema.zig").Evidence) ?Origin {
        const association = proof.candidate().association();
        if (association.result() != .complete) return null;
        const operation = association.operationId();
        if (!operation.model_request_id.stage_run_epoch_id.eql(ledger.stageRunEpochId())) return null;
        const record = ledger.record(operation.model_request_id) orelse return null;
        if (record.status != .terminal or record.terminal_reason != .accepted) return null;
        return from(ledger, operation);
    }
};
