const std = @import("std");
const feature = @import("../../domain/feature_directory.zig");
const source = @import("../../ports/feature_directory_inspector.zig");

pub const Action = struct {
    inspector: source.Inspector,
    pub const contract: @import("../../domain/pipeline.zig").NodeContract = .{
        .id = "inspect-feature-directory@1",
        .kind = .action,
        .requires = &.{.relative_feature_directory},
        .produces = &.{.feature_directory},
        .side_effect = .none,
    };

    pub fn execute(self: Action, allocator: std.mem.Allocator, selector: feature.Selector) source.Error!feature.Directory {
        return self.inspector.inspect(allocator, selector);
    }
};
