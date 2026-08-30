const execution = @import("../../domain/workflow_execution.zig");
const registry = @import("../../domain/workflow_registry.zig");

pub const Action = struct {
    registry: *const registry.ValidatedWorkflowDefinitionRegistry,

    pub fn execute(self: Action, invocation: execution.Invocation) execution.InvocationError!execution.SelectedWorkflow {
        return .{
            .invocation = invocation,
            .graph = self.registry.resolve(invocation.workflow_id) orelse return error.UnknownWorkflowId,
        };
    }
};
