//! Typed repair bindings; the workflow owns call ordering and bounded repetition.
const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const pipeline = @import("../domain/pipeline.zig");
const repair = @import("../domain/specification_repair.zig");
const owned = @import("specification_values.zig").storage;
const spec = @import("specification_workflow.zig");
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
pub const authorization_schema = values.schema(.specification_repair_authorization, owned.Value, 1, null).captured();
pub const schemas = [_]data.Schema{authorization_schema};

pub const Authorize = struct {
    pub const Action = @import("../actions/specification/authorize_specification_repair.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .invalid, .blocked, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const rejection = owned.read(&input.step.data, spec.checked_schema, .unit_rejected) catch return error.OperationExecutionFailed;
        const candidate = owned.read(&input.step.data, spec.parsed_schema, .parsed) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        const authorized = self.action.execute(owner.arena.allocator(), try spec.readSession(&input.step.data), try spec.readContext(&input.step.data), candidate, rejection) catch |err| return reject(self.allocator, authorization_schema, owner, err);
        owner.payload = .{ .repair_authorization = .{ .authorization = authorized } };
        return owned.publish(self.allocator, authorization_schema, owner, if (authorized.operation == .delete) .more else .ok) catch error.OperationExecutionFailed;
    }
};
pub const BuildInput = struct {
    pub const Action = @import("../actions/specification/build_specification_repair_input.zig").Action;
    pub const gates = spec.BuildInput.gates;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = owned.read(&input.step.data, authorization_schema, .repair_authorization) catch return error.OperationExecutionFailed;
        const packet = self.action.execute(self.allocator, try spec.readSession(&input.step.data), try spec.readContext(&input.step.data), state.authorization) catch return error.OperationExecutionFailed;
        return @import("model_request_workflow.zig").publishPacket(self.allocator, packet);
    }
};
pub const Parse = struct {
    pub const Action = @import("../actions/specification/parse_specification_repair.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = owned.read(&input.step.data, authorization_schema, .repair_authorization) catch return error.OperationExecutionFailed;
        const packet = values.read(&input.step.data, @import("model_request_workflow.zig").packet_schema, @import("../domain/model_input_packet.zig").Packet) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        const source = try @import("model_candidate_handoff.zig").read(&input.step.data);
        owner.payload = .{ .repair_authorization = .{ .authorization = state.authorization, .response = .{ .value = self.action.execute(owner.arena.allocator(), state.authorization, packet, source.body) catch return error.OperationExecutionFailed, .origin = source.origin } } };
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(authorization_schema.key)] = values.adopt(self.allocator, authorization_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch return error.OperationExecutionFailed;
        return .{ .outcome = .ok, .delta = delta };
    }
};
pub const Merge = struct {
    pub const parameters = [_]@import("../domain/workflow_operation.zig").ParameterDescriptor{.{ .id = "retry-limit", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 0, .integer_max = std.math.maxInt(u32) }};
    pub const retry_limit: @import("../domain/workflow_operation.zig").RetryLimitDescriptor = .{ .maximum = std.math.maxInt(u32) };
    pub const Action = @import("../actions/specification/merge_specification_repair.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = owned.read(&input.step.data, authorization_schema, .repair_authorization) catch return error.OperationExecutionFailed;
        const candidate = owned.read(&input.step.data, spec.parsed_schema, .parsed) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .parsed = self.action.execute(owner.arena.allocator(), try spec.readSession(&input.step.data), try spec.readContext(&input.step.data), candidate, state.authorization, if (state.response) |response| response.value else null, if (state.response) |response| response.origin else null) catch return error.OperationExecutionFailed };
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(spec.parsed_schema.key)] = values.adopt(self.allocator, spec.parsed_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch return error.OperationExecutionFailed;
        for (Action.contract.invalidates) |key| delta.data_invalidations.insert(key);
        return .{ .outcome = .ok, .delta = delta };
    }
};
fn reject(allocator: std.mem.Allocator, schema: data.Schema, owner: *owned.Owner, err: repair.Error) operations.Error!execution.Candidate {
    if (err == error.OutOfMemory) return error.OperationExecutionFailed;
    owner.payload = .rejected;
    return owned.publish(allocator, schema, owner, if (err == error.UnsafeSpecificationRepair) .blocked else .invalid) catch error.OperationExecutionFailed;
}
