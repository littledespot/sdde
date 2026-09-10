//! Registered bindings. All publication sequencing remains in workflow YAML.
const std = @import("std");
const values = @import("pipeline_values.zig");
const owned = @import("specification_values.zig").storage;
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const state = @import("../domain/specification_state.zig");
const c = @import("../domain/clarification_inputs.zig");
const ci = @import("clarification_input_workflow.zig");
const refresh = @import("clarification_refresh_workflow.zig");
const rendering = @import("specification_rendering_workflow.zig");
const authority = @import("required_authority_values.zig");
pub const raw_schema = values.schema(.raw_workflow_state, ?[]const u8, 1, state.max_bytes + 1024);
pub const prior_schema = values.schema(.prior_specification_state, owned.Value, 1, null);
pub const state_schema = values.schema(.specification_publication_state, owned.Value, 1, null);
pub const reference_schema = values.schema(.rendered_reference_context, owned.Value, 1, null);
pub const snapshot_schema = values.schema(.reference_snapshot, owned.Value, 1, null);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ raw_schema, prior_schema, state_schema, reference_schema, snapshot_schema };

pub const Capture = struct {
    pub const Action = @import("../actions/workflow/capture_workflow_state.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const feature = try readFeature(&input.step.data);
        const paths = values.read(&input.step.data, ci.paths_schema, @import("../domain/workflow_artifact_registry.zig").FeaturePaths) catch return error.OperationExecutionFailed;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const bytes = self.action.execute(arena.allocator(), feature, paths.*) catch return error.OperationExecutionFailed;
        return @import("workflow_candidate.zig").publish(self.allocator, raw_schema, ?[]const u8, bytes);
    }
};
pub const Parse = struct {
    pub const Action = @import("../actions/specification/parse_specification_state.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const bytes = values.read(&input.step.data, raw_schema, ?[]const u8) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .prior_state = self.action.execute(owner.arena.allocator(), (try readFeature(&input.step.data)).selector.feature_id, bytes.*) catch return error.OperationExecutionFailed };
        return owned.publish(self.allocator, prior_schema, owner, .ok) catch error.OperationExecutionFailed;
    }
};
pub const ResolvedNeeds = struct {
    pub const Action = @import("../actions/clarification/build_resolved_clarification_needs.zig").Action;
    pub const gates = [_][]const u8{"required-authority@1"};
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const result = authority.read(&input.step.data, @import("required_authority_workflow.zig").result_schema, .result) catch return error.OperationExecutionFailed;
        const needs = self.action.execute(result) catch return error.OperationExecutionFailed;
        return @import("workflow_candidate.zig").publish(self.allocator, refresh.needs_schema, @import("../domain/clarification_refresh.zig").Needs, needs);
    }
};
pub const Build = struct {
    pub const Action = @import("../actions/specification/build_specification_state.zig").Action;
    pub const gates = [_][]const u8{"required-authority@1"};
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const view = &input.step.data;
        const prior = owned.read(view, prior_schema, .prior_state) catch return error.OperationExecutionFailed;
        const snapshot = owned.read(view, snapshot_schema, .reference_snapshot) catch return error.OperationExecutionFailed;
        const content = authority.read(view, @import("required_authority_workflow.zig").content_schema, .content) catch return error.OperationExecutionFailed;
        const ledger = values.read(view, @import("specification_workflow.zig").ids_schema, @import("../domain/specification_identity.zig").Ledger) catch return error.OperationExecutionFailed;
        const coverage = owned.read(view, @import("specification_workflow.zig").coverage_schema, .coverage) catch return error.OperationExecutionFailed;
        const inputs = authority.read(view, @import("required_authority_workflow.zig").inputs_schema, .inputs) catch return error.OperationExecutionFailed;
        const observations = authority.read(view, @import("required_authority_workflow.zig").observations_schema, .observations) catch return error.OperationExecutionFailed;
        const result = authority.read(view, @import("required_authority_workflow.zig").result_schema, .result) catch return error.OperationExecutionFailed;
        const clarifications = values.read(view, refresh.state_schema, @import("../domain/clarification_refresh.zig").Result) catch return error.OperationExecutionFailed;
        const valid = values.read(view, rendering.validated_schema, bool) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .publication_state = self.action.execute(owner.arena.allocator(), prior, snapshot, try @import("specification_workflow.zig").readContext(view), content, ledger.*, coverage, inputs, observations, result, clarifications.*, valid.*) catch return error.OperationExecutionFailed };
        return owned.publish(self.allocator, state_schema, owner, .ok) catch error.OperationExecutionFailed;
    }
};
pub const BuildSnapshot = struct {
    pub const Action = @import("../actions/reference/build_reference_snapshot.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const view = &input.step.data;
        const directory = values.read(view, @import("reference_workflow_values.zig").directory, @import("../domain/reference_selector.zig").Directory) catch return error.OperationExecutionFailed;
        const inputs = values.read(view, @import("reference_evidence_workflow.zig").inputs_schema, @import("../domain/reference_evidence.zig").Inputs) catch return error.OperationExecutionFailed;
        const extracted = @import("reference_extraction_workflow.zig").read(view, @import("reference_extraction_workflow.zig").accounted_schema, .accounted) catch return error.OperationExecutionFailed;
        const reconciled = @import("reference_extraction_workflow.zig").read(view, @import("reference_reconciliation_workflow.zig").accounted_schema, .reconciliation_accounted) catch return error.OperationExecutionFailed;
        const registry = values.read(view, @import("passive_literal_workflow.zig").registry_schema, @import("../domain/passive_literals.zig").Registry) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .reference_snapshot = self.action.execute(.{ .bytes = directory.project_relative_path }, inputs.*, extracted.payload().accounted, reconciled.payload().reconciliation_accounted, registry.*) catch return error.OperationExecutionFailed };
        return owned.publish(self.allocator, snapshot_schema, owner, .ok) catch error.OperationExecutionFailed;
    }
};
pub const RenderReference = struct {
    pub const Action = @import("../actions/reference/render_reference_context.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = owned.read(&input.step.data, snapshot_schema, .reference_snapshot) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .reference_context = self.action.execute(owner.arena.allocator(), current) catch return error.OperationExecutionFailed };
        return owned.publish(self.allocator, reference_schema, owner, .ok) catch error.OperationExecutionFailed;
    }
};
pub const Prepare = struct {
    pub const Action = @import("../actions/specification/prepare_specification_output.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const view = &input.step.data;
        const paths = values.read(view, ci.paths_schema, @import("../domain/workflow_artifact_registry.zig").FeaturePaths) catch return error.OperationExecutionFailed;
        const captured = values.read(view, ci.captures_schema, c.Captures) catch return error.OperationExecutionFailed;
        const inputs = values.read(view, ci.inputs_schema, c.Inputs) catch return error.OperationExecutionFailed;
        const clarifications = values.read(view, refresh.state_schema, @import("../domain/clarification_refresh.zig").Result) catch return error.OperationExecutionFailed;
        const forms = values.read(view, refresh.views_schema, []const @import("../domain/clarification_views.zig").View) catch return error.OperationExecutionFailed;
        const prior = owned.read(view, prior_schema, .prior_state) catch return error.OperationExecutionFailed;
        const current = owned.read(view, state_schema, .publication_state) catch return error.OperationExecutionFailed;
        const spec = owned.read(view, rendering.rendered_schema, .rendered) catch return error.OperationExecutionFailed;
        const valid = values.read(view, rendering.validated_schema, bool) catch return error.OperationExecutionFailed;
        const reference = owned.read(view, reference_schema, .reference_context) catch return error.OperationExecutionFailed;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const prepared = self.action.execute(arena.allocator(), try readFeature(view), paths.*, captured.*, inputs.*, clarifications.*, forms.*, prior, current, try @import("specification_workflow.zig").readContext(view), spec, valid.*, reference) catch return error.OperationExecutionFailed;
        return @import("workflow_candidate.zig").publish(self.allocator, @import("workflow_output_binding.zig").prepared_schema, @import("../domain/workflow_output.zig").Prepared, prepared);
    }
};
fn readFeature(view: *const @import("../domain/pipeline_data.zig").View) operations.Error!@import("../domain/feature_directory.zig").Directory {
    return (values.read(view, @import("feature_directory_workflow.zig").directory, @import("../domain/feature_directory.zig").Directory) catch return error.OperationExecutionFailed).*;
}
