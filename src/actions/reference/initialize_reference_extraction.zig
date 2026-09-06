const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const iteration = @import("../../domain/reference_model_iteration.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "initialize-reference-extraction", .kind = .action, .requires = &.{.citable_reference_inputs}, .produces = &.{.reference_extraction_progress}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: @import("../../domain/reference_evidence.zig").Inputs) @import("../../domain/reference_extraction.zig").Error!iteration.Progress {
        return iteration.initialize(allocator, inputs);
    }
};
