const runtime = @import("../domain/feature_log_runtime.zig");
const telemetry = @import("../domain/telemetry.zig");

pub const Barrier = struct {
    context: *anyopaque,
    process_fn: *const fn (*anyopaque, telemetry.WorkflowTelemetryFact) runtime.BarrierOutcome,

    pub fn process(self: Barrier, fact: telemetry.WorkflowTelemetryFact) runtime.BarrierOutcome {
        return self.process_fn(self.context, fact);
    }
};
