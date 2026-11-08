const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const session = @import("../../domain/specification_session.zig");
const request = @import("../../domain/scenario_link_request.zig");
const link = @import("../../domain/scenario_link.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "check-scenario-link-progress", .kind = .action, .requires = &.{ .specification_generation_session, .scenario_link_progress }, .produces = &.{}, .side_effect = .none };

    /// `more` while an edge case still awaits its model choice.
    pub fn execute(_: Action, allocator: std.mem.Allocator, current: session.Session, chosen: []const link.Link) request.Error!@import("../../domain/workflow.zig").OutcomeTag {
        const pending = (try request.planFor(allocator, current)).pending.len;
        if (chosen.len > pending) return error.InvalidScenarioLink;
        return if (chosen.len == pending) .ok else .more;
    }
};
