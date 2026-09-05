const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const reference = @import("../../domain/reference_ingestion.zig");
const source = @import("../../ports/reference_corpus_source.zig");
pub const Action = struct {
    source: source.Enumerator,
    pub const contract: pipeline.NodeContract = .{
        .id = "inventory-reference-sources@1",
        .kind = .action,
        .requires = &.{.reference_directory},
        .produces = &.{.raw_reference_inventory},
        .side_effect = .filesystem_read,
    };
    pub fn execute(self: Action, allocator: std.mem.Allocator, directory: @import("../../domain/reference_selector.zig").Directory) source.Error!reference.RawInventory {
        return self.source.enumerate(allocator, directory);
    }
};
