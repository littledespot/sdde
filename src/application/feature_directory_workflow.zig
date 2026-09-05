const std = @import("std");
const feature = @import("../domain/feature_directory.zig");
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const publish = @import("workflow_candidate.zig").publish;

const maximum_bytes = @import("../domain/relative_directory_path.zig").max_bytes * 8 + 2048;
pub const normalized = values.schema(.normalized_feature_directory, feature.NormalizedCandidate, 1, maximum_bytes);
pub const selector = values.schema(.relative_feature_directory, feature.Selector, 1, maximum_bytes);
pub const directory = values.schema(.feature_directory, feature.Directory, 1, maximum_bytes);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ normalized, selector, directory };

pub const Normalize = struct {
    pub const Action = @import("../actions/specify/normalize_feature_directory.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = values.read(&input.step.data, @import("reference_workflow_values.zig").invocation, @import("../domain/specify_invocation.zig").Invocation) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), source.*) catch return error.OperationExecutionFailed;
        return publish(self.allocator, normalized, feature.NormalizedCandidate, result);
    }
};

pub const Validate = struct {
    pub const Action = @import("../actions/specify/validate_feature_directory.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const candidate = values.read(&input.step.data, normalized, feature.NormalizedCandidate) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), candidate.*) catch return error.OperationExecutionFailed;
        return publish(self.allocator, selector, feature.Selector, result);
    }
};

pub const Inspect = struct {
    pub const Action = @import("../actions/specify/inspect_feature_directory.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const candidate = values.read(&input.step.data, selector, feature.Selector) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), candidate.*) catch return error.OperationExecutionFailed;
        return publish(self.allocator, directory, feature.Directory, result);
    }
};
