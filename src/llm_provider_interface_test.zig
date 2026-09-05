const std = @import("std");
const fake_provider = @import("adapters/provider/fake_llm_provider.zig");
const operation = @import("domain/llm_provider_operation.zig");
const Fixture = @import("provider_authorization_test_fixture.zig").Fixture;

test "fake provider conforms to count and inference through the sole interface" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var fake = makeFake(&fixture);
    fake.invocation_plan = .{ .complete = .{
        .content = "{\"schemaVersion\":\"model-envelope/v1\"}",
        .input_tokens = 10,
        .output_tokens = 5,
        .provider_latency_ms = 7,
    } };
    const evidence = try countEvidence(&fixture, &fake);
    try std.testing.expectEqual(@as(u64, 10), evidence.input_tokens);
    const inference = try fixture.finishCountAndStartInference(evidence);
    var result = try fake.interface().invoke(&fixture.provider_binding, &fixture.request, inference.reference, inference.invoked);
    defer result.deinit();
    switch (result) {
        .completed => |completed| {
            try std.testing.expect(completed.operation_id.eql(inference.invoked.id));
            switch (completed.raw_result) {
                .complete => |complete| {
                    try std.testing.expect(complete.request_id == fixture.model_request_id);
                    try std.testing.expect(complete.binding_id.eql(fixture.provider_binding.bindingId()));
                    try std.testing.expectEqualStrings("{\"schemaVersion\":\"model-envelope/v1\"}", complete.content.bytes);
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
    try std.testing.expectEqual(@as(usize, 2), fake.effect_count);
    try std.testing.expectEqual(@as(usize, 2), fixture.preloader.destroyed_count);
}

test "actual fake-provider usage may overshoot and prevents another API call" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var tokens = @import("application/workflow_token_accounting_runner.zig").Runner.init(std.testing.allocator, .{ .value = 14 });
    defer tokens.deinit();
    var fake = makeFake(&fixture);
    fake.invocation_plan = .{ .complete = .{ .content = "{}", .input_tokens = 10, .output_tokens = 5 } };
    try tokens.check();
    const evidence = try countEvidence(&fixture, &fake);
    const inference = try fixture.finishCountAndStartInference(evidence);
    try tokens.check();
    var response = try fake.interface().invoke(&fixture.provider_binding, &fixture.request, inference.reference, inference.invoked);
    defer response.deinit();
    const actual = response.completed.raw_result.complete.usage;
    try std.testing.expectError(error.WorkflowTokenBudgetExceeded, tokens.reconcile(.initial, inference.invoked.id, .{ .exact_usage = actual }));
    try std.testing.expectEqual(@as(u128, 15), tokens.current().committed());
    try std.testing.expectError(error.WorkflowTokenBudgetExceeded, tokens.check());
    try std.testing.expectEqual(@as(usize, 1), fake.invocation_call_count);
    try std.testing.expectEqual(@as(usize, 1), fake.count_call_count);
}

test "inference needs no counter and preserves provider-reported large usage and limit stops" {
    for (0..3) |variant| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        fixture.registry_entry.capabilities.input_token_count = false;
        fixture.registry_entry.capabilities.exact_token_counter = .unavailable;
        var fake = makeFake(&fixture);
        fake.count_plan = .{ .failed = .{
            .cause = .exact_token_count_unavailable,
            .retry_class = .never,
            .delivery = .not_sent,
        } };
        fake.invocation_plan = if (variant == 0)
            .{ .complete = .{ .content = "{}", .input_tokens = 1_000_000, .output_tokens = 500_000 } }
        else
            .{ .stopped = .{ .reason = if (variant == 1) .output_limit else .context_limit, .input_tokens = 1_000_000, .output_tokens = 500_000 } };
        const inference = try fixture.startInference();
        try std.testing.expect(fixture.ledger().record(fixture.id(.input_token_count)) == null);
        var result = try fake.interface().invoke(&fixture.provider_binding, &fixture.request, inference.reference, inference.invoked);
        defer result.deinit();
        const usage = switch (result.completed.raw_result) {
            .complete => |value| value.usage,
            .stopped => |value| value.usage,
        };
        try std.testing.expectEqual(@as(u64, 1_500_000), usage.total_tokens);
        try std.testing.expectEqual(@as(usize, 0), fake.count_call_count);
        try std.testing.expectEqual(@as(usize, 1), fake.invocation_call_count);
        try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
    }
}

test "explicit unsupported counting rejects before send without disabling inference" {
    inline for (.{ false, true }) |count_supported| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        fixture.registry_entry.capabilities.input_token_count = count_supported;
        fixture.registry_entry.capabilities.exact_token_counter = .unavailable;
        try std.testing.expect(fixture.request.matchesBinding(fixture.provider_binding));
        var fake = makeFake(&fixture);
        const count = try fixture.startCount();
        const result = try fake.interface().countInputTokens(&fixture.provider_binding, &fixture.request, count.reference, count.invoked);
        try std.testing.expectEqual(operation.ProviderFailureCause.request_rejected, result.failed.cause);
        try std.testing.expectEqual(operation.ProviderDeliveryDisposition.not_sent, result.failed.delivery);
        try std.testing.expectEqual(@as(usize, 0), fake.effect_count);
        try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
    }
}

test "provider request rejects malformed identity content controls and limits" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var invalid = fixture.request;
    invalid.model_operation_id.workflow_version = 2;
    try std.testing.expectError(error.InvalidProviderNeutralModelRequest, operation.IdentifiedProviderNeutralModelRequest.init(invalid));
    const invalid_utf8 = [_]u8{0xff};
    const invalid_content = [_]operation.ModelVisibleContent{.{ .user = &invalid_utf8 }};
    invalid = fixture.request;
    invalid.content = &invalid_content;
    try std.testing.expectError(error.InvalidProviderNeutralModelRequest, operation.IdentifiedProviderNeutralModelRequest.init(invalid));
    invalid = fixture.request;
    invalid.controls.temperature = .{ .value = 1001 };
    try std.testing.expectError(error.InvalidProviderNeutralModelRequest, operation.IdentifiedProviderNeutralModelRequest.init(invalid));
    invalid = fixture.request;
    invalid.limits.maximum_input_bytes = 1;
    try std.testing.expectError(error.InvalidProviderNeutralModelRequest, operation.IdentifiedProviderNeutralModelRequest.init(invalid));
}

test "optional count evidence validates association without imposing token capacity" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const failure: operation.ProviderTokenCountObservation = .{ .failed = .{
        .operation_id = fixture.id(.input_token_count),
        .cause = .exact_token_count_unavailable,
        .retry_class = .never,
        .delivery = .not_sent,
    } };
    try std.testing.expectError(error.ExactTokenCountEvidenceUnavailable, operation.ExactInputTokenCountEvidence.fromObservation(failure, fixture.request, fixture.provider_binding));
    var counted: operation.ProviderTokenCountObservation = .{ .counted = .{
        .operation_id = fixture.id(.input_token_count),
        .binding_id = fixture.provider_binding.bindingId(),
        .model_visible_input_id = fixture.request.model_visible_input_id,
        .input_tokens = 81,
    } };
    _ = try operation.ExactInputTokenCountEvidence.fromObservation(counted, fixture.request, fixture.provider_binding);
    counted.counted.input_tokens = std.math.maxInt(u64);
    _ = try operation.ExactInputTokenCountEvidence.fromObservation(counted, fixture.request, fixture.provider_binding);
    counted.counted.input_tokens = 10;
    counted.counted.model_visible_input_id = operation.ModelVisibleInputId.parse("other-input").?;
    try std.testing.expectError(error.InvalidExactTokenCountEvidence, operation.ExactInputTokenCountEvidence.fromObservation(counted, fixture.request, fixture.provider_binding));
}

test "fake provider rejects incoherent operations before a simulated send" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    _ = try fixture.startCount();
    const inference = try fixture.finishCountAndStartInference(fixture.evidence());
    var fake = makeFake(&fixture);
    const result = try fake.interface().countInputTokens(&fixture.provider_binding, &fixture.request, inference.reference, inference.invoked);
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
    try std.testing.expectEqual(@as(usize, 0), fake.effect_count);
    try std.testing.expectEqual(@as(usize, 2), fixture.preloader.destroyed_count);
}

test "fake provider preserves every closed failure cause without retrying" {
    for (std.enums.values(operation.ProviderFailureCause)) |cause| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        var fake = makeFake(&fixture);
        fake.count_plan = .{ .failed = .{ .cause = cause, .retry_class = .policy_eligible, .delivery = .accepted_or_unknown } };
        const count = try fixture.startCount();
        const result = try fake.interface().countInputTokens(&fixture.provider_binding, &fixture.request, count.reference, count.invoked);
        switch (result) {
            .counted => return error.ExpectedProviderFailure,
            .failed => |failure| {
                try std.testing.expectEqual(cause, failure.cause);
                try std.testing.expectEqual(operation.ProviderRetryClass.policy_eligible, failure.retry_class);
                try std.testing.expectEqual(operation.ProviderDeliveryDisposition.accepted_or_unknown, failure.delivery);
            },
        }
        try std.testing.expectEqual(@as(usize, 1), fake.count_call_count);
        try std.testing.expectEqual(@as(usize, 0), fake.invocation_call_count);
        try std.testing.expectEqual(@as(usize, 1), fake.effect_count);
        try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
    }
}

test "noncandidate stops carry no content" {
    for (std.enums.values(operation.ProviderNonCandidateStopReason)) |reason| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        var fake = makeFake(&fixture);
        fake.invocation_plan = .{ .stopped = .{ .reason = reason, .input_tokens = 10, .output_tokens = 0 } };
        const evidence = try countEvidence(&fixture, &fake);
        const inference = try fixture.finishCountAndStartInference(evidence);
        var stopped = try fake.interface().invoke(&fixture.provider_binding, &fixture.request, inference.reference, inference.invoked);
        defer stopped.deinit();
        switch (stopped) {
            .completed => |completed| switch (completed.raw_result) {
                .stopped => |value| try std.testing.expectEqual(reason, value.reason),
                .complete => return error.ExpectedStoppedProviderResult,
            },
            .failed => return error.ExpectedCompletedProviderObservation,
        }
        try std.testing.expectEqual(@as(usize, 2), fixture.preloader.destroyed_count);
    }
}

test "provider cancellation stays distinct and destroys its consumed authorization" {
    inline for (.{ operation.ProviderOperationKind.input_token_count, operation.ProviderOperationKind.inference }) |kind| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        var fake = makeFake(&fixture);
        if (kind == .input_token_count) {
            fake.count_plan = .cancelled;
            const count = try fixture.startCount();
            try std.testing.expectError(error.Cancelled, fake.interface().countInputTokens(&fixture.provider_binding, &fixture.request, count.reference, count.invoked));
            try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
        } else {
            const evidence = try countEvidence(&fixture, &fake);
            fake.invocation_plan = .cancelled;
            const inference = try fixture.finishCountAndStartInference(evidence);
            try std.testing.expectError(error.Cancelled, fake.interface().invoke(&fixture.provider_binding, &fixture.request, inference.reference, inference.invoked));
            try std.testing.expectEqual(@as(usize, 2), fixture.preloader.destroyed_count);
        }
    }
}

test "fake provider maps malformed and over-limit output to closed failures" {
    const invalid_utf8 = [_]u8{0xff};
    const cases = [_]struct { plan: fake_provider.CompletePlan, cause: operation.ProviderFailureCause }{
        .{ .plan = .{ .content = &invalid_utf8, .input_tokens = 10, .output_tokens = 1 }, .cause = .response_invalid },
        .{ .plan = .{ .content = "this response exceeds the configured byte ceiling", .input_tokens = 10, .output_tokens = 1 }, .cause = .response_limit_exceeded },
        .{ .plan = .{ .content = "{}", .input_tokens = std.math.maxInt(u64), .output_tokens = 1 }, .cause = .response_invalid },
    };
    for (cases) |case| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        var fake = makeFake(&fixture);
        fake.invocation_plan = .{ .complete = case.plan };
        const evidence = try countEvidence(&fixture, &fake);
        const inference = try fixture.finishCountAndStartInference(evidence);
        var result = try fake.interface().invoke(&fixture.provider_binding, &fixture.request, inference.reference, inference.invoked);
        defer result.deinit();
        try expectFailure(result, case.cause, .response_received);
        try std.testing.expectEqual(@as(usize, 2), fixture.preloader.destroyed_count);
    }
}

test "fake provider allocation failures destroy consumed authorization and owned results" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}

fn allocationCase(allocator: std.mem.Allocator) !void {
    var fixture: Fixture = undefined;
    try fixture.init(allocator);
    defer fixture.deinit();
    var fake = makeFake(&fixture);
    fake.allocator = allocator;
    const evidence = try countEvidence(&fixture, &fake);
    const inference = try fixture.finishCountAndStartInference(evidence);
    var result = fake.interface().invoke(&fixture.provider_binding, &fixture.request, inference.reference, inference.invoked) catch |err| {
        try std.testing.expectEqual(fixture.preloader.prepared_count, fixture.preloader.destroyed_count);
        return err;
    };
    defer result.deinit();
    try std.testing.expect(result == .completed);
    try std.testing.expectEqual(fixture.preloader.prepared_count, fixture.preloader.destroyed_count);
}

fn makeFake(fixture: *Fixture) fake_provider.FakeLLMProvider {
    return .{
        .allocator = std.testing.allocator,
        .authorization_leases = fixture.leasePort(),
        .count_plan = .{ .counted = 10 },
        .invocation_plan = .{ .complete = .{ .content = "{}", .input_tokens = 10, .output_tokens = 1 } },
    };
}

fn countEvidence(fixture: *Fixture, fake: *fake_provider.FakeLLMProvider) !operation.ExactInputTokenCountEvidence {
    const count = try fixture.startCount();
    const observation = try fake.interface().countInputTokens(&fixture.provider_binding, &fixture.request, count.reference, count.invoked);
    return operation.ExactInputTokenCountEvidence.fromObservation(observation, fixture.request, fixture.provider_binding);
}

fn expectFailure(observation: operation.ProviderInvocationObservation, cause: operation.ProviderFailureCause, delivery: operation.ProviderDeliveryDisposition) !void {
    switch (observation) {
        .completed => return error.ExpectedProviderFailure,
        .failed => |failure| {
            try std.testing.expectEqual(cause, failure.cause);
            try std.testing.expectEqual(delivery, failure.delivery);
            try std.testing.expectEqual(operation.ProviderRetryClass.never, failure.retry_class);
        },
    }
}
