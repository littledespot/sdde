const std = @import("std");
const fixture_module = @import("provider_authorization_test_fixture.zig");
const Fixture = fixture_module.Fixture;
const operation = @import("domain/llm_provider_operation.zig");
const pipeline = @import("domain/pipeline.zig");
const references = @import("domain/execution_reference.zig");
const preparation = @import("ports/provider_operation_authorization.zig");
const lease = @import("ports/provider_authorization_lease.zig");
const action = @import("actions/model/prepare_provider_operation_authorization.zig");
const fake_provider = @import("adapters/provider/fake_llm_provider.zig");
const envelope_module = @import("application/pipeline_envelope.zig");
const values = @import("application/pipeline_values.zig");
const data = @import("domain/pipeline_data.zig");

test "preparation emits only a typed opaque reference through NodeDelta" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try fixture.assignCount();
    const facts = fixture.facts(.input_token_count);
    const slot = try fixture.operations().authorization_leases.allocate(facts);
    const prepare_action: action.Action = .{ .authorization = fixture.preloader.port() };
    const outcome = try prepare_action.execute(facts, slot, .{});
    try std.testing.expect(outcome == .prepared);
    var delta = outcome.prepared;
    var envelope = envelope_module.PipelineEnvelope.init(&.{preparation.value_schema});
    defer envelope.deinit();
    defer envelope.discard(&delta);
    var writes: usize = 0;
    for (delta.data_writes) |entry| if (entry != null) {
        writes += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), writes);
    try std.testing.expect(delta.runner_accounting_transition == null);
    try std.testing.expectEqual(@as(usize, 0), delta.telemetry_fact_count);
    const view: data.View = .{ .slots = delta.data_writes };
    const ref = try values.read(&view, preparation.value_schema, operation.ValidatedProviderAuthorizationLeaseRef);
    const canonical = try fixture.operations().authorization_leases.canonicalReference(ref.*);
    try std.testing.expect(ref.identity.eql(canonical.identity));
    try std.testing.expectEqual(@as(usize, 1), fixture.preloader.prepared_count);
    try std.testing.expectEqual(@as(usize, 0), fixture.preloader.destroyed_count);
}

test "lease is consumed once and never authorizes a second simulated effect" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const authorized = try fixture.startCount();
    var fake = model(&fixture);
    const first = try fake.interface().countInputTokens(&fixture.provider_binding, &fixture.request, authorized.reference, authorized.invoked);
    try std.testing.expect(first == .counted);
    const second = try fake.interface().countInputTokens(&fixture.provider_binding, &fixture.request, authorized.reference, authorized.invoked);
    try denied(second);
    try std.testing.expectEqual(@as(usize, 1), fake.effect_count);
    try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
}

test "foreign and forged reference identities cannot consume another execution's lease" {
    var first: Fixture = undefined;
    try first.init(std.testing.allocator);
    defer first.deinit();
    var second: Fixture = undefined;
    try second.init(std.testing.allocator);
    defer second.deinit();
    const left = try first.startCount();
    const right = try second.startCount();
    var fake = model(&first);
    try denied(try fake.interface().countInputTokens(&first.provider_binding, &first.request, right.reference, left.invoked));
    const forged: operation.ValidatedProviderAuthorizationLeaseRef = .{ .identity = try references.create(std.testing.allocator) };
    defer forged.identity.release();
    try denied(try fake.interface().countInputTokens(&first.provider_binding, &first.request, &forged, left.invoked));
    try std.testing.expectEqual(@as(usize, 0), fake.effect_count);
    try std.testing.expectEqual(@as(usize, 0), first.preloader.destroyed_count);
    try std.testing.expectEqual(@as(usize, 0), second.preloader.destroyed_count);
}

test "lease rejects copied invocation proof even when every field is equal" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const authorized = try fixture.startCount();
    const copied = authorized.invoked.*;
    try std.testing.expectError(error.AuthorizationDenied, fixture.leasePort().consume(authorized.reference, &fixture.provider_binding, &fixture.request, &copied));
    try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
}

test "assigned operation cannot consume a lease using a manufactured invoked value" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try fixture.assignCount();
    const reference = try fixture.prepare(.input_token_count);
    const invoked = operation.InvokedProviderOperation.init(fixture.id(.input_token_count), 1000, operation.ProviderReceiveBudgets.init(32, 4096, 4096).?).?;
    try std.testing.expectError(error.AuthorizationDenied, fixture.leasePort().consume(reference, &fixture.provider_binding, &fixture.request, &invoked));
    try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
}

test "provider model binding input and deadline mismatches finalize without an effect" {
    for (0..5) |variant| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const authorized = try fixture.startCount();
        var binding = fixture.provider_binding;
        var entry = fixture.registry_entry;
        var request = fixture.request;
        var invoked = authorized.invoked.*;
        switch (variant) {
            0 => {
                entry.provider = .{ .bytes = "different-provider" };
                binding.registry_entry = &entry;
            },
            1 => binding.slot_id = .{ .bytes = "different-slot" },
            2 => request.model_visible_input_id = .{ .bytes = "different-input" },
            3 => invoked.deadline_monotonic_ms += 1,
            4 => {
                entry.model = .{ .bytes = "different-model" };
                binding.registry_entry = &entry;
            },
            else => unreachable,
        }
        try std.testing.expectError(error.AuthorizationDenied, fixture.leasePort().consume(authorized.reference, &binding, &request, if (variant == 3) &invoked else authorized.invoked));
        try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
    }
}

test "deadline is checked again at consume including exact equality" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const authorized = try fixture.startCount();
    fixture.clock.now_ms = 1000;
    var fake = model(&fixture);
    const result = try fake.interface().countInputTokens(&fixture.provider_binding, &fixture.request, authorized.reference, authorized.invoked);
    try std.testing.expect(result == .failed);
    try std.testing.expectEqual(operation.ProviderFailureCause.timeout, result.failed.cause);
    try std.testing.expectEqual(operation.ProviderDeliveryDisposition.not_sent, result.failed.delivery);
    try std.testing.expectEqual(@as(usize, 0), fake.effect_count);
    try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
}

test "cancellation and clock failure release unconsumed capabilities" {
    for (0..2) |variant| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const authorized = try fixture.startCount();
        var port = fixture.leasePort();
        if (variant == 0) port.runtime = .{ .status_fn = cancelled } else fixture.clock.unavailable = true;
        try std.testing.expectError(if (variant == 0) error.Cancelled else error.ClockUnavailable, port.consume(authorized.reference, &fixture.provider_binding, &fixture.request, authorized.invoked));
        try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
    }
}

test "operation terminalization destroys its unused lease before request completion" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const authorized = try fixture.startCount();
    _ = try fixture.change(.input_token_count, .{ .terminate = .{ .cancelled = .not_sent } });
    try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
    try std.testing.expectError(error.AuthorizationDenied, fixture.leasePort().consume(authorized.reference, &fixture.provider_binding, &fixture.request, authorized.invoked));
    try fixture.requests.advance(fixture.requests.ledger().?.revision(), fixture.model_request_id, .invoked, .{ .terminal = .cancelled });
}

test "preparation rejects unassigned duplicate and terminal operations" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var runner = fixture.preparationRunner();
    try std.testing.expect((try runner.prepare(fixture.facts(.input_token_count))) == .failed);
    try std.testing.expectEqual(@as(usize, 0), fixture.preloader.prepare_count);
    try fixture.assignCount();
    _ = try fixture.prepare(.input_token_count);
    try std.testing.expect((try runner.prepare(fixture.facts(.input_token_count))) == .failed);
    _ = try fixture.change(.input_token_count, .{ .terminate = .{ .cancelled = .not_sent } });
    try std.testing.expect((try runner.prepare(fixture.facts(.input_token_count))) == .failed);
    try std.testing.expectEqual(@as(usize, 1), fixture.preloader.prepare_count);
    try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
}

test "preparation failure and cancellation have no successful reference" {
    for (0..3) |variant| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        try fixture.assignCount();
        fixture.preloader.plan = switch (variant) {
            0 => .{ .failed = .authentication_failed },
            1 => .{ .failed = .authorization_denied },
            2 => .cancelled,
            else => unreachable,
        };
        var runner = fixture.preparationRunner();
        const outcome = try runner.prepare(fixture.facts(.input_token_count));
        if (variant == 2) try std.testing.expect(outcome == .cancelled) else {
            try std.testing.expect(outcome == .failed);
            try std.testing.expectEqual(operation.ProviderDeliveryDisposition.not_sent, outcome.failed.delivery);
        }
        try std.testing.expectEqual(@as(usize, 0), fixture.preloader.prepared_count);
        try std.testing.expect((try runner.prepare(fixture.facts(.input_token_count))) == .failed);
    }
}

test "expired and cancelled preparation invokes no authorization adapter" {
    for (0..2) |variant| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        try fixture.assignCount();
        var runner = fixture.preparationRunner();
        if (variant == 0) fixture.clock.now_ms = 1000 else runner.runtime = .{ .status_fn = cancelled };
        const outcome = try runner.prepare(fixture.facts(.input_token_count));
        if (variant == 0) {
            try std.testing.expect(outcome == .failed);
            try std.testing.expectEqual(operation.ProviderFailureCause.timeout, outcome.failed.cause);
        } else try std.testing.expect(outcome == .cancelled);
        try std.testing.expectEqual(@as(usize, 0), fixture.preloader.prepare_count);
    }
}

test "retained stale lease cannot authorize a later execution after table teardown" {
    var first: Fixture = undefined;
    try first.init(std.testing.allocator);
    const issued = first.startCount() catch |err| {
        first.deinit();
        return err;
    };
    const stale: operation.ValidatedProviderAuthorizationLeaseRef = .{ .identity = issued.reference.identity.retain() };
    defer stale.identity.release();
    first.deinit();
    try std.testing.expectEqual(@as(usize, 1), first.preloader.destroyed_count);
    var second: Fixture = undefined;
    try second.init(std.testing.allocator);
    defer second.deinit();
    const current = try second.startCount();
    try std.testing.expectError(error.AuthorizationDenied, second.leasePort().consume(&stale, &second.provider_binding, &second.request, current.invoked));
    var capability = try second.leasePort().consume(current.reference, &second.provider_binding, &second.request, current.invoked);
    capability.deinit();
    try std.testing.expectEqual(@as(usize, 1), second.preloader.destroyed_count);
}

test "failed or expired preparation after deposit releases backing and rejected delta" {
    for (0..3) |variant| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        try fixture.assignCount();
        var spy: PreparationSpy = .{ .fixture = &fixture, .variant = variant };
        var runner = fixture.preparationRunner();
        runner.prepare_action.authorization = .{ .context = @ptrCast(&spy), .prepare_fn = PreparationSpy.prepare };
        const outcome = try runner.prepare(fixture.facts(.input_token_count));
        try std.testing.expect(outcome == .failed);
        try std.testing.expectEqual(@as(usize, 1), fixture.preloader.prepared_count);
        try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
    }
}

test "adapter cannot claim preparation without depositing a capability" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try fixture.assignCount();
    var spy: PreparationSpy = .{ .fixture = &fixture, .variant = 3 };
    var runner = fixture.preparationRunner();
    runner.prepare_action.authorization = .{ .context = @ptrCast(&spy), .prepare_fn = PreparationSpy.prepare };
    try std.testing.expect((try runner.prepare(fixture.facts(.input_token_count))) == .failed);
    try std.testing.expectEqual(@as(usize, 0), fixture.preloader.prepared_count);
}

test "preloaded preparation cannot fill the same slot twice" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try fixture.assignCount();
    const facts = fixture.facts(.input_token_count);
    const slot = try fixture.operations().authorization_leases.allocate(facts);
    try std.testing.expect((try fixture.preloader.port().prepare(facts, slot.deposit)) == .prepared);
    try std.testing.expectError(error.AuthorizationDenied, fixture.preloader.port().prepare(facts, slot.deposit));
    try std.testing.expectEqual(@as(usize, 2), fixture.preloader.prepared_count);
    try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
    fixture.operations().authorization_leases.cancel(slot);
    try std.testing.expectEqual(@as(usize, 2), fixture.preloader.destroyed_count);
}

test "execution teardown releases unused backing but not consumed backing twice" {
    for (0..2) |consume| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        const authorized = fixture.startCount() catch |err| {
            fixture.deinit();
            return err;
        };
        if (consume == 1) {
            var capability = try fixture.leasePort().consume(authorized.reference, &fixture.provider_binding, &fixture.request, authorized.invoked);
            capability.deinit();
        }
        fixture.deinit();
        try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
    }
}

test "authorization preparation and NodeDelta ownership clean every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}

fn allocationCase(allocator: std.mem.Allocator) !void {
    var fixture: Fixture = undefined;
    try fixture.init(allocator);
    defer fixture.deinit();
    const authorized = try fixture.startCount();
    var capability = try fixture.leasePort().consume(authorized.reference, &fixture.provider_binding, &fixture.request, authorized.invoked);
    defer capability.deinit();
}

const PreparationSpy = struct {
    fixture: *Fixture,
    variant: usize,

    fn prepare(context: *preparation.Context, facts: preparation.Facts, slot: preparation.Slot) preparation.Error!preparation.Observation {
        const self: *PreparationSpy = @ptrCast(@alignCast(context));
        if (self.variant == 3) return .prepared;
        _ = try self.fixture.preloader.port().prepare(facts, slot);
        return switch (self.variant) {
            0 => .{ .failed = .authorization_denied },
            1 => error.AuthorizationDenied,
            2 => expired: {
                self.fixture.clock.now_ms = facts.deadline_monotonic_ms;
                break :expired .prepared;
            },
            else => unreachable,
        };
    }
};

fn cancelled(_: ?*anyopaque) pipeline.RuntimeStatus {
    return .cancelled;
}

fn model(fixture: *Fixture) fake_provider.FakeLLMProvider {
    return .{ .allocator = std.testing.allocator, .authorization_leases = fixture.leasePort(), .count_plan = .{ .counted = 10 }, .invocation_plan = .{ .complete = .{ .content = "{}", .output_tokens = 5 } } };
}

fn denied(observation: operation.ProviderTokenCountObservation) !void {
    try std.testing.expect(observation == .failed);
    try std.testing.expectEqual(operation.ProviderFailureCause.authorization_denied, observation.failed.cause);
    try std.testing.expectEqual(operation.ProviderRetryClass.never, observation.failed.retry_class);
    try std.testing.expectEqual(operation.ProviderDeliveryDisposition.not_sent, observation.failed.delivery);
}
