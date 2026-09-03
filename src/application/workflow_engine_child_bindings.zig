const bootstrap_error = @import("../domain/bootstrap_error.zig");
const execution = @import("../domain/workflow_execution.zig");
const workflow = @import("../domain/workflow.zig");
const compilation = @import("../domain/workflow_compilation.zig");

pub const SelectionStepOutcome = enum { ok, invocation_invalid, failed, cancelled };

pub const PreparationOutcome = union(enum) {
    ok,
    failed: bootstrap_error.PublicError,
    cancelled,
};

pub const ChildBindings = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        validate_implementation_registry: *const fn (*anyopaque) SelectionStepOutcome,
        parse_invocation: *const fn (*anyopaque) SelectionStepOutcome,
        select_workflow: *const fn (*anyopaque) SelectionStepOutcome,
        prepare_workflow: *const fn (*anyopaque) PreparationOutcome,
        selected_graph: *const fn (*const anyopaque) *const compilation.CompiledWorkflow,
        invoke_invocation: *const fn (*anyopaque) execution.Applied,
        invoke_node: *const fn (*anyopaque, workflow.WorkflowNodeId) execution.Applied,
    };

    pub fn invokeValidateImplementationRegistry(self: ChildBindings) SelectionStepOutcome {
        return self.vtable.validate_implementation_registry(self.context);
    }
    pub fn invokeParseInvocation(self: ChildBindings) SelectionStepOutcome {
        return self.vtable.parse_invocation(self.context);
    }
    pub fn invokeSelectWorkflow(self: ChildBindings) SelectionStepOutcome {
        return self.vtable.select_workflow(self.context);
    }
    pub fn invokePrepareWorkflow(self: ChildBindings) PreparationOutcome {
        return self.vtable.prepare_workflow(self.context);
    }
    pub fn selectedGraph(self: ChildBindings) *const compilation.CompiledWorkflow {
        return self.vtable.selected_graph(self.context);
    }
    pub fn invokeInvocation(self: ChildBindings) execution.Applied {
        return self.vtable.invoke_invocation(self.context);
    }
    pub fn invokeNode(self: ChildBindings, id: workflow.WorkflowNodeId) execution.Applied {
        return self.vtable.invoke_node(self.context, id);
    }
};
