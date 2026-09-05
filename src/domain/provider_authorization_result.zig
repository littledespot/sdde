const std = @import("std");
const provider = @import("llm_provider_operation.zig");
const identity = @import("model_request_identity.zig");

pub const Outcome = union(enum) {
    prepared: provider.ValidatedProviderAuthorizationLeaseRef,
    failed: provider.ProviderFailure,
    cancelled: provider.ProviderOperationId,
};

/// Immutable outcome data only. The lease capability stays in the private table.
pub const Result = opaque {
    pub fn outcome(self: *const Result) *const Outcome {
        const value: *const Storage = @ptrCast(@alignCast(self));
        return &value.outcome;
    }
};
const Storage = struct { allocator: std.mem.Allocator, requests: *identity.Owner, outcome: Outcome };

pub fn create(allocator: std.mem.Allocator, requests: *const identity.ModelRequestIdentityLedger, outcome: Outcome) (std.mem.Allocator.Error || identity.Error || error{InvalidAuthorizationResult})!*Result {
    const id = switch (outcome) {
        .prepared => null,
        .failed => |failure| failure.operation_id,
        .cancelled => |id| id,
    };
    if (id) |operation| {
        if (requests.canonicalRequestId(operation.model_request_id) != operation.model_request_id) return error.InvalidAuthorizationResult;
    }
    const owner = try identity.retainLedger(requests);
    errdefer identity.deinitOwner(owner);
    const value = try allocator.create(Storage);
    value.* = .{ .allocator = allocator, .requests = owner, .outcome = outcome };
    if (value.outcome == .prepared) value.outcome.prepared.identity = outcome.prepared.identity.retain();
    return @ptrCast(value);
}

pub fn destroy(result: *Result) void {
    const value: *Storage = @ptrCast(@alignCast(result));
    if (value.outcome == .prepared) value.outcome.prepared.identity.release();
    identity.deinitOwner(value.requests);
    value.allocator.destroy(value);
}
