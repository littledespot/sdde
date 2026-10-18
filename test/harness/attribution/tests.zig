const std = @import("std");
const p = @import("preparation.zig");
const s = @import("scoring.zig");
const cli = @import("cli.zig");
const strict = @import("../../../src/domain/strict_json.zig");

test "attribution CLI accepts only explicit offline modes and safe paths" {
    _ = try cli.parse(&.{ "prepare", "test/calibration/bundle" });
    _ = try cli.parse(&.{ "validate", "test/calibration/bundle" });
    _ = try cli.parse(&.{ "score", "bundle", "receipts.json", "score.json" });
    _ = try cli.parse(&.{ "dispatch-request", "bundle", "trial-1", "calls.json", "request.json" });
    for ([_][]const []const u8{ &.{}, &.{"prepare"}, &.{ "acquire", "bundle" }, &.{ "prepare", "../outside" }, &.{ "score", "bundle", "receipts.json", "score.json", "--live" } }) |args| {
        if (cli.parse(args)) |_| return error.TestExpectedError else |_| {}
    }
}
test "attribution grouped rules retain every field once and reject malformed entries" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const value = try strict.parse(a, "[{\"field\":\"alpha\",\"instruction\":\"Write prose\"},{\"field\":\"beta\",\"instruction\":\"Write prose\"},{\"field\":\"gamma\",\"instruction\":\"Label\"}]", .{ .maximum_depth = 64 }, false, null);
    const grouped = try p.groupRules(a, value.value);
    try std.testing.expectEqual(@as(usize, 2), grouped.array.items.len);
    try std.testing.expectEqualStrings("alpha", grouped.array.items[0].object.get("fields").?.array.items[0].string);
    try std.testing.expectEqualStrings("beta", grouped.array.items[0].object.get("fields").?.array.items[1].string);
    for ([_][]const u8{ "{}", "[{\"field\":\"a\"}]", "[{\"field\":3,\"instruction\":\"x\"}]", "[{\"field\":\"a\",\"instruction\":\"x\",\"extra\":true}]" }) |bad| {
        const parsed = try strict.parse(a, bad, .{ .maximum_depth = 64 }, false, null);
        try std.testing.expectError(error.InvalidPacket, p.groupRules(a, parsed.value));
    }
}
test "attribution raw measurements count insertions independently of admission" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cases = [_]struct { text: []const u8, insertion: u32, prose: u32, malformed: u32 }{
        .{ .text = "{\"fragments\":[{\"kind\":\"exact_copy\"}]}", .insertion = 1, .prose = 0, .malformed = 0 },
        .{ .text = "{\"fragments\":[\" \",{\"kind\":\"source\",\"source_id\":1}]}", .insertion = 1, .prose = 0, .malformed = 0 },
        .{ .text = "{\"fragments\":[\"Display \",{\"kind\":\"exact_copy\"}]}", .insertion = 0, .prose = 1, .malformed = 0 },
        .{ .text = "\"ordinary prose\"", .insertion = 0, .prose = 1, .malformed = 0 },
        .{ .text = "{\"fragments\":[{\"kind\":\"foreign\"}]}", .insertion = 0, .prose = 0, .malformed = 1 },
        .{ .text = "{\"fragments\":[{\"kind\":\"exact_copy\",\"extra\":1}]}", .insertion = 0, .prose = 0, .malformed = 1 },
        .{ .text = "{\"fragments\":[{\"kind\":\"source\"}]}", .insertion = 0, .prose = 0, .malformed = 1 },
    };
    for (cases) |case| {
        const parsed = try strict.parse(a, case.text, .{ .maximum_depth = 64 }, false, null);
        var count: s.FieldCount = .{ .field = .functional_requirement };
        try s.observe(a, parsed.value, &count);
        try std.testing.expectEqual(case.insertion, count.insertion_only);
        try std.testing.expectEqual(case.prose, count.with_nonblank_prose);
        try std.testing.expectEqual(case.malformed, count.malformed_text_shape);
    }
}
test "attribution diagnostic decoders reject unknown metadata and duplicate fields" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "[{\"unknown\":true}]", "[{\"run\":\"x\",\"run\":\"y\"}]" }) |bytes| {
        if (p.decodeCalls(a, bytes)) |_| return error.TestExpectedError else |_| {}
    }
    for ([_][]const u8{ "{\"unknown\":true}", "{\"version\":\"request-replay/v1\"}" }) |bytes| {
        if (s.decodeRequest(a, bytes)) |_| return error.TestExpectedError else |_| {}
    }
    const calls = [_]@import("../../../src/domain/request_debugger.zig").Call{.{
        .run = "MOCK",
        .sequence = 1,
        .id = "request-1-inference-1",
        .workflow = "sample-workflow",
        .action = "invoke-model",
        .node = "sample-node",
        .request_step = "sample-request",
        .slot = "sample-slot",
        .kind = "inference",
        .original = "request-1-inference-1",
        .parent = null,
    }};
    const valid = try p.json(a, calls);
    try std.testing.expectEqual(@as(usize, 1), (try p.decodeCalls(a, valid)).len);
    for ([_]struct { before: []const u8, after: []const u8 }{
        .{ .before = "\"sequence\":1", .after = "\"sequence\":\"1\"" },
        .{ .before = "\"normalization\":\"none\"", .after = "\"normalization\":0" },
        .{ .before = "\"run\":\"MOCK\"", .after = "\"run\":[77,79,67,75]" },
    }) |case| {
        const bad = try std.mem.replaceOwned(u8, a, valid, case.before, case.after);
        try std.testing.expect(!std.mem.eql(u8, valid, bad));
        try std.testing.expectError(error.InvalidJsonDocument, p.decodeCalls(a, bad));
    }
}
test "attribution historical metadata cannot acquire current exact scope or version" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const captured = try p.description(a, .records);
    const bytes = try p.json(a, captured);
    _ = try strict.decode(p.CapturedDescription, a, bytes, .{ .maximum_depth = 64 });
    var value = try std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{});
    try value.object.put(a, "exact_scope", .null);
    try std.testing.expectError(error.InvalidJsonDocument, strict.decode(p.CapturedDescription, a, try p.json(a, value), .{ .maximum_depth = 64 }));
    _ = value.object.orderedRemove("exact_scope");
    value.object.getPtr("version").?.* = .{ .string = "model-request-debug/v8" };
    try std.testing.expectError(error.InvalidJsonDocument, strict.decode(p.CapturedDescription, a, try p.json(a, value), .{ .maximum_depth = 64 }));

    const record: s.CapturedRequestRecord = .{
        .id = "MOCK-history",
        .run = "MOCK-run",
        .sequence = 1,
        .parent_run = p.run,
        .parent_call = p.parentId(.records),
        .original_run = p.run,
        .original_call = p.parentId(.records),
        .node = "MOCK-node",
        .mode = .exact,
        .description = captured,
        .body = p.requestBytes(.records),
    };
    var replay = try std.json.parseFromSliceLeaky(std.json.Value, a, try p.json(a, record), .{});
    _ = try s.decodeRequest(a, try p.json(a, replay));
    try replay.object.getPtr("description").?.object.put(a, "exact_scope", .null);
    try std.testing.expectError(error.InvalidJsonDocument, s.decodeRequest(a, try p.json(a, replay)));
    _ = replay.object.getPtr("description").?.object.orderedRemove("exact_scope");
    replay.object.getPtr("version").?.* = .{ .string = "request-replay/v7" };
    try std.testing.expectError(error.InvalidJsonDocument, s.decodeRequest(a, try p.json(a, replay)));
}
test "attribution scorer distinguishes invalid provider content from explicit stops" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const description: p.CapturedDescription = .{
        .version = .@"model-request-debug/v5",
        .provider = "aws-bedrock",
        .model = "openai.gpt-oss-20b-1:0",
        .provider_config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2" } },
        .model_slot = "sample-slot",
        .workflow_id = "sample-workflow",
        .workflow_version = 1,
        .request_step = "sample-request",
        .content = &.{.{ .user = "MOCK request" }},
        .protocol_prompt = "MOCK protocol",
        .schema = "{}",
        .response_mode = .native_schema,
        .controls = .{ .temperature = .fixed },
        .reasoning_effort = "low",
        .operation_kind = .inference,
        .original_sources = &.{},
        .prose_fields = &.{},
        .field_policies = &.{},
    };
    for ([_]struct { stop: []const u8, expected: s.State }{
        .{ .stop = "end_turn", .expected = .invalid_provider },
        .{ .stop = "max_tokens", .expected = .stopped },
        .{ .stop = "content_filtered", .expected = .stopped },
    }) |case| {
        const body = try std.fmt.allocPrint(a, "{{\"stopReason\":\"{s}\",\"usage\":{{\"inputTokens\":1,\"outputTokens\":1,\"totalTokens\":2}},\"output\":{{\"message\":{{\"role\":\"assistant\",\"content\":[]}}}}}}", .{case.stop});
        const value = try s.measure(a, description, .{ .id = "MOCK-response", .outcome = .received, .status = 200, .body = body });
        try std.testing.expectEqual(case.expected, value.state);
        try std.testing.expectEqual(@as(u64, 1), value.input_tokens.?);
        try std.testing.expectEqual(@as(u64, 1), value.output_tokens.?);
    }
}
