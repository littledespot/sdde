const std = @import("std");
const requests = @import("model_request_workflow.zig");
const values = @import("pipeline_values.zig");
const identity = @import("../domain/model_request_identity.zig");
const selection = @import("../domain/workflow_model_request_lifecycle.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const payload = @import("model_payload_schema_workflow.zig");
const lifecycle = @import("../domain/provider_operation_lifecycle.zig");

/// Close this request only. The candidate retains no semantic or commit authority.
pub const Complete = Completion(.inference);
pub const CompleteCount = Completion(.input_token_count);

fn Completion(comptime kind: @import("../domain/llm_provider_operation.zig").ProviderOperationKind) type {
    return struct {
        pub const Action = @import("../actions/model/advance_model_request_lifecycle.zig").Action;
        pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
            .id = if (kind == .inference) "complete-model-request" else "complete-count-request",
            .kind = .step,
            .requires = if (kind == .inference) &selection.completion_requires else &selection.count_completion_requires,
            .replaces = Action.contract.replaces,
            .outcomes = if (kind == .inference) &selection.completion_outcomes else &selection.termination_outcomes,
            .side_effect = Action.contract.side_effect,
        };
        allocator: std.mem.Allocator,
        action: Action = .{},

        pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!@import("../domain/workflow_execution.zig").Candidate {
            const self = context.?;
            if (input.step.data.contains(.provider_token_count_validation_result) != (kind == .input_token_count)) return error.OperationExecutionFailed;
            const facts = try readCurrent(&input.step.data);
            const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
            const current = values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
            const operation_ledger = input.step.model_request_lifecycle orelse return error.OperationExecutionFailed;
            const owner = self.action.execute(current, operation_ledger, current.revision(), request.id(), facts.expected_status, .{ .terminal = facts.reason }) catch return error.OperationExecutionFailed;
            errdefer identity.deinitOwner(owner);
            var delta: @import("../domain/pipeline.zig").NodeDelta = .{};
            delta.data_replacements[@intFromEnum(requests.ledger_schema.key)] = requests.adoptLedger(self.allocator, owner) catch return error.OperationExecutionFailed;
            return .{ .outcome = facts.outcome, .delta = delta };
        }
    };
}

/// Sealed result association only; no second parsing, validation or token charge.
pub fn readCurrent(view: *const @import("../domain/pipeline_data.zig").View) operations.Error!selection.Closure {
    if (view.contains(.provider_token_count_validation_result)) return readCountClosure(view);
    const result = try payload.readCurrent(view);
    const source = result.source().source();
    const terminal = values.read(view, @import("workflow_model_accounting.zig").terminal_schema, lifecycle.TerminalOperation) catch return error.OperationExecutionFailed;
    if (!terminal.record().id.eql(source.operationId()) or source.operationId().kind != .inference or
        source.outcome() == .rejected) return error.OperationExecutionFailed;
    const current = values.read(view, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
    const record = current.record(source.operationId().model_request_id) orelse return error.OperationExecutionFailed;
    if (record.status != .invoked) return error.OperationExecutionFailed;
    const outcome = payload.status(result);
    return .{
        .expected_status = .invoked,
        .reason = switch (outcome) {
            .ok => .accepted,
            // Explicit closure abandons invalid content; it does not assert retry exhaustion.
            .invalid, .failed => .failed,
            .cancelled => .cancelled,
            .more, .needs_user, .blocked => return error.OperationExecutionFailed,
        },
        .outcome = outcome,
    };
}

fn readCountClosure(view: *const @import("../domain/pipeline_data.zig").View) operations.Error!selection.Closure {
    const counts = @import("model_token_count_observation_workflow.zig");
    const source = try counts.readCurrent(view);
    const terminal = values.read(view, @import("workflow_model_accounting.zig").terminal_schema, lifecycle.TerminalOperation) catch return error.OperationExecutionFailed;
    const record = terminal.record();
    if (!record.id.eql(source.operationId()) or record.state != .terminal) return error.OperationExecutionFailed;
    const current = values.read(view, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
    const request_record = current.record(record.id.model_request_id) orelse return error.OperationExecutionFailed;
    if (request_record.status != .invoked) return error.OperationExecutionFailed;
    switch (source.outcome()) {
        .validated => |evidence| switch (evidence) {
            // Counting does not accept a logical request or authorize inference.
            .counted => return error.OperationExecutionFailed,
            .failed => |failure| {
                const fact = switch (record.state.terminal) {
                    .failed => |fact| fact,
                    else => return error.OperationExecutionFailed,
                };
                if (!std.meta.eql(fact.cause, failure.cause) or fact.retry_class != failure.retry_class or fact.delivery != failure.delivery) return error.OperationExecutionFailed;
                return .{ .expected_status = .invoked, .reason = .failed, .outcome = .failed };
            },
        },
        .cancelled => {
            if (record.state.terminal != .cancelled or record.state.terminal.cancelled != .accepted_or_unknown) return error.OperationExecutionFailed;
            return .{ .expected_status = .invoked, .reason = .cancelled, .outcome = .cancelled };
        },
        .rejected => return error.OperationExecutionFailed,
    }
}
