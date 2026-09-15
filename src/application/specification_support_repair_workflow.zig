//! Runner bindings for the shared review repair contract; YAML owns retries.
const std = @import("std");
const repair = @import("../domain/specification_support_repair.zig");
const support = @import("specification_support_workflow.zig");
const authority = @import("required_authority_workflow.zig");
const owned = @import("required_authority_values.zig");
const spec = @import("specification_workflow.zig");
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
pub const schema = values.schema(.specification_support_repair, owned.Value, 1, null).captured();
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{schema};
pub const Authorize = struct {
    pub const Action = @import("../actions/specification/authorize_specification_support_repair.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .blocked, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = owned.read(&input.step.data, authority.inputs_schema, .inputs) catch return error.OperationExecutionFailed;
        const current = owned.read(&input.step.data, support.schema, .support) catch return error.OperationExecutionFailed;
        if (current != .rejected) return error.OperationExecutionFailed;
        const context_value = try spec.readContext(&input.step.data);
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        const authorization = self.action.execute(owner.arena.allocator(), source, context_value, current.rejected) catch |err| {
            if (err == error.OutOfMemory) return error.OperationExecutionFailed;
            return owned.publish(self.allocator, schema, owner, .blocked) catch error.OperationExecutionFailed;
        };
        owner.payload = .{ .support_repair = .{ .authorization = authorization } };
        return owned.publish(self.allocator, schema, owner, if (authorization.operation == .delete) .more else .ok) catch error.OperationExecutionFailed;
    }
};
pub const BuildInput = struct {
    pub const Action = @import("../actions/specification/build_specification_support_repair_input.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = owned.read(&input.step.data, authority.inputs_schema, .inputs) catch return error.OperationExecutionFailed;
        const state = owned.read(&input.step.data, schema, .support_repair) catch return error.OperationExecutionFailed;
        const current = owned.read(&input.step.data, support.schema, .support) catch return error.OperationExecutionFailed;
        if (current != .rejected or current.rejected.candidate == null) return error.OperationExecutionFailed;
        return @import("model_request_workflow.zig").publishPacket(self.allocator, self.action.execute(self.allocator, source, try spec.readContext(&input.step.data), current.rejected.candidate.?, state.authorization) catch return error.OperationExecutionFailed);
    }
};
pub const Parse = struct {
    pub const Action = @import("../actions/specification/parse_specification_support_repair.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = owned.read(&input.step.data, schema, .support_repair) catch return error.OperationExecutionFailed;
        const packet = values.read(&input.step.data, @import("model_request_workflow.zig").packet_schema, @import("../domain/model_input_packet.zig").Packet) catch return error.OperationExecutionFailed;
        const handoff = try @import("model_candidate_handoff.zig").read(&input.step.data);
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .support_repair = .{ .authorization = state.authorization, .response = .{ .value = self.action.execute(owner.arena.allocator(), state.authorization, packet, handoff.body) catch return error.OperationExecutionFailed, .origin = handoff.origin } } };
        var delta: @import("../domain/pipeline.zig").NodeDelta = .{};
        delta.data_replacements[@intFromEnum(schema.key)] = values.adopt(self.allocator, schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch return error.OperationExecutionFailed;
        return .{ .outcome = .ok, .delta = delta };
    }
};
pub const Merge = struct {
    pub const Action = @import("../actions/specification/merge_specification_support_repair.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .invalid, .failed };
    pub const parameters = [_]@import("../domain/workflow_operation.zig").ParameterDescriptor{.{ .id = "retry-limit", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 0, .integer_max = std.math.maxInt(u32) }};
    pub const retry_limit: @import("../domain/workflow_operation.zig").RetryLimitDescriptor = .{ .maximum = std.math.maxInt(u32) };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = owned.read(&input.step.data, authority.inputs_schema, .inputs) catch return error.OperationExecutionFailed;
        const current = owned.read(&input.step.data, support.schema, .support) catch return error.OperationExecutionFailed;
        if (current != .rejected or current.rejected.candidate == null) return error.OperationExecutionFailed;
        const state = owned.read(&input.step.data, schema, .support_repair) catch return error.OperationExecutionFailed;
        const context_value = try spec.readContext(&input.step.data);
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        const result = self.action.execute(owner.arena.allocator(), source, context_value, current.rejected.candidate.?, state) catch {
            owned.destroy(owner);
            return error.OperationExecutionFailed;
        };
        var candidate = try support.publish(self.allocator, owner, result, true);
        for (Action.contract.invalidates) |key| candidate.delta.data_invalidations.insert(key);
        return candidate;
    }
};
