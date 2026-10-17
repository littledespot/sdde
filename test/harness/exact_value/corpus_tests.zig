const std = @import("std");
const corpus = @import("corpus.zig");
const policy = @import("../../../src/domain/text_field_policy.zig");
const classifier: corpus.recognition.LexicalClassifier = .{ .boundary_fn = @import("exact_value_unicode").wholeWordBoundary };

const packet =
    \\{"preserved_tokens":[{"claim_id":1,"value":"ACTIVE"}],"source_assignment":{"requirements":[{"claim_id":1}]}}
;
const historical_text_schema =
    \\{"oneOf":[{"type":"string","minLength":1,"maxLength":4096},{"type":"object","properties":{"fragments":{"type":"array","items":{"oneOf":[{"type":"string","minLength":1,"maxLength":4096},{"type":"object","properties":{"kind":{"const":"exact_copy"},"claim_id":{"enum":[1]}},"required":["kind","claim_id"],"additionalProperties":false}]},"minItems":1,"maxItems":16}},"required":["fragments"],"additionalProperties":false}]}
;
const text_schema =
    \\{"oneOf":[{"type":"string","minLength":1,"maxLength":4096},{"type":"object","properties":{"fragments":{"type":"array","items":{"oneOf":[{"type":"string","minLength":1,"maxLength":4096},{"type":"object","properties":{"kind":{"const":"passive"},"passive_literal_id":{"enum":[1]}},"required":["kind","passive_literal_id"],"additionalProperties":false}]},"minItems":1,"maxItems":16}},"required":["fragments"],"additionalProperties":false}]}
;
const root_schema = "{\"type\":\"object\",\"properties\":{\"value\":" ++ text_schema ++ "},\"required\":[\"value\"],\"additionalProperties\":false}";
fn valueOutput(a: std.mem.Allocator, output: []const u8) ![]const u8 {
    return std.fmt.allocPrint(a, "{{\"value\":{s}}}", .{output});
}
fn valueSchema(a: std.mem.Allocator, schema: []const u8) ![]const u8 {
    return std.fmt.allocPrint(a, "{{\"type\":\"object\",\"properties\":{{\"value\":{s}}},\"required\":[\"value\"],\"additionalProperties\":false}}", .{schema});
}
fn measure(a: std.mem.Allocator, output: []const u8, field: policy.Field) !corpus.Measurement {
    return measureContract(a, output, field, .current_v6);
}
fn measureContract(a: std.mem.Allocator, output: []const u8, field: policy.Field, contract: corpus.MetadataContract) !corpus.Measurement {
    return corpus.measure(a, .{
        .packet = packet,
        .output = try valueOutput(a, output),
        .schema = if (contract == .current_v6) root_schema else "{\"type\":\"object\",\"properties\":{\"value\":" ++ historical_text_schema ++ "},\"required\":[\"value\"],\"additionalProperties\":false}",
        .metadata_contract = contract,
        .field_policies = &.{.{ .field = field, .path = &.{.{ .property = "value" }} }},
        .original_sources = &.{},
    }, classifier);
}

test "prototype lexical recognition preserves prose and insertion role policies" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const obligation = try measure(a, "\"ACTIVE\"", .ac_then);
    try std.testing.expectEqual(.measured, obligation.state);
    try std.testing.expectEqual(@as(usize, 1), obligation.fields.len);
    const selected = obligation.fields[0];
    try std.testing.expectEqual(.assigned_requirements, selected.binding);
    try std.testing.expectEqual(.matched, selected.plain_runs[0].result.state);
    try std.testing.expectEqual(@as(usize, 1), selected.plain_runs[0].result.matches.len);
    try std.testing.expectEqual(.valid, selected.original_composition);
    try std.testing.expectEqual(.invalid, selected.proposed_composition);
    try std.testing.expectEqual(.reference_only, selected.proposed_composition_issue.?);
    try std.testing.expect(!obligation.workflow_authority and !obligation.semantic_quality_assessed);

    const identity = try measure(a, "\"ACTIVE\"", .entity_name);
    try std.testing.expectEqual(.matched, identity.fields[0].plain_runs[0].result.state);
    try std.testing.expectEqual(.valid, identity.fields[0].proposed_composition);
    try std.testing.expectEqual(null, identity.fields[0].proposed_composition_issue);

    const prose = try measure(a, "\"Display ACTIVE when started.\"", .ac_then);
    try std.testing.expectEqual(.matched, prose.fields[0].plain_runs[0].result.state);
    try std.testing.expectEqual(.valid, prose.fields[0].proposed_composition);
}

test "prototype retained typed insertions and encoded syntax are never healed by recognition" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const insertion = try measureContract(a,
        \\{"fragments":[{"kind":"exact_copy","claim_id":1}]}
    , .ac_then, .historical_v5);
    const selected = insertion.fields[0];
    try std.testing.expectEqual(@as(usize, 0), selected.plain_runs.len);
    try std.testing.expectEqual(@as(usize, 1), selected.typed_exact_references.len);
    try std.testing.expect(selected.typed_exact_references[0].resolved);
    try std.testing.expectEqual(@as(?u32, 1), selected.typed_exact_references[0].occurrence);
    try std.testing.expectEqual(.invalid, selected.original_composition);
    try std.testing.expectEqual(.invalid, selected.proposed_composition);
    try std.testing.expectEqual(.reference_only, selected.proposed_composition_issue.?);
    try std.testing.expectEqual(.matched, selected.historical_typed_counterfactual.?.result.state);

    const encoded = try measure(a,
        \\"{\"kind\":\"exact_copy\",\"claim_id\":1}"
    , .ac_then);
    const encoded_field = encoded.fields[0];
    try std.testing.expectEqual(@as(usize, 0), encoded_field.typed_exact_references.len);
    try std.testing.expectEqual(.no_match, encoded_field.plain_runs[0].result.state);
    try std.testing.expectEqual(@as(usize, 0), encoded_field.plain_runs[0].result.matches.len);
    try std.testing.expectEqual(null, encoded_field.historical_typed_counterfactual);
    try std.testing.expectEqual(.invalid, encoded_field.original_composition);
    try std.testing.expectEqual(.invalid, encoded_field.proposed_composition);
    try std.testing.expectEqual(.embedded_insertion_syntax, encoded_field.proposed_composition_issue.?);
}

test "prototype composition preserves exact original source syntax exception" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const encoded =
        \\"{\"kind\":\"exact_copy\",\"claim_id\":1}"
    ;
    const source_packet =
        \\{"preserved_tokens":[{"claim_id":1,"value":"ACTIVE"}],"source_assignment":{"requirements":[{"claim_id":1}]},"sources":[{"id":1,"text":"The original source includes {\"kind\":\"exact_copy\",\"claim_id\":1} as data."}]}
    ;
    const measured = try corpus.measure(a, .{
        // This particular packet omits the original witness. Native metadata
        // captured with the request remains the authority for the exception.
        .packet = packet,
        .output = try valueOutput(a, encoded),
        .schema = root_schema,
        .field_policies = &.{.{ .field = .ac_then, .path = &.{.{ .property = "value" }} }},
        .original_sources = &.{.{ .source_id = .{ .ordinal = 1 }, .bytes = "The original source includes {\"kind\":\"exact_copy\",\"claim_id\":1} as data." }},
    }, classifier);
    try std.testing.expectEqual(.native_description, measured.fields[0].source_metadata);
    try std.testing.expectEqual(.valid, measured.fields[0].original_composition);
    try std.testing.expectEqual(.valid, measured.fields[0].proposed_composition);
    try std.testing.expectEqual(.no_match, measured.fields[0].plain_runs[0].result.state);
    try std.testing.expectEqual(@as(usize, 0), measured.fields[0].typed_exact_references.len);
    try std.testing.expectEqual(null, measured.fields[0].historical_typed_counterfactual);

    const packet_only = try corpus.measure(a, .{
        .packet = source_packet,
        .output = try valueOutput(a, encoded),
        .schema = root_schema,
        .field_policies = &.{.{ .field = .ac_then, .path = &.{.{ .property = "value" }} }},
    }, classifier);
    try std.testing.expectEqual(.packet_projection, packet_only.fields[0].source_metadata);
    try std.testing.expectEqual(.valid, packet_only.fields[0].proposed_composition);

    const known_empty = try corpus.measure(a, .{
        .packet = source_packet,
        .output = try valueOutput(a, encoded),
        .schema = root_schema,
        .field_policies = &.{.{ .field = .ac_then, .path = &.{.{ .property = "value" }} }},
        .original_sources = &.{},
    }, classifier);
    try std.testing.expectEqual(.native_description, known_empty.fields[0].source_metadata);
    try std.testing.expectEqual(.invalid, known_empty.fields[0].original_composition);
    try std.testing.expectEqual(.invalid, known_empty.fields[0].proposed_composition);
    try std.testing.expectEqual(.embedded_insertion_syntax, known_empty.fields[0].proposed_composition_issue.?);
}

test "prototype native field binding conflicts reject instead of selecting the last policy" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const field_owner = @import("../../../src/domain/model_text_field.zig");
    const wire = @import("../../../src/domain/model_text_wire.zig");
    const variants = [_][2]policy.Field{
        .{ .ac_then, .entity_name },
        .{ .entity_name, .ac_then },
    };
    for (variants) |fields| {
        const bindings: []const field_owner.Binding = &.{
            .{ .field = fields[0], .path = &.{.{ .property = "value" }} },
            .{ .field = fields[1], .path = &.{.{ .property = "value" }} },
        };
        try std.testing.expect(!field_owner.valid(bindings));
        const measured = try corpus.measure(a, .{
            .packet = packet,
            .output = "{\"value\":\"ACTIVE\"}",
            .schema = root_schema,
            .field_policies = bindings,
        }, classifier);
        try std.testing.expectEqual(.invalid_field_metadata, measured.state);
        try std.testing.expectEqual(@as(usize, 0), measured.fields.len);
        try std.testing.expect(!measured.workflow_authority and !measured.semantic_quality_assessed);

        const prose_fields: []const wire.ProseField = &.{
            .{ .field = fields[0], .path = &.{.{ .property = "value" }} },
            .{ .field = fields[1], .path = &.{.{ .property = "value" }} },
        };
        try std.testing.expect(!wire.validProseFields(prose_fields));
        const prose_conflict = try corpus.measure(a, .{
            .packet = packet,
            .output = "{\"value\":\"ACTIVE\"}",
            .schema = root_schema,
            .prose_fields = prose_fields,
        }, classifier);
        try std.testing.expectEqual(.invalid_field_metadata, prose_conflict.state);
        try std.testing.expectEqual(@as(usize, 0), prose_conflict.fields.len);
    }
}

test "prototype native field metadata must fit the selected response schema" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const measured = try corpus.measure(a, .{
        .packet = packet,
        .output = "{\"value\":\"ACTIVE\"}",
        .schema = "{\"type\":\"object\",\"properties\":{\"value\":" ++ historical_text_schema ++ "},\"required\":[\"value\"],\"additionalProperties\":false}",
        // Every current model field prohibits exact-copy input. This historical
        // alternative must not acquire current model metadata authority.
        .field_policies = &.{.{ .field = .clarification_question, .path = &.{.{ .property = "value" }} }},
    }, classifier);
    try std.testing.expectEqual(.invalid_field_metadata, measured.state);
    try std.testing.expectEqual(@as(usize, 0), measured.fields.len);
    try std.testing.expect(!measured.workflow_authority and !measured.semantic_quality_assessed);

    const historical = try measureContract(a, "\"ACTIVE\"", .entity_name, .historical_v5);
    try std.testing.expectEqual(corpus.State.measured, historical.state);
    try std.testing.expectEqual(corpus.MetadataContract.historical_v5, historical.metadata_contract);
    try std.testing.expect(historical.native_exact_scope == null);
    try std.testing.expect(!historical.workflow_authority and !historical.semantic_quality_assessed);

    const wrong_leaf = try corpus.measure(a, .{
        .packet = packet,
        .output = "{\"value\":true}",
        .schema = "{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"boolean\"}},\"required\":[\"value\"],\"additionalProperties\":false}",
        .field_policies = &.{.{ .field = .entity_name, .path = &.{.{ .property = "value" }} }},
        .metadata_contract = .historical_v5,
    }, classifier);
    try std.testing.expectEqual(corpus.State.invalid_field_metadata, wrong_leaf.state);
}

test "current native occurrence facts remain separate from historical membership diagnostics" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const input: corpus.Input = .{
        .packet = "{\"source_assignment\":{\"requirements\":[{\"claim_id\":1}]}}",
        .output = "{\"value\":\"Display ACTIVE.\"}",
        .schema = root_schema,
        .field_policies = &.{.{ .field = .ac_then, .path = &.{.{ .property = "value" }} }},
        .exact_scope = .{ .reference_state = .{ .bytes = "REF-current" }, .occurrences = &.{.{ .claim_id = .{ .ordinal = 2 }, .bytes = "ACTIVE" }} },
    };
    const measured = try corpus.measure(a, input, classifier);
    try std.testing.expectEqual(corpus.State.measured, measured.state);
    try std.testing.expectEqual(@as(usize, 1), measured.occurrence_count);
    try std.testing.expectEqual(@as(u32, 2), measured.native_exact_scope.?.occurrences[0].claim_id.ordinal);
    try std.testing.expectEqual(.selected_requirement_membership, measured.binding_policy);
    try std.testing.expectEqual(@as(usize, 0), measured.fields[0].plain_runs[0].result.matches.len);
    try std.testing.expectEqual(@as(usize, 1), measured.fields[0].plain_runs[0].result.unbound_matches.len);
    var forged_history = input;
    forged_history.metadata_contract = .historical_v5;
    const rejected = try corpus.measure(a, forged_history, classifier);
    try std.testing.expectEqual(corpus.State.invalid_field_metadata, rejected.state);
    try std.testing.expectEqual(@as(usize, 0), rejected.fields.len);
    try std.testing.expect(rejected.native_exact_scope == null);
}

test "prototype lexical matches inside encoded insertion syntax cannot repair the native rejection" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const measured = try corpus.measure(a, .{
        .packet =
        \\{"preserved_tokens":[{"claim_id":1,"value":"exact_copy"}],"source_assignment":{"requirements":[{"claim_id":1}]}}
        ,
        .output = try valueOutput(a,
            \\"{\"kind\":\"exact_copy\",\"claim_id\":1}"
        ),
        .schema = root_schema,
        .field_policies = &.{.{ .field = .ac_then, .path = &.{.{ .property = "value" }} }},
        .original_sources = &.{},
    }, classifier);
    try std.testing.expectEqual(.measured, measured.state);
    try std.testing.expectEqual(.matched, measured.fields[0].plain_runs[0].result.state);
    try std.testing.expectEqual(@as(usize, 1), measured.fields[0].plain_runs[0].result.matches.len);
    try std.testing.expectEqual(@as(usize, 0), measured.fields[0].typed_exact_references.len);
    try std.testing.expectEqual(.invalid, measured.fields[0].original_composition);
    try std.testing.expectEqual(.invalid, measured.fields[0].proposed_composition);
    try std.testing.expectEqual(.embedded_insertion_syntax, measured.fields[0].proposed_composition_issue.?);
}

test "prototype literal runs do not invent whole word boundaries next to typed insertions" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const separated = try measureContract(a,
        \\{"fragments":["ACT",{"kind":"exact_copy","claim_id":1},"IVE"]}
    , .ac_then, .historical_v5);
    try std.testing.expectEqual(@as(usize, 2), separated.fields[0].plain_runs.len);
    for (separated.fields[0].plain_runs) |run| {
        try std.testing.expectEqual(.unavailable_boundary_context, run.result.state);
        try std.testing.expectEqual(@as(usize, 0), run.result.matches.len);
        try std.testing.expectEqual(@as(usize, 0), run.result.unbound_matches.len);
    }
    try std.testing.expectEqual(.valid, separated.fields[0].original_composition);
    try std.testing.expectEqual(.not_evaluated, separated.fields[0].proposed_composition);
    try std.testing.expectEqual(.no_match, separated.fields[0].historical_typed_counterfactual.?.result.state);

    const adjacent = try measure(a,
        \\{"fragments":["AC","TIVE"]}
    , .ac_then);
    try std.testing.expectEqual(@as(usize, 1), adjacent.fields[0].plain_runs.len);
    try std.testing.expectEqual(.matched, adjacent.fields[0].plain_runs[0].result.state);
    try std.testing.expectEqual(@as(usize, 1), adjacent.fields[0].plain_runs[0].result.matches.len);
    try std.testing.expectEqual(.reference_only, adjacent.fields[0].proposed_composition_issue.?);
}

test "prototype omitted typed occurrence identity requires constructed singleton schema evidence" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const output =
        \\{"fragments":[{"kind":"exact_copy"}]}
    ;
    // A historical schema that merely makes the identity optional supplies no
    // canonical construction witness, despite the sole available catalogue item.
    const optional_identity_schema = try std.mem.replaceOwned(u8, a, historical_text_schema, "\"required\":[\"kind\",\"claim_id\"]", "\"required\":[\"kind\"]");
    const unknown = try corpus.measure(a, .{
        .packet = packet,
        .output = try valueOutput(a, output),
        .schema = try valueSchema(a, optional_identity_schema),
        .metadata_contract = .historical_v5,
        .field_policies = &.{.{ .field = .entity_name, .path = &.{.{ .property = "value" }} }},
    }, classifier);
    try std.testing.expectEqual(.measured, unknown.state);
    try std.testing.expectEqual(@as(usize, 1), unknown.fields[0].typed_exact_references.len);
    try std.testing.expect(!unknown.fields[0].typed_exact_references[0].resolved);
    try std.testing.expectEqual(null, unknown.fields[0].typed_exact_references[0].occurrence);
    try std.testing.expectEqual(null, unknown.fields[0].historical_typed_counterfactual);

    const no_identity_property = try std.mem.replaceOwned(u8, a, historical_text_schema, ",\"claim_id\":{\"enum\":[1]}", "");
    const constructed_schema = try std.mem.replaceOwned(u8, a, no_identity_property, "\"required\":[\"kind\",\"claim_id\"]", "\"required\":[\"kind\"]");
    const constructed = try corpus.measure(a, .{
        .packet = packet,
        .output = try valueOutput(a, output),
        .schema = try valueSchema(a, constructed_schema),
        .metadata_contract = .historical_v5,
        .field_policies = &.{.{ .field = .entity_name, .path = &.{.{ .property = "value" }} }},
    }, classifier);
    try std.testing.expectEqual(.measured, constructed.state);
    try std.testing.expect(constructed.fields[0].typed_exact_references[0].resolved);
    try std.testing.expectEqual(@as(?u32, 1), constructed.fields[0].typed_exact_references[0].occurrence);
    try std.testing.expectEqual(.matched, constructed.fields[0].historical_typed_counterfactual.?.result.state);

    const required = try measureContract(a, output, .entity_name, .historical_v5);
    try std.testing.expectEqual(.schema_invalid, required.state);
    try std.testing.expectEqual(@as(usize, 0), required.fields.len);
}

test "prototype offered values do not create requirement or native field bindings" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const foreign = try corpus.measure(a, .{
        .packet =
        \\{"preserved_tokens":[{"claim_id":1,"value":"ACTIVE"}],"source_assignment":{"requirements":[{"claim_id":2}]}}
        ,
        .output = "{\"value\":\"ACTIVE\"}",
        .schema = root_schema,
        .field_policies = &.{.{ .field = .ac_then, .path = &.{.{ .property = "value" }} }},
    }, classifier);
    try std.testing.expectEqual(.measured, foreign.state);
    try std.testing.expectEqual(.assigned_requirements, foreign.fields[0].binding);
    try std.testing.expectEqual(.no_match, foreign.fields[0].plain_runs[0].result.state);
    try std.testing.expectEqual(@as(usize, 0), foreign.fields[0].plain_runs[0].result.matches.len);
    try std.testing.expectEqual(@as(usize, 1), foreign.fields[0].plain_runs[0].result.unbound_matches.len);

    const missing = try corpus.measure(a, .{
        .packet =
        \\{"preserved_tokens":[{"claim_id":1,"value":"ACTIVE"}]}
        ,
        .output = "{\"value\":\"ACTIVE\"}",
        .schema = root_schema,
    }, classifier);
    try std.testing.expectEqual(.missing, missing.fields[0].binding);
    try std.testing.expectEqual(.unavailable_field_metadata, missing.fields[0].proposed_composition);
    try std.testing.expectEqual(@as(usize, 1), missing.fields[0].plain_runs[0].result.unbound_matches.len);
    try std.testing.expect(!missing.workflow_authority and !missing.semantic_quality_assessed);

    const no_native = try corpus.measure(a, .{ .packet = packet, .output = "{\"value\":\"ACTIVE\"}", .schema = root_schema }, classifier);
    try std.testing.expectEqual(.matched, no_native.fields[0].plain_runs[0].result.state);
    try std.testing.expectEqual(null, no_native.fields[0].native_field);
    try std.testing.expectEqual(.unavailable_field_metadata, no_native.fields[0].original_composition);
    try std.testing.expectEqual(.unavailable_field_metadata, no_native.fields[0].proposed_composition);
}

test "prototype invalid selected group bindings remain visible without eligible matches" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = "{\"type\":\"object\",\"properties\":{\"signal_ids\":{\"type\":\"array\",\"items\":{\"enum\":[1,99]},\"minItems\":1,\"maxItems\":2},\"value\":" ++ text_schema ++ "},\"required\":[\"signal_ids\",\"value\"],\"additionalProperties\":false}";
    const measured = try corpus.measure(a, .{
        .packet =
        \\{"preserved_tokens":[{"claim_id":1,"value":"ACTIVE"}],"source_groups":[{"signal_id":1,"requirements":[{"claim_id":1}]}]}
        ,
        .output = "{\"signal_ids\":[99],\"value\":\"ACTIVE\"}",
        .schema = schema,
        .field_policies = &.{.{ .field = .ac_then, .path = &.{.{ .property = "value" }} }},
    }, classifier);
    try std.testing.expectEqual(.measured, measured.state);
    try std.testing.expectEqual(@as(usize, 1), measured.fields.len);
    try std.testing.expectEqualStrings("/value", measured.fields[0].path);
    try std.testing.expectEqual(.invalid, measured.fields[0].binding);
    try std.testing.expectEqual(.no_match, measured.fields[0].plain_runs[0].result.state);
    try std.testing.expectEqual(@as(usize, 0), measured.fields[0].plain_runs[0].result.matches.len);
    try std.testing.expectEqual(@as(usize, 1), measured.fields[0].plain_runs[0].result.unbound_matches.len);
}

test "prototype malformed capture projection and output schema failures have explicit dispositions" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Case = struct { input: corpus.Input, state: corpus.State };
    const cases: []const Case = &.{
        .{ .input = .{ .packet = "{", .output = "{\"value\":\"ACTIVE\"}", .schema = root_schema }, .state = .invalid_packet },
        .{ .input = .{ .packet = "{}", .output = "{\"value\":\"ACTIVE\"}", .schema = root_schema }, .state = .no_exact_context },
        .{ .input = .{ .packet = "{\"preserved_tokens\":{}}", .output = "{\"value\":\"ACTIVE\"}", .schema = root_schema }, .state = .invalid_packet },
        .{ .input = .{ .packet = "{\"preserved_tokens\":[{\"claim_id\":0,\"value\":\"ACTIVE\"}]}", .output = "{\"value\":\"ACTIVE\"}", .schema = root_schema }, .state = .invalid_packet },
        .{ .input = .{ .packet = "{\"preserved_tokens\":[{\"claim_id\":1,\"value\":\"ACTIVE\"},{\"claim_id\":1,\"value\":\"READY\"}]}", .output = "{\"value\":\"ACTIVE\"}", .schema = root_schema }, .state = .invalid_packet },
        .{ .input = .{ .packet = packet, .output = "{", .schema = root_schema }, .state = .invalid_model_json },
        .{ .input = .{ .packet = packet, .output = "\"ACTIVE\"", .schema = root_schema }, .state = .invalid_model_json },
        .{ .input = .{ .packet = packet, .output = "{\"value\":\"ACTIVE\"}" }, .state = .missing_schema },
        .{ .input = .{ .packet = packet, .output = "{\"value\":\"ACTIVE\"}", .schema = "{\"type\":\"imaginary\"}" }, .state = .unsupported_schema },
        .{ .input = .{ .packet = packet, .output = "{}", .schema = root_schema }, .state = .schema_invalid },
        .{ .input = .{ .packet = packet, .output = "{\"other\":true}", .schema = "{\"type\":\"object\",\"properties\":{\"other\":{\"type\":\"boolean\"}},\"required\":[\"other\"],\"additionalProperties\":false}" }, .state = .no_declared_text_fields },
    };
    for (cases) |case| {
        const measured = try corpus.measure(a, case.input, classifier);
        try std.testing.expectEqual(case.state, measured.state);
        try std.testing.expectEqual(@as(usize, 0), measured.fields.len);
        try std.testing.expect(!measured.workflow_authority and !measured.semantic_quality_assessed);
    }
}

test "prototype corpus CLI rejects unknown flags duplicate outputs and overlapping roots" {
    const cli = @import("cli.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectError(error.InvalidArguments, cli.parse(a, &.{ "--wat", "test/captures", "--output", "test/report.json", "--root", "test/captures" }));
    try std.testing.expectError(error.InvalidArguments, cli.parse(a, &.{ "--output", "test/report.json", "--output", "test/other.json", "--root", "test/captures" }));
    try std.testing.expectError(error.OverlappingRoots, cli.parse(a, &.{ "--output", "test/report.json", "--root", "test/captures", "--root", "test/captures/nested" }));
    try std.testing.expectError(error.OverlappingRoots, cli.parse(a, &.{ "--output", "test/report.json", "--root", "test/captures/nested", "--root", "test/captures" }));
    try std.testing.expectError(error.InvalidArguments, cli.parse(a, &.{ "--output", "test/report.json" }));
    const valid = try cli.parse(a, &.{ "--output", "test/report.json", "--root", "test/captures", "--root", "test/captures-other" });
    try std.testing.expectEqual(@as(usize, 2), valid.roots.len);
}
