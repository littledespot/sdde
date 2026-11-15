const std = @import("std");
const fake_provider = @import("adapters/provider/fake_llm_provider.zig");
const operation = @import("domain/llm_provider_operation.zig");
const Fixture = @import("provider_authorization_test_fixture.zig").Fixture;

test "actual fake-provider usage may overshoot and prevents another API call" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var tokens = @import("application/workflow_token_accounting_runner.zig").Runner.init(std.testing.allocator, .{ .value = 14 });
    defer tokens.deinit();
    var fake = makeFake(&fixture);
    fake.invocation_plan = .{ .complete = .{ .content = "{}", .input_tokens = 10, .output_tokens = 5 } };
    try tokens.check();
    const inference = try fixture.startInference();
    try tokens.check();
    var response = try fake.interface().invoke(&fixture.provider_binding, &fixture.request, inference.reference, inference.invoked);
    defer response.deinit();
    const actual = response.completed.raw_result.complete.usage;
    try std.testing.expectError(error.WorkflowTokenBudgetExceeded, tokens.reconcile(.initial, inference.invoked.id, .{ .exact_usage = actual }));
    try std.testing.expectEqual(@as(u128, 15), tokens.current().committed());
    try std.testing.expectError(error.WorkflowTokenBudgetExceeded, tokens.check());
    try std.testing.expectEqual(@as(usize, 1), fake.invocation_call_count);
}

test "provider request rejects malformed identity content and controls" {
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
    invalid.controls.temperatures = null;
    try std.testing.expect(!invalid.matchesBinding(fixture.provider_binding));
}

test "fake provider rejects an incoherent request before a simulated send" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const inference = try fixture.startInference();
    var fake = makeFake(&fixture);
    const invalid_utf8 = [_]u8{0xff};
    const invalid_content = [_]operation.ModelVisibleContent{.{ .user = &invalid_utf8 }};
    var request = fixture.request;
    request.content = &invalid_content;
    var result = try fake.interface().invoke(&fixture.provider_binding, &request, inference.reference, inference.invoked);
    defer result.deinit();
    try expectFailure(result, .request_rejected, .not_sent);
    try std.testing.expectEqual(@as(usize, 1), fake.invocation_call_count);
    try std.testing.expectEqual(@as(usize, 0), fake.effect_count);
    try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
}

test "provider cancellation stays distinct and destroys its consumed authorization" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var fake = makeFake(&fixture);
    fake.invocation_plan = .cancelled;
    const inference = try fixture.startInference();
    try std.testing.expectError(error.Cancelled, fake.interface().invoke(&fixture.provider_binding, &fixture.request, inference.reference, inference.invoked));
    try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
}

test "fake provider preserves valid usage on invalid text and rejects inconsistent usage" {
    const invalid_utf8 = [_]u8{0xff};
    const cases = [_]struct { plan: fake_provider.CompletePlan, cause: operation.ProviderFailureCause }{
        .{ .plan = .{ .content = &invalid_utf8, .input_tokens = 10, .output_tokens = 1 }, .cause = .response_invalid },
        .{ .plan = .{ .content = "{}", .input_tokens = std.math.maxInt(u64), .output_tokens = 1 }, .cause = .response_invalid },
    };
    for (cases) |case| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        var fake = makeFake(&fixture);
        fake.invocation_plan = .{ .complete = case.plan };
        const inference = try fixture.startInference();
        var result = try fake.interface().invoke(&fixture.provider_binding, &fixture.request, inference.reference, inference.invoked);
        defer result.deinit();
        if (case.plan.input_tokens == 10) {
            try std.testing.expectEqual(.invalid_content, result.completed.raw_result.rejected.reason);
            try std.testing.expectEqual(@as(u64, 11), result.completed.raw_result.rejected.usage.total_tokens);
        } else try expectFailure(result, case.cause, .response_received);
        try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
    }
}

test "fake provider allocation failures destroy consumed authorization and owned results" {
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(allocationCase, .{});
}

fn allocationCase(allocator: std.mem.Allocator) !void {
    var fixture: Fixture = undefined;
    try fixture.init(allocator);
    defer fixture.deinit();
    var fake = makeFake(&fixture);
    fake.allocator = allocator;
    const inference = try fixture.startInference();
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
        .invocation_plan = .{ .complete = .{ .content = "{}", .input_tokens = 10, .output_tokens = 1 } },
    };
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
