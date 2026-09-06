const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "assign-reference-reconciliation-partitions", .kind = .action, .requires = &.{.reference_reconciliation_layout}, .produces = &.{.reference_reconciliation_plan}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, layout: r.Layout) r.Error!r.Plan {
        const partitions = try allocator.alloc(r.Partition, layout.groups.len);
        for (layout.groups, partitions, 0..) |group, *partition, index| {
            const members = try allocator.alloc(r.SummaryId, group.children.len);
            for (group.children, members) |child, *id| {
                if (child.value >= index) return error.InvalidReferenceReconciliation;
                id.* = .{ .ordinal = try r.ordinal(child.value) };
            }
            partition.* = .{ .id = .{ .ordinal = try r.ordinal(index) }, .group = group, .member_summary_ids = members };
        }
        return .{ .layout = layout, .partitions = partitions };
    }
};
