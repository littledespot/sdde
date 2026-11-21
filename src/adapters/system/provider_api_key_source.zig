const std = @import("std");
const key = @import("../provider/provider_api_key.zig");

/// The one production variable each family reads (ADR 0028).
pub fn variable(family: key.Family) []const u8 {
    return switch (family) {
        .aws_bedrock => "AWS_BEARER_TOKEN_BEDROCK",
        .anthropic => "ANTHROPIC_API_KEY",
    };
}

// Composition calls this once per selected family, after selected-workflow
// provider preparation. No fallback variables, default credential chain, or
// environment mutation.
pub fn read(allocator: std.mem.Allocator, environment: *const std.process.Environ.Map, family: key.Family) key.Material {
    const raw = environment.get(variable(family));
    const snapshot = key.Snapshot.capture(allocator, raw) catch return .allocation_failed;
    if (snapshot) |value| return .{ .ready = value };
    return if (key.defect(raw).? == .malformed) .malformed else .unavailable;
}
