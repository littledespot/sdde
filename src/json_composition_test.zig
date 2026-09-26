const std = @import("std");
const composition = @import("domain/json_composition.zig");
const schemas = @import("adapters/parsers/model_result_schemas.zig");
const schema = @import("domain/model_result_schema.zig");
const pointer = @import("domain/json_pointer.zig");

fn compileSchema(allocator: std.mem.Allocator, bytes: []const u8) !*const schema.Schema {
    var adapter: schemas.Adapter = .{};
    return adapter.compiler().compile(allocator, bytes);
}
fn compilePlan(allocator: std.mem.Allocator, bytes: []const u8, canonical: *const schema.Schema) !*const composition.Plan {
    var adapter: schemas.Adapter = .{};
    return adapter.compiler().compileComposition(allocator, bytes, canonical);
}

test "named composition derives from one captured schema and rebinds after source cleanup" {
    var destination: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer destination.deinit();
    const a = destination.allocator();
    var source: std.heap.ArenaAllocator = .init(std.testing.allocator);
    const raw =
        \\{"$ref":"#/$defs/header","$defs":{"header":{"type":"object","properties":{"title":{"type":"string","maxLength":40}},"required":["title"],"additionalProperties":false},"ledger":{"type":"object","properties":{"rows":{"type":"array","items":{"type":"integer","minimum":0,"maximum":9},"maxItems":4},"complete":{"type":"boolean"}},"required":["rows","complete"],"additionalProperties":false}}}
    ;
    const config =
        \\{"schema":"json-composition/v1","result":"report","definition":"ledger","parts":{"rows":{"paths":["/rows"]},"state":{"paths":["/complete"]}}}
    ;
    const original_schema = try compileSchema(source.allocator(), raw);
    const original = try compilePlan(source.allocator(), config, original_schema);
    const canonical = try original_schema.clone(a);
    const copied = try original.clone(a, canonical);
    source.deinit();
    try std.testing.expect(copied.resultSchema() == canonical);
    try std.testing.expect(copied.completeSchema() == canonical.select(.{ .bytes = "ledger" }).?);
    try std.testing.expect(copied.completeSchema() != canonical);
    try std.testing.expectEqualStrings(config, copied.bytes());
    try std.testing.expectEqualStrings("ledger", copied.definition().?.bytes);
    try std.testing.expect((try copied.selectSchema(0, &.{})).root().object[0].schema == copied.completeSchema().root().object[0].schema);
    const root = try compilePlan(a,
        \\{"schema":"json-composition/v1","result":"report","parts":{"header":{"paths":["/title"]}}}
    , canonical);
    try std.testing.expect(root.definition() == null and root.completeSchema() == canonical);
    for ([_][]const u8{ "missing", "#/$defs/ledger", "header" }) |bad| {
        const invalid = try std.mem.replaceOwned(u8, a, config, "\"definition\":\"ledger\"", try std.fmt.allocPrint(a, "\"definition\":\"{s}\"", .{bad}));
        try std.testing.expectError(error.InvalidJsonComposition, compilePlan(a, invalid, canonical));
    }
    for ([_][]const u8{ "\"definition\":null", "\"definition\":3", "\"definition\":\"\"", "\"definition\":\"ledger\",\"fallback\":true" }) |bad| {
        const invalid = try std.mem.replaceOwned(u8, a, config, "\"definition\":\"ledger\"", bad);
        try std.testing.expectError(error.InvalidJsonComposition, compilePlan(a, invalid, canonical));
    }
    const foreign = try compileSchema(a, nested);
    try std.testing.expectError(error.InvalidJsonComposition, copied.clone(a, foreign));
}
const nested =
    \\{"type":"object","properties":{"header":{"type":"object","properties":{"title":{"type":"string","maxLength":40},"enabled":{"type":"boolean"}},"required":["title","enabled"],"additionalProperties":false},"rows":{"type":"array","items":{"type":"integer","minimum":0,"maximum":9},"maxItems":4},"details":{"type":"object","properties":{"note":{"type":"string","maxLength":80}},"required":["note"],"additionalProperties":false}},"required":["header","rows"],"additionalProperties":false}
;
const partition =
    \\{"schema":"json-composition/v1","result":"response-schema","parts":{"text":{"paths":["/header/title","/details"]},"flags":{"paths":["/header/enabled"]},"rows":{"paths":["/rows"],"requires":["text"]}}}
;
const tagged =
    \\{"oneOf":[{"type":"object","properties":{"kind":{"const":"ready"},"content":{"type":"string","maxLength":40},"detail":{"type":"integer","minimum":0,"maximum":5}},"required":["kind","content","detail"],"additionalProperties":false},{"type":"object","properties":{"kind":{"const":"blocked"},"reason":{"type":"string","maxLength":40},"detail":{"type":"boolean"}},"required":["kind","reason","detail"],"additionalProperties":false}]}
;
const tagged_partition =
    \\{"schema":"json-composition/v1","result":"response-schema","parts":{"content":{"paths":["/kind","/content","/reason"]},"detail":{"paths":["/detail"],"requires":["content"]}}}
;

test "composition derives nested projections without duplicating shape authority" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const canonical = try compileSchema(allocator, nested);
    const plan = try compilePlan(allocator, partition, canonical);
    try std.testing.expect(plan.resultSchema() == canonical);
    try std.testing.expectEqualStrings(partition, plan.bytes());
    try std.testing.expectEqualStrings("response-schema", plan.resultAlias().bytes);
    const text = try plan.selectSchema(0, &.{});
    const header = schema.findProperty(text.root().object, "header").?;
    try std.testing.expectEqual(@as(usize, 1), header.schema.object.len);
    try std.testing.expectEqualStrings("title", header.schema.object[0].name);
    try std.testing.expect(!schema.findProperty(text.root().object, "details").?.required);
    const title = schema.findProperty(canonical.root().object, "header").?.schema.object[0].schema;
    try std.testing.expect(header.schema.object[0].schema == title);
    try std.testing.expectError(error.InvalidCompositionSelection, plan.selectSchema(2, &.{}));
    const rows = try plan.selectSchema(2, &.{.{ .part = 0, .value = .{ .object = .{} } }});
    try std.testing.expect(rows.root().object[0].schema == schema.findProperty(canonical.root().object, "rows").?.schema);
    try std.testing.expectError(error.InvalidCompositionSelection, plan.selectSchema(2, &.{.{ .part = 1, .value = .{ .object = .{} } }}));
}

test "composition selects unequal variant projections only through declared discriminator prerequisites" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const canonical = try compileSchema(allocator, tagged);
    const plan = try compilePlan(allocator, tagged_partition, canonical);
    try std.testing.expectEqual(@as(usize, 2), (try plan.selectSchema(0, &.{})).root().one_of.len);
    var ready: std.json.ObjectMap = .{};
    try ready.put(allocator, "kind", .{ .string = "ready" });
    const detail = try plan.selectSchema(1, &.{.{ .part = 0, .value = .{ .object = ready } }});
    try std.testing.expect(detail.root().object[0].schema.* == .integer);
    try ready.put(allocator, "kind", .{ .string = "blocked" });
    const blocked = try plan.selectSchema(1, &.{.{ .part = 0, .value = .{ .object = ready } }});
    try std.testing.expect(blocked.root().object[0].schema.* == .boolean);
    try ready.put(allocator, "kind", .{ .string = "invented" });
    try std.testing.expectError(error.InvalidCompositionSelection, plan.selectSchema(1, &.{.{ .part = 0, .value = .{ .object = ready } }}));
    const independent =
        \\{"schema":"json-composition/v1","result":"response-schema","parts":{"content":{"paths":["/kind","/content","/reason"]},"detail":{"paths":["/detail"]}}}
    ;
    try std.testing.expectError(error.InvalidJsonComposition, compilePlan(allocator, independent, canonical));
}

test "composition rejects a part absent from a reachable tagged branch" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const canonical = try compileSchema(allocator, tagged);
    const every_branch =
        \\{"schema":"json-composition/v1","result":"response-schema","parts":{"status":{"paths":["/kind","/detail"]},"body":{"paths":["/content","/reason"],"requires":["status"]}}}
    ;
    _ = try compilePlan(allocator, every_branch, canonical);
    const missing_blocked_branch =
        \\{"schema":"json-composition/v1","result":"response-schema","parts":{"status":{"paths":["/kind","/detail","/reason"]},"body":{"paths":["/content"],"requires":["status"]}}}
    ;
    try std.testing.expectError(error.InvalidJsonComposition, compilePlan(allocator, missing_blocked_branch, canonical));
}

test "nested variant selection ignores discriminator paths in inactive outer branches" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const canonical = try compileSchema(a,
        \\{"oneOf":[
        \\ {"type":"object","properties":{"kind":{"const":"ready"},"details":{"oneOf":[
        \\  {"type":"object","properties":{"kind":{"const":"text"},"value":{"type":"string","maxLength":16}},"required":["kind","value"],"additionalProperties":false},
        \\  {"type":"object","properties":{"kind":{"const":"count"},"value":{"type":"integer","minimum":0,"maximum":9}},"required":["kind","value"],"additionalProperties":false}
        \\ ]}},"required":["kind","details"],"additionalProperties":false},
        \\ {"type":"object","properties":{"kind":{"const":"blocked"},"other":{"oneOf":[
        \\  {"type":"object","properties":{"kind":{"const":"flag"},"value":{"type":"boolean"}},"required":["kind","value"],"additionalProperties":false},
        \\  {"type":"object","properties":{"kind":{"const":"empty"},"value":{"type":"null"}},"required":["kind","value"],"additionalProperties":false}
        \\ ]}},"required":["kind","other"],"additionalProperties":false}
        \\]}
    );
    const plan = try compilePlan(a,
        \\{"schema":"json-composition/v1","result":"result","parts":{"tags":{"paths":["/kind","/details/kind","/other/kind"]},"value":{"paths":["/details/value","/other/value"],"requires":["tags"]}}}
    , canonical);
    const cases = [_]struct { input: []const u8, path: []const u8, node: std.meta.Tag(schema.Node) }{
        .{ .input = "{\"kind\":\"ready\",\"details\":{\"kind\":\"text\"}}", .path = "details", .node = .string },
        .{ .input = "{\"kind\":\"ready\",\"details\":{\"kind\":\"count\"}}", .path = "details", .node = .integer },
        .{ .input = "{\"kind\":\"blocked\",\"other\":{\"kind\":\"flag\"}}", .path = "other", .node = .boolean },
        .{ .input = "{\"kind\":\"blocked\",\"other\":{\"kind\":\"empty\"}}", .path = "other", .node = .null_value },
    };
    for (cases) |case| {
        var parsed = try @import("domain/strict_json.zig").parse(a, case.input, .{ .maximum_depth = 8 }, false, null);
        defer parsed.deinit();
        try std.testing.expect(@import("domain/model_payload_schema.zig").validateValue(@import("domain/model_envelope.zig").value(&parsed.value), (try plan.selectSchema(0, &.{})).root()) == null);
        const selected = try plan.selectSchema(1, &.{.{ .part = 0, .value = parsed.value }});
        try std.testing.expectEqual(@as(usize, 1), selected.root().object.len);
        const field = selected.root().object[0];
        try std.testing.expectEqualStrings(case.path, field.name);
        try std.testing.expectEqual(case.node, std.meta.activeTag(schema.findProperty(field.schema.object, "value").?.schema.*));
    }
    try std.testing.expectError(error.InvalidCompositionSelection, plan.selectSchema(1, &.{}));
    var missing = try @import("domain/strict_json.zig").parse(a, "{\"kind\":\"blocked\",\"other\":{}}", .{ .maximum_depth = 8 }, false, null);
    defer missing.deinit();
    try std.testing.expectError(error.InvalidCompositionSelection, plan.selectSchema(1, &.{.{ .part = 0, .value = missing.value }}));
}

test "extraction content and classifications derive from complete schema and retain all branches" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/extraction.schema.json", allocator, .unlimited);
    const canonical = try compileSchema(allocator, bytes);
    const config =
        \\{"schema":"json-composition/v1","result":"extraction-schema","parts":{"content":{"paths":["/kind","/claims","/reason"]},"classifications":{"paths":["/token_classifications"],"requires":["content"]}}}
    ;
    const plan = try compilePlan(allocator, config, canonical);
    const content = try plan.selectSchema(0, &.{});
    try std.testing.expectEqual(@as(usize, 2), content.root().one_of.len);
    for (content.root().one_of) |variant| try std.testing.expect(schema.findProperty(variant.object, "token_classifications") == null);
    try std.testing.expectEqual(@as(usize, 1), plan.parts()[1].alternatives.len);
    var prior: std.json.ObjectMap = .{};
    try prior.put(allocator, "kind", .{ .string = "claims" });
    const classifications = try plan.selectSchema(1, &.{.{ .part = 0, .value = .{ .object = prior } }});
    try std.testing.expectEqual(@as(usize, 1), classifications.root().object.len);
    try std.testing.expectEqualStrings("token_classifications", classifications.root().object[0].name);
    try std.testing.expect(classifications.root().object[0].schema == schema.findProperty(canonical.root().one_of[0].object, "token_classifications").?.schema);
}

test "composition rejects malformed contracts unsafe paths incomplete ownership and dependency cycles" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const canonical = try compileSchema(allocator, nested);
    const bad = [_][]const u8{
        "{}",
        "{\"schema\":\"json-composition/v1\",\"result\":\"response-schema\",\"parts\":{},\"extra\":true}",
        "{\"schema\":\"json-composition/v1\",\"result\":\"response-schema\",\"parts\":{\"a\":{\"paths\":[\"/header\"]},\"b\":{\"paths\":[\"/rows\"]}}}",
        "{\"schema\":\"json-composition/v1\",\"result\":\"response-schema\",\"parts\":{\"a\":{\"paths\":[\"/header\",\"/details/note\"]},\"b\":{\"paths\":[\"/rows\"]}}}",
        "{\"schema\":\"json-composition/v1\",\"result\":\"response-schema\",\"parts\":{\"a\":{\"paths\":[\"/header\",\"/details\"]},\"b\":{\"paths\":[\"/rows/0\"]}}}",
        "{\"schema\":\"json-composition/v1\",\"result\":\"response-schema\",\"parts\":{\"a\":{\"paths\":[\"/header\",\"/details\"]},\"b\":{\"paths\":[\"/rows\",\"/header/title\"]}}}",
        "{\"schema\":\"json-composition/v1\",\"result\":\"response-schema\",\"parts\":{\"a\":{\"paths\":[\"/header\",\"/details\"]},\"b\":{\"paths\":[\"/rows\",\"/invented\"]}}}",
        "{\"schema\":\"json-composition/v1\",\"result\":\"response-schema\",\"parts\":{\"a\":{\"paths\":[\"/header\",\"/details\"],\"requires\":[\"b\"]},\"b\":{\"paths\":[\"/rows\"],\"requires\":[\"a\"]}}}",
        "{\"schema\":\"json-composition/v1\",\"result\":\"response-schema\",\"parts\":{\"a\":{\"paths\":[\"/header\",\"/details\"]},\"b\":{\"paths\":[\"/rows\"],\"requires\":[\"missing\"]}}}",
        "{\"schema\":\"json-composition/v1\",\"result\":\"response-schema\",\"parts\":{\"a\":{\"paths\":[\"/header\",\"/details\"],\"unknown\":false},\"b\":{\"paths\":[\"/rows\"]}}}",
        "{\"schema\":\"json-composition/v1\",\"result\":\"response-schema\",\"parts\":{\"a\":{\"paths\":[\"/header\",\"/details\"]},\"b\":{\"paths\":[\"/rows~2\"]}}}",
        "{\"schema\":\"json-composition/v1\",\"result\":\"response-schema\",\"parts\":{\"a\":{\"paths\":[\"/header\",\"/details\"]},\"b\":{\"paths\":[\"/rows\",\"/rows\"]}}}",
    };
    for (bad) |config| try std.testing.expectError(error.InvalidJsonComposition, compilePlan(allocator, config, canonical));
}

test "shared JSON pointers decode escaped properties and compare complete segments" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const path = try pointer.parse(allocator, "/a~1b/c~0d/0/");
    try std.testing.expectEqualStrings("a/b", path.segments[0]);
    try std.testing.expectEqualStrings("c~d", path.segments[1]);
    try std.testing.expectEqualStrings("0", path.segments[2]);
    try std.testing.expectEqualStrings("", path.segments[3]);
    try std.testing.expect(!(try pointer.parse(allocator, "/a")).isPrefixOf(try pointer.parse(allocator, "/ab")));
    for ([_][]const u8{ "a", "/~", "/~2" }) |invalid| try std.testing.expectError(error.InvalidJsonPointer, pointer.parse(allocator, invalid));
    var values: std.json.Array = .init(allocator);
    try values.append(.{ .string = "first" });
    const array: std.json.Value = .{ .array = values };
    try std.testing.expectEqualStrings("first", pointer.lookup(array, try pointer.parse(allocator, "/0")).?.string);
    for ([_][]const u8{ "/00", "/-", "/1", "/+0" }) |invalid| try std.testing.expect(pointer.lookup(array, try pointer.parse(allocator, invalid)) == null);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, pointerAllocation, .{});
}

fn pointerAllocation(allocator: std.mem.Allocator) !void {
    const selected = try pointer.parse(allocator, "/a~1b/c~0d/0/");
    defer {
        for (selected.segments) |segment| allocator.free(segment);
        allocator.free(selected.segments);
    }
    try std.testing.expectEqualStrings("a/b", selected.segments[0]);
}

test "composition clone rebinds canonical schema and keeps equal destination values distinct" {
    var destination: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer destination.deinit();
    var source: std.heap.ArenaAllocator = .init(std.testing.allocator);
    const raw =
        \\{"$defs":{"address":{"type":"object","properties":{"city":{"type":"string","maxLength":50}},"required":["city"],"additionalProperties":false}},"type":"object","properties":{"billing":{"$ref":"#/$defs/address"},"shipping":{"$ref":"#/$defs/address"}},"required":["billing","shipping"],"additionalProperties":false}
    ;
    const config =
        \\{"schema":"json-composition/v1","result":"addresses","parts":{"billing":{"paths":["/billing"]},"shipping":{"paths":["/shipping"]}}}
    ;
    const original_schema = try compileSchema(source.allocator(), raw);
    const original = try compilePlan(source.allocator(), config, original_schema);
    const canonical = try original_schema.clone(destination.allocator());
    const copied = try original.clone(destination.allocator(), canonical);
    source.deinit();
    try std.testing.expect(copied.resultSchema() == canonical);
    try std.testing.expectEqualStrings(config, copied.bytes());
    const billing = try copied.selectSchema(0, &.{});
    const shipping = try copied.selectSchema(1, &.{});
    try std.testing.expect(billing != shipping);
    try std.testing.expectEqualStrings("billing", billing.root().object[0].name);
    try std.testing.expectEqualStrings("shipping", shipping.root().object[0].name);
    try std.testing.expect(billing.root().object[0].schema == schema.findProperty(canonical.root().object, "billing").?.schema);
}

test "composition retains type-disjoint values whole and rejects inferred discriminator splits" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const canonical = try compileSchema(a,
        \\{"type":"object","properties":{"payload":{"oneOf":[{"type":"string","maxLength":100},{"type":"object","properties":{"kind":{"const":"ref"},"id":{"type":"integer","minimum":1,"maximum":100}},"required":["kind","id"],"additionalProperties":false}]}},"required":["payload"],"additionalProperties":false}
    );
    const whole = try compilePlan(a,
        \\{"schema":"json-composition/v1","result":"shape","parts":{"content":{"paths":["/payload"]}}}
    , canonical);
    try std.testing.expectEqual(@as(usize, 1), whole.parts().len);
    try std.testing.expectError(error.InvalidJsonComposition, compilePlan(a,
        \\{"schema":"json-composition/v1","result":"shape","parts":{"content":{"paths":["/payload/kind","/payload/id"]}}}
    , canonical));
}
