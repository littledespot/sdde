//! Offline preparation through native assignment and handoff owners.
//! No provider dispatch or generated-output authority.
const std = @import("std");

pub fn check(a: std.mem.Allocator, packet: *const @import("../domain/model_input_packet.zig").Packet, schema: *const @import("../domain/model_result_schema.zig").Schema, selected_output: []const u8, wrapped_output: []const u8) !void {
    const handoff = @import("../domain/model_request_handoff.zig");
    const fields = @import("../domain/model_text_field.zig");
    const strict = @import("../domain/strict_json.zig");
    const schemas = @import("../domain/model_result_schema.zig");
    const payload = @import("../domain/model_payload_schema.zig");
    var base: @import("../provider_authorization_test_fixture.zig").Fixture = undefined;
    try base.init(std.testing.allocator);
    defer base.deinit();
    const original = try a.dupe(u8, packet.body());
    const selection: handoff.Selection = .{ .binding = base.provider_binding, .prompt = .{ .id = .{ .bytes = "repair-prompt" }, .content = .{ .prompt = "Repair the assigned native field." } }, .protocol_prompt = null, .result = .{ .id = .{ .bytes = "repair-result" }, .content = .{ .result_schema = schema } }, .input = .{ .packet = packet }, .result_selection = .input };
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
    const selected = try strict.parse(a, selected_output, .{ .maximum_depth = schemas.max_json_depth }, false, null);
    const wrapped = try strict.parse(a, wrapped_output, .{ .maximum_depth = schemas.max_json_depth }, false, null);
    try std.testing.expect(payload.validateValue(@import("../domain/model_envelope.zig").value(&selected.value), actual.response_schema.root()) == null);
    try std.testing.expect(payload.validateValue(@import("../domain/model_envelope.zig").value(&wrapped.value), actual.response_schema.root()) != null);
    const body = (try strict.parse(a, request.input().?, .{ .maximum_depth = schemas.max_json_depth }, false, null)).value;
    try std.testing.expectEqual(packet.fieldPolicies().len, body.object.get("field_rules").?.array.items.len);
    try std.testing.expectEqualStrings(original, packet.body());
}
