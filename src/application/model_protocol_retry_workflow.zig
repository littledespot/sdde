const std = @import("std");
const values = @import("pipeline_values.zig");
const requests = @import("model_request_workflow.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const identity = @import("../domain/model_request_identity.zig");
pub const Build = struct {
    pub const Action = @import("../actions/model/build_model_protocol_retry.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{ .id = Action.contract.id, .kind = .step, .requires = Action.contract.requires, .replaces = Action.contract.replaces, .invalidates = Action.contract.invalidates, .outcomes = &.{ .ok, .failed }, .side_effect = .none, .retry_limit = .{ .maximum = 1 }, .parameters = &.{.{ .id = "retry-limit", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 0, .integer_max = 0 }} };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const validated = try requests.readCurrent(&input.step.data, requests.validated_schema);
        if (current.id() != validated.id()) return error.OperationExecutionFailed;
        const ledger = values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
        const payload = try @import("model_payload_schema_workflow.zig").readCurrent(&input.step.data);
        var delta = @import("../domain/model_transport.zig").retire(.rejected_attempt, ledger, current.id(), @import("model_payload_schema_workflow.zig").status(payload)) catch return error.OperationExecutionFailed;
        const diagnostic: @import("../domain/model_protocol_retry.zig").Diagnostic = switch (payload.outcome()) {
            .schema_rejected => |reason| .{ .schema = reason },
            .not_validated => |source| if (source.outcome() == .protocol_rejected) .{ .decoder = .invalid_json_object } else return error.OperationExecutionFailed,
            .valid => return error.OperationExecutionFailed,
        };
        var input_id: [64]u8 = undefined;
        const input_bytes = std.fmt.bufPrint(&input_id, "protocol-{d}", .{ledger.revision().value}) catch return error.OperationExecutionFailed;
        const source = validated.source(.{ .bytes = input_bytes }) catch return error.OperationExecutionFailed;
        const prompt = current.protocolPrompt() orelse return error.OperationExecutionFailed;
        var prepared = self.action.execute(self.allocator, source, current.prepared() orelse return error.OperationExecutionFailed, diagnostic, prompt) catch return error.OperationExecutionFailed;
        const next = @import("../domain/model_request_handoff.zig").prepared(validated, prepared) catch {
            prepared.deinit();
            return error.OperationExecutionFailed;
        };
        errdefer @import("../domain/model_request_handoff.zig").destroy(next);
        delta.data_replacements[@intFromEnum(requests.prepared_schema.key)] = requests.adoptRequest(self.allocator, requests.prepared_schema, next) catch return error.OperationExecutionFailed;
        return .{ .outcome = .ok, .delta = delta };
    }
};
pub const Check = struct {
    pub const Action = @import("../actions/model/check_model_request_phase.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{ .id = Action.contract.id, .kind = .step, .requires = Action.contract.requires, .outcomes = &.{ .ok, .more, .failed }, .side_effect = .none };
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const current = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const ledger = values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
        return .{ .outcome = context.?.action.execute(ledger, current.id()), .delta = .{} };
    }
};
