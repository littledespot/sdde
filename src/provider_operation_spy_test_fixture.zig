const binding = @import("domain/llm_provider_binding.zig");
const operation = @import("domain/llm_provider_operation.zig");
const provider_port = @import("ports/llm_provider_interface.zig");

// Records borrowed pointers and delegates to the existing fake. Owns no lease
// or response; optional error injection occurs after the fake's cleanup.
pub const Spy = struct {
    inner: provider_port.LLMProviderInterface,
    invoke_calls: usize = 0,
    count_calls: usize = 0,
    received: ?struct {
        provider_binding: *const binding.ValidatedProviderModelBinding,
        request: *const operation.IdentifiedProviderNeutralModelRequest,
        authorization: *const operation.ValidatedProviderAuthorizationLeaseRef,
        invoked: *const operation.InvokedProviderOperation,
    } = null,
    returned_content: ?[]const u8 = null,
    returned_count: ?operation.ProviderTokenCountObservation = null,
    count_error: ?provider_port.Error = null,

    pub fn port(self: *Spy) provider_port.LLMProviderInterface {
        return .{ .context = @ptrCast(self), .vtable = &.{ .invoke = call, .count_input_tokens = count } };
    }

    fn call(context: *provider_port.Context, provider_binding: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, authorization: *const operation.ValidatedProviderAuthorizationLeaseRef, invoked: *const operation.InvokedProviderOperation) provider_port.Error!operation.ProviderInvocationObservation {
        const self: *Spy = @ptrCast(@alignCast(context));
        self.invoke_calls += 1;
        self.received = .{ .provider_binding = provider_binding, .request = request, .authorization = authorization, .invoked = invoked };
        const response = try self.inner.invoke(provider_binding, request, authorization, invoked);
        if (response == .completed and response.completed.raw_result == .complete) self.returned_content = response.completed.raw_result.complete.content.bytes;
        return response;
    }

    fn count(context: *provider_port.Context, provider_binding: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, authorization: *const operation.ValidatedProviderAuthorizationLeaseRef, invoked: *const operation.InvokedProviderOperation) provider_port.Error!operation.ProviderTokenCountObservation {
        const self: *Spy = @ptrCast(@alignCast(context));
        self.count_calls += 1;
        self.received = .{ .provider_binding = provider_binding, .request = request, .authorization = authorization, .invoked = invoked };
        const response = try self.inner.countInputTokens(provider_binding, request, authorization, invoked);
        self.returned_count = response;
        if (self.count_error) |err| return err;
        return response;
    }
};
