const transport = @import("../domain/model_transport.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const requests = @import("model_request_workflow.zig");
const payload = @import("model_payload_schema_workflow.zig");

pub fn Retire(comptime retirement: transport.Retirement) type {
    return struct {
        pub const Action = switch (retirement) {
            .advisory_protocol => @compileError("Advisory protocol retirement requires its sealed stop receipt"),
            .request_and_input => @import("../actions/model/retire_model_transport.zig").Action,
            .request => @import("../actions/model/retire_model_request.zig").Action,
            .rejected_attempt => @compileError("Rejected attempt retirement belongs to protocol retry preparation"),
            .input => @import("../actions/model/retire_model_input.zig").Action,
        };
        pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
            .id = Action.contract.id,
            .kind = .step,
            .requires = Action.contract.requires,
            .invalidates = Action.contract.invalidates,
            .outcomes = &.{ .ok, .failed },
            .side_effect = .none,
            .outcome_association = .{ .preserve = .{ .kind = .request, .subject = .prepared_model_request, .evidence = .model_payload_schema_result } },
        };
        action: Action = .{},
        pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!@import("../domain/workflow_execution.zig").Candidate {
            const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
            const result = try payload.readCurrent(&input.step.data);
            const ledger = @import("pipeline_values.zig").read(&input.step.data, requests.ledger_schema, @import("../domain/model_request_identity.zig").ModelRequestIdentityLedger) catch |operation_error| return operation_error;
            return .{ .outcome = .ok, .delta = context.?.action.execute(ledger, request.id(), payload.status(result)) catch |operation_error| return operation_error };
        }
    };
}

/// The failed logical request has no current provider payload or terminal slot:
/// protocol retirement already released them before the exhausted attempt.
pub const RetireAdvisoryProtocol = struct {
    pub const Action = @import("../actions/model/retire_advisory_protocol_transport.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
        .id = Action.contract.id,
        .kind = .step,
        .requires = Action.contract.requires,
        .invalidates = Action.contract.invalidates,
        .outcomes = &.{ .ok, .failed },
        .side_effect = .none,
        .outcome_association = .{ .preserve = .{ .kind = .request, .subject = .prepared_model_request, .evidence = .accounted_model_attempt } },
    };
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!@import("../domain/workflow_execution.zig").Candidate {
        const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const receipt = try @import("workflow_model_accounting.zig").readAdvisoryStop(&input.step.data);
        const ledger = try @import("pipeline_values.zig").read(&input.step.data, requests.ledger_schema, @import("../domain/model_request_identity.zig").ModelRequestIdentityLedger);
        return .{ .outcome = .ok, .delta = try context.?.action.execute(ledger, request, receipt) };
    }
};

pub fn isAdvisoryProtocolRetirement(requires: []const @import("../domain/pipeline.zig").DataKey, invalidates: []const @import("../domain/pipeline.zig").DataKey) bool {
    const std = @import("std");
    return std.mem.eql(@import("../domain/pipeline.zig").DataKey, requires, &transport.advisory_protocol_requires) and
        std.mem.eql(@import("../domain/pipeline.zig").DataKey, invalidates, &transport.advisory_protocol_keys);
}
