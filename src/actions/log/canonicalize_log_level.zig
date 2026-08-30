const logging = @import("../../domain/logging.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{LoggingPolicyInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "canonicalize-log-level@1",
        .kind = .action,
        .requires = &.{.engine_config},
        .produces = &.{.canonical_log_level},
        .side_effect = .none,
    };

    pub fn execute(_: Action, raw: []const u8) Error!logging.CanonicalizedLevel {
        return logging.canonicalizeConfiguredLevel(raw) catch error.LoggingPolicyInvalid;
    }
};

test "canonicalizes case and only the two declared aliases" {
    const telemetry = @import("../../domain/telemetry.zig");
    try @import("std").testing.expectEqual(
        telemetry.CanonicalLogLevel.error_level,
        (try (Action{}).execute("ERROR")).threshold,
    );
    try @import("std").testing.expectError(
        error.LoggingPolicyInvalid,
        (Action{}).execute("NOTICE"),
    );
}
