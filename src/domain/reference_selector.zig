const path = @import("relative_directory_path.zig");

pub const max_bytes = path.max_bytes;
pub const max_segment_bytes = path.max_segment_bytes;
pub const Error = error{InvalidReferenceSelector};

pub const NormalizedCandidate = struct { bytes: []const u8 };
pub const RelativeSelector = struct { bytes: []const u8 };

/// Read-only observation, not permission to open a path later. Future readers
/// must recheck the configured root and directory identities through their port.
pub const Directory = struct {
    selector: RelativeSelector,
    project_relative_path: []const u8,
    root_identity: @import("filesystem_identity.zig").FileIdentity,
    directory_identity: @import("filesystem_identity.zig").FileIdentity,
};

pub fn validate(candidate: NormalizedCandidate) Error!RelativeSelector {
    path.validate(candidate.bytes) catch return error.InvalidReferenceSelector;
    return .{ .bytes = candidate.bytes };
}
