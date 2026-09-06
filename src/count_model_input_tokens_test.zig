const std = @import("std");
const count = @import("actions/model/count_model_input_tokens.zig");
const operation = @import("domain/llm_provider_operation.zig");
const authorization = @import("provider_authorization_test_fixture.zig");
const Fixture = authorization.Fixture;
const Spy = @import("provider_operation_spy_test_fixture.zig").Spy;
const fake_provider = @import("adapters/provider/fake_llm_provider.zig");

test "count action forwards exact pointers and returns the observation without limits or mutation" {
    for ([_]u64{ 0, 10, std.math.maxInt(u64) }) |input_tokens| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const authorized = try fixture.startCount();
        var fake = makeFake(&fixture);
        fake.count_plan = .{ .counted = input_tokens };
        var spy: Spy = .{ .inner = fake.interface() };
        const request = fixture.request;
        const ledger = fixture.ledger();
        const requests = fixture.requests.ledger().?;
        const attempts = fixture.attempts.current();
        const applied = try ledger.requireInvoked(authorized.invoked.id);
        const response = try (count.Action{ .provider = spy.port() }).execute(&fixture.provider_binding, &fixture.request, authorized.reference, applied);
        const received = spy.received.?;
        try std.testing.expect(received.provider_binding == &fixture.provider_binding);
        try std.testing.expect(received.request == &fixture.request);
        try std.testing.expect(received.authorization == authorized.reference);
        try std.testing.expect(received.invoked == applied);
        try std.testing.expectEqual(@as(usize, 1), spy.count_calls);
        try std.testing.expectEqual(@as(usize, 0), spy.invoke_calls);
        try std.testing.expectEqualDeep(spy.returned_count.?, response);
        try std.testing.expect(response.counted.operation_id.eql(applied.id));
        try std.testing.expect(response.counted.binding_id.eql(request.binding_id));
        try std.testing.expect(response.counted.model_visible_input_id.eql(request.model_visible_input_id));
        try std.testing.expectEqual(input_tokens, response.counted.input_tokens);
        try std.testing.expectEqualDeep(request, fixture.request);
        try std.testing.expect(ledger == fixture.ledger());
        try std.testing.expect(requests == fixture.requests.ledger().?);
        try std.testing.expect(attempts == fixture.attempts.current());
        try expectCalls(&fake, 1, 1);
        try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
    }
}

test "count action preserves every failure fact without retry or reinterpretation" {
    for (std.enums.values(operation.ProviderFailureCause)) |cause| {
        for (std.enums.values(operation.ProviderRetryClass)) |retry| {
            for (std.enums.values(operation.ProviderDeliveryDisposition)) |delivery| {
                var fixture: Fixture = undefined;
                try fixture.init(std.testing.allocator);
                defer fixture.deinit();
                const authorized = try fixture.startCount();
                var fake = makeFake(&fixture);
                fake.count_plan = .{ .failed = .{ .cause = cause, .retry_class = retry, .delivery = delivery } };
                const response = try execute(&fixture, &fake, authorized);
                // Observation validation is separate; even inconsistent adapter
                // facts must not be rewritten by the forwarding action.
                try std.testing.expectEqualDeep(operation.ProviderFailure{
                    .operation_id = authorized.invoked.id,
                    .cause = cause,
                    .retry_class = retry,
                    .delivery = delivery,
                }, response.failed);
                try expectCalls(&fake, 1, 1);
                try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
            }
        }
    }
}

test "count cancellation before and during the call remains distinct with one cleanup" {
    for ([_]bool{ false, true }) |before| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        var active = true;
        defer if (active) fixture.deinit();
        const authorized = try fixture.startCount();
        var fake = makeFake(&fixture);
        if (before) fake.authorization_leases.runtime = .{ .status_fn = cancelled } else fake.count_plan = .cancelled;
        const ledger = fixture.ledger();
        try std.testing.expectError(error.Cancelled, execute(&fixture, &fake, authorized));
        try expectCalls(&fake, 1, if (before) 0 else 1);
        try std.testing.expect(ledger == fixture.ledger());
        try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
        fixture.deinit();
        active = false;
        try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
    }
}

test "count action propagates allocation failure without retry or duplicated cleanup" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const authorized = try fixture.startCount();
    var fake = makeFake(&fixture);
    var spy: Spy = .{ .inner = fake.interface(), .count_error = error.OutOfMemory };
    const ledger = fixture.ledger();
    try std.testing.expectError(error.OutOfMemory, (count.Action{ .provider = spy.port() }).execute(&fixture.provider_binding, &fixture.request, authorized.reference, authorized.invoked));
    try std.testing.expectEqual(@as(usize, 1), spy.count_calls);
    try std.testing.expectEqual(@as(usize, 0), spy.invoke_calls);
    try expectCalls(&fake, 1, 1);
    try std.testing.expect(ledger == fixture.ledger());
    try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
}

test "count authorization is single use and cannot produce another effect" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const authorized = try fixture.startCount();
    var fake = makeFake(&fixture);
    const first = try execute(&fixture, &fake, authorized);
    try std.testing.expectEqual(@as(u64, 10), first.counted.input_tokens);
    const second = try execute(&fixture, &fake, authorized);
    try std.testing.expectEqualDeep(operation.ProviderFailure{
        .operation_id = authorized.invoked.id,
        .cause = .authorization_denied,
        .retry_class = .never,
        .delivery = .not_sent,
    }, second.failed);
    try expectCalls(&fake, 2, 1);
    try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
}

test "count port rejects foreign request binding input attempt kind operation and lease" {
    for (0..7) |variant| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        var foreign: Fixture = undefined;
        try foreign.init(std.testing.allocator);
        defer foreign.deinit();
        const authorized = try fixture.startCount();
        const foreign_authorized = try foreign.startCount();
        var fake = makeFake(&fixture);
        var wrong_binding = fixture.provider_binding;
        wrong_binding.slot_id.bytes = "another-slot";
        var wrong_request = fixture.request;
        wrong_request.model_visible_input_id.bytes = "another-input";
        // A copied applied record is not canonical even if its fields match.
        var copied_operation = authorized.invoked.*;
        if (variant == 4) copied_operation.id.model_attempt_ordinal.value += 1;
        if (variant == 5) copied_operation.id.kind = .inference;
        const response = try (count.Action{ .provider = fake.interface() }).execute(
            if (variant == 0) &wrong_binding else &fixture.provider_binding,
            if (variant == 1) &wrong_request else if (variant == 6) &foreign.request else &fixture.request,
            if (variant == 3) foreign_authorized.reference else authorized.reference,
            if (variant == 2 or variant == 4 or variant == 5) &copied_operation else authorized.invoked,
        );
        try std.testing.expectEqual(operation.ProviderFailureCause.authorization_denied, response.failed.cause);
        try std.testing.expectEqual(operation.ProviderDeliveryDisposition.not_sent, response.failed.delivery);
        try expectCalls(&fake, 1, 0);
        try std.testing.expectEqual(@as(usize, 0), foreign.preloader.destroyed_count);
    }
}

test "count deadline boundary unavailable clock and terminal operation cannot produce effects" {
    for (0..4) |variant| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const authorized = try fixture.startCount();
        var fake = makeFake(&fixture);
        switch (variant) {
            0 => fixture.clock.now_ms = authorized.invoked.deadline_monotonic_ms - 1,
            1 => fixture.clock.now_ms = authorized.invoked.deadline_monotonic_ms,
            2 => fixture.clock.unavailable = true,
            3 => try fixture.change(.input_token_count, .{ .terminate = .{ .cancelled = .not_sent } }),
            else => unreachable,
        }
        const ledger = fixture.ledger();
        const response = try execute(&fixture, &fake, authorized);
        if (variant == 0) {
            try std.testing.expectEqual(@as(u64, 10), response.counted.input_tokens);
        } else {
            try std.testing.expectEqual(@as(operation.ProviderFailureCause, if (variant == 1) .timeout else .authorization_denied), response.failed.cause);
            try std.testing.expectEqual(operation.ProviderDeliveryDisposition.not_sent, response.failed.delivery);
        }
        try expectCalls(&fake, 1, if (variant == 0) 1 else 0);
        try std.testing.expect(ledger == fixture.ledger());
        try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
    }
}

test "unsupported explicit count rejects before send and never falls back to inference" {
    for ([_]bool{ false, true }) |count_supported| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        fixture.registry_entry.capabilities.input_token_count = count_supported;
        fixture.registry_entry.capabilities.exact_token_counter = .unavailable;
        const authorized = try fixture.startCount();
        var fake = makeFake(&fixture);
        const response = try execute(&fixture, &fake, authorized);
        try std.testing.expectEqualDeep(operation.ProviderFailure{
            .operation_id = authorized.invoked.id,
            .cause = .request_rejected,
            .retry_class = .never,
            .delivery = .not_sent,
        }, response.failed);
        try expectCalls(&fake, 1, 0);
        try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
    }
}

test "count action cannot use a genuine inference operation as count authority" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const inference = try fixture.startInference();
    var fake = makeFake(&fixture);
    const ledger = fixture.ledger();
    const response = try execute(&fixture, &fake, inference);
    try std.testing.expectEqual(operation.ProviderFailureCause.request_rejected, response.failed.cause);
    try std.testing.expectEqual(operation.ProviderDeliveryDisposition.not_sent, response.failed.delivery);
    try std.testing.expect(response.failed.operation_id.eql(inference.invoked.id));
    try expectCalls(&fake, 1, 0);
    try std.testing.expect(ledger == fixture.ledger());
    try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
}

fn makeFake(fixture: *Fixture) fake_provider.FakeLLMProvider {
    return .{
        .allocator = std.testing.allocator,
        .authorization_leases = fixture.leasePort(),
        .count_plan = .{ .counted = 10 },
        .invocation_plan = .{ .complete = .{ .content = "{}", .input_tokens = 10, .output_tokens = 1 } },
    };
}

fn execute(fixture: *Fixture, fake: *fake_provider.FakeLLMProvider, authorized: authorization.Authorized) @import("ports/llm_provider_interface.zig").Error!operation.ProviderTokenCountObservation {
    return (count.Action{ .provider = fake.interface() }).execute(&fixture.provider_binding, &fixture.request, authorized.reference, authorized.invoked);
}

fn expectCalls(fake: *const fake_provider.FakeLLMProvider, calls: usize, effects: usize) !void {
    try std.testing.expectEqual(calls, fake.count_call_count);
    try std.testing.expectEqual(effects, fake.effect_count);
    try std.testing.expectEqual(@as(usize, 0), fake.invocation_call_count);
}

fn cancelled(_: ?*anyopaque) @import("domain/pipeline.zig").RuntimeStatus {
    return .cancelled;
}
