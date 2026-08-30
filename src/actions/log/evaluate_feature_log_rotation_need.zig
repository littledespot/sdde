const logging = @import("../../domain/logging.zig");
const runtime = @import("../../domain/feature_log_runtime.zig");

pub const Decision = union(enum) { append, rotate: u16, exhausted };
pub const Action = struct {
    pub fn execute(_: Action, state: runtime.StreamState, row_bytes: usize, trailer_bytes: usize, next_header_bytes: usize) Decision {
        if (state.segment_bytes + row_bytes + trailer_bytes <= logging.max_segment_bytes) return .append;
        if (state.total_segment_count == logging.max_segments) return .exhausted;
        if (next_header_bytes + row_bytes > logging.max_segment_bytes) return .exhausted;
        return .{ .rotate = state.segment_ordinal + 1 };
    }
};
