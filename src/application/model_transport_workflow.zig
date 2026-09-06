const transport = @import("../domain/model_transport.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const requests = @import("model_request_workflow.zig");
const payload = @import("model_payload_schema_workflow.zig");

pub fn Retire(comptime retirement: transport.Retirement) type {
    return struct {
        pub const Action = switch (retirement) {
            .request => @import("../actions/model/retire_model_request.zig").Action,
            .rejected_attempt => @import("../actions/model/retire_rejected_model_attempt.zig").Action,
            .input => @import("../actions/model/retire_model_input.zig").Action,
        };
        pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
            .id = Action.contract.id,
            .kind = .step,
            .requires = Action.contract.requires,
            .invalidates = Action.contract.invalidates,
            .outcomes = &.{ .ok, .failed },
            .side_effect = .none,
        };
        action: Action = .{},
        pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!@import("../domain/workflow_execution.zig").Candidate {
            const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
            const result = try payload.readCurrent(&input.step.data);
            const ledger = @import("pipeline_values.zig").read(&input.step.data, requests.ledger_schema, @import("../domain/model_request_identity.zig").ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
            return .{ .outcome = .ok, .delta = context.?.action.execute(ledger, request.id(), payload.status(result)) catch return error.OperationExecutionFailed };
        }
    };
}
