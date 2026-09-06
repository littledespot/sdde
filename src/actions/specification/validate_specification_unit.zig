const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const g = @import("../../domain/specification_generation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-specification-unit", .kind = .action, .requires = &.{ .specification_generation_session, .parsed_specification_unit, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain }, .produces = &.{.validated_specification_unit}, .side_effect = .none };
    validator: @import("../../domain/typed_text.zig").Validator,
    pub fn execute(self: Action, allocator: std.mem.Allocator, current: @import("../../domain/specification_session.zig").Session, context: @import("../../domain/specification_provenance.zig").Context, proposed: g.Response) g.Error!g.Checked {
        return g.validate(allocator, self.validator, context, try @import("../../domain/specification_session.zig").unit(current.completed), proposed);
    }
};
