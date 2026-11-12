const std = @import("std");
const feature = @import("../domain/feature_directory.zig");
const reference = @import("../domain/reference_selector.zig");
const evidence = @import("../domain/reference_evidence.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const values = @import("pipeline_values.zig");
const feature_values = @import("feature_directory_workflow.zig");
const reference_values = @import("reference_workflow_values.zig");
const evidence_values = @import("reference_evidence_workflow.zig");
const publish = @import("workflow_candidate.zig").publish;
const stage = @import("../actions/reference/prepare_reference_evidence.zig");

// One binding runs the one stage action. YAML owns where it sits in the graph; the stage's internal
// steps are functions, not operations, and its intermediates never become pipeline data.
pub const PrepareReferenceEvidence = struct {
    pub const Action = stage.Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const directory = values.read(&input.step.data, reference_values.directory, reference.Directory) catch |operation_error| return operation_error;
        const selected = values.read(&input.step.data, feature_values.directory, feature.Directory) catch |operation_error| return operation_error;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        var diagnostic: stage.Diagnostic = .{};
        const result = self.action.execute(scratch.allocator(), input.step.runtime, &diagnostic, directory.*, selected.selector.feature_id) catch |operation_error| {
            // The stage-owned slot is read before the unchanged error propagates; the runner
            // records the step in the failed action's event (ADR 0031).
            if (input.step.stage_step) |slot| slot.name = if (diagnostic.step) |step| @tagName(step) else null;
            return operation_error;
        };
        return publish(self.allocator, evidence_values.inputs_schema, evidence.Inputs, result);
    }
};
