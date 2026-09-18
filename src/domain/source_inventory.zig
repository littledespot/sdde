//! Shared physical source inventory; owning domains classify and account its entries.
const std = @import("std");
const identity = @import("filesystem_identity.zig");
const paths = @import("relative_directory_path.zig");
const unicode = @import("../ports/unicode_normalizer.zig");
pub const Observation = union(enum) { directory: identity.FileIdentity, file: identity.FileObservation, symlink: void, special: void, unreadable: void };
pub const Descriptor = struct { raw_path: []const u8, observation: Observation };
pub const Entry = struct { path: []const u8, raw_path: []const u8, observation: Observation };
pub const Limits = struct { entries: usize, depth: usize, duration_ms: i64 };
pub const Error = std.mem.Allocator.Error || error{InvalidSourceInventory};

pub fn validate(a: std.mem.Allocator, raw: []const Descriptor, limits: Limits, normalizer: unicode.Normalizer, folder: unicode.CaseFolder) Error![]const Entry {
    if (raw.len > limits.entries) return error.InvalidSourceInventory;
    const entries = try a.alloc(Entry, raw.len);
    const keys = try a.alloc([]const u8, raw.len);
    for (raw, 0..) |item, index| {
        paths.validate(item.raw_path) catch return error.InvalidSourceInventory;
        const normalized = normalizer.nfc(a, item.raw_path, paths.max_bytes) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSourceInventory;
        paths.validate(normalized) catch return error.InvalidSourceInventory;
        if (std.mem.count(u8, normalized, "/") >= limits.depth) return error.InvalidSourceInventory;
        keys[index] = folder.key(a, normalized, paths.max_bytes * 4) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSourceInventory;
        for (keys[0..index]) |key| if (std.mem.eql(u8, key, keys[index])) return error.InvalidSourceInventory;
        for (raw[0..index]) |other| {
            const left = physical(item.observation);
            const right = physical(other.observation);
            if (left != null and right != null and left.?.eql(right.?)) return error.InvalidSourceInventory;
        }
        entries[index] = .{ .path = normalized, .raw_path = item.raw_path, .observation = item.observation };
    }
    std.mem.sort(Entry, entries, {}, struct {
        fn less(_: void, left: Entry, right: Entry) bool {
            return std.mem.order(u8, left.path, right.path) == .lt;
        }
    }.less);
    for (entries, 0..) |entry, index| if (std.mem.lastIndexOfScalar(u8, entry.raw_path, '/')) |slash| {
        const parent = for (entries[0..index]) |candidate| {
            if (std.mem.eql(u8, candidate.raw_path, entry.raw_path[0..slash])) break candidate;
        } else return error.InvalidSourceInventory;
        if (parent.observation != .directory) return error.InvalidSourceInventory;
    };
    return entries;
}
fn physical(observation: Observation) ?identity.FileIdentity {
    return switch (observation) {
        .directory => |id| id,
        .file => |file| file.identity,
        else => null,
    };
}
