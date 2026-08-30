const std = @import("std");
const config = @import("../../domain/config.zig");
const logging = @import("../../domain/logging.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{LoggingPolicyInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-logging-policy@1",
        .kind = .action,
        .requires = &.{ .engine_config, .canonical_log_level },
        .produces = &.{.logging_policy},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        allocator: std.mem.Allocator,
        logs: config.LogsConfig,
        canonicalized: logging.CanonicalizedLevel,
    ) Error!*logging.Owner {
        return logging.createValidated(allocator, logs, canonicalized) catch {
            return error.LoggingPolicyInvalid;
        };
    }
};

test "rejects duplicate selectors and body classes without a direction" {
    const canonicalized = try logging.canonicalizeConfiguredLevel("debug");
    try std.testing.expectError(error.LoggingPolicyInvalid, (Action{}).execute(
        std.testing.allocator,
        .{ .level = "debug", .console = false, .promptCapture = &.{ .request, .request } },
        canonicalized,
    ));
    try std.testing.expectError(error.LoggingPolicyInvalid, (Action{}).execute(
        std.testing.allocator,
        .{ .level = "debug", .console = false, .promptCapture = &.{.code_body} },
        canonicalized,
    ));
}

test "rejects canonicalization evidence from a different config value" {
    const canonicalized = try logging.canonicalizeConfiguredLevel("debug");
    try std.testing.expectError(error.LoggingPolicyInvalid, (Action{}).execute(
        std.testing.allocator,
        .{ .level = "info", .console = false, .promptCapture = &.{} },
        canonicalized,
    ));
}
