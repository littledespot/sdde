const pipeline = @import("../../domain/pipeline.zig");
const transport = @import("../../domain/model_transport.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "retire-advisory-protocol-transport",
        .kind = .action,
        .requires = &transport.advisory_protocol_requires,
        .produces = &.{},
        .invalidates = &transport.advisory_protocol_keys,
        .side_effect = .none,
    };
    pub fn execute(_: Action, ledger: *const @import("../../domain/model_request_identity.zig").ModelRequestIdentityLedger, request: *const @import("../../domain/model_request_handoff.zig").Request, receipt: *const @import("../../domain/model_attempt_decision.zig").StopReceipt) transport.Error!pipeline.NodeDelta {
        if (@import("../../domain/advisory_completion.zig").protocolReason(request, receipt) == null) return error.InvalidTransportRetirement;
        return transport.retire(.advisory_protocol, ledger, request.id(), .failed);
    }
};
