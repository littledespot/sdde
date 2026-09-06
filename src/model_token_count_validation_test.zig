const std = @import("std");
const action = @import("actions/model/validate_model_token_count_observation.zig");
const count = @import("actions/model/count_model_input_tokens.zig");
const validation = @import("domain/model_token_count_validation.zig");
const provider = @import("domain/llm_provider_operation.zig");
const authorization = @import("provider_authorization_test_fixture.zig");
const Fixture = authorization.Fixture;
const fake_provider = @import("adapters/provider/fake_llm_provider.zig");

test "fake counts validate exact borrowed evidence without limits calls or ledger mutation" {
    for ([_]u64{ 0, 10, std.math.maxInt(u64) }) |input_tokens| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const authorized = try fixture.startCount();
        var fake = makeFake(&fixture);
        fake.count_plan = .{ .counted = input_tokens };
        var response = try observe(&fixture, &fake, authorized);
        const original = response;
        const request = fixture.request;
        const operations = fixture.ledger();
        const requests = fixture.requests.ledger().?;
        const attempts = fixture.attempts.current();
        var tokens = @import("application/workflow_token_accounting_runner.zig").Runner.init(std.testing.allocator, .{ .value = 1 });
        defer tokens.deinit();
        const token_ledger = tokens.current();

        const result = try (action.Action{}).execute(call(&fixture, authorized.invoked.id), &response);
        try std.testing.expectEqualDeep(try provider.ExactInputTokenCountEvidence.fromObservation(response, fixture.request, fixture.provider_binding), result.counted);
        try std.testing.expect(result.counted.count_operation_id.eql(authorized.invoked.id));
        try std.testing.expect(result.counted.count_operation_id.model_request_id == fixture.model_request_id);
        try std.testing.expect(result.counted.model_visible_input_id.bytes.ptr == request.model_visible_input_id.bytes.ptr);
        try std.testing.expect(result.counted.binding_id.slot_id.bytes.ptr == request.binding_id.slot_id.bytes.ptr);
        try std.testing.expectEqual(input_tokens, result.counted.input_tokens);
        try std.testing.expectEqualDeep(original, response);
        try std.testing.expectEqualDeep(request, fixture.request);
        try std.testing.expect(operations == fixture.ledger());
        try std.testing.expect(requests == fixture.requests.ledger().?);
        try std.testing.expect(attempts == fixture.attempts.current());
        try std.testing.expect(token_ledger == tokens.current());
        try std.testing.expectEqual(@as(u128, 0), tokens.current().committed());
        try expectOneCall(&fixture, &fake);

        // Evidence owns its scalar facts, not the observation container; only
        // the original request/binding identity owners must remain alive.
        response.counted.input_tokens = if (input_tokens == 0) 1 else 0;
        try std.testing.expectEqual(input_tokens, result.counted.input_tokens);
    }
}

test "shared count constructor and action retain canonical identities after observation storage is freed" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const authorized = try fixture.startCount();
    var fake = makeFake(&fixture);
    const response = try observe(&fixture, &fake, authorized);
    for ([_]bool{ false, true }) |through_action| {
        const evidence = evidence: {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const allocator = arena.allocator();
            var separate = response;
            const id = &separate.counted.binding_id;
            id.operation_id.workflow_id.bytes = try allocator.dupe(u8, id.operation_id.workflow_id.bytes);
            id.operation_id.workflow_step_id.bytes = try allocator.dupe(u8, id.operation_id.workflow_step_id.bytes);
            id.slot_id.bytes = try allocator.dupe(u8, id.slot_id.bytes);
            id.reasoning_effort = try allocator.dupe(u8, id.reasoning_effort.?);
            separate.counted.model_visible_input_id.bytes = try allocator.dupe(u8, separate.counted.model_visible_input_id.bytes);
            const validated = if (through_action)
                (try (action.Action{}).execute(call(&fixture, authorized.invoked.id), &separate)).counted
            else
                try provider.ExactInputTokenCountEvidence.fromObservation(separate, fixture.request, fixture.provider_binding);
            const canonical = fixture.provider_binding.bindingId();
            try std.testing.expect(validated.binding_id.operation_id.workflow_id.bytes.ptr == canonical.operation_id.workflow_id.bytes.ptr);
            try std.testing.expect(validated.binding_id.operation_id.workflow_step_id.bytes.ptr == canonical.operation_id.workflow_step_id.bytes.ptr);
            try std.testing.expect(validated.binding_id.slot_id.bytes.ptr == canonical.slot_id.bytes.ptr);
            try std.testing.expect(validated.binding_id.reasoning_effort.?.ptr == canonical.reasoning_effort.?.ptr);
            try std.testing.expect(validated.model_visible_input_id.bytes.ptr == fixture.request.model_visible_input_id.bytes.ptr);
            break :evidence validated;
        };
        // The separately allocated observation strings are gone, but the
        // original request/binding owners still back every evidence slice.
        try std.testing.expect(evidence.isValidFor(fixture.request, fixture.provider_binding.bindingId()));
        try std.testing.expectEqual(@as(u64, 10), evidence.input_tokens);
    }
    try expectOneCall(&fixture, &fake);
}

test "count validation preserves every provider failure cause retry class and delivery fact" {
    for (std.enums.values(provider.ProviderFailureCause)) |cause| {
        for (std.enums.values(provider.ProviderRetryClass)) |retry| {
            for (std.enums.values(provider.ProviderDeliveryDisposition)) |delivery| {
                var fixture: Fixture = undefined;
                try fixture.init(std.testing.allocator);
                defer fixture.deinit();
                const authorized = try fixture.startCount();
                var fake = makeFake(&fixture);
                fake.count_plan = .{ .failed = .{ .cause = cause, .retry_class = retry, .delivery = delivery } };
                const response = try observe(&fixture, &fake, authorized);
                const original = response;
                const result = try (action.Action{}).execute(call(&fixture, authorized.invoked.id), &response);
                try std.testing.expectEqualDeep(response.failed, result.failed);
                try std.testing.expectEqualDeep(original, response);
                try expectOneCall(&fixture, &fake);
            }
        }
    }
}

test "count evidence rejects foreign request attempt kind binding and input without modifying the observation" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var foreign: Fixture = undefined;
    try foreign.init(std.testing.allocator);
    defer foreign.deinit();
    const authorized = try fixture.startCount();
    var fake = makeFake(&fixture);
    const response = try observe(&fixture, &fake, authorized);
    const request_copy = fixture.model_request_id.*;
    for (0..10) |variant| {
        var wrong = response;
        switch (variant) {
            0 => wrong.counted.operation_id.kind = .inference,
            1 => wrong.counted.operation_id.model_attempt_ordinal.value += 1,
            2 => wrong.counted.operation_id.model_attempt_ordinal.value = 0,
            3 => wrong.counted.operation_id.model_request_id = &request_copy,
            4 => wrong.counted.operation_id.model_request_id = foreign.model_request_id,
            5 => wrong.counted.binding_id.slot_id.bytes = "another-slot",
            6 => wrong.counted.binding_id.registry_entry_id.ordinal += 1,
            7 => wrong.counted.binding_id.operation_id.workflow_step_id.bytes = "another-step",
            8 => wrong.counted.binding_id.reasoning_effort = null,
            9 => wrong.counted.model_visible_input_id.bytes = "another-input",
            else => unreachable,
        }
        const original = wrong;
        try std.testing.expectError(error.ModelTokenCountAssociationInvalid, (action.Action{}).execute(call(&fixture, authorized.invoked.id), &wrong));
        try std.testing.expectEqualDeep(original, wrong);
    }
    _ = try (action.Action{}).execute(call(&fixture, authorized.invoked.id), &response);
    try expectOneCall(&fixture, &fake);
}

test "foreign failed observations cannot bypass count operation association" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const authorized = try fixture.startCount();
    var fake = makeFake(&fixture);
    fake.count_plan = .{ .failed = .{ .cause = .throttled, .retry_class = .policy_eligible, .delivery = .response_received } };
    const response = try observe(&fixture, &fake, authorized);
    const request_copy = fixture.model_request_id.*;
    for (0..3) |variant| {
        var wrong = response;
        switch (variant) {
            0 => wrong.failed.operation_id.kind = .inference,
            1 => wrong.failed.operation_id.model_attempt_ordinal.value += 1,
            2 => wrong.failed.operation_id.model_request_id = &request_copy,
            else => unreachable,
        }
        try std.testing.expectError(error.ModelTokenCountAssociationInvalid, (action.Action{}).execute(call(&fixture, authorized.invoked.id), &wrong));
    }
    try expectOneCall(&fixture, &fake);
}

test "count validation rejects missing assigned foreign terminal and wrong-kind operation contexts" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var foreign: Fixture = undefined;
    try foreign.init(std.testing.allocator);
    defer foreign.deinit();
    const missing = fixture.ledger();
    try fixture.assignCount();
    const assigned = fixture.ledger();
    const reference = try fixture.prepare(.input_token_count);
    const authorized: authorization.Authorized = .{ .reference = reference, .invoked = try fixture.invoke(.input_token_count) };
    var fake = makeFake(&fixture);
    const response = try observe(&fixture, &fake, authorized);
    const context = call(&fixture, authorized.invoked.id);
    const result = try (action.Action{}).execute(context, &response);
    try fixture.change(.input_token_count, .{ .terminate = .{ .counted = result.counted } });
    for ([_]*const @import("domain/provider_operation_lifecycle.zig").Ledger{ missing, assigned, foreign.ledger(), fixture.ledger() }) |operations| {
        var wrong = context;
        wrong.operations = operations;
        try std.testing.expectError(error.InvalidModelTokenCountContext, (action.Action{}).execute(wrong, &response));
    }
    const inference = try fixture.startInference();
    try std.testing.expectError(error.InvalidModelTokenCountContext, (action.Action{}).execute(call(&fixture, inference.invoked.id), &response));
    var wrong = context;
    wrong.operation_id.model_attempt_ordinal.value += 1;
    try std.testing.expectError(error.InvalidModelTokenCountContext, (action.Action{}).execute(wrong, &response));
    // Validation did not consume the separately prepared inference lease.
    try expectOneCall(&fixture, &fake);
}

test "count validation reuses invocation checks and rejects substituted request binding or input" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const authorized = try fixture.startCount();
    var fake = makeFake(&fixture);
    const response = try observe(&fixture, &fake, authorized);
    const request_copy = fixture.model_request_id.*;
    for (0..10) |variant| {
        var wrong_request = fixture.request;
        var wrong_binding = fixture.provider_binding;
        var wrong_registry = fixture.registry_entry;
        switch (variant) {
            0 => wrong_request.model_request_id = &request_copy,
            1 => wrong_binding.slot_id.bytes = "another-slot",
            2 => wrong_request.model_visible_input_id.bytes = "another-input",
            3 => wrong_request.request_schema_id.bytes = "",
            4 => wrong_request.content = &.{.{ .user = "\xff" }},
            5 => wrong_request.controls.temperature = null,
            6 => {
                wrong_registry.id.ordinal += 1;
                wrong_binding.registry_entry = &wrong_registry;
            },
            7 => {
                // Even mutually matching replacement inputs must match the
                // canonical operation's originally assigned binding.
                wrong_binding.slot_id.bytes = "replacement-slot";
                wrong_request.binding_id = wrong_binding.bindingId();
            },
            8 => {
                wrong_registry.capabilities.input_token_count = false;
                wrong_binding.registry_entry = &wrong_registry;
            },
            9 => {
                wrong_registry.capabilities.exact_token_counter = .unavailable;
                wrong_binding.registry_entry = &wrong_registry;
            },
            else => unreachable,
        }
        var context = call(&fixture, authorized.invoked.id);
        context.request = &wrong_request;
        context.provider_binding = &wrong_binding;
        const original = wrong_request;
        try std.testing.expectError(error.InvalidModelTokenCountContext, (action.Action{}).execute(context, &response));
        try std.testing.expectEqualDeep(original, wrong_request);
    }
    try expectOneCall(&fixture, &fake);
}

test "count validation is independent of expired deadlines consumed leases and token exhaustion" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const authorized = try fixture.startCount();
    var fake = makeFake(&fixture);
    const response = try observe(&fixture, &fake, authorized);
    fixture.clock.now_ms = authorized.invoked.deadline_monotonic_ms;
    fixture.clock.unavailable = true;
    var tokens = @import("application/workflow_token_accounting_runner.zig").Runner.init(std.testing.allocator, .{ .value = 1 });
    defer tokens.deinit();
    try tokens.reconcile(.initial, fixture.id(.inference), .{ .exact_usage = provider.ProviderUsage.init(1, 0, 1).? });
    try std.testing.expectError(error.WorkflowTokenBudgetExceeded, tokens.check());
    const token_ledger = tokens.current();
    const first = try (action.Action{}).execute(call(&fixture, authorized.invoked.id), &response);
    const second = try (action.Action{}).execute(call(&fixture, authorized.invoked.id), &response);
    // Pure validation is repeatable; lifecycle CAS owns one-time completion.
    try std.testing.expectEqualDeep(first, second);
    try std.testing.expect(token_ledger == tokens.current());
    try std.testing.expectEqual(@as(u128, 1), tokens.current().committed());
    try expectOneCall(&fixture, &fake);
}

test "cancelled counting produces no validation observation and has exactly one cleanup owner" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    var active = true;
    defer if (active) fixture.deinit();
    const authorized = try fixture.startCount();
    var fake = makeFake(&fixture);
    fake.count_plan = .cancelled;
    try std.testing.expectError(error.Cancelled, observe(&fixture, &fake, authorized));
    try std.testing.expect(!@hasField(validation.Result, "cancelled"));
    try std.testing.expect(!@hasField(provider.ProviderTokenCountObservation, "cancelled"));
    try expectOneCall(&fixture, &fake);
    fixture.deinit();
    active = false;
    try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
}

fn call(fixture: *Fixture, id: provider.ProviderOperationId) validation.Call {
    return .{ .request = &fixture.request, .provider_binding = &fixture.provider_binding, .operations = fixture.ledger(), .operation_id = id };
}

fn makeFake(fixture: *Fixture) fake_provider.FakeLLMProvider {
    return .{ .allocator = std.testing.allocator, .authorization_leases = fixture.leasePort(), .count_plan = .{ .counted = 10 }, .invocation_plan = .cancelled };
}

fn observe(fixture: *Fixture, fake: *fake_provider.FakeLLMProvider, authorized: authorization.Authorized) @import("ports/llm_provider_interface.zig").Error!provider.ProviderTokenCountObservation {
    return (count.Action{ .provider = fake.interface() }).execute(&fixture.provider_binding, &fixture.request, authorized.reference, authorized.invoked);
}

fn expectOneCall(fixture: *const Fixture, fake: *const fake_provider.FakeLLMProvider) !void {
    try std.testing.expectEqual(@as(usize, 1), fake.count_call_count);
    try std.testing.expectEqual(@as(usize, 1), fake.effect_count);
    try std.testing.expectEqual(@as(usize, 0), fake.invocation_call_count);
    try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
}
