//! One registered action per binding. Workflow definitions own capture sequencing.
const std = @import("std");
const registry = @import("../domain/principle_registry.zig");
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const publish = @import("workflow_candidate.zig").publish;
pub const raw_schema = values.schema(.raw_principle_inventory, registry.Raw, 1, 16 * 1024 * 1024);
pub const inventory_schema = values.schema(.principle_inventory, registry.Inventory, 1, 16 * 1024 * 1024);
pub const capture_schema = values.schema(.captured_principles, registry.Captured, 1, 32 * 1024 * 1024);
pub const registry_schema = values.schema(.principle_registry, registry.Registry, 1, 64 * 1024 * 1024);
pub const prior_schema = values.schema(.prior_principle_registry, ?registry.Registry, 1, 64 * 1024 * 1024);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ raw_schema, inventory_schema, capture_schema, registry_schema, prior_schema };
pub const CaptureRegistry = struct {
    pub const Action = @import("../actions/principle/capture_principle_registry.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const prior: ?registry.Registry = if (input.step.data.contains(prior_schema.key)) (values.read(&input.step.data, prior_schema, ?registry.Registry) catch return error.OperationExecutionFailed).* else null;
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        return publish(self.allocator, registry_schema, registry.Registry, self.action.execute(scratch.allocator(), prior) catch return error.OperationExecutionFailed);
    }
};
pub const Inventory = struct {
    pub const Action = @import("../actions/principle/inventory_principle_sources.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), _: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        return publish(self.allocator, raw_schema, registry.Raw, self.action.execute(scratch.allocator()) catch return error.OperationExecutionFailed);
    }
};
pub const ValidateInventory = struct {
    pub const Action = @import("../actions/principle/validate_principle_inventory.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const raw = values.read(&input.step.data, raw_schema, registry.Raw) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        return publish(self.allocator, inventory_schema, registry.Inventory, self.action.execute(scratch.allocator(), raw.*) catch return error.OperationExecutionFailed);
    }
};
pub const Capture = struct {
    pub const Action = @import("../actions/principle/capture_principle_sources.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const inventory = values.read(&input.step.data, inventory_schema, registry.Inventory) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        return publish(self.allocator, capture_schema, registry.Captured, self.action.execute(scratch.allocator(), inventory.*) catch return error.OperationExecutionFailed);
    }
};
pub const Build = struct {
    pub const Action = @import("../actions/principle/build_principle_registry.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const captured = values.read(&input.step.data, capture_schema, registry.Captured) catch return error.OperationExecutionFailed;
        const prior: ?registry.Registry = if (input.step.data.contains(prior_schema.key)) (values.read(&input.step.data, prior_schema, ?registry.Registry) catch return error.OperationExecutionFailed).* else null;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        return publish(self.allocator, registry_schema, registry.Registry, self.action.execute(scratch.allocator(), captured.*, prior) catch return error.OperationExecutionFailed);
    }
};
