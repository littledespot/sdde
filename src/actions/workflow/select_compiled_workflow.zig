const execution = @import("../../domain/workflow_execution.zig");
const workflow = @import("../../domain/workflow_registry.zig");

pub const Action = struct {
    registry: *const workflow.ValidatedWorkflowDefinitionRegistry,

    pub fn execute(self: Action, invocation: execution.Invocation) execution.InvocationError!execution.SelectedWorkflow {
        return .{
            .invocation = invocation,
            .graph = self.registry.resolve(invocation.workflow_id) orelse return error.UnknownWorkflowId,
        };
    }
};
