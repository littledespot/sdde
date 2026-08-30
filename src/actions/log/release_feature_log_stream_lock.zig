const pipeline = @import("../../domain/pipeline.zig");
const sink_port = @import("../../ports/feature_log_sink.zig");

pub const Error = error{LogReleaseFailure};
pub const Action = struct {
    sink: sink_port.Sink,
    pub const contract: pipeline.NodeContract = .{
        .id = "release-feature-log-stream-lock@1",
        .kind = .action,
        .requires = &.{.feature_log_stream_lock},
        .invalidates = &.{.feature_log_stream_lock},
        .side_effect = .filesystem_write,
    };
    pub fn execute(self: Action) Error!void {
        self.sink.release() catch return error.LogReleaseFailure;
    }
};
