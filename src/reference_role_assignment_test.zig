const std = @import("std");
const r = @import("domain/reference_reconciliation.zig");
const roles = @import("domain/reference_role_assignment.zig");
const stage = @import("domain/reference_reconciliation_stage.zig");
const codec = @import("domain/model_candidate_json.zig");
const schema = @import("domain/model_result_schema.zig");
const packets = @import("domain/model_input_packet.zig");

fn unsupported() r.RoleDecisions {
    var result: r.RoleDecisions = undefined;
    inline for (@typeInfo(r.GenerationRole).@"enum".fields) |role| @field(result, role.name) = .{ .unsupported = .{} };
    return result;
}
fn wire(a: std.mem.Allocator, decisions: r.RoleDecisions) ![]const u8 {
    return codec.encodeSelected(stage.Response, a, .{ .roles = .{ .role_decisions = decisions } });
}
fn compiled(a: std.mem.Allocator) !*const schema.Schema {
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/reconciliation.schema.json", a, .limited(schema.max_bytes));
    return (try parser.compiler().compile(a, bytes)).select(.{ .bytes = "roles_assignment" }).?;
}
fn group(id: u32, claims: []const r.ClaimId) roles.Group {
    return .{ .signal_id = .{ .ordinal = id }, .value = .{ .claim_ids = claims, .citation_ids = &.{}, .content = .{ .preserved_token = .{ .token_id = .{ .ordinal = 1 } } }, .generation_roles = &.{} } };
}
const dispositions = [_]r.ClaimDisposition{
    .{ .claim_id = .{ .ordinal = 1 }, .disposition = .retained, .related_claim_ids = &.{} },
    .{ .claim_id = .{ .ordinal = 2 }, .disposition = .retained, .related_claim_ids = &.{} },
    .{ .claim_id = .{ .ordinal = 3 }, .disposition = .superseded, .related_claim_ids = &.{.{ .ordinal = 1 }} },
};
const offered = [_]roles.Group{
    group(23, &.{.{ .ordinal = 1 }}),
    group(17, &.{.{ .ordinal = 2 }}),
    group(29, &.{ .{ .ordinal = 1 }, .{ .ordinal = 3 } }),
};

test "complete role map is tied to registered roles in native and provider schemas" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const selected = try compiled(a);
    const map = schema.findProperty(selected.root().object, "role_decisions").?;
    try std.testing.expect(map.required);
    try std.testing.expectEqual(@typeInfo(r.GenerationRole).@"enum".fields.len, map.schema.object.len);
    const encoded = try wire(a, unsupported());
    _ = try codec.decodeSelected(stage.Response, a, .roles, encoded);
    try @import("model_payload_schema_test.zig").checkDocument(selected.modelBytes(), .{ .bytes = encoded });
    const provider = try std.json.parseFromSlice(std.json.Value, a, try @import("domain/model_schema_projection.zig").render(a, selected, .bedrock), .{});
    const projected = provider.value.object.get("properties").?.object.get("role_decisions").?.object;
    try std.testing.expectEqual(@typeInfo(r.GenerationRole).@"enum".fields.len, projected.get("required").?.array.items.len);
    inline for (@typeInfo(r.GenerationRole).@"enum".fields) |role| {
        try std.testing.expect(schema.findProperty(map.schema.object, role.name).?.required);
        var is_required = false;
        for (projected.get("required").?.array.items) |required| if (std.mem.eql(u8, required.string, role.name)) {
            is_required = true;
        };
        try std.testing.expect(is_required);
        const property = projected.get("properties").?.object.get(role.name).?.object;
        const branches = property.get("anyOf").?.array.items;
        try std.testing.expectEqual(@as(usize, 2), branches.len);
        try std.testing.expectEqual(@as(i64, 1), branches[0].object.get("properties").?.object.get("signal_ids").?.object.get("minItems").?.integer);
        var missing = try std.json.parseFromSlice(std.json.Value, a, encoded, .{});
        try std.testing.expect(missing.value.object.getPtr("role_decisions").?.object.swapRemove(role.name));
        const bytes = try std.json.Stringify.valueAlloc(a, missing.value, .{});
        try std.testing.expectError(error.InvalidJsonDocument, codec.decodeSelected(stage.Response, a, .roles, bytes));
        try @import("model_payload_schema_test.zig").checkDocument(selected.modelBytes(), .{ .bytes = bytes, .rejection = .missing_required_property, .path = try std.fmt.allocPrint(a, "/role_decisions/{s}", .{role.name}) });
    }
}

test "complete role decoder rejects duplicates unknown keys malformed branches and the sparse wire" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const encoded = try wire(a, unsupported());
    for ([_][]const u8{
        "{\"role_assignments\":[]}",
        try std.mem.replaceOwned(u8, a, encoded, "\"title\":", "\"title\":{\"kind\":\"unsupported\"},\"title\":"),
        try std.mem.replaceOwned(u8, a, encoded, "\"title\":", "\"tit\\u006ce\":{\"kind\":\"unsupported\"},\"title\":"),
        try std.mem.replaceOwned(u8, a, encoded, "\"title\":", "\"foreign\":"),
    }) |bad| try std.testing.expectError(error.InvalidJsonDocument, codec.decodeSelected(stage.Response, a, .roles, bad));
    for ([_][]const u8{
        "{}",                                           "null",                                                                        "{\"kind\":\"supported\"}", "{\"kind\":\"unknown\"}",
        "{\"kind\":\"unsupported\",\"signal_ids\":[]}", "{\"kind\":\"supported\",\"signal_ids\":[1],\"reason\":\"MOCK explanation\"}",
    }) |branch| {
        const bad = try std.mem.replaceOwned(u8, a, encoded, "\"title\":{\"kind\":\"unsupported\"}", try std.fmt.allocPrint(a, "\"title\":{s}", .{branch}));
        try std.testing.expectError(error.InvalidJsonDocument, codec.decodeSelected(stage.Response, a, .roles, bad));
    }
}

test "role decision admission preserves many-to-many bindings and native ordering" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var decision = unsupported();
    decision.title = .{ .supported = .{ .signal_ids = &.{ .{ .ordinal = 17 }, .{ .ordinal = 23 } } } };
    decision.records = .{ .supported = .{ .signal_ids = &.{.{ .ordinal = 17 }} } };
    const assignments = (try roles.admit(a, &dispositions, &offered, decision)).valid;
    try std.testing.expectEqual(@as(usize, 2), assignments.len);
    try std.testing.expectEqual(@as(u32, 23), assignments[0].signal_id.ordinal);
    try std.testing.expectEqualSlices(r.GenerationRole, &.{.title}, assignments[0].generation_roles);
    try std.testing.expectEqual(@as(u32, 17), assignments[1].signal_id.ordinal);
    try std.testing.expectEqualSlices(r.GenerationRole, &.{ .title, .records }, assignments[1].generation_roles);
    decision.title.supported.signal_ids = &.{ .{ .ordinal = 23 }, .{ .ordinal = 17 } };
    try std.testing.expectEqualStrings(try codec.encode([]const r.RoleAssignment, a, assignments), try codec.encode([]const r.RoleAssignment, a, (try roles.admit(a, &dispositions, &offered, decision)).valid));
    var reordered = try std.json.parseFromSlice(std.json.Value, a, try wire(a, decision), .{});
    const entries = reordered.value.object.get("role_decisions").?.object;
    var reversed: std.json.ObjectMap = .{};
    for (0..entries.count()) |index| {
        const original = entries.count() - 1 - index;
        try reversed.put(a, entries.keys()[original], entries.values()[original]);
    }
    try reordered.value.object.put(a, "role_decisions", .{ .object = reversed });
    const parsed = try codec.decodeSelected(stage.Response, a, .roles, try std.json.Stringify.valueAlloc(a, reordered.value, .{}));
    try std.testing.expectEqualStrings(try codec.encode([]const r.RoleAssignment, a, assignments), try codec.encode([]const r.RoleAssignment, a, (try roles.admit(a, &dispositions, &offered, parsed.roles.role_decisions)).valid));
    try std.testing.expectEqual(@as(usize, 0), (try roles.admit(a, &dispositions, &offered, unsupported())).valid.len);
}

test "role decision admission rejects empty duplicate foreign and mixed inactive selections" {
    for ([_][]const r.SignalSelectionId{
        &.{},                                         &.{.{ .ordinal = 0 }},  &.{.{ .ordinal = 999 }},
        &.{ .{ .ordinal = 17 }, .{ .ordinal = 17 } }, &.{.{ .ordinal = 29 }},
    }) |selection| {
        var decision = unsupported();
        decision.records = .{ .supported = .{ .signal_ids = selection } };
        try std.testing.expect((try roles.admit(std.testing.allocator, &dispositions, &offered, decision)) == .invalid);
    }
    try std.testing.expectError(error.InvalidReferenceReconciliation, roles.admit(std.testing.allocator, &dispositions, &.{ offered[0], offered[0] }, unsupported()));
}

test "role catalogue restrictions project all roles unsupported when no group is eligible" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try packets.create(std.testing.allocator, "{}", .{ .reference_global = .{ .reference_state_id = .{ .bytes = "MOCK-state" }, .unit_slot_id = .{ .bytes = "MOCK-role-assessment" } } }, .initial_generation, .{ .bytes = "roles_assignment" });
    defer packets.release(base);
    const selected = try compiled(a);
    for ([_][]const roles.Group{ &.{}, offered[2..] }) |catalogue| {
        const packet = try stage.restrictRolePacket(std.testing.allocator, base, &dispositions, catalogue);
        defer packets.release(packet);
        try std.testing.expectEqual(@as(usize, 0), packet.integerChoices().len);
        const restricted = try schema.restrict(std.testing.allocator, selected, packet.excludedVariants(), packet.integerChoices());
        defer restricted.release();
        const map = schema.findProperty(restricted.selected().root().object, "role_decisions").?.schema;
        inline for (@typeInfo(r.GenerationRole).@"enum".fields) |role| {
            const decision = schema.findProperty(map.object, role.name).?.schema;
            try std.testing.expectEqualStrings("unsupported", schema.findProperty(decision.object, "kind").?.schema.constant.string);
            try std.testing.expect(schema.findProperty(decision.object, "signal_ids") == null);
        }
        try @import("model_payload_schema_test.zig").checkDocument(restricted.selected().modelBytes(), .{ .bytes = try wire(a, unsupported()) });
        const provider = try std.json.parseFromSlice(std.json.Value, a, try @import("domain/model_schema_projection.zig").render(a, restricted.selected(), .bedrock), .{});
        inline for (@typeInfo(r.GenerationRole).@"enum".fields) |role| {
            const decision = provider.value.object.get("properties").?.object.get("role_decisions").?.object.get("properties").?.object.get(role.name).?.object;
            try std.testing.expectEqualStrings("unsupported", decision.get("properties").?.object.get("kind").?.object.get("const").?.string);
            var invented = unsupported();
            @field(invented, role.name) = .{ .supported = .{ .signal_ids = &.{.{ .ordinal = 999 }} } };
            const invented_wire = try wire(a, invented);
            try @import("model_payload_schema_test.zig").checkDocument(restricted.selected().modelBytes(), .{ .bytes = invented_wire, .rejection = .unknown_property, .path = try std.fmt.allocPrint(a, "/role_decisions/{s}/signal_ids", .{role.name}) });
            var kind_value = try std.json.parseFromSlice(std.json.Value, a, invented_wire, .{});
            try std.testing.expect(kind_value.value.object.getPtr("role_decisions").?.object.getPtr(role.name).?.object.swapRemove("signal_ids"));
            try @import("model_payload_schema_test.zig").checkDocument(restricted.selected().modelBytes(), .{ .bytes = try std.json.Stringify.valueAlloc(a, kind_value.value, .{}), .rejection = .constant_mismatch, .path = try std.fmt.allocPrint(a, "/role_decisions/{s}/kind", .{role.name}) });
            try std.testing.expect((try roles.admit(a, &dispositions, catalogue, invented)) == .invalid);
        }
    }
}

test "role inversion releases successful rejected and allocation-failure candidates" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, admissionAllocations, .{});
}
fn admissionAllocations(a: std.mem.Allocator) !void {
    var decision = unsupported();
    decision.title = .{ .supported = .{ .signal_ids = &.{ .{ .ordinal = 17 }, .{ .ordinal = 23 } } } };
    decision.records = .{ .supported = .{ .signal_ids = &.{.{ .ordinal = 17 }} } };
    const assignments = (try roles.admit(a, &dispositions, &offered, decision)).valid;
    defer {
        for (assignments) |assignment| a.free(assignment.generation_roles);
        a.free(assignments);
    }
    decision.records.supported.signal_ids = &.{.{ .ordinal = 29 }};
    try std.testing.expect((try roles.admit(a, &dispositions, &offered, decision)) == .invalid);
}
