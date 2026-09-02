const runtime = @import("../../domain/feature_log_runtime.zig");
const pipeline = @import("../../domain/pipeline.zig");
const sink_port = @import("../../ports/feature_log_sink.zig");

pub const Error = error{LogSinkFailure};
pub const Action = struct {
    sink: sink_port.SegmentPruner,
    pub const contract: pipeline.NodeContract = .{
        .id = "prune-feature-log-segment@1",
        .kind = .action,
        .requires = &.{ .feature_log_binding, .feature_log_stream_lock, .feature_log_retention_authorization },
        .invalidates = &.{.feature_log_retention_authorization},
        .side_effect = .filesystem_write,
    };
    pub fn execute(self: Action, binding: *const runtime.ValidatedFeatureLogBinding, authorization: *runtime.RetentionAuthorizationOwner) Error!void {
        const authorized = runtime.consumeRetentionAuthorization(authorization, binding) orelse return error.LogSinkFailure;
        self.sink.prune(binding, authorized.stream, authorized.cutoff_unix_ms) catch return error.LogSinkFailure;
    }
};
