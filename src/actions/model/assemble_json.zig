const std = @import("std");
const runtime = @import("../../domain/json_composition_runtime.zig");
const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "assemble-json",
        .kind = .action,
        .requires = &.{.json_composition},
        .produces = &.{.assembled_json},
        .invalidates = &.{.json_composition},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, state: runtime.State) !runtime.Candidate {
        return state.assemble(allocator);
    }
};
