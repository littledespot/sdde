const std = @import("std");
const fake_provider = @import("adapters/provider/fake_llm_provider.zig");
const binding = @import("domain/llm_provider_binding.zig");
const contracts = @import("domain/llm_provider_contracts.zig");
const provider_identity = @import("domain/llm_provider_identity.zig");
const operation = @import("domain/llm_provider_operation.zig");
const provider_registry = @import("domain/llm_provider_registry.zig");
const request_identity = @import("domain/model_request_identity.zig");
const workflow = @import("domain/workflow.zig");

test "fake provider conforms to count and inference through the sole interface" {
    var fixture: Fixture = undefined;
    try fixture.init();
    var fake: fake_provider.FakeLLMProvider = .{
        .allocator = std.testing.allocator,
        .count_plan = .{ .counted = 10 },
        .invocation_plan = .{ .complete = .{
            .content = "{\"schemaVersion\":\"model-envelope/v1\"}",
            .output_tokens = 5,
            .provider_latency_ms = 7,
        } },
    };
    const interface = fake.interface();

    const count_operation = fixture.invoked(.input_token_count, 1);
    const count_lease = fixture.lease(count_operation, 1);
    const count = try interface.countInputTokens(
        &fixture.provider_binding,
        &fixture.request,
        &count_lease,
        &count_operation,
    );
    const evidence = try operation.ExactInputTokenCountEvidence.fromObservation(
        count,
        fixture.request,
        fixture.provider_binding,
    );
    try std.testing.expectEqual(@as(u64, 10), evidence.input_tokens);

    const inference_operation = fixture.invoked(.inference, 1);
    const inference_lease = fixture.lease(inference_operation, 2);
    var result = try interface.invoke(
        &fixture.provider_binding,
        &fixture.request,
        &evidence,
        &inference_lease,
        &inference_operation,
    );
    defer result.deinit();

    switch (result) {
        .completed => |completed| {
            try std.testing.expect(completed.operation_id.eql(inference_operation.id));
            switch (completed.raw_result) {
                .complete => |complete| {
                    try std.testing.expect(complete.request_id == &fixture.model_request_id);
                    try std.testing.expect(complete.binding_id.eql(fixture.provider_binding.bindingId()));
                    try std.testing.expectEqualStrings(
                        "{\"schemaVersion\":\"model-envelope/v1\"}",
                        complete.content.bytes,
                    );
                    try std.testing.expectEqual(@as(u64, 15), complete.usage.total_tokens);
                    try std.testing.expectEqual(@as(?u32, 7), complete.provider_latency_ms);
                },
                .stopped => return error.ExpectedCompleteProviderResult,
            }
        },
        .failed => return error.ExpectedCompletedProviderObservation,
    }
    try std.testing.expectEqual(@as(usize, 1), fake.count_call_count);
    try std.testing.expectEqual(@as(usize, 1), fake.invocation_call_count);
}

test "provider request rejects malformed identity content controls and limits" {
    var fixture: Fixture = undefined;
    try fixture.init();

    var invalid = fixture.request;
    invalid.model_operation_id.workflow_version = 2;
    try std.testing.expectError(
        error.InvalidProviderNeutralModelRequest,
        operation.IdentifiedProviderNeutralModelRequest.init(invalid),
    );

    const invalid_utf8 = [_]u8{0xff};
    const invalid_content = [_]operation.ModelVisibleContent{.{ .user = &invalid_utf8 }};
    invalid = fixture.request;
    invalid.content = &invalid_content;
    try std.testing.expectError(
        error.InvalidProviderNeutralModelRequest,
        operation.IdentifiedProviderNeutralModelRequest.init(invalid),
    );

    invalid = fixture.request;
    invalid.controls.temperature = .{ .value = 1001 };
    try std.testing.expectError(
        error.InvalidProviderNeutralModelRequest,
        operation.IdentifiedProviderNeutralModelRequest.init(invalid),
    );

    invalid = fixture.request;
    invalid.limits.maximum_input_bytes = 1;
    try std.testing.expectError(
        error.InvalidProviderNeutralModelRequest,
        operation.IdentifiedProviderNeutralModelRequest.init(invalid),
    );
}

test "exact count evidence rejects failures mismatches and exhausted capacity" {
    var fixture: Fixture = undefined;
    try fixture.init();
    const count_operation = fixture.invoked(.input_token_count, 1);
    const failure: operation.ProviderTokenCountObservation = .{ .failed = .{
        .operation_id = count_operation.id,
        .cause = .exact_token_count_unavailable,
        .retry_class = .never,
        .delivery = .not_sent,
    } };
    try std.testing.expectError(
        error.ExactTokenCountEvidenceUnavailable,
        operation.ExactInputTokenCountEvidence.fromObservation(
            failure,
            fixture.request,
            fixture.provider_binding,
        ),
    );

    var counted: operation.ProviderTokenCountObservation = .{ .counted = .{
        .operation_id = count_operation.id,
        .binding_id = fixture.provider_binding.bindingId(),
        .model_visible_input_id = fixture.request.model_visible_input_id,
        .input_tokens = 81,
    } };
    try std.testing.expectError(
        error.InvalidExactTokenCountEvidence,
        operation.ExactInputTokenCountEvidence.fromObservation(
            counted,
            fixture.request,
            fixture.provider_binding,
        ),
    );

    counted.counted.input_tokens = 101;
    try std.testing.expectError(
        error.InvalidExactTokenCountEvidence,
        operation.ExactInputTokenCountEvidence.fromObservation(
            counted,
            fixture.request,
            fixture.provider_binding,
        ),
    );

    counted.counted.input_tokens = 10;
    counted.counted.model_visible_input_id = operation.ModelVisibleInputId.parse("other-input").?;
    try std.testing.expectError(
        error.InvalidExactTokenCountEvidence,
        operation.ExactInputTokenCountEvidence.fromObservation(
            counted,
            fixture.request,
            fixture.provider_binding,
        ),
    );
}

test "fake provider rejects incoherent operations before a simulated send" {
    var fixture: Fixture = undefined;
    try fixture.init();
    var fake: fake_provider.FakeLLMProvider = .{
        .allocator = std.testing.allocator,
        .count_plan = .{ .counted = 10 },
        .invocation_plan = .{ .complete = .{ .content = "{}", .output_tokens = 1 } },
    };
    const interface = fake.interface();
    const wrong_operation = fixture.invoked(.inference, 1);
    const lease = fixture.lease(wrong_operation, 1);
    const result = try interface.countInputTokens(
        &fixture.provider_binding,
        &fixture.request,
        &lease,
        &wrong_operation,
    );
    switch (result) {
        .counted => return error.ExpectedRejectedCountInvocation,
        .failed => |failure| {
            try std.testing.expectEqual(operation.ProviderFailureCause.request_rejected, failure.cause);
            try std.testing.expectEqual(operation.ProviderRetryClass.never, failure.retry_class);
            try std.testing.expectEqual(operation.ProviderDeliveryDisposition.not_sent, failure.delivery);
        },
    }
    try std.testing.expectEqual(@as(usize, 1), fake.count_call_count);
    try std.testing.expectEqual(@as(usize, 0), fake.invocation_call_count);
}

test "fake provider preserves every closed failure cause without retrying" {
    var fixture: Fixture = undefined;
    try fixture.init();
    var fake: fake_provider.FakeLLMProvider = .{
        .allocator = std.testing.allocator,
        .count_plan = undefined,
        .invocation_plan = .cancelled,
    };
    const interface = fake.interface();
    const count_operation = fixture.invoked(.input_token_count, 1);
    const count_lease = fixture.lease(count_operation, 1);

    for (std.enums.values(operation.ProviderFailureCause)) |cause| {
        fake.count_plan = .{ .failed = .{
            .cause = cause,
            .retry_class = .policy_eligible,
            .delivery = .accepted_or_unknown,
        } };
        const result = try interface.countInputTokens(
            &fixture.provider_binding,
            &fixture.request,
            &count_lease,
            &count_operation,
        );
        switch (result) {
            .counted => return error.ExpectedProviderFailure,
            .failed => |failure| {
                try std.testing.expectEqual(cause, failure.cause);
                try std.testing.expectEqual(operation.ProviderRetryClass.policy_eligible, failure.retry_class);
                try std.testing.expectEqual(operation.ProviderDeliveryDisposition.accepted_or_unknown, failure.delivery);
            },
        }
    }
    try std.testing.expectEqual(
        std.enums.values(operation.ProviderFailureCause).len,
        fake.count_call_count,
    );
    try std.testing.expectEqual(@as(usize, 0), fake.invocation_call_count);
}

test "noncandidate stops carry no content and cancellation stays distinct" {
    var fixture: Fixture = undefined;
    try fixture.init();
    var fake: fake_provider.FakeLLMProvider = .{
        .allocator = std.testing.allocator,
        .count_plan = .{ .counted = 10 },
        .invocation_plan = .{ .stopped = .{
            .reason = .content_filtered,
            .output_tokens = 0,
        } },
    };
    const interface = fake.interface();
    const count_operation = fixture.invoked(.input_token_count, 1);
    const count_lease = fixture.lease(count_operation, 1);
    const count = try interface.countInputTokens(
        &fixture.provider_binding,
        &fixture.request,
        &count_lease,
        &count_operation,
    );
    const evidence = try operation.ExactInputTokenCountEvidence.fromObservation(
        count,
        fixture.request,
        fixture.provider_binding,
    );
    const inference_operation = fixture.invoked(.inference, 1);
    const inference_lease = fixture.lease(inference_operation, 2);
    var stopped = try interface.invoke(
        &fixture.provider_binding,
        &fixture.request,
        &evidence,
        &inference_lease,
        &inference_operation,
    );
    defer stopped.deinit();
    switch (stopped) {
        .completed => |completed| switch (completed.raw_result) {
            .stopped => |value| try std.testing.expectEqual(
                operation.ProviderNonCandidateStopReason.content_filtered,
                value.reason,
            ),
            .complete => return error.ExpectedStoppedProviderResult,
        },
        .failed => return error.ExpectedCompletedProviderObservation,
    }

    fake.count_plan = .cancelled;
    try std.testing.expectError(
        error.Cancelled,
        interface.countInputTokens(
            &fixture.provider_binding,
            &fixture.request,
            &count_lease,
            &count_operation,
        ),
    );
}

test "fake provider maps malformed and over-limit output to closed failures" {
    var fixture: Fixture = undefined;
    try fixture.init();
    var fake: fake_provider.FakeLLMProvider = .{
        .allocator = std.testing.allocator,
        .count_plan = .{ .counted = 10 },
        .invocation_plan = .{ .complete = .{ .content = "{}", .output_tokens = 1 } },
    };
    const interface = fake.interface();
    const count_operation = fixture.invoked(.input_token_count, 1);
    const count_lease = fixture.lease(count_operation, 1);
    const count = try interface.countInputTokens(
        &fixture.provider_binding,
        &fixture.request,
        &count_lease,
        &count_operation,
    );
    const evidence = try operation.ExactInputTokenCountEvidence.fromObservation(
        count,
        fixture.request,
        fixture.provider_binding,
    );
    const inference_operation = fixture.invoked(.inference, 1);
    const inference_lease = fixture.lease(inference_operation, 2);

    const invalid_utf8 = [_]u8{0xff};
    fake.invocation_plan = .{ .complete = .{
        .content = &invalid_utf8,
        .output_tokens = 1,
    } };
    var malformed = try interface.invoke(
        &fixture.provider_binding,
        &fixture.request,
        &evidence,
        &inference_lease,
        &inference_operation,
    );
    defer malformed.deinit();
    try expectFailure(malformed, .response_invalid, .response_received);

    fake.invocation_plan = .{ .complete = .{
        .content = "this response exceeds the configured byte ceiling",
        .output_tokens = 1,
    } };
    var over_limit = try interface.invoke(
        &fixture.provider_binding,
        &fixture.request,
        &evidence,
        &inference_lease,
        &inference_operation,
    );
    defer over_limit.deinit();
    try expectFailure(over_limit, .response_limit_exceeded, .response_received);
}

const Fixture = struct {
    registry_entry: provider_registry.Entry,
    provider_binding: binding.ValidatedProviderModelBinding,
    model_request_id: request_identity.ModelRequestId,
    request: operation.IdentifiedProviderNeutralModelRequest,

    fn init(self: *Fixture) !void {
        self.registry_entry = .{
            .id = .{ .ordinal = 1 },
            .provider = provider_identity.ProviderId.parse("fake-provider").?,
            .model = provider_identity.ModelId.parse("fake-model").?,
            .implementation_id = contracts.RegisteredProviderImplementationId.init(1).?,
            .config = .empty_object,
            .supported_reasoning_efforts = &.{"low"},
        };
        self.provider_binding = .{
            .operation_id = modelOperation(),
            .slot_id = provider_identity.ModelSlotId.parse("generation").?,
            .registry_entry = &self.registry_entry,
            .reasoning_effort = "low",
        };
        self.model_request_id = .{
            .stage_run_epoch_id = .{ .bytes = "epoch-1" },
            .immutable_unit_owner_id = .{ .task_cluster = .{
                .plan_state_id = .{ .bytes = "plan-state-1" },
                .obligation_cluster_id = .{ .bytes = "cluster-1" },
            } },
            .model_operation_id = modelOperation(),
            .purpose = .initial_generation,
            .request_ordinal = request_identity.PositiveOrdinal.init(1).?,
        };
        self.request = try operation.IdentifiedProviderNeutralModelRequest.init(.{
            .model_request_id = &self.model_request_id,
            .model_operation_id = modelOperation(),
            .binding_id = self.provider_binding.bindingId(),
            .request_schema_id = operation.RequestSchemaId.parse("request.test/v1").?,
            .result_schema_id = operation.ResultSchemaId.parse("result.test/v1").?,
            .model_visible_input_id = operation.ModelVisibleInputId.parse("input-1").?,
            .content = &fixture_content,
            .response_schema = "{}",
            .response_guidance_mode = .prompt_only,
            .controls = .{ .temperature = operation.TemperaturePermille.init(100) },
            .limits = operation.EffectiveModelLimits.init(256, 40, 100, 20, 100).?,
        });
    }

    fn invoked(
        self: *const Fixture,
        kind: operation.ProviderOperationKind,
        attempt: u32,
    ) operation.InvokedProviderOperation {
        return operation.InvokedProviderOperation.init(.{
            .model_request_id = &self.model_request_id,
            .model_attempt_ordinal = operation.ModelAttemptOrdinal.init(attempt).?,
            .kind = kind,
        }, 1000, operation.ProviderReceiveBudgets.init(32, 4096, 4096).?).?;
    }

    fn lease(
        self: *const Fixture,
        invoked_operation: operation.InvokedProviderOperation,
        id: u64,
    ) operation.ValidatedProviderAuthorizationLeaseRef {
        return operation.ValidatedProviderAuthorizationLeaseRef.init(.{
            .id = operation.ProviderAuthorizationLeaseId.init(id).?,
            .operation_id = invoked_operation.id,
            .binding_id = self.provider_binding.bindingId(),
            .model_visible_input_id = self.request.model_visible_input_id,
            .deadline_monotonic_ms = invoked_operation.deadline_monotonic_ms,
        }).?;
    }
};

const fixture_content = [_]operation.ModelVisibleContent{
    .{ .system = "Return the declared result." },
    .{ .user = "Generate the bounded candidate." },
};

fn modelOperation() binding.WorkflowModelOperationId {
    return .{
        .workflow_id = workflow.WorkflowId.parse("arbitrary-flow").?,
        .workflow_version = 1,
        .workflow_step_id = workflow.WorkflowStepId.parse("generate").?,
    };
}

fn expectFailure(
    observation: operation.ProviderInvocationObservation,
    cause: operation.ProviderFailureCause,
    delivery: operation.ProviderDeliveryDisposition,
) !void {
    switch (observation) {
        .completed => return error.ExpectedProviderFailure,
        .failed => |failure| {
            try std.testing.expectEqual(cause, failure.cause);
            try std.testing.expectEqual(delivery, failure.delivery);
            try std.testing.expectEqual(operation.ProviderRetryClass.never, failure.retry_class);
        },
    }
}
