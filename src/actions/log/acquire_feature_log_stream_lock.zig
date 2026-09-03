const log_limits = @import("../../domain/feature_log_limits.zig");
const pipeline = @import("../../domain/pipeline.zig");
const log_binding = @import("../../domain/feature_log_binding.zig");
const log_stream = @import("../../domain/feature_log_stream.zig");
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
    pub fn execute(self: Action, binding: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream) Error!void {
        self.sink.acquire(binding, stream, log_limits.stream_lock_deadline_ms) catch return error.LogLockTimeout;
    }
};
