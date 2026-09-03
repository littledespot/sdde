const log_policy = @import("../../domain/log_policy.zig");
const pipeline = @import("../../domain/pipeline.zig");
const telemetry = @import("../../domain/telemetry.zig");

pub const Decision = enum { emit, drop };

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "evaluate-log-threshold@1",
        .kind = .action,
        .requires = &.{ .logging_policy, .log_event_definition },
        .produces = &.{.log_emit_decision},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        policy: log_policy.CompiledLoggingPolicy,
        level: telemetry.CanonicalLogLevel,
    ) Decision {
        return if (log_policy.isEmitted(policy, level)) .emit else .drop;
    }
};

test "drops before any identity or sink work" {
    const policy: log_policy.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .warning, .alias_evidence = .none },
        .console = false,
        .prompt_capture = &.{},
    };
    try @import("std").testing.expectEqual(Decision.drop, (Action{}).execute(policy, .info));
}
