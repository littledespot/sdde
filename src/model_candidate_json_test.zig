const std = @import("std");
const codec = @import("domain/model_candidate_json.zig");
const Choice = union(enum) {
    count: struct { amount: u32 },
    note: struct { text: []const u8 },
};
const Document = struct { left: Choice, right: Choice, history: []const Choice };
const sample: Document = .{ .left = .{ .count = .{ .amount = 7 } }, .right = .{ .note = .{ .text = "Café" } }, .history = &.{.{ .count = .{ .amount = 9 } }} };

test "reconciliation rejects the observed native union response and accepts the canonical content shapes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/reconciliation.schema.json", a, .limited(@import("domain/model_result_schema.zig").max_bytes));
    const check = @import("model_payload_schema_test.zig").checkDocument;
    const prefix = "{\"member_claim_ids\":[{\"ordinal\":1}],\"member_summary_ids\":[],\"statements\":[{\"local_key\":1,\"claim_ids\":[{\"ordinal\":1}],\"content\":";
    for ([_][]const u8{
        "{\"model\":{\"kind\":\"business\",\"segments\":[{\"kind\":\"literal\",\"value\":\"Display the greeting.\"}]}}",
        "{\"preserved_token\":{\"id\":{\"ordinal\":1},\"kind\":\"business_exact_string\",\"value\":\"Hello, World!\"}}",
    }) |content| try check(schema, .{ .bytes = try std.mem.concat(a, u8, &.{ prefix, content, "}]}" }), .rejection = .missing_required_property, .path = "/statements/0/content/kind" });
    for ([_][]const u8{
        "{\"kind\":\"model\",\"model\":{\"kind\":\"business\",\"segments\":[{\"kind\":\"literal\",\"value\":\"Display the greeting.\"}]}}",
        "{\"kind\":\"preserved_token\",\"token_id\":{\"ordinal\":1}}",
    }) |content| try check(schema, .{ .bytes = try std.mem.concat(a, u8, &.{ prefix, content, "}]}" }) });
}

test "compact model JSON keeps sibling objects intact and round trips native unions" {
    try roundTrip(std.testing.allocator);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "7", "7.0", "70e-1" }) |number| {
        const bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"count\",\"amount\":{s}}}", .{number});
        try std.testing.expectEqual(@as(u32, 7), (try codec.decode(Choice, a, bytes)).count.amount);
    }
    const Collision = union(enum) { selected: struct { kind: enum { business } }, absent: struct { reason: []const u8 } };
    const value: Collision = .{ .selected = .{ .kind = .business } };
    try std.testing.expectEqualDeep(value, try codec.decode(Collision, a, try codec.encode(Collision, a, value)));
}

fn roundTrip(allocator: std.mem.Allocator) !void {
    const wire = try codec.encode(Document, allocator, sample);
    defer allocator.free(wire);
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    try std.testing.expectEqualDeep(sample, try codec.decode(Document, arena.allocator(), wire));
}

test "compact model JSON rejects empty mixed legacy and malformed nested variants" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{
        "{}",                                                             "{\"count\":{\"amount\":7}}",          "{\"kind\":\"count\"}",
        "{\"kind\":\"count\",\"amount\":7,\"text\":\"foreign variant\"}", "{\"kind\":\"unknown\",\"amount\":7}", "{\"kind\":\"count\",\"kind\":\"note\",\"amount\":7}",
        "{\"kind\":\"count\",\"amount\":\"7\"}",                          "{\"kind\":\"count\",\"amount\":7.1}", "{\"kind\":\"count\",\"amount\":-1}",
        "{\"kind\":\"count\",\"amount\":4294967296}",                     "{\"kind\":\"note\",\"text\":[65]}",
    }) |bytes| {
        try std.testing.expectError(error.InvalidJsonDocument, codec.decode(Choice, a, bytes));
        const nested = try std.fmt.allocPrint(a, "{{\"left\":{s},\"right\":{{\"kind\":\"note\",\"text\":\"ok\"}},\"history\":[]}}", .{bytes});
        try std.testing.expectError(error.InvalidJsonDocument, codec.decode(Document, a, nested));
    }
}

test "compact candidate encoding and decoding release every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, roundTrip, .{});
}

test "every specification model schema alternative supplies a native-decodable protocol example" {
    inline for (.{ "extraction", "reconciliation", "generation", "repair", "support" }) |name| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/" ++ name ++ ".schema.json", a, .limited(@import("domain/model_result_schema.zig").max_bytes));
        var adapter: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
        const schema = try adapter.compiler().compile(a, bytes);
        try @import("model_payload_schema_test.zig").checkDocument(bytes, .{ .bytes = "{}", .rejection = .missing_required_property });
        const selections = comptime if (std.mem.eql(u8, name, "reconciliation")) &.{ "summary", "global" } else if (std.mem.eql(u8, name, "generation")) &.{ "brief", "primary_user_story", "entities", "acceptance_criterion", "user_visible_outcome", "edge_case", "functional_requirement", "business_rule", "assumption", "non_goal", "prohibited_behavior", "entity" } else if (std.mem.eql(u8, name, "repair")) &.{ "attributed", "record_acceptance_criterion", "record_user_visible_outcome", "record_edge_case", "record_functional_requirement", "record_business_rule", "record_assumption", "record_non_goal", "record_prohibited_behavior", "record_entity" } else &.{""};
        inline for (selections) |selection| {
            const selected = if (selection.len == 0) schema else schema.select(.{ .bytes = selection }) orelse return error.MissingSchemaSelection;
            const roots = if (selected.root().* == .one_of) selected.root().one_of else &.{selected.root()};
            for (roots) |root| {
                const minimum = try @import("domain/model_protocol_retry.zig").example(a, root);
                const example = try std.json.Stringify.valueAlloc(a, minimum, .{});
                try @import("model_payload_schema_test.zig").checkDocument(selected.modelBytes(), .{ .bytes = example });
                const T = comptime if (std.mem.eql(u8, name, "extraction")) @import("domain/reference_extraction_parser.zig").Response else if (std.mem.eql(u8, name, "reconciliation")) @FieldType(@import("domain/reference_reconciliation.zig").Parsed, "proposal") else if (std.mem.eql(u8, name, "generation")) @import("domain/specification_generation.zig").ModelResponse else if (std.mem.eql(u8, name, "repair")) @import("domain/specification_repair.zig").Replacement else @import("domain/specification_support.zig").Review;
                if (comptime std.mem.eql(u8, name, "reconciliation")) {
                    _ = try codec.decodeSelected(T, a, @field(std.meta.Tag(T), selection), example);
                } else if (comptime std.mem.eql(u8, name, "repair")) {
                    _ = try codec.decodeSelected(T, a, if (std.mem.eql(u8, selection, "attributed")) .attributed else .record, example);
                } else _ = try codec.decode(T, a, example);
            }
        }
    }
}

test "retained variant decoding omits only the root discriminator and rejects legacy or foreign fields" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const value: Choice = .{ .count = .{ .amount = 7 } };
    const bytes = try codec.encodeSelected(Choice, a, value);
    try std.testing.expectEqualStrings("{\"amount\":7}", bytes);
    try std.testing.expectEqualDeep(value, try codec.decodeSelected(Choice, a, .count, bytes));
    for ([_][]const u8{ "{\"kind\":\"count\",\"amount\":7}", "{\"text\":\"foreign\"}", "{\"amount\":7.1}" }) |invalid| {
        try std.testing.expectError(error.InvalidJsonDocument, codec.decodeSelected(Choice, a, .count, invalid));
    }
    const Nested = union(enum) { document: Document, empty: struct {} };
    const nested: Nested = .{ .document = sample };
    try std.testing.expectEqualDeep(nested, try codec.decodeSelected(Nested, a, .document, try codec.encodeSelected(Nested, a, nested)));
}
