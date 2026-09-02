const logging = @import("../../domain/logging.zig");
const telemetry = @import("../../domain/telemetry.zig");

pub const Error = error{InvalidLogEventFact};

pub const Action = struct {
    pub fn execute(_: Action, fact: telemetry.TelemetryFact) Error!logging.EventDefinition {
        return logging.validateFact(fact) catch error.InvalidLogEventFact;
    }
};
