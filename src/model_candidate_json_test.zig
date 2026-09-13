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

// Independent wire fixtures: these values are authored from the contracts, never
// synthesized from schema nodes or encoded by the codec being tested.
const response_wire = struct {
    const id = "{\"ordinal\":7}";
    const provenance = "{\"claim_ids\":[" ++ id ++ "],\"citation_ids\":[" ++ id ++ "],\"clarification_response_ids\":[]}";
    const segments = "[{\"kind\":\"literal\",\"value\":\"Display the status\"},{\"kind\":\"passive\",\"passive_literal_id\":" ++ id ++ "}]";
    const nodes = "[{\"kind\":\"literal\",\"value\":\"Source meaning\"},{\"kind\":\"passive\",\"passive_literal_id\":" ++ id ++ "},{\"kind\":\"source\",\"source_id\":" ++ id ++ "}]";
    const normalized = "{\"kind\":\"normalized\",\"segments\":" ++ segments ++ "}";
    const exact = "{\"kind\":\"exact_copy\",\"token_id\":" ++ id ++ ",\"citation_id\":" ++ id ++ "}";
    const attributed = "{\"value\":" ++ normalized ++ ",\"provenance\":" ++ provenance ++ "}";
    const selection = "{\"first\":{\"ordinal\":7},\"last\":{\"ordinal\":9}}";
    const classifications = "[{\"kind\":\"preserve\",\"preserve\":{\"token_candidate_id\":{\"source_id\":" ++ id ++ ",\"extractor_id\":\"markdown_inline_code_v1\",\"ordinal\":7},\"kind\":\"business_exact_string\"}},{\"kind\":\"irrelevant\",\"source_id\":" ++ id ++ ",\"extractor_id\":\"markdown_inline_code_v1\",\"ordinal\":9}]";
    const clarification = "{\"kind\":\"clarification\",\"reason\":\"ambiguous\",\"question\":" ++ attributed ++ "}";
    const records = .{
        .{ "acceptance_criterion", "{\"kind\":\"acceptance_criterion\",\"given\":" ++ normalized ++ ",\"when\":" ++ normalized ++ ",\"then\":" ++ exact ++ "}" },
        .{ "user_visible_outcome", "{\"kind\":\"user_visible_outcome\",\"text\":" ++ normalized ++ "}" },
        .{ "edge_case", "{\"kind\":\"edge_case\",\"condition\":" ++ normalized ++ ",\"expected_outcome\":" ++ exact ++ "}" },
        .{ "functional_requirement", "{\"kind\":\"functional_requirement\",\"text\":" ++ normalized ++ "}" },
        .{ "business_rule", "{\"kind\":\"business_rule\",\"text\":" ++ exact ++ "}" },
        .{ "assumption", "{\"kind\":\"assumption\",\"text\":" ++ normalized ++ "}" },
        .{ "non_goal", "{\"kind\":\"non_goal\",\"text\":" ++ normalized ++ "}" },
        .{ "prohibited_behavior", "{\"kind\":\"prohibited_behavior\",\"text\":" ++ normalized ++ "}" },
        .{ "entity", "{\"kind\":\"entity\",\"name\":" ++ normalized ++ ",\"business_meaning\":" ++ normalized ++ ",\"relationships\":[" ++ exact ++ "]}" },
    };
};

test "independent wire cases cover every selected specification result and nested content variant" {
    inline for (.{ "business", "scope_guard", "design", "technical", "validation", "implementation_assumption", "open_question" }) |kind| {
        const content = "{\"kind\":\"" ++ kind ++ "\"," ++ (if (comptime std.mem.eql(u8, kind, "business") or std.mem.eql(u8, kind, "scope_guard")) "\"segments\":" ++ response_wire.segments else "\"nodes\":" ++ response_wire.nodes) ++ "}";
        try checkCandidate("extraction", null, "{\"kind\":\"claims\",\"claims\":[{\"content\":" ++ content ++ ",\"citations\":[" ++ response_wire.selection ++ "]}],\"token_classifications\":" ++ response_wire.classifications ++ "}");
        try checkCandidate("reconciliation", "summary", "{\"member_claim_ids\":[" ++ response_wire.id ++ "],\"member_summary_ids\":[],\"statements\":[{\"local_key\":7,\"claim_ids\":[" ++ response_wire.id ++ "],\"content\":{\"kind\":\"model\",\"model\":" ++ content ++ "}}]}");
        try checkCandidate("reconciliation", "global", "{\"claim_dispositions\":[{\"claim_id\":" ++ response_wire.id ++ ",\"disposition\":\"retained\",\"related_claim_ids\":[]}],\"signals\":[{\"claim_ids\":[" ++ response_wire.id ++ "],\"citation_ids\":[" ++ response_wire.id ++ "],\"content\":{\"kind\":\"model\",\"model\":" ++ content ++ "}}],\"conflicts\":[]}");
    }
    try checkCandidate("extraction", null, "{\"kind\":\"no_feature_claim\",\"reason\":{\"nodes\":" ++ response_wire.nodes ++ "},\"token_classifications\":[]}");
    try checkCandidate("extraction", "classification_replacement", "{\"token_classifications\":" ++ response_wire.classifications ++ "}");
    try checkCandidate("extraction", "citation_replacement", "{\"citations\":[" ++ response_wire.selection ++ "]}");
    try checkCandidate("extraction", "source_selection_replacement", response_wire.selection);
    try checkCandidate("reconciliation", "summary", "{\"member_claim_ids\":[" ++ response_wire.id ++ "],\"member_summary_ids\":[],\"statements\":[{\"local_key\":7,\"claim_ids\":[" ++ response_wire.id ++ "],\"content\":{\"kind\":\"preserved_token\",\"token_id\":" ++ response_wire.id ++ "}}]}");
    try checkCandidate("reconciliation", "global", "{\"claim_dispositions\":[],\"signals\":[{\"claim_ids\":[" ++ response_wire.id ++ "],\"citation_ids\":[" ++ response_wire.id ++ "],\"content\":{\"kind\":\"preserved_token\",\"token_id\":" ++ response_wire.id ++ "}}],\"conflicts\":[{\"claim_ids\":[" ++ response_wire.id ++ ",{\"ordinal\":9}],\"citation_ids\":[" ++ response_wire.id ++ "],\"kind\":\"value_mismatch\",\"summary\":{\"nodes\":" ++ response_wire.nodes ++ "},\"resolution\":\"unresolved\"}]}");
    // Structural conformance is not a claim that these independently shaped
    // records satisfy the graph, source-join or semantic validators.
    try checkCandidate("generation", "brief", "{\"kind\":\"brief\",\"title\":" ++ response_wire.attributed ++ ",\"description\":" ++ response_wire.attributed ++ ",\"primary_goal\":" ++ response_wire.attributed ++ "}");
    try checkCandidate("generation", "primary_user_story", "{\"kind\":\"primary_user_story\",\"value\":" ++ response_wire.exact ++ ",\"provenance\":" ++ response_wire.provenance ++ "}");
    try checkCandidate("generation", "entities", "{\"kind\":\"entities\",\"disposition\":\"not_applicable\",\"basis\":" ++ response_wire.attributed ++ "}");
    inline for (.{ "brief", "primary_user_story", "entities" }) |selection| try checkCandidate("generation", selection, response_wire.clarification);
    inline for (response_wire.records) |record| {
        const bytes = "{\"content\":" ++ record[1] ++ ",\"provenance\":" ++ response_wire.provenance ++ "}";
        try checkCandidate("generation", record[0], "{\"kind\":\"records\",\"records\":[" ++ bytes ++ "]}");
        try checkCandidate("generation", record[0], response_wire.clarification);
        try checkCandidate("repair", "record_" ++ record[0], bytes);
    }
    try checkCandidate("repair", "attributed", response_wire.attributed);
    try checkCandidate("repair", "attributed", "{\"value\":" ++ response_wire.exact ++ ",\"provenance\":" ++ response_wire.provenance ++ "}");
    try checkCandidate("support", null, "{\"entries\":[{\"requirement_ordinal\":7,\"finding\":\"supported\",\"disposition\":\"supported\",\"provenance\":" ++ response_wire.provenance ++ "},{\"requirement_ordinal\":9,\"finding\":\"unsupported\",\"disposition\":\"not_applicable\",\"provenance\":{\"claim_ids\":[],\"citation_ids\":[],\"clarification_response_ids\":[]}}]}");
}

fn checkCandidate(comptime name: []const u8, comptime selection: ?[]const u8, bytes: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/" ++ name ++ ".schema.json", a, .limited(@import("domain/model_result_schema.zig").max_bytes));
    var adapter: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try adapter.compiler().compile(a, source);
    const selected = if (selection) |definition| schema.select(.{ .bytes = definition }) orelse return error.MissingSchemaSelection else schema;
    try @import("model_payload_schema_test.zig").checkDocument(selected.modelBytes(), .{ .bytes = bytes });
    if (comptime std.mem.eql(u8, name, "extraction")) {
        if (comptime selection) |definition| {
            const T = @import("domain/reference_extraction_repair.zig").Replacement;
            _ = try codec.decodeSelected(T, a, if (std.mem.eql(u8, definition, "classification_replacement")) .classifications else if (std.mem.eql(u8, definition, "citation_replacement")) .citations else .citation, bytes);
        } else _ = try codec.decode(@import("domain/reference_extraction_parser.zig").Response, a, bytes);
    } else if (comptime std.mem.eql(u8, name, "reconciliation")) {
        _ = try codec.decodeSelected(@FieldType(@import("domain/reference_reconciliation.zig").Parsed, "proposal"), a, if (std.mem.eql(u8, selection.?, "summary")) .summary else .global, bytes);
    } else if (comptime std.mem.eql(u8, name, "repair")) {
        _ = try codec.decodeSelected(@import("domain/specification_repair.zig").Replacement, a, if (std.mem.eql(u8, selection.?, "attributed")) .attributed else .record, bytes);
    } else if (comptime std.mem.eql(u8, name, "generation")) {
        _ = try codec.decode(@import("domain/specification_generation.zig").ModelResponse, a, bytes);
    } else _ = try codec.decode(@import("domain/specification_support.zig").Review, a, bytes);
}

test "explicit null and empty struct alternatives retain their closed native wire contracts" {
    const Value = struct { optional: ?u32, choice: union(enum) { retained: struct {}, selected: struct { target: u32 } } };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const value = try codec.decode(Value, a, "{\"choice\":{\"kind\":\"retained\"}, \"optional\":null}");
    try std.testing.expect(value.optional == null);
    try std.testing.expect(value.choice == .retained);
    for ([_][]const u8{ "{\"choice\":{\"kind\":\"retained\"}}", "{\"optional\":null,\"choice\":{\"kind\":\"retained\",\"target\":7}}", "{\"optional\":null,\"choice\":{}}" }) |bytes| try std.testing.expectError(error.InvalidJsonDocument, codec.decode(Value, a, bytes));
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
