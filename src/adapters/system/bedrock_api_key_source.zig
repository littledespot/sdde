const std = @import("std");
const key = @import("../provider/bedrock_api_key.zig");

// Composition calls this once, after selected-workflow provider preparation.
// No fallback variables, default credential chain, or environment mutation.
pub fn read(allocator: std.mem.Allocator, environment: *const std.process.Environ.Map) key.Material {
    const snapshot = key.Snapshot.capture(allocator, environment.get("AWS_BEARER_TOKEN_BEDROCK")) catch return .allocation_failed;
    return if (snapshot) |value| .{ .ready = value } else .unavailable;
}
