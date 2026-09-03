const pipeline = @import("../../domain/pipeline.zig");
const log_binding = @import("../../domain/feature_log_binding.zig");
const log_stream = @import("../../domain/feature_log_stream.zig");
const sink_port = @import("../../ports/feature_log_sink.zig");

pub const Error = error{LogSinkFailure};
pub const Action = struct {
    sink: sink_port.SegmentCreator,
    pub const contract: pipeline.NodeContract = .{
        .id = "create-feature-log-segment@1",
        .kind = .action,
        .requires = &.{ .feature_log_binding, .feature_log_stream_lock },
        .produces = &.{.feature_log_stream_state},
        .side_effect = .filesystem_write,
    };
    pub fn execute(self: Action, binding: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, ordinal: u16, seed: log_stream.StreamSeed, heading: []const u8, header: []const u8) Error!log_stream.StreamState {
        return self.sink.create(binding, stream, ordinal, seed, heading, header) catch error.LogSinkFailure;
    }
};
