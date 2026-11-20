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
    candidate_error: ?@import("candidate_validation_diagnostic.zig").Diagnostic = null,
    last_operation_rejection: ?execution.OperationRejection = null,
    /// For a startup failure in the workflow authority: where and why, printed after the public code.
    bootstrap_detail: ?@import("definition_rejection.zig").Detail = null,
    /// The typed cause of the last model call when it failed, printed after the terminal outcome. A
    /// later call that completes leaves none.
    provider_failure: ?@import("provider_failure_detail.zig").Detail = null,
    /// The display path of the reference entry whose own reason ended the run, printed after that reason's name
    /// (13-03, contract 08). Never authority, and no event, log or E2E report records it.
    reference_entry_path: ?@import("pipeline.zig").StageEntryPath = null,
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
