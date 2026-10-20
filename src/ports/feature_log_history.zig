//! Read-only discovery of the current feature's prior-run log binding groups for
//! retention. Discovery never writes or deletes. Every prior group must validate;
//! a prior run with an active tail in either stream is kept whole (ADR 0026).
const std = @import("std");
const artifacts = @import("../domain/workflow_artifact_registry.zig");
const log_binding = @import("../domain/feature_log_binding.zig");
const log_stream = @import("../domain/feature_log_stream.zig");

/// `InvalidHistory` is a prior group that fails validation, such as a symlinked
/// entry, an insecure directory, an unexpected entry or a mismatched identity.
/// `HistoryUnavailable` is a path or read that cannot be completed. Both block
/// the run; neither is skipped.
pub const Error = error{ HistoryUnavailable, InvalidHistory, Cancelled, OutOfMemory };

/// One closed binding of one stream of a prior run. Its identity comes from the
/// segment headers.
pub const Group = struct { stream: log_stream.Stream, binding: log_binding.BindingCandidate };

/// Groups are ordered by `(runId, bindingId, stream rank)`. `retained_runs`
/// counts prior runs kept whole because a stream has an active tail.
pub const Discovery = struct {
    groups: []const Group,
    retained_runs: usize,

    pub fn deinit(self: Discovery, allocator: std.mem.Allocator) void {
        for (self.groups) |group| freeCandidate(allocator, group.binding);
        allocator.free(self.groups);
    }
};

pub fn freeCandidate(allocator: std.mem.Allocator, candidate: log_binding.BindingCandidate) void {
    allocator.free(candidate.log_policy_id.bytes);
    allocator.free(candidate.binding_id.bytes);
    allocator.free(candidate.run_id.bytes);
    allocator.free(candidate.feature_id.bytes);
}

pub const Discoverer = struct {
    context: *anyopaque,
    discover_fn: *const fn (*anyopaque, std.mem.Allocator, *const artifacts.WorkflowArtifactRegistry) Error!Discovery,

    pub fn discover(self: Discoverer, allocator: std.mem.Allocator, registry: *const artifacts.WorkflowArtifactRegistry) Error!Discovery {
        return self.discover_fn(self.context, allocator, registry);
    }
};
