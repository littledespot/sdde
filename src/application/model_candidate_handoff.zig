//! Read the existing payload proof and exact immutable request input. Domain
//! bindings cannot substitute another request, packet or unvalidated response.
const data = @import("../domain/pipeline_data.zig");
const packets = @import("../domain/model_input_packet.zig");
const requests = @import("model_request_workflow.zig");
pub const requires = [_]@import("../domain/pipeline.zig").DataKey{ .model_request_identity_ledger, .prepared_model_request, .model_input_packet, .model_payload_schema_result };
pub const Candidate = struct { body: []const u8, origin: @import("../domain/model_candidate_origin.zig").Origin };
pub fn read(view: *const data.View) @import("../ports/workflow_operation_registry.zig").Error!Candidate {
    const request = try requests.readCurrent(view, requests.prepared_schema);
    const packet = @import("pipeline_values.zig").read(view, requests.packet_schema, packets.Packet) catch return error.OperationExecutionFailed;
    if (request.packet() != packet) return error.OperationExecutionFailed;
    const result = try @import("model_payload_schema_workflow.zig").readCurrent(view);
    const ledger = @import("pipeline_values.zig").read(view, requests.ledger_schema, @import("../domain/model_request_identity.zig").ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
    return switch (result.outcome()) {
        .valid => |proof| switch (proof.candidate().association().result()) {
            .complete => |complete| .{ .body = complete.content(), .origin = @import("../domain/model_candidate_origin.zig").Origin.from(ledger, complete.association().operationId()) orelse return error.OperationExecutionFailed },
            .stopped, .failed => error.OperationExecutionFailed,
        },
        .schema_rejected, .not_validated => error.OperationExecutionFailed,
    };
}
