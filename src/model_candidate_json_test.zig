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
    const prefix = "{\"statements\":[{\"local_key\":1,\"claim_ids\":[1],\"content\":";
    for ([_][]const u8{
        "{\"model\":{\"kind\":\"business\",\"segments\":[\"Display the greeting.\"]}}",
        "{\"preserved_token\":{\"id\":1,\"kind\":\"business_exact_string\",\"value\":\"Hello, World!\"}}",
    }) |content| try check(schema, .{ .bytes = try std.mem.concat(a, u8, &.{ prefix, content, "}]}" }), .rejection = .missing_required_property, .path = "/statements/0/content/kind" });
    for ([_][]const u8{
        "{\"kind\":\"model\",\"model\":{\"kind\":\"business\",\"segments\":[\"Display the greeting.\"]}}",
        "{\"kind\":\"preserved_token\",\"token_id\":1}",
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
    const id = "7";
    const provenance = "{\"claim_ids\":[" ++ id ++ "],\"clarification_response_ids\":[]}";
    const segments = "[\"Display the status\",{\"kind\":\"passive\",\"passive_literal_id\":" ++ id ++ "}]";
    const nodes = "[\"Source meaning\",{\"kind\":\"passive\",\"passive_literal_id\":" ++ id ++ "},{\"kind\":\"source\",\"source_id\":" ++ id ++ "}]";
    const normalized = segments;
    const exact = "[{\"kind\":\"exact_copy\",\"claim_id\":" ++ id ++ "}]";
    const attributed = "{\"value\":" ++ normalized ++ ",\"provenance\":" ++ provenance ++ "}";
    const selection = "{\"first\":7,\"last\":9}";
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
    try checkCandidate("reconciliation", "global", "{\"claim_dispositions\":[],\"signals\":[{\"claim_ids\":[" ++ response_wire.id ++ "],\"content\":{\"kind\":\"preserved_token\",\"token_id\":" ++ response_wire.id ++ "}}],\"conflicts\":[{\"claim_ids\":[" ++ response_wire.id ++ ",9],\"kind\":\"value_mismatch\",\"summary\":{\"nodes\":" ++ response_wire.nodes ++ "},\"resolution\":\"unresolved\"}]}");
    // Structural conformance is not a claim that these independently shaped
    // records satisfy the graph, source-join or semantic validators.
    try checkCandidate("generation", "brief", "{\"kind\":\"brief\",\"title\":" ++ response_wire.attributed ++ ",\"description\":" ++ response_wire.attributed ++ ",\"primary_goal\":" ++ response_wire.attributed ++ "}");
    try checkCandidate("generation", "primary_user_story", "{\"kind\":\"primary_user_story\",\"value\":" ++ response_wire.exact ++ ",\"provenance\":" ++ response_wire.provenance ++ "}");
    try checkCandidate("generation", "entities", "{\"kind\":\"entities\",\"disposition\":\"not_applicable\",\"basis\":" ++ response_wire.attributed ++ "}");
    inline for (.{ "brief", "primary_user_story", "entities" }) |selection| try checkCandidate("generation", selection, response_wire.clarification);
    // Assignment-specific rules require the unit context: schema checks here,
    // with native validation covered by specification_generation_test.
    try candidateSchemaCase("generation", "records", response_wire.clarification, .missing_required_property, "/record_kind");
    inline for (response_wire.records) |record| {
        const bytes = "{\"content\":" ++ record[1] ++ ",\"provenance\":" ++ response_wire.provenance ++ "}";
        try checkCandidate("generation", "records", "{\"kind\":\"records\",\"records\":[" ++ bytes ++ "]}");
        const need = response_wire.clarification[0 .. response_wire.clarification.len - 1] ++ ",\"record_kind\":\"" ++ record[0] ++ "\"}";
        try checkCandidate("generation", "records", need);
        try candidateSchemaCase("generation", "primary_user_story", need, .unknown_property, "/record_kind");
        if (comptime std.mem.eql(u8, record[0], "acceptance_criterion") or std.mem.eql(u8, record[0], "functional_requirement") or std.mem.eql(u8, record[0], "entity")) try checkCandidate("generation", "repair_record_" ++ record[0], bytes);
        if (comptime !std.mem.eql(u8, record[0], "entity")) try checkCandidate("generation", "repair_record_non_entity", bytes);
    }
    try checkCandidate("generation", "provenance", response_wire.provenance);
    try checkCandidate("generation", "value", "{\"value\":" ++ response_wire.exact ++ "}");
    try checkCandidate("support", "detail", "{\"detail\":\"Which deadline applies?\"}");
    try candidateCase("support", "detail", "{\"detail\":\"Which deadline applies?\",\"finding\":\"supported\"}", .unknown_property, "/finding");
    try checkCandidate("support", "selection", "{\"provenance\":" ++ response_wire.provenance ++ ",\"source_ids\":[]}");
    try checkCandidate("support", "finding", "{\"kind\":\"candidate_omission\",\"loss\":{\"kind\":\"unlocalized\"},\"provenance\":" ++ response_wire.provenance ++ ",\"source_ids\":[],\"detail\":\"Preserve the required confirmation.\"}");
    try checkCandidate("support", null, "{\"entries\":[{\"requirement_ordinal\":7,\"value\":{\"kind\":\"supported\",\"loss\":{\"kind\":\"unlocalized\"},\"provenance\":" ++ response_wire.provenance ++ ",\"source_ids\":[],\"detail\":\"\"}},{\"requirement_ordinal\":9,\"value\":{\"kind\":\"unsupported\",\"loss\":{\"kind\":\"unlocalized\"},\"provenance\":{\"claim_ids\":[],\"clarification_response_ids\":[]},\"source_ids\":[],\"detail\":\"Which deadline applies?\",\"question\":\"Which deadline applies? Supply a duration.\"}}]}");
}

test "support schemas expose applicability only when selected and reject superseded fields" {
    const value = "{\"kind\":\"not_applicable\",\"loss\":{\"kind\":\"unlocalized\"},\"provenance\":" ++ response_wire.provenance ++ ",\"source_ids\":[],\"detail\":\"No business data is involved.\"}";
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
        try @import("model_payload_schema_test.zig").checkDocument(selected.modelBytes(), .{ .bytes = if (std.mem.eql(u8, selection, "finding")) value else review, .rejection = .unknown_variant, .path = if (std.mem.eql(u8, selection, "finding")) "/kind" else "/entries/0/value/kind" });
    }
    inline for (.{ "finding", "disposition", "decision" }) |field| {
        try candidateCase("support", "finding", "{\"kind\":\"unsupported\",\"loss\":{\"kind\":\"unlocalized\"},\"" ++ field ++ "\":\"supported\",\"provenance\":" ++ response_wire.provenance ++ ",\"source_ids\":[],\"detail\":\"The source leaves a decision open.\",\"question\":\"Which deadline applies?\"}", .unknown_property, "/" ++ field);
    }
}

test "D1 source variants require questions only for gaps across initial and inserted findings" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .limited(@import("domain/model_result_schema.zig").max_bytes));
    var adapter: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try adapter.compiler().compile(a, source);
    const review = @import("domain/specification_support.zig").Source;
    const json = @import("domain/model_candidate_json.zig");
    for (std.meta.tags(review.Decision)) |tag| {
        const gap = @import("domain/specification_support_evidence.zig").questionRequired(tag.finding());
        const value: review.Value = .{ .kind = tag, .provenance = .{ .claim_ids = &.{.{ .ordinal = 1 }}, .clarification_response_ids = &.{} }, .source_ids = &.{.{ .ordinal = 1 }}, .detail = "The request identifies the action but leaves its duration undecided.", .question = if (gap) "Which duration applies? Supply the duration and starting event." else null };
        const valid = try json.encode(review.Value, a, value);
        try std.testing.expectEqualDeep(value, try json.decode(review.Value, a, valid));
        var wrong = value;
        wrong.question = if (gap) null else "Should this outcome be accepted?";
        const invalid = try json.encode(review.Value, a, wrong);
        for ([_][]const u8{ "finding", "applicability_finding", "review", "review_applicability" }) |definition| {
            if (tag == .not_applicable and std.mem.indexOf(u8, definition, "applicability") == null) continue;
            const whole = std.mem.startsWith(u8, definition, "review");
            const good_bytes = if (whole) try std.fmt.allocPrint(a, "{{\"entries\":[{{\"requirement_ordinal\":1,\"value\":{s}}}]}}", .{valid}) else valid;
            const bad_bytes = if (whole) try std.fmt.allocPrint(a, "{{\"entries\":[{{\"requirement_ordinal\":1,\"value\":{s}}}]}}", .{invalid}) else invalid;
            const selected = schema.select(.{ .bytes = definition }).?;
            try @import("model_payload_schema_test.zig").checkDocument(selected.modelBytes(), .{ .bytes = good_bytes });
            try @import("model_payload_schema_test.zig").checkDocument(selected.modelBytes(), .{ .bytes = bad_bytes, .rejection = if (gap) .missing_required_property else .unknown_property, .path = if (whole) "/entries/0/value/question" else "/question" });
        }
        var parsed = try std.json.parseFromSlice(std.json.Value, a, valid, .{});
        const discriminator = parsed.value.object.get("kind").?;
        _ = parsed.value.object.orderedRemove("kind");
        try parsed.value.object.put(a, "decision", discriminator);
        const legacy = try std.json.Stringify.valueAlloc(a, parsed.value, .{});
        try std.testing.expectError(error.InvalidJsonDocument, json.decode(review.Value, a, legacy));
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

test "business values use one segment shape for prose and exact references" {
    const value = "[\"Display \",{\"kind\":\"exact_copy\",\"claim_id\":7},\" with UTC date/time.\"]";
    try checkCandidate("generation", "value", "{\"value\":" ++ value ++ "}");
    try checkCandidate("generation", "primary_user_story", "{\"kind\":\"primary_user_story\",\"value\":" ++ value ++ ",\"provenance\":" ++ response_wire.provenance ++ "}");
    try candidateCase("generation", "value", "{\"value\":{\"kind\":\"exact_copy\",\"claim_id\":7}}", .type_mismatch, "/value");
    try candidateCase("generation", "value", "{\"value\":[{\"kind\":\"exact_copy\",\"token_id\":7,\"citation_id\":9}]}", .unknown_property, "/value/0/token_id");
}

test "review and insertion evidence shapes follow native minima without excluding source-only diagnoses" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const review = @import("domain/specification_support.zig").Source;
    const admission = @import("domain/specification_support_evidence.zig");
    const check = @import("model_payload_schema_test.zig").checkDocument;
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited));
    for (std.meta.tags(review.Decision)) |decision| {
        var value: review.Value = .{
            .kind = decision,
            .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} },
            .source_ids = &.{.{ .ordinal = 7 }},
            .detail = "The source establishes an action; its duration is unspecified.",
            .question = if (admission.questionRequired(decision.finding())) "Which duration applies? Supply the duration and starting event." else null,
        };
        for ([_][]const u8{ "finding", "applicability_finding", "review", "review_applicability" }) |definition| {
            if (decision == .not_applicable and std.mem.indexOf(u8, definition, "applicability") == null) continue;
            const selected = schema.select(.{ .bytes = definition }).?;
            const whole = std.mem.startsWith(u8, definition, "review");
            for (0..2) |claims| {
                value.provenance.claim_ids = if (claims == 0) &.{} else &.{.{ .ordinal = 7 }};
                const encoded = if (whole) try codec.encode(review.Review, a, .{ .entries = &.{.{ .requirement_ordinal = 7, .value = value }} }) else try codec.encode(review.Value, a, value);
                const rejects = claims == 0 and admission.minimum(decision.finding()) == .claim_required;
                try check(selected.modelBytes(), .{ .bytes = encoded, .rejection = if (rejects) .array_length else null, .path = if (!rejects) null else if (whole) "/entries/0/value/provenance/claim_ids" else "/provenance/claim_ids" });
            }
        }
    }
    // The provider projection must also retain the nonempty condition. The full
    // schema and native validator continue to own admission and evidence meaning.
    const projection = @import("domain/model_schema_projection.zig");
    const native = try projection.value(a, schema.select(.{ .bytes = "applicability_finding" }).?.root(), .bedrock);
    for (native.object.get("anyOf").?.array.items) |variant| {
        const properties = variant.object.get("properties").?.object;
        const decision = std.meta.stringToEnum(review.Decision, properties.get("kind").?.object.get("const").?.string).?;
        const claims = properties.get("provenance").?.object.get("properties").?.object.get("claim_ids").?.object;
        const required = admission.minimum(decision.finding()) == .claim_required;
        try std.testing.expectEqual(required, claims.contains("minItems"));
        if (required) try std.testing.expectEqual(@as(i64, 1), claims.get("minItems").?.integer);
    }
}

test "loss attribution wire variants stay closed across initial review insertion and replacement" {
    const locations = .{
        "{\"kind\":\"unlocalized\"}",
        "{\"kind\":\"extraction_claim\",\"bytes\":\"chunk-7\"}",
        "{\"kind\":\"token_classification\",\"source_id\":7,\"extractor_id\":\"markdown_inline_code_v1\",\"ordinal\":9}",
        "{\"kind\":\"reconciliation_signal\",\"ordinal\":7}",
        "{\"kind\":\"reconciliation_disposition\",\"ordinal\":9}",
        "{\"kind\":\"reconciliation_conflict\",\"ordinal\":9}",
    };
    try std.testing.expectEqual(@typeInfo(@import("domain/source_omission.zig").Location).@"union".fields.len, locations.len);
    inline for (locations) |location| {
        try checkCandidate("support", "loss", location);
        const value = "{\"kind\":\"candidate_omission\",\"loss\":" ++ location ++ ",\"provenance\":" ++ response_wire.provenance ++ ",\"source_ids\":[" ++ response_wire.id ++ "],\"detail\":\"Preserve the deadline.\"}";
        inline for (.{ "finding", "applicability_finding" }) |selection| try checkCandidate("support", selection, value);
        inline for (.{ "review", "review_applicability" }) |selection| try checkCandidate("support", selection, "{\"entries\":[{\"requirement_ordinal\":7,\"value\":" ++ value ++ "}]}");
    }
    try candidateCase("support", "loss", "{\"kind\":\"unlocalized\",\"value\":null}", .unknown_property, "/value");
    try candidateCase("support", "finding", "{\"kind\":\"candidate_omission\",\"provenance\":" ++ response_wire.provenance ++ ",\"source_ids\":[],\"detail\":\"Preserve the deadline.\"}", .missing_required_property, "/loss");
}

fn checkCandidate(comptime name: []const u8, comptime selection: ?[]const u8, bytes: []const u8) !void {
    return candidateCase(name, selection, bytes, null, null);
}

fn candidateSchemaCase(comptime name: []const u8, comptime selection: ?[]const u8, bytes: []const u8, rejection: ?@import("domain/model_payload_schema.zig").Rejection, path: ?[]const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/" ++ name ++ ".schema.json", a, .limited(@import("domain/model_result_schema.zig").max_bytes));
    var adapter: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try adapter.compiler().compile(a, source);
    const selected = if (selection) |definition| schema.select(.{ .bytes = definition }) orelse return error.MissingSchemaSelection else schema;
    try @import("model_payload_schema_test.zig").checkDocument(selected.modelBytes(), .{ .bytes = bytes, .rejection = rejection, .path = path });
}

fn candidateCase(comptime name: []const u8, comptime selection: ?[]const u8, bytes: []const u8, rejection: ?@import("domain/model_payload_schema.zig").Rejection, path: ?[]const u8) !void {
    try candidateSchemaCase(name, selection, bytes, rejection, path);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    if (rejection != null) {
        try std.testing.expectError(error.InvalidJsonDocument, decodeCandidate(name, selection, a, bytes));
    } else {
        const encoded = try decodeCandidate(name, selection, a, bytes);
        // Both owners must accept the response in both directions. In particular,
        // native union encoding must not introduce a wrapper absent from the schema.
        try candidateSchemaCase(name, selection, encoded, null, null);
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
    } else if (comptime std.mem.eql(u8, name, "generation")) {
        const definition = selection.?;
        if (comptime std.mem.eql(u8, definition, "provenance") or std.mem.eql(u8, definition, "value") or std.mem.startsWith(u8, definition, "repair_record_")) {
            return selectedWire(@import("domain/specification_repair.zig").Replacement, a, if (std.mem.eql(u8, definition, "provenance")) .provenance else if (std.mem.eql(u8, definition, "value")) .value else .record, bytes);
        }
        return nativeWire(@import("domain/specification_generation.zig").ModelResponse, a, bytes);
    } else if (comptime selection != null and !std.mem.startsWith(u8, selection.?, "review")) {
        const selected = selection.?;
        if (comptime std.mem.eql(u8, selected, "loss")) return nativeWire(@import("domain/source_omission.zig").Location, a, bytes);
        const T = @import("domain/specification_support_repair.zig").Source.Replacement;
        return selectedWire(T, a, if (comptime std.mem.eql(u8, selected, "applicability_finding")) .finding else @field(std.meta.Tag(T), selected), bytes);
    } else return nativeWire(@import("domain/specification_support.zig").Source.Review, a, bytes);
}

test "final proposal schemas and native readers reject deterministic echoes and mixed shapes" {
    const echoed = "{\"claim_ids\":[7],\"citation_ids\":[7],\"clarification_response_ids\":[]}";
    inline for (.{ "member_claim_ids", "member_summary_ids" }) |field| {
        try candidateCase("reconciliation", "summary", "{\"statements\":[],\"" ++ field ++ "\":[]}", .unknown_property, "/" ++ field);
    }
    try candidateCase("generation", "primary_user_story", "{\"kind\":\"primary_user_story\",\"value\":" ++ response_wire.normalized ++ ",\"provenance\":" ++ echoed ++ "}", .unknown_property, "/provenance/citation_ids");
    try candidateCase("generation", "provenance", echoed, .unknown_property, "/citation_ids");
    try candidateCase("support", null, "{\"entries\":[{\"requirement_ordinal\":7,\"value\":{\"kind\":\"supported\",\"loss\":{\"kind\":\"unlocalized\"},\"provenance\":" ++ echoed ++ ",\"source_ids\":[],\"detail\":\"\"}}]}", .unknown_property, "/entries/0/value/provenance/citation_ids");
    try candidateCase("reconciliation", "global", "{\"claim_dispositions\":[],\"signals\":[{\"claim_ids\":[7],\"citation_ids\":[],\"content\":{\"kind\":\"preserved_token\",\"token_id\":7}}],\"conflicts\":[]}", .unknown_property, "/signals/0/citation_ids");
    try candidateCase("reconciliation", "global", "{\"claim_dispositions\":[],\"signals\":[],\"conflicts\":[{\"claim_ids\":[7,9],\"citation_ids\":[],\"kind\":\"value_mismatch\",\"summary\":{\"nodes\":" ++ response_wire.nodes ++ "},\"resolution\":\"unresolved\"}]}", .unknown_property, "/conflicts/0/citation_ids");
}

test "independent multi-record proposals retain siblings and all disposition variants" {
    const dispositions =
        \\{"claim_dispositions":[{"claim_id":7,"disposition":{"kind":"retained"}},{"claim_id":9,"disposition":{"kind":"duplicate","target_claim_id":7}},{"claim_id":11,"disposition":{"kind":"superseded","related_claim_ids":[7,9]}},{"claim_id":13,"disposition":{"kind":"conflicting","related_claim_ids":[15]}},{"claim_id":15,"disposition":{"kind":"conflicting","related_claim_ids":[13]}}],"signals":[],"conflicts":[]}
    ;
    try checkCandidate("reconciliation", "global", dispositions);
    const statements =
        \\{"statements":[{"local_key":7,"claim_ids":[7],"content":{"kind":"model","model":{"kind":"business","segments":["Confirm a booking."]}}},{"local_key":9,"claim_ids":[9],"content":{"kind":"model","model":{"kind":"business","segments":["Issue a renewal receipt."]}}}]}
    ;
    try checkCandidate("reconciliation", "summary", statements);
    const records =
        \\{"kind":"records","records":[{"content":{"kind":"functional_requirement","text":["Confirm a booking."]},"provenance":{"claim_ids":[7],"clarification_response_ids":[]}},{"content":{"kind":"functional_requirement","text":["Issue a receipt."]},"provenance":{"claim_ids":[9],"clarification_response_ids":[]}}]}
    ;
    try checkCandidate("generation", "records", records);
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
    const prefix = "{\"claim_dispositions\":[{\"claim_id\":7,\"disposition\":";
    const suffix = "}],\"signals\":[],\"conflicts\":[]}";
    try candidateCase("reconciliation", "global", prefix ++ "\"retained\",\"related_claim_ids\":[]" ++ suffix, .unknown_property, "/claim_dispositions/0/related_claim_ids");
    try candidateCase("reconciliation", "global", prefix ++ "{\"kind\":\"retained\"},\"related_claim_ids\":[]" ++ suffix, .unknown_property, "/claim_dispositions/0/related_claim_ids");
    try candidateCase("reconciliation", "global", prefix ++ "{\"kind\":\"retained\",\"related_claim_ids\":[]}" ++ suffix, .unknown_property, "/claim_dispositions/0/disposition/related_claim_ids");
    try candidateCase("reconciliation", "global", prefix ++ "{\"kind\":\"duplicate\"}" ++ suffix, .missing_required_property, "/claim_dispositions/0/disposition/target_claim_id");
    try candidateCase("reconciliation", "global", prefix ++ "{\"kind\":\"duplicate\",\"target_claim_id\":9,\"related_claim_ids\":[]}" ++ suffix, .unknown_property, "/claim_dispositions/0/disposition/related_claim_ids");
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
            .bytes = "{\"claim_dispositions\":[{\"claim_id\":7,\"disposition\":{\"kind\":\"" ++ kind ++ "\",\"related_claim_ids\":[]}}],\"signals\":[],\"conflicts\":[]}",
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

test "model JSON optional fields round trip without relaxing required nullable fields" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Value = struct { name: []const u8, answer: ?[]const u8 = null, status: ?u32 };
    const absent: Value = .{ .name = "delivery", .status = null };
    try std.testing.expectEqualStrings("{\"name\":\"delivery\",\"status\":null}", try codec.encode(Value, a, absent));
    try std.testing.expectEqualDeep(absent, try codec.decode(Value, a, try codec.encode(Value, a, absent)));
    const present: Value = .{ .name = "delivery", .answer = "next day", .status = 3 };
    try std.testing.expectEqualDeep(present, try codec.decode(Value, a, try codec.encode(Value, a, present)));
    for ([_][]const u8{ "{\"name\":\"delivery\"}", "{\"status\":null}", "{\"name\":\"delivery\",\"status\":null,\"foreign\":0}" }) |bad| try std.testing.expectError(error.InvalidJsonDocument, codec.decode(Value, a, bad));
}

test "declared compact values preserve typed identities and reject legacy or ambiguous wire shapes" {
    try compactRoundTrip(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, compactRoundTrip, .{});
}
fn compactRoundTrip(allocator: std.mem.Allocator) !void {
    const Id = struct {
        pub const model_scalar = "number";
        number: u16,
    };
    const Segment = union(enum) {
        pub const model_inline = .{ .words = "text" };
        words: struct { text: []const u8 },
        reference: struct { id: Id },
    };
    const Value = union(enum) {
        pub const model_inline = .{ .sequence = "items" };
        sequence: struct { items: []const Segment },
        choice: struct { id: Id },
    };
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sample_value: Value = .{ .sequence = .{ .items = &.{ .{ .words = .{ .text = "Renew a loan " } }, .{ .reference = .{ .id = .{ .number = 9 } } } } } };
    const expected = "{\"value\":[\"Renew a loan \",{\"kind\":\"reference\",\"id\":9}]}";
    const decoded = try codec.decode(Value, a, expected);
    try std.testing.expectEqualDeep(sample_value, decoded);
    const stored_before = try std.json.Stringify.valueAlloc(a, sample_value, .{});
    const stored_after = try std.json.Stringify.valueAlloc(a, decoded, .{});
    try std.testing.expectEqualStrings(stored_before, stored_after);
    try std.testing.expectEqualDeep(decoded, try codec.decode(Value, a, try codec.encode(Value, a, decoded)));
    _ = try codec.decode(Value, a, "{\"value\":{\"kind\":\"choice\",\"id\":90e-1}}");
    for ([_][]const u8{
        "[]",                                               "{\"value\":[{\"kind\":\"words\",\"text\":\"old\"}]}",
        "{\"value\":{\"kind\":\"sequence\",\"items\":[]}}", "{\"value\":{\"kind\":\"choice\",\"id\":{\"number\":9}}}",
        "{\"value\":{\"kind\":\"choice\",\"id\":9.5}}",     "{\"value\":{\"kind\":\"choice\",\"id\":65536}}",
        "{\"value\":false}",                                "{\"value\":[],\"extra\":0}",
    }) |bad| try std.testing.expectError(error.InvalidJsonDocument, codec.decode(Value, a, bad));
}
