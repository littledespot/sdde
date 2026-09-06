const identity = @import("../../domain/model_request_identity.zig");
const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "check-model-request-phase", .kind = .action, .requires = &.{ .model_request_identity_ledger, .prepared_model_request }, .produces = &.{}, .side_effect = .none };
    pub fn execute(_: Action, ledger: *const identity.ModelRequestIdentityLedger, request: *const identity.ModelRequestId) @import("../../domain/workflow.zig").OutcomeTag {
        const record = ledger.record(request) orelse return .failed;
        return switch (record.status) {
            .assigned => .ok,
            .invoked => .more,
            .terminal => .failed,
        };
    }
};
