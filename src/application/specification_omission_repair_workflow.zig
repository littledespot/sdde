//! Existing post-generation repair owner, bound to current shared review facts.
const std = @import("std");
const repair = @import("../domain/specification_coverage_repair.zig");
const owned = @import("specification_values.zig").storage;
const authority = @import("required_authority_workflow.zig");
const authority_values = @import("required_authority_values.zig");
const spec = @import("specification_workflow.zig");
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const data = @import("../domain/pipeline_data.zig");
pub const schema = values.schema(.specification_omission_repair, owned.Value, 1, null).captured();
pub const schemas = [_]data.Schema{schema};
pub const Authorize = struct {
    pub const Action = @import("../actions/specification/authorize_specification_omission_repair.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .blocked, .failed };
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        const authorization = self.action.execute(owner.arena.allocator(), try spec.readSession(&input.step.data), try spec.readContext(&input.step.data), try content(&input.step.data), try support(&input.step.data)) catch |err| {
            if (err == error.OutOfMemory) return error.OperationExecutionFailed;
            return owned.publish(self.allocator, schema, owner, .blocked) catch error.OperationExecutionFailed;
        };
        owner.payload = .{ .omission_repair = .{ .authorization = authorization } };
        return owned.publish(self.allocator, schema, owner, .ok) catch error.OperationExecutionFailed;
    }
};
pub const BuildInput = struct {
    pub const Action = @import("../actions/specification/build_specification_omission_repair_input.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = owned.read(&input.step.data, schema, .omission_repair) catch return error.OperationExecutionFailed;
        const packet = self.action.execute(self.allocator, try spec.readSession(&input.step.data), try spec.readContext(&input.step.data), try content(&input.step.data), try support(&input.step.data), state.authorization) catch return error.OperationExecutionFailed;
        return @import("model_request_workflow.zig").publishPacket(self.allocator, packet);
    }
};
pub const Parse = struct {
    pub const Action = @import("../actions/specification/parse_specification_omission_repair.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = owned.read(&input.step.data, schema, .omission_repair) catch return error.OperationExecutionFailed;
        const packet = values.read(&input.step.data, @import("model_request_workflow.zig").packet_schema, @import("../domain/model_input_packet.zig").Packet) catch return error.OperationExecutionFailed;
        const handoff = try @import("model_candidate_handoff.zig").read(&input.step.data);
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .omission_repair = .{ .authorization = state.authorization, .response = .{ .value = self.action.execute(owner.arena.allocator(), state.authorization, packet, handoff.body) catch return error.OperationExecutionFailed, .origin = handoff.origin } } };
        var delta: @import("../domain/pipeline.zig").NodeDelta = .{};
        delta.data_replacements[@intFromEnum(schema.key)] = values.adopt(self.allocator, schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch return error.OperationExecutionFailed;
        return .{ .outcome = .ok, .delta = delta };
    }
};
pub const Merge = struct {
    pub const Action = @import("../actions/specification/merge_specification_omission_repair.zig").Action;
    pub const parameters = [_]@import("../domain/workflow_operation.zig").ParameterDescriptor{.{ .id = "retry-limit", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 0, .integer_max = std.math.maxInt(u32) }};
    pub const retry_limit: @import("../domain/workflow_operation.zig").RetryLimitDescriptor = .{ .maximum = std.math.maxInt(u32) };
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = owned.read(&input.step.data, schema, .omission_repair) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .session = self.action.execute(owner.arena.allocator(), try spec.readSession(&input.step.data), try spec.readContext(&input.step.data), try content(&input.step.data), try support(&input.step.data), state) catch return error.OperationExecutionFailed };
        var delta: @import("../domain/pipeline.zig").NodeDelta = .{};
        delta.data_replacements[@intFromEnum(spec.session_schema.key)] = values.adopt(self.allocator, spec.session_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch return error.OperationExecutionFailed;
        for (Action.contract.invalidates) |key| delta.data_invalidations.insert(key);
        return .{ .outcome = .ok, .delta = delta };
    }
};
fn content(view: *const data.View) operations.Error!@import("../domain/specification.zig").IdentifiedContent {
    return authority_values.read(view, authority.content_schema, .content) catch error.OperationExecutionFailed;
}
fn support(view: *const data.View) operations.Error!repair.Support {
    return .{ .inputs = authority_values.read(view, authority.inputs_schema, .inputs) catch return error.OperationExecutionFailed, .observations = authority_values.read(view, authority.observations_schema, .observations) catch return error.OperationExecutionFailed, .result = authority_values.read(view, authority.result_schema, .result) catch return error.OperationExecutionFailed };
}
