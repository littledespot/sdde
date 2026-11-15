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
pub const prior_schema = values.schema(.prior_specification_state, owned.Value, 1, null);
pub const state_schema = values.schema(.specification_publication_state, owned.Value, 1, null);
pub const reference_schema = values.schema(.rendered_reference_context, owned.Value, 1, null);
pub const snapshot_schema = values.schema(.reference_snapshot, owned.Value, 1, null);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ prior_schema, state_schema, reference_schema, snapshot_schema };

pub const ResolvedNeeds = struct {
    pub const Action = @import("../actions/clarification/build_resolved_clarification_needs.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const sources = try values.read(&input.step.data, @import("reference_evidence_workflow.zig").inputs_schema, @import("../domain/reference_evidence.zig").Inputs);
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const needs = self.action.execute(arena.allocator(), sources.*) catch |operation_error| return operation_error;
        return @import("workflow_candidate.zig").publish(self.allocator, refresh.needs_schema, @import("../domain/clarification_refresh.zig").Needs, needs);
    }
};
pub const Build = struct {
    pub const Action = @import("../actions/specification/build_specification_state.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const view = &input.step.data;
        const prior = owned.read(view, prior_schema, .prior_state) catch |operation_error| return operation_error;
        const snapshot = owned.read(view, snapshot_schema, .reference_snapshot) catch |operation_error| return operation_error;
        const content = authority.read(view, @import("required_authority_workflow.zig").content_schema, .content) catch |operation_error| return operation_error;
        const ledger = values.read(view, @import("specification_workflow.zig").ids_schema, @import("../domain/specification_identity.zig").Ledger) catch |operation_error| return operation_error;
        const coverage = owned.read(view, @import("specification_workflow.zig").coverage_schema, .coverage) catch |operation_error| return operation_error;
        const brief = (try @import("specification_generation_facts.zig").read(view)).brief() orelse return error.SpecificationBriefMissing;
        const principles = values.read(view, @import("principle_workflow.zig").registry_schema, @import("../domain/principle_registry.zig").Registry) catch |operation_error| return operation_error;
        const clarifications = values.read(view, refresh.state_schema, @import("../domain/clarification_refresh.zig").Result) catch |operation_error| return operation_error;
        const valid = values.read(view, rendering.validated_schema, bool) catch |operation_error| return operation_error;
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        owner.payload = .{ .publication_state = self.action.execute(owner.arena.allocator(), prior, snapshot, try @import("specification_workflow.zig").readContext(view), brief, content, ledger.*, coverage, principles.*, clarifications.*, valid.*) catch |cause| return cause };
        return owned.publish(self.allocator, state_schema, owner, .ok) catch |operation_error| operation_error;
    }
};
pub const BuildSnapshot = struct {
    pub const Action = @import("../actions/reference/build_reference_snapshot.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const view = &input.step.data;
        const directory = values.read(view, @import("reference_workflow_values.zig").directory, @import("../domain/reference_selector.zig").Directory) catch |operation_error| return operation_error;
        const inputs = values.read(view, @import("reference_evidence_workflow.zig").inputs_schema, @import("../domain/reference_evidence.zig").Inputs) catch |operation_error| return operation_error;
        const extracted = @import("reference_extraction_workflow.zig").read(view, @import("reference_extraction_workflow.zig").accounted_schema, .accounted) catch |operation_error| return operation_error;
        const reconciled = @import("reference_extraction_workflow.zig").read(view, @import("reference_reconciliation_workflow.zig").accounted_schema, .reconciliation_accounted) catch |operation_error| return operation_error;
        const registry = values.read(view, @import("passive_literal_workflow.zig").registry_schema, @import("../domain/passive_literals.zig").Registry) catch |operation_error| return operation_error;
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        owner.payload = .{ .reference_snapshot = self.action.execute(owner.arena.allocator(), (input.step.authority orelse return error.ProjectAuthorityMissing).*, .{ .bytes = directory.project_relative_path }, inputs.*, extracted.payload().accounted, reconciled.payload().reconciliation_accounted, registry.*) catch |cause| return cause };
        return owned.publish(self.allocator, snapshot_schema, owner, .ok) catch |operation_error| operation_error;
    }
};
pub const RenderReference = struct {
    pub const Action = @import("../actions/reference/render_reference_context.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = owned.read(&input.step.data, state_schema, .publication_state) catch |operation_error| return operation_error;
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        owner.payload = .{ .reference_context = self.action.execute(owner.arena.allocator(), current) catch |operation_error| return operation_error };
        return owned.publish(self.allocator, reference_schema, owner, .ok) catch |operation_error| operation_error;
    }
};
pub const Prepare = struct {
    pub const Action = @import("../actions/specification/prepare_specification_output.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const view = &input.step.data;
        const paths = values.read(view, ci.paths_schema, @import("../domain/workflow_artifact_registry.zig").FeaturePaths) catch |operation_error| return operation_error;
        const captured = values.read(view, ci.captures_schema, c.Captures) catch |operation_error| return operation_error;
        const inputs = values.read(view, ci.inputs_schema, c.Inputs) catch |operation_error| return operation_error;
        const clarifications = values.read(view, refresh.state_schema, @import("../domain/clarification_refresh.zig").Result) catch |operation_error| return operation_error;
        const forms = values.read(view, refresh.views_schema, []const @import("../domain/clarification_views.zig").View) catch |operation_error| return operation_error;
        const prior = owned.read(view, prior_schema, .prior_state) catch |operation_error| return operation_error;
        const current = owned.read(view, state_schema, .publication_state) catch |operation_error| return operation_error;
        const spec = owned.read(view, rendering.rendered_schema, .rendered) catch |operation_error| return operation_error;
        const valid = values.read(view, rendering.validated_schema, bool) catch |operation_error| return operation_error;
        const reference = owned.read(view, reference_schema, .reference_context) catch |operation_error| return operation_error;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const current_feature = values.read(view, @import("feature_logging_workflow.zig").directory, @import("../domain/feature_directory.zig").Directory) catch |operation_error| return operation_error;
        const prepared = self.action.execute(arena.allocator(), current_feature.*, paths.*, captured.*, inputs.*, clarifications.*, forms.*, prior, current, try @import("specification_workflow.zig").readContext(view), spec, valid.*, reference) catch |cause| return cause;
        return @import("workflow_candidate.zig").publish(self.allocator, @import("workflow_output_binding.zig").prepared_schema, @import("../domain/workflow_output.zig").Prepared, prepared);
    }
};
