const pipeline = @import("../../domain/pipeline.zig");
const iteration = @import("../../domain/reference_model_iteration.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "check-reference-extraction-progress", .kind = .action, .requires = &.{.reference_extraction_progress}, .produces = &.{}, .side_effect = .none };
    pub fn execute(_: Action, progress: iteration.Progress) @import("../../domain/workflow.zig").OutcomeTag {
        return if (iteration.current(progress) != null) .more else .ok;
    }
};
