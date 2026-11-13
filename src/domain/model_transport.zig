const pipeline = @import("pipeline.zig");

pub const Error = error{InvalidTransportRetirement};

pub const Retirement = enum { rejected_attempt, released_request, released_request_and_input };
pub const requires = [_]pipeline.DataKey{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .model_payload_schema_result };
pub const attempt_keys = [_]pipeline.DataKey{
    .accounted_model_attempt,     .terminal_provider_operation,           .provider_authorization_result,
    .provider_invocation_result,  .provider_invocation_validation_result, .model_envelope_result,
    .model_payload_schema_result,
};

/// What a `request-model` step leaves current once its request closed (ADR 0030, DE1 decision 2),
/// less the ledger, which is replaced and never retired. Its release retires exactly these, so the
/// set is stated once, by the kernel contract that produces it.
pub const released_keys = @import("model_request_kernel.zig").produces;

pub fn keys(comptime retirement: Retirement) []const pipeline.DataKey {
    return switch (retirement) {
        .released_request => &released_keys,
        .released_request_and_input => &(released_keys ++ [_]pipeline.DataKey{.model_input_packet}),
        .rejected_attempt => &attempt_keys,
    };
}

pub fn retire(comptime retirement: Retirement, ledger: *const @import("model_request_identity.zig").ModelRequestIdentityLedger, request: *const @import("model_request_identity.zig").ModelRequestId, payload: @import("workflow.zig").OutcomeTag) Error!pipeline.NodeDelta {
    const record = ledger.record(request) orelse return error.InvalidTransportRetirement;
    if (retirement == .rejected_attempt) {
        if (record.status != .invoked or payload != .invalid) return error.InvalidTransportRetirement;
    } else if (record.status != .terminal) return error.InvalidTransportRetirement;
    var delta: pipeline.NodeDelta = .{};
    for (keys(retirement)) |key| delta.data_invalidations.insert(key);
    return delta;
}
