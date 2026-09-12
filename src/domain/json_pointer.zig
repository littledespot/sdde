//! RFC 6901 paths shared by syntax and schema diagnostics.
const std = @import("std");
pub const Segment = union(enum) { property: []const u8, index: usize };
pub fn render(allocator: std.mem.Allocator, segments: []const Segment) std.mem.Allocator.Error![]const u8 {
    var path: std.ArrayList(u8) = .empty;
    errdefer path.deinit(allocator);
    for (segments) |segment| {
        try path.append(allocator, '/');
        switch (segment) {
            .property => |name| for (name) |byte| {
                switch (byte) {
                    '~' => try path.appendSlice(allocator, "~0"),
                    '/' => try path.appendSlice(allocator, "~1"),
                    else => try path.append(allocator, byte),
                }
            },
            .index => |index| {
                var digits: [20]u8 = undefined;
                try path.appendSlice(allocator, std.fmt.bufPrint(&digits, "{d}", .{index}) catch unreachable);
            },
        }
    }
    return path.toOwnedSlice(allocator);
}
