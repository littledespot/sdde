const std = @import("std");
const binding = @import("../domain/llm_provider_binding.zig");
const operation = @import("../domain/llm_provider_operation.zig");

pub const Error = std.mem.Allocator.Error || error{Cancelled};

pub const Context = opaque {};

pub const LLMProviderInterface = struct {
    context: *Context,
    vtable: *const VTable,

    pub const VTable = struct {
        count_input_tokens: *const fn (
            *Context,
            *const binding.ValidatedProviderModelBinding,
            *const operation.IdentifiedProviderNeutralModelRequest,
            *const operation.ValidatedProviderAuthorizationLeaseRef,
            *const operation.InvokedProviderOperation,
        ) Error!operation.ProviderTokenCountObservation,
        invoke: *const fn (
            *Context,
            *const binding.ValidatedProviderModelBinding,
            *const operation.IdentifiedProviderNeutralModelRequest,
            *const operation.ExactInputTokenCountEvidence,
            *const operation.ValidatedProviderAuthorizationLeaseRef,
            *const operation.InvokedProviderOperation,
        ) Error!operation.ProviderInvocationObservation,
    };

    pub fn countInputTokens(
        self: LLMProviderInterface,
        provider_binding: *const binding.ValidatedProviderModelBinding,
        request: *const operation.IdentifiedProviderNeutralModelRequest,
        authorization: *const operation.ValidatedProviderAuthorizationLeaseRef,
        invoked_operation: *const operation.InvokedProviderOperation,
    ) Error!operation.ProviderTokenCountObservation {
        return self.vtable.count_input_tokens(
            self.context,
            provider_binding,
            request,
            authorization,
            invoked_operation,
        );
    }

    pub fn invoke(
        self: LLMProviderInterface,
        provider_binding: *const binding.ValidatedProviderModelBinding,
        request: *const operation.IdentifiedProviderNeutralModelRequest,
        count_evidence: *const operation.ExactInputTokenCountEvidence,
        authorization: *const operation.ValidatedProviderAuthorizationLeaseRef,
        invoked_operation: *const operation.InvokedProviderOperation,
    ) Error!operation.ProviderInvocationObservation {
        return self.vtable.invoke(
            self.context,
            provider_binding,
            request,
            count_evidence,
            authorization,
            invoked_operation,
        );
    }
};
