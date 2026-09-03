const log_stream = @import("../../domain/feature_log_stream.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "advance-feature-log-stream-state@1",
        .kind = .action,
        .requires = &.{ .feature_log_stream_state, .feature_log_append_evidence, .trusted_log_clock },
        .replaces = &.{.feature_log_stream_state},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        current: log_stream.StreamState,
        row_bytes: usize,
        flushed: bool,
        monotonic_ms: u64,
    ) log_stream.StreamState {
        var next = current;
        next.segment_bytes += row_bytes;
        next.next_sequence += 1;
        if (flushed) {
            next.records_since_flush = 0;
            next.last_flush_monotonic_ms = monotonic_ms;
        } else {
            next.records_since_flush += 1;
        }
        return next;
    }
};
