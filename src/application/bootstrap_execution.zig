const bootstrap_error = @import("../domain/bootstrap_error.zig");
const pipeline = @import("../domain/pipeline.zig");
const child_bindings = @import("bootstrap_child_bindings.zig");

pub const State = struct {
    runtime: pipeline.NodeRuntime,
    envelope: pipeline.DataShape = .init(&.{ .invocation_working_directory, .workflow_operation_registry }),

    pub fn begin(
        self: *State,
        contract: pipeline.NodeContract,
        failure: bootstrap_error.PublicError,
    ) ?child_bindings.StepOutcome {
        if (self.terminal(failure)) |outcome| return outcome;
        self.envelope.validateInvocation(contract) catch return .{ .failed = failure };
        return null;
    }

    pub fn finish(
        self: *State,
        contract: pipeline.NodeContract,
        failure: bootstrap_error.PublicError,
    ) child_bindings.StepOutcome {
        if (self.terminal(failure)) |outcome| return outcome;
        self.envelope = self.envelope.apply(
            contract,
            pipeline.DataEffects.fromContract(contract),
        ) catch return .{ .failed = failure };
        return .ok;
    }

    fn terminal(
        self: *const State,
        failure: bootstrap_error.PublicError,
    ) ?child_bindings.StepOutcome {
        return switch (self.runtime.status()) {
            .active => null,
            .cancelled => .cancelled,
            .deadline_exhausted => .{ .failed = failure },
        };
    }
};
