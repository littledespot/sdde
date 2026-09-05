const model_attempt = @import("model_attempt_accounting.zig");
const workflow_tokens = @import("workflow_token_accounting.zig");
const provider_lifecycle = @import("provider_operation_lifecycle.zig");

pub const Transition = union(enum) {
    increment_model_attempt: model_attempt.Transition,
    reconcile_workflow_tokens: workflow_tokens.ReconciliationTransition,
    advance_provider_operation: provider_lifecycle.Transition,
};
