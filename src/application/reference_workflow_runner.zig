const std = @import("std");
const reference = @import("../domain/reference_selector.zig");
const invocation_types = @import("../domain/specify_invocation.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const values = @import("pipeline_values.zig");
const schemas = @import("reference_workflow_values.zig");
const publish = @import("workflow_candidate.zig").publish;
const invocation_values = @import("specify_invocation_values.zig");

pub const NormalizeSelector = struct {
    pub const Action = @import("../actions/reference/normalize_reference_selector.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const invocation = values.read(&input.step.data, invocation_values.invocation, invocation_types.Invocation) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), invocation.*) catch return error.OperationExecutionFailed;
        return publish(self.allocator, schemas.normalized, reference.NormalizedCandidate, result);
    }
};

pub const ValidateSelector = struct {
    pub const Action = @import("../actions/reference/validate_reference_selector.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const candidate = values.read(&input.step.data, schemas.normalized, reference.NormalizedCandidate) catch return error.OperationExecutionFailed;
        const result = self.action.execute(candidate.*) catch return error.OperationExecutionFailed;
        return publish(self.allocator, schemas.selector, reference.RelativeSelector, result);
    }
};

pub const InspectDirectory = struct {
    pub const Action = @import("../actions/reference/inspect_reference_directory.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const selector = values.read(&input.step.data, schemas.selector, reference.RelativeSelector) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), selector.*) catch return error.OperationExecutionFailed;
        return publish(self.allocator, schemas.directory, reference.Directory, result);
    }
};
