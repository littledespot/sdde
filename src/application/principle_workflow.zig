//! One registered action per binding. Workflow definitions own capture sequencing.
const std = @import("std");
const registry = @import("../domain/principle_registry.zig");
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const publish = @import("workflow_candidate.zig").publish;
pub const registry_schema = values.schema(.principle_registry, registry.Registry, 1, values.max_value_bytes);
pub const prior_schema = values.schema(.prior_principle_registry, ?registry.Registry, 1, values.max_value_bytes);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ registry_schema, prior_schema };
pub const CaptureRegistry = struct {
    pub const Action = @import("../actions/principle/capture_principle_registry.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const prior: ?registry.Registry = if (input.step.data.contains(prior_schema.key)) (values.read(&input.step.data, prior_schema, ?registry.Registry) catch |operation_error| return operation_error).* else null;
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        return publish(self.allocator, registry_schema, registry.Registry, self.action.execute(scratch.allocator(), prior) catch |operation_error| return operation_error);
    }
};
