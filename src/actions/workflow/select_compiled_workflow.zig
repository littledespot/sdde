const execution = @import("../../domain/workflow_execution.zig");
const pipeline = @import("../../domain/pipeline.zig");
const registry = @import("../../domain/workflow_registry.zig");

pub const Action = struct {
    registry: *const registry.ValidatedWorkflowDefinitionRegistry,

    pub const contract: pipeline.NodeContract = .{
        .id = "select-compiled-workflow@1",
        .kind = .action,
        .requires = &.{ .workflow_definition_registry, .workflow_invocation },
        .produces = &.{.selected_compiled_workflow},
        .side_effect = .none,
    };

    pub fn execute(self: Action, invocation: execution.Invocation) execution.InvocationError!execution.SelectedWorkflow {
        return .{
            .invocation = invocation,
            .graph = self.registry.resolve(invocation.workflow_id) orelse return error.UnknownWorkflowId,
        };
    }
};
