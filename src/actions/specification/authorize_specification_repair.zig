const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/specification_repair.zig");
const session = @import("../../domain/specification_session.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "authorize-specification-repair", .kind = .action, .requires = &.{ .specification_generation_session, .parsed_specification_unit, .validated_specification_unit, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain }, .produces = &.{.specification_repair_authorization}, .side_effect = .none };
    validator: @import("../../domain/typed_text.zig").Validator,
    pub fn execute(self: Action, allocator: std.mem.Allocator, current: session.Session, context: @import("../../domain/specification_provenance.zig").Context, candidate: repair.Candidate) repair.Error!repair.Authorization {
        return repair.authorize(allocator, self.validator, context, current, candidate);
    }
};
