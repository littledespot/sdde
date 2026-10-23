const std = @import("std");
const binding = @import("../../domain/llm_provider_binding.zig");
const operation = @import("../../domain/llm_provider_operation.zig");
const provider_interface = @import("../../ports/llm_provider_interface.zig");
const lease = @import("../../ports/provider_authorization_lease.zig");

pub const FailurePlan = struct {
    cause: operation.ProviderFailureCause,
    retry_class: operation.ProviderRetryClass,
    delivery: operation.ProviderDeliveryDisposition,
};

pub const CompletePlan = struct {
    content_diagnostic: ?operation.ProviderContentDiagnostic = null,
    content: []const u8,
    input_tokens: u64,
    output_tokens: u64,
    provider_latency_ms: ?u32 = null,
};

pub const StoppedPlan = struct {
    reason: operation.ProviderNonCandidateStopReason,
    input_tokens: u64,
    output_tokens: u64,
    provider_latency_ms: ?u32 = null,
};

pub const InvocationPlan = union(enum) {
    complete: CompletePlan,
    stopped: StoppedPlan,
    failed: FailurePlan,
    cancelled,
};

pub const FakeLLMProvider = struct {
    allocator: std.mem.Allocator,
    authorization_leases: lease.Port,
    invocation_plan: InvocationPlan,
    invocation_call_count: usize = 0,
    effect_count: usize = 0,

    pub fn interface(self: *FakeLLMProvider) provider_interface.LLMProviderInterface {
        return .{
            .context = @ptrCast(self),
            .vtable = &vtable,
        };
    }

    fn invoke(
        context: *provider_interface.Context,
        provider_binding: *const binding.ValidatedProviderModelBinding,
        request: *const operation.IdentifiedProviderNeutralModelRequest,
        authorization: *const operation.ValidatedProviderAuthorizationLeaseRef,
        invoked_operation: *const operation.InvokedProviderOperation,
    ) provider_interface.Error!operation.ProviderInvocationObservation {
        const self = cast(context);
        self.invocation_call_count += 1;
        var capability = self.authorization_leases.consume(authorization, provider_binding, request, invoked_operation) catch |err| {
            if (err == error.Cancelled) return error.Cancelled;
            return .{ .failed = authorizationFailure(invoked_operation.id, err) };
        };
        defer capability.deinit();
        if (!operation.validateInferenceInvocation(
            provider_binding,
            request,
            invoked_operation,
        )) return invalidInvocationCall(invoked_operation.id);
        self.effect_count += 1;

        return switch (self.invocation_plan) {
            .complete => |plan| self.complete(
                provider_binding,
                request,
                invoked_operation.id,
                plan,
            ),
            .stopped => |plan| self.stopped(
                provider_binding,
                request,
                invoked_operation.id,
                plan,
            ),
            .failed => |plan| .{ .failed = failure(invoked_operation.id, plan) },
            .cancelled => error.Cancelled,
        };
    }

    fn complete(
        self: *FakeLLMProvider,
        provider_binding: *const binding.ValidatedProviderModelBinding,
        request: *const operation.IdentifiedProviderNeutralModelRequest,
        operation_id: operation.ProviderOperationId,
        plan: CompletePlan,
    ) provider_interface.Error!operation.ProviderInvocationObservation {
        const total_tokens = std.math.add(u64, plan.input_tokens, plan.output_tokens) catch {
            return responseFailure(operation_id, .response_invalid);
        };
        const usage = operation.ProviderUsage.init(
            plan.input_tokens,
            plan.output_tokens,
            total_tokens,
        ) orelse return responseFailure(operation_id, .response_invalid);
        if (plan.content_diagnostic) |reason| return .{ .completed = .{ .operation_id = operation_id, .raw_result = .{ .rejected = .{
            .request_id = request.model_request_id,
            .binding_id = provider_binding.bindingId(),
            .reason = reason,
            .usage = usage,
            .provider_latency_ms = plan.provider_latency_ms,
        } } } };
        var content = operation.CompleteOwnedUtf8.init(
            self.allocator,
            plan.content,
        ) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidUtf8 => .{ .completed = .{ .operation_id = operation_id, .raw_result = .{ .rejected = .{
                .request_id = request.model_request_id,
                .binding_id = provider_binding.bindingId(),
                .reason = .invalid_content,
                .usage = usage,
                .provider_latency_ms = plan.provider_latency_ms,
            } } } },
        };
        errdefer content.deinit();
        return .{ .completed = .{
            .operation_id = operation_id,
            .raw_result = .{ .complete = .{
                .request_id = request.model_request_id,
                .binding_id = provider_binding.bindingId(),
                .content = content,
                .usage = usage,
                .provider_latency_ms = plan.provider_latency_ms,
            } },
        } };
    }

    fn stopped(
        _: *FakeLLMProvider,
        provider_binding: *const binding.ValidatedProviderModelBinding,
        request: *const operation.IdentifiedProviderNeutralModelRequest,
        operation_id: operation.ProviderOperationId,
        plan: StoppedPlan,
    ) provider_interface.Error!operation.ProviderInvocationObservation {
        const total_tokens = std.math.add(u64, plan.input_tokens, plan.output_tokens) catch {
            return responseFailure(operation_id, .response_invalid);
        };
        const usage = operation.ProviderUsage.init(
            plan.input_tokens,
            plan.output_tokens,
            total_tokens,
        ) orelse return responseFailure(operation_id, .response_invalid);
        return .{ .completed = .{
            .operation_id = operation_id,
            .raw_result = .{ .stopped = .{
                .request_id = request.model_request_id,
                .binding_id = provider_binding.bindingId(),
                .reason = plan.reason,
                .usage = usage,
                .provider_latency_ms = plan.provider_latency_ms,
            } },
        } };
    }
};

const vtable: provider_interface.LLMProviderInterface.VTable = .{
    .invoke = FakeLLMProvider.invoke,
};

fn cast(context: *provider_interface.Context) *FakeLLMProvider {
    return @ptrCast(@alignCast(context));
}

fn failure(
    operation_id: operation.ProviderOperationId,
    plan: FailurePlan,
) operation.ProviderFailure {
    return .{
        .operation_id = operation_id,
        .cause = plan.cause,
        .retry_class = plan.retry_class,
        .delivery = plan.delivery,
    };
}

fn authorizationFailure(operation_id: operation.ProviderOperationId, err: lease.Error) operation.ProviderFailure {
    return failure(operation_id, .{
        .cause = if (err == error.AuthorizationExpired) .timeout else .authorization_denied,
        .retry_class = .never,
        .delivery = .not_sent,
    });
}

fn invalidInvocationCall(operation_id: operation.ProviderOperationId) operation.ProviderInvocationObservation {
    return .{ .failed = failure(operation_id, .{
        .cause = .request_rejected,
        .retry_class = .never,
        .delivery = .not_sent,
    }) };
}

fn responseFailure(
    operation_id: operation.ProviderOperationId,
    cause: operation.ProviderFailureCause,
) operation.ProviderInvocationObservation {
    return .{ .failed = failure(operation_id, .{
        .cause = cause,
        .retry_class = .never,
        .delivery = .response_received,
    }) };
}
