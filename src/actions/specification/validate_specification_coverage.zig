const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const coverage = @import("../../domain/specification_coverage.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-specification-coverage", .kind = .action, .requires = &.{ .specification_generation_session, .accounted_reference_reconciliation, .identified_specification_content }, .produces = &.{.specification_coverage}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, references: @import("../../domain/reference_reconciliation.zig").Accounted, brief: @import("../../domain/specification_generation.zig").Brief, candidate: @import("../../domain/specification.zig").IdentifiedContent) coverage.Error!coverage.Coverage {
        return coverage.validate(allocator, references, brief, candidate);
    }
};
