const std = @import("std");
const binding = @import("feature_log_binding.zig");
const limits = @import("feature_log_limits.zig");
const policy = @import("log_policy.zig");
const stream = @import("feature_log_stream.zig");
const telemetry = @import("telemetry.zig");

pub const AuthorizationOwner = opaque {};
pub const Authorized = struct { stream: stream.Stream, cutoff_unix_ms: u64 };
const Storage = struct {
    backing_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    current_feature_id: @import("feature_identity.zig").FeatureId,
    current_run_id: telemetry.Identifier,
    expected: binding.BindingCandidate,
    stream: stream.Stream,
    cutoff_unix_ms: u64,
    used: bool = false,
};

pub const Error = error{InvalidFeatureLogRetentionAuthorization};

pub fn create(
    allocator: std.mem.Allocator,
    active_policy: *const policy.CompiledLoggingPolicy,
    current: *const binding.ValidatedFeatureLogBinding,
    historical: *const binding.ValidatedFeatureLogBinding,
    selected_stream: stream.Stream,
    now_unix_ms: u64,
) Error!*AuthorizationOwner {
    if (active_policy.retention_days != limits.retention_days or
        !std.mem.eql(u8, current.featureId().bytes, historical.featureId().bytes) or
        std.mem.eql(u8, current.runId().bytes, historical.runId().bytes)) return error.InvalidFeatureLogRetentionAuthorization;
    const owner = allocator.create(Storage) catch return error.InvalidFeatureLogRetentionAuthorization;
    errdefer allocator.destroy(owner);
    owner.* = .{
        .backing_allocator = allocator,
        .arena = .init(allocator),
        .current_feature_id = undefined,
        .current_run_id = undefined,
        .expected = undefined,
        .stream = selected_stream,
        .cutoff_unix_ms = now_unix_ms -| limits.retention_period_ms,
    };
    errdefer owner.arena.deinit();
    const owned = owner.arena.allocator();
    owner.current_feature_id = .{ .bytes = owned.dupe(u8, current.featureId().bytes) catch return error.InvalidFeatureLogRetentionAuthorization };
    owner.current_run_id = .{ .bytes = owned.dupe(u8, current.runId().bytes) catch return error.InvalidFeatureLogRetentionAuthorization };
    owner.expected = .{
        .log_policy_id = .{ .bytes = owned.dupe(u8, historical.logPolicyId().bytes) catch return error.InvalidFeatureLogRetentionAuthorization },
        .binding_id = .{ .bytes = owned.dupe(u8, historical.bindingId().bytes) catch return error.InvalidFeatureLogRetentionAuthorization },
        .run_id = .{ .bytes = owned.dupe(u8, historical.runId().bytes) catch return error.InvalidFeatureLogRetentionAuthorization },
        .feature_id = .{ .bytes = owned.dupe(u8, historical.featureId().bytes) catch return error.InvalidFeatureLogRetentionAuthorization },
    };
    return @ptrCast(owner);
}

pub fn consume(owner: *AuthorizationOwner, historical: *const binding.ValidatedFeatureLogBinding) ?Authorized {
    const stored = storage(owner);
    if (stored.used or !binding.sameBinding(historical, stored.expected)) return null;
    stored.used = true;
    return .{ .stream = stored.stream, .cutoff_unix_ms = stored.cutoff_unix_ms };
}

pub fn authorizedStream(
    owner: *const AuthorizationOwner,
    current: *const binding.ValidatedFeatureLogBinding,
    historical: *const binding.ValidatedFeatureLogBinding,
) ?stream.Stream {
    const stored: *const Storage = @ptrCast(@alignCast(owner));
    if (stored.used or !binding.sameBinding(historical, stored.expected) or
        !std.mem.eql(u8, current.featureId().bytes, stored.current_feature_id.bytes) or
        !std.mem.eql(u8, current.runId().bytes, stored.current_run_id.bytes)) return null;
    return stored.stream;
}

pub fn deinit(owner: *AuthorizationOwner) void {
    const stored = storage(owner);
    const allocator = stored.backing_allocator;
    stored.arena.deinit();
    allocator.destroy(stored);
}

fn storage(owner: *AuthorizationOwner) *Storage {
    return @ptrCast(@alignCast(owner));
}
