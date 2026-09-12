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

test "syntax examples expose nested array item shapes even when arrays may be empty" {
    const contract =
        \\{"type":"object","properties":{"statements":{"type":"array","maxItems":2,"items":{"type":"object","properties":{"content":{"oneOf":[{"type":"object","properties":{"kind":{"const":"model"},"text":{"type":"string","maxLength":8}},"required":["kind","text"],"additionalProperties":false},{"type":"object","properties":{"kind":{"const":"preserved_token"},"token_id":{"type":"integer","minimum":1,"maximum":9}},"required":["kind","token_id"],"additionalProperties":false}]}},"required":["content"],"additionalProperties":false}},"empty":{"type":"array","maxItems":0,"items":{"type":"boolean"}}},"required":["statements","empty"],"additionalProperties":false}
    ;
    var fixture: Fixture = undefined;
    try fixture.initWithSchema(contract);
    defer fixture.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const value = try @import("domain/model_protocol_retry.zig").example(arena.allocator(), fixture.resource.content.result_schema.root());
    const statements = value.object.get("statements").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), statements.len);
    try std.testing.expectEqual(@as(usize, 0), value.object.get("empty").?.array.items.len);
    try std.testing.expectEqualStrings("model", statements[0].object.get("content").?.object.get("kind").?.string);
    try checkDocument(contract, .{ .bytes = try std.json.Stringify.valueAlloc(arena.allocator(), value, .{}) });
}

test "protocol retry examples satisfy unrelated closed schemas without supplying semantic defaults" {
    const contracts = [_][]const u8{
        empty,                                                                                                                                                                                                                                                                                                                                                                                         variants,
        "{\"type\":\"object\",\"properties\":{\"count\":{\"type\":\"integer\",\"minimum\":3,\"maximum\":9},\"items\":{\"type\":\"array\",\"minItems\":2,\"maxItems\":3,\"items\":{\"type\":\"string\",\"minLength\":2,\"maxLength\":8}},\"enabled\":{\"type\":\"boolean\"},\"absent\":{\"type\":\"null\"}},\"required\":[\"count\",\"items\",\"enabled\",\"absent\"],\"additionalProperties\":false}",
    };
    for (contracts) |contract| {
        var fixture: Fixture = undefined;
        try fixture.initWithSchema(contract);
        defer fixture.deinit();
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const minimum = try @import("domain/model_protocol_retry.zig").example(arena.allocator(), fixture.resource.content.result_schema.root());
        const bytes = try std.json.Stringify.valueAlloc(arena.allocator(), minimum, .{});
        try checkDocument(contract, .{ .bytes = bytes });
    }
}

test "protocol retry retains exact request schema and identity and releases every failed allocation" {
    var fixture: Fixture = undefined;
    try fixture.initWithSchema(variants);
    defer fixture.deinit();
    var response = try fixture.response();
    defer response.deinit();
    var captured = try (observation.Action{}).execute(std.testing.allocator, fixture.call, &response);
    defer captured.deinit();
    const rejected = captured.evidence.result().complete;
    try std.testing.checkAllAllocationFailures(std.testing.allocator, retryAllocation, .{ &fixture, rejected });
    var source = try fixture.requestSource();
    var other: Fixture = undefined;
    try other.initWithSchema(empty);
    defer other.deinit();
    source.result_resource = &other.resource;
    try std.testing.expectError(error.ModelRequestAssociationInvalid, (@import("actions/model/build_model_protocol_retry.zig").Action{}).execute(std.testing.allocator, source, fixture.prepared.request.content, rejected, .{ .decoder = .{ .reason = .ExpectedObject } }, "Correct syntax only."));
}

fn retryAllocation(allocator: std.mem.Allocator, fixture: *Fixture, rejected: *const @import("domain/provider_invocation_validation.zig").CompleteCandidate) !void {
    const source = try fixture.requestSource();
    var retried = try (@import("actions/model/build_model_protocol_retry.zig").Action{}).execute(allocator, source, fixture.prepared.request.content, rejected, .{ .schema = .{ .reason = .missing_required_property, .expected = fixture.prepared.request.response_schema.root() } }, "Correct syntax only.");
    defer retried.deinit();
    try std.testing.expect(retried.request.model_request_id == fixture.prepared.request.model_request_id);
    try std.testing.expect(retried.request.response_schema == fixture.prepared.request.response_schema);
    try std.testing.expectEqual(fixture.prepared.request.content.len + 3, retried.request.content.len);
    for (fixture.prepared.request.content, retried.request.content[0..fixture.prepared.request.content.len]) |original, copied| try std.testing.expectEqualDeep(original, copied);
    try std.testing.expectEqual(@as(usize, 1), fixture.fake.invocation_call_count);
}

test "protocol retries expose the original parser reason and position for unrelated malformed responses" {
    const strict = @import("domain/strict_json.zig");
    for ([_][]const u8{ "```json\n{}\n```", "{\n\"answer\":}" }) |bytes| {
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
        var retried = try (@import("actions/model/build_model_protocol_retry.zig").Action{}).execute(std.testing.allocator, try fixture.requestSource(), fixture.prepared.request.content, captured.evidence.result().complete, .{ .decoder = diagnostic.? }, "Correct syntax only.");
        defer retried.deinit();
        const content = retried.request.content;
        var guidance = try strict.parse(std.testing.allocator, content[content.len - 2].guidance, .{ .maximum_depth = 64 }, true, null);
        defer guidance.deinit();
        var evidence = try strict.parse(std.testing.allocator, content[content.len - 1].evidence, .{ .maximum_depth = 64 }, true, null);
        defer evidence.deinit();
        try std.testing.expectEqualStrings(bytes, evidence.value.object.get("rejected_response").?.string);
        const supplied = guidance.value.object.get("diagnostic").?.object.get("decoder").?.object;
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
        var retried = try (@import("actions/model/build_model_protocol_retry.zig").Action{}).execute(std.testing.allocator, try fixture.requestSource(), fixture.prepared.request.content, captured.evidence.result().complete, .{ .schema = .{ .reason = .missing_required_property, .expected = fixture.prepared.request.response_schema.root() } }, "Correct syntax only.");
        defer retried.deinit();
        for ([_]*const provider.IdentifiedProviderNeutralModelRequest{ fixture.prepared.request, retried.request }) |request| {
            // Retry-owned content retains task guidance only; serialization adds framing.
            for (request.content) |part| try std.testing.expect(std.mem.indexOf(u8, part.bytes(), framing) == null);
            for ([_]provider.ProviderOperationKind{ .inference, .input_token_count }) |kind| {
                const bytes = try encoding.encode(std.testing.allocator, request, kind);
                defer std.testing.allocator.free(bytes);
                try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, bytes, framing));
                var parsed = try @import("domain/strict_json.zig").parse(std.testing.allocator, bytes, .{ .maximum_depth = 64 }, false, null);
                defer parsed.deinit();
                const root = if (kind == .inference) parsed.value else parsed.value.object.get("input").?.object.get("converse").?;
                const system = root.object.get("system").?.array.items;
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
            var retried = try (@import("actions/model/build_model_protocol_retry.zig").Action{}).execute(std.testing.allocator, try fixture.requestSource(), fixture.prepared.request.content, validated.evidence.result().complete, .{ .schema = result.invalid }, "Correct syntax only.");
            defer retried.deinit();
            const parts = retried.request.content;
            var guidance = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, parts[parts.len - 2].guidance, .{});
            defer guidance.deinit();
            const reported = guidance.value.object.get("diagnostic").?.object.get("schema").?.object;
            try std.testing.expectEqualStrings(path, reported.get("path").?.string);
            try std.testing.expectEqualStrings(@tagName(reason), reported.get("reason").?.string);
            const expected_path = if (result.invalid.expected_location == .parent) path[0..std.mem.lastIndexOfScalar(u8, path, '/').?] else path;
            try std.testing.expectEqualStrings(expected_path, guidance.value.object.get("example_path").?.string);
            const examples = guidance.value.object.get("expected_shape_examples").?.array.items;
            const node = result.invalid.expected;
            try std.testing.expectEqual(if (node.* == .one_of) node.one_of.len else @as(usize, 1), examples.len);
            if (node.* == .one_of) for (examples, node.one_of) |example, variant| {
                const expected_kind = @import("domain/model_result_schema.zig").findProperty(variant.object, "kind").?.schema.constant.string;
                try std.testing.expectEqualStrings(expected_kind, example.object.get("kind").?.string);
            };
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
