const std = @import("std");
const r = @import("../domain/principle_registry.zig");
pub fn registry(a: std.mem.Allocator, prose: ?[]const u8) !r.Registry {
    const count: usize = if (prose != null) 2 else 1;
    const entries = try a.alloc(r.Entry, count);
    if (prose) |bytes| entries[0] = .{ .kind = .semantic_markdown, .descriptor = .{ .path = "core.md", .raw_path = "core.md", .observation = .{ .file = .{ .identity = .{ .filesystem_id = 1, .file_id = 2 }, .size = bytes.len, .modified_ns = 0, .changed_ns = 0 } } } };
    entries[count - 1] = .{ .kind = .mechanical_toolchain_layer_excluded, .descriptor = .{ .path = "toolchain.yaml", .raw_path = "toolchain.yaml", .observation = .{ .file = .{ .identity = .{ .filesystem_id = 1, .file_id = 3 }, .size = 20, .modified_ns = 0, .changed_ns = 0 } } } };
    const captures = try a.alloc(r.Capture, if (prose != null) 1 else 0);
    if (prose) |bytes| captures[0] = .{ .entry = 1, .bytes = bytes };
    return r.build(a, .{ .inventory = .{ .root = .{ .path = "principles", .identity = .{ .filesystem_id = 1, .file_id = 1 } }, .entries = entries, .source_bytes = if (prose) |bytes| bytes.len else 0 }, .sources = captures }, null);
}
