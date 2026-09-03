const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const log_binding = @import("../../domain/feature_log_binding.zig");
const log_stream = @import("../../domain/feature_log_stream.zig");
const sink_port = @import("../../ports/feature_log_sink.zig");

pub const Error = error{LogSinkFailure};
pub const Action = struct {
    sink: sink_port.StreamRecoverer,
    pub const contract: pipeline.NodeContract = .{
        .id = "recover-feature-log-stream@1",
        .kind = .action,
        .requires = &.{ .feature_log_binding, .feature_log_stream_lock },
        .produces = &.{.feature_log_stream_state},
        .side_effect = .filesystem_write,
    };
    pub fn execute(self: Action, allocator: std.mem.Allocator, binding: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, heading: []const u8) Error!log_stream.Recovery {
        return self.sink.recover(binding, stream, heading, allocator) catch error.LogSinkFailure;
    }
};
