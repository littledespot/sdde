const std = @import("std");
const pipeline = @import("../domain/pipeline.zig");
const feature = @import("../domain/feature_directory.zig");
const reference = @import("../domain/reference_selector.zig");
const artifacts = @import("../domain/workflow_artifact_registry.zig");
const clarification = @import("../domain/clarification_inputs.zig");
const principles = @import("../domain/principle_registry.zig");
const invocation_types = @import("../domain/specify_invocation.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const values = @import("pipeline_values.zig");
const invocation_values = @import("specify_invocation_values.zig");
const feature_values = @import("feature_directory_workflow.zig");
const reference_values = @import("reference_workflow_values.zig");
const clarification_values = @import("clarification_input_workflow.zig");
const publication = @import("specification_publication_workflow.zig");
const principle_values = @import("principle_workflow.zig");
const owned = @import("specification_values.zig").storage;
const stage = @import("../actions/specify/prepare_inputs.zig");

// One binding runs the one stage action. YAML owns where it sits in the graph; the stage's internal
// steps are functions, not operations, and its intermediates never become pipeline data.
pub const PrepareInputs = struct {
    pub const Action = stage.Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const invocation = values.read(&input.step.data, invocation_values.invocation, invocation_types.Invocation) catch |operation_error| return operation_error;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        // The prior specification state is owned by this value, which keeps the invocation it was
        // read for alive; every other edge value is copied out of the scratch space.
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        var diagnostic: stage.Diagnostic = .{};
        const result = self.action.execute(scratch.allocator(), owner.arena.allocator(), input.step.runtime, &diagnostic, invocation.*) catch |operation_error| {
            // The stage-owned slot is read before the unchanged error propagates; the runner
            // records the step in the failed action's event (ADR 0031).
            if (input.step.stage_step) |slot| slot.name = if (diagnostic.step) |step| @tagName(step) else null;
            return operation_error;
        };
        owner.payload = .{ .prior_state = result.prior };
        const prior_principles = if (result.prior.specified()) |state_value| state_value.principle_registry else null;

        var delta: pipeline.NodeDelta = .{};
        errdefer for (delta.data_writes) |slot| if (slot) |written| values.destroy(written);
        delta.data_writes[@intFromEnum(feature_values.directory.key)] = values.create(self.allocator, feature_values.directory, feature.Directory, result.feature) catch |operation_error| return operation_error;
        delta.data_writes[@intFromEnum(feature_values.selector.key)] = values.create(self.allocator, feature_values.selector, feature.Selector, result.selector) catch |operation_error| return operation_error;
        delta.data_writes[@intFromEnum(reference_values.directory.key)] = values.create(self.allocator, reference_values.directory, reference.Directory, result.reference) catch |operation_error| return operation_error;
        delta.data_writes[@intFromEnum(clarification_values.paths_schema.key)] = values.create(self.allocator, clarification_values.paths_schema, artifacts.FeaturePaths, result.paths) catch |operation_error| return operation_error;
        delta.data_writes[@intFromEnum(clarification_values.captures_schema.key)] = values.create(self.allocator, clarification_values.captures_schema, clarification.Captures, result.captures) catch |operation_error| return operation_error;
        delta.data_writes[@intFromEnum(clarification_values.inputs_schema.key)] = values.create(self.allocator, clarification_values.inputs_schema, clarification.Inputs, result.inputs) catch |operation_error| return operation_error;
        delta.data_writes[@intFromEnum(principle_values.prior_schema.key)] = values.create(self.allocator, principle_values.prior_schema, ?principles.Registry, prior_principles) catch |operation_error| return operation_error;
        // Adopting the owner is the last step that can fail; after it no error path remains.
        const adopted = owned.publish(self.allocator, publication.prior_schema, owner, .ok) catch |operation_error| return operation_error;
        delta.data_writes[@intFromEnum(publication.prior_schema.key)] = adopted.delta.data_writes[@intFromEnum(publication.prior_schema.key)];
        return .{ .outcome = .ok, .delta = delta };
    }
};
