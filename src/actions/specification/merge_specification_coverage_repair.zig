const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/specification_coverage_repair.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "merge-specification-coverage-repair", .kind = .action, .requires = &.{ .specification_generation_session, .accounted_reference_reconciliation, .identified_specification_content, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain, .specification_coverage_repair }, .produces = &.{}, .replaces = &.{.specification_generation_session}, .invalidates = &.{ .identified_specification_content, .specification_id_ledger, .specification_coverage, .specification_coverage_repair }, .side_effect = .none };
    validator: @import("../../domain/typed_text.zig").Validator,
    pub fn execute(self: Action, a: std.mem.Allocator, current: @import("../../domain/specification_session.zig").Session, context: @import("../../domain/specification_provenance.zig").Context, candidate: @import("../../domain/specification.zig").IdentifiedContent, authorization: repair.Authorization) repair.Error!@import("../../domain/specification_session.zig").Session {
        return repair.merge(a, self.validator, current, context, candidate, authorization);
    }
};
