//! Shared lexical policy for root-relative Unicode directory inputs.
const std = @import("std");
const policy = @import("configured_path_policy.zig");

pub const max_bytes = 4096;
pub const max_segment_bytes = 255;
pub const Error = error{InvalidRelativeDirectory};

pub fn validate(bytes: []const u8) Error!void {
    if (bytes.len == 0 or bytes.len > max_bytes or bytes[0] == '/' or bytes[bytes.len - 1] == '/' or
        policy.hasEncodedDotOrSeparator(bytes)) return error.InvalidRelativeDirectory;
    const view = std.unicode.Utf8View.init(bytes) catch return error.InvalidRelativeDirectory;
    var scalars = view.iterator();
    while (scalars.nextCodepoint()) |scalar| {
        if (scalar <= 0x1f or (scalar >= 0x7f and scalar <= 0x9f)) return error.InvalidRelativeDirectory;
    }
    var components = std.mem.splitScalar(u8, bytes, '/');
    while (components.next()) |component| {
        policy.validateComponent(max_segment_bytes, component, .unicode) catch return error.InvalidRelativeDirectory;
    }
}

/// Input has already passed the pinned NFC normalizer. Preserve empty segments
/// for validation; only literal dot segments and separators are canonicalized.
pub fn normalize(allocator: std.mem.Allocator, nfc: []const u8) std.mem.Allocator.Error![]u8 {
    var normalized: std.Io.Writer.Allocating = .init(allocator);
    errdefer normalized.deinit();
    var segments = std.mem.splitAny(u8, nfc, "/\\");
    var first = true;
    while (segments.next()) |segment| {
        if (std.mem.eql(u8, segment, ".")) continue;
        if (!first) normalized.writer.writeByte('/') catch return error.OutOfMemory;
        normalized.writer.writeAll(segment) catch return error.OutOfMemory;
        first = false;
    }
    return normalized.toOwnedSlice() catch return error.OutOfMemory;
}

pub fn contains(root: []const u8, path: []const u8) bool {
    return std.ascii.eqlIgnoreCase(root, path) or
        (path.len > root.len and std.ascii.startsWithIgnoreCase(path, root) and path[root.len] == '/');
}
