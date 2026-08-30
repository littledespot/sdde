const execution = @import("../domain/workflow_execution.zig");
const workflow = @import("../domain/workflow.zig");
const compilation = @import("../domain/workflow_compilation.zig");
const bindings = @import("workflow_engine_child_bindings.zig");

pub fn run(graph: *const compilation.CompiledWorkflow, children: bindings.ChildBindings) execution.Outcome {
    const invocation = children.invokeInvocation();
    if (invocation.outcome != .ok) return invocation.outcome;

    var current = graph.authority.entry_node_id;
    var visited: usize = 0;
    while (visited < graph.authority.nodes.len) : (visited += 1) {
        const applied = children.invokeNode(current);
        const target = resolveTransition(graph.authority.transitions, current, applied.outcome) orelse {
            return if (applied.outcome == .ok) .failed else applied.outcome;
        };
        switch (target) {
            .terminal => |outcome| return outcome,
            .node => |next| current = next,
        }
    }
    return .failed;
}

fn resolveTransition(
    transitions: []const workflow.Transition,
    node_id: workflow.WorkflowNodeId,
    outcome: workflow.OutcomeTag,
) ?workflow.TransitionTarget {
    for (transitions) |transition| {
        if (@import("std").mem.eql(u8, transition.from.bytes, node_id.bytes) and transition.outcome == outcome) {
            return transition.target;
        }
    }
    return null;
}
