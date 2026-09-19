const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const draft = @import("../../domain/incomplete_specification.zig");
const state = @import("../../domain/specification_state.zig");
pub const Action = struct {
    contracts: ?state.ContractSource = null,
    pub const contract: pipeline.NodeContract = .{
        .id = "build-incomplete-specification",
        .kind = .action,
        .requires = &.{ .prior_specification_state, .reference_snapshot, .refreshed_clarification_state },
        .produces = &.{.incomplete_specification_state},
        .side_effect = .none,
    };
    pub fn execute(self: Action, a: std.mem.Allocator, prior: state.Prior, snapshot: @import("../../domain/reference_snapshot.zig").Snapshot, clarifications: @import("../../domain/clarification_refresh.zig").Result) draft.Error!draft.State {
        if (clarifications != .ready) return error.InvalidIncompleteSpecification;
        return draft.build(a, prior, snapshot, clarifications.ready, self.contracts);
    }
};
