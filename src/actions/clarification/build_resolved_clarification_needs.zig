const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-resolved-clarification-needs", .kind = .action, .requires = &.{.citable_reference_inputs}, .produces = &.{.clarification_needs}, .side_effect = .none };
    pub fn execute(_: Action, a: std.mem.Allocator, sources: @import("../../domain/reference_evidence.zig").Inputs) @import("../../domain/clarification_refresh.zig").Error!@import("../../domain/clarification_refresh.zig").Needs {
        return .{ .feature = sources.corpus.feature_id, .original_sources = try @import("../../domain/clarification_refresh.zig").originalSources(a, sources), .entries = &.{} };
    }
};
