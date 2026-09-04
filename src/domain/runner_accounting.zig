const model_attempt = @import("model_attempt_accounting.zig");
const workflow_tokens = @import("workflow_token_accounting.zig");

pub const Transition = union(enum) {
    increment_model_attempt: model_attempt.Transition,
    reserve_workflow_tokens: workflow_tokens.ReservationTransition,
    reconcile_workflow_tokens: workflow_tokens.ReconciliationTransition,
};
