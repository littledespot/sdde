const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const iteration = @import("../../domain/reference_model_iteration.zig");
const extraction = @import("../../domain/reference_extraction.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-reference-extraction-results", .kind = .action, .requires = &.{.reference_extraction_progress}, .produces = &.{.raw_reference_extraction}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, progress: iteration.Progress) extraction.Error!extraction.Raw {
        return iteration.finish(allocator, progress);
    }
};
