const std = @import("std");
const path = @import("relative_directory_path.zig");
const feature = @import("feature_identity.zig");
const roots = @import("bootstrap_roots.zig");

pub const Error = std.mem.Allocator.Error || error{InvalidFeatureDirectory};
pub const NormalizedCandidate = struct { bytes: []const u8 };
/// Borrowed metadata from the validated bootstrap registry, not I/O authority.
pub const Roots = struct { specs: []const u8, archive: []const u8 };
pub const Selector = struct {
    feature_id: feature.FeatureId,
    project_relative_path: []const u8,
};
/// Observations are not permission to write or evidence of completed workflow state.
pub const Directory = struct {
    selector: Selector,
    root_observation: roots.RootObservation,
    observation: roots.RootObservation,
};

pub fn validate(allocator: std.mem.Allocator, candidate: NormalizedCandidate, configured: Roots) Error!Selector {
    const id = feature.FeatureId.parse(candidate.bytes) orelse return error.InvalidFeatureDirectory;
    const relative = try std.mem.concat(allocator, u8, &.{ configured.specs, "/", id.bytes });
    errdefer allocator.free(relative);
    path.validate(relative) catch return error.InvalidFeatureDirectory;
    if (!path.contains(configured.specs, relative) or path.contains(configured.archive, relative)) return error.InvalidFeatureDirectory;
    return .{ .feature_id = id, .project_relative_path = relative };
}
