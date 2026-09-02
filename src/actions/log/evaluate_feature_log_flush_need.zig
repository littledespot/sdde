const logging = @import("../../domain/logging.zig");
const runtime = @import("../../domain/feature_log_runtime.zig");
const telemetry = @import("../../domain/telemetry.zig");

pub const Decision = enum { flush, buffer };

pub const Action = struct {
    pub fn execute(
        _: Action,
        policy: logging.CompiledLoggingPolicy,
        level: telemetry.CanonicalLogLevel,
        event_type: telemetry.EventType,
        state: runtime.StreamState,
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
