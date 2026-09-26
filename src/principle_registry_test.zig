const std = @import("std");
const r = @import("domain/principle_registry.zig");
const p = @import("domain/principle_policy.zig");
const fixture = @import("test_fixtures/principles.zig");
const unicode = @import("unicode_normalization");
const normalizer: @import("ports/unicode_normalizer.zig").Normalizer = .{ .normalize_fn = unicode.nfc };
const folder: @import("ports/unicode_normalizer.zig").CaseFolder = .{ .fold_fn = unicode.caseFold };
fn file(name: []const u8, id: u128, size: u64) @import("domain/source_inventory.zig").Descriptor {
    return .{ .raw_path = name, .observation = .{ .file = .{ .identity = .{ .filesystem_id = 1, .file_id = id }, .size = size, .modified_ns = 0, .changed_ns = 0 } } };
}
test "shared inventory and principle policy preserve Unicode allocation failures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const failure = struct {
        fn transform(_: std.mem.Allocator, _: []const u8, _: usize) @import("ports/unicode_normalizer.zig").Error![]u8 {
            return error.OutOfMemory;
        }
    }.transform;
    for (0..2) |mode| {
        const n: @import("ports/unicode_normalizer.zig").Normalizer = if (mode == 0) .{ .normalize_fn = failure } else normalizer;
        const f: @import("ports/unicode_normalizer.zig").CaseFolder = if (mode == 1) .{ .fold_fn = failure } else folder;
        try std.testing.expectError(error.OutOfMemory, @import("domain/source_inventory.zig").validate(a, &.{file("policy.md", 1, 0)}, r.limits, n, f));
        try std.testing.expectError(error.OutOfMemory, p.compile(a, .{ .filenames = &.{"policy.md"}, .categories = &.{.custom}, .selections = &.{fixture.selection} }, n, f));
    }
}
test "principle selection has one explicit configuration owner and rejects incomplete policy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const input: p.Input = .{ .filenames = &.{"core.md"}, .categories = &.{.core}, .selections = &.{ fixture.selection, .{ .stage = .plan, .environment = "server", .fileKind = "source", .categories = &.{ .core, .custom, .security } } } };
    const policy = try p.compile(a, input, normalizer, folder);
    const spec = try p.select(policy, .{ .stage = .spec, .environment = null, .fileKind = null });
    try std.testing.expect(spec.contains(.core) and spec.contains(.custom) and !spec.contains(.security));
    try std.testing.expect((try p.select(policy, .{ .stage = .plan, .environment = "server", .fileKind = "source" })).contains(.security));
    try std.testing.expectError(error.InvalidPrinciplePolicy, p.select(policy, .{ .stage = .plan, .environment = "client", .fileKind = "source" }));
    try std.testing.expectEqual(.custom, p.category(policy, "nested/security-looking-prose.md"));
    for (0..6) |mode| {
        var invalid = input;
        switch (mode) {
            0 => invalid.selections = &.{},
            1 => invalid.selections = &.{ fixture.selection, fixture.selection },
            2 => invalid.selections = &.{.{ .stage = .spec, .environment = null, .fileKind = null, .categories = &.{.core} }},
            3 => {
                invalid.filenames = &.{ "Core.md", "core.md" };
                invalid.categories = &.{ .core, .custom };
            },
            4 => invalid.filenames = &.{"../core.md"},
            5 => invalid.selections = &.{.{ .stage = .spec, .environment = "server", .fileKind = null, .categories = &.{ .core, .custom } }},
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidPrinciplePolicy, p.compile(a, invalid, normalizer, folder));
    }
    for ([_][]const u8{
        "{\"filenameHints\":{},\"selections\":[],\"fallback\":true}",
        "{\"filenameHints\":{\"core.md\":\"unknown\"},\"selections\":[]}",
        "{\"filenameHints\":{},\"selections\":[{\"stage\":\"spec\",\"environment\":null,\"fileKind\":null,\"categories\":[\"core\"],\"autoSelect\":true}]}",
    }) |bytes| {
        const full = try std.fmt.allocPrint(a, "{{\"logs\":{{\"level\":\"info\",\"console\":false}},\"models\":{{\"slots\":{{}}}},\"paths\":{{\"specs\":\"s\",\"references\":\"r\",\"specsArchive\":\"s/a\",\"workflows\":\"w\",\"toolchainPreset\":\"t\",\"principles\":\"p\",\"templates\":\"x\",\"providers\":\".sddproviders.json\"}},\"principles\":{s}}}", .{bytes});
        try std.testing.expectError(error.EngineConfigParseError, (@import("actions/config/decode_sddtoolkit_config.zig").Action{}).execute(a, full));
    }
}
test "semantic inventory accounts for the exact mechanical exclusion and rejects unsafe siblings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root: r.Root = .{ .path = "policy", .identity = .{ .filesystem_id = 1, .file_id = 1 } };
    const valid = try r.classify(a, .{ .root = root, .entries = &.{ file("toolchain.yaml", 2, 999), file("arbitrary.md", 3, 3) } }, normalizer, folder);
    try std.testing.expectEqual(@as(usize, 3), valid.source_bytes);
    try std.testing.expectEqual(.mechanical_toolchain_layer_excluded, valid.entries[1].kind);
    for ([_][]const u8{ "toolchain.yml", "foo.yaml", "../bad.md", "nested/child.md" }) |name| try std.testing.expectError(error.InvalidPrincipleRegistry, r.classify(a, .{ .root = root, .entries = &.{file(name, 2, 0)} }, normalizer, folder));
    for ([_][2][]const u8{ .{ "A.md", "a.md" }, .{ "Café.md", "Cafe\u{301}.md" }, .{ "Straße.md", "STRASSE.md" } }) |names| try std.testing.expectError(error.InvalidPrincipleRegistry, r.classify(a, .{ .root = root, .entries = &.{ file("toolchain.yaml", 2, 0), file(names[0], 3, 0), file(names[1], 4, 0) } }, normalizer, folder));
    try std.testing.expectError(error.InvalidPrincipleRegistry, r.classify(a, .{ .root = root, .entries = &.{ file("toolchain.yaml", 2, 0), file("a.md", 3, 0), file("b.md", 3, 0) } }, normalizer, folder));
    inline for (.{ .symlink, .special, .unreadable }) |tag| try std.testing.expectError(error.InvalidPrincipleRegistry, r.classify(a, .{ .root = root, .entries = &.{ file("toolchain.yaml", 2, 0), .{ .raw_path = "other.md", .observation = @unionInit(@import("domain/source_inventory.zig").Observation, @tagName(tag), {}) } } }, normalizer, folder));
}
test "principle chunks cover every selected byte and citations reject stale foreign and omitted chunks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const prose = "# 任意 policy\r\nKeep precise evidence.\n" ** 1500;
    const registry = try fixture.registry(a, prose);
    const selected = try r.select(a, registry, .{ .stage = .spec, .environment = null, .fileKind = null });
    const guidance = try r.guidance(a, registry, selected);
    try std.testing.expect(guidance.len > 1);
    var bytes: std.ArrayList(u8) = .empty;
    for (guidance) |span| try bytes.appendSlice(a, span.text);
    try std.testing.expectEqualStrings(prose, bytes.items);
    try std.testing.expectEqual(null, try r.validateCitation(registry, selected, .{ .chunk = selected.chunks[0], .first_line = 1, .last_line = 1 }));
    try std.testing.expectEqualDeep(r.CitationDiagnostic{ .field = .chunk, .rejected = 999 }, (try r.validateCitation(registry, selected, .{ .chunk = .{ .ordinal = 999 }, .first_line = 1, .last_line = 1 })).?);
    try std.testing.expectEqualDeep(r.CitationDiagnostic{ .field = .first_line, .rejected = 0, .bounds = .{ .minimum = 1, .maximum = guidance[0].last_line } }, (try r.validateCitation(registry, selected, .{ .chunk = selected.chunks[0], .first_line = 0, .last_line = 1 })).?);
    for (guidance) |span| {
        try std.testing.expectEqual(null, try r.validateCitation(registry, selected, .{ .chunk = span.id, .first_line = span.first_line, .last_line = span.last_line }));
        const bounds: r.LineBounds = .{ .minimum = span.first_line, .maximum = span.last_line };
        for ([_]u32{ span.first_line - 1, span.last_line + 1 }) |line| {
            try std.testing.expectEqualDeep(r.CitationDiagnostic{ .field = .first_line, .rejected = line, .bounds = bounds }, (try r.validateCitation(registry, selected, .{ .chunk = span.id, .first_line = line, .last_line = span.last_line })).?);
            try std.testing.expectEqualDeep(r.CitationDiagnostic{ .field = .last_line, .rejected = line, .bounds = bounds }, (try r.validateCitation(registry, selected, .{ .chunk = span.id, .first_line = span.first_line, .last_line = line })).?);
        }
    }
    // Transport and validation share source coordinates, including mid-line splits.
    try std.testing.expect(registry.chunks[1].span.start.column > 1);
    var broken = selected;
    broken.registry.revision += 1;
    try std.testing.expectError(error.InvalidPrincipleRegistry, r.validateCitation(registry, broken, .{ .chunk = selected.chunks[0], .first_line = 1, .last_line = 1 }));
    try std.testing.expectError(error.InvalidPrincipleRegistry, r.validateSelection(a, registry, broken));
    broken = selected;
    broken.chunks = broken.chunks[1..];
    try std.testing.expectError(error.InvalidPrincipleRegistry, r.validateSelection(a, registry, broken));
    const captures = [_]r.Capture{.{ .entry = 1, .bytes = prose }};
    const same = try r.build(a, .{ .inventory = registry.inventory, .sources = &captures }, registry.policy, registry);
    try std.testing.expectEqualDeep(registry.id, same.id);
    const changed_text = try a.dupe(u8, prose);
    changed_text[0] = '!';
    const changed = try r.build(a, .{ .inventory = registry.inventory, .sources = &.{.{ .entry = 1, .bytes = changed_text }} }, registry.policy, registry);
    try std.testing.expectEqual(registry.id.revision + 1, changed.id.revision);
    try std.testing.expect(changed.sources[0].id.ordinal >= registry.next_source);
    try std.testing.expect(changed.chunks[0].id.ordinal >= registry.next_chunk);
    try std.testing.expectError(error.InvalidPrincipleRegistry, r.validateSelection(a, changed, selected));
    const renewed = try r.select(a, changed, selected.scope);
    try std.testing.expect(renewed.chunks[0].ordinal > renewed.chunks.len);
    try std.testing.expectEqual(null, try r.validateCitation(changed, renewed, .{ .chunk = renewed.chunks[0], .first_line = 1, .last_line = 1 }));
    try std.testing.expectEqualDeep(r.CitationDiagnostic{ .field = .chunk, .rejected = selected.chunks[0].ordinal }, (try r.validateCitation(changed, renewed, .{ .chunk = selected.chunks[0], .first_line = 1, .last_line = 1 })).?);
    var missing = registry;
    missing.chunks = missing.chunks[1..];
    try std.testing.expectError(error.InvalidPrincipleRegistry, r.validate(missing));
}

test "citation membership uses the selected policy rather than all captured chunks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try fixture.registry(a, "Require authenticated requests.\n");
    const registry = try r.build(a, .{ .inventory = base.inventory, .sources = &.{.{ .entry = 1, .bytes = base.sources[0].bytes }} }, .{ .hints = &.{.{ .basename = "core.md", .category = .security }}, .selections = &.{fixture.selection} }, base);
    const selection = try r.select(a, registry, .{ .stage = .spec, .environment = null, .fileKind = null });
    try std.testing.expectEqual(@as(usize, 0), selection.chunks.len);
    const id = registry.chunks[0].id;
    try std.testing.expectEqualDeep(r.CitationDiagnostic{ .field = .chunk, .rejected = id.ordinal }, (try r.validateCitation(registry, selection, .{ .chunk = id, .first_line = 1, .last_line = 1 })).?);
}
