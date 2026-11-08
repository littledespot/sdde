const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const session = @import("../../domain/specification_session.zig");
const request = @import("../../domain/scenario_link_request.zig");
const provenance = @import("../../domain/specification_provenance.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "plan-scenario-links", .kind = .action, .requires = &.{ .specification_generation_session, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain }, .produces = &.{.scenario_link_progress}, .side_effect = .none };

    /// The number of edge cases that need a model choice, or the edge case no criterion serves.
    pub fn execute(_: Action, allocator: std.mem.Allocator, current: session.Session, context: provenance.Context) request.Error!request.Planned {
        return request.begin(allocator, current, context);
    }
};
