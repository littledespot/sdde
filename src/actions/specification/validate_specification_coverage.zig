const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const coverage = @import("../../domain/specification_coverage.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-specification-coverage", .kind = .action, .requires = &.{ .specification_generation_session, .accounted_reference_reconciliation, .identified_specification_content, .citable_reference_inputs, .reference_passive_literals }, .produces = &.{.specification_coverage}, .side_effect = .none };
    pub fn execute(_: Action, a: std.mem.Allocator, current: @import("../../domain/specification_session.zig").Session, context: @import("../../domain/specification_provenance.zig").Context, candidate: @import("../../domain/specification.zig").IdentifiedContent) (@import("../../domain/specification_provenance.zig").Error || coverage.Error)!coverage.Result {
        try @import("../../domain/specification_provenance.zig").bind(a, context);
        return coverage.check(a, context.references, (current.units[0] orelse return error.InvalidSpecificationCoverage).response.content.brief, candidate);
    }
};
