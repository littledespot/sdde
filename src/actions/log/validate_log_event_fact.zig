const log_event_registry = @import("../../domain/log_event_registry.zig");
const telemetry = @import("../../domain/telemetry.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{InvalidLogEventFact};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-log-event-fact@1",
        .kind = .action,
        .requires = &.{.workflow_telemetry_fact},
        .produces = &.{.log_event_definition},
        .side_effect = .none,
    };

    pub fn execute(_: Action, fact: telemetry.TelemetryFact) Error!log_event_registry.EventDefinition {
        return log_event_registry.validateFact(fact) catch error.InvalidLogEventFact;
    }
};
