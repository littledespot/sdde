const execution = @import("../domain/workflow_execution.zig");
const validation = @import("../domain/provider_invocation_validation.zig");
const result = @import("../domain/model_invocation_result.zig").For(.inference);
const tokens = @import("../domain/workflow_token_accounting.zig");
const token_runner = @import("workflow_token_accounting_runner.zig");
const invocation = @import("model_invocation_workflow.zig");
const values = @import("pipeline_values.zig");

/// Counts have no usage reconciliation, including after failure or cancellation.
pub fn validateCount(call: validation.Call, candidate: *const execution.Candidate) ?execution.Rejection {
    const counted = @import("../domain/model_invocation_result.zig").For(.input_token_count);
    const observed = values.read(&.{ .slots = candidate.delta.data_writes }, invocation.count_schema, counted.Result) catch return .authority;
    if (!observed.operationId().eql(call.operation_id)) return .authority;
    const outcome = observed.outcome() orelse return .authority;
    if (outcome.* == .allocation_failed) return .operation_failed;
    return if (candidate.outcome == invocation.countStatus(outcome.*)) null else .authority;
}

/// Accounting is unconditional after a call, before runtime/delta publication
/// checks. Content validation and workflow transitions remain separate steps.
pub fn reconcile(accounting: *token_runner.Runner, revision: tokens.Revision, call: validation.Call, candidate: ?*const execution.Candidate) ?execution.Rejection {
    var resolution: tokens.Reconciliation = .unavailable;
    const rejection = classify(call, candidate, &resolution);
    accounting.reconcile(revision, call.operation_id, resolution) catch |err| switch (err) {
        // Preserve the original failure/cancellation. This ledger state blocks
        // the next call without fabricating zero usage for an unknown delivery.
        error.ProviderTokenUsageUnavailable => {},
        error.WorkflowTokenBudgetExceeded => return .{ .token_budget = error.WorkflowTokenBudgetExceeded },
        else => return .operation_failed,
    };
    return rejection;
}

fn classify(call: validation.Call, candidate: ?*const execution.Candidate, resolution: *tokens.Reconciliation) ?execution.Rejection {
    const value = candidate orelse return .operation_failed;
    const observed = values.read(&.{ .slots = value.delta.data_writes }, invocation.schema, result.Result) catch return .authority;
    if (!observed.operationId().eql(call.operation_id)) return .authority;
    const outcome = observed.outcome() orelse return .authority;
    switch (outcome.*) {
        .observation => |*observation| {
            const usage = validation.validateUsage(call, observation) catch return .authority;
            if (usage) |exact| {
                resolution.* = .{ .exact_usage = exact };
            } else if (observation.failed.delivery == .not_sent) {
                resolution.* = .not_sent;
            }
        },
        .cancelled => {},
        .allocation_failed => return .operation_failed,
    }
    if (value.outcome != invocation.status(outcome.*)) return .authority;
    return null;
}
