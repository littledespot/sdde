const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/specification_coverage_repair.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "authorize-specification-coverage-repair", .kind = .action, .requires = &.{ .specification_generation_session, .accounted_reference_reconciliation, .identified_specification_content, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain, .specification_coverage }, .produces = &.{.specification_coverage_repair}, .side_effect = .none };
    pub fn execute(_: Action, a: std.mem.Allocator, current: @import("../../domain/specification_session.zig").Session, context: @import("../../domain/specification_provenance.zig").Context, candidate: @import("../../domain/specification.zig").IdentifiedContent, rejection: @import("../../domain/specification_coverage.zig").Rejection) repair.Error!repair.Decision {
        return repair.authorize(a, current, context, candidate, rejection);
    }
};
