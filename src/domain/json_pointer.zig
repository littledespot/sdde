//! RFC 6901 paths shared by syntax and schema diagnostics.
const std = @import("std");
pub const Segment = union(enum) { property: []const u8, index: usize };

/// Object selectors retain decoded property segments. Schema consumers decide
/// whether traversal is permitted; numeric property names remain properties.
pub const Pointer = struct {
    segments: []const []const u8,

    pub fn isPrefixOf(self: Pointer, other: Pointer) bool {
        if (self.segments.len > other.segments.len) return false;
        for (self.segments, other.segments[0..self.segments.len]) |left, right| {
            if (!std.mem.eql(u8, left, right)) return false;
        }
        return true;
    }
};

pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) (error{InvalidJsonPointer} || std.mem.Allocator.Error)!Pointer {
    if (bytes.len == 0) return .{ .segments = &.{} };
    if (bytes[0] != '/') return error.InvalidJsonPointer;
    var segments: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (segments.items) |segment| allocator.free(segment);
        segments.deinit(allocator);
    }
    var iterator = std.mem.splitScalar(u8, bytes[1..], '/');
    while (iterator.next()) |encoded| {
        var decoded: std.ArrayList(u8) = .empty;
        errdefer decoded.deinit(allocator);
        var offset: usize = 0;
        while (offset < encoded.len) : (offset += 1) {
            if (encoded[offset] != '~') {
                try decoded.append(allocator, encoded[offset]);
                continue;
            }
            offset += 1;
            if (offset == encoded.len) return error.InvalidJsonPointer;
            try decoded.append(allocator, switch (encoded[offset]) {
                '0' => '~',
                '1' => '/',
                else => return error.InvalidJsonPointer,
            });
        }
        const owned = try decoded.toOwnedSlice(allocator);
        errdefer allocator.free(owned);
        try segments.append(allocator, owned);
    }
    return .{ .segments = try segments.toOwnedSlice(allocator) };
}

pub fn lookup(value: std.json.Value, path: Pointer) ?std.json.Value {
    var current = value;
    for (path.segments) |segment| {
        current = switch (current) {
            .object => |object| object.get(segment) orelse return null,
            .array => |array| blk: {
                if (segment.len == 0 or (segment.len > 1 and segment[0] == '0')) return null;
                for (segment) |byte| if (!std.ascii.isDigit(byte)) return null;
                const index = std.fmt.parseInt(usize, segment, 10) catch return null;
                if (index >= array.items.len) return null;
                break :blk array.items[index];
            },
            else => return null,
        };
    }
    return current;
}
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
