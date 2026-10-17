const std = @import("std");
const requests = @import("model_request_workflow.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const operation = @import("../domain/workflow_operation.zig");
const values = @import("pipeline_values.zig");
const accounting = @import("workflow_model_accounting.zig");
const decisions = @import("../domain/model_attempt_decision.zig");
const data = @import("../domain/pipeline_data.zig");

/// A single pure action call. The runner supplies immutable accounting inputs
/// and publishes the applied attempt; this binding cannot mutate either ledger.
pub const Advance = struct {
    pub const Action = @import("../actions/model/advance_model_attempt_accounting.zig").Action;
    pub const contract: operation.Contract = .{
        .id = Action.contract.id,
        .kind = .step,
        .requires = &.{ .model_request_identity_ledger, .prepared_model_request },
        .produces = &.{.accounted_model_attempt},
        .outcomes = &.{ .ok, .more, .failed },
        .side_effect = Action.contract.side_effect,
        .runner_accounting = Action.contract.runner_accounting,
        .parameters = &.{.{ .id = "retry-limit", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 0, .integer_max = std.math.maxInt(u32) }},
        .retry_limit = .{ .maximum = std.math.maxInt(u32), .scope = .model_request },
    };
    allocator: std.mem.Allocator,
    action: Action = .{},

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const current = @import("pipeline_values.zig").read(&input.step.data, requests.ledger_schema, @import("../domain/model_request_identity.zig").ModelRequestIdentityLedger) catch |operation_error| return operation_error;
        if (input.step.model_attempt_exhaustion) |exhaustion| {
            const decision = decisions.stopped(self.allocator, request, current, exhaustion) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.OperationExecutionFailed;
            errdefer decision.deinit();
            const retained = try values.retain(input.step.data.slots[@intFromEnum(requests.prepared_schema.key)].?);
            errdefer values.destroy(retained);
            const owner = try self.allocator.create(StoppedOwner);
            errdefer self.allocator.destroy(owner);
            owner.* = .{ .allocator = self.allocator, .request = retained, .decision = decision };
            var delta: @import("../domain/pipeline.zig").NodeDelta = .{};
            delta.data_writes[@intFromEnum(accounting.schema.key)] = try values.adopt(self.allocator, accounting.schema, decisions.Decision, StoppedOwner, owner, StoppedOwner.view, StoppedOwner.destroy, null);
            delta.runner_accounting_transition = .{ .advisory_model_attempt_stopped = decision.decision.outcome().advisory_stopped };
            return .{ .outcome = .more, .delta = delta };
        }
        const facts = input.step.model_attempt orelse return error.OperationExecutionFailed;
        const delta = self.action.execute(facts.accounting, facts.accounting.revision(), current, facts.operations, current.revision(), request.id(), facts.attempt) catch |operation_error| return operation_error;
        return .{ .outcome = .ok, .delta = delta };
    }
};

const StoppedOwner = struct {
    allocator: std.mem.Allocator,
    request: *data.Value,
    decision: decisions.Owned,
    fn view(self: *const StoppedOwner) *const decisions.Decision {
        return self.decision.decision;
    }
    fn destroy(self: *StoppedOwner) void {
        self.decision.deinit();
        values.destroy(self.request);
        self.allocator.destroy(self);
    }
};
