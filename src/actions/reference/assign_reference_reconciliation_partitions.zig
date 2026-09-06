const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "assign-reference-reconciliation-partitions", .kind = .action, .requires = &.{.reference_reconciliation_layout}, .produces = &.{.reference_reconciliation_plan}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, layout: r.Layout) r.Error!r.Plan {
        const partitions = try allocator.alloc(r.Partition, layout.groups.len);
        for (layout.groups, partitions, 0..) |group, *partition, index| {
            for (group.children) |child| {
                if (child.value >= index) return error.InvalidReferenceReconciliation;
            }
            partition.* = .{ .id = .{ .ordinal = try r.ordinal(index) }, .group = group };
        }
        return .{ .layout = layout, .partitions = partitions };
    }
};
