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
    /// Expected rejection evidence; operational failure uses the error union.
    diagnostic: ?OperationError = null,
};

/// Diagnostic facts from the last accepted in-memory application. Failed deltas
/// never appear here and these facts cannot authorize execution or publication.
pub const OperationRejection = struct {
    cause: @import("operation_error.zig").Code(OperationError),
    outcome: workflow.OutcomeTag,
};

pub const AppliedEffects = struct {
    writes: @import("std").enums.EnumSet(pipeline.DataKey) = .initEmpty(),
    replacements: @import("std").enums.EnumSet(pipeline.DataKey) = .initEmpty(),
    invalidations: @import("std").enums.EnumSet(pipeline.DataKey) = .initEmpty(),
    repair: ?@import("workflow_retry.zig").Transition = null,
    diagnostic: ?OperationError = null,
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

pub const OperationError = @import("operation_error.zig").Error;

pub const Rejection = union(enum) {
    gate: @import("workflow_gate.zig").Rejection,
    authority,
    operation_failed: OperationError,
    logging: @import("feature_log_stream.zig").FailureCode,
    cancelled,
    deadline_exhausted,
    token_budget: @import("workflow_token_accounting.zig").BudgetError,
    retry_limit: @import("workflow_retry.zig").Exhaustion,

    pub fn diagnostic(self: Rejection) []const u8 {
        return switch (self) {
            .token_budget => |failure| @errorName(failure),
            .operation_failed => |failure| @errorName(failure),
            .retry_limit => "RetryLimitExhausted",
            .gate, .authority, .logging, .cancelled, .deadline_exhausted => @tagName(self.status()),
        };
    }

    pub fn status(self: Rejection) workflow.OutcomeTag {
        return switch (self) {
            .gate, .logging => .blocked,
            .authority, .operation_failed, .deadline_exhausted, .token_budget, .retry_limit => .failed,
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
