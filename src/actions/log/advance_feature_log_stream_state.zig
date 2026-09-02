const runtime = @import("../../domain/feature_log_runtime.zig");

pub const Action = struct {
    pub fn execute(
        _: Action,
        current: runtime.StreamState,
        row_bytes: usize,
        flushed: bool,
        monotonic_ms: u64,
    ) runtime.StreamState {
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
