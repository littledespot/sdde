const path = @import("relative_directory_path.zig");

/// Lossless paths.specs-relative directory key, not an allocated identity.
pub const FeatureId = struct {
    bytes: []const u8,

    pub fn parse(bytes: []const u8) ?FeatureId {
        path.validate(bytes) catch return null;
        return .{ .bytes = bytes };
    }
};
