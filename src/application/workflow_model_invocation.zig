const execution = @import("../domain/workflow_execution.zig");
const validation = @import("../domain/provider_invocation_validation.zig");
const result = @import("../domain/model_invocation_result.zig");
const tokens = @import("../domain/workflow_token_accounting.zig");
const token_runner = @import("workflow_token_accounting_runner.zig");
const invocation = @import("model_invocation_workflow.zig");
const values = @import("pipeline_values.zig");

/// Accounting is unconditional after a call, before runtime/delta publication
/// checks. Content validation and workflow transitions remain separate steps.
pub const InvocationResult = union(enum) { candidate: *const execution.Candidate, failed: execution.OperationError };

/// What accounting after a call decided: the rejection that ends the step, if any, and the call's own
/// rejection when a later accounting failure replaced it. The runner keeps `replaced` beside whatever
/// ends the step (27-observability.md); this decides nothing about it.
pub const Reconciled = struct {
    rejection: ?execution.Rejection = null,
    replaced: ?execution.Rejection = null,

    /// The earliest rejection this call left: what accounting replaced, else the rejection itself.
    pub fn earliest(self: Reconciled) ?execution.Rejection {
        return self.replaced orelse self.rejection;
    }
};

pub fn reconcile(accounting: *token_runner.Runner, revision: tokens.Revision, call: validation.Call, observed: InvocationResult) Reconciled {
    var resolution: tokens.Reconciliation = .unavailable;
    const rejection = classify(call, observed, &resolution);
    accounting.reconcile(revision, call.operation_id, resolution) catch |err| switch (err) {
        // Preserve the original failure/cancellation. This ledger state blocks
        // the next call without fabricating zero usage for an unknown delivery.
        error.ProviderTokenUsageUnavailable => {},
        error.WorkflowTokenBudgetExceeded => return replacing(rejection, .{ .token_budget = error.WorkflowTokenBudgetExceeded }),
        else => return replacing(rejection, .{ .operation_failed = err }),
    };
    if (observed == .candidate) {
        const candidate = observed.candidate;
        const retained = values.read(&.{ .slots = candidate.delta.data_writes }, invocation.schema, result.Result) catch return replacing(rejection, .{ .authority = .invocation_result });
        const original = retained.outcome() orelse return replacing(rejection, .{ .authority = .invocation_result });
        const stop: ?@import("../domain/model_invocation_result.zig").AccountingStop = if (rejection != null) null else switch (original.*) {
            .observation => if (resolution == .unavailable) .usage_unavailable else null,
            .cancelled, .allocation_failed, .logging_blocked_before_send => null,
        };
        retained.reconcileAccounting(stop) catch return replacing(rejection, .{ .authority = .invocation_result });
    }
    return .{ .rejection = rejection };
}

/// A rejection that ends the step where the call's own rejection, if it had one, would have.
fn replacing(replaced: ?execution.Rejection, terminal: execution.Rejection) Reconciled {
    return .{ .rejection = terminal, .replaced = replaced };
}

fn classify(call: validation.Call, result_value: InvocationResult, resolution: *tokens.Reconciliation) ?execution.Rejection {
    const value = switch (result_value) {
        .candidate => |value| value,
        .failed => |cause| return .{ .operation_failed = cause },
    };
    const observed = values.read(&.{ .slots = value.delta.data_writes }, invocation.schema, result.Result) catch return .{ .authority = .invocation_result };
    if (!observed.operationId().eql(call.operation_id)) return .{ .authority = .invocation_result };
    const outcome = observed.outcome() orelse return .{ .authority = .invocation_result };
    switch (outcome.*) {
        .observation => |*observation| {
            const usage = validation.validateUsage(call, observation) catch return .{ .authority = .invocation_result };
            if (usage) |exact| {
                resolution.* = .{ .exact_usage = exact };
            } else if (observation.failed.delivery == .not_sent) {
                resolution.* = .not_sent;
            }
        },
        .cancelled => {},
        .allocation_failed => return .{ .operation_failed = error.OutOfMemory },
        .logging_blocked_before_send => {
            resolution.* = .not_sent;
            return .{ .logging = .LOG_SINK_FAILURE };
        },
    }
    if (value.outcome != invocation.status(outcome.*)) return .{ .authority = .invocation_result };
    return null;
}
