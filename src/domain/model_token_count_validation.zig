const provider = @import("llm_provider_operation.zig");
const binding = @import("llm_provider_binding.zig");
const lifecycle = @import("provider_operation_lifecycle.zig");

/// The caller supplies the current execution ledger and retained call inputs.
pub const Call = struct {
    request: *const provider.IdentifiedProviderNeutralModelRequest,
    provider_binding: *const binding.ValidatedProviderModelBinding,
    operations: *const lifecycle.Ledger,
    operation_id: provider.ProviderOperationId,
};

pub const Error = error{
    InvalidModelTokenCountContext,
    ModelTokenCountAssociationInvalid,
};

/// Allocation-free facts borrowing the original request/binding identities.
/// Those owners must outlive this result; the observation itself is not retained.
/// Cancellation stays outside observations as the provider port's Cancelled error.
pub const Result = union(enum) {
    counted: provider.ExactInputTokenCountEvidence,
    failed: provider.ProviderFailure,
};

pub fn validate(call: Call, observation: *const provider.ProviderTokenCountObservation) Error!Result {
    const request = call.request;
    const invoked = call.operations.requireInvoked(call.operation_id) catch return error.InvalidModelTokenCountContext;
    const record = call.operations.record(call.operation_id) orelse return error.InvalidModelTokenCountContext;
    if (!provider.validateCountInvocation(call.provider_binding, request, invoked) or
        !record.binding_id.eql(request.binding_id) or
        !record.model_visible_input_id.eql(request.model_visible_input_id)) return error.InvalidModelTokenCountContext;

    // fromObservation validates request, binding and input, but not the exact
    // expected attempt. Compare both observation variants with the applied ID.
    const observed_id = switch (observation.*) {
        inline else => |value| value.operation_id,
    };
    if (!observed_id.eql(invoked.id)) return error.ModelTokenCountAssociationInvalid;
    return switch (observation.*) {
        .counted => .{ .counted = provider.ExactInputTokenCountEvidence.fromObservation(observation.*, request.*, call.provider_binding.*) catch return error.ModelTokenCountAssociationInvalid },
        .failed => |failure| .{ .failed = failure },
    };
}
