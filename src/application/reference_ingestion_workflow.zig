const std = @import("std");
const reference = @import("../domain/reference_ingestion.zig");
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const publish = @import("workflow_candidate.zig").publish;
const maximum = 64 * 1024 * 1024;
pub const raw_schema = values.schema(.raw_reference_inventory, reference.RawInventory, 1, maximum);
pub const inventory_schema = values.schema(.reference_inventory, reference.Inventory, 1, maximum);
pub const captured_schema = values.schema(.captured_reference_corpus, reference.CapturedCorpus, 1, maximum);
pub const decoded_schema = values.schema(.decoded_reference_corpus, reference.DecodedCorpus, 1, maximum);
pub const inputs_schema = values.schema(.reference_inputs, reference.Inputs, 1, maximum);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ raw_schema, inventory_schema, captured_schema, decoded_schema, inputs_schema };

pub const Inventory = struct {
    pub const Action = @import("../actions/reference/inventory_reference_sources.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const directory = values.read(&input.step.data, @import("reference_workflow_values.zig").directory, @import("../domain/reference_selector.zig").Directory) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), directory.*) catch return error.OperationExecutionFailed;
        return publish(self.allocator, raw_schema, reference.RawInventory, result);
    }
};
pub const ValidateInventory = struct {
    pub const Action = @import("../actions/reference/validate_reference_inventory.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const raw = values.read(&input.step.data, raw_schema, reference.RawInventory) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), raw.*) catch return error.OperationExecutionFailed;
        return publish(self.allocator, inventory_schema, reference.Inventory, result);
    }
};
pub const Capture = struct {
    pub const Action = @import("../actions/reference/capture_reference_sources.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const inventory = values.read(&input.step.data, inventory_schema, reference.Inventory) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), inventory.*) catch return error.OperationExecutionFailed;
        return publish(self.allocator, captured_schema, reference.CapturedCorpus, result);
    }
};
pub const Decode = struct {
    pub const Action = @import("../actions/reference/decode_reference_markdown.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const captured = values.read(&input.step.data, captured_schema, reference.CapturedCorpus) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), captured.*) catch return error.OperationExecutionFailed;
        return publish(self.allocator, decoded_schema, reference.DecodedCorpus, result);
    }
};
pub const ValidateAccounting = struct {
    pub const Action = @import("../actions/reference/validate_reference_accounting.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const decoded = values.read(&input.step.data, decoded_schema, reference.DecodedCorpus) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), decoded.*) catch return error.OperationExecutionFailed;
        return publish(self.allocator, inputs_schema, reference.Inputs, result);
    }
};
