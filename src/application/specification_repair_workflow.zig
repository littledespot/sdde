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
pub const result_schema = values.schema(.specification_repair_result, owned.Value, 1, null).captured();
pub const schemas = [_]data.Schema{ authorization_schema, result_schema };
const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .invalid, .failed };

pub const Authorize = struct {
    pub const Action = @import("../actions/specification/authorize_specification_repair.zig").Action;
    pub const outcomes = @import("specification_repair_workflow.zig").outcomes;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        _ = owned.read(&input.step.data, spec.checked_schema, .rejected) catch return error.OperationExecutionFailed;
        const candidate = owned.read(&input.step.data, spec.parsed_schema, .parsed) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .repair_authorization = self.action.execute(owner.arena.allocator(), try spec.readSession(&input.step.data), try spec.readContext(&input.step.data), candidate) catch |err| return reject(self.allocator, authorization_schema, owner, err) };
        return owned.publish(self.allocator, authorization_schema, owner, .ok) catch error.OperationExecutionFailed;
    }
};
pub const BuildInput = struct {
    pub const Action = @import("../actions/specification/build_specification_repair_input.zig").Action;
    pub const gates = spec.BuildInput.gates;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const authorization = owned.read(&input.step.data, authorization_schema, .repair_authorization) catch return error.OperationExecutionFailed;
        const packet = self.action.execute(self.allocator, try spec.readSession(&input.step.data), try spec.readContext(&input.step.data), authorization) catch return error.OperationExecutionFailed;
        return @import("model_request_workflow.zig").publishPacket(self.allocator, packet);
    }
};
pub const Parse = struct {
    pub const Action = @import("../actions/specification/parse_specification_repair.zig").Action;
    pub const outcomes = @import("specification_repair_workflow.zig").outcomes;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const authorization = owned.read(&input.step.data, authorization_schema, .repair_authorization) catch return error.OperationExecutionFailed;
        const packet = values.read(&input.step.data, @import("model_request_workflow.zig").packet_schema, @import("../domain/model_input_packet.zig").Packet) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .repair_result = self.action.execute(owner.arena.allocator(), authorization, packet, (try @import("model_candidate_handoff.zig").read(&input.step.data)).body) catch |err| return reject(self.allocator, result_schema, owner, err) };
        return owned.publish(self.allocator, result_schema, owner, .ok) catch error.OperationExecutionFailed;
    }
};
pub const Merge = struct {
    pub const Action = @import("../actions/specification/merge_specification_repair.zig").Action;
    pub const outcomes = @import("specification_repair_workflow.zig").outcomes;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const authorization = owned.read(&input.step.data, authorization_schema, .repair_authorization) catch return error.OperationExecutionFailed;
        const candidate = owned.read(&input.step.data, spec.parsed_schema, .parsed) catch return error.OperationExecutionFailed;
        const replacement = owned.read(&input.step.data, result_schema, .repair_result) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .parsed = self.action.execute(owner.arena.allocator(), try spec.readSession(&input.step.data), candidate, authorization, replacement) catch return error.OperationExecutionFailed };
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(spec.parsed_schema.key)] = values.adopt(self.allocator, spec.parsed_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch return error.OperationExecutionFailed;
        for (Action.contract.invalidates) |key| delta.data_invalidations.insert(key);
        return .{ .outcome = .ok, .delta = delta };
    }
};
fn reject(allocator: std.mem.Allocator, schema: data.Schema, owner: *owned.Owner, err: repair.Error) operations.Error!execution.Candidate {
    if (err == error.OutOfMemory) return error.OperationExecutionFailed;
    owner.payload = .{ .rejected = .invalid_unit };
    return owned.publish(allocator, schema, owner, .invalid) catch error.OperationExecutionFailed;
}
