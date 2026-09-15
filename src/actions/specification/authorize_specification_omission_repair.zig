const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/specification_coverage_repair.zig");
const sessions = @import("../../domain/specification_session.zig");
const p = @import("../../domain/specification_provenance.zig");
const spec = @import("../../domain/specification.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "authorize-specification-omission-repair", .kind = .action, .requires = &.{ .specification_generation_session, .identified_specification_content, .required_authority_inputs, .required_authority_observations, .required_authority_result, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain }, .produces = &.{.specification_omission_repair}, .side_effect = .none };
    validator: @import("../../domain/typed_text.zig").Validator,
    pub fn execute(self: Action, a: std.mem.Allocator, current: sessions.Session, context: p.Context, candidate: spec.IdentifiedContent, support: repair.Support) repair.Error!repair.Authorization {
        return repair.authorizeOmission(a, self.validator, current, context, candidate, support);
    }
};
