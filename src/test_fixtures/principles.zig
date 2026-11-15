const std = @import("std");
const r = @import("../domain/principle_registry.zig");
pub fn registry(a: std.mem.Allocator, prose: ?[]const u8) !r.Registry {
    return registryOf(a, if (prose) |bytes| &.{bytes} else &.{});
}
/// A registry of one Markdown file per text, named in order, beside the toolchain layer.
pub fn registryOf(a: std.mem.Allocator, texts: []const []const u8) !r.Registry {
    const entries = try a.alloc(r.Entry, texts.len + 1);
    const captures = try a.alloc(r.Capture, texts.len);
    var total: usize = 0;
    for (texts, entries[0..texts.len], captures, 0..) |bytes, *entry, *capture, index| {
        const name = if (index == 0) "core.md" else try std.fmt.allocPrint(a, "p{d}.md", .{index});
        entry.* = .{ .kind = .semantic_markdown, .descriptor = .{ .path = name, .raw_path = name, .observation = .{ .file = .{ .identity = .{ .filesystem_id = 1, .file_id = 2 + index }, .size = bytes.len, .modified_ns = 0, .changed_ns = 0 } } } };
        capture.* = .{ .entry = @intCast(index + 1), .bytes = bytes };
        total += bytes.len;
    }
    entries[texts.len] = .{ .kind = .mechanical_toolchain_layer_excluded, .descriptor = .{ .path = "toolchain.yaml", .raw_path = "toolchain.yaml", .observation = .{ .file = .{ .identity = .{ .filesystem_id = 1, .file_id = @max(3, 2 + texts.len) }, .size = 20, .modified_ns = 0, .changed_ns = 0 } } } };
    return r.build(a, .{ .inventory = .{ .root = .{ .path = "principles", .identity = .{ .filesystem_id = 1, .file_id = 1 } }, .entries = entries, .source_bytes = total }, .sources = captures }, null);
}
