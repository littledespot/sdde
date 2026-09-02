const logging = @import("../../domain/logging.zig");
const pipeline = @import("../../domain/pipeline.zig");
const runtime = @import("../../domain/feature_log_runtime.zig");
const sink_port = @import("../../ports/feature_log_sink.zig");

pub const Error = error{LogLockTimeout};
pub const Action = struct {
    sink: sink_port.LockAcquirer,
    pub const contract: pipeline.NodeContract = .{
        .id = "acquire-feature-log-stream-lock@1",
        .kind = .action,
        .requires = &.{.feature_log_binding},
        .produces = &.{.feature_log_stream_lock},
        .side_effect = .filesystem_write,
    };
    pub fn execute(self: Action, binding: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream) Error!void {
        self.sink.acquire(binding, stream, logging.stream_lock_deadline_ms) catch return error.LogLockTimeout;
    }
};
