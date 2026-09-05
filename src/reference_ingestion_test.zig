const std = @import("std");
const reference = @import("domain/reference_ingestion.zig");
const inventory_action = @import("actions/reference/validate_reference_inventory.zig");
const decode_action = @import("actions/reference/decode_reference_markdown.zig");
const account_action = @import("actions/reference/validate_reference_accounting.zig");
const markdown = @import("adapters/parsers/markdown_reference.zig");
const unicode = @import("unicode_normalization");
const selected: @import("domain/reference_selector.zig").Directory = .{
    .selector = .{ .bytes = "hello" },
    .project_relative_path = "reference-input/hello",
    .root_identity = .{ .filesystem_id = 1, .file_id = 1 },
    .directory_identity = .{ .filesystem_id = 1, .file_id = 2 },
};
const validator: inventory_action.Action = .{
    .normalizer = .{ .normalize_fn = unicode.nfc },
    .case_folder = .{ .fold_fn = unicode.caseFold },
};
fn file(path: []const u8, id: u128, size: u64) reference.Descriptor {
    return .{ .raw_path = path, .observation = .{ .file = .{
        .identity = .{ .filesystem_id = 1, .file_id = id },
        .size = size,
        .modified_ns = 1,
        .changed_ns = 1,
    } } };
}
fn captured(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) !reference.CapturedCorpus {
    const inventory = try validator.execute(allocator, .{ .directory = selected, .entries = &.{file(path, 3, bytes.len)} });
    const entries = try allocator.alloc(reference.CapturedEntry, 1);
    entries[0] = .{ .entry = inventory.entries[0], .source = .{ .bytes = bytes }, .debit = .{ .reserved = bytes.len, .outcome = .{ .committed = bytes.len } } };
    return .{ .inventory = inventory, .entries = entries, .source_bytes = bytes.len, .budget_revision = 1 };
}
fn read(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) !reference.Inputs {
    var adapter: markdown.Adapter = .{ .io = std.testing.io };
    const decoded = try (decode_action.Action{ .decoder = adapter.decoderPort() }).execute(allocator, try captured(allocator, path, bytes));
    return (account_action.Action{}).execute(allocator, decoded);
}

test "reference inventory normalizes sorts and assigns run-local source IDs without changing names" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const raw = [_]reference.Descriptor{ file("z.md", 3, 0), file("Cafe\u{301}.md", 4, 0), file(".hidden.md", 5, 0) };
    const result = try validator.execute(arena.allocator(), .{ .directory = selected, .entries = &raw });
    try std.testing.expectEqualStrings(".hidden.md", result.entries[0].path.bytes);
    try std.testing.expectEqualStrings("Café.md", result.entries[1].path.bytes);
    try std.testing.expectEqualStrings("Cafe\u{301}.md", result.entries[1].raw_path);
    for (result.entries, 0..) |entry, index| try std.testing.expectEqual(index + 1, entry.id.ordinal);
}

test "reference inventory rejects Unicode case normalization physical aliases and unsafe paths" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    for ([_][2][]const u8{ .{ "A.md", "a.md" }, .{ "Café.md", "Cafe\u{301}.md" }, .{ "Straße.md", "STRASSE.md" }, .{ "Σ.md", "σ.md" } }) |pair| {
        try std.testing.expectError(error.InvalidReferenceInventory, validator.execute(arena.allocator(), .{ .directory = selected, .entries = &.{ file(pair[0], 3, 0), file(pair[1], 4, 0) } }));
    }
    for ([_][]const u8{ "../escape.md", "/absolute.md", "a\\b.md", "missing/child.md", "bad\x00.md", "%252e%252e.md", "\xff.md" }) |path| {
        try std.testing.expectError(error.InvalidReferenceInventory, validator.execute(arena.allocator(), .{ .directory = selected, .entries = &.{file(path, 3, 0)} }));
    }
    try std.testing.expectError(error.InvalidReferenceInventory, validator.execute(arena.allocator(), .{ .directory = selected, .entries = &.{ file("a.md", 3, 0), file("b.md", 3, 0) } }));
}

test "Hello World reference preserves exact content and source locations" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "test/evaluation/wf-001-hello-world/reference/stories.md", arena.allocator(), .limited(reference.limits.source_file_bytes));
    const inputs = try read(arena.allocator(), "stories.md", bytes);
    try std.testing.expectEqual(@as(usize, 1), inputs.documents.len);
    const document = inputs.documents[0];
    try std.testing.expectEqualSlices(u8, bytes, document.bytes);
    try std.testing.expectEqual(@as(usize, 0), document.blocks[0].span.start.byte);
    try std.testing.expectEqual(bytes.len, document.blocks[document.blocks.len - 1].span.end.byte);
    try std.testing.expectEqual(reference.ReaderId.markdown_source_v1, document.reader);
    try std.testing.expectEqualStrings("stories.md", document.path.bytes);
    try std.testing.expectEqual(bytes.len, inputs.source_bytes);
    try std.testing.expectEqual(bytes.len, inputs.decoded_bytes);
}

test "Markdown reader retains BOM CRLF Unicode whitespace links and code without executing or rewriting" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const bytes = "\xef\xbb\xbf# Café\r\n\r\n[link](https://invalid.example)\r\n<script>ignored()</script>\r\n\t- `a/b.ts`\r";
    const result = try read(arena.allocator(), "notes.MD", bytes);
    try std.testing.expectEqualSlices(u8, bytes, result.documents[0].bytes);
    const end = result.documents[0].blocks[0].span.end;
    try std.testing.expectEqual(@as(u32, 6), end.line);
    try std.testing.expectEqual(@as(u32, 1), end.column);
    const whitespace = try read(arena.allocator(), "blank.markdown", " \t\n");
    try std.testing.expect(whitespace.documents[0].blocks.len > 0);
    const empty = try read(arena.allocator(), "empty.md", "");
    try std.testing.expectEqual(@as(usize, 0), empty.documents[0].blocks.len);
}

test "reader chunks are gap-free and never split a UTF-8 scalar or CRLF" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var body: std.Io.Writer.Allocating = .init(allocator);
    for (0..9000) |_| try body.writer.writeAll("日");
    try body.writer.writeAll("\r\n");
    for (0..130) |_| try body.writer.writeAll("line\n");
    const bytes = body.written();
    const inputs = try read(allocator, "unrelated.md", bytes);
    try std.testing.expect(inputs.documents[0].blocks.len > 2);
    var offset: usize = 0;
    for (inputs.documents[0].blocks) |block| {
        try std.testing.expectEqual(offset, block.span.start.byte);
        const content = bytes[block.span.start.byte..block.span.end.byte];
        try std.testing.expect(std.unicode.utf8ValidateSlice(content));
        try std.testing.expect(content.len <= reference.limits.block_bytes);
        offset = block.span.end.byte;
    }
    try std.testing.expectEqual(bytes.len, offset);
}

test "unsupported and malformed content is retained as explicit failure and cannot validate" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var adapter: markdown.Adapter = .{ .io = std.testing.io };
    for ([_]struct { path: []const u8, bytes: []const u8, failure: reference.Failure }{
        .{ .path = "data.json", .bytes = "{}", .failure = .unsupported_media },
        .{ .path = "disguised.md", .bytes = "%PDF-1.0", .failure = .unsupported_media },
        .{ .path = "invalid.md", .bytes = "\xff", .failure = .malformed_text },
        .{ .path = "control.md", .bytes = "a\x00b", .failure = .malformed_text },
    }) |case| {
        const result = try (decode_action.Action{ .decoder = adapter.decoderPort() }).execute(arena.allocator(), try captured(arena.allocator(), case.path, case.bytes));
        try std.testing.expectEqual(case.failure, result.entries[0].result.blocked);
        try std.testing.expect(result.entries[0].debit.?.outcome == .released);
        try std.testing.expectError(error.InvalidReferenceAccounting, (account_action.Action{}).execute(arena.allocator(), result));
    }
}

test "accounting rejects missing duplicate forged and incomplete decoder evidence" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var adapter: markdown.Adapter = .{ .io = std.testing.io };
    const valid = try (decode_action.Action{ .decoder = adapter.decoderPort() }).execute(arena.allocator(), try captured(arena.allocator(), "source.md", "# Original\n"));
    var bad = valid;
    bad.entries = &.{};
    try std.testing.expectError(error.InvalidReferenceAccounting, (account_action.Action{}).execute(arena.allocator(), bad));
    bad = valid;
    bad.entries = &.{ valid.entries[0], valid.entries[0] };
    try std.testing.expectError(error.InvalidReferenceAccounting, (account_action.Action{}).execute(arena.allocator(), bad));
    bad = valid;
    bad.decoded_bytes += 1;
    try std.testing.expectError(error.InvalidReferenceAccounting, (account_action.Action{}).execute(arena.allocator(), bad));
    var entry = valid.entries[0];
    var block = entry.result.decoded.blocks[0];
    block.span.end.byte -= 1;
    entry.result.decoded.blocks = &.{block};
    bad = valid;
    bad.entries = &.{entry};
    try std.testing.expectError(error.InvalidReferenceAccounting, (account_action.Action{}).execute(arena.allocator(), bad));
    block = valid.entries[0].result.decoded.blocks[0];
    block.span.end.line += 1;
    entry.result.decoded.blocks = &.{block};
    bad.entries = &.{entry};
    try std.testing.expectError(error.InvalidReferenceAccounting, (account_action.Action{}).execute(arena.allocator(), bad));
}

test "reader enforces source and decoded byte ceilings before allocation" {
    var adapter: markdown.Adapter = .{ .io = std.testing.io };
    try std.testing.expectError(error.DecodeLimitExceeded, adapter.decoderPort().decode(std.testing.allocator, .{ .bytes = "a.md" }, "abc", 2));
}

test "reference input preparation cleans up partial allocations" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
fn allocationCase(backing: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(backing);
    defer arena.deinit();
    _ = try read(arena.allocator(), "Café.md", "# source\r\n日本語\n");
}
