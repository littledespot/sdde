const pipeline = @import("../../domain/pipeline.zig");
const workflow = @import("../../domain/workflow.zig");
const clarification = @import("../../domain/clarification_inputs.zig");
const acceptance = @import("../../domain/clarification_acceptance.zig");
const authentication = @import("../../domain/clarification_authentication.zig");

/// Reports `cancelled` when a form this run accepted cancelled its record, else `ok` (ADR 0025): the user's own `cancel`
/// ends the run, whatever else was accepted with it. It reads what acceptance produced and routes the one typed outcome.
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "check-clarification-cancellation",
        .kind = .action,
        .requires = &.{ .clarification_inputs, .authentication_progress },
        .produces = &.{},
        .side_effect = .none,
    };
    pub fn execute(_: Action, accepted: clarification.Inputs, progress: authentication.Progress) workflow.OutcomeTag {
        return if (acceptance.cancels(accepted, progress.pending)) .cancelled else .ok;
    }
};
