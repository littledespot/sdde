const std = @import("std");
const action = @import("actions/model/validate_provider_invocation_observation.zig");
const validation = @import("domain/provider_invocation_validation.zig");
const provider = @import("domain/llm_provider_operation.zig");
const preparation = @import("domain/model_request_preparation.zig");
const build_request = @import("actions/model/build_model_request.zig");
const preflight = @import("actions/model/validate_static_model_request_capacity.zig");

const Fixture = @import("provider_invocation_test_fixture.zig").Fixture;

test "fake response validation retains exact call authority without copying content or mutating accounting" {
    var fixture: Fixture = undefined;
    try fixture.init(40);
    defer fixture.deinit();
    fixture.fake.invocation_plan = .{ .complete = .{ .content = "{}", .input_tokens = 1_000_000, .output_tokens = 500_000, .provider_latency_ms = 7 } };
    var response = try fixture.response();
    defer response.deinit();
    const original = response;
    const ledger = fixture.base.ledger();
    const attempts = fixture.base.attempts.current();
    var owned = try (action.Action{}).execute(std.testing.allocator, fixture.call, &response);
    defer owned.deinit();
    const evidence = owned.evidence;
    const candidate = evidence.result().complete;
    try std.testing.expect(candidate.association() == evidence);
    try std.testing.expect(evidence.request() == fixture.prepared.request);
    try std.testing.expect(evidence.request().response_schema == fixture.resource.content.result_schema);
    try std.testing.expect(evidence.request().model_visible_input_id.eql(fixture.prepared.request.model_visible_input_id));
    try std.testing.expect(evidence.operationId().eql(fixture.authorized.invoked.id));
    try std.testing.expect(candidate.content().ptr == response.completed.raw_result.complete.content.bytes.ptr);
    try std.testing.expectEqualStrings("{}", candidate.content());
    try std.testing.expectEqual(@as(u64, 1_500_000), evidence.usage().?.total_tokens);
    try std.testing.expectEqual(@as(?u32, 7), evidence.providerLatencyMs());
    try std.testing.expectEqual(provider.ProviderDeliveryDisposition.response_received, evidence.delivery());
    try std.testing.expectEqualDeep(original, response);
    try std.testing.expect(ledger == fixture.base.ledger());
    try std.testing.expect(attempts == fixture.base.attempts.current());
    try std.testing.expectEqual(@as(usize, 0), fixture.fake.count_call_count);
    try std.testing.expectEqual(@as(usize, 1), fixture.fake.invocation_call_count);
    try std.testing.expectEqual(@as(usize, 1), fixture.base.preloader.destroyed_count);
}

test "all provider stops preserve usage and expose no decoder candidate" {
    inline for (std.enums.values(provider.ProviderNonCandidateStopReason)) |reason| {
        var fixture: Fixture = undefined;
        try fixture.init(40);
        defer fixture.deinit();
        fixture.fake.invocation_plan = .{ .stopped = .{ .reason = reason, .input_tokens = std.math.maxInt(u64), .output_tokens = 0 } };
        var response = try fixture.response();
        defer response.deinit();
        var owned = try (action.Action{}).execute(std.testing.allocator, fixture.call, &response);
        defer owned.deinit();
        try std.testing.expectEqual(reason, owned.evidence.result().stopped);
        try std.testing.expectEqual(std.math.maxInt(u64), owned.evidence.usage().?.total_tokens);
        try std.testing.expectEqual(provider.ProviderDeliveryDisposition.response_received, owned.evidence.delivery());
        try std.testing.expect(owned.evidence.providerLatencyMs() == null);
    }
}

test "provider failure causes retry facts and delivery are preserved without fabricated usage" {
    inline for (std.enums.values(provider.ProviderFailureCause)) |cause| {
        inline for (std.enums.values(provider.ProviderRetryClass)) |retry| {
            inline for (std.enums.values(provider.ProviderDeliveryDisposition)) |delivery| {
                if (cause == .request_limit_exceeded and delivery != .not_sent) continue;
                var fixture: Fixture = undefined;
                try fixture.init(40);
                defer fixture.deinit();
                fixture.fake.invocation_plan = .{ .failed = .{ .cause = cause, .retry_class = retry, .delivery = delivery } };
                var response = try fixture.response();
                defer response.deinit();
                var owned = try (action.Action{}).execute(std.testing.allocator, fixture.call, &response);
                defer owned.deinit();
                try std.testing.expectEqualDeep(response.failed, owned.evidence.result().failed);
                try std.testing.expectEqual(delivery, owned.evidence.delivery());
                try std.testing.expect(owned.evidence.usage() == null);
                try std.testing.expect(owned.evidence.providerLatencyMs() == null);
                try std.testing.expectEqual(@as(usize, 1), fixture.fake.invocation_call_count);
            }
        }
    }
}

test "cancellation remains outside invocation observations and destroys the single-use lease" {
    var fixture: Fixture = undefined;
    try fixture.init(40);
    defer fixture.deinit();
    fixture.fake.invocation_plan = .cancelled;
    try std.testing.expectError(error.Cancelled, fixture.response());
    try std.testing.expectEqual(@as(usize, 1), fixture.fake.invocation_call_count);
    try std.testing.expectEqual(@as(usize, 1), fixture.base.preloader.destroyed_count);
    try std.testing.expect(!@hasField(validation.Result, "cancelled"));
    try std.testing.expect(!@hasField(provider.ProviderFailureCause, "cancelled"));
}

test "validation accepts bounded UTF8 without interpreting JSON model claims or echoed IDs" {
    for ([_][]const u8{ "", "not JSON", "```json\n{}\n```", "{\"status\":\"approved\"}", "{\"requestId\":\"another-request\"}" }) |content| {
        var fixture: Fixture = undefined;
        try fixture.init(40);
        defer fixture.deinit();
        var response = try rawComplete(&fixture, content);
        defer response.deinit();
        var owned = try (action.Action{}).execute(std.testing.allocator, fixture.call, &response);
        defer owned.deinit();
        try std.testing.expectEqualStrings(content, owned.evidence.result().complete.content());
        try std.testing.expect(owned.evidence.request().model_request_id == fixture.base.model_request_id);
    }
}

test "unsafe response content becomes a failure with retained actual usage and no candidate" {
    const invalid_utf8 = [_]u8{0xff};
    const exact = [_]u8{'x'} ** 40;
    const oversized = [_]u8{'x'} ** 41;
    for ([_][]const u8{ &exact, &oversized, &invalid_utf8 }, 0..) |bytes, index| {
        var fixture: Fixture = undefined;
        try fixture.init(40);
        defer fixture.deinit();
        var response = try rawComplete(&fixture, bytes);
        defer response.deinit();
        var owned = try (action.Action{}).execute(std.testing.allocator, fixture.call, &response);
        defer owned.deinit();
        if (index == 0) {
            try std.testing.expectEqualStrings(&exact, owned.evidence.result().complete.content());
        } else {
            const failure = owned.evidence.result().failed;
            try std.testing.expectEqual(if (index == 1) provider.ProviderFailureCause.response_limit_exceeded else .response_invalid, failure.cause);
            try std.testing.expectEqual(provider.ProviderRetryClass.never, failure.retry_class);
            try std.testing.expectEqual(provider.ProviderDeliveryDisposition.response_received, failure.delivery);
            try std.testing.expect(failure.operation_id.eql(fixture.call.operation_id));
        }
        try std.testing.expectEqual(@as(u64, 12), owned.evidence.usage().?.total_tokens);
        try std.testing.expectEqualStrings(bytes, response.completed.raw_result.complete.content.bytes);
        var tokens = @import("application/workflow_token_accounting_runner.zig").Runner.init(std.testing.allocator, .{ .value = 11 });
        defer tokens.deinit();
        try std.testing.expectEqual(@as(u128, 0), tokens.current().committed());
        try std.testing.expectError(error.WorkflowTokenBudgetExceeded, tokens.reconcile(.initial, owned.evidence.operationId(), .{ .exact_usage = owned.evidence.usage().? }));
        try std.testing.expectEqual(@as(u128, 12), tokens.current().committed());
        try std.testing.expectError(error.WorkflowTokenBudgetExceeded, tokens.check());
    }
}

test "malformed usage rejects both complete and stopped observations without mutation" {
    var fixture: Fixture = undefined;
    try fixture.init(40);
    defer fixture.deinit();
    var response = try fixture.response();
    defer response.deinit();
    inline for (.{ false, true }) |stopped| {
        for ([_]provider.ProviderUsage{
            .{ .input_tokens = 10, .output_tokens = 2, .total_tokens = 11 },
            .{ .input_tokens = 10, .output_tokens = 2, .total_tokens = 13 },
            .{ .input_tokens = std.math.maxInt(u64), .output_tokens = 1, .total_tokens = 0 },
        }) |usage| {
            var wrong = response;
            if (stopped) {
                wrong.completed.raw_result = .{ .stopped = .{
                    .request_id = fixture.base.model_request_id,
                    .binding_id = fixture.base.provider_binding.bindingId(),
                    .reason = .output_limit,
                    .usage = usage,
                    .provider_latency_ms = null,
                } };
            } else wrong.completed.raw_result.complete.usage = usage;
            const original = wrong;
            try std.testing.expectError(error.InvalidProviderTokenUsage, (action.Action{}).execute(std.testing.allocator, fixture.call, &wrong));
            try std.testing.expectEqualDeep(original, wrong);
        }
    }
}

test "foreign request binding operation kind and attempt observations reject before evidence allocation" {
    var fixture: Fixture = undefined;
    try fixture.init(40);
    defer fixture.deinit();
    var other: Fixture = undefined;
    try other.init(40);
    defer other.deinit();
    var response = try fixture.response();
    defer response.deinit();
    inline for (0..7) |variant| {
        var wrong = response;
        switch (variant) {
            0 => wrong.completed.operation_id.model_request_id = other.base.model_request_id,
            1 => wrong.completed.operation_id.kind = .input_token_count,
            2 => wrong.completed.operation_id.model_attempt_ordinal.value += 1,
            3 => wrong.completed.raw_result.complete.request_id = other.base.model_request_id,
            4 => wrong.completed.raw_result.complete.binding_id.registry_entry_id.ordinal += 1,
            5 => wrong.completed.raw_result.complete.binding_id.slot_id.bytes = "another-slot",
            6 => wrong.completed.raw_result.complete.binding_id.operation_id.workflow_version += 1,
            else => unreachable,
        }
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
        try std.testing.expectError(error.ProviderInvocationAssociationInvalid, (action.Action{}).execute(failing.allocator(), fixture.call, &wrong));
    }
    const stopped: provider.ProviderInvocationObservation = .{ .completed = .{
        .operation_id = fixture.call.operation_id,
        .raw_result = .{ .stopped = .{
            .request_id = other.base.model_request_id,
            .binding_id = fixture.base.provider_binding.bindingId(),
            .reason = .context_limit,
            .usage = provider.ProviderUsage.init(0, 0, 0).?,
            .provider_latency_ms = null,
        } },
    } };
    try std.testing.expectError(error.ProviderInvocationAssociationInvalid, (action.Action{}).execute(std.testing.allocator, fixture.call, &stopped));
    const failure: provider.ProviderInvocationObservation = .{ .failed = .{
        .operation_id = other.call.operation_id,
        .cause = .transport_failed,
        .retry_class = .policy_eligible,
        .delivery = .accepted_or_unknown,
    } };
    try std.testing.expectError(error.ProviderInvocationAssociationInvalid, (action.Action{}).execute(std.testing.allocator, fixture.call, &failure));
}

test "retained operation ledger rejects substituted input binding and unavailable lifecycle authority" {
    var fixture: Fixture = undefined;
    try fixture.init(40);
    defer fixture.deinit();
    var other: Fixture = undefined;
    try other.init(40);
    defer other.deinit();
    var response = try fixture.response();
    defer response.deinit();
    var wrong = fixture.call;
    wrong.operations = other.base.ledger();
    try std.testing.expectError(error.InvalidProviderInvocationContext, (action.Action{}).execute(std.testing.allocator, wrong, &response));
    wrong = fixture.call;
    wrong.preflight = other.call.preflight;
    try std.testing.expectError(error.InvalidProviderInvocationContext, (action.Action{}).execute(std.testing.allocator, wrong, &response));
    var source = try fixture.requestSource();
    source.model_visible_input_id.bytes = "different-input";
    var substituted = try (build_request.Action{}).execute(std.testing.allocator, source, fixture.prepared.request.content);
    defer substituted.deinit();
    wrong = fixture.call;
    wrong.preflight = try (preflight.Action{}).execute(source, substituted.request);
    try std.testing.expectError(error.InvalidProviderInvocationContext, (action.Action{}).execute(std.testing.allocator, wrong, &response));
    var different_binding = fixture.base.provider_binding;
    different_binding.slot_id.bytes = "other-slot";
    wrong = fixture.call;
    wrong.provider_binding = &different_binding;
    try std.testing.expectError(error.InvalidProviderInvocationContext, (action.Action{}).execute(std.testing.allocator, wrong, &response));
    try fixture.base.change(.inference, .{ .terminate = .completed });
    wrong = fixture.call;
    wrong.operations = fixture.base.ledger();
    try std.testing.expectError(error.InvalidProviderInvocationContext, (action.Action{}).execute(std.testing.allocator, wrong, &response));
}

test "request wire-limit rejection cannot claim sent delivery" {
    var fixture: Fixture = undefined;
    try fixture.init(40);
    defer fixture.deinit();
    inline for (.{ .response_received, .accepted_or_unknown }) |delivery| {
        const response: provider.ProviderInvocationObservation = .{ .failed = .{
            .operation_id = fixture.call.operation_id,
            .cause = .request_limit_exceeded,
            .retry_class = .never,
            .delivery = delivery,
        } };
        try std.testing.expectError(error.InvalidProviderDeliveryDisposition, (action.Action{}).execute(std.testing.allocator, fixture.call, &response));
    }
}

test "evidence allocation failure and cleanup never consume or free the raw response" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}

fn allocationCase(allocator: std.mem.Allocator) !void {
    var fixture: Fixture = undefined;
    try fixture.init(40);
    defer fixture.deinit();
    var response = try fixture.response();
    defer response.deinit();
    const bytes = response.completed.raw_result.complete.content.bytes;
    var owned = (action.Action{}).execute(allocator, fixture.call, &response) catch |err| {
        try std.testing.expectEqualStrings("{}", bytes);
        return err;
    };
    owned.deinit();
    try std.testing.expectEqualStrings("{}", response.completed.raw_result.complete.content.bytes);
}

fn rawComplete(fixture: *Fixture, bytes: []const u8) !provider.ProviderInvocationObservation {
    return .{
        .completed = .{
            .operation_id = fixture.call.operation_id,
            .raw_result = .{
                .complete = .{
                    .request_id = fixture.base.model_request_id,
                    .binding_id = fixture.base.provider_binding.bindingId(),
                    // Deliberately bypass the constructor to model a faulty adapter.
                    .content = .{ .allocator = std.testing.allocator, .bytes = try std.testing.allocator.dupe(u8, bytes) },
                    .usage = provider.ProviderUsage.init(10, 2, 12).?,
                    .provider_latency_ms = null,
                },
            },
        },
    };
}
