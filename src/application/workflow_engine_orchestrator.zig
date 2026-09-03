const run_outcome = @import("../domain/run_outcome.zig");
const workflow = @import("../domain/workflow.zig");
const bindings = @import("workflow_engine_child_bindings.zig");

pub fn run(children: bindings.ChildBindings) run_outcome.Outcome {
    if (selectionTerminal(children.invokeValidateOperationRegistry())) |outcome| return outcome;
    if (selectionTerminal(children.invokeParseInvocation())) |outcome| return outcome;
    if (selectionTerminal(children.invokeSelectWorkflow())) |outcome| return outcome;
    switch (children.invokePrepareWorkflow()) {
        .ok => {},
        .failed => |failure| return .{ .bootstrap_failed = failure },
        .cancelled => return .{ .execution = .cancelled },
    }

    const graph = children.selectedGraph();
    const invocation = children.invokeInvocation();
    if (invocation.outcome != .ok) return .{ .execution = invocation.outcome };

    var current = graph.authority.start_step_id;
    var visited: usize = 0;
    while (visited < graph.authority.maximum_step_executions) : (visited += 1) {
        const applied = children.invokeStep(current);
        const target = resolveTransition(graph.authority.transitions, current, applied.outcome) orelse {
            return .{ .execution = if (applied.outcome == .ok) .failed else applied.outcome };
        };
        switch (target) {
            .terminal => |outcome| return .{ .execution = outcome },
            .step => |next| current = next,
        }
    }
    return .{ .execution = .failed };
}

fn selectionTerminal(step: bindings.SelectionStepOutcome) ?run_outcome.Outcome {
    return switch (step) {
        .ok => null,
        .invocation_invalid => .invocation_invalid,
        .failed => .{ .execution = .failed },
        .cancelled => .{ .execution = .cancelled },
    };
}

fn resolveTransition(
    transitions: []const workflow.Transition,
    step_id: workflow.WorkflowStepId,
    outcome: workflow.OutcomeTag,
) ?workflow.TransitionTarget {
    for (transitions) |transition| {
        if (@import("std").mem.eql(u8, transition.from.bytes, step_id.bytes) and transition.outcome == outcome) {
            return transition.target;
        }
    }
    return null;
}
