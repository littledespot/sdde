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
const Case = struct { bytes: []const u8, rejection: ?validation.Rejection = null };

test "fake provider through decode and schema validation retains only existing candidate authority" {
    try checkDocument(empty, .{ .bytes = "{}" });
    const schema =
        \\{"type":"object","properties":{"status":{"enum":["completed"]},"requestId":{"type":"string","maxLength":32},"values":{"type":"array","minItems":1,"maxItems":2,"items":{"type":"integer","minimum":1,"maximum":2}},"optional":{"type":"boolean"}},"required":["status","requestId","values"],"additionalProperties":false}
    ;
    try checkDocument(schema, .{ .bytes = "{\"status\":\"completed\",\"requestId\":\"model-only\",\"values\":[1.0,2e0]}" });
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

fn checkDocument(contract: []const u8, case: Case) !void {
    var fixture: Fixture = undefined;
    try fixture.initWithSchema(1024, contract);
    defer fixture.deinit();
    fixture.fake.invocation_plan = .{ .complete = .{ .content = case.bytes, .input_tokens = 10, .output_tokens = 2 } };
    var response = try fixture.response();
    defer response.deinit();
    var validated = try (observation.Action{}).execute(std.testing.allocator, fixture.call, &response);
    defer validated.deinit();
    var decoded = try (decoder.Action{}).execute(std.testing.allocator, validated.evidence.result().complete);
    defer decoded.deinit();
    const ledger = fixture.base.ledger();
    const attempts = fixture.base.attempts.current();
    const count = decoded.candidate.root().count();
    const result = (action.Action{}).execute(decoded.candidate);
    if (case.rejection) |reason| {
        try std.testing.expectEqual(reason, result.invalid);
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
