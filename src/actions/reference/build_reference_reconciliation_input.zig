const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-reference-reconciliation-input", .kind = .action, .requires = &.{.reference_reconciliation_progress}, .produces = &.{.reference_reconciliation_input}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, progress: r.Progress) r.Error!r.Input {
        if (progress.summary_count >= progress.plan.partitions.len) return error.InvalidReferenceReconciliation;
        const partition = progress.plan.partitions[progress.summary_count];
        const items = try allocator.alloc(r.Item, partition.group.claim_ids.len);
        for (items, partition.group.claim_ids) |*value, id| value.* = try r.item(progress.plan.layout.items, id);
        const summaries = try allocator.alloc(r.Summary, partition.group.children.len);
        const summary_ids = try allocator.alloc(r.SummaryId, summaries.len);
        var history = progress.latest;
        var pending = summaries.len;
        while (pending != 0) {
            const node = history orelse return error.InvalidReferenceReconciliation;
            const child = partition.group.children[pending - 1];
            if (child.value >= progress.summary_count) return error.InvalidReferenceReconciliation;
            const id = progress.plan.partitions[child.value].id;
            if (node.value.partition_id.ordinal == id.ordinal) {
                summaries[pending - 1] = node.value;
                summary_ids[pending - 1] = node.value.id;
                pending -= 1;
            } else if (node.value.partition_id.ordinal < id.ordinal) return error.InvalidReferenceReconciliation;
            history = node.previous;
        }
        return .{ .progress = progress, .partition = partition, .items = items, .summaries = summaries, .member_summary_ids = summary_ids, .purpose = if (progress.summary_count + 1 == progress.plan.partitions.len) .global else .summary };
    }
};
