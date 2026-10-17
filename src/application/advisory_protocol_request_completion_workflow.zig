const std = @import("std");
const requests = @import("model_request_workflow.zig");
const values = @import("pipeline_values.zig");
const identity = @import("../domain/model_request_identity.zig");
const selection = @import("../domain/workflow_model_request_lifecycle.zig");
const operations = @import("../ports/workflow_operation_registry.zig");

/// Exhaustion creates no new provider operation or usage. Close only the
/// existing logical request identified by the native attempt-stop receipt.
pub const Complete = struct {
    pub const Action = @import("../actions/model/advance_model_request_lifecycle.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
        .id = "complete-advisory-protocol-request",
        .kind = .step,
        .requires = &selection.advisory_protocol_requires,
        .replaces = &.{.model_request_identity_ledger},
        .outcomes = &selection.advisory_protocol_outcomes,
        .side_effect = .none,
        .outcome_association = .{ .advisory_request_closure = .{ .kind = .request, .subject = .prepared_model_request, .evidence = .accounted_model_attempt } },
    };
    allocator: std.mem.Allocator,
    action: Action = .{},

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!@import("../domain/workflow_execution.zig").Candidate {
        const self = context.?;
        const receipt = try @import("workflow_model_accounting.zig").readAdvisoryStop(&input.step.data);
        const facts = try readCurrent(&input.step.data, receipt);
        const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const current = try values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger);
        const operations_ledger = input.step.model_request_lifecycle orelse return error.OperationExecutionFailed;
        const owner = try self.action.execute(current, operations_ledger, current.revision(), request.id(), facts.expected_status, .{ .terminal = facts.reason });
        errdefer identity.deinitOwner(owner);
        var delta: @import("../domain/pipeline.zig").NodeDelta = .{};
        delta.data_replacements[@intFromEnum(requests.ledger_schema.key)] = try requests.adoptLedger(self.allocator, owner);
        return .{ .outcome = facts.outcome, .delta = delta };
    }
};

pub fn readCurrent(view: *const @import("../domain/pipeline_data.zig").View, receipt: *const @import("../domain/model_attempt_decision.zig").StopReceipt) operations.Error!selection.Closure {
    const request = try requests.readCurrent(view, requests.prepared_schema);
    if (@import("../domain/advisory_completion.zig").protocolReason(request, receipt) == null) return error.OperationExecutionFailed;
    const current = try values.read(view, requests.ledger_schema, identity.ModelRequestIdentityLedger);
    const record = current.record(request.id()) orelse return error.OperationExecutionFailed;
    if (record.status != .invoked) return error.OperationExecutionFailed;
    return .{ .expected_status = .invoked, .reason = .failed, .outcome = .blocked };
}
