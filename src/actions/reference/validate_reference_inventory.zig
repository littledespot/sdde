const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const reference = @import("../../domain/reference_ingestion.zig");
const paths = @import("../../domain/relative_directory_path.zig");
const unicode = @import("../../ports/unicode_normalizer.zig");

pub const Action = struct {
    normalizer: unicode.Normalizer,
    case_folder: unicode.CaseFolder,
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-reference-inventory@1",
        .kind = .action,
        .requires = &.{.raw_reference_inventory},
        .produces = &.{.reference_inventory},
        .side_effect = .none,
    };
    /// Caller arena owns normalized paths and comparison keys.
    pub fn execute(self: Action, allocator: std.mem.Allocator, raw: reference.RawInventory) reference.Error!reference.Inventory {
        if (raw.entries.len > reference.limits.entries) return error.InvalidReferenceInventory;
        const entries = try allocator.alloc(reference.Entry, raw.entries.len);
        const keys = try allocator.alloc([]const u8, raw.entries.len);
        for (raw.entries, 0..) |item, index| {
            // Filesystem names are not CLI syntax: never reinterpret backslashes or dots.
            paths.validate(item.raw_path) catch return error.InvalidReferenceInventory;
            const normalized = self.normalizer.nfc(allocator, item.raw_path, paths.max_bytes) catch |err| return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.InvalidReferenceInventory,
            };
            paths.validate(normalized) catch return error.InvalidReferenceInventory;
            if (std.mem.count(u8, normalized, "/") >= reference.limits.depth) return error.InvalidReferenceInventory;
            keys[index] = self.case_folder.key(allocator, normalized, paths.max_bytes * 4) catch |err| return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.InvalidReferenceInventory,
            };
            for (keys[0..index]) |key| if (std.mem.eql(u8, key, keys[index])) return error.InvalidReferenceInventory;
            for (raw.entries[0..index]) |other| {
                const left = physical(item.observation);
                const right = physical(other.observation);
                if (left != null and right != null and left.?.eql(right.?)) return error.InvalidReferenceInventory;
            }
            entries[index] = .{ .id = .{ .ordinal = 0 }, .path = .{ .bytes = normalized }, .raw_path = item.raw_path, .observation = item.observation };
        }
        // UTF-8 byte ordering equals Unicode scalar ordering for validated strings.
        std.mem.sort(reference.Entry, entries, {}, less);
        for (entries, 0..) |*entry, index| {
            entry.id = .{ .ordinal = @intCast(index + 1) };
            if (std.mem.lastIndexOfScalar(u8, entry.raw_path, '/')) |slash| {
                const parent = for (entries[0..index]) |candidate| {
                    if (std.mem.eql(u8, candidate.raw_path, entry.raw_path[0..slash])) break candidate;
                } else return error.InvalidReferenceInventory;
                if (parent.observation != .directory) return error.InvalidReferenceInventory;
            }
        }
        return .{ .directory = raw.directory, .entries = entries };
    }
};
fn physical(observation: reference.Observation) ?@import("../../domain/filesystem_identity.zig").FileIdentity {
    return switch (observation) {
        .directory => |id| id,
        .file => |file| file.identity,
        .symlink, .special, .unreadable => null,
    };
}
fn less(_: void, a: reference.Entry, b: reference.Entry) bool {
    return std.mem.order(u8, a.path.bytes, b.path.bytes) == .lt;
}
