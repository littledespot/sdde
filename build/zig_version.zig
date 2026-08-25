const std = @import("std");

pub const required = std.SemanticVersion{
    .major = 0,
    .minor = 16,
    .patch = 0,
};

pub fn isSupported(version: std.SemanticVersion) bool {
    return version.order(required) == .eq;
}

test "accepts the exact pinned Zig version" {
    try std.testing.expect(isSupported(.{
        .major = 0,
        .minor = 16,
        .patch = 0,
    }));
}

test "rejects other stable and development versions" {
    const unsupported_versions = [_]std.SemanticVersion{
        .{ .major = 0, .minor = 15, .patch = 2 },
        .{ .major = 0, .minor = 16, .patch = 1 },
        .{ .major = 0, .minor = 16, .patch = 0, .pre = "dev.1" },
        .{ .major = 0, .minor = 17, .patch = 0 },
    };

    for (unsupported_versions) |version| {
        try std.testing.expect(!isSupported(version));
    }
}
