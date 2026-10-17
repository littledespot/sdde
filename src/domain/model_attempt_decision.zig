//! Native result of requesting an inference attempt. A stop allocates no attempt.
const std = @import("std");
const attempt = @import("model_attempt_accounting.zig");
const handoff = @import("model_request_handoff.zig");
const retry = @import("workflow_retry.zig");
pub const StopCause = enum { protocol_exhausted };

pub const Error = std.mem.Allocator.Error || error{InvalidModelAttemptDecision};
pub const Outcome = union(enum) { admitted: *const attempt.AccountedAttempt, advisory_stopped: *const StopReceipt };

pub const Decision = opaque {
    pub fn outcome(self: *const Decision) Outcome {
        const value = storage(self);
        return switch (value.value) {
            .admitted => |value_attempt| .{ .admitted = value_attempt },
            .stopped => .{ .advisory_stopped = @ptrCast(value) },
        };
    }
};

pub const StopReceipt = opaque {
    pub fn request(self: *const StopReceipt) *const handoff.Request {
        return stopStorage(self).value.stopped.request;
    }
    pub fn exhaustion(self: *const StopReceipt) retry.Exhaustion {
        return stopStorage(self).value.stopped.exhaustion;
    }
    pub fn cause(_: *const StopReceipt) StopCause {
        return .protocol_exhausted;
    }
};

/// Callers retain the exact admitted accounting owner or prepared request owner.
pub const Owned = struct {
    allocator: std.mem.Allocator,
    decision: *const Decision,

    pub fn deinit(self: Owned) void {
        self.allocator.destroy(storage(self.decision));
    }
};

pub fn admitted(a: std.mem.Allocator, value: *const attempt.AccountedAttempt) Error!Owned {
    const owner = try a.create(Storage);
    owner.* = .{ .value = .{ .admitted = value } };
    return .{ .allocator = a, .decision = @ptrCast(owner) };
}

pub fn stopped(a: std.mem.Allocator, request: *const handoff.Request, current: *const @import("model_request_identity.zig").ModelRequestIdentityLedger, exhaustion: retry.Exhaustion) Error!Owned {
    const correction = request.protocolCorrection() orelse return error.InvalidModelAttemptDecision;
    const record = current.record(request.id()) orelse return error.InvalidModelAttemptDecision;
    if (request.advisoryAssessment() == null or record.status != .invoked or
        current.canonicalRequestId(request.id()) != request.id() or !current.stageRunEpochId().eql(request.id().stage_run_epoch_id) or
        correction.model_request_id != request.id() or exhaustion.reason != .retry_limit or
        exhaustion.defect != null or exhaustion.completed_executions <= exhaustion.limit.value) return error.InvalidModelAttemptDecision;
    const owner = try a.create(Storage);
    owner.* = .{ .value = .{ .stopped = .{ .request = request, .exhaustion = exhaustion } } };
    return .{ .allocator = a, .decision = @ptrCast(owner) };
}

const Storage = struct { value: union(enum) { admitted: *const attempt.AccountedAttempt, stopped: struct { request: *const handoff.Request, exhaustion: retry.Exhaustion } } };
fn storage(value: *const Decision) *const Storage {
    return @ptrCast(@alignCast(value));
}
fn stopStorage(value: *const StopReceipt) *const Storage {
    return @ptrCast(@alignCast(value));
}
