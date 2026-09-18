const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const loss = @import("../../domain/source_omission.zig");
const ex = @import("../../domain/reference_extraction_repair.zig").Omission;
const rec = @import("../../domain/reference_reconciliation_repair.zig").Omission;
const r = @import("../../domain/reference_reconciliation.zig");
const Context = @import("../../domain/reference_reconciliation_validation.zig").TextContext;
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "check-source-omission", .kind = .action, .requires = &.{ .required_authority_inputs, .required_authority_observations, .required_authority_result, .citable_reference_inputs, .specification_support_review }, .produces = &.{}, .replaces = &.{}, .invalidates = &.{}, .side_effect = .none };
    pub fn execute(_: Action, a: std.mem.Allocator, sources: r.evidence.Inputs, support: loss.Support) loss.Error!bool {
        for (support.review.review.entries) |finding| if (finding.value.loss != .unlocalized) {
            _ = try loss.select(a, sources, support);
            return true;
        };
        return false;
    }
};
