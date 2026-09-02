const pipeline = @import("../../domain/pipeline.zig");
const runtime = @import("../../domain/feature_log_runtime.zig");
const sink_port = @import("../../ports/feature_log_sink.zig");

pub const Error = error{LogSinkFailure};
pub const Action = struct {
    sink: sink_port.SegmentRotator,
    pub const contract: pipeline.NodeContract = .{
        .id = "rotate-feature-log-segment@1",
        .kind = .action,
        .requires = &.{ .feature_log_binding, .feature_log_stream_lock, .feature_log_stream_state },
        .replaces = &.{.feature_log_stream_state},
        .side_effect = .filesystem_write,
    };
    pub fn execute(self: Action, binding: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, state: runtime.StreamState, trailer: []const u8, heading: []const u8, header: []const u8) Error!runtime.StreamState {
        return self.sink.rotate(binding, stream, state, trailer, heading, header) catch error.LogSinkFailure;
    }
};
