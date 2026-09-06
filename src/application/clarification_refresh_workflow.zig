const std = @import("std");
const c = @import("../domain/clarification_inputs.zig");
const refresh = @import("../domain/clarification_refresh.zig");
const views = @import("../domain/clarification_views.zig");
const values = @import("pipeline_values.zig");
const inputs = @import("clarification_input_workflow.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const publish = @import("workflow_candidate.zig").publish;
pub const needs_schema = values.schema(.clarification_needs, refresh.Needs, 1, c.max_state_bytes);
pub const state_schema = values.schema(.refreshed_clarification_state, c.ValidatedState, 1, c.max_state_bytes * 4);
pub const views_schema = values.schema(.clarification_views, []const views.View, 1, c.max_forms * c.max_form_bytes * 4);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ needs_schema, state_schema, views_schema };

pub const BuildSpecificationNeed = struct {
    pub const Action = @import("../actions/clarification/build_specification_clarification_need.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const checked = @import("specification_values.zig").storage.read(&input.step.data, @import("specification_workflow.zig").checked_schema, .checked) catch return error.OperationExecutionFailed;
        const feature = values.read(&input.step.data, @import("feature_directory_workflow.zig").selector, @import("../domain/feature_directory.zig").Selector) catch return error.OperationExecutionFailed;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const result = self.action.execute(arena.allocator(), feature.feature_id, try @import("specification_workflow.zig").readContext(&input.step.data), checked) catch return error.OperationExecutionFailed;
        return publish(self.allocator, needs_schema, refresh.Needs, result);
    }
};
pub const Refresh = struct {
    pub const Action = @import("../actions/clarification/refresh_clarifications.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .blocked, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const captured = values.read(&input.step.data, inputs.inputs_schema, c.Inputs) catch return error.OperationExecutionFailed;
        const needs = values.read(&input.step.data, needs_schema, refresh.Needs) catch return error.OperationExecutionFailed;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const result = self.action.execute(arena.allocator(), captured.*, needs.*) catch |err| switch (err) {
            error.AuthenticationRequired, error.ProtectedClarification, error.ClarificationLimitExceeded => return .{ .outcome = .blocked, .delta = .{} },
            else => return error.OperationExecutionFailed,
        };
        return publish(self.allocator, state_schema, c.ValidatedState, result);
    }
};
pub const Render = struct {
    pub const Action = @import("../actions/clarification/render_clarification_forms.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const captured = values.read(&input.step.data, inputs.inputs_schema, c.Inputs) catch return error.OperationExecutionFailed;
        const state = values.read(&input.step.data, state_schema, c.ValidatedState) catch return error.OperationExecutionFailed;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const result = self.action.execute(arena.allocator(), state.*, captured.*) catch return error.OperationExecutionFailed;
        return publish(self.allocator, views_schema, []const views.View, result);
    }
};
