const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "propagate-advisory-request-failure",
        .kind = .action,
        .requires = &.{ .model_request_identity_ledger, .prepared_model_request },
        .produces = &.{},
        .side_effect = .none,
    };
    /// A caller without a native advice resolver retains failure. No request,
    /// repair, outcome reference or publication authority is changed.
    pub fn execute(_: Action) @import("../../domain/workflow.zig").OutcomeTag {
        return .failed;
    }
};
