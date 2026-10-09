//! Registered native bindings. Workflow YAML owns clarification publication order.
const std = @import("std");
const values = @import("pipeline_values.zig");
const owned = @import("specification_values.zig").storage;
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const publication = @import("specification_publication_workflow.zig");
const refresh = @import("clarification_refresh_workflow.zig");
const c = @import("../domain/clarification_inputs.zig");
const ci = @import("clarification_input_workflow.zig");
pub const state_schema = values.schema(.incomplete_specification_state, owned.Value, 1, null);
pub const rendered_schema = values.schema(.rendered_incomplete_specification, owned.Value, 1, null);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ state_schema, rendered_schema };

pub const Build = struct {
    pub const Action = @import("../actions/specification/build_incomplete_specification.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const view = &input.step.data;
        const prior = owned.read(view, publication.prior_schema, .prior_state) catch |operation_error| return operation_error;
        const snapshot = owned.read(view, publication.snapshot_schema, .reference_snapshot) catch |operation_error| return operation_error;
        const clarifications = values.read(view, refresh.state_schema, @import("../domain/clarification_refresh.zig").Result) catch |operation_error| return operation_error;
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        owner.payload = .{ .incomplete_state = self.action.execute(owner.arena.allocator(), prior, snapshot, clarifications.*) catch |cause| return cause };
        return owned.publish(self.allocator, state_schema, owner, .ok) catch |operation_error| operation_error;
    }
};
pub const Render = struct {
    pub const Action = @import("../actions/specification/render_incomplete_specification.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = owned.read(&input.step.data, state_schema, .incomplete_state) catch |operation_error| return operation_error;
        const clarifications = values.read(&input.step.data, refresh.state_schema, @import("../domain/clarification_refresh.zig").Result) catch |operation_error| return operation_error;
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        owner.payload = .{ .rendered = self.action.execute(owner.arena.allocator(), current, clarifications.*) catch |cause| return cause };
        return owned.publish(self.allocator, rendered_schema, owner, .ok) catch |operation_error| operation_error;
    }
};
pub const Prepare = struct {
    pub const Action = @import("../actions/specification/prepare_incomplete_specification_output.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const view = &input.step.data;
        const feature = values.read(view, @import("feature_logging_workflow.zig").directory, @import("../domain/feature_directory.zig").Directory) catch |operation_error| return operation_error;
        const paths = values.read(view, ci.paths_schema, @import("../domain/workflow_artifact_registry.zig").FeaturePaths) catch |operation_error| return operation_error;
        const captured = values.read(view, ci.captures_schema, c.Captures) catch |operation_error| return operation_error;
        const inputs = values.read(view, ci.inputs_schema, c.Inputs) catch |operation_error| return operation_error;
        const clarifications = values.read(view, refresh.state_schema, @import("../domain/clarification_refresh.zig").Result) catch |operation_error| return operation_error;
        const forms = values.read(view, refresh.views_schema, []const @import("../domain/clarification_views.zig").View) catch |operation_error| return operation_error;
        const prior = owned.read(view, publication.prior_schema, .prior_state) catch |operation_error| return operation_error;
        const current = owned.read(view, state_schema, .incomplete_state) catch |operation_error| return operation_error;
        const rendered = owned.read(view, rendered_schema, .rendered) catch |operation_error| return operation_error;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const prepared = self.action.execute(arena.allocator(), feature.*, paths.*, captured.*, inputs.*, clarifications.*, forms.*, prior, current, rendered) catch |cause| return cause;
        return @import("workflow_candidate.zig").publish(self.allocator, @import("workflow_output_binding.zig").prepared_schema, @import("../domain/workflow_output.zig").Prepared, prepared);
    }
};
