const execution = @import("../domain/workflow_execution.zig");
const telemetry = @import("../domain/telemetry.zig");

pub const Barrier = struct {
    context: *anyopaque,
    process_fn: *const fn (*anyopaque, telemetry.WorkflowTelemetryFact) execution.Candidate,

    pub fn process(self: Barrier, fact: telemetry.WorkflowTelemetryFact) execution.Candidate {
        return self.process_fn(self.context, fact);
    }
};
