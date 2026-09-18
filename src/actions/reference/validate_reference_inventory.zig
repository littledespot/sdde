const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const reference = @import("../../domain/reference_ingestion.zig");
const unicode = @import("../../ports/unicode_normalizer.zig");

pub const Action = struct {
    normalizer: unicode.Normalizer,
    case_folder: unicode.CaseFolder,
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-reference-inventory",
        .kind = .action,
        .requires = &.{.raw_reference_inventory},
        .produces = &.{.reference_inventory},
        .side_effect = .none,
    };
    /// Caller arena owns normalized paths and comparison keys.
    pub fn execute(self: Action, allocator: std.mem.Allocator, raw: reference.RawInventory) reference.Error!reference.Inventory {
        const checked = @import("../../domain/source_inventory.zig").validate(allocator, raw.entries, .{ .entries = reference.limits.entries, .depth = reference.limits.depth, .duration_ms = reference.limits.duration_ms }, self.normalizer, self.case_folder) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReferenceInventory;
        const entries = try allocator.alloc(reference.Entry, checked.len);
        for (checked, entries, 0..) |entry, *result, index| result.* = .{ .id = .{ .ordinal = @intCast(index + 1) }, .path = .{ .bytes = entry.path }, .raw_path = entry.raw_path, .observation = entry.observation };
        return .{ .directory = raw.directory, .entries = entries };
    }
};
