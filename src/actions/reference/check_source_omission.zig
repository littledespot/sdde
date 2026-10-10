const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const loss = @import("../../domain/source_omission.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "check-source-omission", .kind = .action, .requires = &.{ .required_authority_inputs, .required_authority_observations, .required_authority_result, .citable_reference_inputs, .specification_support_review }, .produces = &.{}, .replaces = &.{}, .invalidates = &.{}, .side_effect = .none };
    pub fn execute(_: Action, a: std.mem.Allocator, sources: r.evidence.Inputs, support: loss.Support) loss.Error!bool {
        for (support.review.review.entries) |finding| if (loss.isUpstream(finding.value.loss)) {
            _ = try loss.select(a, sources, support);
            return true;
        };
        return false;
    }
};
