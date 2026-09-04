const std = @import("std");
const binding = @import("../../domain/llm_provider_binding.zig");
const operation = @import("../../domain/llm_provider_operation.zig");
const provider_interface = @import("../../ports/llm_provider_interface.zig");

pub const FailurePlan = struct {
    cause: operation.ProviderFailureCause,
    retry_class: operation.ProviderRetryClass,
    delivery: operation.ProviderDeliveryDisposition,
};

pub const CountPlan = union(enum) {
    counted: u64,
    failed: FailurePlan,
    cancelled,
};

pub const CompletePlan = struct {
    content: []const u8,
    output_tokens: u64,
    provider_latency_ms: ?u32 = null,
};

pub const StoppedPlan = struct {
    reason: operation.ProviderNonCandidateStopReason,
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
    count_plan: CountPlan,
    invocation_plan: InvocationPlan,
    count_call_count: usize = 0,
    invocation_call_count: usize = 0,

    pub fn interface(self: *FakeLLMProvider) provider_interface.LLMProviderInterface {
        return .{
            .context = @ptrCast(self),
            .vtable = &vtable,
        };
    }

    fn countInputTokens(
        context: *provider_interface.Context,
        provider_binding: *const binding.ValidatedProviderModelBinding,
        request: *const operation.IdentifiedProviderNeutralModelRequest,
        authorization: *const operation.ValidatedProviderAuthorizationLeaseRef,
        invoked_operation: *const operation.InvokedProviderOperation,
    ) provider_interface.Error!operation.ProviderTokenCountObservation {
        const self = cast(context);
        self.count_call_count += 1;
        if (!operation.validateCountInvocation(
            provider_binding,
            request,
            authorization,
            invoked_operation,
        )) return invalidCall(invoked_operation.id);

        return switch (self.count_plan) {
            .counted => |input_tokens| .{ .counted = .{
                .operation_id = invoked_operation.id,
                .binding_id = provider_binding.bindingId(),
                .model_visible_input_id = request.model_visible_input_id,
                .input_tokens = input_tokens,
            } },
            .failed => |plan| .{ .failed = failure(invoked_operation.id, plan) },
            .cancelled => error.Cancelled,
        };
    }

    fn invoke(
        context: *provider_interface.Context,
        provider_binding: *const binding.ValidatedProviderModelBinding,
        request: *const operation.IdentifiedProviderNeutralModelRequest,
        count_evidence: *const operation.ExactInputTokenCountEvidence,
        authorization: *const operation.ValidatedProviderAuthorizationLeaseRef,
        invoked_operation: *const operation.InvokedProviderOperation,
    ) provider_interface.Error!operation.ProviderInvocationObservation {
        const self = cast(context);
        self.invocation_call_count += 1;
        if (!operation.validateInferenceInvocation(
            provider_binding,
            request,
            count_evidence,
            authorization,
            invoked_operation,
        )) return invalidInvocationCall(invoked_operation.id);

        return switch (self.invocation_plan) {
            .complete => |plan| self.complete(
                provider_binding,
                request,
                count_evidence,
                invoked_operation.id,
                plan,
            ),
            .stopped => |plan| self.stopped(
                provider_binding,
                request,
                count_evidence,
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
        count_evidence: *const operation.ExactInputTokenCountEvidence,
        operation_id: operation.ProviderOperationId,
        plan: CompletePlan,
    ) provider_interface.Error!operation.ProviderInvocationObservation {
        if (plan.output_tokens > request.limits.maximum_output_tokens) {
            return responseFailure(operation_id, .response_limit_exceeded);
        }
        const total_tokens = std.math.add(u64, count_evidence.input_tokens, plan.output_tokens) catch {
            return responseFailure(operation_id, .response_invalid);
        };
        const usage = operation.ProviderUsage.init(
            count_evidence.input_tokens,
            plan.output_tokens,
            total_tokens,
        ) orelse return responseFailure(operation_id, .response_invalid);
        var content = operation.CompleteBoundedOwnedUtf8.init(
            self.allocator,
            plan.content,
            request.limits.maximum_output_bytes,
        ) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidUtf8 => responseFailure(operation_id, .response_invalid),
            error.LimitExceeded => responseFailure(operation_id, .response_limit_exceeded),
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
        count_evidence: *const operation.ExactInputTokenCountEvidence,
        operation_id: operation.ProviderOperationId,
        plan: StoppedPlan,
    ) provider_interface.Error!operation.ProviderInvocationObservation {
        if (plan.output_tokens > request.limits.maximum_output_tokens) {
            return responseFailure(operation_id, .response_limit_exceeded);
        }
        const total_tokens = std.math.add(u64, count_evidence.input_tokens, plan.output_tokens) catch {
            return responseFailure(operation_id, .response_invalid);
        };
        const usage = operation.ProviderUsage.init(
            count_evidence.input_tokens,
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
    .count_input_tokens = FakeLLMProvider.countInputTokens,
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

fn invalidCall(operation_id: operation.ProviderOperationId) operation.ProviderTokenCountObservation {
    return .{ .failed = failure(operation_id, .{
        .cause = .request_rejected,
        .retry_class = .never,
        .delivery = .not_sent,
    }) };
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
