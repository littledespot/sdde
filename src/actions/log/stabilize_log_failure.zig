const stabilizer_port = @import("../../ports/transaction_stabilizer.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{LogFailureStabilizationFailed};

pub const Action = struct {
    stabilizer: stabilizer_port.Stabilizer,
    pub const contract: pipeline.NodeContract = .{
        .id = "stabilize-log-failure@1",
        .kind = .action,
        .requires = &.{},
        .produces = &.{},
        .side_effect = .filesystem_write,
    };

    pub fn execute(self: Action) Error!void {
        self.stabilizer.stabilize() catch return error.LogFailureStabilizationFailed;
    }
};
