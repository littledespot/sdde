const bootstrap_error = @import("bootstrap_error.zig");
const execution = @import("workflow_execution.zig");

pub const Outcome = union(enum) {
    execution: execution.Outcome,
    execution_rejected: execution.Rejection,
    bootstrap_failed: bootstrap_error.PublicError,
    invocation_invalid,

    pub fn executionStatus(self: Outcome) ?execution.Outcome {
        return switch (self) {
            .execution => |value| value,
            .execution_rejected => |reason| reason.status(),
            .bootstrap_failed, .invocation_invalid => null,
        };
    }
};
