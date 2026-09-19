//! Typed observation data; no provider or workflow authority is retained.
const operation = @import("llm_provider_operation.zig");
pub const TransportFailure = struct {
    cause: operation.ProviderFailureCause,
    retry_class: operation.ProviderRetryClass,
    delivery: operation.ProviderDeliveryDisposition,
    diagnostic: ?operation.TransportDiagnostic = null,
};
pub const TransportOutcome = struct {
    outcome: enum { cancelled, allocation_failed, transport_failed, rejected_before_send },
    delivery: ?operation.ProviderDeliveryDisposition = null,
    failure: ?TransportFailure = null,
};
pub const Body = union(enum) {
    provider_body: []const u8,
    partial_provider_body: []const u8,
    transport_outcome: TransportOutcome,
};
