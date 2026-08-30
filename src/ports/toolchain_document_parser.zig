const std = @import("std");
const toolchain = @import("../domain/toolchain.zig");
pub const Error = error{InvalidToolchainDocument};
pub const Parser = struct {
    context: *anyopaque,
    parse_fn: *const fn (*anyopaque, std.mem.Allocator, []const toolchain.Capture) Error![]const toolchain.RawDocument,
    pub fn parse(self: Parser, allocator: std.mem.Allocator, captures: []const toolchain.Capture) Error![]const toolchain.RawDocument {
        return self.parse_fn(self.context, allocator, captures);
    }
};
