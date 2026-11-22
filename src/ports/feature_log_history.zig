//! Read-only discovery of the current feature's prior-run log binding groups for
//! retention and for crash finalization. Discovery never writes or deletes. Every
//! prior group must validate; a prior run with an active tail in either stream is
//! kept whole until its tails are finalized (ADR 0026).
const std = @import("std");
const artifacts = @import("../domain/workflow_artifact_registry.zig");
const log_binding = @import("../domain/feature_log_binding.zig");
const log_stream = @import("../domain/feature_log_stream.zig");

/// `InvalidHistory` is a prior group that fails validation, such as a symlinked
/// entry, an insecure directory, a misplaced segment or directory, or a
/// mismatched identity. A regular file whose name is not a segment name is not
/// history.
/// `HistoryUnavailable` is a path or read that cannot be completed. Both block
/// the run; neither is skipped.
pub const Error = error{ HistoryUnavailable, InvalidHistory, Cancelled, OutOfMemory };

/// One closed binding of one stream of a prior run. Its identity comes from the
/// segment headers.
pub const Group = struct { stream: log_stream.Stream, binding: log_binding.BindingCandidate };

/// Groups and tails are each ordered by `(runId, bindingId, stream rank)`. `groups` are the closed groups of runs with
/// no active tail. `tails` are the binding groups whose last segment holds no trailer but a complete header row: a
/// crash left them open, and each names the identity its header carries. A group torn before its header row was
/// complete has no identity to close; it is in neither list, and its run is kept whole. `retained_runs` counts prior
/// runs kept whole because a stream has an active tail or a torn one.
pub const Discovery = struct {
    groups: []const Group,
    tails: []const Group,
    retained_runs: usize,

    pub fn deinit(self: Discovery, allocator: std.mem.Allocator) void {
        for (self.groups) |group| freeCandidate(allocator, group.binding);
        allocator.free(self.groups);
        for (self.tails) |group| freeCandidate(allocator, group.binding);
        allocator.free(self.tails);
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
