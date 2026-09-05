const pipeline = @import("pipeline.zig");
const workflow = @import("workflow.zig");
const compilation = @import("workflow_compilation.zig");

pub const max_invocation_arguments: usize = 64;

pub const Invocation = struct {
    workflow_id: workflow.WorkflowId,
    arguments: []const []const u8,
};

pub const SelectedWorkflow = struct {
    invocation: Invocation,
    graph: *const compilation.CompiledWorkflow,
};

pub const Candidate = struct {
    outcome: workflow.OutcomeTag,
    delta: pipeline.NodeDelta,
};

pub const Applied = union(enum) {
    outcome: workflow.OutcomeTag,
    rejected: Rejection,

    pub fn status(self: Applied) workflow.OutcomeTag {
        return switch (self) {
            .outcome => |tag| tag,
            .rejected => |reason| reason.status(),
        };
    }
};

pub const Rejection = union(enum) {
    gate: @import("workflow_gate.zig").Rejection,
    authority,
    logging: @import("feature_log_stream.zig").FailureCode,
    cancelled,
    deadline_exhausted,
    token_budget: @import("workflow_token_accounting.zig").BudgetError,

    pub fn status(self: Rejection) workflow.OutcomeTag {
        return switch (self) {
            .gate, .logging => .blocked,
            .authority, .deadline_exhausted, .token_budget => .failed,
            .cancelled => .cancelled,
        };
    }
};

pub const Outcome = workflow.OutcomeTag;

pub const InvocationError = error{
    MissingWorkflowId,
    TooManyArguments,
    InvalidWorkflowId,
    UnknownWorkflowId,
};
