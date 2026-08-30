pub const Error = error{StabilizationFailure};
pub const Stabilizer = struct {
    context: *anyopaque,
    stabilize_fn: *const fn (*anyopaque) Error!void,

    pub fn stabilize(self: Stabilizer) Error!void {
        return self.stabilize_fn(self.context);
    }
};
