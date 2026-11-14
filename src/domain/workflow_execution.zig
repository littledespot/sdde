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
    iteration: ?@import("workflow_iteration.zig").Transition = null,
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

/// Why the runner or a kernel binding stopped a run on its own authority (design/contracts/06-pipeline-nodes.md,
/// Runner rejection reasons). One member per cause class: an invariant the runner checks, never a call
/// site or a caller. The tag it rides (`Rejection.authority`) and the publish rules that follow from it
/// (ADR 0041) do not change.
pub const AuthorityReason = enum {
    /// The registry, the compiled graph or the selected operation drifted from what was compiled: an
    /// invalid registry, an unknown invocation operation, or its contract kind or outputs.
    registry_drift,
    /// A compiled step names no step, index, operation or contract variant the registry holds.
    step_unresolved,
    /// A compiled step's projection, contract, capabilities or the policy's permission disagree with the
    /// registered operation (ordinary and kernel steps alike).
    step_contract_mismatch,
    /// A gate the compiled step carries is no longer the registered gate.
    gate_drift,
    /// The step's model binding disagrees with its parameters, or the binding does not resolve.
    model_binding_mismatch,
    /// The step's input view, request ledger, resources or retained request cannot be built, or the ledger
    /// or request it carries is not the runner's own.
    input_view_unavailable,
    /// The retained request holds no prepared form, or the runner's model accounting state is absent.
    request_state_missing,
    /// Attempt, operation, request-closure, call-context or origin evidence is missing or disagrees with
    /// the retained request.
    lifecycle_evidence,
    /// Authorization evidence cannot be read, carries no bound deadline, or disagrees with the deadline it
    /// bound.
    authorization_evidence,
    /// The authorization does not allow this call: its preparation failed, or its lease is foreign,
    /// mismatched, stale or already consumed. A cancelled preparation is `cancelled`, not this.
    authorization_denied,
    /// The authorization clock is unavailable.
    authorization_clock_unavailable,
    /// The repair permit or the request assignment of a retry-bearing step does not match.
    repair_permit_mismatch,
    /// A runner-owned accounting transition cannot be prepared or applied: attempt accounting, provider
    /// operation transitions and their expected outcome. The attempt accounting also belongs to the
    /// stage run of the request it serves.
    accounting_transition,
    /// A retry allowance cannot be admitted or its exhaustion cannot be described.
    retry_admission,
    /// The step execution ceiling is spent.
    step_execution_ceiling,
    /// The publication finalizer refused to let publication proceed.
    publication_finalizer,
    /// A model invocation result cannot be read or disagrees with the call it records.
    invocation_result,
    /// An operation returned an outcome its contract does not declare.
    outcome_undeclared,
    /// An iteration descriptor and the candidate's iteration transition disagree.
    iteration_contract,
    /// A repair transition is missing, forbidden by the step's repair role, or unchanged beyond its limit.
    repair_transition,
    /// The candidate's diagnostic, request-ledger replacement, delta or application is not accepted.
    candidate_delta,
    /// A kernel stage does not match its registered stage.
    kernel_stage,
    /// A kernel stage answered with an outcome its stage table does not allow.
    kernel_stage_outcome,
    /// The kernel's engine-internal keys cannot be dropped at the end of the step.
    kernel_key_drop,
};

pub const Rejection = union(enum) {
    gate: @import("workflow_gate.zig").Rejection,
    authority: AuthorityReason,
    operation_failed: OperationError,
    logging: @import("feature_log_stream.zig").FailureCode,
    model_capture: @import("model_capture_failure.zig").Failure,
    cancelled,
    deadline_exhausted,
    token_budget: @import("workflow_token_accounting.zig").BudgetError,
    retry_limit: @import("workflow_retry.zig").Exhaustion,

    /// The stable name every surface shows for this rejection (events, the command line, reports and
    /// traces). An authority rejection names its reason; the reason sits beside the tag and moves no
    /// failure across the publish line, which `status()` alone decides (ADR 0041).
    pub fn diagnostic(self: Rejection) []const u8 {
        return switch (self) {
            .token_budget => |failure| @errorName(failure),
            .operation_failed => |failure| @errorName(failure),
            .authority => |reason| @tagName(reason),
            .retry_limit => |failure| switch (failure.reason) {
                .retry_limit => "RetryLimitExhausted",
                .unchanged_repair => "RepairNoProgress",
            },
            .model_capture => |failure| failure.diagnostic(),
            .gate, .logging, .cancelled, .deadline_exhausted => @tagName(self.status()),
        };
    }

    pub fn status(self: Rejection) workflow.OutcomeTag {
        return switch (self) {
            .gate, .logging, .model_capture => .blocked,
            .authority, .operation_failed, .deadline_exhausted, .token_budget, .retry_limit => .failed,
            .cancelled => .cancelled,
        };
    }
};

/// The rejection a later one replaced during a run, kept whole. The terminal `Rejection`
/// stays the later failure with its own status and diagnostic (ADR 0041 reads only that); this is the
/// first cause the report carries beside it. A capture failure is never one: it is recorded while its
/// call runs, before any rejection formed from that call's result, so it is its own first cause, and a
/// later logging failure reaches it as `Failure.subsequent_logging_failure`.
pub const FirstCause = union(enum) {
    gate: @import("workflow_gate.zig").Rejection,
    authority: AuthorityReason,
    operation_failed: OperationError,
    logging: @import("feature_log_stream.zig").FailureCode,
    cancelled,
    deadline_exhausted,
    token_budget: @import("workflow_token_accounting.zig").BudgetError,
    retry_limit: @import("workflow_retry.zig").Exhaustion,

    /// What `terminal` kept of the rejection it replaced: nothing when either is a capture failure, and
    /// nothing when both are the same rejection, which is one failure seen twice (a sink that stays
    /// broken fails every event the same way) and replaced nothing.
    pub fn replacedBy(replaced: Rejection, terminal: Rejection) ?FirstCause {
        const first = of(replaced) orelse return null;
        const later = of(terminal) orelse return null;
        return if (@import("std").meta.eql(first, later)) null else first;
    }

    fn of(rejected: Rejection) ?FirstCause {
        return switch (rejected) {
            .gate => |value| .{ .gate = value },
            .authority => |value| .{ .authority = value },
            .operation_failed => |value| .{ .operation_failed = value },
            .logging => |value| .{ .logging = value },
            .cancelled => .cancelled,
            .deadline_exhausted => .deadline_exhausted,
            .token_budget => |value| .{ .token_budget = value },
            .retry_limit => |value| .{ .retry_limit = value },
            .model_capture => null,
        };
    }

    /// The rejection this was, so its status and diagnostic come from `Rejection` alone.
    pub fn rejection(self: FirstCause) Rejection {
        return switch (self) {
            .gate => |value| .{ .gate = value },
            .authority => |value| .{ .authority = value },
            .operation_failed => |value| .{ .operation_failed = value },
            .logging => |value| .{ .logging = value },
            .cancelled => .cancelled,
            .deadline_exhausted => .deadline_exhausted,
            .token_budget => |value| .{ .token_budget = value },
            .retry_limit => |value| .{ .retry_limit = value },
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
