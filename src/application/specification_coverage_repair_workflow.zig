const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const pipeline = @import("../domain/pipeline.zig");
const repair = @import("../domain/specification_coverage_repair.zig");
const owned = @import("specification_values.zig").storage;
const spec = @import("specification_workflow.zig");
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
pub const schema = values.schema(.specification_coverage_repair, owned.Value, 1, null).captured();
pub const schemas = [_]data.Schema{schema};
pub const Authorize = struct {
    pub const Action = @import("../actions/specification/authorize_specification_coverage_repair.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .blocked, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const rejection = owned.read(&input.step.data, spec.coverage_schema, .coverage_rejected) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        const decision = self.action.execute(owner.arena.allocator(), try spec.readSession(&input.step.data), try spec.readContext(&input.step.data), try content(&input.step.data), rejection) catch return error.OperationExecutionFailed;
        owner.payload = .{ .coverage_repair = decision };
        return owned.publish(self.allocator, schema, owner, if (decision == .authorized) .ok else .blocked) catch error.OperationExecutionFailed;
    }
};
pub const Merge = struct {
    pub const Action = @import("../actions/specification/merge_specification_coverage_repair.zig").Action;
    pub const parameters = [_]@import("../domain/workflow_operation.zig").ParameterDescriptor{.{ .id = "retry-limit", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 0, .integer_max = std.math.maxInt(u32) }};
    pub const retry_limit: @import("../domain/workflow_operation.zig").RetryLimitDescriptor = .{ .maximum = std.math.maxInt(u32) };
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = owned.read(&input.step.data, schema, .coverage_repair) catch return error.OperationExecutionFailed;
        if (state != .authorized) return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .session = self.action.execute(owner.arena.allocator(), try spec.readSession(&input.step.data), try spec.readContext(&input.step.data), try content(&input.step.data), state.authorized) catch return error.OperationExecutionFailed };
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(spec.session_schema.key)] = values.adopt(self.allocator, spec.session_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch return error.OperationExecutionFailed;
        for (Action.contract.invalidates) |key| delta.data_invalidations.insert(key);
        return .{ .outcome = .ok, .delta = delta };
    }
};
fn content(view: *const data.View) operations.Error!@import("../domain/specification.zig").IdentifiedContent {
    return @import("required_authority_values.zig").read(view, @import("required_authority_workflow.zig").content_schema, .content) catch error.OperationExecutionFailed;
}
