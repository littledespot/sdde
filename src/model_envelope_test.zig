const std = @import("std");
const action = @import("actions/model/decode_model_envelope.zig");
const validate = @import("actions/model/validate_provider_invocation_observation.zig");
const invocation = @import("domain/provider_invocation_validation.zig");
const schema = @import("domain/model_result_schema.zig");
const Fixture = @import("provider_invocation_test_fixture.zig").Fixture;

const model_text_schema =
    \\{"type":"object","properties":{"text":{"oneOf":[{"type":"string","minLength":1,"maxLength":4294967295},{"type":"object","properties":{"fragments":{"type":"array","minItems":1,"maxItems":4294967295,"items":{"oneOf":[{"type":"string","minLength":1,"maxLength":4294967295},{"type":"object","properties":{"kind":{"const":"passive"},"passive_literal_id":{"type":"integer","minimum":1,"maximum":4294967295}},"required":["kind","passive_literal_id"],"additionalProperties":false}]}}},"required":["fragments"],"additionalProperties":false}]}},"required":["text"],"additionalProperties":false}
;

const raw_prose_schema =
    \\{"type":"object","properties":{"question":{"type":"string","minLength":1,"maxLength":4294967295},"diagnostic":{"type":"string","maxLength":4294967295},"gap":{"type":"object","properties":{"question":{"type":"string","minLength":1,"maxLength":4294967295}},"required":["question"],"additionalProperties":false},"rows":{"type":"array","minItems":0,"maxItems":32,"items":{"type":"object","properties":{"question":{"type":"string","minLength":1,"maxLength":4294967295}},"required":["question"],"additionalProperties":false}}},"required":[],"additionalProperties":false}
;

test "native prose selectors reject raw question wire syntax and retain independent payload checks" {
    const wire = @import("domain/model_text_wire.zig");
    const fields = [_]wire.ProseField{
        .{ .field = .clarification_question, .path = &.{.{ .property = "question" }} },
        .{ .field = .clarification_question, .path = &.{ .{ .property = "gap" }, .{ .property = "question" } } },
        .{ .field = .clarification_question, .path = &.{ .{ .property = "rows" }, .items, .{ .property = "question" } } },
    };
    for ([_]struct { bytes: []const u8, source: ?[]const u8 = null, accepted: bool }{
        .{ .bytes = "{\"question\":\"What follows {\\\"kind\\\":\\\"exact_copy\\\"}?\"}", .accepted = false },
        .{ .bytes = "{\"gap\":{\"question\":\"Select {\\\"kind\\\":\\\"source\\\",\\\"source_id\\\":1}?\"}}", .accepted = false },
        .{ .bytes = "{\"rows\":[{\"question\":\"Choose {\\\"fragments\\\":[\\\"a\\\",{\\\"kind\\\":\\\"passive\\\",\\\"passive_literal_id\\\":2}]}?\"}]}", .accepted = false },
        .{ .bytes = "{\"question\":\"What follows {\\\"kind\\\":\\\"exact_copy\\\"}?\"}", .source = "Original source: {\"kind\":\"exact_copy\"}", .accepted = true },
        .{ .bytes = "{\"diagnostic\":\"{\\\"kind\\\":\\\"exact_copy\\\"}\"}", .accepted = true },
        .{ .bytes = "{\"question\":\"Which literal braces {} apply?\"}", .accepted = true },
        // Incorrect property shape is left for payload validation, not treated
        // as an alternate text grammar or silently accepted as prose.
        .{ .bytes = "{\"question\":{\"kind\":\"exact_copy\"}}", .accepted = true },
    }) |case| {
        var fixture: Fixture = undefined;
        const sources: []const wire.SourceText = if (case.source) |bytes| &.{.{ .source_id = .{ .ordinal = 1 }, .bytes = bytes }} else &.{};
        try fixture.initWithProseFields(raw_prose_schema, sources, &fields);
        defer fixture.deinit();
        fixture.fake.invocation_plan = .{ .complete = .{ .content = case.bytes, .input_tokens = 7, .output_tokens = 3 } };
        var response = try fixture.response();
        defer response.deinit();
        var validated = try (validate.Action{}).execute(std.testing.allocator, fixture.call, &response);
        defer validated.deinit();
        var diagnostic: ?@import("domain/model_envelope.zig").Diagnostic = null;
        defer if (diagnostic) |value| value.deinit(std.testing.allocator);
        if (case.accepted) {
            var decoded = try (action.Action{}).execute(std.testing.allocator, validated.evidence.result().complete, &diagnostic);
            defer decoded.deinit();
            try std.testing.expect(diagnostic == null);
            if (std.mem.eql(u8, case.bytes, "{\"question\":{\"kind\":\"exact_copy\"}}")) {
                const rejection = @import("domain/model_payload_schema.zig").validateValue(@import("domain/model_envelope.zig").value(decoded.candidate.json()), fixture.prepared.request.response_schema.root());
                try std.testing.expect(rejection != null);
            }
        } else {
            try std.testing.expectError(error.InvalidModelEnvelope, (action.Action{}).execute(std.testing.allocator, validated.evidence.result().complete, &diagnostic));
            try std.testing.expectEqual(.embedded_insertion_syntax, diagnostic.?.composition.fields[0].issue.reason);
            var correction = try (@import("actions/model/build_model_protocol_retry.zig").Action{}).execute(std.testing.allocator, try fixture.requestSource(), fixture.prepared.request.content, validated.evidence, .{ .composition = diagnostic.?.composition }, .unconfirmed, "Correct the rejected prose encoding.");
            defer correction.deinit();
            try std.testing.expectEqualDeep(fixture.prepared.request.prose_fields, correction.request.prose_fields);
            try std.testing.expect(correction.request.model_request_id == fixture.prepared.request.model_request_id);
        }
        try std.testing.expectEqual(@as(usize, 1), fixture.fake.invocation_call_count);
        try std.testing.expectEqual(@as(u64, 10), validated.evidence.usage().?.total_tokens);
    }
}

test "model text wire grammar rejects encoded insertions before schema admission and retains source exceptions" {
    const wire = @import("domain/model_text_wire.zig");
    for ([_]struct { prose: []const u8, source: ?[]const u8 = null, accepted: bool }{
        .{ .prose = "Display the exact_copy label, using ordinary braces {}.", .accepted = true },
        .{ .prose = "Send {\"kind\":\"exact_copy\"} to the user.", .accepted = false },
        .{ .prose = "Send {\"kind\":\"exact_copy\"} to the user.", .source = "The protocol displays `{\"kind\":\"exact_copy\"}` literally.", .accepted = true },
        .{ .prose = "Send { \"kind\":\"exact_copy\"} to the user.", .source = "The protocol displays `{\"kind\":\"exact_copy\"}` literally.", .accepted = false },
        .{ .prose = "Audit {\"fragments\":[\"retained \",{\"kind\":\"passive\",\"passive_literal_id\":1}]} now.", .accepted = false },
        .{ .prose = "A source {\"kind\":\"source\",\"source_id\":2} cannot be prose.", .accepted = false },
        .{ .prose = "Unrelated JSON {\"kind\":\"record\",\"id\":2} remains ordinary prose.", .accepted = true },
    }) |case| {
        const sources: []const wire.SourceText = if (case.source) |bytes| &.{.{ .source_id = .{ .ordinal = 1 }, .bytes = bytes }} else &.{};
        var fixture: Fixture = undefined;
        try fixture.initWithFieldPolicies(model_text_schema, sources, &.{}, &.{.{ .field = .functional_requirement, .path = &.{.{ .property = "text" }} }});
        defer fixture.deinit();
        const bytes = try std.json.Stringify.valueAlloc(std.testing.allocator, .{ .text = case.prose }, .{});
        defer std.testing.allocator.free(bytes);
        fixture.fake.invocation_plan = .{ .complete = .{ .content = bytes, .input_tokens = 7, .output_tokens = 3 } };
        var response = try fixture.response();
        defer response.deinit();
        var validated = try (validate.Action{}).execute(std.testing.allocator, fixture.call, &response);
        defer validated.deinit();
        var diagnostic: ?@import("domain/model_envelope.zig").Diagnostic = null;
        defer if (diagnostic) |value| value.deinit(std.testing.allocator);
        if (case.accepted) {
            var decoded = try (action.Action{}).execute(std.testing.allocator, validated.evidence.result().complete, &diagnostic);
            defer decoded.deinit();
            try std.testing.expect(diagnostic == null);
        } else {
            try std.testing.expectError(error.InvalidModelEnvelope, (action.Action{}).execute(std.testing.allocator, validated.evidence.result().complete, &diagnostic));
            try std.testing.expectEqual(.embedded_insertion_syntax, diagnostic.?.composition.fields[0].issue.reason);
            try std.testing.expect(diagnostic.?.composition.fields[0].issue.description().len != 0);
            var correction = try (@import("actions/model/build_model_protocol_retry.zig").Action{}).execute(std.testing.allocator, try fixture.requestSource(), fixture.prepared.request.content, validated.evidence, .{ .composition = diagnostic.?.composition }, .unconfirmed, "Correct the rejected wire text only.");
            defer correction.deinit();
            try std.testing.expect(correction.request.model_request_id == fixture.prepared.request.model_request_id);
            try std.testing.expect(correction.request.response_schema == fixture.prepared.request.response_schema);
            try std.testing.expect(std.mem.indexOf(u8, correction.request.content[correction.request.content.len - 2].bytes(), "embedded_insertion_syntax") != null);
        }
        try std.testing.expectEqual(@as(usize, 1), fixture.fake.invocation_call_count);
        try std.testing.expectEqual(@as(u64, 10), validated.evidence.usage().?.total_tokens);
        try std.testing.expectEqualStrings(bytes, validated.evidence.result().complete.content());
    }
}

test "adjacent prose fragments cannot split an encoded insertion past the protocol boundary" {
    var fixture: Fixture = undefined;
    try fixture.initWithFieldPolicies(model_text_schema, &.{}, &.{}, &.{.{ .field = .functional_requirement, .path = &.{.{ .property = "text" }} }});
    defer fixture.deinit();
    fixture.fake.invocation_plan = .{ .complete = .{ .content = "{\"text\":{\"fragments\":[\"Display {\\\"ki\",\"nd\\\":\\\"exact_copy\\\"}\"]}}", .input_tokens = 1, .output_tokens = 1 } };
    var response = try fixture.response();
    defer response.deinit();
    var validated = try (validate.Action{}).execute(std.testing.allocator, fixture.call, &response);
    defer validated.deinit();
    try std.testing.expectError(error.InvalidModelEnvelope, (action.Action{}).execute(std.testing.allocator, validated.evidence.result().complete, null));
}

test "source-aware wire scanner preserves ordinary prose and frees every failed allocation" {
    const wire = @import("domain/model_text_wire.zig");
    try std.testing.expect((try wire.checkProse(std.testing.allocator, "Use {broken JSON or the fragments label.", &.{})) == null);
    try std.testing.expectEqual(wire.Issue.embedded_insertion_syntax, (try wire.checkProse(std.testing.allocator, "{\"fragments\":[\"text\"]}", &.{})).?);
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(wireAllocation, .{});
}
fn wireAllocation(a: std.mem.Allocator) !void {
    const issue = try @import("domain/model_text_wire.zig").checkProse(a, "Before {\"fragments\":[\"text \",{\"kind\":\"exact_copy\",\"claim_id\":1}]} after", &.{});
    try std.testing.expectEqual(.embedded_insertion_syntax, issue.?);
}

test "fake response decodes one compact object and preserves exact trusted association" {
    for ([_][]const u8{
        "{}",
        " \t\r\n{\"replacement\":\"candidate\"}\n ",
        "{\"kind\":\"clarification\",\"question\":\"Which option?\"}",
        "{\"replacementsByTargetId\":{\"a\":\"first\",\"b\":\"second\"}}",
    }) |bytes| {
        var fixture: Fixture = undefined;
        try fixture.init();
        defer fixture.deinit();
        fixture.fake.invocation_plan = .{ .complete = .{ .content = bytes, .input_tokens = 10, .output_tokens = 2 } };
        var response = try fixture.response();
        defer response.deinit();
        var validated = try (validate.Action{}).execute(std.testing.allocator, fixture.call, &response);
        defer validated.deinit();
        const ledger = fixture.base.ledger();
        const attempts = fixture.base.attempts.current();
        {
            var decoded = try (action.Action{}).execute(std.testing.allocator, validated.evidence.result().complete, null);
            defer decoded.deinit();
            const association = decoded.candidate.association();
            try std.testing.expect(association == validated.evidence);
            try std.testing.expect(association.request() == fixture.prepared.request);
            try std.testing.expect(association.request().response_schema == fixture.resource.content.result_schema);
            try std.testing.expect(association.operationId().eql(fixture.call.operation_id));
            try std.testing.expect(association.request().model_visible_input_id.eql(fixture.prepared.request.model_visible_input_id));
            try std.testing.expectEqual(@as(u64, 12), association.usage().?.total_tokens);
        }
        try std.testing.expectEqualStrings(bytes, validated.evidence.result().complete.content());
        try std.testing.expect(ledger == fixture.base.ledger());
        try std.testing.expect(attempts == fixture.base.attempts.current());
        try std.testing.expectEqual(@as(usize, 1), fixture.fake.invocation_call_count);
        try std.testing.expectEqual(@as(usize, 1), fixture.base.preloader.destroyed_count);
    }
}

test "read-only views retain decoded keys Unicode scalars arrays and objects" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const bytes = "{\"a\\u0062\":[null,true,false,\"\\uD83D\\uDE00\",{\"text\":\"\\n[]{}\\\"\"}],\"empty\":[],\"object\":{}}";
    fixture.fake.invocation_plan = .{ .complete = .{ .content = bytes, .input_tokens = 1, .output_tokens = 1 } };
    var response = try fixture.response();
    defer response.deinit();
    var validated = try (validate.Action{}).execute(std.testing.allocator, fixture.call, &response);
    defer validated.deinit();
    var decoded = try (action.Action{}).execute(std.testing.allocator, validated.evidence.result().complete, null);
    defer decoded.deinit();
    const root = decoded.candidate.root();
    try std.testing.expectEqual(@as(usize, 3), root.count());
    try std.testing.expectEqualStrings("ab", root.at(0).?.name);
    const items = root.get("ab").?.array;
    try std.testing.expectEqual(@as(usize, 5), items.count());
    try std.testing.expect(items.at(0).? == .null_value);
    try std.testing.expect(items.at(1).?.boolean);
    try std.testing.expect(!items.at(2).?.boolean);
    try std.testing.expectEqualStrings("😀", items.at(3).?.string);
    try std.testing.expectEqualStrings("\n[]{}\"", items.at(4).?.object.get("text").?.string);
    try std.testing.expect(items.at(5) == null);
    try std.testing.expect(items.at(std.math.maxInt(usize)) == null);
    try std.testing.expect(root.get("empty").?.array.at(0) == null);
    try std.testing.expectEqual(@as(usize, 0), root.get("object").?.object.count());
    try std.testing.expect(root.get("missing") == null);
    try std.testing.expect(root.at(3) == null);
    try std.testing.expect(root.at(std.math.maxInt(usize)) == null);
}

test "decoding preserves exact numeric lexemes without rounding coercion or range validation" {
    for ([_][]const u8{ "0", "-0", "9223372036854775808", "-9223372036854775809", "9007199254740993.0", "1e9999", "-1.234567890123456789E-9999" }) |number| {
        const bytes = try std.fmt.allocPrint(std.testing.allocator, "{{\"n\":{s}}}", .{number});
        defer std.testing.allocator.free(bytes);
        var fixture: Fixture = undefined;
        try fixture.init();
        defer fixture.deinit();
        fixture.fake.invocation_plan = .{ .complete = .{ .content = bytes, .input_tokens = 1, .output_tokens = 1 } };
        var response = try fixture.response();
        defer response.deinit();
        var validated = try (validate.Action{}).execute(std.testing.allocator, fixture.call, &response);
        defer validated.deinit();
        var decoded = try (action.Action{}).execute(std.testing.allocator, validated.evidence.result().complete, null);
        defer decoded.deinit();
        try std.testing.expectEqualStrings(number, decoded.candidate.root().get("n").?.number);
    }
}

test "malformed non-object fenced prefixed and trailing model output rejects without extraction" {
    for ([_][]const u8{
        "",               " ",                   "{",                   "[]",                         "[{}]",                        "null",                   "true",             "false",      "1",          "\"{}\"",
        "\xef\xbb\xbf{}", "\x0b{}",              "{}\x0c",              "{}\x00",                     "```json\n{}\n```",            "Here is the result: {}", "{} done",          "{} {}",      "{}[]",       "{}null",
        "{\"x\":}",       "{\"x\":true,}",       "{\"x\":[1,]}",        "{/*comment*/}",              "{x:1}",                       "{\"x\":NaN}",            "{\"x\":Infinity}", "{\"x\":01}", "{\"x\":+1}", "{\"x\":1.}",
        "{\"x\":1e}",     "{\"x\":\"\\uD800\"}", "{\"x\":\"\\uDC00\"}", "{\"x\":\"\\uD800\\u0041\"}", "{\"x\":\"unescaped\nline\"}",
    }) |bytes| try checkDocument(bytes, false);
}

test "approved prefix normalization preserves content evidence and accounting" {
    const envelope = @import("domain/model_envelope.zig");
    const Case = struct { prefix: []const u8, object: []const u8, normalization: envelope.Normalization };
    for ([_]Case{
        .{ .prefix = "{\"", .object = "{ \"kind\":\"claims\",\"items\":[1,2],\"sibling\":{\"kept\":true}}", .normalization = .removed_leading_brace_quote },
        .{ .prefix = "{\"", .object = "{\"value\":\"orchard\"}", .normalization = .removed_leading_brace_quote },
        .{ .prefix = "{\"", .object = "{\"loan\":{\"days\":1e3},\"note\":\"é😀\"}", .normalization = .removed_leading_brace_quote },
        .{ .prefix = "{\"kind", .object = "{\"kind\":\"claims\",\"items\":[1,2],\"sibling\":{\"kept\":true}}", .normalization = .removed_repeated_field_prefix },
        .{ .prefix = "{\"replacement", .object = "{ \"replacement\":\"candidate\",\"sibling\":{\"kept\":true}}", .normalization = .removed_repeated_field_prefix },
        .{ .prefix = "{\"loan", .object = "{\"loan\":{\"days\":1e3},\"note\":\"é😀\"}", .normalization = .removed_repeated_field_prefix },
        .{ .prefix = "{\"request-id", .object = "{\n\t\"request-id\" \r\n:9}", .normalization = .removed_repeated_field_prefix },
        .{ .prefix = "{\"état", .object = "{\"état\":\"active\"}", .normalization = .removed_repeated_field_prefix },
        .{ .prefix = "{\"decision\":\"", .object = "{  \"decision\":\"compatible\",\"citations\":[1],\"detail\":\"MOCK evidence\"}", .normalization = .removed_repeated_field_prefix },
        .{ .prefix = "{\"kind\":\"", .object = "{\"kind\":\"claims\",\"items\":[1,2],\"sibling\":{\"kept\":true}}", .normalization = .removed_repeated_field_prefix },
        .{ .prefix = "{\"replacement\":\"", .object = "{ \"replacement\":\"candidate\",\"sibling\":{\"kept\":true}}", .normalization = .removed_repeated_field_prefix },
        .{ .prefix = "{\"request-id\":\"", .object = "{\n\t\"request-id\" \r\n:9}", .normalization = .removed_repeated_field_prefix },
        .{ .prefix = "{\"état\":\"", .object = "{\"état\":\"active\"}", .normalization = .removed_repeated_field_prefix },
        // The observed Bedrock GPT-OSS truncation repeats only a start of the first key.
        .{ .prefix = "{\"find", .object = "{\"findings\":[{\"requirement_ordinal\":1,\"value\":{\"kind\":\"supported\"}}]}", .normalization = .removed_partial_field_prefix },
        .{ .prefix = "{\"token", .object = "{\"token_classifications\":[]}", .normalization = .removed_partial_field_prefix },
        .{ .prefix = "{\"kind", .object = "{\"kind_extra\":1}", .normalization = .removed_partial_field_prefix },
        .{ .prefix = "{\"f", .object = "{\n\t\"findings\" \r\n:[]}", .normalization = .removed_partial_field_prefix },
        .{ .prefix = "{\"é", .object = "{\"état\":\"active\"}", .normalization = .removed_partial_field_prefix },
    }) |case| {
        const bytes = try std.mem.concat(std.testing.allocator, u8, &.{ case.prefix, case.object });
        defer std.testing.allocator.free(bytes);
        var fixture: Fixture = undefined;
        try fixture.init();
        defer fixture.deinit();
        fixture.fake.invocation_plan = .{ .complete = .{ .content = bytes, .input_tokens = 10, .output_tokens = 2 } };
        var response = try fixture.response();
        defer response.deinit();
        var validated = try (validate.Action{}).execute(std.testing.allocator, fixture.call, &response);
        defer validated.deinit();
        const ledger = fixture.base.ledger();
        const attempts = fixture.base.attempts.current();
        var decoded = try (action.Action{}).execute(std.testing.allocator, validated.evidence.result().complete, null);
        defer decoded.deinit();
        try std.testing.expectEqual(case.normalization, decoded.candidate.normalization());
        try std.testing.expectEqualStrings(case.object, decoded.candidate.content());
        var expected = try envelope.parseContent(std.testing.allocator, case.object, null);
        defer expected.deinit();
        const actual_bytes = try std.json.Stringify.valueAlloc(std.testing.allocator, decoded.candidate.json().*, .{});
        defer std.testing.allocator.free(actual_bytes);
        const expected_bytes = try std.json.Stringify.valueAlloc(std.testing.allocator, expected.parsed.value, .{});
        defer std.testing.allocator.free(expected_bytes);
        try std.testing.expectEqualStrings(expected_bytes, actual_bytes);
        try std.testing.expect(decoded.candidate.association() == validated.evidence);
        try std.testing.expectEqualStrings(bytes, validated.evidence.result().complete.content());
        try std.testing.expectEqual(@as(u64, 12), validated.evidence.usage().?.total_tokens);
        try std.testing.expect(ledger == fixture.base.ledger());
        try std.testing.expect(attempts == fixture.base.attempts.current());
        try std.testing.expectEqual(@as(usize, 1), fixture.fake.invocation_call_count);
        // Configuration, persistence and provider wire parsing remain strict.
        try std.testing.expectError(error.InvalidJsonDocument, @import("domain/strict_json.zig").parse(std.testing.allocator, bytes, .{ .maximum_depth = schema.max_json_depth }, false, null));
    }
}

test "prefix normalization preserves valid keys and rejects every other malformed form" {
    const envelope = @import("domain/model_envelope.zig");
    for ([_][]const u8{
        "{\"{\":1}",
        "{\"{name\":\"value\"}",
        "{\"x\":\"{\\\"{\"}",
        "{\"kind\":{\"kind\":\"claims\"}}",
        "{\"kind{\":\"value\"}",
        "{\"decision\":\"{\\\"decision\\\":\\\"compatible\\\"}\"}",
        "{\"decision\":{\"decision\":\"compatible\"}}",
    }) |bytes| {
        var document = try envelope.parseContent(std.testing.allocator, bytes, null);
        defer document.deinit();
        try std.testing.expectEqual(.none, document.normalization);
        try std.testing.expectEqualStrings(bytes, document.content);
    }
    for ([_][]const u8{
        "{\"{\"{\"value\":1}", // Never strip recursively.
        " {\"{\"value\":1}", // No fuzzy prefix matching.
        "{\"{\"value\":1,}",
        "{\"{\"value\":1,\"value\":2}",
        "{\"{\"value\":1} trailing",
        "{\"{\"value\":1}{}",
        "{\"{\"value\":\"\xff\"}",
        "{\"{\"value\":",
        "{\"[1,2]",
        "```json\n{\"{\"value\":1}\n```",
        "{\"kind{\"other\":\"claims\"}", // The discarded name must repeat the first key or its start.
        "{\"fond{\"findings\":1}",
        "{\"findingsX{\"findings\":1}",
        "{\"find{\"findings\" 1}",
        "{\"find{\"findings\":1} trailing",
        "{\"find{\"findings\":1,}",
        "{\"find{\"findings\":",
        "{\"find{\"findings",
        "{\"find{\"find\\u0069ngs\":1}", // Escaped member names are never inferred.
        "{\"fin{\"find{\"findings\":1}", // Never strip recursively.
        "{\"find{\"findings\":1,\"findings\":2}",
        "{\"find{\"find\x01ings\":1}",
        "{\"find{\"find\xffings\":1}",
        "{\"\xc3{\"état\":1}", // A partial name cannot split a character.
        "{\"decisio\":\"{\"decision\":1}", // The string-value opener stays exact.
        "{\"kind{\"kind\" 1}",
        "{\"kind{\"kind{\"kind\":\"claims\"}",
        " {\"kind{\"kind\":\"claims\"}",
        "{\"kind\"{\"kind\":\"claims\"}",
        "{\"ki\\nd{\"ki\\nd\":1}", // Do not infer escaped member names.
        "{\"kind{\"kind\":\"claims\",}",
        "{\"kind{\"kind\":1,\"kind\":2}",
        "{\"kind{\"kind\":1} trailing",
        "{\"kind{\"kind\":1}{}",
        "{\"kind{\"kind\":",
        "{\"kind{\"kind\":\"\xff\"}",
        "{\"kind\n{\"kind\":1}",
        "{\"kind{}",
        "{\"kind",
        "{\"decision\":\"{\"other\":1}",
        "{\"decision\":\"{\"decision_extra\":1}",
        "{\"decision\":\"{\"decisio\":1}",
        "{\"decision\":\"{\"\\u0064ecision\":1}",
        "{\"\":\"{\"\":1}", // The named prefix must be nonempty.
        "{\"decision\"\"{\"decision\":1}",
        "{\"decision\":{\"decision\":1}",
        "{\"decision\":\"\"{\"decision\":1}",
        "{\"decision\":\"text{\"decision\":1}", // Never discard string content.
        "{\"decision\" :\"{\"decision\":1}",
        "{\"decision\": \"{\"decision\":1}",
        "{\"decision\":\" {\"decision\":1}",
        " {\"decision\":\"{\"decision\":1}",
        "{\"decision\":\"{\"decision\":\"{\"decision\":1}",
        "{\"decision\":\"{\"decision\":1,}",
        "{\"decision\":\"{\"decision\":1,\"decision\":2}",
        "{\"decision\":\"{\"decision\":1,\"\\u0064ecision\":2}",
        "{\"decision\":\"{\"decision\":1} trailing",
        "{\"decision\":\"{\"decision\":1}{}",
        "{\"decision\":\"{\"decision\":\"\xff\"}",
        "{\"deci\\sion\":\"{\"decision\":1}",
        "{\"deci\nsion\":\"{\"decision\":1}",
        "{\"\xff\":\"{\"\xff\":1}",
        "{\"decision\":\"{}",
        "{\"decision\":\"{\"decision\" 1}",
        "{\"decision\":\"{\"decision\":",
        "{\"decision\":\"",
        "{\"decision\":",
        "{\"decision\"",
    }) |bytes| {
        var syntax_diagnostic: ?envelope.SyntaxDiagnostic = null;
        defer if (syntax_diagnostic) |failure| failure.deinit(std.testing.allocator);
        try std.testing.expectError(error.InvalidModelEnvelope, envelope.parseContent(std.testing.allocator, bytes, &syntax_diagnostic));
        var original: ?envelope.SyntaxDiagnostic = null;
        defer if (original) |failure| failure.deinit(std.testing.allocator);
        try std.testing.expectError(error.InvalidJsonDocument, @import("domain/strict_json.zig").parse(std.testing.allocator, bytes, .{ .maximum_depth = schema.max_json_depth }, false, &original));
        try std.testing.expect(syntax_diagnostic.?.eql(original.?));
    }
}

test "R36 stray quote then unchanged missing signal brace never becomes an admitted candidate" {
    const initial =
        \\{"claim_dispositions":[{"claim_id":{"ordinal":1},"disposition":{"kind":"retained"}},"{"claim_id":{"ordinal":2},"disposition":{"kind":"retained"}}],"signals":[{"claim_ids":[{"ordinal":1}],"content":{"kind":"model","model":{"kind":"business","segments":[{"kind":"literal","value":"The application must start successfully.When started, the application must display `Hello, World!`.Should also output date and time in UTC"}]}}],"conflicts":[]}
    ;
    const correction =
        \\{"claim_dispositions":[{"claim_id":{"ordinal":1},"disposition":{"kind":"retained"}} ,{"claim_id":{"ordinal":2},"disposition":{"kind":"retained"}}],"signals":[{"claim_ids":[{"ordinal":1},{"ordinal":2}],"content":{"kind":"model","model":{"kind":"business","segments":[{"kind":"literal","value":"The application must start successfully.When started, the application must display `Hello, World!`.Should also output date and time in UTC"}]}}],"conflicts":[]}
    ;
    for ([_][]const u8{ initial, correction, correction }) |body| try checkDocument(body, false);
    const fixed = try std.mem.replaceOwned(u8, std.testing.allocator, correction, "}}],\"conflicts\"", "}}}],\"conflicts\"");
    defer std.testing.allocator.free(fixed);
    try checkDocument(fixed, true);
    // Syntax acceptance grants no meaning/coverage authority: the production
    // R36 sequence separately rejects and repairs this mixed-kind selection.
    for ([_][]const u8{
        "{\"rows\":[{\"content\":{\"value\":\"Loan renewed!\"}}]}",
        "{\"rows\":[{\"content\":{\"value\":\"Inventory received\"}}]}",
    }) |body| {
        const missing = try std.mem.replaceOwned(u8, std.testing.allocator, body, "}}]", "}]");
        defer std.testing.allocator.free(missing);
        try checkDocument(missing, false);
        try checkDocument(body, true);
    }
}

test "duplicate decoded keys reject at every depth including escaped equivalents" {
    for ([_][]const u8{
        "{\"x\":1,\"x\":2}",
        "{\"x\":1,\"\\u0078\":2}",
        "{\"outer\":{\"x\":true,\"x\":false}}",
        "{\"outer\":[{\"x\":null,\"\\u0078\":[]}]}",
        "{\"é\":1,\"\\u00e9\":2}",
        "{\"😀\":1,\"\\ud83d\\ude00\":2}",
    }) |bytes| try checkDocument(bytes, false);
    // Keys in different objects are unrelated; Unicode is not normalized.
    try checkDocument("{\"a\":{\"x\":1},\"b\":{\"x\":2},\"é\":0,\"e\\u0301\":1}", true);
    // Repeated identifier values are a domain concern, not duplicate members.
    try checkDocument("{\"statements\":[{\"local_key\":1},{\"local_key\":1}]}", true);
}

test "decoding never interprets model metadata or validates the bound payload schema" {
    // The fixture schema is an empty closed object. These parse, but none is
    // schema-valid. No wrapper is extracted and no model claim gains authority.
    for ([_][]const u8{
        "{\"requestId\":\"foreign\",\"status\":\"completed\"}",
        "{\"schemaVersion\":\"model-envelope/v1\",\"payload\":{}}",
        "{\"kind\":\"unknown\",\"extra\":true}",
    }) |bytes| try checkDocument(bytes, true);
}

test "JSON container guard accepts its exact boundary and ignores brackets in strings" {
    for ([_]bool{ false, true }) |objects| {
        for ([_]usize{ schema.max_json_depth, schema.max_json_depth + 1 }) |depth| {
            var bytes: std.array_list.Managed(u8) = .init(std.testing.allocator);
            defer bytes.deinit();
            try bytes.appendSlice("{\"nested\":");
            for (1..depth) |_| try bytes.appendSlice(if (objects) "{\"child\":" else "[");
            try bytes.appendSlice("null");
            try bytes.appendNTimes(if (objects) '}' else ']', depth - 1);
            try bytes.append('}');
            try checkDocument(bytes.items, depth == schema.max_json_depth);
            const prefixed = try std.fmt.allocPrint(std.testing.allocator, "{{\"{s}", .{bytes.items});
            defer std.testing.allocator.free(prefixed);
            try checkDocument(prefixed, depth == schema.max_json_depth);
            const repeated = try std.fmt.allocPrint(std.testing.allocator, "{{\"nested{s}", .{bytes.items});
            defer std.testing.allocator.free(repeated);
            try checkDocument(repeated, depth == schema.max_json_depth);
            const string_value = try std.fmt.allocPrint(std.testing.allocator, "{{\"nested\":\"{s}", .{bytes.items});
            defer std.testing.allocator.free(string_value);
            try checkDocument(string_value, depth == schema.max_json_depth);
        }
    }
    try checkDocument("{\"brackets\":\"" ++ "[]{}" ** 100 ++ "\"}", true);
    // Surrounding JSON whitespace is accepted; there is no output-byte guard.
    try checkDocument("{}" ++ " " ** 1022, true);
}

test "separate decoded candidates own their trees and retain their own associations" {
    var first: Fixture = undefined;
    try first.init();
    defer first.deinit();
    var second: Fixture = undefined;
    try second.init();
    defer second.deinit();
    const bytes = "{\"requestId\":\"not-authority\"}";
    first.fake.invocation_plan = .{ .complete = .{ .content = bytes, .input_tokens = 1, .output_tokens = 1 } };
    second.fake.invocation_plan = first.fake.invocation_plan;
    var first_response = try first.response();
    defer first_response.deinit();
    var second_response = try second.response();
    defer second_response.deinit();
    var first_validation = try (validate.Action{}).execute(std.testing.allocator, first.call, &first_response);
    defer first_validation.deinit();
    var second_validation = try (validate.Action{}).execute(std.testing.allocator, second.call, &second_response);
    defer second_validation.deinit();
    var one = try (action.Action{}).execute(std.testing.allocator, first_validation.evidence.result().complete, null);
    defer one.deinit();
    var two = try (action.Action{}).execute(std.testing.allocator, second_validation.evidence.result().complete, null);
    defer two.deinit();
    try std.testing.expect(one.candidate.association() == first_validation.evidence);
    try std.testing.expect(two.candidate.association() == second_validation.evidence);
    try std.testing.expect(one.candidate.association().request() != two.candidate.association().request());
    try std.testing.expect(one.candidate.root() != two.candidate.root());
    try std.testing.expect(one.candidate.root().get("requestId").?.string.ptr != two.candidate.root().get("requestId").?.string.ptr);
    const original = first_response.completed.raw_result.complete.content.bytes;
    const original_value = original[std.mem.indexOf(u8, original, "not-authority").?..][0.."not-authority".len];
    try std.testing.expect(one.candidate.root().get("requestId").?.string.ptr != original_value.ptr);
    try std.testing.expectEqualStrings(bytes, original);
}

test "every decoding allocation failure and syntax rejection frees partial trees without consuming evidence" {
    const Case = struct { body: []const u8, accepted: bool = false };
    for ([_]Case{
        .{ .body = "{\"a\":[true,null,{\"text\":\"\\u00e9\",\"number\":1e9999}],\"b\":{}}", .accepted = true },
        .{ .body = "{\"{\"a\":[true,null,{\"text\":\"\\u00e9\",\"number\":1e9999}],\"b\":{}}", .accepted = true },
        .{ .body = "{\"a{\"a\":[true,null,{\"text\":\"\\u00e9\",\"number\":1e9999}],\"b\":{}}", .accepted = true },
        .{ .body = "{\"a\":\"{\"a\":[true,null,{\"text\":\"\\u00e9\",\"number\":1e9999}],\"b\":{}}", .accepted = true },
        .{ .body = "{\"{\"a\":1,\"a\":2}" },
        .{ .body = "{\"a{\"a\":1,\"a\":2}" },
        .{ .body = "{\"a\":\"{\"a\":1,\"a\":2}" },
        .{ .body = "{\"a\":[{\"key\":\"one\",\"key\":\"two\"}]}" },
        .{ .body = "{\"a\":[1,2,3]} {}" },
        .{ .body = "[1,2,3]" },
    }) |case| {
        const bytes = case.body;
        var fixture: Fixture = undefined;
        try fixture.init();
        defer fixture.deinit();
        fixture.fake.invocation_plan = .{ .complete = .{ .content = bytes, .input_tokens = 1, .output_tokens = 1 } };
        var response = try fixture.response();
        defer response.deinit();
        var validated = try (validate.Action{}).execute(std.testing.allocator, fixture.call, &response);
        defer validated.deinit();
        try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(allocationCase, .{ validated.evidence.result().complete, case.accepted });
        try std.testing.expectEqualStrings(bytes, validated.evidence.result().complete.content());
    }
}

fn allocationCase(allocator: std.mem.Allocator, complete: *const invocation.CompleteCandidate, accepted: bool) !void {
    var diagnostic: ?@import("domain/model_envelope.zig").Diagnostic = null;
    defer if (diagnostic) |value| value.deinit(allocator);
    var decoded = (action.Action{}).execute(allocator, complete, &diagnostic) catch |err| switch (err) {
        error.OutOfMemory => {
            try std.testing.expect(diagnostic == null);
            return error.OutOfMemory;
        },
        error.InvalidModelEnvelope => {
            try std.testing.expect(diagnostic != null);
            return std.testing.expect(!accepted);
        },
    };
    defer decoded.deinit();
    try std.testing.expect(accepted);
    try std.testing.expect(diagnostic == null);
    try std.testing.expect(decoded.candidate.association() == complete.association());
}

fn checkDocument(bytes: []const u8, accepted: bool) !void {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    fixture.fake.invocation_plan = .{ .complete = .{ .content = bytes, .input_tokens = 1, .output_tokens = 1 } };
    var response = try fixture.response();
    defer response.deinit();
    var validated = try (validate.Action{}).execute(std.testing.allocator, fixture.call, &response);
    defer validated.deinit();
    try allocationCase(std.testing.allocator, validated.evidence.result().complete, accepted);
    try std.testing.expectEqualStrings(bytes, response.completed.raw_result.complete.content.bytes);
    try std.testing.expectEqual(@as(usize, 1), fixture.fake.invocation_call_count);
}

const aggregate_bindings: []const @import("domain/model_text_field.zig").Binding = &.{
    .{ .field = .ac_given, .path = &.{ .{ .property = "records" }, .items, .{ .variant = "acceptance_criterion" }, .{ .property = "given" } } },
    .{ .field = .ac_when, .path = &.{ .{ .property = "records" }, .items, .{ .variant = "acceptance_criterion" }, .{ .property = "when" } } },
    .{ .field = .extraction_business, .path = &.{.{ .property = "business" }} },
    .{ .field = .reconciliation_technical, .path = &.{.{ .property = "technical" }} },
    .{ .field = .entity_name, .path = &.{.{ .property = "identity" }} },
    .{ .field = .spec_title, .path = &.{.{ .property = "a/b~c" }} },
    // An absent selected union branch is not a returned leaf.
    .{ .field = .entity_meaning, .path = &.{ .{ .property = "records" }, .items, .{ .variant = "entity" }, .{ .property = "meaning" } } },
};
const aggregate_questions: []const @import("domain/model_text_wire.zig").ProseField = &.{
    .{ .field = .clarification_question, .path = &.{ .{ .property = "questions" }, .items } },
};
const aggregate_body =
    \\{"records":[{"kind":"acceptance_criterion","given":{"fragments":[{"kind":"exact_copy"}]},"when":{"fragments":[{"kind":"passive","passive_literal_id":3}]}},{"kind":"acceptance_criterion","given":{"fragments":[{"kind":"exact_copy","claim_id":7}]},"when":"A valid condition."}],"business":{"fragments":["Describe ",{"kind":"source","source_id":1}]},"technical":{"fragments":[{"kind":"source","source_id":1}]},"identity":{"fragments":[{"kind":"exact_copy"},{"kind":"exact_copy","claim_id":7}]},"a/b~c":{"fragments":["Label ",{"kind":"exact_copy"}]},"questions":["Which {\"kind\":\"exact_copy\"} applies?","Which channel?"]}
;

test "response composition aggregates concrete sibling fields typed reasons and escaped pointers" {
    const composition = @import("domain/model_text_composition.zig");
    var document = try @import("domain/strict_json.zig").parse(std.testing.allocator, aggregate_body, .{ .maximum_depth = schema.max_json_depth }, false, null);
    defer document.deinit();
    const diagnostic = (try composition.check(std.testing.allocator, document.value, aggregate_bindings, aggregate_questions, &.{}, .{ .exact_scope = null })).?;
    defer diagnostic.deinit(std.testing.allocator);
    const expected = [_]struct { path: []const u8, field: @import("domain/text_field_policy.zig").Field, reason: @FieldType(@import("domain/typed_text.zig").Issue, "reason") }{
        .{ .path = "/records/0/given", .field = .ac_given, .reason = .reference_only },
        .{ .path = "/records/1/given", .field = .ac_given, .reason = .reference_only },
        .{ .path = "/records/0/when", .field = .ac_when, .reason = .reference_only },
        .{ .path = "/business", .field = .extraction_business, .reason = .prohibited_source },
        .{ .path = "/technical", .field = .reconciliation_technical, .reason = .reference_only },
        .{ .path = "/a~1b~0c", .field = .spec_title, .reason = .prohibited_exact },
        .{ .path = "/questions/0", .field = .clarification_question, .reason = .embedded_insertion_syntax },
    };
    try std.testing.expectEqual(expected.len, diagnostic.fields.len);
    for (expected, diagnostic.fields) |want, actual| {
        try std.testing.expectEqualStrings(want.path, actual.path);
        try std.testing.expectEqual(want.field, actual.field);
        try std.testing.expectEqual(want.reason, actual.issue.reason);
    }
    const copied = try diagnostic.copy(std.testing.allocator);
    defer copied.deinit(std.testing.allocator);
    try std.testing.expect(diagnostic.eql(copied));
    try std.testing.expect(diagnostic.fields.ptr != copied.fields.ptr);
    try std.testing.expect(diagnostic.fields[0].path.ptr != copied.fields[0].path.ptr);
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(aggregateAllocation, .{document.value});
}
fn aggregateAllocation(a: std.mem.Allocator, value: std.json.Value) !void {
    const diagnostic = (try @import("domain/model_text_composition.zig").check(a, value, aggregate_bindings, aggregate_questions, &.{}, .{ .exact_scope = null })).?;
    defer diagnostic.deinit(a);
    const copied = try diagnostic.copy(a);
    defer copied.deinit(a);
    try std.testing.expect(diagnostic.eql(copied));
}

test "selected root leaves source witnesses malformed shapes and unrelated prose preserve their contracts" {
    const composition = @import("domain/model_text_composition.zig");
    const bindings: []const @import("domain/model_text_field.zig").Binding = &.{.{ .field = .spec_story, .path = &.{} }};
    for ([_]struct { body: []const u8, source: ?[]const u8 = null, reason: ?@FieldType(@import("domain/typed_text.zig").Issue, "reason") = null }{
        .{ .body = "{\"fragments\":[{\"kind\":\"exact_copy\"}]}", .reason = .reference_only },
        .{ .body = "{\"fragments\":[\"Display \",{\"kind\":\"exact_copy\"},\" now.\"]}" },
        .{ .body = "\" \\t\\n\"", .reason = .blank },
        .{ .body = "\"Use {\\\"kind\\\":\\\"exact_copy\\\"}.\"", .reason = .embedded_insertion_syntax },
        .{ .body = "\"Use {\\\"kind\\\":\\\"exact_copy\\\"}.\"", .source = "Original {\"kind\":\"exact_copy\"}." },
        .{ .body = "\"Use { \\\"kind\\\":\\\"exact_copy\\\"}.\"", .source = "Original {\"kind\":\"exact_copy\"}.", .reason = .embedded_insertion_syntax },
        .{ .body = "{\"fragments\":[{\"kind\":\"invented\"}]}" },
        .{ .body = "{\"kind\":\"exact_copy\"}" },
        .{ .body = "{\"fragments\":17}" },
        // Scalar validity and malformed empty wire contracts retain their
        // ordinary schema/native handling; no composition repair is added.
        .{ .body = "\"Invalid scalar\\u0001\"" },
        .{ .body = "{\"fragments\":[]}" },
    }) |case| {
        var parsed = try @import("domain/strict_json.zig").parse(std.testing.allocator, case.body, .{ .maximum_depth = schema.max_json_depth }, false, null);
        defer parsed.deinit();
        const sources: []const @import("domain/model_text_wire.zig").SourceText = if (case.source) |bytes| &.{.{ .source_id = .{ .ordinal = 1 }, .bytes = bytes }} else &.{};
        const diagnostic = try composition.check(std.testing.allocator, parsed.value, bindings, &.{}, sources, .{ .exact_scope = null });
        defer if (diagnostic) |failure| failure.deinit(std.testing.allocator);
        if (case.reason) |reason| {
            try std.testing.expectEqual(@as(usize, 1), diagnostic.?.fields.len);
            try std.testing.expectEqual(reason, diagnostic.?.fields[0].issue.reason);
            try std.testing.expectEqualStrings("", diagnostic.?.fields[0].path);
        } else try std.testing.expect(diagnostic == null);
        // The same bytes in a schema's unrelated string have no field policy.
        const unrelated = try composition.check(std.testing.allocator, parsed.value, &.{}, &.{}, sources, .{ .exact_scope = null });
        try std.testing.expect(unrelated == null);
    }
}

test "aggregate admission and protocol diagnostic copying clean every failed allocation" {
    var fixture: Fixture = undefined;
    try fixture.initWithFieldPolicies(model_text_schema, &.{}, &.{}, &.{.{ .field = .functional_requirement, .path = &.{.{ .property = "text" }} }});
    defer fixture.deinit();
    fixture.fake.invocation_plan.complete.content = "{\"text\":{\"fragments\":[{\"kind\":\"passive\",\"passive_literal_id\":3}]}}";
    var response = try fixture.response();
    defer response.deinit();
    var validated = try (validate.Action{}).execute(std.testing.allocator, fixture.call, &response);
    defer validated.deinit();
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(allocationCase, .{ validated.evidence.result().complete, false });
    try std.testing.expectEqual(@as(usize, 1), fixture.fake.invocation_call_count);
}

test "native exact scope classifies raw prose without granting semantic support or crossing opaque references" {
    const composition = @import("domain/model_text_composition.zig");
    const field_policy = @import("domain/text_field_policy.zig");
    const native: @import("domain/model_exact_values.zig").Scope = .{ .reference_state = .{ .bytes = "REF-current" }, .occurrences = &.{.{ .claim_id = .{ .ordinal = 2 }, .bytes = "ACTIVE" }} };
    const competing: @import("domain/model_exact_values.zig").Scope = .{ .reference_state = native.reference_state, .occurrences = &.{ native.occurrences[0], .{ .claim_id = .{ .ordinal = 3 }, .bytes = "ACTIVE" } } };
    const Reason = @FieldType(@import("domain/typed_text.zig").Issue, "reason");
    const Case = struct { value: []const u8, field: field_policy.Field = .ac_then, scope: @import("domain/model_exact_values.zig").Scope = native, reason: ?Reason = null };
    for ([_]Case{
        .{ .value = "\"ACTIVE\"", .reason = .reference_only },
        .{ .value = "\"Display ACTIVE.\"" },
        .{ .value = "\"ACTIVE-suffix\"" },
        .{ .value = "\"ACTIVE\"", .scope = competing, .reason = .ambiguous_exact },
        .{ .value = "{\"fragments\":[{\"kind\":\"passive\",\"passive_literal_id\":7},\"ACTIVE\"]}" },
        .{ .value = "{\"fragments\":[\"ACT\",{\"kind\":\"passive\",\"passive_literal_id\":7},\"IVE\"]}" },
        .{ .value = "\"ACTIVE\"", .field = .entity_meaning },
        .{ .value = "\"ACTIVE\"", .field = .entity_name },
    }) |case| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const bytes = try std.mem.concat(a, u8, &.{ "{\"value\":", case.value, "}" });
        const document = try @import("domain/strict_json.zig").parse(a, bytes, .{ .maximum_depth = schema.max_json_depth }, false, null);
        const bindings: []const @import("domain/model_text_field.zig").Binding = &.{.{ .field = case.field, .path = &.{.{ .property = "value" }} }};
        const diagnostic = try composition.check(a, document.value, bindings, &.{}, &.{}, .{ .exact_scope = case.scope });
        if (case.reason) |expected| {
            try std.testing.expectEqual(@as(usize, 1), diagnostic.?.fields.len);
            try std.testing.expectEqual(expected, diagnostic.?.fields[0].issue.reason);
            try std.testing.expectEqualStrings("/value", diagnostic.?.fields[0].path);
        } else try std.testing.expect(diagnostic == null);
        // A null composition diagnostic assesses structure only. In particular,
        // attached suffixes and opaque references supply no occurrence evidence;
        // the separate native coverage owner still checks exact obligations.
        try std.testing.expectEqualStrings(bytes, try std.json.Stringify.valueAlloc(a, document.value, .{}));
    }
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(nativeCompositionAllocation, .{});
}
fn nativeCompositionAllocation(a: std.mem.Allocator) !void {
    const raw = "{\"value\":\"ACTIVE\"}";
    var document = try @import("domain/strict_json.zig").parse(a, raw, .{ .maximum_depth = schema.max_json_depth }, false, null);
    defer document.deinit();
    const diagnostic = (try @import("domain/model_text_composition.zig").check(a, document.value, &.{.{ .field = .ac_then, .path = &.{.{ .property = "value" }} }}, &.{}, &.{}, .{ .exact_scope = .{ .reference_state = .{ .bytes = "REF-current" }, .occurrences = &.{.{ .claim_id = .{ .ordinal = 2 }, .bytes = "ACTIVE" }} } })).?;
    defer diagnostic.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), diagnostic.fields.len);
    try std.testing.expectEqual(.reference_only, diagnostic.fields[0].issue.reason);
}
