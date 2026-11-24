const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const evidence = @import("../../domain/actor_evidence.zig");
const lease = @import("../../domain/actor_authentication_lease.zig");
const actor_port = @import("../../ports/actor_authentication.zig");

/// Observes the invoking operating-system account once, under the lease the runner issued for this invocation (ADR 0025).
/// The observation is the step's own; nothing here records it, validates it as evidence or accepts an answer.
pub const Action = struct {
    port: actor_port.Port,
    pub const contract: pipeline.NodeContract = .{
        .id = "authenticate-actor",
        .kind = .action,
        .requires = &.{ .clarification_inputs, .authentication_progress },
        .produces = &.{.actor_observation},
        .side_effect = .actor_authentication,
    };
    pub fn execute(self: Action, allocator: std.mem.Allocator, runtime: pipeline.NodeRuntime, granted: lease.Lease) actor_port.Error!evidence.Observation {
        return self.port.authenticate(allocator, runtime, granted);
    }
};
