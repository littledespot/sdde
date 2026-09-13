const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const coverage = @import("../../domain/specification_coverage.zig");
const repair = @import("../../domain/specification_coverage_repair.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-specification-coverage", .kind = .action, .requires = &.{ .specification_generation_session, .accounted_reference_reconciliation, .identified_specification_content, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain }, .produces = &.{.specification_coverage}, .side_effect = .none };
    validator: @import("../../domain/typed_text.zig").Validator,
    pub fn execute(self: Action, a: std.mem.Allocator, current: @import("../../domain/specification_session.zig").Session, context: @import("../../domain/specification_provenance.zig").Context, candidate: @import("../../domain/specification.zig").IdentifiedContent) (repair.Error || coverage.Error)!coverage.Result {
        try @import("../../domain/specification_provenance.zig").bind(a, self.validator, context);
        const facts = try repair.stamp(a, current, context, candidate);
        var result = try coverage.check(a, context.references, (current.units[0] orelse return error.InvalidSpecificationCoverage).response.content.brief, candidate);
        if (result == .invalid) {
            result.invalid.revision = current.revision;
            result.invalid.dependencies = facts;
        }
        return result;
    }
};
