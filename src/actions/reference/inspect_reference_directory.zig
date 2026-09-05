const std = @import("std");
const reference = @import("../../domain/reference_selector.zig");
const source = @import("../../ports/reference_directory_inspector.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Action = struct {
    inspector: source.Inspector,
    pub const contract: pipeline.NodeContract = .{
        .id = "inspect-reference-directory@1",
        .kind = .action,
        .requires = &.{.relative_reference_selector},
        .produces = &.{.reference_directory},
        .side_effect = .filesystem_read,
    };
    pub fn execute(self: Action, allocator: std.mem.Allocator, selector: reference.RelativeSelector) source.Error!reference.Directory {
        return self.inspector.inspect(allocator, selector);
    }
};
