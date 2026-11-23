const pipeline = @import("../../domain/pipeline.zig");
const workflow = @import("../../domain/workflow.zig");
const authentication = @import("../../domain/clarification_authentication.zig");

/// `more` while a form awaits its observation, else `ok`. It reads the progress and changes nothing.
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "check-clarification-authentication",
        .kind = .action,
        .requires = &.{ .clarification_inputs, .authentication_progress },
        .produces = &.{},
        .side_effect = .none,
    };
    pub fn execute(_: Action, progress: authentication.Progress) workflow.OutcomeTag {
        return if (authentication.more(progress)) .more else .ok;
    }
};
