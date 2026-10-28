const log_event_registry = @import("../../domain/log_event_registry.zig");
const log_policy = @import("../../domain/log_policy.zig");
const pipeline = @import("../../domain/pipeline.zig");
const telemetry = @import("../../domain/telemetry.zig");

pub const Decision = enum { emit, drop };

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "evaluate-log-threshold",
        .kind = .action,
        .requires = &.{ .logging_policy, .log_event_definition },
        .produces = &.{.log_emit_decision},
        .side_effect = .none,
    };

    /// An ADR-required event is emitted at every threshold (§26.5); every other
    /// event follows the configured threshold.
    pub fn execute(
        _: Action,
        policy: log_policy.CompiledLoggingPolicy,
        definition: log_event_registry.EventDefinition,
    ) Decision {
        return switch (definition.emission) {
            .always => .emit,
            .threshold => if (log_policy.isEmitted(policy, definition.level)) .emit else .drop,
        };
    }
};

test "drops before any identity or sink work" {
    const policy: log_policy.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .warning, .alias_evidence = .none },
        .console = false,
    };
    try @import("std").testing.expectEqual(Decision.drop, (Action{}).execute(policy, log_event_registry.eventDefinition(.run_started)));
}

test "ADR-required events are emitted at every threshold; other warnings follow it" {
    const testing = @import("std").testing;
    for (@import("std").enums.values(telemetry.CanonicalLogLevel)) |configured| {
        const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = configured, .alias_evidence = .none }, .console = false };
        for ([_]telemetry.EventType{ .model_response_normalized, .model_provider_stopped, .model_runaway_resent, .review_incomplete }) |required|
            try testing.expectEqual(Decision.emit, (Action{}).execute(policy, log_event_registry.eventDefinition(required)));
        const ordinary = log_event_registry.eventDefinition(.validation_failed);
        try testing.expectEqual(log_event_registry.Emission.threshold, ordinary.emission);
        try testing.expectEqual(if (log_policy.isEmitted(policy, ordinary.level)) Decision.emit else Decision.drop, (Action{}).execute(policy, ordinary));
    }
}
