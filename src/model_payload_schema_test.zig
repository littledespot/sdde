const std = @import("std");
const action = @import("actions/model/validate_model_payload_schema.zig");
const validation = @import("domain/model_payload_schema.zig");
const observation = @import("actions/model/validate_provider_invocation_observation.zig");
const decoder = @import("actions/model/decode_model_envelope.zig");
const Fixture = @import("provider_invocation_test_fixture.zig").Fixture;

const empty = "{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":false}";
const text = "{\"type\":\"string\",\"minLength\":1,\"maxLength\":2}";
const integer = "{\"type\":\"integer\",\"minimum\":-9223372036854775808,\"maximum\":9223372036854775807}";
const variants =
    \\{"oneOf":[{"type":"object","properties":{"kind":{"const":"content"},"value":{"type":"string","maxLength":8}},"required":["kind","value"],"additionalProperties":false},{"type":"object","properties":{"kind":{"const":"question"},"subject":{"enum":["alpha","beta"]}},"required":["kind","subject"],"additionalProperties":false}]}
;
const Case = struct { bytes: []const u8, rejection: ?validation.Rejection = null, path: ?[]const u8 = null };

const child_objects =
    \\{"type":"object","properties":{"optional":{"type":"object","properties":{"a~/b":{"type":"boolean"},"deep":{"type":"object","properties":{"id":{"type":"boolean"}},"required":["id"],"additionalProperties":false}},"required":["a~/b","deep"],"additionalProperties":false},"empty":{"type":"object","properties":{},"required":[],"additionalProperties":false},"loose":{"type":"object","properties":{"flag":{"type":"boolean"}},"required":[],"additionalProperties":false},"items":{"type":"array","maxItems":2,"items":{"type":"boolean"}},"choice":
++ variants ++
    \\},"required":[],"additionalProperties":false}
;

test "correction outlines expose conditional child requirements without recursive schemas" {
    var fixture: Fixture = undefined;
    try fixture.initWithSchema(child_objects);
    defer fixture.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const outline = try @import("domain/model_schema_projection.zig").outline(a, fixture.prepared.request.response_schema.root());
    try std.testing.expectEqualStrings(
        \\{"fields":{"optional":{"type":"object","required":["a~/b","deep"]},"empty":{"type":"object","required":[]},"loose":{"type":"object","required":[]},"items":{"type":"array"},"choice":{"kind":["content","question"]}},"required":[]}
    , try std.json.Stringify.valueAlloc(a, outline, .{}));
    for ([_]Case{
        .{ .bytes = "{}" },
        .{ .bytes = "{\"empty\":{},\"loose\":{}}" },
        .{ .bytes = "{\"optional\":{}}", .rejection = .missing_required_property, .path = "/optional/a~0~1b" },
        .{ .bytes = "{\"optional\":{\"a~/b\":true,\"deep\":{}}}", .rejection = .missing_required_property, .path = "/optional/deep/id" },
        .{ .bytes = "{\"optional\":{\"a~/b\":true,\"deep\":{\"id\":true}}}" },
        .{ .bytes = "{\"choice\":{}}", .rejection = .missing_required_property, .path = "/choice/kind" },
        .{ .bytes = "{\"choice\":{\"kind\":\"foreign\"}}", .rejection = .unknown_variant, .path = "/choice/kind" },
        .{ .bytes = "{\"choice\":{\"kind\":\"question\",\"subject\":\"alpha\"}}" },
    }) |case| try checkDocument(child_objects, case);
    var response = try fixture.response();
    defer response.deinit();
    var captured = try (observation.Action{}).execute(std.testing.allocator, fixture.call, &response);
    defer captured.deinit();
    try std.testing.checkAllAllocationFailures(std.testing.allocator, retryAllocation, .{ &fixture, captured.evidence, @as(@import("domain/model_protocol_retry.zig").Diagnostic, .{ .schema = .{ .reason = .type_mismatch, .expected = fixture.prepared.request.response_schema.root() } }), "Correct syntax only." });
}

test "reconciliation repair definitions admit only the natively selected payload" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/reconciliation.schema.json", a, .limited(1_048_576));
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try parser.compiler().compile(a, bytes);
    try std.testing.expect(schema.select(.{ .bytes = "repair_content" }) == null);
    for ([_][2][]const u8{
        .{ "business_text", "{\"segments\":[\"Display a greeting.\"]}" },
        .{ "reference_text", "{\"nodes\":[{\"kind\":\"source\",\"source_id\":1}]}" },
        .{ "token_reference", "{\"token_id\":1}" },
    }) |example| {
        const selected = schema.select(.{ .bytes = example[0] }).?;
        try checkDocument(selected.modelBytes(), .{ .bytes = example[1] });
        for ([_][]const u8{
            "{\"kind\":\"preserved_token\",\"token_id\":1}",
            "{\"kind\":\"model\",\"model\":{\"kind\":\"business\",\"segments\":[]}}",
            "{\"current_value\":{}}",
        }) |invalid| try checkDocument(selected.modelBytes(), .{ .bytes = invalid, .rejection = .unknown_property, .path = if (std.mem.startsWith(u8, invalid, "{\"kind\"")) "/kind" else "/current_value" });
    }
}

test "child requirements stay inside selected definitions parts and repair schemas in both modes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const canonical = try parser.compiler().compile(a, try std.fmt.allocPrint(a, "{{\"$defs\":{{\"record\":{s}}},\"type\":\"object\",\"properties\":{{}},\"required\":[],\"additionalProperties\":false}}", .{child_objects}));
    const selected = canonical.select(.{ .bytes = "record" }).?;
    const plan = try parser.compiler().compileComposition(a,
        \\{"schema":"json-composition/v1","result":"result","definition":"record","parts":{"selected":{"paths":["/optional"]},"siblings":{"paths":["/empty","/loose","/items","/choice"]}}}
    , canonical);
    const generation = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/generation.schema.json", a, .limited(1_048_576)));
    const repair_schema = generation.select(.{ .bytes = "attributed_value" }).?;
    for ([_]*const @import("domain/model_result_schema.zig").Schema{ selected, try plan.selectSchema(0, &.{}), repair_schema }) |schema| {
        var fixture: Fixture = undefined;
        try fixture.initWithCompiledSchema(schema);
        defer fixture.deinit();
        fixture.fake.invocation_plan.complete.content = "{\"foreign\":true}";
        var response = try fixture.response();
        defer response.deinit();
        var captured = try (observation.Action{}).execute(std.testing.allocator, fixture.call, &response);
        defer captured.deinit();
        var decoded = try (decoder.Action{}).execute(std.testing.allocator, captured.evidence.result().complete, null);
        defer decoded.deinit();
        const diagnostic = validation.validate(decoded.candidate).invalid;
        var retry = try (@import("actions/model/build_model_protocol_retry.zig").Action{}).execute(std.testing.allocator, try fixture.requestSource(), fixture.prepared.request.content, captured.evidence, .{ .schema = diagnostic }, .unconfirmed, "Correct syntax only.");
        defer retry.deinit();
        const guidance = try std.json.parseFromSlice(std.json.Value, a, retry.request.content[retry.request.content.len - 2].guidance, .{});
        const expected = guidance.value.object.get("expected").?.object;
        try std.testing.expectEqualStrings("", expected.get("schema_pointer").?.string);
        const fields = expected.get("shape").?.object.get("fields").?.object;
        const child = fields.get(if (schema == repair_schema) "provenance" else "optional").?.object;
        try std.testing.expectEqual(@as(usize, 2), child.count());
        try std.testing.expectEqualStrings(if (schema == repair_schema) "[\"claim_ids\",\"clarification_response_ids\"]" else "[\"a~/b\",\"deep\"]", try std.json.Stringify.valueAlloc(a, child.get("required").?, .{}));
        if (schema != selected) try std.testing.expect(!fields.contains("items") and !fields.contains("loose"));
        for (std.enums.values(@import("domain/model_controls.zig").ResponseGuidanceMode)) |mode| {
            var request = retry.request.*;
            request.response_guidance_mode = mode;
            const bytes = try @import("adapters/provider/bedrock_request.zig").encode(a, &request, .inference);
            const wire = try std.json.parseFromSlice(std.json.Value, a, bytes, .{});
            var count: usize = 0;
            for (wire.value.object.get("messages").?.array.items[0].object.get("content").?.array.items) |part| count += @intFromBool(std.mem.eql(u8, part.object.get("text").?.string, schema.modelBytes()));
            try std.testing.expectEqual(@as(usize, 1), count);
            try std.testing.expectEqual(mode == .native_schema, wire.value.object.contains("response_format"));
        }
    }
}

test "native generation projection preserves variants while full schema retains bound authority" {
    const contract =
        \\{"type":"object","properties":{"items":{"type":"array","minItems":2,"maxItems":3,"items":{"oneOf":[{"type":"object","properties":{"kind":{"const":"text"},"value":{"type":"string","minLength":1,"maxLength":2}},"required":["kind","value"],"additionalProperties":false},{"type":"object","properties":{"kind":{"const":"count"},"value":{"type":"integer","minimum":1,"maximum":9}},"required":["kind","value"],"additionalProperties":false}]}}},"required":["items"],"additionalProperties":false}
    ;
    var fixture: Fixture = undefined;
    try fixture.initWithSchema(contract);
    defer fixture.deinit();
    const source = fixture.resource.content.result_schema;
    const projection = try @import("domain/model_schema_projection.zig").render(std.testing.allocator, source, .bedrock);
    defer std.testing.allocator.free(projection);
    var projected = try @import("domain/strict_json.zig").parse(std.testing.allocator, projection, .{ .maximum_depth = 32 }, true, null);
    defer projected.deinit();
    const items = projected.value.object.get("properties").?.object.get("items").?.object;
    try std.testing.expectEqual(@as(i64, 1), items.get("minItems").?.integer);
    const choices = items.get("items").?.object.get("anyOf").?.array.items;
    try std.testing.expectEqual(@as(usize, 2), choices.len);
    for (choices, [_][]const u8{ "text", "count" }) |choice, tag| {
        try std.testing.expectEqualStrings(tag, choice.object.get("properties").?.object.get("kind").?.object.get("const").?.string);
        try std.testing.expect(!choice.object.get("additionalProperties").?.bool);
        try std.testing.expectEqual(@as(usize, 2), choice.object.get("required").?.array.items.len);
    }
    for ([_][]const u8{ "oneOf", "minLength", "maxLength", "minimum", "maximum", "maxItems" }) |keyword|
        try std.testing.expect(std.mem.indexOf(u8, projection, keyword) == null);
    for ([_]Case{
        .{ .bytes = "{\"items\":[{\"kind\":\"text\",\"value\":\"ok\"},{\"kind\":\"count\",\"value\":3}]}" },
        .{ .bytes = "{\"items\":[{\"kind\":\"count\",\"value\":3}]}", .rejection = .array_length },
        .{ .bytes = "{\"items\":[{\"kind\":\"text\",\"value\":\"long\"},{\"kind\":\"count\",\"value\":3}]}", .rejection = .string_length },
        .{ .bytes = "{\"items\":[{\"kind\":\"text\",\"value\":\"ok\"},{\"kind\":\"count\",\"value\":10}]}", .rejection = .integer_range },
        .{ .bytes = "{\"items\":[{\"value\":\"ok\"},{\"kind\":\"count\",\"value\":3}]}", .rejection = .missing_required_property },
    }) |case| try checkDocument(contract, case);
}

test "schema diagnostics identify nested fields and array indices without relaxing closed validation" {
    const contract =
        \\{"type":"object","properties":{"entries":{"type":"array","maxItems":4,"items":{"oneOf":[{"type":"object","properties":{"kind":{"const":"text"},"value":{"type":"string","maxLength":8}},"required":["kind","value"],"additionalProperties":false},{"type":"object","properties":{"kind":{"const":"reference"},"id":{"type":"integer","minimum":1,"maximum":9}},"required":["kind","id"],"additionalProperties":false}]}}},"required":["entries"],"additionalProperties":false}
    ;
    for ([_]Case{
        .{ .bytes = "{\"entries\":[{\"text\":{\"value\":\"hello\"}}]}", .rejection = .missing_required_property, .path = "/entries/0/kind" },
        .{ .bytes = "{\"entries\":[{\"kind\":\"text\",\"value\":\"hello\"},{\"kind\":\"reference\",\"id\":0}]}", .rejection = .integer_range, .path = "/entries/1/id" },
        .{ .bytes = "{\"entries\":[{\"kind\":\"reference\",\"id\":1,\"a~/b\":2}]}", .rejection = .unknown_property, .path = "/entries/0/a~0~1b" },
        .{ .bytes = "{\"entries\":[{\"kind\":false}]}", .rejection = .type_mismatch, .path = "/entries/0/kind" },
        .{ .bytes = "{\"entries\":[{\"kind\":\"absent\"}]}", .rejection = .unknown_variant, .path = "/entries/0/kind" },
        .{ .bytes = "{\"entries\":[{\"kind\":\"reference\"}]}", .rejection = .missing_required_property, .path = "/entries/0/id" },
        .{ .bytes = "{\"entries\":[{\"kind\":\"text\",\"value\":\"hello\"},{\"kind\":\"reference\",\"id\":1}]}" },
    }) |case| try checkDocument(contract, case);
    try checkDocument(empty, .{ .bytes = "{\"unexpected\":true}", .rejection = .unknown_property, .path = "/unexpected" });
}

test "correction schema retains nested alternatives and exact bounds without candidate examples" {
    const contract =
        \\{"type":"object","properties":{"statements":{"type":"array","maxItems":2,"items":{"type":"object","properties":{"content":{"oneOf":[{"type":"object","properties":{"kind":{"const":"model"},"text":{"type":"string","maxLength":8}},"required":["kind","text"],"additionalProperties":false},{"type":"object","properties":{"kind":{"const":"preserved_token"},"token_id":{"type":"integer","minimum":1,"maximum":9}},"required":["kind","token_id"],"additionalProperties":false}]}},"required":["content"],"additionalProperties":false}},"empty":{"type":"array","maxItems":0,"items":{"type":"boolean"}}},"required":["statements","empty"],"additionalProperties":false}
    ;
    try checkDocument(contract, .{ .bytes = "{}", .rejection = .missing_required_property, .path = "/statements" });
    try checkDocument(contract, .{ .bytes = "{\"statements\":[{\"content\":{}}],\"empty\":[]}", .rejection = .missing_required_property, .path = "/statements/0/content/kind" });
    try checkDocument(contract, .{ .bytes = "{\"statements\":[{\"content\":{\"kind\":\"preserved_token\",\"token_id\":10}}],\"empty\":[]}", .rejection = .integer_range, .path = "/statements/0/content/token_id" });
    try checkDocument(contract, .{ .bytes = "{\"statements\":[{\"content\":{\"kind\":\"model\",\"text\":\"hello\"}},{\"content\":{\"kind\":\"preserved_token\",\"token_id\":7}}],\"empty\":[]}" });
}

test "independent values cover unrelated closed schemas and explicit null fields" {
    try checkDocument(empty, .{ .bytes = "{}" });
    try checkDocument(variants, .{ .bytes = "{\"kind\":\"question\",\"subject\":\"beta\"}" });
    const contract =
        \\{"type":"object","properties":{"count":{"type":"integer","minimum":3,"maximum":9},"items":{"type":"array","minItems":2,"maxItems":3,"items":{"type":"string","minLength":2,"maxLength":8}},"enabled":{"type":"boolean"},"absent":{"type":"null"}},"required":["count","items","enabled","absent"],"additionalProperties":false}
    ;
    try checkDocument(contract, .{ .bytes = "{\"count\":7,\"items\":[\"first\",\"second\"],\"enabled\":true,\"absent\":null}" });
    try checkDocument(contract, .{ .bytes = "{\"count\":7,\"items\":[\"first\",\"second\"],\"enabled\":true}", .rejection = .missing_required_property, .path = "/absent" });
}

test "protocol retry retains exact request schema and identity and releases every failed allocation" {
    var fixture: Fixture = undefined;
    try fixture.initWithSchema(variants);
    defer fixture.deinit();
    var response = try fixture.response();
    defer response.deinit();
    var captured = try (observation.Action{}).execute(std.testing.allocator, fixture.call, &response);
    defer captured.deinit();
    const rejected = captured.evidence;
    const diagnostic: @import("domain/model_protocol_retry.zig").Diagnostic = .{ .schema = .{ .reason = .missing_required_property, .expected = fixture.prepared.request.response_schema.root() } };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, retryAllocation, .{ &fixture, rejected, diagnostic, "Correct syntax only." });
    var source = try fixture.requestSource();
    var other: Fixture = undefined;
    try other.initWithSchema(empty);
    defer other.deinit();
    source.result_resource = &other.resource;
    try std.testing.expectError(error.ModelRequestAssociationInvalid, (@import("actions/model/build_model_protocol_retry.zig").Action{}).execute(std.testing.allocator, source, fixture.prepared.request.content, rejected, .{ .decoder = .{ .reason = .ExpectedObject } }, .unconfirmed, "Correct syntax only."));
    try std.testing.expectError(error.ModelRequestAssociationInvalid, (@import("actions/model/build_model_protocol_retry.zig").Action{}).execute(std.testing.allocator, try fixture.requestSource(), fixture.prepared.request.content, rejected, .{ .schema = .{ .reason = .type_mismatch, .expected = other.prepared.request.response_schema.root() } }, .unconfirmed, "Correct syntax only."));
    const child = @import("domain/model_result_schema.zig").findProperty(fixture.prepared.request.response_schema.root().one_of[0].object, "value").?.schema;
    try std.testing.checkAllAllocationFailures(std.testing.allocator, retryAllocation, .{ &fixture, rejected, @as(@import("domain/model_protocol_retry.zig").Diagnostic, .{ .schema = .{ .reason = .string_length, .expected = child } }), "Correct syntax only." });
}

test "missing-answer correction admits only validated missing content and cleans up every failed allocation" {
    var fixture: Fixture = undefined;
    try fixture.initWithSchema(variants);
    defer fixture.deinit();
    var response = try fixture.response();
    const prior = response.completed.raw_result.complete;
    response.deinit();
    response = .{ .completed = .{ .operation_id = fixture.authorized.invoked.id, .raw_result = .{ .rejected = .{
        .request_id = fixture.prepared.request.model_request_id,
        .binding_id = fixture.prepared.request.binding_id,
        .reason = .missing_final_text,
        .usage = prior.usage,
        .provider_latency_ms = prior.provider_latency_ms,
    } } } };
    defer response.deinit();
    var captured = try (observation.Action{}).execute(std.testing.allocator, fixture.call, &response);
    defer captured.deinit();
    try std.testing.expect(captured.evidence.missingFinalText());
    try std.testing.checkAllAllocationFailures(std.testing.allocator, retryAllocation, .{ &fixture, captured.evidence, @as(@import("domain/model_protocol_retry.zig").Diagnostic, .missing_final_text), "Return the complete assigned response." });
    const retry_action: @import("actions/model/build_model_protocol_retry.zig").Action = .{};
    try std.testing.expectError(error.ModelRequestAssociationInvalid, retry_action.execute(std.testing.allocator, try fixture.requestSource(), fixture.prepared.request.content, captured.evidence, .{ .decoder = .{ .reason = .ExpectedObject } }, .unconfirmed, "Correct syntax only."));
}

test "correction locators resolve escaped names root alternatives and selected definitions" {
    try checkDocument(variants, .{ .bytes = "{\"kind\":\"content\"}", .rejection = .missing_required_property, .path = "/value" });
    try checkDocument(variants, .{ .bytes = "{\"kind\":\"unknown\"}", .rejection = .unknown_variant, .path = "/kind" });
    try checkDocument(variants, .{ .bytes = "{\"kind\":\"question\",\"subject\":\"foreign\"}", .rejection = .enum_mismatch, .path = "/subject" });
    const escaped =
        \\{"type":"object","properties":{"a~/b":{"type":"object","properties":{"count":{"type":"integer","minimum":1,"maximum":9}},"required":["count"],"additionalProperties":false}},"required":["a~/b"],"additionalProperties":false}
    ;
    try checkDocument(escaped, .{ .bytes = "{\"a~/b\":{\"count\":10}}", .rejection = .integer_range, .path = "/a~0~1b/count" });
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/reconciliation.schema.json", a, .unlimited);
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const compiled = try parser.compiler().compile(a, bytes);
    const selected = compiled.select(.{ .bytes = "summary" }).?;
    const cases = [_]Case{
        .{ .bytes = "{\"statements\":[{\"local_key\":1,\"claim_ids\":[1],\"content\":{\"model\":{\"kind\":\"business\",\"segments\":[]}}}]}", .rejection = .missing_required_property, .path = "/statements/0/content/kind" },
        .{ .bytes = "{\"statements\":[{\"local_key\":1,\"claim_ids\":[1],\"kind\":\"model\",\"content\":{\"model\":{\"kind\":\"business\",\"segments\":[]}}}]}", .rejection = .unknown_property, .path = "/statements/0/kind" },
    };
    for (cases) |case| try checkDocument(selected.modelBytes(), case);
    const projection = @import("domain/model_schema_projection.zig");
    const schema = @import("domain/model_result_schema.zig");
    const statement = schema.findProperty(selected.root().object, "statements").?.schema.array.items;
    const content = schema.findProperty(statement.object, "content").?.schema;
    try std.testing.expectEqualStrings("/properties/statements/items/properties/content", (try projection.locate(a, selected, content)).?);
    const shape = (try projection.outline(a, statement)).object;
    try std.testing.expectEqual(@as(usize, 3), shape.get("fields").?.object.count());
    try std.testing.expectEqual(@as(usize, 3), shape.get("required").?.array.items.len);
    const tags = shape.get("fields").?.object.get("content").?.object.get("kind").?.array.items;
    try std.testing.expectEqual(@as(usize, 2), tags.len);
    try std.testing.expectEqualStrings("model", tags[0].string);
    try std.testing.expectEqualStrings("preserved_token", tags[1].string);
    try std.testing.expect(!shape.get("fields").?.object.get("claim_ids").?.object.contains("items"));
    try std.testing.expect(try projection.locate(a, selected, compiled.root()) == null);
}

fn retryAllocation(allocator: std.mem.Allocator, fixture: *Fixture, rejected: *const @import("domain/provider_invocation_validation.zig").Evidence, diagnostic: @import("domain/model_protocol_retry.zig").Diagnostic, prompt: []const u8) !void {
    const source = try fixture.requestSource();
    var retried = try (@import("actions/model/build_model_protocol_retry.zig").Action{}).execute(allocator, source, fixture.prepared.request.content, rejected, diagnostic, .unconfirmed, prompt);
    defer retried.deinit();
    try std.testing.expect(retried.request.model_request_id == fixture.prepared.request.model_request_id);
    try std.testing.expect(retried.request.response_schema == fixture.prepared.request.response_schema);
    try std.testing.expectEqual(fixture.prepared.request.content.len + @as(usize, if (diagnostic == .missing_final_text) 2 else 3), retried.request.content.len);
    for (fixture.prepared.request.content, retried.request.content[0..fixture.prepared.request.content.len]) |original, copied| try std.testing.expectEqualDeep(original, copied);
    try std.testing.expectEqual(@as(usize, 1), fixture.fake.invocation_call_count);
}

test "selected protocol guidance explains duplicate property names and preserves native diagnostics" {
    const strict = @import("domain/strict_json.zig");
    const prompt = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/protocol.prompt.md", std.testing.allocator, .unlimited);
    defer std.testing.allocator.free(prompt);
    for ([_][]const u8{ "complete corrected response", "original schema", "unaffected entries", "business meaning" }) |instruction|
        try std.testing.expect(std.mem.indexOf(u8, prompt, instruction) != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "examples") == null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "placeholder") == null);
    for ([_][]const u8{
        "```json\n{}\n```",
        "{\n\"answer\":}",
        "{\"statements\":[{\"local_key\":1,\"content\":\"first\",\"local_key\":2,\"content\":\"second\"}]}",
        "{\"groups\":[{\"items\":[{\"code\":\"a\",\"\\u0063ode\":\"b\"}]}]}",
    }) |bytes| {
        var fixture: Fixture = undefined;
        try fixture.initWithSchema(variants);
        defer fixture.deinit();
        fixture.fake.invocation_plan = .{ .complete = .{ .content = bytes, .input_tokens = 10, .output_tokens = 2 } };
        var response = try fixture.response();
        defer response.deinit();
        var captured = try (observation.Action{}).execute(std.testing.allocator, fixture.call, &response);
        defer captured.deinit();
        var diagnostic: ?strict.Diagnostic = null;
        defer if (diagnostic) |value| value.deinit(std.testing.allocator);
        try std.testing.expectError(error.InvalidJsonDocument, strict.parse(std.testing.allocator, bytes, .{ .maximum_depth = 64 }, false, &diagnostic));
        var retried = try (@import("actions/model/build_model_protocol_retry.zig").Action{}).execute(std.testing.allocator, try fixture.requestSource(), fixture.prepared.request.content, captured.evidence, .{ .decoder = diagnostic.? }, .unconfirmed, prompt);
        defer retried.deinit();
        const content = retried.request.content;
        var guidance = try strict.parse(std.testing.allocator, content[content.len - 2].guidance, .{ .maximum_depth = 64 }, true, null);
        defer guidance.deinit();
        var evidence = try strict.parse(std.testing.allocator, content[content.len - 1].evidence, .{ .maximum_depth = 64 }, true, null);
        defer evidence.deinit();
        try std.testing.expectEqualStrings(bytes, evidence.value.object.get("rejected_response").?.string);
        try std.testing.expectEqualStrings(prompt, content[content.len - 3].guidance);
        const duplicate = diagnostic.?.reason == .DuplicateField;
        try std.testing.expectEqual(@as(usize, 2), guidance.value.object.count());
        try std.testing.expect(std.mem.startsWith(u8, guidance.value.object.get("explanation").?.string, "JSON decoding failed:"));
        if (duplicate) {
            try std.testing.expectEqualStrings("JSON decoding failed: property names must be unique within each object. This diagnostic concerns repeated names, not repeated identifier values.", guidance.value.object.get("explanation").?.string);
            try std.testing.checkAllAllocationFailures(std.testing.allocator, retryAllocation, .{ &fixture, captured.evidence, @as(@import("domain/model_protocol_retry.zig").Diagnostic, .{ .decoder = diagnostic.? }), prompt });
        }
        const supplied = guidance.value.object.get("diagnostic").?.object.get("decoder").?.object;
        try std.testing.expectEqual(@as(usize, 3), supplied.count());
        try std.testing.expectEqualStrings(@tagName(diagnostic.?.reason), supplied.get("reason").?.string);
        const context = try std.json.Stringify.valueAlloc(std.testing.allocator, diagnostic.?.context, .{});
        defer std.testing.allocator.free(context);
        const encoded_context = try std.json.Stringify.valueAlloc(std.testing.allocator, supplied.get("context").?, .{});
        defer std.testing.allocator.free(encoded_context);
        try std.testing.expectEqualStrings(context, encoded_context);
        const position = supplied.get("location").?.object;
        try std.testing.expectEqual(@as(i128, diagnostic.?.location.?.byte_offset), position.get("byte_offset").?.integer);
        try std.testing.expectEqual(@as(i128, diagnostic.?.location.?.line), position.get("line").?.integer);
        try std.testing.expectEqual(@as(i128, diagnostic.?.location.?.column), position.get("column").?.integer);
        try std.testing.expect(retried.request.model_request_id == fixture.prepared.request.model_request_id);
        try std.testing.expect(retried.request.response_schema == fixture.prepared.request.response_schema);
        try std.testing.expectEqual(@as(usize, 1), fixture.fake.invocation_call_count);
    }
}

test "unrelated schemas retain one universal framing instruction across initial calls retries and counting" {
    const framing = @import("domain/model_controls.zig").response_format_guidance;
    const encoding = @import("adapters/provider/bedrock_request.zig");
    const provider = @import("domain/llm_provider_operation.zig");
    for ([_][]const u8{ empty, variants }) |contract| {
        var fixture: Fixture = undefined;
        try fixture.initWithSchema(contract);
        defer fixture.deinit();
        var response = try fixture.response();
        defer response.deinit();
        var captured = try (observation.Action{}).execute(std.testing.allocator, fixture.call, &response);
        defer captured.deinit();
        var retried = try (@import("actions/model/build_model_protocol_retry.zig").Action{}).execute(std.testing.allocator, try fixture.requestSource(), fixture.prepared.request.content, captured.evidence, .{ .schema = .{ .reason = .missing_required_property, .expected = fixture.prepared.request.response_schema.root() } }, .unconfirmed, "Correct syntax only.");
        defer retried.deinit();
        for ([_]*const provider.IdentifiedProviderNeutralModelRequest{ fixture.prepared.request, retried.request }) |request| {
            // Retry-owned content retains task guidance only; serialization adds framing.
            for (request.content) |part| try std.testing.expect(std.mem.indexOf(u8, part.bytes(), framing) == null);
            for ([_]provider.ProviderOperationKind{ .inference, .input_token_count }) |kind| {
                const bytes = try encoding.encode(std.testing.allocator, request, kind);
                defer std.testing.allocator.free(bytes);
                const decoded_body = try @import("bedrock_transport_test_fixture.zig").requestBody(std.testing.allocator, bytes, kind);
                defer std.testing.allocator.free(decoded_body);
                try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, decoded_body, framing));
                var parsed = try @import("domain/strict_json.zig").parse(std.testing.allocator, decoded_body, .{ .maximum_depth = 64 }, false, null);
                defer parsed.deinit();
                const root = parsed.value;
                const system = root.object.get("messages").?.array.items[0].object.get("content").?.array.items;
                try std.testing.expectEqualStrings(framing, system[system.len - 2].object.get("text").?.string);
                try std.testing.expectEqualStrings(request.response_schema.modelBytes(), system[system.len - 1].object.get("text").?.string);
            }
        }
    }
}

test "fake provider through decode and schema validation retains only existing candidate authority" {
    try checkDocument(empty, .{ .bytes = "{}" });
    const schema =
        \\{"type":"object","properties":{"status":{"enum":["completed"]},"requestId":{"type":"string","maxLength":32},"values":{"type":"array","minItems":1,"maxItems":2,"items":{"type":"integer","minimum":1,"maximum":2}},"optional":{"type":"boolean"}},"required":["status","requestId","values"],"additionalProperties":false}
    ;
    try checkDocument(schema, .{ .bytes = "{\"status\":\"completed\",\"requestId\":\"model-only\",\"values\":[1.0,2e0]}" });
}

test "complete model payloads beyond former byte ceilings still use their exact schema" {
    const bytes = try std.testing.allocator.alloc(u8, 16_384);
    defer std.testing.allocator.free(bytes);
    @memset(bytes, 'x');
    const string = try std.fmt.allocPrint(std.testing.allocator, "\"{s}\"", .{bytes});
    defer std.testing.allocator.free(string);
    try checkField("{\"type\":\"string\",\"maxLength\":16384}", &.{.{ .bytes = string }});
    const array = try std.fmt.allocPrint(std.testing.allocator, "[{s},{s}]", .{ string, string });
    defer std.testing.allocator.free(array);
    try checkField("{\"type\":\"array\",\"maxItems\":2,\"items\":{\"type\":\"string\",\"maxLength\":16384}}", &.{.{ .bytes = array }});
    // Removing API-size caps does not weaken workflow-declared schema rules.
    try checkField("{\"type\":\"string\",\"maxLength\":16383}", &.{.{ .bytes = string, .rejection = .string_length }});
}

test "closed objects reject unknown and missing properties but do not fill optional fields" {
    const schema =
        \\{"type":"object","properties":{"required":{"type":"boolean"},"optional":{"type":"null"}},"required":["required"],"additionalProperties":false}
    ;
    for ([_]Case{
        .{ .bytes = "{\"required\":true}" },
        .{ .bytes = "{\"required\":false,\"optional\":null}" },
        .{ .bytes = "{}", .rejection = .missing_required_property },
        .{ .bytes = "{\"optional\":null}", .rejection = .missing_required_property },
        .{ .bytes = "{\"required\":true,\"extra\":null}", .rejection = .unknown_property },
        .{ .bytes = "{\"required\":true,\"optional\":null,\"extra\":null}", .rejection = .unknown_property },
        .{ .bytes = "{\"required\":null}", .rejection = .type_mismatch },
        .{ .bytes = "{\"required\":true,\"optional\":false}", .rejection = .type_mismatch },
    }) |case| try checkDocument(schema, case);
    try checkField(empty, &.{
        .{ .bytes = "{}" },
        .{ .bytes = "{\"extra\":1}", .rejection = .unknown_property },
        .{ .bytes = "[]", .rejection = .type_mismatch },
        .{ .bytes = "null", .rejection = .type_mismatch },
    });
}

test "property names use decoded exact keys without Unicode normalization or positional matching" {
    const schema =
        \\{"type":"object","properties":{"é":{"type":"boolean"},"":{"type":"null"}},"required":["é",""],"additionalProperties":false}
    ;
    try checkDocument(schema, .{ .bytes = "{\"\":null,\"\\u00e9\":true}" });
    try checkDocument(schema, .{ .bytes = "{\"\":null,\"e\\u0301\":true}", .rejection = .unknown_property });
    const targets =
        \\{"type":"object","properties":{"replacementsByTargetId":{"type":"object","properties":{"a":{"type":"string","maxLength":3},"b":{"type":"string","maxLength":3}},"required":["a","b"],"additionalProperties":false}},"required":["replacementsByTargetId"],"additionalProperties":false}
    ;
    try checkDocument(targets, .{ .bytes = "{\"replacementsByTargetId\":{\"b\":\"two\",\"a\":\"one\"}}" });
    try checkDocument(targets, .{ .bytes = "{\"replacementsByTargetId\":{\"a\":\"one\"}}", .rejection = .missing_required_property });
    try checkDocument(targets, .{ .bytes = "{\"replacementsByTargetId\":{\"a\":\"one\",\"c\":\"two\"}}", .rejection = .unknown_property });
    try checkDocument(targets, .{ .bytes = "{\"replacementsByTargetId\":[\"one\",\"two\"]}", .rejection = .type_mismatch });
}

test "string bounds count Unicode scalar values rather than bytes escapes or graphemes" {
    try checkField(text, &.{
        .{ .bytes = "\"a\"" },                                .{ .bytes = "\"ab\"" },
        .{ .bytes = "\"é\"" },
        .{ .bytes = "\"😀\"" },
        .{ .bytes = "\"\\ud83d\\ude00\"" },                   .{ .bytes = "\"e\\u0301\"" },
        .{ .bytes = "\"\\u0000\\n\"" },                       .{ .bytes = "\"\"", .rejection = .string_length },
        .{ .bytes = "\"abc\"", .rejection = .string_length },
        .{ .bytes = "\"😀‍😀\"", .rejection = .string_length },
        .{ .bytes = "1", .rejection = .type_mismatch },       .{ .bytes = "null", .rejection = .type_mismatch },
    });
    try checkField("{\"type\":\"string\",\"maxLength\":0}", &.{
        .{ .bytes = "\"\"" }, .{ .bytes = "\"a\"", .rejection = .string_length },
    });
}

test "integer semantics are exact across decimal exponent and signed 64 bit boundaries" {
    try checkField(integer, &.{
        .{ .bytes = "0" },                                               .{ .bytes = "-0.0" },                                                 .{ .bytes = "1.0" },                                                           .{ .bytes = "1e0" },                                                  .{ .bytes = "10e-1" },
        .{ .bytes = "0.001e3" },                                         .{ .bytes = "1.2300e2" },                                             .{ .bytes = "-0.0001200e5" },                                                  .{ .bytes = "9007199254740993" },                                     .{ .bytes = "9007199254740993.0" },
        .{ .bytes = "9223372036854775807" },                             .{ .bytes = "-9223372036854775808" },                                 .{ .bytes = "9.223372036854775807e18" },                                       .{ .bytes = "-9223372036854775808.000" },                             .{ .bytes = "1000000000000000000000000e-24" },
        .{ .bytes = "1e+000000000000000000000000000000" },               .{ .bytes = "0e999999999999999999999999999999" },                     .{ .bytes = "-0.000e-999999999999999999999999999999" },                        .{ .bytes = "1.01", .rejection = .type_mismatch },                    .{ .bytes = "1e-1", .rejection = .type_mismatch },
        .{ .bytes = "9007199254740993.1", .rejection = .type_mismatch }, .{ .bytes = "9223372036854775808", .rejection = .integer_range },     .{ .bytes = "-9223372036854775809", .rejection = .integer_range },             .{ .bytes = "9.223372036854775808e18", .rejection = .integer_range }, .{ .bytes = "1e19", .rejection = .integer_range },
        .{ .bytes = "1e9999", .rejection = .integer_range },             .{ .bytes = "100e9223372036854775807", .rejection = .integer_range }, .{ .bytes = "1e999999999999999999999999999999", .rejection = .integer_range }, .{ .bytes = "1e-9223372036854775808", .rejection = .type_mismatch },  .{ .bytes = "1e-999999999999999999999999999999", .rejection = .type_mismatch },
        .{ .bytes = "\"1\"", .rejection = .type_mismatch },              .{ .bytes = "true", .rejection = .type_mismatch },
    });
    try checkField("{\"type\":\"integer\",\"minimum\":-2,\"maximum\":2}", &.{
        .{ .bytes = "-2.0" },                            .{ .bytes = "2e0" },                            .{ .bytes = "0" },
        .{ .bytes = "-3", .rejection = .integer_range }, .{ .bytes = "3", .rejection = .integer_range },
    });
}

test "integer constants share exact numeric interpretation and do not round fractional tails" {
    try checkField("{\"const\":1}", &.{
        .{ .bytes = "1" },                                                               .{ .bytes = "1.0" },                                                             .{ .bytes = "0.1e1" },
        .{ .bytes = "1.0000000000000000000000000001", .rejection = .constant_mismatch }, .{ .bytes = "0.9999999999999999999999999999", .rejection = .constant_mismatch }, .{ .bytes = "2", .rejection = .constant_mismatch },
        .{ .bytes = "\"1\"", .rejection = .constant_mismatch },                          .{ .bytes = "true", .rejection = .constant_mismatch },                           .{ .bytes = "1e9999", .rejection = .constant_mismatch },
    });
    try checkField("{\"const\":-9223372036854775808}", &.{
        .{ .bytes = "-9.223372036854775808e18" }, .{ .bytes = "9223372036854775808", .rejection = .constant_mismatch },
    });
    try checkField("{\"const\":0}", &.{.{ .bytes = "-0e999999999999999999999999999999" }});
}

test "equivalent decimal spellings preserve integer constants across signs and scales" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    for ([_]i64{ -12345, -1, 0, 1, 12345, std.math.minInt(i64), std.math.maxInt(i64) }) |expected| {
        const field = try std.fmt.allocPrint(allocator, "{{\"const\":{d}}}", .{expected});
        for ([_]usize{ 0, 1, 20, 200 }) |zeroes| {
            const padding = try allocator.alloc(u8, zeroes);
            @memset(padding, '0');
            const scaled = try std.fmt.allocPrint(allocator, "{d}{s}e-{d}", .{ expected, padding, zeroes });
            // JSON itself prohibits leading zeroes in a multi-digit integer.
            // Zero's exponent-independent case is exercised with a fraction.
            const bytes = if (expected == 0)
                try std.fmt.allocPrint(allocator, "0.0{s}e-{d}", .{ padding, zeroes })
            else
                scaled;
            try checkField(field, &.{.{ .bytes = bytes }});
        }
    }
    try checkField("{\"type\":\"integer\",\"minimum\":0,\"maximum\":0}", &.{
        .{ .bytes = "-0.0e123" }, .{ .bytes = "1", .rejection = .integer_range },
    });
}

test "boolean null constants and enumerations reject wrong values and types without coercion" {
    try checkField("{\"type\":\"boolean\"}", &.{
        .{ .bytes = "true" },                                  .{ .bytes = "false" },                             .{ .bytes = "1", .rejection = .type_mismatch },
        .{ .bytes = "\"true\"", .rejection = .type_mismatch }, .{ .bytes = "null", .rejection = .type_mismatch },
    });
    try checkField("{\"type\":\"null\"}", &.{
        .{ .bytes = "null" }, .{ .bytes = "false", .rejection = .type_mismatch }, .{ .bytes = "\"null\"", .rejection = .type_mismatch },
    });
    try checkField("{\"const\":\"é\"}", &.{
        .{ .bytes = "\"\\u00e9\"" }, .{ .bytes = "\"e\\u0301\"", .rejection = .constant_mismatch }, .{ .bytes = "false", .rejection = .constant_mismatch },
    });
    try checkField("{\"const\":false}", &.{
        .{ .bytes = "false" }, .{ .bytes = "true", .rejection = .constant_mismatch }, .{ .bytes = "0", .rejection = .constant_mismatch },
    });
    try checkField("{\"const\":null}", &.{ .{ .bytes = "null" }, .{ .bytes = "0", .rejection = .constant_mismatch } });
    try checkField("{\"enum\":[\"é\",\"yes\"]}", &.{
        .{ .bytes = "\"yes\"" },                                   .{ .bytes = "\"\\u00e9\"" },                       .{ .bytes = "\"YES\"", .rejection = .enum_mismatch },
        .{ .bytes = "\"e\\u0301\"", .rejection = .enum_mismatch }, .{ .bytes = "true", .rejection = .type_mismatch },
    });
    try checkField("{\"enum\":[-9223372036854775808,2,9223372036854775807]}", &.{
        .{ .bytes = "2" },                                  .{ .bytes = "2.0" },                              .{ .bytes = "2e0" },
        .{ .bytes = "-9223372036854775808" },               .{ .bytes = "9223372036854775807" },              .{ .bytes = "1", .rejection = .enum_mismatch },
        .{ .bytes = "\"2\"", .rejection = .type_mismatch }, .{ .bytes = "2.5", .rejection = .type_mismatch }, .{ .bytes = "9223372036854775808", .rejection = .integer_range },
    });
}

test "arrays validate all elements and exact item bounds including empty arrays" {
    try checkField("{\"type\":\"array\",\"minItems\":1,\"maxItems\":2,\"items\":{\"type\":\"boolean\"}}", &.{
        .{ .bytes = "[true]" },                                .{ .bytes = "[true,false]" },
        .{ .bytes = "[]", .rejection = .array_length },        .{ .bytes = "[true,false,true]", .rejection = .array_length },
        .{ .bytes = "[true,1]", .rejection = .type_mismatch }, .{ .bytes = "{}", .rejection = .type_mismatch },
    });
    try checkField("{\"type\":\"array\",\"maxItems\":0,\"items\":{\"type\":\"null\"}}", &.{
        .{ .bytes = "[]" }, .{ .bytes = "[null]", .rejection = .array_length },
    });
    try checkField("{\"type\":\"array\",\"maxItems\":2,\"items\":" ++ empty ++ "}", &.{
        .{ .bytes = "[]" }, .{ .bytes = "[{},{}]" }, .{ .bytes = "[{},{\"extra\":true}]", .rejection = .unknown_property },
    });
}

test "root and nested alternatives select only the declared discriminator and reject mixed variants" {
    const cases = [_]Case{
        .{ .bytes = "{\"kind\":\"content\",\"value\":\"accepted\"}" },
        .{ .bytes = "{\"subject\":\"beta\",\"kind\":\"question\"}" },
        .{ .bytes = "{}", .rejection = .missing_required_property },
        .{ .bytes = "{\"value\":\"candidate\"}", .rejection = .missing_required_property },
        .{ .bytes = "{\"kind\":1}", .rejection = .type_mismatch },
        .{ .bytes = "{\"kind\":\"other\"}", .rejection = .unknown_variant },
        .{ .bytes = "{\"kind\":\"content\"}", .rejection = .missing_required_property },
        .{ .bytes = "{\"kind\":\"question\",\"value\":\"candidate\"}", .rejection = .unknown_property },
        .{ .bytes = "{\"kind\":\"content\",\"value\":\"candidate\",\"subject\":\"alpha\"}", .rejection = .unknown_property },
        .{ .bytes = "{\"kind\":\"content\",\"value\":\"excessive\"}", .rejection = .string_length },
    };
    for (cases) |case| try checkDocument(variants, case);
    try checkField(variants, &cases);
    try checkField(variants, &.{.{ .bytes = "null", .rejection = .type_mismatch }});
    try checkField("{\"type\":\"array\",\"maxItems\":2,\"items\":" ++ variants ++ "}", &.{
        .{ .bytes = "[{\"kind\":\"content\",\"value\":\"ok\"},{\"kind\":\"question\",\"subject\":\"alpha\"}]" },
        .{ .bytes = "[{\"kind\":\"content\",\"value\":\"ok\"},{\"kind\":\"question\",\"subject\":\"other\"}]", .rejection = .enum_mismatch },
    });
}

test "schema-valid evidence cannot be obtained from model supplied wrappers or undeclared authority fields" {
    for ([_][]const u8{
        "{\"schemaVersion\":\"model-envelope/v1\",\"payload\":{}}",
        "{\"result\":{}}",
        "{\"requestId\":\"foreign\"}",
        "{\"status\":\"completed\"}",
    }) |bytes| try checkDocument(empty, .{ .bytes = bytes, .rejection = .unknown_property });
}

test "validation traverses the full compiled schema depth without truncating nested checks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var field: []const u8 = text;
    var accepted: []const u8 = "\"ok\"";
    var rejected: []const u8 = "0";
    // One outer object, fourteen arrays and one string reach all sixteen nodes.
    for (0..@import("domain/model_result_schema.zig").max_depth - 2) |_| {
        field = try std.mem.concat(allocator, u8, &.{ "{\"type\":\"array\",\"maxItems\":1,\"items\":", field, "}" });
        accepted = try std.mem.concat(allocator, u8, &.{ "[", accepted, "]" });
        rejected = try std.mem.concat(allocator, u8, &.{ "[", rejected, "]" });
    }
    try checkField(field, &.{ .{ .bytes = accepted }, .{ .bytes = rejected, .rejection = .type_mismatch } });
}

test "equal schema IDs do not authorize validation against another request's schema" {
    const schemas = [_][]const u8{ "{\"const\":1}", "{\"const\":2}" };
    for (schemas, 0..) |field, index| {
        try checkField(field, &.{.{ .bytes = "1", .rejection = if (index == 0) null else .constant_mismatch }});
    }
}

fn checkField(field: []const u8, cases: []const Case) !void {
    const contract = try std.fmt.allocPrint(std.testing.allocator, "{{\"type\":\"object\",\"properties\":{{\"value\":{s}}},\"required\":[\"value\"],\"additionalProperties\":false}}", .{field});
    defer std.testing.allocator.free(contract);
    for (cases) |case| {
        const bytes = try std.fmt.allocPrint(std.testing.allocator, "{{\"value\":{s}}}", .{case.bytes});
        defer std.testing.allocator.free(bytes);
        try checkDocument(contract, .{ .bytes = bytes, .rejection = case.rejection });
    }
}

pub fn checkDocument(contract: []const u8, case: Case) !void {
    var fixture: Fixture = undefined;
    try fixture.initWithSchema(contract);
    defer fixture.deinit();
    fixture.fake.invocation_plan = .{ .complete = .{ .content = case.bytes, .input_tokens = 10, .output_tokens = 2 } };
    var response = try fixture.response();
    defer response.deinit();
    var validated = try (observation.Action{}).execute(std.testing.allocator, fixture.call, &response);
    defer validated.deinit();
    var decoded = try (decoder.Action{}).execute(std.testing.allocator, validated.evidence.result().complete, null);
    defer decoded.deinit();
    const ledger = fixture.base.ledger();
    const attempts = fixture.base.attempts.current();
    const count = decoded.candidate.root().count();
    const result = (action.Action{}).execute(decoded.candidate);
    if (case.rejection) |reason| {
        try std.testing.expectEqual(reason, result.invalid.reason);
        if (case.path) |path| {
            const description = try result.invalid.describe(std.testing.allocator);
            defer std.testing.allocator.free(description.path);
            try std.testing.expectEqualStrings(path, description.path);
            var retried = try (@import("actions/model/build_model_protocol_retry.zig").Action{}).execute(std.testing.allocator, try fixture.requestSource(), fixture.prepared.request.content, validated.evidence, .{ .schema = result.invalid }, .unconfirmed, "Correct syntax only.");
            defer retried.deinit();
            const parts = retried.request.content;
            var guidance = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, parts[parts.len - 2].guidance, .{});
            defer guidance.deinit();
            const reported = guidance.value.object.get("diagnostic").?.object.get("schema").?.object;
            try std.testing.expectEqualStrings(path, reported.get("path").?.string);
            try std.testing.expectEqualStrings(@tagName(reason), reported.get("reason").?.string);
            const expected_path = if (result.invalid.expected_location == .parent) path[0..std.mem.lastIndexOfScalar(u8, path, '/').?] else path;
            const expected = guidance.value.object.get("expected").?.object;
            try std.testing.expectEqualStrings(expected_path, expected.get("path").?.string);
            try std.testing.expectEqualStrings(@tagName(result.invalid.expected_location), expected.get("scope").?.string);
            var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
            defer arena.deinit();
            const a = arena.allocator();
            try std.testing.expect(!expected.contains("schema"));
            try std.testing.expect(retried.request.response_schema == fixture.prepared.request.response_schema);
            const projection = @import("domain/model_schema_projection.zig");
            const pointer = @import("domain/json_pointer.zig");
            const complete = try std.json.parseFromSlice(std.json.Value, a, retried.request.response_schema.modelBytes(), .{});
            const located = pointer.lookup(complete.value, try pointer.parse(a, expected.get("schema_pointer").?.string)).?;
            const projected = try projection.value(a, result.invalid.expected, .complete);
            try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, projected, .{}), try std.json.Stringify.valueAlloc(a, located, .{}));
            try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, try projection.outline(a, result.invalid.expected), .{}), try std.json.Stringify.valueAlloc(a, expected.get("shape").?, .{}));
            const wire = try @import("adapters/provider/bedrock_request.zig").encode(a, retried.request, .inference);
            const request = try std.json.parseFromSlice(std.json.Value, a, wire, .{});
            var occurrences: usize = 0;
            for (request.value.object.get("messages").?.array.items[0].object.get("content").?.array.items) |part|
                occurrences += std.mem.count(u8, part.object.get("text").?.string, retried.request.response_schema.modelBytes());
            try std.testing.expectEqual(@as(usize, 1), occurrences);
            try std.testing.expectEqual(@as(usize, 3), guidance.value.object.count());
            const explanation = guidance.value.object.get("explanation").?.string;
            try std.testing.expect(std.mem.startsWith(u8, explanation, "Schema validation failed:"));
            const expected_words = switch (reason) {
                .unknown_property => "not allowed",
                .missing_required_property => "required property is missing",
                .type_mismatch => if (result.invalid.expected_location == .parent) "discriminator must be a string" else "wrong type",
                .string_length => "string length",
                .integer_range => "integer is outside",
                .array_length => "number of array items",
                .constant_mismatch => "expected constant",
                .enum_mismatch => "allowed values",
                .unknown_variant => "allowed kind",
            };
            try std.testing.expect(std.mem.indexOf(u8, explanation, expected_words) != null);
            try std.testing.expect(std.mem.indexOf(u8, wire, explanation) != null);
            if (reason == .array_length) {
                const shape = expected.get("shape").?.object;
                try std.testing.expectEqual(result.invalid.expected.array.minimum, shape.get("minItems").?.integer);
                try std.testing.expectEqual(result.invalid.expected.array.maximum, shape.get("maxItems").?.integer);
                try std.testing.expect(!shape.contains("items"));
            }
            var retained = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, parts[parts.len - 1].evidence, .{});
            defer retained.deinit();
            try std.testing.expectEqualStrings(case.bytes, retained.value.object.get("rejected_response").?.string);
        }
    } else {
        const candidate = result.valid.candidate();
        try std.testing.expect(candidate == decoded.candidate);
        try std.testing.expect(candidate.association() == validated.evidence);
        try std.testing.expect(candidate.association().request() == fixture.prepared.request);
        try std.testing.expect(candidate.association().request().response_schema == fixture.resource.content.result_schema);
        try std.testing.expect(candidate.association().operationId().eql(fixture.authorized.invoked.id));
        try std.testing.expectEqual(@as(u64, 12), candidate.association().usage().?.total_tokens);
        // The proof is an allocation-free view, not a cloned candidate or tree.
        try std.testing.expectEqual(count, candidate.root().count());
    }
    try std.testing.expectEqual(count, decoded.candidate.root().count());
    try std.testing.expectEqualDeep(result, (action.Action{}).execute(decoded.candidate));
    try std.testing.expectEqualStrings(case.bytes, response.completed.raw_result.complete.content.bytes);
    try std.testing.expect(ledger == fixture.base.ledger());
    try std.testing.expect(attempts == fixture.base.attempts.current());
    try std.testing.expectEqual(@as(usize, 1), fixture.fake.invocation_call_count);
    try std.testing.expectEqual(@as(usize, 0), fixture.fake.count_call_count);
    try std.testing.expectEqual(@as(usize, 1), fixture.base.preloader.destroyed_count);
}

test "type-disjoint nested alternatives retain bounds tags diagnostics and provider shape" {
    const selected = "{\"oneOf\":[{\"type\":\"string\",\"maxLength\":4},{\"type\":\"array\",\"items\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":9},\"maxItems\":2},{\"type\":\"object\",\"properties\":{\"kind\":{\"const\":\"reference\"},\"id\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":9}},\"required\":[\"kind\",\"id\"],\"additionalProperties\":false}]}";
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var compiler: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const contract = try std.mem.concat(a, u8, &.{ "{\"type\":\"object\",\"properties\":{\"value\":", selected, "},\"required\":[\"value\"],\"additionalProperties\":false}" });
    const compiled = try compiler.compiler().compile(a, contract);
    const projected = try @import("domain/model_schema_projection.zig").render(a, compiled, .bedrock);
    const tree = try std.json.parseFromSlice(std.json.Value, a, projected, .{});
    const choices = tree.value.object.get("properties").?.object.get("value").?.object.get("anyOf").?.array.items;
    for (choices, [_][]const u8{ "string", "array", "object" }) |choice, expected| try std.testing.expectEqualStrings(expected, choice.object.get("type").?.string);
    try checkField(selected, &.{
        .{ .bytes = "\"loan\"" },                                                                      .{ .bytes = "[1,9]" },                                       .{ .bytes = "{\"kind\":\"reference\",\"id\":3}" },
        .{ .bytes = "\"excess\"", .rejection = .string_length },                                       .{ .bytes = "[0]", .rejection = .integer_range },            .{ .bytes = "[1,2,3]", .rejection = .array_length },
        .{ .bytes = "true", .rejection = .type_mismatch },                                             .{ .bytes = "{}", .rejection = .missing_required_property }, .{ .bytes = "{\"kind\":\"foreign\",\"id\":3}", .rejection = .unknown_variant },
        .{ .bytes = "{\"kind\":\"reference\",\"id\":3,\"extra\":0}", .rejection = .unknown_property },
    });
}
