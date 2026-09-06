const std = @import("std");

pub const Snapshot = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    pub fn capture(allocator: std.mem.Allocator, raw: ?[]const u8) std.mem.Allocator.Error!?Snapshot {
        const value = raw orelse return null;
        if (value.len == 0) return null;
        for (value) |byte| if (byte <= 32 or byte >= 127) return null;
        return .{ .allocator = allocator, .bytes = try allocator.dupe(u8, value) };
    }

    pub fn deinit(self: *Snapshot) void {
        std.crypto.secureZero(u8, self.bytes);
        self.allocator.free(self.bytes);
        self.* = undefined;
    }
};

pub const Material = union(enum) {
    unavailable,
    allocation_failed,
    ready: Snapshot,

    pub fn deinit(self: *Material) void {
        if (self.* == .ready) self.ready.deinit();
        self.* = .unavailable;
    }
};
