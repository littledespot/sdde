const std = @import("std");
const contracts = @import("../../domain/llm_provider_contracts.zig");
const identity = @import("../../domain/llm_provider_identity.zig");
const operation = @import("../../domain/llm_provider_operation.zig");

// Infrastructure-private transport seam. It is not a second model interface
// and is never exposed to actions, workflow data, or project configuration.
pub const Request = struct {
    region: contracts.BedrockRegion,
    model: identity.ModelId,
    kind: operation.ProviderOperationKind,
    body: []const u8,
    api_key: []const u8,
    deadline_monotonic_ms: u64,
};
pub const Failure = struct {
    cause: operation.ProviderFailureCause,
    retry_class: operation.ProviderRetryClass,
    delivery: operation.ProviderDeliveryDisposition,
};
pub const Response = union(enum) {
    received: struct { status: u16, exception: ?[]const u8 = null, body: []const u8 },
    failed: Failure,
};
pub const Error = std.mem.Allocator.Error || error{Cancelled};
pub const Context = opaque {};
pub const Port = struct {
    context: *Context,
    exchange_fn: *const fn (*Context, std.mem.Allocator, Request) Error!Response,

    // Response allocations belong to the call-local arena supplied here.
    pub fn exchange(self: Port, allocator: std.mem.Allocator, request: Request) Error!Response {
        return self.exchange_fn(self.context, allocator, request);
    }
};
