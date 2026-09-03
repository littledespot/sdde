const log_stream = @import("../domain/feature_log_stream.zig");

pub const Error = error{ClockFailure};
pub const Clock = struct {
    context: *anyopaque,
    now_fn: *const fn (*anyopaque) Error!log_stream.ClockReading,

    pub fn now(self: Clock) Error!log_stream.ClockReading {
        return self.now_fn(self.context);
    }
};
