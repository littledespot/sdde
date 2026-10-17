//! Provider-supplied diagnostic content. Never candidate data or workflow authority.
const std = @import("std");

pub const Block = union(enum) {
    text: struct { text: []const u8, signature: ?[]const u8 = null },
    redacted: struct { base64: []const u8 },

    pub fn clone(self: Block, allocator: std.mem.Allocator) std.mem.Allocator.Error!Block {
        return switch (self) {
            .text => |value| blk: {
                const text = try allocator.dupe(u8, value.text);
                errdefer allocator.free(text);
                break :blk .{ .text = .{ .text = text, .signature = if (value.signature) |signature| try allocator.dupe(u8, signature) else null } };
            },
            .redacted => |value| .{ .redacted = .{ .base64 = try allocator.dupe(u8, value.base64) } },
        };
    }

    pub fn deinit(self: Block, allocator: std.mem.Allocator) void {
        switch (self) {
            .text => |value| {
                allocator.free(value.text);
                if (value.signature) |signature| allocator.free(signature);
            },
            .redacted => |value| allocator.free(value.base64),
        }
    }
};

pub fn clone(allocator: std.mem.Allocator, blocks: []const Block) std.mem.Allocator.Error![]Block {
    const result = try allocator.alloc(Block, blocks.len);
    var initialized: usize = 0;
    errdefer {
        for (result[0..initialized]) |block| block.deinit(allocator);
        allocator.free(result);
    }
    for (blocks, result) |block, *owned| {
        owned.* = try block.clone(allocator);
        initialized += 1;
    }
    return result;
}

pub fn deinit(allocator: std.mem.Allocator, blocks: []const Block) void {
    for (blocks) |block| block.deinit(allocator);
    allocator.free(blocks);
}

/// Move-only diagnostic owner. Copies are borrowed views; only the current
/// owning provider observation destroys it. It confers no workflow authority.
pub const Owned = struct {
    allocator: std.mem.Allocator,
    blocks: []const Block,

    pub fn init(allocator: std.mem.Allocator, blocks: []const Block) std.mem.Allocator.Error!Owned {
        return .{ .allocator = allocator, .blocks = try clone(allocator, blocks) };
    }

    /// Transfer an already-owned decoder allocation without allocating again.
    pub fn take(allocator: std.mem.Allocator, blocks: *[]const Block) Owned {
        const owned: Owned = .{ .allocator = allocator, .blocks = blocks.* };
        blocks.* = &.{};
        return owned;
    }

    pub fn deinit(self: *Owned) void {
        for (self.blocks) |block| block.deinit(self.allocator);
        self.allocator.free(self.blocks);
        self.* = undefined;
    }
};
