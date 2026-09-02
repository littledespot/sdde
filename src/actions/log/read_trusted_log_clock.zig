const runtime = @import("../../domain/feature_log_runtime.zig");
const clock_port = @import("../../ports/trusted_log_clock.zig");

pub const Error = error{LogClockReadFailure};

pub const Action = struct {
    clock: clock_port.Clock,
    pub fn execute(self: Action) Error!runtime.ClockReading {
        return self.clock.now() catch error.LogClockReadFailure;
    }
};
