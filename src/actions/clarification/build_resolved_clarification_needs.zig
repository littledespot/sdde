const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-resolved-clarification-needs", .kind = .action, .requires = &.{ .citable_reference_inputs, .accounted_reference_reconciliation }, .produces = &.{.clarification_needs}, .side_effect = .none };
    /// No new need, so a run with no gap still refreshes existing forms, and the conflicts an applied answer dropped, so the
    /// refresh closes any form of one that is still open (ADR 0025).
    pub fn execute(_: Action, a: std.mem.Allocator, sources: @import("../../domain/reference_evidence.zig").Inputs, references: @import("../../domain/reference_reconciliation.zig").Accounted) @import("../../domain/clarification_refresh.zig").Error!@import("../../domain/clarification_refresh.zig").Needs {
        return .{ .feature = sources.corpus.feature_id, .original_sources = try @import("../../domain/clarification_refresh.zig").originalSources(a, sources), .entries = &.{}, .decided = references.records.answer_dropped };
    }
};
