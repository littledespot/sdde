const execution = @import("../domain/workflow_execution.zig");
const workflow = @import("../domain/workflow.zig");

pub const ChildBindings = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        invoke_invocation: *const fn (*anyopaque) execution.Applied,
        invoke_step: *const fn (*anyopaque, workflow.WorkflowStepId) execution.Applied,
    };

    pub fn invokeInvocation(self: ChildBindings) execution.Applied {
        return self.vtable.invoke_invocation(self.context);
    }

    pub fn invokeStep(self: ChildBindings, id: workflow.WorkflowStepId) execution.Applied {
        return self.vtable.invoke_step(self.context, id);
    }
};
