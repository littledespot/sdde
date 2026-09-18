//! Runner bindings for the shared review repair contract; YAML owns retries.
const std = @import("std");
const repair = @import("../domain/specification_support_repair.zig");
const Purpose = @import("../domain/specification_support.zig").Purpose;
const support = @import("specification_support_workflow.zig");
const owned = @import("required_authority_values.zig");
const spec = @import("specification_workflow.zig");
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
pub const schema = values.schema(.specification_support_repair, owned.Value, 1, null).captured();
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{schema};
fn read(comptime selected: Purpose, view: *const @import("../domain/pipeline_data.zig").View) operations.Error!repair.Contract(selected).State {
    return owned.read(view, schema, if (selected == .source) .support_repair else .principle_support_repair) catch error.OperationExecutionFailed;
}
fn retain(comptime selected: Purpose, owner: *owned.Owner, state: repair.Contract(selected).State) void {
    owner.payload = if (selected == .source) .{ .support_repair = state } else .{ .principle_support_repair = state };
}
pub const Authorize = struct {
    pub const Action = @import("../actions/specification/authorize_specification_support_repair.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .blocked, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const progress = try support.progress(&input.step.data);
        const source = try support.inputs(&input.step.data, progress);
        inline for (.{ Purpose.source, .principles }) |selected| if (support.purpose(progress) == selected) {
            const current = try support.collection(selected, progress);
            if (current != .rejected) return error.OperationExecutionFailed;
            const context_value = try spec.readContext(&input.step.data);
            const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
            errdefer owned.destroy(owner);
            const authorization = self.action.execute(selected, owner.arena.allocator(), source, context_value, current.rejected) catch |err| {
                if (err == error.OutOfMemory) return error.OperationExecutionFailed;
                return owned.publish(self.allocator, schema, owner, .blocked) catch error.OperationExecutionFailed;
            };
            retain(selected, owner, .{ .authorization = authorization });
            return owned.publish(self.allocator, schema, owner, if (authorization.operation == .delete) .more else .ok) catch error.OperationExecutionFailed;
        };
        unreachable;
    }
};
pub const BuildInput = struct {
    pub const Action = @import("../actions/specification/build_specification_support_repair_input.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const progress = try support.progress(&input.step.data);
        const source = try support.inputs(&input.step.data, progress);
        inline for (.{ Purpose.source, .principles }) |selected| if (support.purpose(progress) == selected) {
            const state = try read(selected, &input.step.data);
            const current = try support.collection(selected, progress);
            if (current != .rejected or current.rejected.candidate == null) return error.OperationExecutionFailed;
            return @import("model_request_workflow.zig").publishPacket(self.allocator, self.action.execute(selected, self.allocator, source, try spec.readContext(&input.step.data), current.rejected.candidate.?, state.authorization) catch return error.OperationExecutionFailed);
        };
        unreachable;
    }
};
pub const Parse = struct {
    pub const Action = @import("../actions/specification/parse_specification_support_repair.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const payload = owned.payload(values.read(&input.step.data, schema, owned.Value) catch return error.OperationExecutionFailed);
        inline for (.{ Purpose.source, .principles }) |selected| if (payload.* == (if (selected == .source) .support_repair else .principle_support_repair)) {
            const state = try read(selected, &input.step.data);
            const packet = values.read(&input.step.data, @import("model_request_workflow.zig").packet_schema, @import("../domain/model_input_packet.zig").Packet) catch return error.OperationExecutionFailed;
            const handoff = try @import("model_candidate_handoff.zig").read(&input.step.data);
            const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
            errdefer owned.destroy(owner);
            retain(selected, owner, .{ .authorization = state.authorization, .response = .{ .value = self.action.execute(selected, owner.arena.allocator(), state.authorization, packet, handoff.body) catch return error.OperationExecutionFailed, .origin = handoff.origin } });
            var delta: @import("../domain/pipeline.zig").NodeDelta = .{};
            delta.data_replacements[@intFromEnum(schema.key)] = values.adopt(self.allocator, schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch return error.OperationExecutionFailed;
            return .{ .outcome = .ok, .delta = delta };
        };
        return error.OperationExecutionFailed;
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
        const progress = try support.progress(&input.step.data);
        const source = try support.inputs(&input.step.data, progress);
        inline for (.{ Purpose.source, .principles }) |selected| if (support.purpose(progress) == selected) {
            const current = try support.collection(selected, progress);
            if (current != .rejected or current.rejected.candidate == null) return error.OperationExecutionFailed;
            const state = try read(selected, &input.step.data);
            const context_value = try spec.readContext(&input.step.data);
            const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
            const result = self.action.execute(selected, owner.arena.allocator(), source, context_value, current.rejected.candidate.?, state) catch {
                owned.destroy(owner);
                return error.OperationExecutionFailed;
            };
            var candidate = try support.publish(selected, self.allocator, owner, progress, result);
            for (Action.contract.invalidates) |key| candidate.delta.data_invalidations.insert(key);
            return candidate;
        };
        unreachable;
    }
};
