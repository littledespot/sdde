const pipeline = @import("pipeline.zig");
const workflow = @import("workflow_registry.zig");

pub const max_invocation_arguments: usize = 64;

pub const Invocation = struct {
    workflow_id: workflow.WorkflowId,
    arguments: []const []const u8,
};

pub const SelectedWorkflow = struct {
    invocation: Invocation,
    graph: *const workflow.CompiledWorkflow,
};

pub const Candidate = struct {
    outcome: workflow.OutcomeTag,
    delta: pipeline.NodeDelta,
};

pub const Applied = struct {
    outcome: workflow.OutcomeTag,
};

pub const Outcome = workflow.OutcomeTag;

pub const InvocationError = error{
    MissingWorkflowId,
    TooManyArguments,
    InvalidWorkflowId,
    UnknownWorkflowId,
};
