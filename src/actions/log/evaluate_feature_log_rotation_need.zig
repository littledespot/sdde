const log_limits = @import("../../domain/feature_log_limits.zig");
const log_stream = @import("../../domain/feature_log_stream.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Decision = union(enum) { append, rotate: u16, exhausted };
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "evaluate-feature-log-rotation-need@1",
        .kind = .action,
        .requires = &.{ .feature_log_stream_state, .serialized_log_record, .serialized_log_control_record },
        .produces = &.{.log_rotation_decision},
        .side_effect = .none,
    };

    pub fn execute(_: Action, state: log_stream.StreamState, row_bytes: usize, trailer_bytes: usize, next_header_bytes: usize) Decision {
        if (state.segment_bytes + row_bytes + trailer_bytes <= log_limits.max_segment_bytes) return .append;
        if (state.total_segment_count == log_limits.max_segments) return .exhausted;
        if (next_header_bytes + row_bytes > log_limits.max_segment_bytes) return .exhausted;
        return .{ .rotate = state.segment_ordinal + 1 };
    }
};
