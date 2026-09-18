//! Bounded no-follow enumeration shared by source readers. No content classification.
const std = @import("std");
const inventory = @import("../../domain/source_inventory.zig");
const paths = @import("../../domain/relative_directory_path.zig");
const directories = @import("directory_access.zig");
const files = @import("file_access.zig");
pub const Error = std.mem.Allocator.Error || error{ SourceUnavailable, SourceLimitExceeded };
pub fn scan(io: std.Io, a: std.mem.Allocator, root: std.Io.Dir, limits: inventory.Limits) Error![]const inventory.Descriptor {
    var entries: std.ArrayList(inventory.Descriptor) = .empty;
    try walk(io, a, root, "", 1, .now(io, .boot), limits, &entries);
    return entries.toOwnedSlice(a);
}
fn walk(io: std.Io, a: std.mem.Allocator, parent: std.Io.Dir, prefix: []const u8, depth: usize, started: std.Io.Clock.Timestamp, limits: inventory.Limits, entries: *std.ArrayList(inventory.Descriptor)) Error!void {
    var iterator = parent.iterate();
    while (iterator.next(io) catch return error.SourceUnavailable) |entry| {
        if (started.durationTo(.now(io, .boot)).raw.toMilliseconds() > limits.duration_ms or entries.items.len >= limits.entries or depth > limits.depth) return error.SourceLimitExceeded;
        const path = try std.mem.concat(a, u8, &.{ prefix, entry.name });
        paths.validate(path) catch return error.SourceUnavailable;
        const index = entries.items.len;
        try entries.append(a, .{ .raw_path = path, .observation = .{ .unreadable = {} } });
        switch (entry.kind) {
            .directory => {
                const child = directories.open(io, parent, entry.name) catch continue;
                defer child.close(io);
                const id = directories.inspectReadable(io, child) catch continue;
                entries.items[index].observation = .{ .directory = id };
                try walk(io, a, child, try std.mem.concat(a, u8, &.{ path, "/" }), depth + 1, started, limits, entries);
            },
            .file => entries.items[index].observation = .{ .file = files.observe(io, parent, entry.name) catch continue },
            .sym_link => entries.items[index].observation = .{ .symlink = {} },
            else => entries.items[index].observation = .{ .special = {} },
        }
    }
}
