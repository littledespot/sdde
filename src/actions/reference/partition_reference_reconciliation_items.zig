const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "partition-reference-reconciliation-items", .kind = .action, .requires = &.{.reference_reconciliation_items}, .produces = &.{.reference_reconciliation_layout}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, items: r.Items, group_size: u32) r.Error!r.Layout {
        return @import("../../domain/reference_reconciliation_partition.zig").layout(allocator, items, group_size);
    }
};
