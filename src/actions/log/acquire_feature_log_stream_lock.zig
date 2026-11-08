const log_limits = @import("../../domain/feature_log_limits.zig");
const pipeline = @import("../../domain/pipeline.zig");
const log_binding = @import("../../domain/feature_log_binding.zig");
const log_stream = @import("../../domain/feature_log_stream.zig");
const sink_port = @import("../../ports/feature_log_sink.zig");

pub const Error = error{ LogLockTimeout, LogSinkFailure };

/// F0002: only a lock held elsewhere is a timeout. A binding the sink rejects, or a lock file
/// it cannot use, is a sink failure.
pub fn failureCode(failure: Error) log_stream.FailureCode {
    return switch (failure) {
        error.LogLockTimeout => .LOG_LOCK_TIMEOUT,
        error.LogSinkFailure => .LOG_SINK_FAILURE,
    };
}

pub const Action = struct {
    sink: sink_port.LockAcquirer,
    pub const contract: pipeline.NodeContract = .{
        .id = "acquire-feature-log-stream-lock",
        .kind = .action,
        .requires = &.{.feature_log_binding},
        .produces = &.{.feature_log_stream_lock},
        .side_effect = .filesystem_write,
    };
    pub fn execute(self: Action, binding: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream) Error!void {
        self.sink.acquire(binding, stream, log_limits.stream_lock_deadline_ms) catch |failure| return switch (failure) {
            error.LockUnavailable => error.LogLockTimeout,
            error.InvalidBinding, error.CorruptStream, error.SegmentLimitExhausted, error.SinkFailure, error.FlushFailure, error.ReleaseFailure => error.LogSinkFailure,
        };
    }
};
