const std = @import("std");
const action = @import("actions/model/decode_model_envelope.zig");
const validate = @import("actions/model/validate_provider_invocation_observation.zig");
const invocation = @import("domain/provider_invocation_validation.zig");
const schema = @import("domain/model_result_schema.zig");
const Fixture = @import("provider_invocation_test_fixture.zig").Fixture;

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
            var decoded = try (action.Action{}).execute(std.testing.allocator, validated.evidence.result().complete);
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
        try std.testing.expectEqual(@as(usize, 0), fixture.fake.count_call_count);
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
    var decoded = try (action.Action{}).execute(std.testing.allocator, validated.evidence.result().complete);
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
        var decoded = try (action.Action{}).execute(std.testing.allocator, validated.evidence.result().complete);
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
        }
    }
    try checkDocument("{\"brackets\":\"" ++ "[]{}" ** 100 ++ "\"}", true);
    // Surrounding JSON whitespace counts toward the existing output-byte guard.
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
    var one = try (action.Action{}).execute(std.testing.allocator, first_validation.evidence.result().complete);
    defer one.deinit();
    var two = try (action.Action{}).execute(std.testing.allocator, second_validation.evidence.result().complete);
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
    for ([_][]const u8{
        "{\"a\":[true,null,{\"text\":\"\\u00e9\",\"number\":1e9999}],\"b\":{}}",
        "{\"a\":[{\"key\":\"one\",\"key\":\"two\"}]}",
        "{\"a\":[1,2,3]} {}",
        "[1,2,3]",
    }, 0..) |bytes, index| {
        var fixture: Fixture = undefined;
        try fixture.init();
        defer fixture.deinit();
        fixture.fake.invocation_plan = .{ .complete = .{ .content = bytes, .input_tokens = 1, .output_tokens = 1 } };
        var response = try fixture.response();
        defer response.deinit();
        var validated = try (validate.Action{}).execute(std.testing.allocator, fixture.call, &response);
        defer validated.deinit();
        try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{ validated.evidence.result().complete, index == 0 });
        try std.testing.expectEqualStrings(bytes, validated.evidence.result().complete.content());
    }
}

fn allocationCase(allocator: std.mem.Allocator, complete: *const invocation.CompleteCandidate, accepted: bool) !void {
    var decoded = (action.Action{}).execute(allocator, complete) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidModelEnvelope => return std.testing.expect(!accepted),
    };
    defer decoded.deinit();
    try std.testing.expect(accepted);
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
