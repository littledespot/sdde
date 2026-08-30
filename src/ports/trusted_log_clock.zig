const runtime = @import("../domain/feature_log_runtime.zig");

pub const Error = error{ClockFailure};
pub const Clock = struct {
    context: *anyopaque,
    now_fn: *const fn (*anyopaque) Error!runtime.ClockReading,

    pub fn now(self: Clock) Error!runtime.ClockReading {
        return self.now_fn(self.context);
    }
};
