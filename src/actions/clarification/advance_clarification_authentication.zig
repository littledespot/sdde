const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const evidence = @import("../../domain/actor_evidence.zig");
const authentication = @import("../../domain/clarification_authentication.zig");

/// Joins the observation of the form just authenticated to the progress and advances the loop's iteration. The
/// observation is dropped with it, so the next pass makes its own.
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "advance-clarification-authentication",
        .kind = .action,
        .requires = &.{ .clarification_inputs, .authentication_progress, .actor_observation },
        .produces = &.{},
        .replaces = &.{.authentication_progress},
        .invalidates = &.{.actor_observation},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, progress: authentication.Progress, observation: evidence.Observation) authentication.Error!authentication.Progress {
        return authentication.advance(allocator, progress, observation);
    }
};
