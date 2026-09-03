const log_policy = @import("../../domain/log_policy.zig");
const log_stream = @import("../../domain/feature_log_stream.zig");
const telemetry = @import("../../domain/telemetry.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Decision = enum { flush, buffer };

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "evaluate-feature-log-flush-need@1",
        .kind = .action,
        .requires = &.{ .logging_policy, .feature_log_stream_state, .trusted_log_clock },
        .produces = &.{.log_flush_decision},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        policy: log_policy.CompiledLoggingPolicy,
        level: telemetry.CanonicalLogLevel,
        event_type: telemetry.EventType,
        state: log_stream.StreamState,
        monotonic_ms: u64,
    ) Decision {
        const required = level.rank() >= policy.flush_at_or_above.rank() or
            terminalEvent(event_type) or
            state.records_since_flush + 1 >= policy.lower_level_flush_records or
            monotonic_ms -| state.last_flush_monotonic_ms >= policy.lower_level_flush_interval_ms;
        return if (required) .flush else .buffer;
    }
};

fn terminalEvent(event_type: telemetry.EventType) bool {
    return switch (event_type) {
        .stage_completed,
        .stage_blocked,
        .stage_failed,
        .task_completed,
        .task_blocked,
        .task_failed,
        .transaction_committed,
        .transaction_rolled_back,
        .transaction_recovered,
        => true,
        else => false,
    };
}
