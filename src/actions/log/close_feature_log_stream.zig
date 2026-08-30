const pipeline = @import("../../domain/pipeline.zig");
const runtime = @import("../../domain/feature_log_runtime.zig");
const sink_port = @import("../../ports/feature_log_sink.zig");

pub const Error = error{ LogSinkFailure, LogFlushFailure };
pub const Action = struct {
    sink: sink_port.Sink,
    pub const contract: pipeline.NodeContract = .{
        .id = "close-feature-log-stream@1",
        .kind = .action,
        .requires = &.{ .feature_log_binding, .feature_log_stream_lock, .feature_log_stream_state },
        .invalidates = &.{.feature_log_stream_state},
        .side_effect = .filesystem_write,
    };
    pub fn execute(self: Action, binding: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, state: runtime.StreamState, trailer: []const u8) Error!void {
        self.sink.close(binding, stream, state, trailer) catch |failure| return switch (failure) {
            error.FlushFailure => error.LogFlushFailure,
            else => error.LogSinkFailure,
        };
    }
};
