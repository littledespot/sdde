const identity = @import("../domain/model_request_identity.zig");
const handoff = @import("../domain/model_request_handoff.zig");
const pipeline = @import("../domain/pipeline.zig");
const data = @import("../domain/pipeline_data.zig");
const requests = @import("model_request_workflow.zig");
const values = @import("pipeline_values.zig");
const selection = @import("../domain/workflow_model_request_lifecycle.zig");
const lifecycle = @import("../domain/provider_operation_lifecycle.zig");
const Error = identity.ValidationError || lifecycle.ValidationError || values.Error || @import("../ports/workflow_operation_registry.zig").Error;

/// Validate a declared ledger replacement, not a second transition authority.
pub fn validateReplacement(input: *const data.View, contract: pipeline.NodeContract, delta: *const pipeline.NodeDelta, outcome: @import("../domain/workflow.zig").OutcomeTag, operations: ?*const lifecycle.Ledger) Error!*const identity.ModelRequestIdentityLedger {
    const current = try values.read(input, requests.ledger_schema, identity.ModelRequestIdentityLedger);
    const next = try values.read(&.{ .slots = delta.data_replacements }, requests.ledger_schema, identity.ModelRequestIdentityLedger);
    if (selection.advances(contract.replaces, contract.produces)) {
        const request = try requests.readCurrent(input, requests.prepared_schema);
        if (selection.completes(contract.requires)) {
            const facts = try readClosure(input);
            if (outcome != facts.outcome) return error.InvalidModelRequestLifecycleTransition;
            try (operations orelse return error.OperationExecutionFailed).validateRequestClosure(request.id());
            try identity.validateLifecycleSuccessor(current, next, request.id(), facts.expected_status, .{ .terminal = facts.reason });
        } else {
            if (outcome != .ok) return error.InvalidModelRequestLifecycleTransition;
            try identity.validateLifecycleSuccessor(current, next, request.id(), .assigned, .invoked);
        }
    } else {
        if (outcome != .ok) return error.InvalidModelRequestLifecycleTransition;
        const assigned = try values.read(&.{ .slots = delta.data_writes }, requests.assigned_schema, handoff.Request);
        if (assigned.ledger() != next) return error.ModelRequestBindingInvalid;
        try identity.validateAssignmentSuccessor(current, next, assigned.id());
    }
    return next;
}

pub fn readClosure(input: *const data.View) Error!selection.Closure {
    return if (input.contains(.provider_authorization_result))
        @import("model_request_termination_workflow.zig").readCurrent(input)
    else
        @import("model_request_completion_workflow.zig").readCurrent(input);
}
