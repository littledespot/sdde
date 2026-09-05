const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const reference = @import("../../domain/reference_ingestion.zig");
const source = @import("../../ports/reference_corpus_source.zig");
pub const Action = struct {
    source: source.Capturer,
    pub const contract: pipeline.NodeContract = .{
        .id = "capture-reference-sources@1",
        .kind = .action,
        .requires = &.{.reference_inventory},
        .produces = &.{.captured_reference_corpus},
        .side_effect = .filesystem_read,
    };
    pub fn execute(self: Action, allocator: std.mem.Allocator, inventory: reference.Inventory) source.Error!reference.CapturedCorpus {
        return self.source.capture(allocator, inventory);
    }
};
