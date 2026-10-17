//! Offline preparation through native assignment and handoff owners.
//! In-memory fake provider observations only; no live provider dispatch or
//! generated-output authority.
const std = @import("std");

pub fn check(a: std.mem.Allocator, packet: *const @import("../domain/model_input_packet.zig").Packet, schema: *const @import("../domain/model_result_schema.zig").Schema, selected_output: []const u8, wrapped_output: ?[]const u8) !void {
    const handoff = @import("../domain/model_request_handoff.zig");
    const fields = @import("../domain/model_text_field.zig");
    const strict = @import("../domain/strict_json.zig");
    const schemas = @import("../domain/model_result_schema.zig");
    const payload = @import("../domain/model_payload_schema.zig");
    var base: @import("../provider_authorization_test_fixture.zig").Fixture = undefined;
    try base.init(std.testing.allocator);
    defer base.deinit();
    const original = try a.dupe(u8, packet.body());
    const selection: handoff.Selection = .{ .binding = base.provider_binding, .prompt = .{ .id = .{ .bytes = "repair-prompt" }, .content = .{ .prompt = "Repair the assigned native field." } }, .protocol_prompt = .{ .id = .{ .bytes = "protocol-prompt" }, .content = .{ .prompt = "Correct the complete response within its original assignment." } }, .result = .{ .id = .{ .bytes = "repair-result" }, .content = .{ .result_schema = schema } }, .input = .{ .packet = packet }, .result_selection = .input };
    const id = try base.requests.assign(base.requests.ledger().?.revision(), packet.unit(), base.provider_binding.operation_id, packet.purpose());
    const assigned = try handoff.assign(std.testing.allocator, base.requests.current_owner.?, id, selection);
    defer handoff.destroy(assigned);
    const binding = try base.requests.validate(base.requests.ledger().?.revision(), id, packet.unit(), base.provider_binding.operation_id, packet.purpose());
    const checked = try handoff.validated(assigned, binding);
    defer handoff.destroy(checked);
    var input_id: [32]u8 = undefined;
    var parts: handoff.ContentBuffer = undefined;
    var owned = try @import("../domain/model_request_preparation.zig").build(std.testing.allocator, try checked.buildSource(&input_id), checked.content(&parts));
    const request = handoff.prepared(checked, owned, null) catch |err| {
        owned.deinit();
        return err;
    };
    defer handoff.destroy(request);
    const actual = request.prepared().?;
    try actual.validate();
    try std.testing.expect(fields.same(packet.fieldPolicies(), actual.field_policies));
    try std.testing.expectEqualDeep(packet.originalSources(), actual.original_sources);
    try std.testing.expect(@import("../domain/model_exact_values.zig").same(packet.exactScope(), actual.exact_scope));
    try std.testing.expectEqualDeep(packet.proseFields(), actual.prose_fields);
    const selected = try strict.parse(a, selected_output, .{ .maximum_depth = schemas.max_json_depth }, false, null);
    try std.testing.expect(payload.validateValue(@import("../domain/model_envelope.zig").value(&selected.value), actual.response_schema.root()) == null);
    if (wrapped_output) |bytes| {
        const wrapped = try strict.parse(a, bytes, .{ .maximum_depth = schemas.max_json_depth }, false, null);
        try std.testing.expect(payload.validateValue(@import("../domain/model_envelope.zig").value(&wrapped.value), actual.response_schema.root()) != null);
    }
    const body = (try strict.parse(a, request.input().?, .{ .maximum_depth = schemas.max_json_depth }, false, null)).value;
    const active_count = (try fields.activeBindings(a, actual.response_schema.root(), actual.field_policies)).len;
    if (active_count == 0) {
        try std.testing.expect(!body.object.contains("field_rules"));
    } else try std.testing.expectEqual(active_count, body.object.get("field_rules").?.array.items.len);
    try std.testing.expectEqualStrings(original, packet.body());
    try checkCompositionCorrection(a, &base, checked, request, packet, selected_output);
}

fn checkCompositionCorrection(a: std.mem.Allocator, base: *@import("../provider_authorization_test_fixture.zig").Fixture, checked: *const @import("../domain/model_request_handoff.zig").Request, request: *const @import("../domain/model_request_handoff.zig").Request, packet: *const @import("../domain/model_input_packet.zig").Packet, selected_output: []const u8) !void {
    const fields = @import("../domain/model_text_field.zig");
    const strict = @import("../domain/strict_json.zig");
    const schemas = @import("../domain/model_result_schema.zig");
    const envelope = @import("../domain/model_envelope.zig");
    const actual = request.prepared().?;
    var rejected = try strict.parse(a, selected_output, .{ .maximum_depth = schemas.max_json_depth }, false, null);
    defer rejected.deinit();
    var modified: usize = 0;
    var visited: std.AutoHashMap(*std.json.Value, void) = .init(a);
    defer visited.deinit();
    const active = try fields.activeBindings(a, actual.response_schema.root(), actual.field_policies);
    for (active) |binding| modified += try replaceSelected(a, &rejected.value, binding.path, binding.insertions, packet, &visited);
    for (actual.prose_fields) |binding| {
        const path = try a.alloc(fields.Step, binding.path.len);
        for (binding.path, path) |step, *destination| destination.* = switch (step) {
            .property => |name| .{ .property = name },
            .items => .items,
        };
        modified += try replaceSelected(a, &rejected.value, path, .initEmpty(), packet, &visited);
    }
    try std.testing.expect(modified != 0);
    // These replacements conform to the selected wire schema. Composition,
    // independently of shape/selection, owns their protocol rejection.
    try std.testing.expect(@import("../domain/model_payload_schema.zig").validateValue(envelope.value(&rejected.value), actual.response_schema.root()) == null);
    const bytes = try std.json.Stringify.valueAlloc(a, rejected.value, .{});
    base.model_request_id = actual.model_request_id;
    base.request = actual.*;
    _ = try base.attempts.reserve(base.attempts.current().revision(), base.requests.ledger().?, base.ledger(), base.requests.ledger().?.revision(), base.model_request_id, .initial);
    const authorized = try base.startInference();
    var fake: @import("../adapters/provider/fake_llm_provider.zig").FakeLLMProvider = .{
        .allocator = std.testing.allocator,
        .authorization_leases = base.leasePort(),
        .count_plan = .{ .counted = 0 },
        .invocation_plan = .{ .complete = .{ .content = bytes, .input_tokens = 7, .output_tokens = 3 } },
    };
    var response = try (@import("../actions/model/invoke_model.zig").Action{ .provider = fake.interface() }).execute(&base.provider_binding, actual, authorized.reference, authorized.invoked);
    defer response.deinit();
    var validated = try (@import("../actions/model/validate_provider_invocation_observation.zig").Action{}).execute(std.testing.allocator, .{ .request = actual, .provider_binding = &base.provider_binding, .operations = base.ledger(), .operation_id = authorized.invoked.id }, &response);
    defer validated.deinit();
    var diagnostic: ?envelope.Diagnostic = null;
    defer if (diagnostic) |value| value.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidModelEnvelope, envelope.decode(std.testing.allocator, validated.evidence.result().complete, &diagnostic));
    try std.testing.expectEqual(modified, diagnostic.?.composition.fields.len);
    for (diagnostic.?.composition.fields) |field| try std.testing.expect(field.issue.reason == .reference_only or field.issue.reason == .blank);
    var input_id: [32]u8 = undefined;
    var content: @import("../domain/model_request_handoff.zig").ContentBuffer = undefined;
    var correction = try (@import("../actions/model/build_model_protocol_retry.zig").Action{}).execute(std.testing.allocator, try checked.buildSource(&input_id), checked.content(&content), validated.evidence, .{ .composition = diagnostic.?.composition }, .unconfirmed, request.protocolPrompt().?);
    const corrected_request = @import("../domain/model_request_handoff.zig").prepared(checked, correction, .{ .previous = request, .rejected = validated.evidence, .diagnostic = .{ .composition = diagnostic.?.composition } }) catch |err| {
        correction.deinit();
        return err;
    };
    defer @import("../domain/model_request_handoff.zig").destroy(corrected_request);
    try std.testing.expect(correction.request.model_request_id == actual.model_request_id);
    try std.testing.expect(correction.request.response_schema == actual.response_schema);
    try std.testing.expectEqualDeep(actual.field_policies, correction.request.field_policies);
    try std.testing.expectEqualDeep(actual.prose_fields, correction.request.prose_fields);
    try std.testing.expectEqualDeep(actual.original_sources, correction.request.original_sources);
    try std.testing.expect(@import("../domain/model_exact_values.zig").same(actual.exact_scope, correction.request.exact_scope));
    try std.testing.expectEqualDeep(actual.controls, correction.request.controls);
    try std.testing.expectEqualDeep(actual.content, correction.request.content[0..actual.content.len]);
    try std.testing.expect(corrected_request.packet() == packet);
    try std.testing.expectEqualDeep(packet.repairPermit(), corrected_request.packet().?.repairPermit());
    try std.testing.expectEqual(@as(usize, 1), fake.invocation_call_count);
    try std.testing.expectEqual(@as(u64, 10), validated.evidence.usage().?.total_tokens);
}

fn replaceSelected(a: std.mem.Allocator, value: *std.json.Value, path: []const @import("../domain/model_text_field.zig").Step, offered: @import("../domain/text_field_policy.zig").Insertions, packet: *const @import("../domain/model_input_packet.zig").Packet, visited: *std.AutoHashMap(*std.json.Value, void)) !usize {
    if (path.len == 0) {
        if (value.* != .object and value.* != .string) return 0;
        if ((try visited.getOrPut(value)).found_existing) return 0;
        // Plain-text-only leaves still need nonblank prose. Reference-bearing
        // leaves use a real source choice without inventing a reference ID.
        value.* = if (offered.contains(.source)) source: {
            try std.testing.expect(packet.originalSources().len != 0);
            const bytes = try std.fmt.allocPrint(a, "{{\"fragments\":[{{\"kind\":\"source\",\"source_id\":{d}}}]}}", .{packet.originalSources()[0].source_id.ordinal});
            break :source (try @import("../domain/strict_json.zig").parse(a, bytes, .{ .maximum_depth = 64 }, false, null)).value;
        } else .{ .string = " \t" };
        return 1;
    }
    switch (path[0]) {
        .variant => |kind| if (value.* == .object) {
            const tag = value.object.get("kind") orelse return 0;
            if (tag == .string and std.mem.eql(u8, tag.string, kind)) return replaceSelected(a, value, path[1..], offered, packet, visited);
        },
        .property => |name| if (value.* == .object) {
            if (value.object.getPtr(name)) |child| return replaceSelected(a, child, path[1..], offered, packet, visited);
        },
        .items => if (value.* == .array) {
            var count: usize = 0;
            for (value.array.items) |*child| count += try replaceSelected(a, child, path[1..], offered, packet, visited);
            return count;
        },
    }
    return 0;
}
