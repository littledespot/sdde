const bootstrap_error = @import("bootstrap_error.zig");
const execution = @import("workflow_execution.zig");

pub const Outcome = union(enum) {
    execution: execution.Outcome,
    bootstrap_failed: bootstrap_error.PublicError,
    invocation_invalid,
};
