const std = @import("std");
const clarification = @import("../domain/clarification_inputs.zig");
const artifacts = @import("../domain/workflow_artifact_registry.zig");
const feature = @import("../domain/feature_directory.zig");
const values = @import("pipeline_values.zig");
const feature_values = @import("feature_directory_workflow.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const publish = @import("workflow_candidate.zig").publish;

const maximum = clarification.max_state_bytes * 4;
pub const paths_schema = values.schema(.feature_artifact_paths, artifacts.FeaturePaths, 1, 128 * 1024);
pub const captures_schema = values.schema(.raw_clarification_inputs, clarification.Captures, 1, maximum);
pub const parsed_schema = values.schema(.parsed_clarification_state, clarification.ParsedState, 1, maximum);
pub const state_schema = values.schema(.validated_clarification_state, clarification.ValidatedState, 1, maximum);
pub const inputs_schema = values.schema(.clarification_inputs, clarification.Inputs, 1, maximum);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ paths_schema, captures_schema, parsed_schema, state_schema, inputs_schema };

pub const ResolvePaths = struct {
    pub const Action = @import("../actions/specify/resolve_feature_artifact_paths.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const selected = values.read(&input.step.data, feature_values.directory, feature.Directory) catch |operation_error| return operation_error;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const result = self.action.execute(arena.allocator(), selected.*) catch |operation_error| return operation_error;
        return publish(self.allocator, paths_schema, artifacts.FeaturePaths, result);
    }
};
pub const Capture = struct {
    pub const Action = @import("../actions/clarification/capture_clarification_inputs.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const selected = values.read(&input.step.data, feature_values.directory, feature.Directory) catch |operation_error| return operation_error;
        const paths = values.read(&input.step.data, paths_schema, artifacts.FeaturePaths) catch |operation_error| return operation_error;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const result = self.action.execute(arena.allocator(), selected.*, paths.*) catch |operation_error| return operation_error;
        return publish(self.allocator, captures_schema, clarification.Captures, result);
    }
};
pub const ParseState = struct {
    pub const Action = @import("../actions/clarification/parse_clarification_state.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const captures = values.read(&input.step.data, captures_schema, clarification.Captures) catch |operation_error| return operation_error;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const result = self.action.execute(arena.allocator(), captures.*) catch |operation_error| return operation_error;
        return publish(self.allocator, parsed_schema, clarification.ParsedState, result);
    }
};
pub const ValidateState = struct {
    pub const Action = @import("../actions/clarification/validate_clarification_state.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const parsed = values.read(&input.step.data, parsed_schema, clarification.ParsedState) catch |operation_error| return operation_error;
        const paths = values.read(&input.step.data, paths_schema, artifacts.FeaturePaths) catch |operation_error| return operation_error;
        const result = self.action.execute(parsed.*, paths.feature.feature_id) catch |operation_error| return operation_error;
        return publish(self.allocator, state_schema, clarification.ValidatedState, result);
    }
};
pub const ValidateForms = struct {
    pub const Action = @import("../actions/clarification/validate_clarification_forms.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = values.read(&input.step.data, state_schema, clarification.ValidatedState) catch |operation_error| return operation_error;
        const captures = values.read(&input.step.data, captures_schema, clarification.Captures) catch |operation_error| return operation_error;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const result = self.action.execute(arena.allocator(), state.*, captures.*) catch |operation_error| return operation_error;
        return publish(self.allocator, inputs_schema, clarification.Inputs, result);
    }
};
