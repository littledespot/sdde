const std = @import("std");
const path_policy = @import("configured_path_policy.zig");

pub const max_bytes = 4096;
pub const max_segment_bytes = 255;
pub const Error = error{ InvalidSpecifyArguments, InvalidReferenceSelector };

pub const ParsedInvocation = struct { reference: ?[]const u8, count: usize };
pub const Invocation = struct { raw_reference: []const u8 };
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
    const bytes = candidate.bytes;
    if (bytes.len == 0 or bytes.len > max_bytes or bytes[0] == '/' or bytes[bytes.len - 1] == '/' or
        path_policy.hasEncodedDotOrSeparator(bytes)) return error.InvalidReferenceSelector;
    const view = std.unicode.Utf8View.init(bytes) catch return error.InvalidReferenceSelector;
    var scalars = view.iterator();
    while (scalars.nextCodepoint()) |scalar| {
        if (scalar <= 0x1f or (scalar >= 0x7f and scalar <= 0x9f)) return error.InvalidReferenceSelector;
    }
    var components = std.mem.splitScalar(u8, bytes, '/');
    while (components.next()) |component| {
        path_policy.validateComponent(max_segment_bytes, component, .unicode) catch return error.InvalidReferenceSelector;
    }
    return .{ .bytes = bytes };
}
