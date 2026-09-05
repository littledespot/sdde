//! Reference identity types shared by evidence and model-request owners.
const std = @import("std");

pub const StateId = struct {
    bytes: []const u8,

    pub fn eql(self: StateId, other: StateId) bool {
        return std.mem.eql(u8, self.bytes, other.bytes);
    }
};
pub const SourceId = struct { ordinal: u32 };
pub const BlockId = struct { ordinal: u32 };
pub const ChunkId = struct {
    bytes: []const u8,

    pub fn eql(self: ChunkId, other: ChunkId) bool {
        return std.mem.eql(u8, self.bytes, other.bytes);
    }
};

/// A fresh state namespace, not a content fingerprint or a persisted counter.
pub fn stateId(allocator: std.mem.Allocator, nonce: [16]u8) std.mem.Allocator.Error!StateId {
    return .{ .bytes = try std.fmt.allocPrint(allocator, "reference-{s}", .{std.fmt.bytesToHex(nonce, .lower)}) };
}

pub fn chunkId(allocator: std.mem.Allocator, ordinal: u32) std.mem.Allocator.Error!ChunkId {
    var buffer: [32]u8 = undefined;
    const id = formatChunkId(&buffer, ordinal);
    return .{ .bytes = try allocator.dupe(u8, id.bytes) };
}

pub fn formatChunkId(buffer: *[32]u8, ordinal: u32) ChunkId {
    std.debug.assert(ordinal != 0);
    return .{ .bytes = std.fmt.bufPrint(buffer, "chunk-{d}", .{ordinal}) catch unreachable };
}
