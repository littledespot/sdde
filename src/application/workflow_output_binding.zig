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
pub const Publish = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .preserve = .{ .kind = .clarification, .subject = .prepared_workflow_output, .evidence = .prepared_workflow_output, .result = .published_workflow_output } };
    pub const Action = @import("../actions/workflow/publish_workflow_output.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .needs_user, .cancelled, .failed };
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
            .cancelled => .cancelled,
        };
        self.action.execute(self.allocator, prepared.*) catch |operation_error| return operation_error;
        return candidate;
    }
};
