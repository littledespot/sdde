const std = @import("std");
const invoke = @import("actions/model/invoke_model.zig");
const binding = @import("domain/llm_provider_binding.zig");
const operation = @import("domain/llm_provider_operation.zig");
const provider_port = @import("ports/llm_provider_interface.zig");
const Fixture = @import("provider_invocation_test_fixture.zig").Fixture;

test "invoke action forwards exact request binding authorization and applied operation once" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    fixture.fake.invocation_plan = .{ .complete = .{ .content = "not JSON", .input_tokens = 1_000_000, .output_tokens = 500_000, .provider_latency_ms = 7 } };
    var spy: Spy = .{ .inner = fixture.fake.interface() };
    const action: invoke.Action = .{ .provider = spy.port() };
    const request = fixture.prepared.request.*;
    const ledger = fixture.base.ledger();
    const attempts = fixture.base.attempts.current();
    const applied = try ledger.requireInvoked(fixture.authorized.invoked.id);
    var response = try action.execute(&fixture.base.provider_binding, fixture.prepared.request, fixture.authorized.reference, applied);
    defer response.deinit();
    const received = spy.received.?;
    try std.testing.expect(received.provider_binding == &fixture.base.provider_binding);
    try std.testing.expect(received.request == fixture.prepared.request);
    try std.testing.expect(received.authorization == fixture.authorized.reference);
    try std.testing.expect(received.invoked == applied);
    try std.testing.expectEqual(@as(usize, 1), spy.invoke_calls);
    try std.testing.expectEqual(@as(usize, 0), spy.count_calls);
    const complete = response.completed.raw_result.complete;
    try std.testing.expect(complete.content.bytes.ptr == spy.returned_content.?.ptr);
    try std.testing.expectEqualStrings("not JSON", complete.content.bytes);
    try std.testing.expect(complete.request_id == request.model_request_id);
    try std.testing.expect(complete.binding_id.eql(request.binding_id));
    try std.testing.expect(response.completed.operation_id.eql(applied.id));
    try std.testing.expectEqual(@as(u64, 1_500_000), complete.usage.total_tokens);
    try std.testing.expectEqual(@as(?u32, 7), complete.provider_latency_ms);
    try std.testing.expectEqualDeep(request, fixture.prepared.request.*);
    try std.testing.expect(ledger == fixture.base.ledger());
    try std.testing.expect(attempts == fixture.base.attempts.current());
    try expectCalls(&fixture, 1, 1);
    try std.testing.expectEqual(@as(usize, 1), fixture.base.preloader.destroyed_count);
}

test "invoke action preserves every failure fact without retry or reinterpretation" {
    inline for (std.enums.values(operation.ProviderFailureCause)) |cause| {
        inline for (std.enums.values(operation.ProviderRetryClass)) |retry| {
            inline for (std.enums.values(operation.ProviderDeliveryDisposition)) |delivery| {
                var fixture: Fixture = undefined;
                try fixture.init();
                defer fixture.deinit();
                fixture.fake.invocation_plan = .{ .failed = .{ .cause = cause, .retry_class = retry, .delivery = delivery } };
                var response = try fixture.response();
                defer response.deinit();
                try std.testing.expectEqualDeep(operation.ProviderFailure{
                    .operation_id = fixture.authorized.invoked.id,
                    .cause = cause,
                    .retry_class = retry,
                    .delivery = delivery,
                }, response.failed);
                // Even inconsistent adapter facts belong to the separate
                // observation validator; invocation never rewrites them.
                try expectCalls(&fixture, 1, 1);
                try std.testing.expectEqual(@as(usize, 1), fixture.base.preloader.destroyed_count);
            }
        }
    }
}

test "invoke action preserves all stops and usage without manufacturing candidate content" {
    inline for (std.enums.values(operation.ProviderNonCandidateStopReason)) |reason| {
        var fixture: Fixture = undefined;
        try fixture.init();
        defer fixture.deinit();
        fixture.fake.invocation_plan = .{ .stopped = .{ .reason = reason, .input_tokens = std.math.maxInt(u64), .output_tokens = 0, .provider_latency_ms = 12 } };
        var response = try fixture.response();
        defer response.deinit();
        const stopped = response.completed.raw_result.stopped;
        try std.testing.expectEqual(reason, stopped.reason);
        try std.testing.expect(stopped.request_id == fixture.prepared.request.model_request_id);
        try std.testing.expect(stopped.binding_id.eql(fixture.prepared.request.binding_id));
        try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), stopped.usage.total_tokens);
        try std.testing.expectEqual(@as(?u32, 12), stopped.provider_latency_ms);
        try expectCalls(&fixture, 1, 1);
        try std.testing.expectEqual(@as(usize, 1), fixture.base.preloader.destroyed_count);
    }
}

test "cancellation and allocation errors escape unchanged with no retry and consumed lease cleanup" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const ledger = fixture.base.ledger();
    fixture.fake.invocation_plan = .cancelled;
    try std.testing.expectError(error.Cancelled, fixture.response());
    try expectCalls(&fixture, 1, 1);
    try std.testing.expectEqual(@as(usize, 1), fixture.base.preloader.destroyed_count);
    try std.testing.expect(ledger == fixture.base.ledger());
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}

test "a reused authorization reaches the same port once and cannot cause a second effect" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    var first = try fixture.response();
    defer first.deinit();
    var second = try fixture.response();
    defer second.deinit();
    try std.testing.expectEqual(operation.ProviderFailureCause.authorization_denied, second.failed.cause);
    try std.testing.expectEqual(operation.ProviderRetryClass.never, second.failed.retry_class);
    try std.testing.expectEqual(operation.ProviderDeliveryDisposition.not_sent, second.failed.delivery);
    try expectCalls(&fixture, 2, 1);
    try std.testing.expectEqual(@as(usize, 1), fixture.base.preloader.destroyed_count);
}

test "port rejects substituted binding input operation and lease without an external effect" {
    for (0..4) |case| {
        var fixture: Fixture = undefined;
        try fixture.init();
        defer fixture.deinit();
        var foreign: Fixture = undefined;
        try foreign.init();
        defer foreign.deinit();
        var wrong_binding = fixture.base.provider_binding;
        wrong_binding.slot_id.bytes = "another-slot";
        var wrong_request = fixture.prepared.request.*;
        wrong_request.model_visible_input_id.bytes = "another-input";
        // Identical values do not replace the actual applied ledger record.
        const copied_operation = fixture.authorized.invoked.*;
        const action: invoke.Action = .{ .provider = fixture.fake.interface() };
        var response = try action.execute(
            if (case == 0) &wrong_binding else &fixture.base.provider_binding,
            if (case == 1) &wrong_request else fixture.prepared.request,
            if (case == 3) foreign.authorized.reference else fixture.authorized.reference,
            if (case == 2) &copied_operation else fixture.authorized.invoked,
        );
        defer response.deinit();
        try std.testing.expectEqual(operation.ProviderFailureCause.authorization_denied, response.failed.cause);
        try std.testing.expectEqual(operation.ProviderDeliveryDisposition.not_sent, response.failed.delivery);
        try expectCalls(&fixture, 1, 0);
        try expectCalls(&foreign, 0, 0);
    }
}

test "expired authorization and no-longer-invoked operations cannot produce effects" {
    for ([_]bool{ false, true }) |expired| {
        var fixture: Fixture = undefined;
        try fixture.init();
        defer fixture.deinit();
        if (expired) {
            fixture.base.clock.now_ms = fixture.authorized.invoked.deadline_monotonic_ms;
        } else {
            try fixture.base.change(.inference, .{ .terminate = .{ .cancelled = .not_sent } });
        }
        var response = try fixture.response();
        defer response.deinit();
        try std.testing.expectEqual(if (expired) operation.ProviderFailureCause.timeout else .authorization_denied, response.failed.cause);
        try std.testing.expectEqual(operation.ProviderDeliveryDisposition.not_sent, response.failed.delivery);
        try expectCalls(&fixture, 1, 0);
        try std.testing.expectEqual(@as(usize, 1), fixture.base.preloader.destroyed_count);
    }
}

fn allocationCase(allocator: std.mem.Allocator) !void {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    fixture.fake.allocator = allocator;
    const ledger = fixture.base.ledger();
    var response = fixture.response() catch |err| {
        try expectCalls(&fixture, 1, 1);
        try std.testing.expectEqual(@as(usize, 1), fixture.base.preloader.destroyed_count);
        try std.testing.expect(ledger == fixture.base.ledger());
        return err;
    };
    defer response.deinit();
    try std.testing.expectEqualStrings("{}", response.completed.raw_result.complete.content.bytes);
    try expectCalls(&fixture, 1, 1);
    try std.testing.expectEqual(@as(usize, 1), fixture.base.preloader.destroyed_count);
    try std.testing.expect(ledger == fixture.base.ledger());
}

fn expectCalls(fixture: *const Fixture, invocations: usize, effects: usize) !void {
    try std.testing.expectEqual(invocations, fixture.fake.invocation_call_count);
    try std.testing.expectEqual(@as(usize, 0), fixture.fake.count_call_count);
    try std.testing.expectEqual(effects, fixture.fake.effect_count);
}

// Records borrowed argument/content pointers only; ownership stays with the
// existing fake and the action's caller. This is not a second fake provider.
const Spy = struct {
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

    fn port(self: *Spy) provider_port.LLMProviderInterface {
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
        return self.inner.countInputTokens(provider_binding, request, authorization, invoked);
    }
};
