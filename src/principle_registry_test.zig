const std = @import("std");
const r = @import("domain/principle_registry.zig");
const fixture = @import("test_fixtures/principles.zig");
const unicode = @import("unicode_normalization");
const normalizer: @import("ports/unicode_normalizer.zig").Normalizer = .{ .normalize_fn = unicode.nfc };
const folder: @import("ports/unicode_normalizer.zig").CaseFolder = .{ .fold_fn = unicode.caseFold };
fn file(name: []const u8, id: u128, size: u64) @import("domain/source_inventory.zig").Descriptor {
    return .{ .raw_path = name, .observation = .{ .file = .{ .identity = .{ .filesystem_id = 1, .file_id = id }, .size = size, .modified_ns = 0, .changed_ns = 0 } } };
}
test "shared inventory preserves Unicode allocation failures" {
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
test "principle chunks cover every captured byte and a changed source renews its identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const prose = "# 任意 policy\r\nKeep precise evidence.\n" ** 1500;
    const registry = try fixture.registry(a, prose);
    try std.testing.expect(registry.chunks.len > 1);
    var bytes: std.ArrayList(u8) = .empty;
    for (registry.chunks) |chunk| try bytes.appendSlice(a, registry.sources[0].bytes[chunk.span.start.byte..chunk.span.end.byte]);
    try std.testing.expectEqualStrings(prose, bytes.items);
    // Mid-line splits are covered: a chunk can start after the first column.
    try std.testing.expect(registry.chunks[1].span.start.column > 1);
    const captures = [_]r.Capture{.{ .entry = 1, .bytes = prose }};
    const same = try r.build(a, .{ .inventory = registry.inventory, .sources = &captures }, registry);
    try std.testing.expectEqualDeep(registry.id, same.id);
    const changed_text = try a.dupe(u8, prose);
    changed_text[0] = '!';
    const changed = try r.build(a, .{ .inventory = registry.inventory, .sources = &.{.{ .entry = 1, .bytes = changed_text }} }, registry);
    try std.testing.expectEqual(registry.id.revision + 1, changed.id.revision);
    try std.testing.expect(changed.sources[0].id.ordinal >= registry.next_source);
    try std.testing.expect(changed.chunks[0].id.ordinal >= registry.next_chunk);
    var missing = registry;
    missing.chunks = missing.chunks[1..];
    try std.testing.expectError(error.InvalidPrincipleRegistry, r.validate(missing));
}
