const pipeline = @import("../../domain/pipeline.zig");
const session = @import("../../domain/specification_session.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "complete-scenario-generation", .kind = .action, .requires = &.{.specification_generation_session}, .produces = &.{}, .replaces = &.{.specification_generation_session}, .side_effect = .none };

    /// The one completion of the records unit: the held batches merge once every group with a slot has
    /// its criteria (ADR 0038 Decision 3).
    pub fn execute(_: Action, allocator: @import("std").mem.Allocator, current: session.Session) session.Error!session.Session {
        return session.completeScenarios(allocator, current);
    }
};
