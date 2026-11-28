//! What an operation that observes the invoking account looks like (ADR 0025). The `actor_authentication` side effect and
//! the `actor_authentication` capability come together: an operation that reaches the authentication port declares the
//! effect, one that declares the effect reaches the port, and neither is a repair, a retry or an accounted step.
const operation = @import("workflow_operation.zig");
const compilation = @import("workflow_compilation.zig");
const capability = @import("workflow_capability.zig");

pub fn validContract(contract: operation.Contract, capabilities: []const capability.Capability) bool {
    const effect = contract.side_effect == .actor_authentication;
    if (effect != capability.contains(capabilities, .actor_authentication)) return false;
    return !effect or (contract.runner_accounting == .none and contract.retry_limit == null and contract.repair_role == .none);
}

pub fn validProjection(step: compilation.CompiledStep) bool {
    const effect = step.side_effect == .actor_authentication;
    if (effect != capability.contains(step.capabilities, .actor_authentication)) return false;
    return !effect or (step.runner_accounting == .none and step.retry_authority == null and step.repair_role == .none);
}
