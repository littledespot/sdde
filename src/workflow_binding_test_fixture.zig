const provider_port = @import("ports/llm_provider_interface.zig");
const provider_binding = @import("domain/llm_provider_binding.zig");
const provider_operation = @import("domain/llm_provider_operation.zig");
const operations = @import("ports/workflow_operation_registry.zig");
const execution = @import("domain/workflow_execution.zig");

var context: u8 = 0;
pub const ModelContext = struct { provider: provider_port.LLMProviderInterface = port() };
pub var model_context: ModelContext = .{};

/// A real narrow port with no external effects; these binding tests never call
/// a provider. Unexpected calls fail rather than silently succeeding.
pub fn port() provider_port.LLMProviderInterface {
    return .{ .context = @ptrCast(&context), .vtable = &.{ .count_input_tokens = count, .invoke = invoke } };
}

pub fn unused(_: ?*void, _: operations.Input) operations.Error!execution.Candidate {
    return error.OperationExecutionFailed;
}

pub fn unusedModel(_: ?*ModelContext, _: operations.Input) operations.Error!execution.Candidate {
    return error.OperationExecutionFailed;
}

fn count(_: *provider_port.Context, _: *const provider_binding.ValidatedProviderModelBinding, _: *const provider_operation.IdentifiedProviderNeutralModelRequest, _: *const provider_operation.ValidatedProviderAuthorizationLeaseRef, _: *const provider_operation.InvokedProviderOperation) provider_port.Error!provider_operation.ProviderTokenCountObservation {
    return error.Cancelled;
}

fn invoke(_: *provider_port.Context, _: *const provider_binding.ValidatedProviderModelBinding, _: *const provider_operation.IdentifiedProviderNeutralModelRequest, _: *const provider_operation.ExactInputTokenCountEvidence, _: *const provider_operation.ValidatedProviderAuthorizationLeaseRef, _: *const provider_operation.InvokedProviderOperation) provider_port.Error!provider_operation.ProviderInvocationObservation {
    return error.Cancelled;
}
