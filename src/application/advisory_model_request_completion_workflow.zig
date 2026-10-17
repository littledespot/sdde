const std = @import("std");
const requests = @import("model_request_workflow.zig");
const values = @import("pipeline_values.zig");
const identity = @import("../domain/model_request_identity.zig");
const selection = @import("../domain/workflow_model_request_lifecycle.zig");
const operations = @import("../ports/workflow_operation_registry.zig");

/// Close a natively stopped optional request, without accepting any candidate.
pub const Complete = struct {
    pub const Action = @import("../actions/model/advance_model_request_lifecycle.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
        .id = "complete-advisory-model-request",
        .kind = .step,
        .requires = &selection.completion_requires,
        .replaces = &.{.model_request_identity_ledger},
        .outcomes = &.{.more},
        .side_effect = .none,
        .outcome_association = .{ .advisory_request_closure = .{ .kind = .request, .subject = .prepared_model_request, .evidence = .model_payload_schema_result } },
    };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!@import("../domain/workflow_execution.zig").Candidate {
        const self = context.?;
        _ = try @import("advisory_request_completion_workflow.zig").closing(&input.step.data);
        const facts = try @import("model_request_completion_workflow.zig").readCurrent(&input.step.data);
        if (facts.outcome != .more or facts.reason != .failed) return error.OperationExecutionFailed;
        const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const current = try values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger);
        const owner = try self.action.execute(current, input.step.model_request_lifecycle orelse return error.OperationExecutionFailed, current.revision(), request.id(), facts.expected_status, .{ .terminal = .failed });
        errdefer identity.deinitOwner(owner);
        var delta: @import("../domain/pipeline.zig").NodeDelta = .{};
        delta.data_replacements[@intFromEnum(requests.ledger_schema.key)] = try requests.adoptLedger(self.allocator, owner);
        return .{ .outcome = .more, .delta = delta };
    }
};
