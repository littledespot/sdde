const std = @import("std");
const toolchain = @import("../../domain/toolchain.zig");
const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-project-toolchain-schema@1", .kind = .action, .requires = &.{.raw_toolchain_documents}, .produces = &.{.schema_valid_project_toolchain}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, document: toolchain.RawDocument) toolchain.Error!toolchain.Project {
        return toolchain.parseProject(allocator, document);
    }
};
