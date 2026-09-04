const telemetry = @import("../domain/telemetry.zig");
const log_stream = @import("../domain/feature_log_stream.zig");

pub const Barrier = struct {
    context: *anyopaque,
    process_fn: *const fn (*anyopaque, telemetry.WorkflowTelemetryFact) log_stream.Outcome,

    pub fn process(self: Barrier, fact: telemetry.WorkflowTelemetryFact) log_stream.Outcome {
        return self.process_fn(self.context, fact);
    }
};
