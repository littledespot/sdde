const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const extraction = @import("../../domain/reference_extraction.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "parse-reference-extraction-results",
        .kind = .action,
        .requires = &.{.raw_reference_extraction},
        .produces = &.{.parsed_reference_extraction},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, raw: extraction.Raw) extraction.Error!extraction.Parsed {
        return @import("../../domain/reference_extraction_parser.zig").parse(allocator, raw);
    }
};
