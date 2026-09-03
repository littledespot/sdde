const log_stream = @import("../../domain/feature_log_stream.zig");
const clock_port = @import("../../ports/trusted_log_clock.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{LogClockReadFailure};

pub const Action = struct {
    clock: clock_port.Clock,
    pub const contract: pipeline.NodeContract = .{
        .id = "read-trusted-log-clock@1",
        .kind = .action,
        .requires = &.{},
        .produces = &.{.trusted_log_clock},
        .side_effect = .none,
    };

    pub fn execute(self: Action) Error!log_stream.ClockReading {
        return self.clock.now() catch error.LogClockReadFailure;
    }
};
