const std = @import("std");
const output = @import("../domain/workflow_output.zig");
const values = @import("pipeline_values.zig");
const c = @import("../domain/clarification_inputs.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const publish = @import("workflow_candidate.zig").publish;
pub const prepared_schema = values.schema(.prepared_workflow_output, output.Prepared, 1, c.max_state_bytes * 8);
pub const published_schema = values.schema(.published_workflow_output, bool, 1, @sizeOf(bool));
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ prepared_schema, published_schema };
pub const PrepareClarifications = struct {
    pub const Action = @import("../actions/clarification/prepare_clarification_output.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const read = @import("clarification_input_workflow.zig");
        const refresh = @import("clarification_refresh_workflow.zig");
        const feature = values.read(&input.step.data, @import("feature_logging_workflow.zig").directory, @import("../domain/feature_directory.zig").Directory) catch |operation_error| return operation_error;
        const paths = values.read(&input.step.data, read.paths_schema, @import("../domain/workflow_artifact_registry.zig").FeaturePaths) catch |operation_error| return operation_error;
        const prior = values.read(&input.step.data, read.captures_schema, c.Captures) catch |operation_error| return operation_error;
        const inputs = values.read(&input.step.data, read.inputs_schema, c.Inputs) catch |operation_error| return operation_error;
        const state = values.read(&input.step.data, refresh.state_schema, @import("../domain/clarification_refresh.zig").Result) catch |operation_error| return operation_error;
        const views = values.read(&input.step.data, refresh.views_schema, []const @import("../domain/clarification_views.zig").View) catch |operation_error| return operation_error;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const prepared = self.action.execute(arena.allocator(), feature.*, paths.*, prior.*, inputs.*, state.*, views.*) catch |operation_error| return operation_error;
        return publish(self.allocator, prepared_schema, output.Prepared, prepared);
    }
};
pub const Publish = struct {
    pub const Action = @import("../actions/workflow/publish_workflow_output.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .needs_user, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const prepared = values.read(&input.step.data, prepared_schema, output.Prepared) catch |operation_error| return operation_error;
        var candidate = try publish(self.allocator, published_schema, bool, true);
        errdefer values.destroy(candidate.delta.data_writes[@intFromEnum(published_schema.key)].?);
        candidate.outcome = switch (prepared.terminal_outcome) {
            .ok => .ok,
            .needs_user => .needs_user,
        };
        self.action.execute(self.allocator, prepared.*) catch |operation_error| return operation_error;
        return candidate;
    }
};
