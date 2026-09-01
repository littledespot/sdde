const std = @import("std");

pub const max_bytes: usize = 1024 * 1024;

pub const Raw = struct {
    bytes: []u8,

    pub fn deinit(self: *Raw, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
        self.* = undefined;
    }
};
