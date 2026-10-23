const std = @import("std");
const contracts = @import("../../domain/llm_provider_contracts.zig");
const identity = @import("../../domain/llm_provider_identity.zig");
const operation = @import("../../domain/llm_provider_operation.zig");

// Infrastructure-private transport seam shared by every provider family. It is
// not a second model interface and is never exposed to actions, workflow data,
// or project configuration.

/// Closed endpoint target of one exchange. Each family's endpoint projection
/// owns its URL, authentication header and retained response headers, so a
/// key can only be sent to its own family's endpoint.
pub const Target = union(enum) {
    aws_bedrock: struct { region: contracts.BedrockRegion, model: identity.ModelId },
    /// The Messages API carries its model in the body.
    anthropic,
};

pub const Request = struct {
    target: Target,
    body: []const u8,
    api_key: []const u8,
    deadline_monotonic_ms: u64,
    // Error-union exits cannot carry a response. The caller may retain the
    // received prefix through this borrowed slot; the exchange joins all tasks
    // before publishing it, and the call-local arena owns its bytes.
    response_body_on_error: ?*?ResponseBody = null,
};
pub const ResponseBody = struct { bytes: []const u8, complete: bool };
pub const Failure = struct {
    cause: operation.ProviderFailureCause,
    retry_class: operation.ProviderRetryClass,
    delivery: operation.ProviderDeliveryDisposition,
    diagnostic: ?operation.TransportDiagnostic = null,
    body: ?ResponseBody = null,

    pub fn metadata(self: Failure) @import("../../domain/model_exchange.zig").TransportFailure {
        return .{ .cause = self.cause, .retry_class = self.retry_class, .delivery = self.delivery, .diagnostic = self.diagnostic };
    }
};
/// Response headers a family's endpoint projection retains. A duplicate of a
/// retained name is a malformed head.
pub const RetainedHeader = enum { exception, request_id, retry_after };
pub const Response = union(enum) {
    received: struct { status: u16, exception: ?[]const u8 = null, request_id: ?[]const u8 = null, retry_after: ?[]const u8 = null, body: []const u8 },
    failed: Failure,
};
/// The request line and headers one family's endpoint sends. `authorization`
/// is call-owned secret bytes that the exchange zeroes after sending; extra
/// headers borrow the consumed capability's key.
pub const Projection = struct {
    url: []const u8,
    authorization: ?[]u8 = null,
    extra_headers: []const std.http.Header = &.{},
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
