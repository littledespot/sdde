const std = @import("std");
const schema = @import("domain/model_result_schema.zig");
const parser = @import("adapters/parsers/model_result_schemas.zig");
const compilation = @import("domain/workflow_compilation.zig");

const replacement =
    \\{"type":"object","properties":{"replacement":{"type":"string","maxLength":256}},"required":["replacement"],"additionalProperties":false}
;
const variants =
    \\{"oneOf":[
    \\{"type":"object","properties":{"kind":{"const":"content"},"answer":{"type":"string","minLength":1,"maxLength":64}},"required":["kind","answer"],"additionalProperties":false},
    \\{"type":"object","properties":{"kind":{"const":"clarification_needed"},"question":{"type":"string","maxLength":128}},"required":["kind","question"],"additionalProperties":false}]}
;

fn compile(allocator: std.mem.Allocator, bytes: []const u8) schema.Error!*const schema.Schema {
    var adapter: parser.Adapter = .{};
    return adapter.compiler().compile(allocator, bytes);
}

fn fieldSchema(allocator: std.mem.Allocator, field: []const u8) ![]const u8 {
    return std.mem.concat(allocator, u8, &.{ "{\"type\":\"object\",\"properties\":{\"value\":", field, "},\"required\":[\"value\"],\"additionalProperties\":false}" });
}

test "compact singleton schema compiles candidate fields without execution metadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const compiled = try compile(arena.allocator(), replacement);
    try std.testing.expectEqualStrings(replacement, compiled.bytes());
    const properties = compiled.root().object;
    try std.testing.expectEqual(@as(usize, 1), properties.len);
    try std.testing.expectEqualStrings("replacement", properties[0].name);
    try std.testing.expect(properties[0].required);
    try std.testing.expectEqual(@as(u32, 0), properties[0].schema.string.minimum);
    try std.testing.expectEqual(@as(u32, 256), properties[0].schema.string.maximum);
    try std.testing.expect(schema.findProperty(properties, "kind") == null);
}

test "oneOf compiles disjoint closed variants and retains domain selections" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const compiled = try compile(arena.allocator(), variants);
    try std.testing.expectEqual(@as(usize, 2), compiled.root().one_of.len);
    const content = compiled.root().one_of[0].object;
    try std.testing.expectEqualStrings("content", schema.findProperty(content, "kind").?.schema.constant.string);
    const nested = try compile(arena.allocator(), try fieldSchema(arena.allocator(), variants));
    try std.testing.expectEqual(@as(usize, 2), nested.root().object[0].schema.one_of.len);

    const group = try compile(arena.allocator(),
        \\{"type":"object","properties":{"replacementsByTargetId":{"type":"object","properties":{"target-a":{"type":"string","maxLength":64},"target-b":{"enum":["yes","no"]}},"required":["target-a","target-b"],"additionalProperties":false}},"required":["replacementsByTargetId"],"additionalProperties":false}
    );
    const targets = group.root().object[0].schema.object;
    try std.testing.expectEqual(@as(usize, 2), targets.len);
    try std.testing.expect(schema.findProperty(targets, "target-a").?.required);
    try std.testing.expect(schema.findProperty(targets, "target-b").?.required);
}

test "bounded scalar collection and optional property shapes are supported" {
    const accepted = [_][]const u8{
        "{\"type\":\"string\",\"maxLength\":0}",
        "{\"type\":\"integer\",\"minimum\":-9223372036854775808,\"maximum\":9223372036854775807}",
        "{\"type\":\"boolean\"}",
        "{\"type\":\"null\"}",
        "{\"const\":true}",
        "{\"const\":null}",
        "{\"const\":7}",
        "{\"const\":\"Unicode \\u00e9\"}",
        "{\"enum\":[\"one\",\"two\"]}",
        "{\"type\":\"array\",\"items\":{\"type\":\"boolean\"},\"minItems\":0,\"maxItems\":4}",
        "{\"type\":\"object\",\"properties\":{\"optional\":{\"type\":\"boolean\"}},\"required\":[],\"additionalProperties\":false}",
    };
    for (accepted) |field| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const compiled = try compile(arena.allocator(), try fieldSchema(arena.allocator(), field));
        const cloned = try compiled.clone(arena.allocator());
        try std.testing.expectEqualStrings(compiled.bytes(), cloned.bytes());
    }
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // These are ordinary schema-declared business fields, not runtime authority.
    _ = try compile(arena.allocator(),
        \\{"type":"object","properties":{"status":{"enum":["new","old"]},"requestId":{"type":"string","maxLength":32}},"required":["status","requestId"],"additionalProperties":false}
    );
}

test "schema transport rejects malformed duplicate trailing and legacy envelope documents" {
    const rejected = [_][]const u8{
        "",                                                                                                                                             "{",                        "{}",                                  "true",                                                    "[]",                                        "\xff",                                            "\xef\xbb\xbf" ++ replacement,
        replacement ++ " {}",                                                                                                                           replacement ++ " trailing", "```json\n" ++ replacement ++ "\n```", "{\"schemaVersion\":\"model-envelope/v1\",\"result\":{}}", "{\"type\":\"object\",\"type\":\"object\"}", "{\"type\":\"object\",\"t\\u0079pe\":\"object\"}", "{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":false,\"$schema\":\"other\"}",
        "{\"type\":\"object\",\"properties\":{\"x\":{\"type\":\"boolean\"},\"x\":{\"type\":\"null\"}},\"required\":[],\"additionalProperties\":false}",
    };
    for (rejected) |bytes| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        try std.testing.expectError(error.InvalidModelResultSchema, compile(arena.allocator(), bytes));
    }
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try compile(arena.allocator(), " \t\r\n" ++ replacement ++ "\n");
}

test "unknown contradictory unbounded and unsupported schema fields reject at any depth" {
    const rejected = [_][]const u8{
        "{}",                                                                                                      "true",                                                                                              "[]",                                                                                                                            "{\"type\":\"number\",\"minimum\":0,\"maximum\":1}",
        "{\"type\":[\"string\",\"null\"]}",                                                                        "{\"$ref\":\"https://example.invalid/schema\"}",                                                     "{\"type\":\"string\"}",                                                                                                         "{\"type\":\"string\",\"maxLength\":-1}",
        "{\"type\":\"string\",\"maxLength\":4294967296}",                                                          "{\"type\":\"string\",\"maxLength\":2.0}",                                                           "{\"type\":\"string\",\"minLength\":3,\"maxLength\":2}",                                                                         "{\"type\":\"string\",\"maxLength\":2,\"pattern\":\".*\"}",
        "{\"type\":\"boolean\",\"default\":true}",                                                                 "{\"type\":\"null\",\"nullable\":true}",                                                             "{\"type\":\"integer\",\"minimum\":0}",                                                                                          "{\"type\":\"integer\",\"minimum\":1,\"maximum\":0}",
        "{\"type\":\"integer\",\"minimum\":0,\"maximum\":9223372036854775808}",                                    "{\"type\":\"integer\",\"minimum\":0,\"maximum\":1e9999}",                                           "{\"type\":\"array\",\"items\":{\"type\":\"boolean\"}}",                                                                         "{\"type\":\"array\",\"maxItems\":2}",
        "{\"type\":\"array\",\"items\":[],\"maxItems\":2}",                                                        "{\"type\":\"array\",\"items\":{\"type\":\"boolean\"},\"minItems\":3,\"maxItems\":2}",               "{\"enum\":[]}",                                                                                                                 "{\"enum\":[\"x\",\"x\"]}",
        "{\"enum\":[\"x\",\"\\u0078\"]}",                                                                          "{\"enum\":[1]}",                                                                                    "{\"const\":{}}",                                                                                                                "{\"const\":1.5}",
        "{\"const\":true,\"enum\":[\"yes\"]}",                                                                     "{\"enum\":[\"x\"],\"type\":\"string\"}",                                                            "{\"type\":\"object\"}",                                                                                                         "{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":true}",
        "{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":{\"type\":\"boolean\"}}", "{\"type\":\"object\",\"properties\":{},\"required\":[\"missing\"],\"additionalProperties\":false}", "{\"type\":\"object\",\"properties\":{\"x\":{\"type\":\"boolean\"}},\"required\":[\"x\",\"x\"],\"additionalProperties\":false}", "{\"type\":\"object\",\"properties\":{},\"additionalProperties\":false}",
        "{\"type\":\"object\",\"properties\":[],\"required\":[],\"additionalProperties\":false}",                  "{\"type\":\"object\",\"properties\":{},\"required\":true,\"additionalProperties\":false}",          "{\"anyOf\":[{},{}]}",                                                                                                           "{\"oneOf\":[]}",
        "{\"oneOf\":[{}]}",                                                                                        "{\"oneOf\":[{\"type\":\"boolean\"},{\"type\":\"null\"}]}",
    };
    for (rejected) |field| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        try std.testing.expectError(error.InvalidModelResultSchema, compile(arena.allocator(), try fieldSchema(arena.allocator(), field)));
    }
}

test "root shape and variant discriminator must be explicit nonredundant and unique" {
    const rejected = [_][]const u8{
        "{\"type\":\"string\",\"maxLength\":64}",
        "{\"type\":\"object\",\"properties\":{\"kind\":{\"const\":\"content\"}},\"required\":[\"kind\"],\"additionalProperties\":false}",
        "{\"type\":\"object\",\"properties\":{\"kind\":{\"enum\":[\"content\"]}},\"required\":[\"kind\"],\"additionalProperties\":false}",
    };
    for (rejected) |bytes| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        try std.testing.expectError(error.InvalidModelResultSchema, compile(arena.allocator(), bytes));
    }
    const replacements = [_][2][]const u8{
        .{ "clarification_needed", "content" },
        .{ "\"required\":[\"kind\",\"question\"]", "\"required\":[\"question\"]" },
        .{ "{\"const\":\"content\"}", "{\"enum\":[\"content\",\"other\"]}" },
        .{ "{\"const\":\"content\"}", "{\"const\":0}" },
        .{ "{\"const\":\"content\"}", "{\"const\":\"\"}" },
    };
    for (replacements) |change| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const bytes = try std.mem.replaceOwned(u8, arena.allocator(), variants, change[0], change[1]);
        try std.testing.expect(!std.mem.eql(u8, variants, bytes));
        try std.testing.expectError(error.InvalidModelResultSchema, compile(arena.allocator(), bytes));
    }
}

test "schema compilation respects exact depth and byte guards" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var child: []const u8 = "{\"type\":\"boolean\"}";
    for (0..schema.max_depth - 2) |_| {
        child = try std.mem.concat(allocator, u8, &.{ "{\"type\":\"array\",\"maxItems\":1,\"items\":", child, "}" });
    }
    _ = try compile(allocator, try fieldSchema(allocator, child));
    child = try std.mem.concat(allocator, u8, &.{ "{\"type\":\"array\",\"maxItems\":1,\"items\":", child, "}" });
    try std.testing.expectError(error.InvalidModelResultSchema, compile(allocator, try fieldSchema(allocator, child)));

    const padded = try allocator.alloc(u8, schema.max_bytes + 1);
    @memset(padded, ' ');
    @memcpy(padded[0..replacement.len], replacement);
    _ = try compile(allocator, padded[0..schema.max_bytes]);
    try std.testing.expectError(error.InvalidModelResultSchema, compile(allocator, padded));
    var nested: std.array_list.Managed(u8) = .init(allocator);
    try nested.appendNTimes('[', schema.max_json_depth + 1);
    try nested.appendNTimes(']', schema.max_json_depth + 1);
    try std.testing.expectError(error.InvalidModelResultSchema, compile(allocator, nested.items));
}

test "schema resource cloning owns source properties literals and nested nodes" {
    var original = std.heap.ArenaAllocator.init(std.testing.allocator);
    var copy = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer copy.deinit();
    const bytes = try original.allocator().dupe(u8, variants);
    const source: compilation.CompiledResource = .{
        .id = .{ .bytes = "declared-result" },
        .content = .{ .result_schema = try compile(original.allocator(), bytes) },
    };
    @memset(bytes, 'x');
    try std.testing.expectEqualStrings(variants, source.bytes());
    const cloned = try source.clone(copy.allocator());
    original.deinit();
    try std.testing.expectEqualStrings(variants, cloned.bytes());
    try std.testing.expectEqual(.result_schema, cloned.kind());
    const properties = cloned.content.result_schema.root().one_of[1].object;
    try std.testing.expectEqualStrings("clarification_needed", schema.findProperty(properties, "kind").?.schema.constant.string);
    try std.testing.expectEqual(@as(u32, 128), schema.findProperty(properties, "question").?.schema.string.maximum);
}

test "property enumeration variant and total-node guards accept boundaries and reject excess" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    _ = try compile(allocator, try objectProperties(allocator, schema.max_properties, "{\"type\":\"boolean\"}"));
    try std.testing.expectError(error.InvalidModelResultSchema, compile(allocator, try objectProperties(allocator, schema.max_properties + 1, "{\"type\":\"boolean\"}")));
    for ([_]usize{ schema.max_choices, schema.max_choices + 1 }) |count| {
        var buffer: std.array_list.Managed(u8) = .init(allocator);
        try buffer.appendSlice("{\"enum\":[");
        for (0..count) |index| {
            if (index != 0) try buffer.append(',');
            try buffer.appendSlice(try std.fmt.allocPrint(allocator, "\"value-{d}\"", .{index}));
        }
        try buffer.appendSlice("]}");
        const bytes = try fieldSchema(allocator, buffer.items);
        if (count == schema.max_choices) {
            _ = try compile(allocator, bytes);
        } else try std.testing.expectError(error.InvalidModelResultSchema, compile(allocator, bytes));
    }
    for ([_]usize{ schema.max_variants, schema.max_variants + 1 }) |count| {
        var buffer: std.array_list.Managed(u8) = .init(allocator);
        try buffer.appendSlice("{\"oneOf\":[");
        for (0..count) |index| {
            if (index != 0) try buffer.append(',');
            try buffer.appendSlice("{\"type\":\"object\",\"properties\":{\"kind\":{\"const\":");
            try buffer.appendSlice(try std.fmt.allocPrint(allocator, "\"variant-{d}\"", .{index}));
            try buffer.appendSlice("}},\"required\":[\"kind\"],\"additionalProperties\":false}");
        }
        try buffer.appendSlice("]}");
        if (count == schema.max_variants) {
            _ = try compile(allocator, buffer.items);
        } else try std.testing.expectError(error.InvalidModelResultSchema, compile(allocator, buffer.items));
    }

    const child = try objectProperties(allocator, 15, "{\"type\":\"boolean\"}");
    const smaller_child = try objectProperties(allocator, 14, "{\"type\":\"boolean\"}");
    var buffer: std.array_list.Managed(u8) = .init(allocator);
    try buffer.appendSlice("{\"type\":\"object\",\"properties\":{");
    for (0..256) |index| {
        if (index != 0) try buffer.append(',');
        try buffer.appendSlice(try std.fmt.allocPrint(allocator, "\"p{d}\":", .{index}));
        try buffer.appendSlice(if (index == 255) smaller_child else child);
    }
    try buffer.appendSlice("},\"required\":[],\"additionalProperties\":false}");
    // 1 root + 255 * (1 object + 15 leaves) + (1 object + 14 leaves).
    try std.testing.expectEqual(@as(usize, 4096), schema.max_nodes);
    _ = try compile(allocator, buffer.items);
    try std.testing.expectError(error.InvalidModelResultSchema, compile(allocator, try objectProperties(allocator, 256, child)));
}

fn objectProperties(allocator: std.mem.Allocator, count: usize, child: []const u8) ![]const u8 {
    var buffer: std.array_list.Managed(u8) = .init(allocator);
    try buffer.appendSlice("{\"type\":\"object\",\"properties\":{");
    for (0..count) |index| {
        if (index != 0) try buffer.append(',');
        try buffer.appendSlice(try std.fmt.allocPrint(allocator, "\"p{d}\":", .{index}));
        try buffer.appendSlice(child);
    }
    try buffer.appendSlice("},\"required\":[],\"additionalProperties\":false}");
    return buffer.items;
}

test "schema compilation and cloning release every allocation on failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, compileAndClone, .{});
}

fn compileAndClone(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const compiled = try compile(arena.allocator(), variants);
    _ = try compiled.clone(arena.allocator());
}
