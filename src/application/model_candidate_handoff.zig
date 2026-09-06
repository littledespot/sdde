//! Read the existing payload proof and exact immutable request input. Domain
//! bindings cannot substitute another request, packet or unvalidated response.
const data = @import("../domain/pipeline_data.zig");
const packets = @import("../domain/model_input_packet.zig");
const requests = @import("model_request_workflow.zig");
pub const requires = [_]@import("../domain/pipeline.zig").DataKey{ .model_request_identity_ledger, .prepared_model_request, .model_input_packet, .model_payload_schema_result };
pub fn body(view: *const data.View) @import("../ports/workflow_operation_registry.zig").Error![]const u8 {
    const request = try requests.readCurrent(view, requests.prepared_schema);
    const packet = @import("pipeline_values.zig").read(view, requests.packet_schema, packets.Packet) catch return error.OperationExecutionFailed;
    if (request.packet() != packet) return error.OperationExecutionFailed;
    const result = try @import("model_payload_schema_workflow.zig").readCurrent(view);
    return switch (result.outcome()) {
        .valid => |proof| switch (proof.candidate().association().result()) {
            .complete => |complete| complete.content(),
            .stopped, .failed => error.OperationExecutionFailed,
        },
        .schema_rejected, .not_validated => error.OperationExecutionFailed,
    };
}
