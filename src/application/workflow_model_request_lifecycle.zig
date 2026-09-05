const identity = @import("../domain/model_request_identity.zig");
const handoff = @import("../domain/model_request_handoff.zig");
const pipeline = @import("../domain/pipeline.zig");
const data = @import("../domain/pipeline_data.zig");
const requests = @import("model_request_workflow.zig");
const values = @import("pipeline_values.zig");
const Error = identity.ValidationError || values.Error || @import("../ports/workflow_operation_registry.zig").Error;

/// Validate a declared ledger replacement, not a second transition authority.
pub fn validateReplacement(input: *const data.View, contract: pipeline.NodeContract, delta: *const pipeline.NodeDelta) Error!*const identity.ModelRequestIdentityLedger {
    const current = try values.read(input, requests.ledger_schema, identity.ModelRequestIdentityLedger);
    const next = try values.read(&.{ .slots = delta.data_replacements }, requests.ledger_schema, identity.ModelRequestIdentityLedger);
    if (@import("../domain/workflow_model_request_lifecycle.zig").advances(contract.replaces, contract.produces)) {
        const request = try requests.readCurrent(input, requests.prepared_schema);
        // The closed YAML contract currently supports only this transition.
        try identity.validateLifecycleSuccessor(current, next, request.id(), .assigned, .invoked);
    } else {
        const assigned = try values.read(&.{ .slots = delta.data_writes }, requests.assigned_schema, handoff.Request);
        if (assigned.ledger() != next) return error.ModelRequestBindingInvalid;
        try identity.validateAssignmentSuccessor(current, next, assigned.id());
    }
    return next;
}
