const std = @import("std");
const operations = @import("../ports/workflow_operation_registry.zig");
const preparation = @import("../ports/provider_operation_authorization.zig");
const provider = @import("../domain/llm_provider_operation.zig");
const result = @import("../domain/provider_authorization_result.zig");
const selection = @import("../domain/workflow_provider_authorization.zig");
const values = @import("pipeline_values.zig");

pub const schema = values.schema(.provider_authorization_result, result.Result, 1, null).captured();

pub const Prepare = struct {
    pub const Action = @import("../actions/model/prepare_provider_operation_authorization.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
        .id = Action.contract.id,
        .kind = .step,
        .requires = &selection.requires,
        .produces = &.{.provider_authorization_result},
        .outcomes = &.{ .ok, .failed, .cancelled },
        .side_effect = .none,
        .parameters = &.{selection.parameter},
    };
    allocator: std.mem.Allocator,
    // Composition must explicitly bind a preloaded port; no fake/default provider.
    action: ?Action = null,

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!@import("../domain/workflow_execution.zig").Candidate {
        const self = context.?;
        const bound = input.step.provider_authorization orelse return error.OperationExecutionFailed;
        const outcome: @import("../actions/model/prepare_provider_operation_authorization.zig").Outcome = if (self.action) |action| action.execute(bound.facts, bound.slot, bound.runtime) catch return error.OperationExecutionFailed else .{
            .failed = .{ .operation_id = bound.facts.operation_id, .cause = .authorization_denied, .retry_class = .never, .delivery = .not_sent },
        };
        var native: ?*@import("../domain/pipeline_data.zig").Value = null;
        defer if (native) |value| values.destroy(value);
        const payload: result.Outcome = switch (outcome) {
            .prepared => |delta| prepared: {
                native = delta.data_writes[@intFromEnum(@import("../domain/pipeline.zig").DataKey.validated_provider_authorization)] orelse return error.OperationExecutionFailed;
                const reference = values.read(&.{ .slots = delta.data_writes }, preparation.value_schema, provider.ValidatedProviderAuthorizationLeaseRef) catch return error.OperationExecutionFailed;
                break :prepared .{ .prepared = reference.* };
            },
            .failed => |failure| .{ .failed = failure },
            .cancelled => .{ .cancelled = bound.facts.operation_id },
        };
        const ledger = values.read(&input.step.data, @import("model_request_workflow.zig").ledger_schema, @import("../domain/model_request_identity.zig").ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
        const owner = result.create(self.allocator, ledger, payload) catch return error.OperationExecutionFailed;
        errdefer result.destroy(owner);
        const value = values.adopt(self.allocator, schema, result.Result, result.Result, owner, get, result.destroy, null) catch return error.OperationExecutionFailed;
        var delta: @import("../domain/pipeline.zig").NodeDelta = .{};
        delta.data_writes[@intFromEnum(schema.key)] = value;
        return .{ .outcome = switch (payload) {
            .prepared => .ok,
            .failed => .failed,
            .cancelled => .cancelled,
        }, .delta = delta };
    }
};

fn get(value: *const result.Result) *const result.Result {
    return value;
}
