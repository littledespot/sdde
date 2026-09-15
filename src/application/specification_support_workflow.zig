const std = @import("std");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const pipeline = @import("../domain/pipeline.zig");
const owned = @import("required_authority_values.zig");
const authority = @import("required_authority_workflow.zig");
const spec = @import("specification_workflow.zig");
const requests = @import("model_request_workflow.zig");
const values = @import("pipeline_values.zig");
pub const schema = values.schema(.specification_support_review, owned.Value, 1, null).captured();
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{schema};
pub const BuildInput = struct {
    pub const Action = @import("../actions/specification/build_specification_support_input.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = owned.read(&input.step.data, authority.inputs_schema, .inputs) catch return error.OperationExecutionFailed;
        const packet = self.action.execute(self.allocator, source, try spec.readContext(&input.step.data)) catch return error.OperationExecutionFailed;
        return requests.publishPacket(self.allocator, packet);
    }
};
pub const Collect = struct {
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .invalid, .failed };
    pub const Action = @import("../actions/specification/collect_specification_support.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = owned.read(&input.step.data, authority.inputs_schema, .inputs) catch return error.OperationExecutionFailed;
        const packet = values.read(&input.step.data, requests.packet_schema, @import("../domain/model_input_packet.zig").Packet) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        const handoff = @import("model_candidate_handoff.zig").read(&input.step.data) catch {
            owned.destroy(owner);
            return error.OperationExecutionFailed;
        };
        const source_context = spec.readContext(&input.step.data) catch {
            owned.destroy(owner);
            return error.OperationExecutionFailed;
        };
        const result = self.action.execute(owner.arena.allocator(), source, source_context, packet, handoff.body, handoff.origin) catch {
            owned.destroy(owner);
            return error.OperationExecutionFailed;
        };
        return publish(self.allocator, owner, result, false);
    }
};

/// Takes the owner on every path; collection and repair retain the same candidate shape.
pub fn publish(allocator: std.mem.Allocator, owner: *owned.Owner, result: @import("../domain/specification_support.zig").Collection, replace: bool) operations.Error!execution.Candidate {
    errdefer owned.destroy(owner);
    owner.payload = .{ .support = result };
    const review_value = values.adopt(allocator, schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch return error.OperationExecutionFailed;
    var delta: pipeline.NodeDelta = .{};
    if (replace) delta.data_replacements[@intFromEnum(schema.key)] = review_value else delta.data_writes[@intFromEnum(schema.key)] = review_value;
    return .{ .outcome = if (result == .accepted) .ok else .invalid, .delta = delta };
}

/// Only admission of a completed review advances authority inputs. Repair keeps
/// the source projection unchanged, preserving its generation and lineage.
pub const Apply = struct {
    pub const Action = @import("../actions/specification/apply_specification_support.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const reviewed = owned.read(&input.step.data, schema, .support) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .inputs = self.action.execute(reviewed) catch return error.OperationExecutionFailed };
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(authority.inputs_schema.key)] = values.adopt(self.allocator, authority.inputs_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch return error.OperationExecutionFailed;
        return .{ .outcome = .ok, .delta = delta };
    }
};
