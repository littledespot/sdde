const std = @import("std");
const values = @import("pipeline_values.zig");
const requests = @import("model_request_workflow.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const identity = @import("../domain/model_request_identity.zig");
pub const Build = struct {
    pub const Action = @import("../actions/model/build_model_protocol_retry.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{ .id = Action.contract.id, .kind = .step, .requires = Action.contract.requires, .replaces = Action.contract.replaces, .invalidates = Action.contract.invalidates, .outcomes = &.{ .ok, .failed }, .side_effect = .none, .outcome_association = .{ .request_protocol = .{ .kind = .request, .subject = .prepared_model_request, .evidence = .model_payload_schema_result, .result = .prepared_model_request } } };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const validated = try requests.readCurrent(&input.step.data, requests.validated_schema);
        if (current.id() != validated.id()) return error.OperationExecutionFailed;
        const ledger = values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch |operation_error| return operation_error;
        const payload = try @import("model_payload_schema_workflow.zig").readCurrent(&input.step.data);
        var delta = @import("../domain/model_transport.zig").retire(.rejected_attempt, ledger, current.id(), @import("model_payload_schema_workflow.zig").status(payload)) catch |operation_error| return operation_error;
        const observation = payload.source().source().outcome();
        if (observation != .validated) return error.OperationExecutionFailed;
        const rejected = observation.validated;
        if (rejected.request() != current.prepared()) return error.OperationExecutionFailed;
        const diagnostic: @import("../domain/model_protocol_retry.zig").Diagnostic = switch (payload.outcome()) {
            .schema_rejected => |reason| .{ .schema = reason },
            .not_validated => |source| switch (source.outcome()) {
                .protocol_rejected => |reason| switch (reason.diagnostic) {
                    .decoder => |failure| .{ .decoder = failure },
                    .composition => |failure| .{ .composition = failure },
                },
                .not_decoded => if (rejected.missingFinalText()) .missing_final_text else return error.OperationExecutionFailed,
                .decoded => return error.OperationExecutionFailed,
            },
            .valid => return error.OperationExecutionFailed,
        };
        var input_id: [64]u8 = undefined;
        const input_bytes = std.fmt.bufPrint(&input_id, "protocol-{d}", .{ledger.revision().value}) catch |operation_error| return operation_error;
        const source = validated.source(.{ .bytes = input_bytes }) catch |operation_error| return operation_error;
        const prompt = current.protocolPrompt() orelse return error.OperationExecutionFailed;
        var parts: @import("../domain/model_request_handoff.zig").ContentBuffer = undefined;
        const repetition = current.protocolRepetition(rejected, diagnostic) catch |operation_error| return operation_error;
        var prepared = self.action.execute(self.allocator, source, validated.content(&parts), rejected, diagnostic, repetition, prompt) catch |operation_error| return operation_error;
        const next = @import("../domain/model_request_handoff.zig").prepared(validated, prepared, .{ .previous = current, .rejected = rejected, .diagnostic = diagnostic }) catch |native_failure| {
            prepared.deinit();
            return native_failure;
        };
        errdefer @import("../domain/model_request_handoff.zig").destroy(next);
        delta.data_replacements[@intFromEnum(requests.prepared_schema.key)] = requests.adoptRequest(self.allocator, requests.prepared_schema, next) catch |operation_error| return operation_error;
        return .{ .outcome = .ok, .delta = delta };
    }
};
pub const Check = struct {
    pub const Action = @import("../actions/model/check_model_request_phase.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{ .id = Action.contract.id, .kind = .step, .requires = Action.contract.requires, .outcomes = &.{ .ok, .more, .failed }, .side_effect = .none, .outcome_association = .{ .preserve = .{ .kind = .request, .subject = .prepared_model_request, .evidence = .model_request_identity_ledger } } };
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const current = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const ledger = values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch |operation_error| return operation_error;
        return .{ .outcome = context.?.action.execute(ledger, current.id()), .delta = .{} };
    }
};
/// ADR 0039: routes a first runaway to its one re-send, and every other
/// correctable rejection to protocol correction.
pub const Runaway = struct {
    pub const Action = @import("../actions/model/check_model_runaway.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{ .id = Action.contract.id, .kind = .step, .requires = Action.contract.requires, .outcomes = &.{ .ok, .more }, .side_effect = .none, .outcome_association = .{ .observe = .{ .kind = .request, .subject = .prepared_model_request, .evidence = .model_payload_schema_result } } };
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const current = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const prepared = current.prepared() orelse return error.OperationExecutionFailed;
        const payload = try @import("model_payload_schema_workflow.zig").readCurrent(&input.step.data);
        const rejected = switch (payload.source().source().outcome()) {
            .validated => |evidence| evidence,
            .rejected, .cancelled, .advisory_stopped => null,
        };
        if (rejected) |evidence| if (evidence.request() != prepared) return error.OperationExecutionFailed;
        return .{ .outcome = context.?.action.execute(prepared, rejected), .delta = .{} };
    }
};
/// ADR 0039: builds the one re-send of a first runaway under the same request.
pub const Resend = struct {
    pub const Action = @import("../actions/model/build_model_runaway_resend.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{ .id = Action.contract.id, .kind = .step, .requires = Action.contract.requires, .replaces = Action.contract.replaces, .invalidates = Action.contract.invalidates, .outcomes = &.{ .ok, .failed }, .side_effect = .none, .outcome_association = .{ .request_resend = .{ .kind = .request, .subject = .prepared_model_request, .evidence = .model_payload_schema_result, .result = .prepared_model_request } } };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const ledger = values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch |operation_error| return operation_error;
        const payload = try @import("model_payload_schema_workflow.zig").readCurrent(&input.step.data);
        var delta = @import("../domain/model_transport.zig").retire(.rejected_attempt, ledger, current.id(), @import("model_payload_schema_workflow.zig").status(payload)) catch |operation_error| return operation_error;
        const observation = payload.source().source().outcome();
        if (observation != .validated) return error.OperationExecutionFailed;
        const runaway = observation.validated;
        if (runaway.request() != current.prepared()) return error.OperationExecutionFailed;
        var prepared = self.action.execute(self.allocator, runaway) catch |operation_error| return operation_error;
        const next = @import("../domain/model_request_handoff.zig").resent(current, prepared, runaway) catch |native_failure| {
            prepared.deinit();
            return native_failure;
        };
        errdefer @import("../domain/model_request_handoff.zig").destroy(next);
        delta.data_replacements[@intFromEnum(requests.prepared_schema.key)] = requests.adoptRequest(self.allocator, requests.prepared_schema, next) catch |operation_error| return operation_error;
        return .{ .outcome = .ok, .delta = delta };
    }
};
