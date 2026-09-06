const pipeline = @import("../../domain/pipeline.zig");
const binding = @import("../../domain/llm_provider_binding.zig");
const operation = @import("../../domain/llm_provider_operation.zig");
const provider_port = @import("../../ports/llm_provider_interface.zig");

pub const Action = struct {
    provider: provider_port.LLMProviderInterface,

    pub const contract: pipeline.NodeContract = .{
        .id = "count-model-input-tokens",
        .kind = .action,
        .requires = &.{ .model_request_identity_ledger, .validated_provider_model_binding, .validated_provider_authorization },
        .produces = &.{},
        .side_effect = .model_call,
    };

    /// The port owns lease consumption and call checks. Counting is optional;
    /// its observation neither authorizes inference nor charges token usage.
    pub fn execute(
        self: Action,
        provider_binding: *const binding.ValidatedProviderModelBinding,
        request: *const operation.IdentifiedProviderNeutralModelRequest,
        authorization: *const operation.ValidatedProviderAuthorizationLeaseRef,
        invoked_operation: *const operation.InvokedProviderOperation,
    ) provider_port.Error!operation.ProviderTokenCountObservation {
        return self.provider.countInputTokens(provider_binding, request, authorization, invoked_operation);
    }
};
