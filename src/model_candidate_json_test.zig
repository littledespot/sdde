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
    const prefix = "{\"statements\":[{\"local_key\":1,\"claim_ids\":[{\"ordinal\":1}],\"content\":";
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
    const provenance = "{\"claim_ids\":[" ++ id ++ "],\"clarification_response_ids\":[]}";
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
        try checkCandidate("reconciliation", "summary", "{\"statements\":[{\"local_key\":7,\"claim_ids\":[" ++ response_wire.id ++ "],\"content\":{\"kind\":\"model\",\"model\":" ++ content ++ "}}]}");
        try checkCandidate("reconciliation", "global", "{\"claim_dispositions\":[{\"claim_id\":" ++ response_wire.id ++ ",\"disposition\":{\"kind\":\"retained\"}}],\"signals\":[{\"claim_ids\":[" ++ response_wire.id ++ "],\"content\":{\"kind\":\"model\",\"model\":" ++ content ++ "}}],\"conflicts\":[]}");
    }
    try checkCandidate("extraction", null, "{\"kind\":\"no_feature_claim\",\"reason\":{\"nodes\":" ++ response_wire.nodes ++ "},\"token_classifications\":[]}");
    try checkCandidate("extraction", "classification_replacement", "{\"token_classifications\":" ++ response_wire.classifications ++ "}");
    try checkCandidate("extraction", "citation_replacement", "{\"citations\":[" ++ response_wire.selection ++ "]}");
    try checkCandidate("extraction", "source_selection_replacement", response_wire.selection);
    try checkCandidate("reconciliation", "summary", "{\"statements\":[{\"local_key\":7,\"claim_ids\":[" ++ response_wire.id ++ "],\"content\":{\"kind\":\"preserved_token\",\"token_id\":" ++ response_wire.id ++ "}}]}");
    try checkCandidate("reconciliation", "global", "{\"claim_dispositions\":[],\"signals\":[{\"claim_ids\":[" ++ response_wire.id ++ "],\"content\":{\"kind\":\"preserved_token\",\"token_id\":" ++ response_wire.id ++ "}}],\"conflicts\":[{\"claim_ids\":[" ++ response_wire.id ++ ",{\"ordinal\":9}],\"kind\":\"value_mismatch\",\"summary\":{\"nodes\":" ++ response_wire.nodes ++ "},\"resolution\":\"unresolved\"}]}");
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
    try checkCandidate("repair", "provenance", response_wire.provenance);
    try checkCandidate("repair", "value", response_wire.exact);
    try checkCandidate("support", "detail", "{\"detail\":\"Which deadline applies?\"}");
    try candidateCase("support", "detail", "{\"detail\":\"Which deadline applies?\",\"finding\":\"supported\"}", .unknown_property, "/finding");
    try checkCandidate("support", "selection", "{\"provenance\":" ++ response_wire.provenance ++ ",\"source_ids\":[]}");
    try checkCandidate("support", "finding", "{\"decision\":\"candidate_omission\",\"loss\":{\"kind\":\"unlocalized\"},\"provenance\":" ++ response_wire.provenance ++ ",\"source_ids\":[],\"detail\":\"Preserve the required confirmation.\"}");
    try checkCandidate("support", null, "{\"entries\":[{\"requirement_ordinal\":7,\"value\":{\"decision\":\"supported\",\"loss\":{\"kind\":\"unlocalized\"},\"provenance\":" ++ response_wire.provenance ++ ",\"source_ids\":[],\"detail\":\"\"}},{\"requirement_ordinal\":9,\"value\":{\"decision\":\"unsupported\",\"loss\":{\"kind\":\"unlocalized\"},\"provenance\":{\"claim_ids\":[],\"clarification_response_ids\":[]},\"source_ids\":[],\"detail\":\"Which deadline applies?\"}}]}");
}

test "support schemas expose applicability only when selected and reject superseded fields" {
    const value = "{\"decision\":\"not_applicable\",\"loss\":{\"kind\":\"unlocalized\"},\"provenance\":" ++ response_wire.provenance ++ ",\"source_ids\":[],\"detail\":\"No business data is involved.\"}";
    const review = "{\"entries\":[{\"requirement_ordinal\":9,\"value\":" ++ value ++ "}]}";
    try checkCandidate("support", "applicability_finding", value);
    try checkCandidate("support", "review_applicability", review);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .limited(@import("domain/model_result_schema.zig").max_bytes));
    var adapter: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try adapter.compiler().compile(a, bytes);
    try std.testing.expect(schema.select(.{ .bytes = "disposition" }) == null);

    inline for (.{ "finding", "review" }) |selection| {
        const selected = schema.select(.{ .bytes = selection }).?;
        // Native decoding represents the full decision union; native admission
        // enforces each requirement's policy after this selected wire schema.
        try @import("model_payload_schema_test.zig").checkDocument(selected.modelBytes(), .{ .bytes = if (std.mem.eql(u8, selection, "finding")) value else review, .rejection = .enum_mismatch, .path = if (std.mem.eql(u8, selection, "finding")) "/decision" else "/entries/0/value/decision" });
    }
    inline for (.{ "finding", "disposition" }) |field| {
        try candidateCase("support", "finding", "{\"decision\":\"unsupported\",\"loss\":{\"kind\":\"unlocalized\"},\"" ++ field ++ "\":\"supported\",\"provenance\":" ++ response_wire.provenance ++ ",\"source_ids\":[],\"detail\":\"The source leaves a decision open.\"}", .unknown_property, "/" ++ field);
    }
}

test "selected source and reconciliation repairs conform to their native response owners" {
    try checkCandidate("extraction", "claim", "{\"content\":{\"kind\":\"business\",\"segments\":" ++ response_wire.segments ++ "},\"citations\":[" ++ response_wire.selection ++ "]}");
    try checkCandidate("extraction", "classification", "{\"kind\":\"irrelevant\",\"source_id\":" ++ response_wire.id ++ ",\"extractor_id\":\"markdown_inline_code_v1\",\"ordinal\":7}");
    try checkCandidate("extraction", "classification", "{\"kind\":\"preserve\",\"preserve\":{\"token_candidate_id\":{\"source_id\":" ++ response_wire.id ++ ",\"extractor_id\":\"markdown_inline_code_v1\",\"ordinal\":7},\"kind\":\"business_exact_string\"}}");
    try checkCandidate("extraction", "business_text_replacement", "{\"segments\":" ++ response_wire.segments ++ "}");
    try checkCandidate("extraction", "reference_text_replacement", "{\"nodes\":" ++ response_wire.nodes ++ "}");
    try checkCandidate("reconciliation", "business_text", "{\"segments\":" ++ response_wire.segments ++ "}");
    try checkCandidate("reconciliation", "reference_text", "{\"nodes\":" ++ response_wire.nodes ++ "}");
    try checkCandidate("reconciliation", "token_reference", "{\"token_id\":" ++ response_wire.id ++ "}");
    try checkCandidate("reconciliation", "repair_key", "{\"local_key\":7}");
    try checkCandidate("reconciliation", "repair_selection", "{\"claim_ids\":[" ++ response_wire.id ++ "]}");
    try checkCandidate("reconciliation", "repair_summary", "{\"nodes\":" ++ response_wire.nodes ++ "}");
    try checkCandidate("reconciliation", "repair_conflict_detail", "{\"kind\":\"scope_mismatch\",\"summary\":{\"nodes\":" ++ response_wire.nodes ++ "}}");
    try checkCandidate("reconciliation", "repair_disposition", "{\"kind\":\"retained\"}");
    inline for (.{ "superseded", "conflicting" }) |kind| try checkCandidate("reconciliation", "repair_disposition", "{\"kind\":\"" ++ kind ++ "\",\"related_claim_ids\":[" ++ response_wire.id ++ "]}");
    try checkCandidate("reconciliation", "repair_disposition", "{\"kind\":\"duplicate\",\"target_claim_id\":" ++ response_wire.id ++ "}");
    try candidateCase("extraction", "claim", "{\"content\":{\"kind\":\"business\",\"segments\":" ++ response_wire.segments ++ "}}", .missing_required_property, "/citations");
    try candidateCase("reconciliation", "business_text", "{\"segments\":" ++ response_wire.segments ++ ",\"claim_ids\":[]}", .unknown_property, "/claim_ids");
}

test "loss attribution wire variants stay closed across initial review insertion and replacement" {
    const locations = .{
        "{\"kind\":\"unlocalized\"}",
        "{\"kind\":\"extraction_claim\",\"bytes\":\"chunk-7\"}",
        "{\"kind\":\"token_classification\",\"source_id\":{\"ordinal\":7},\"extractor_id\":\"markdown_inline_code_v1\",\"ordinal\":9}",
        "{\"kind\":\"reconciliation_signal\",\"ordinal\":7}",
        "{\"kind\":\"reconciliation_disposition\",\"ordinal\":9}",
    };
    try std.testing.expectEqual(@typeInfo(@import("domain/source_omission.zig").Location).@"union".fields.len, locations.len);
    inline for (locations) |location| {
        try checkCandidate("support", "loss", location);
        const value = "{\"decision\":\"candidate_omission\",\"loss\":" ++ location ++ ",\"provenance\":" ++ response_wire.provenance ++ ",\"source_ids\":[" ++ response_wire.id ++ "],\"detail\":\"Preserve the deadline.\"}";
        inline for (.{ "finding", "applicability_finding" }) |selection| try checkCandidate("support", selection, value);
        inline for (.{ "review", "review_applicability" }) |selection| try checkCandidate("support", selection, "{\"entries\":[{\"requirement_ordinal\":7,\"value\":" ++ value ++ "}]}");
    }
    try candidateCase("support", "loss", "{\"kind\":\"unlocalized\",\"value\":null}", .unknown_property, "/value");
    try candidateCase("support", "finding", "{\"decision\":\"candidate_omission\",\"provenance\":" ++ response_wire.provenance ++ ",\"source_ids\":[],\"detail\":\"Preserve the deadline.\"}", .missing_required_property, "/loss");
}

fn checkCandidate(comptime name: []const u8, comptime selection: ?[]const u8, bytes: []const u8) !void {
    return candidateCase(name, selection, bytes, null, null);
}

fn candidateCase(comptime name: []const u8, comptime selection: ?[]const u8, bytes: []const u8, rejection: ?@import("domain/model_payload_schema.zig").Rejection, path: ?[]const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/" ++ name ++ ".schema.json", a, .limited(@import("domain/model_result_schema.zig").max_bytes));
    var adapter: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try adapter.compiler().compile(a, source);
    const selected = if (selection) |definition| schema.select(.{ .bytes = definition }) orelse return error.MissingSchemaSelection else schema;
    try @import("model_payload_schema_test.zig").checkDocument(selected.modelBytes(), .{ .bytes = bytes, .rejection = rejection, .path = path });
    if (rejection != null) {
        try std.testing.expectError(error.InvalidJsonDocument, decodeCandidate(name, selection, a, bytes));
    } else {
        const encoded = try decodeCandidate(name, selection, a, bytes);
        // Both owners must accept the response in both directions. In particular,
        // native union encoding must not introduce a wrapper absent from the schema.
        try @import("model_payload_schema_test.zig").checkDocument(selected.modelBytes(), .{ .bytes = encoded });
        try std.testing.expectEqualStrings(encoded, try decodeCandidate(name, selection, a, encoded));
    }
}

fn nativeWire(comptime T: type, a: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    return codec.encode(T, a, try codec.decode(T, a, bytes));
}

fn selectedWire(comptime T: type, a: std.mem.Allocator, tag: std.meta.Tag(T), bytes: []const u8) ![]const u8 {
    return codec.encodeSelected(T, a, try codec.decodeSelected(T, a, tag, bytes));
}

fn decodeCandidate(comptime name: []const u8, comptime selection: ?[]const u8, a: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    const r = @import("domain/reference_reconciliation.zig");
    if (comptime std.mem.eql(u8, name, "extraction")) {
        if (comptime selection) |definition| {
            if (comptime std.mem.eql(u8, definition, "claim")) return nativeWire(r.extraction.Proposal, a, bytes);
            if (comptime std.mem.eql(u8, definition, "classification")) return nativeWire(r.extraction.tokens.Classification, a, bytes);
            if (comptime std.mem.eql(u8, definition, "business_text_replacement")) return nativeWire(r.text.BusinessText, a, bytes);
            if (comptime std.mem.eql(u8, definition, "reference_text_replacement")) return nativeWire(r.text.ReferenceSemanticText, a, bytes);
            const T = @import("domain/reference_extraction_repair.zig").Replacement;
            return selectedWire(T, a, if (std.mem.eql(u8, definition, "classification_replacement")) .classifications else if (std.mem.eql(u8, definition, "citation_replacement")) .citations else .citation, bytes);
        } else return nativeWire(@import("domain/reference_extraction_parser.zig").Response, a, bytes);
    } else if (comptime std.mem.eql(u8, name, "reconciliation")) {
        const definition = selection.?;
        if (comptime std.mem.eql(u8, definition, "summary") or std.mem.eql(u8, definition, "global")) return selectedWire(@FieldType(r.Parsed, "proposal"), a, @field(std.meta.Tag(@FieldType(r.Parsed, "proposal")), definition), bytes);
        if (comptime std.mem.eql(u8, definition, "business_text")) return nativeWire(r.text.BusinessText, a, bytes);
        if (comptime std.mem.eql(u8, definition, "reference_text")) return nativeWire(r.text.ReferenceSemanticText, a, bytes);
        if (comptime std.mem.eql(u8, definition, "token_reference")) return nativeWire(@FieldType(r.ContentProposal, "preserved_token"), a, bytes);
        const T = @import("domain/reference_reconciliation_repair.zig").Replacement;
        return selectedWire(T, a, @field(std.meta.Tag(T), definition["repair_".len..]), bytes);
    } else if (comptime std.mem.eql(u8, name, "repair")) {
        return selectedWire(@import("domain/specification_repair.zig").Replacement, a, if (std.mem.eql(u8, selection.?, "provenance")) .provenance else if (std.mem.eql(u8, selection.?, "value")) .value else .record, bytes);
    } else if (comptime std.mem.eql(u8, name, "generation")) {
        return nativeWire(@import("domain/specification_generation.zig").ModelResponse, a, bytes);
    } else if (comptime selection != null and !std.mem.startsWith(u8, selection.?, "review")) {
        const selected = selection.?;
        if (comptime std.mem.eql(u8, selected, "loss")) return nativeWire(@import("domain/source_omission.zig").Location, a, bytes);
        const T = @import("domain/specification_support_repair.zig").Replacement;
        return selectedWire(T, a, if (comptime std.mem.eql(u8, selected, "applicability_finding")) .finding else @field(std.meta.Tag(T), selected), bytes);
    } else return nativeWire(@import("domain/specification_support.zig").Review, a, bytes);
}

test "final proposal schemas and native readers reject deterministic echoes and mixed shapes" {
    const echoed = "{\"claim_ids\":[{\"ordinal\":7}],\"citation_ids\":[{\"ordinal\":7}],\"clarification_response_ids\":[]}";
    inline for (.{ "member_claim_ids", "member_summary_ids" }) |field| {
        try candidateCase("reconciliation", "summary", "{\"statements\":[],\"" ++ field ++ "\":[]}", .unknown_property, "/" ++ field);
    }
    try candidateCase("generation", "primary_user_story", "{\"kind\":\"primary_user_story\",\"value\":" ++ response_wire.normalized ++ ",\"provenance\":" ++ echoed ++ "}", .unknown_property, "/provenance/citation_ids");
    try candidateCase("repair", "provenance", echoed, .unknown_property, "/citation_ids");
    try candidateCase("support", null, "{\"entries\":[{\"requirement_ordinal\":7,\"value\":{\"decision\":\"supported\",\"loss\":{\"kind\":\"unlocalized\"},\"provenance\":" ++ echoed ++ ",\"source_ids\":[],\"detail\":\"\"}}]}", .unknown_property, "/entries/0/value/provenance/citation_ids");
    try candidateCase("reconciliation", "global", "{\"claim_dispositions\":[],\"signals\":[{\"claim_ids\":[{\"ordinal\":7}],\"citation_ids\":[],\"content\":{\"kind\":\"preserved_token\",\"token_id\":{\"ordinal\":7}}}],\"conflicts\":[]}", .unknown_property, "/signals/0/citation_ids");
    try candidateCase("reconciliation", "global", "{\"claim_dispositions\":[],\"signals\":[],\"conflicts\":[{\"claim_ids\":[{\"ordinal\":7},{\"ordinal\":9}],\"citation_ids\":[],\"kind\":\"value_mismatch\",\"summary\":{\"nodes\":" ++ response_wire.nodes ++ "},\"resolution\":\"unresolved\"}]}", .unknown_property, "/conflicts/0/citation_ids");
}

test "independent multi-record proposals retain siblings and all disposition variants" {
    const dispositions =
        \\{"claim_dispositions":[{"claim_id":{"ordinal":7},"disposition":{"kind":"retained"}},{"claim_id":{"ordinal":9},"disposition":{"kind":"duplicate","target_claim_id":{"ordinal":7}}},{"claim_id":{"ordinal":11},"disposition":{"kind":"superseded","related_claim_ids":[{"ordinal":7},{"ordinal":9}]}},{"claim_id":{"ordinal":13},"disposition":{"kind":"conflicting","related_claim_ids":[{"ordinal":15}]}},{"claim_id":{"ordinal":15},"disposition":{"kind":"conflicting","related_claim_ids":[{"ordinal":13}]}}],"signals":[],"conflicts":[]}
    ;
    try checkCandidate("reconciliation", "global", dispositions);
    const statements =
        \\{"statements":[{"local_key":7,"claim_ids":[{"ordinal":7}],"content":{"kind":"model","model":{"kind":"business","segments":[{"kind":"literal","value":"Confirm a booking."}]}}},{"local_key":9,"claim_ids":[{"ordinal":9}],"content":{"kind":"model","model":{"kind":"business","segments":[{"kind":"literal","value":"Issue a renewal receipt."}]}}}]}
    ;
    try checkCandidate("reconciliation", "summary", statements);
    const records =
        \\{"kind":"records","records":[{"content":{"kind":"functional_requirement","text":{"kind":"normalized","segments":[{"kind":"literal","value":"Confirm a booking."}]}},"provenance":{"claim_ids":[{"ordinal":7}],"clarification_response_ids":[]}},{"content":{"kind":"functional_requirement","text":{"kind":"normalized","segments":[{"kind":"literal","value":"Issue a receipt."}]}},"provenance":{"claim_ids":[{"ordinal":9}],"clarification_response_ids":[]}}]}
    ;
    try checkCandidate("generation", "functional_requirement", records);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parsed = try codec.decode(@import("domain/specification_generation.zig").ModelResponse, a, records);
    try std.testing.expectEqual(@as(usize, 2), parsed.records.records.len);
    try std.testing.expectEqual(@as(u32, 9), parsed.records.records[1].provenance.claim_ids[0].ordinal);
    for ([_][]const u8{
        "{\"kind\":\"records\",\"records\":[],\"records\":[]}",
        "{\"kind\":\"records\",\"records\":[{},{}]}",
        "{\"kind\":\"records\",\"records\":[{} { }]}",
        "{\"kind\":\"records\",\"records\":[{},]}",
    }) |bytes| try std.testing.expectError(error.InvalidJsonDocument, codec.decode(@import("domain/specification_generation.zig").ModelResponse, a, bytes));
}

test "disposition schemas reject legacy fields incompatible variants and missing targets" {
    const prefix = "{\"claim_dispositions\":[{\"claim_id\":{\"ordinal\":7},\"disposition\":";
    const suffix = "}],\"signals\":[],\"conflicts\":[]}";
    try candidateCase("reconciliation", "global", prefix ++ "\"retained\",\"related_claim_ids\":[]" ++ suffix, .unknown_property, "/claim_dispositions/0/related_claim_ids");
    try candidateCase("reconciliation", "global", prefix ++ "{\"kind\":\"retained\"},\"related_claim_ids\":[]" ++ suffix, .unknown_property, "/claim_dispositions/0/related_claim_ids");
    try candidateCase("reconciliation", "global", prefix ++ "{\"kind\":\"retained\",\"related_claim_ids\":[]}" ++ suffix, .unknown_property, "/claim_dispositions/0/disposition/related_claim_ids");
    try candidateCase("reconciliation", "global", prefix ++ "{\"kind\":\"duplicate\"}" ++ suffix, .missing_required_property, "/claim_dispositions/0/disposition/target_claim_id");
    try candidateCase("reconciliation", "global", prefix ++ "{\"kind\":\"duplicate\",\"target_claim_id\":{\"ordinal\":9},\"related_claim_ids\":[]}" ++ suffix, .unknown_property, "/claim_dispositions/0/disposition/related_claim_ids");
    try candidateCase("reconciliation", "global", prefix ++ "{\"kind\":\"conflicting\"}" ++ suffix, .missing_required_property, "/claim_dispositions/0/disposition/related_claim_ids");
}

test "superseded and conflicting response schemas require nonempty relationship selections" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/reconciliation.schema.json", a, .limited(@import("domain/model_result_schema.zig").max_bytes));
    var adapter: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = (try adapter.compiler().compile(a, source)).select(.{ .bytes = "global" }).?;
    inline for (.{ "superseded", "conflicting" }) |kind| {
        try @import("model_payload_schema_test.zig").checkDocument(schema.modelBytes(), .{
            .bytes = "{\"claim_dispositions\":[{\"claim_id\":{\"ordinal\":7},\"disposition\":{\"kind\":\"" ++ kind ++ "\",\"related_claim_ids\":[]}}],\"signals\":[],\"conflicts\":[]}",
            .rejection = .array_length,
            .path = "/claim_dispositions/0/disposition/related_claim_ids",
        });
    }
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
