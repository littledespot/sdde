const bootstrap_error = @import("bootstrap_error.zig");
const execution = @import("workflow_execution.zig");
const std = @import("std");

pub const Clarification = struct {
    id: @import("clarification_inputs.zig").Id,
    path: @import("workflow_artifact_registry.zig").ArtifactPath,
};

/// Owned presentation data copied before the invocation releases its state.
pub const Report = struct {
    outcome: Outcome,
    clarifications: []const Clarification = &.{},
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *Report) void {
        self.arena.deinit();
    }
};

pub const Outcome = union(enum) {
    execution: execution.Outcome,
    execution_rejected: execution.Rejection,
    bootstrap_failed: bootstrap_error.PublicError,
    invocation_invalid,

    pub fn executionStatus(self: Outcome) ?execution.Outcome {
        return switch (self) {
            .execution => |value| value,
            .execution_rejected => |reason| reason.status(),
            .bootstrap_failed, .invocation_invalid => null,
        };
    }
};
