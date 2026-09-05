const std = @import("std");
const build = @import("actions/model/build_model_request.zig");
const validate = @import("actions/model/validate_static_model_request_capacity.zig");
const preparation = @import("domain/model_request_preparation.zig");
const provider = @import("domain/llm_provider_operation.zig");
const compilation = @import("domain/workflow_compilation.zig");
const fake_provider = @import("adapters/provider/fake_llm_provider.zig");
const Fixture = @import("provider_authorization_test_fixture.zig").Fixture;

test "request construction is deterministic minimal and preserves immutable authorities" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const resource = resultResource(&fixture);
    const selected = try source(&fixture, &resource);
    const content = [_]provider.ModelVisibleContent{
        .{ .system = "Return one object." },
        .{ .guidance = "Keep the declared fields." },
        .{ .user = "Describe this item." },
        .{ .evidence = "A café opens at eight.\n" },
    };
    const ledger = fixture.requests.ledger().?;
    const attempts = fixture.attempts.current();
    var first = try (build.Action{}).execute(std.testing.allocator, selected, &content);
    defer first.deinit();
    var second = try (build.Action{}).execute(std.testing.allocator, selected, &content);
    defer second.deinit();
    const evidence = try (validate.Action{}).execute(selected, first.request);
    try std.testing.expect(evidence.request() == first.request);
    try std.testing.expect(first.request != second.request);
    try std.testing.expectEqualDeep(first.request.*, second.request.*);
    try std.testing.expect(first.request.model_request_id == fixture.model_request_id);
    try std.testing.expect(first.request.response_schema == resource.content.result_schema);
    try std.testing.expectEqualStrings(resource.id.bytes, first.request.result_schema_id.bytes);
    try std.testing.expectEqualDeep(@as([]const provider.ModelVisibleContent, &content), first.request.content);
    for (first.request.content) |part| {
        try std.testing.expect(std.mem.indexOf(u8, part.bytes(), "epoch-1") == null);
        try std.testing.expect(std.mem.indexOf(u8, part.bytes(), "input-1") == null);
        try std.testing.expect(std.mem.indexOf(u8, part.bytes(), "request.test/v1") == null);
        try std.testing.expect(std.mem.indexOf(u8, part.bytes(), resource.content.result_schema.bytes()) == null);
    }
    try std.testing.expect(fixture.requests.ledger().? == ledger);
    try std.testing.expect(fixture.attempts.current() == attempts);
    try std.testing.expectEqual(@as(u64, 0), fixture.ledger().revision().value);
    try std.testing.expectEqual(@as(usize, 0), fixture.preloader.prepared_count);
}

test "prepared request owns transient content and IDs without cloning graph or ledger authority" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const resource = resultResource(&fixture);
    var selected = try source(&fixture, &resource);
    var input = [_]u8{ 'i', 'n', 'p', 'u', 't' };
    var schema_id = [_]u8{ 'r', 'e', 'q' };
    var text = [_]u8{ 'd', 'a', 't', 'a' };
    var content = [_]provider.ModelVisibleContent{.{ .evidence = &text }};
    selected.request_schema_id.bytes = &schema_id;
    selected.model_visible_input_id.bytes = &input;
    var owned = try (build.Action{}).execute(std.testing.allocator, selected, &content);
    defer owned.deinit();
    _ = try (validate.Action{}).execute(selected, owned.request);
    @memset(&input, 'x');
    @memset(&schema_id, 'x');
    @memset(&text, 'x');
    content[0] = .{ .user = "replaced" };
    try std.testing.expectEqualStrings("input", owned.request.model_visible_input_id.bytes);
    try std.testing.expectEqualStrings("req", owned.request.request_schema_id.bytes);
    try std.testing.expectEqualStrings("data", owned.request.content[0].evidence);
    try std.testing.expect(owned.request.response_schema == resource.content.result_schema);
    try owned.request.validate();
}

test "builder rejects malformed content and identities before allocating content" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const resource = resultResource(&fixture);
    const selected = try source(&fixture, &resource);
    const invalid_utf8 = [_]u8{0xff};
    const oversized = [_]u8{'x'} ** 256;
    const cases = [_][]const provider.ModelVisibleContent{
        &.{},
        &.{.{ .user = "" }},
        &.{.{ .guidance = &invalid_utf8 }},
        &.{.{ .evidence = &oversized }},
    };
    for (cases) |content| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
        try std.testing.expectError(error.InvalidProviderNeutralModelRequest, (build.Action{}).execute(failing.allocator(), selected, content));
    }
    inline for (.{ false, true }) |input_identity| {
        var invalid = selected;
        if (input_identity) invalid.model_visible_input_id.bytes = "" else invalid.request_schema_id.bytes = "";
        try std.testing.expectError(error.InvalidProviderNeutralModelRequest, (build.Action{}).execute(std.testing.allocator, invalid, fixture.request.content));
    }
}

test "input byte safety includes the exact schema and all content roles without truncation" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const resource = resultResource(&fixture);
    const selected = try source(&fixture, &resource);
    const content = [_]provider.ModelVisibleContent{ .{ .system = "a" }, .{ .guidance = "b" }, .{ .user = "é" }, .{ .evidence = "d" } };
    const exact: u32 = @intCast(resource.bytes().len + 5);
    fixture.provider_binding.capacity.canonical.maximum_input_bytes = exact;
    var owned = try (build.Action{}).execute(std.testing.allocator, selected, &content);
    defer owned.deinit();
    _ = try (validate.Action{}).execute(selected, owned.request);
    fixture.provider_binding.capacity.canonical.maximum_input_bytes -= 1;
    try std.testing.expectError(error.InvalidProviderNeutralModelRequest, (build.Action{}).execute(std.testing.allocator, selected, &content));
    try std.testing.expectEqual(@as(usize, 2), owned.request.content[2].user.len);
}

test "only a compiled result-schema resource can supply the request schema" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var resource = resultResource(&fixture);
    const selected = try source(&fixture, &resource);
    var owned = try (build.Action{}).execute(std.testing.allocator, selected, fixture.request.content);
    defer owned.deinit();
    inline for (.{ .prompt, .example, .data }) |kind| {
        resource.content = @unionInit(@FieldType(compilation.CompiledResource, "content"), @tagName(kind), "{}");
        try std.testing.expectError(error.InvalidModelRequestSource, (build.Action{}).execute(std.testing.allocator, selected, fixture.request.content));
        try std.testing.expectError(error.InvalidModelRequestSource, (validate.Action{}).execute(selected, owned.request));
    }
    resource = resultResource(&fixture);
    resource.id.bytes = "";
    try std.testing.expectError(error.InvalidModelRequestSource, (build.Action{}).execute(std.testing.allocator, selected, fixture.request.content));
}

test "static preflight rejects foreign request input and schema associations" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var other: Fixture = undefined;
    try other.init(std.testing.allocator);
    defer other.deinit();
    const resource = resultResource(&fixture);
    const selected = try source(&fixture, &resource);
    var owned = try (build.Action{}).execute(std.testing.allocator, selected, fixture.request.content);
    defer owned.deinit();
    inline for (0..5) |variant| {
        var wrong = owned.request.*;
        switch (variant) {
            0 => wrong.model_request_id = other.model_request_id,
            1 => wrong.request_schema_id.bytes = "another-request/v1",
            2 => wrong.result_schema_id.bytes = "another-result",
            3 => wrong.response_schema = other.request.response_schema,
            4 => wrong.model_visible_input_id.bytes = "another-input",
            else => unreachable,
        }
        try std.testing.expectError(error.ModelRequestAssociationInvalid, (validate.Action{}).execute(selected, &wrong));
    }
    var wrong_binding = fixture.provider_binding;
    wrong_binding.operation_id.workflow_version += 1;
    var invalid = selected;
    invalid.provider_binding = &wrong_binding;
    try std.testing.expectError(error.InvalidProviderNeutralModelRequest, (build.Action{}).execute(std.testing.allocator, invalid, fixture.request.content));
}

test "static preflight rejects divergent binding controls modes and safety bounds" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const resource = resultResource(&fixture);
    const selected = try source(&fixture, &resource);
    var owned = try (build.Action{}).execute(std.testing.allocator, selected, fixture.request.content);
    defer owned.deinit();
    inline for (0..6) |variant| {
        var wrong = owned.request.*;
        switch (variant) {
            0 => wrong.binding_id.registry_entry_id.ordinal += 1,
            1 => wrong.binding_id.slot_id.bytes = "another-slot",
            2 => wrong.controls.temperature = null,
            3 => wrong.response_guidance_mode = .native_schema,
            4 => wrong.limits.maximum_input_bytes += 1,
            5 => wrong.limits.maximum_output_bytes += 1,
            else => unreachable,
        }
        try std.testing.expectError(error.ModelRequestCapacityInvalid, (validate.Action{}).execute(selected, &wrong));
    }
    var wrong = owned.request.*;
    wrong.limits.maximum_output_bytes = 0;
    try std.testing.expectError(error.InvalidProviderNeutralModelRequest, (validate.Action{}).execute(selected, &wrong));
    fixture.registry_entry.capabilities.temperature = false;
    try std.testing.expectError(error.ModelRequestCapacityInvalid, (validate.Action{}).execute(selected, owned.request));
    fixture.registry_entry.capabilities.temperature = true;
    fixture.provider_binding.response_mode = .native_schema;
    var unsupported = try (build.Action{}).execute(std.testing.allocator, selected, fixture.request.content);
    defer unsupported.deinit();
    try std.testing.expectError(error.ModelRequestCapacityInvalid, (validate.Action{}).execute(selected, unsupported.request));
}

test "prepared request reaches fake inference without counting or preparation side effects" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    fixture.registry_entry.capabilities.input_token_count = false;
    fixture.registry_entry.capabilities.exact_token_counter = .unavailable;
    const resource = resultResource(&fixture);
    const selected = try source(&fixture, &resource);
    var owned = try (build.Action{}).execute(std.testing.allocator, selected, fixture.request.content);
    defer owned.deinit();
    const validated = try (validate.Action{}).execute(selected, owned.request);
    var fake: fake_provider.FakeLLMProvider = .{
        .allocator = std.testing.allocator,
        .authorization_leases = fixture.leasePort(),
        .count_plan = .{ .counted = 0 },
        .invocation_plan = .{ .complete = .{ .content = "{}", .input_tokens = 1_000_000, .output_tokens = 500_000 } },
    };
    try std.testing.expectEqual(@as(usize, 0), fixture.preloader.prepared_count);
    try std.testing.expectEqual(@as(usize, 0), fake.effect_count);
    fixture.request = validated.request().*;
    const inference = try fixture.startInference();
    var response = try fake.interface().invoke(&fixture.provider_binding, validated.request(), inference.reference, inference.invoked);
    defer response.deinit();
    try std.testing.expectEqualStrings("{}", response.completed.raw_result.complete.content.bytes);
    try std.testing.expectEqual(@as(u64, 1_500_000), response.completed.raw_result.complete.usage.total_tokens);
    try std.testing.expectEqual(@as(usize, 0), fake.count_call_count);
    try std.testing.expectEqual(@as(usize, 1), fake.effect_count);
    try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
}

test "request construction releases every partial allocation without changing source authority" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}

fn allocationCase(allocator: std.mem.Allocator) !void {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const resource = resultResource(&fixture);
    const selected = try source(&fixture, &resource);
    var owned = try (build.Action{}).execute(allocator, selected, fixture.request.content);
    defer owned.deinit();
    _ = try (validate.Action{}).execute(selected, owned.request);
    try std.testing.expectEqual(@as(u64, 0), fixture.ledger().revision().value);
    try std.testing.expectEqual(@as(usize, 0), fixture.preloader.prepared_count);
}

fn resultResource(fixture: *const Fixture) compilation.CompiledResource {
    return .{ .id = .{ .bytes = "result" }, .content = .{ .result_schema = fixture.request.response_schema } };
}

fn source(fixture: *Fixture, resource: *const compilation.CompiledResource) !preparation.Source {
    const request_id = fixture.model_request_id;
    return .{
        .request_binding = try fixture.requests.validate(fixture.requests.ledger().?.revision(), request_id, request_id.immutable_unit_owner_id, request_id.model_operation_id, request_id.purpose),
        .provider_binding = &fixture.provider_binding,
        .request_schema_id = fixture.request.request_schema_id,
        .model_visible_input_id = fixture.request.model_visible_input_id,
        .result_resource = resource,
    };
}
