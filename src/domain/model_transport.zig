const pipeline = @import("pipeline.zig");

pub const Retirement = enum { request, rejected_attempt, input };
pub const requires = [_]pipeline.DataKey{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .model_payload_schema_result };
pub const attempt_keys = [_]pipeline.DataKey{
    .accounted_model_attempt, .terminal_provider_operation, .provider_authorization_result,
    .provider_invocation_result, .provider_invocation_validation_result,
    .model_envelope_result, .model_payload_schema_result,
};
pub const request_keys = attempt_keys ++ [_]pipeline.DataKey{
    .assigned_model_request, .validated_model_request, .prepared_model_request,
};

pub fn keys(comptime retirement: Retirement) []const pipeline.DataKey {
    return switch (retirement) {
        .request => &request_keys,
        .rejected_attempt => &attempt_keys,
        .input => &.{.model_input_packet},
    };
}

pub fn retire(comptime retirement: Retirement, ledger: *const @import("model_request_identity.zig").ModelRequestIdentityLedger, request: *const @import("model_request_identity.zig").ModelRequestId, payload: @import("workflow.zig").OutcomeTag) error{InvalidTransportRetirement}!pipeline.NodeDelta {
    const record = ledger.record(request) orelse return error.InvalidTransportRetirement;
    if (retirement == .rejected_attempt) {
        if (record.status != .invoked or payload != .invalid) return error.InvalidTransportRetirement;
    } else if (record.status != .terminal) return error.InvalidTransportRetirement;
    var delta: pipeline.NodeDelta = .{};
    for (keys(retirement)) |key| delta.data_invalidations.insert(key);
    return delta;
}
