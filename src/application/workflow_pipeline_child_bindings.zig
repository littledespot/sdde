const execution = @import("../domain/workflow_execution.zig");
const workflow = @import("../domain/workflow.zig");

pub const ChildBindings = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        invoke_invocation: *const fn (*anyopaque) execution.Applied,
        invoke_node: *const fn (*anyopaque, workflow.WorkflowNodeId) execution.Applied,
    };

    pub fn invokeInvocation(self: ChildBindings) execution.Applied {
        return self.vtable.invoke_invocation(self.context);
    }

    pub fn invokeNode(self: ChildBindings, id: workflow.WorkflowNodeId) execution.Applied {
        return self.vtable.invoke_node(self.context, id);
    }
};
