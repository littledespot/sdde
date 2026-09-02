const stabilizer_port = @import("../../ports/transaction_stabilizer.zig");

pub const Error = error{LogFailureStabilizationFailed};

pub const Action = struct {
    stabilizer: stabilizer_port.Stabilizer,
    pub fn execute(self: Action) Error!void {
        self.stabilizer.stabilize() catch return error.LogFailureStabilizationFailed;
    }
};
