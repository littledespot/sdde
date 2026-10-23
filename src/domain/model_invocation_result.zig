const std = @import("std");
const provider = @import("llm_provider_operation.zig");
const identity = @import("model_request_identity.zig");
pub const AccountingStop = enum { usage_unavailable };

pub const Error = std.mem.Allocator.Error || identity.Error || error{InvalidInvocationResult};

pub const Outcome = union(enum) {
    observation: provider.ProviderInvocationObservation,
    cancelled,
    allocation_failed,
    logging_blocked_before_send,
};

/// Owns the untrusted response, not validation evidence or workflow authority.
pub const Result = opaque {
    pub fn operationId(self: *const Result) provider.ProviderOperationId {
        return storage(self).operation_id;
    }

    pub fn outcome(self: *const Result) ?*const Outcome {
        return if (storage(self).outcome) |*value| value else null;
    }

    pub fn accountingStop(self: *const Result) ?AccountingStop {
        return switch (storage(self).accounting) {
            .pending => null,
            .reconciled => |stop| stop,
        };
    }

    /// The runner seals accounting once, before publishing this candidate.
    /// The original provider observation remains owned and inspectable.
    pub fn reconcileAccounting(self: *const Result, stop: ?AccountingStop) Error!void {
        const owner = storage(self);
        if (owner.outcome == null or owner.accounting != .pending) return error.InvalidInvocationResult;
        owner.accounting = .{ .reconciled = stop };
    }
};

pub const Owner = struct {
    allocator: std.mem.Allocator,
    requests: *identity.Owner,
    operation_id: provider.ProviderOperationId,
    outcome: ?Outcome = null,
    accounting: union(enum) { pending, reconciled: ?AccountingStop } = .pending,
    handle: Handle,

    /// Prepared before the call so retaining its result cannot allocate afterward.
    pub fn init(allocator: std.mem.Allocator, requests: *const identity.ModelRequestIdentityLedger, operation_id: provider.ProviderOperationId) Error!*Owner {
        if (operation_id.model_attempt_ordinal.value == 0 or
            requests.canonicalRequestId(operation_id.model_request_id) != operation_id.model_request_id) return error.InvalidInvocationResult;
        const retained = try identity.retainLedger(requests);
        errdefer identity.deinitOwner(retained);
        const owner = try allocator.create(Owner);
        owner.* = .{ .allocator = allocator, .requests = retained, .operation_id = operation_id, .handle = .{ .owner = owner } };
        return owner;
    }

    pub fn finish(self: *Owner, outcome: Outcome) void {
        std.debug.assert(self.outcome == null);
        self.outcome = outcome;
    }

    pub fn view(self: *const Owner) *const Result {
        return @ptrCast(&self.handle);
    }

    pub fn destroy(self: *Owner) void {
        if (self.outcome) |*outcome| switch (outcome.*) {
            .observation => |*observation| observation.deinit(),
            .cancelled, .allocation_failed, .logging_blocked_before_send => {},
        };
        identity.deinitOwner(self.requests);
        self.allocator.destroy(self);
    }
};

const Handle = struct { owner: *Owner };

fn storage(result: *const Result) *Owner {
    const handle: *const Handle = @ptrCast(@alignCast(result));
    return handle.owner;
}
