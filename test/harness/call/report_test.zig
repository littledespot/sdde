const std = @import("std");
const report_module = @import("report.zig");
const debug = @import("../../../src/domain/request_debugger.zig");
const description: debug.Description = .{
    .provider = "aws-bedrock",
    .model = "openai.gpt-oss-20b-1:0",
    .provider_config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2" } },
    .model_slot = "sample-slot",
    .workflow_id = "sample-workflow",
    .workflow_version = 1,
    .request_step = "prepare-sample",
    .content = &.{.{ .user = "MOCK ordinary request" }},
    .protocol_prompt = @import("../../../src/domain/model_controls.zig").response_format_guidance,
    .schema = "{\"type\":\"object\",\"properties\":{},\"additionalProperties\":false}",
    .response_mode = .prompt_only,
    .controls = .{ .temperature = .zero },
    .reasoning_effort = "low",
    .operation_kind = .inference,
};

fn report() report_module.Report {
    return .{
        .started_at_utc = "2026-10-10T00:00:00Z",
        .options = .{ .run = "zig-out/e2e-spec/MOCK-run", .workflow = "sample-workflow", .call = 1, .model = description.model, .reasoning_effort = "low" },
        .parent_run = "MOCK-run",
        .parent_call = "request-0-inference-1",
        .original_binding = description,
        .effective_binding = description,
        .context_path = "MOCK/context.json",
        .request_path = "MOCK/request.json",
    };
}

test "call reports redact decoded credentials before JSON and Markdown projections" {
    for ([_]struct { key: []const u8, encoded: []const u8 }{
        .{ .key = "MOCKcredential", .encoded = "{\"answer\":\"\\u004dOCKcredential\"}" },
        .{ .key = "MOCK_key&<>[]", .encoded = "{\"answer\":\"\\u004dOCK_key&<>[]\"}" },
    }) |example| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const parsed = try @import("../../../src/domain/strict_json.zig").decode(std.json.Value, a, example.encoded, .{ .maximum_depth = 8 });
        const decoded = parsed.object.get("answer").?.string;
        try std.testing.expectEqualStrings(example.key, decoded);
        try std.testing.expect(std.mem.indexOf(u8, example.encoded, example.key) == null);
        var value = report();
        value.trials = &.{.{
            .ordinal = 1,
            .request_id = "a" ** 32,
            .outcome = .completed,
            .diagnostic = decoded,
            .validation = .{ .extraction = .valid, .json = .valid, .schema = .valid, .model_text = decoded, .parsed = parsed, .input_tokens = 10, .output_tokens = 2 },
        }};
        var temp = std.testing.tmpDir(.{});
        defer temp.cleanup();
        const output = try @import("../e2e/report.zig").Output.reserve(std.testing.io, temp.dir);
        defer output.close(std.testing.io);
        try report_module.save(std.testing.io, a, output, value, example.key);
        const json = try @import("../files.zig").read(std.testing.io, a, temp.dir, "report.json");
        const markdown = try @import("../files.zig").read(std.testing.io, a, temp.dir, "report.md");
        var escaped: std.Io.Writer.Allocating = .init(a);
        defer escaped.deinit();
        try @import("../report.zig").escape(&escaped.writer, example.key);
        for ([_][]const u8{ json, markdown }) |bytes| try std.testing.expect(std.mem.indexOf(u8, bytes, example.key) == null);
        try std.testing.expect(std.mem.indexOf(u8, markdown, escaped.written()) == null);
        try std.testing.expect(std.mem.indexOf(u8, json, "[REDACTED_CREDENTIAL]") != null);
        try std.testing.expect(std.mem.indexOf(u8, markdown, "REDACTED") != null);
        const stored = try @import("../../../src/domain/strict_json.zig").decode(std.json.Value, a, json, .{ .maximum_depth = 64 });
        try std.testing.expectEqualStrings("not_assessed", stored.object.get("semantic_quality").?.string);
        try std.testing.expect(std.mem.indexOf(u8, markdown, "Input tokens: 10. Output tokens: 2.") != null);
        try std.testing.expectEqualStrings(example.key, value.trials[0].validation.model_text.?);
    }
}

test "call report retains ordinary candidate text unchanged" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var value = report();
    value.trials = &.{.{ .ordinal = 1, .request_id = "b" ** 32, .outcome = .protocol_invalid, .validation = .{ .model_text = "ordinary candidate", .json = .invalid } }};
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const output = try @import("../e2e/report.zig").Output.reserve(std.testing.io, temp.dir);
    defer output.close(std.testing.io);
    try report_module.save(std.testing.io, a, output, value, "MOCK_credential&");
    const json = try @import("../files.zig").read(std.testing.io, a, temp.dir, "report.json");
    const markdown = try @import("../files.zig").read(std.testing.io, a, temp.dir, "report.md");
    try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, value, .{ .whitespace = .indent_2 }), json);
    try std.testing.expectEqualStrings(try report_module.markdown(a, value), markdown);
    try std.testing.expect(std.mem.indexOf(u8, markdown, "failed or incomplete") != null);
}
