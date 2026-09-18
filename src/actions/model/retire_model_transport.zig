const pipeline = @import("../../domain/pipeline.zig");
const identity = @import("../../domain/model_request_identity.zig");
const transport = @import("../../domain/model_transport.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "retire-model-transport", .kind = .action, .requires = &transport.requires, .produces = &.{}, .invalidates = transport.keys(.request_and_input), .side_effect = .none };
    pub fn execute(_: Action, ledger: *const identity.ModelRequestIdentityLedger, request: *const identity.ModelRequestId, payload: @import("../../domain/workflow.zig").OutcomeTag) error{InvalidTransportRetirement}!pipeline.NodeDelta {
        return transport.retire(.request_and_input, ledger, request, payload);
    }
};
