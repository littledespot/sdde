const pipeline = @import("../domain/pipeline.zig");
const execution = @import("../domain/workflow_execution.zig");
const result = @import("feature_log_result.zig");

/// Translates the private logging result into the common pipeline ABI.
pub fn fromResult(outcome: result.Outcome) execution.Candidate {
    return switch (outcome) {
        .dropped => .{
            .outcome = .ok,
            .delta = .{ .data_writes = &.{.log_drop_evidence} },
        },
        .persisted => .{
            .outcome = .ok,
            .delta = .{ .data_writes = &.{.feature_log_append_evidence} },
        },
        .blocked => .{ .outcome = .blocked, .delta = pipeline.NodeDelta{} },
    };
}
