const std = @import("std");
const schema = @import("domain/model_result_schema.zig");
const parser = @import("adapters/parsers/model_result_schemas.zig");
const compilation = @import("domain/workflow_compilation.zig");

test {
    _ = @import("json_composition_test.zig");
    _ = @import("json_composition_runtime_test.zig");
}

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

test "integer choice restrictions bind tagged fields without restricting unrelated integer support" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\{"type":"object","properties":{"value":{"type":"array","maxItems":2,"items":{"oneOf":[{"type":"string","maxLength":20},{"type":"object","properties":{"kind":{"const":"exact_copy"},"claim_id":{"type":"integer","minimum":1,"maximum":100}},"required":["kind","claim_id"],"additionalProperties":false}]}},"support":{"type":"array","maxItems":2,"items":{"type":"integer","minimum":1,"maximum":100}}},"required":["value","support"],"additionalProperties":false}
    ;
    const complete = try compile(a, source);
    const selected = try schema.restrict(std.testing.allocator, complete, &.{}, &.{.{ .kind = "exact_copy", .field = "claim_id", .allowed = &.{ 2, 7 } }});
    defer selected.release();
    const value = schema.findProperty(selected.selected().root().object, "value").?.schema;
    const exact = schema.findProperty(value.array.items.one_of[1].object, "claim_id").?.schema;
    try std.testing.expectEqualDeep(&[_]i64{ 2, 7 }, exact.integer_enumeration);
    try std.testing.expect(schema.findProperty(selected.selected().root().object, "support").?.schema.array.items.* == .integer);
    const validator = @import("domain/model_payload_schema.zig");
    try std.testing.expect(validator.validateValue(.{ .number = "2e0" }, exact) == null);
    try std.testing.expectEqual(.enum_mismatch, validator.validateValue(.{ .number = "1" }, exact).?.reason);
    var adapter: parser.Adapter = .{};
    for (std.enums.values(@import("domain/model_schema_projection.zig").Profile)) |profile| {
        const projection = try @import("domain/model_schema_projection.zig").render(a, selected.selected(), profile);
        if (profile == .complete) {
            const restored = try adapter.compiler().compileSelected(a, projection);
            try std.testing.expectEqualDeep(selected.selected().root().*, restored.root().*);
        } else try std.testing.expect(std.mem.indexOf(u8, projection, "\"enum\":[2,7]") != null);
    }
    for ([_]schema.IntegerChoice{
        .{ .kind = "exact_copy", .field = "other", .allowed = &.{2} },
        .{ .kind = "exact_copy", .field = "claim_id", .allowed = &.{101} },
        .{ .kind = "exact_copy", .field = "claim_id", .allowed = &.{} },
    }) |bad| try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, complete, &.{}, &.{bad}));
    // A retained packet may carry text choices into a provenance-only repair.
    // With no text selector in that selected schema, there is nothing to narrow.
    const provenance_only = try compile(a, "{\"type\":\"object\",\"properties\":{\"claim_ids\":{\"type\":\"array\",\"maxItems\":2,\"items\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":100}}},\"required\":[\"claim_ids\"],\"additionalProperties\":false}");
    const no_text = try schema.restrict(std.testing.allocator, provenance_only, &.{}, &.{.{ .kind = "exact_copy", .field = "claim_id", .allowed = &.{2} }});
    defer no_text.release();
    try std.testing.expectEqualDeep(provenance_only.root().*, no_text.selected().root().*);
}

test "derived integer choice sets accept 1024 values and reject larger sets" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\{"type":"object","properties":{"value":{"type":"object","properties":{"kind":{"const":"selected"},"id":{"type":"integer","minimum":1,"maximum":2000}},"required":["kind","id"],"additionalProperties":false}},"required":["value"],"additionalProperties":false}
    ;
    const complete = try compile(a, source);
    for ([_]usize{ 1024, 1025 }) |count| {
        const ids = try a.alloc(i64, count);
        for (ids, 0..) |*id, index| id.* = @intCast(index + 1);
        const choices = &[_]schema.IntegerChoice{.{ .kind = "selected", .field = "id", .allowed = ids }};
        if (count > schema.max_choices) {
            try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, complete, &.{}, choices));
        } else {
            const selected = try schema.restrict(std.testing.allocator, complete, &.{}, choices);
            defer selected.release();
            const id = schema.findProperty(schema.findProperty(selected.selected().root().object, "value").?.schema.object, "id").?.schema;
            try std.testing.expectEqual(count, id.integer_enumeration.len);
            var adapter: parser.Adapter = .{};
            const restored = try adapter.compiler().compileSelected(a, selected.selected().modelBytes());
            try std.testing.expectEqualDeep(selected.selected().root().*, restored.root().*);
        }
    }
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
        "{\"enum\":[1,2]}",
        "{\"type\":\"array\",\"items\":{\"type\":\"boolean\"},\"minItems\":0,\"maxItems\":4}",
        "{\"type\":\"object\",\"properties\":{\"optional\":{\"type\":\"boolean\"}},\"required\":[],\"additionalProperties\":false}",
    };
    for (accepted) |field| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const compiled = try compile(arena.allocator(), try fieldSchema(arena.allocator(), field));
        const cloned = try compiled.clone(arena.allocator());
        try std.testing.expectEqualStrings(compiled.bytes(), cloned.bytes());
        const transported = try compile(arena.allocator(), cloned.modelBytes());
        try std.testing.expectEqualDeep(compiled.root().*, transported.root().*);
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
        "{\"enum\":[\"x\",\"\\u0078\"]}",                                                                          "{\"enum\":[1,\"1\"]}",                                                                              "{\"const\":{}}",                                                                                                                "{\"const\":1.5}",
        "{\"const\":true,\"enum\":[\"yes\"]}",                                                                     "{\"enum\":[\"x\"],\"type\":\"string\"}",                                                            "{\"type\":\"object\"}",                                                                                                         "{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":true}",
        "{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":{\"type\":\"boolean\"}}", "{\"type\":\"object\",\"properties\":{},\"required\":[\"missing\"],\"additionalProperties\":false}", "{\"type\":\"object\",\"properties\":{\"x\":{\"type\":\"boolean\"}},\"required\":[\"x\",\"x\"],\"additionalProperties\":false}", "{\"type\":\"object\",\"properties\":{},\"additionalProperties\":false}",
        "{\"type\":\"object\",\"properties\":[],\"required\":[],\"additionalProperties\":false}",                  "{\"type\":\"object\",\"properties\":{},\"required\":true,\"additionalProperties\":false}",          "{\"anyOf\":[{},{}]}",                                                                                                           "{\"oneOf\":[]}",
        "{\"oneOf\":[{}]}",                                                                                        "{\"oneOf\":[{\"type\":\"boolean\"},{\"type\":\"boolean\"}]}",                                       "{\"enum\":[1,1]}",                                                                                                              "{\"enum\":[1,2.0]}",
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
    const cloned = try source.clone(copy.allocator(), null);
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
    for ([_]usize{ 256, 257, 1024, 1025 }) |count| {
        var buffer: std.array_list.Managed(u8) = .init(allocator);
        try buffer.appendSlice("{\"enum\":[");
        for (0..count) |index| {
            if (index != 0) try buffer.append(',');
            try buffer.appendSlice(try std.fmt.allocPrint(allocator, "\"value-{d}\"", .{index}));
        }
        try buffer.appendSlice("]}");
        const bytes = try fieldSchema(allocator, buffer.items);
        var adapter: parser.Adapter = .{};
        if (count <= 1024) {
            const compiled = try compile(allocator, bytes);
            const cloned = try compiled.clone(allocator);
            const projection = @import("domain/model_schema_projection.zig");
            const validation = @import("domain/model_payload_schema.zig");
            for (std.enums.values(projection.Profile)) |profile| {
                const projected = try projection.render(allocator, cloned, profile);
                const restored = try adapter.compiler().compileSelected(allocator, projected);
                try std.testing.expectEqualDeep(compiled.root().*, restored.root().*);
                const choices = restored.root().object[0].schema;
                try std.testing.expectEqual(count, choices.enumeration.len);
                try std.testing.expect(validation.validateValue(.{ .string = "value-0" }, choices) == null);
                const last = try std.fmt.allocPrint(allocator, "value-{d}", .{count - 1});
                try std.testing.expect(validation.validateValue(.{ .string = last }, choices) == null);
                const unavailable = try std.fmt.allocPrint(allocator, "value-{d}", .{count});
                try std.testing.expectEqual(.enum_mismatch, validation.validateValue(.{ .string = unavailable }, choices).?.reason);
            }
        } else {
            try std.testing.expectError(error.InvalidModelResultSchema, compile(allocator, bytes));
            try std.testing.expectError(error.InvalidModelResultSchema, adapter.compiler().compileSelected(allocator, bytes));
        }
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
    _ = try (try compile(arena.allocator(), referenced)).clone(arena.allocator());
}

const referenced =
    \\{ "$defs": {
    \\  "text": {"type":"string","minLength":1,"maxLength":64},
    \\  "answer": {"type":"object","properties":{"answer":{"$ref":"#/$defs/text"}},"required":["answer"],"additionalProperties":false},
    \\  "replacement": {"type":"object","properties":{"replacement":{"$ref":"#/$defs/text"}},"required":["replacement"],"additionalProperties":false}
    \\}, "$ref": "#/$defs/answer" }
;

test "local definitions retain captured authority and independently owned compact result views" {
    var original: std.heap.ArenaAllocator = .init(std.testing.allocator);
    var destination: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer destination.deinit();
    const compiled = try compile(original.allocator(), referenced);
    const copy = try compiled.clone(destination.allocator());
    original.deinit();
    try std.testing.expectEqualStrings(referenced, copy.bytes());
    try std.testing.expect(copy.modelBytes().len < referenced.len);
    try std.testing.expect(std.mem.indexOf(u8, copy.modelBytes(), "$ref") == null);
    try std.testing.expect(std.mem.indexOf(u8, copy.modelBytes(), "$defs") == null);
    try std.testing.expect(std.mem.indexOf(u8, copy.modelBytes(), "\n") == null);
    try std.testing.expect(copy.select(.{ .bytes = "text" }) == null);
    try std.testing.expect(copy.select(.{ .bytes = "missing" }) == null);
    const selected = copy.select(.{ .bytes = "replacement" }).?;
    try std.testing.expectEqualStrings(referenced, selected.bytes());
    try std.testing.expectEqualStrings("replacement", selected.root().object[0].name);
    try std.testing.expect(schema.findProperty(copy.root().object, "replacement") == null);
    for ([_]*const schema.Schema{ copy, selected }) |view| {
        const reparsed = try compile(destination.allocator(), view.modelBytes());
        try std.testing.expectEqualDeep(view.root().*, reparsed.root().*);
        try std.testing.expectEqualStrings(view.modelBytes(), reparsed.modelBytes());
    }
}

test "local reference validation rejects unknown cyclic remote escaped and unused invalid definitions" {
    const changes = [_][2][]const u8{
        .{ "#/$defs/text", "#/$defs/missing" },
        .{ "#/$defs/text", "#/$defs/answer" },
        .{ "#/$defs/text", "https://example.invalid/text" },
        .{ "#/$defs/text", "other.json#/$defs/text" },
        .{ "#/$defs/text", "#/$defs/te~1xt" },
        .{ "#/$defs/text", "#/$defs/text/properties/x" },
        .{ "{\"$ref\":\"#/$defs/text\"}", "{\"$ref\":\"#/$defs/text\",\"maxLength\":3}" },
        .{ "\"replacement\": {\"type\":\"object\"", "\"replacement\": {\"unknown\":true,\"type\":\"object\"" },
        .{ "\"text\": {\"type\":\"string\"", "\"text\": {\"$defs\":{},\"type\":\"string\"" },
        .{ "\"replacement\": {", "\"bad/name\": {" },
    };
    for (changes) |change| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const bytes = try std.mem.replaceOwned(u8, arena.allocator(), referenced, change[0], change[1]);
        try std.testing.expect(!std.mem.eql(u8, bytes, referenced));
        try std.testing.expectError(error.InvalidModelResultSchema, compile(arena.allocator(), bytes));
    }
}

test "reference expansion enforces node and depth bounds after substitution" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const child = try objectProperties(a, 16, "{\"type\":\"boolean\"}");
    const root = try objectProperties(a, 256, "{\"$ref\":\"#/$defs/child\"}");
    const bytes = try std.mem.concat(a, u8, &.{ "{\"$defs\":{\"child\":", child, "},", root[1..] });
    try std.testing.expectError(error.InvalidModelResultSchema, compile(a, bytes));
    const bounded_child = try objectProperties(a, 15, "{\"type\":\"boolean\"}");
    const small = try objectProperties(a, 14, "{\"type\":\"boolean\"}");
    const exact_root = try std.mem.replaceOwned(u8, a, root, "\"p255\":{\"$ref\":\"#/$defs/child\"}", "\"p255\":{\"$ref\":\"#/$defs/small\"}");
    // References are source syntax, not extra nodes in the expanded 4096-node tree.
    _ = try compile(a, try std.mem.concat(a, u8, &.{ "{\"$defs\":{\"child\":", bounded_child, ",\"small\":", small, "},", exact_root[1..] }));
    var defs: std.array_list.Managed(u8) = .init(a);
    for (0..schema.max_depth + 1) |index| {
        if (index != 0) try defs.append(',');
        try defs.appendSlice(try std.fmt.allocPrint(a, "\"d{d}\":{{\"$ref\":\"#/$defs/d{d}\"}}", .{ index, index + 1 }));
    }
    try defs.appendSlice(try std.fmt.allocPrint(a, ",\"d{d}\":{s}", .{ schema.max_depth + 1, replacement }));
    try std.testing.expectError(error.InvalidModelResultSchema, compile(a, try std.mem.concat(a, u8, &.{ "{\"$defs\":{", defs.items, "},\"$ref\":\"#/$defs/d0\"}" })));
}

test "nested type-disjoint alternatives accept but overlapping and nonobject response roots reject" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const disjoint = "{\"oneOf\":[{\"type\":\"boolean\"},{\"type\":\"null\"}]}";
    _ = try compile(a, try fieldSchema(a, disjoint));
    try std.testing.expectError(error.InvalidModelResultSchema, compile(a, disjoint));
    for ([_][]const u8{
        "{\"oneOf\":[{\"type\":\"string\",\"maxLength\":8},{\"const\":\"overlap\"}]}",
        "{\"oneOf\":[{\"type\":\"integer\",\"minimum\":0,\"maximum\":9},{\"const\":10}]}",
        "{\"oneOf\":[{\"type\":\"boolean\"},{\"oneOf\":[{\"type\":\"string\",\"maxLength\":8},{\"type\":\"null\"}]}]}",
    }) |bad| try std.testing.expectError(error.InvalidModelResultSchema, compile(a, try fieldSchema(a, bad)));
}

test "native availability narrows nested alternatives without altering canonical schemas" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, restrictChoices, .{});
}

fn restrictChoices(allocator: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original = try compile(a, try fieldSchema(a, variants));
    const narrowed = try schema.restrict(allocator, original, &.{.{ .kind = "clarification_needed" }}, &.{});
    defer narrowed.release();
    try std.testing.expect(narrowed.selected().isRestrictionOf(original));
    try std.testing.expect(!original.isRestrictionOf(narrowed.selected()));
    try std.testing.expectEqualStrings(original.bytes(), narrowed.selected().bytes());
    try std.testing.expect(std.mem.indexOf(u8, original.modelBytes(), "clarification_needed") != null);
    try std.testing.expect(std.mem.indexOf(u8, narrowed.selected().modelBytes(), "clarification_needed") == null);
    const check = @import("domain/model_payload_schema.zig");
    for ([_][]const u8{ "{\"value\":{\"kind\":\"content\",\"answer\":\"Supported\"}}", "{\"value\":{\"kind\":\"clarification_needed\",\"question\":\"Choose\"}}" }, 0..) |bytes, index| {
        const parsed = try std.json.parseFromSlice(std.json.Value, a, bytes, .{});
        try std.testing.expect(check.validateValue(@import("domain/model_envelope.zig").value(&parsed.value), original.root()) == null);
        try std.testing.expectEqual(index == 0, check.validateValue(@import("domain/model_envelope.zig").value(&parsed.value), narrowed.selected().root()) == null);
    }
    if (schema.restrict(allocator, original, &.{ .{ .kind = "content" }, .{ .kind = "clarification_needed" } }, &.{})) |unexpected| {
        unexpected.release();
        return error.TestUnexpectedResult;
    } else |err| switch (err) {
        error.OutOfMemory => return err,
        error.InvalidModelResultSchema => {},
    }
    const different = try compile(a, try fieldSchema(a, variants));
    try std.testing.expect(!narrowed.selected().isRestrictionOf(different));
    const copy = try narrowed.selected().clone(a);
    try std.testing.expectEqualStrings(narrowed.selected().modelBytes(), copy.modelBytes());
}
