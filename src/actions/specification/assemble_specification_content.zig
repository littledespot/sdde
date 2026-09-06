const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const session = @import("../../domain/specification_session.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "assemble-specification-content", .kind = .action, .requires = &.{ .specification_generation_session, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain }, .produces = &.{ .identified_specification_content, .specification_id_ledger }, .side_effect = .none };
    validator: @import("../../domain/typed_text.zig").Validator,
    pub fn execute(self: Action, allocator: std.mem.Allocator, current: session.Session, context: @import("../../domain/specification_provenance.zig").Context) session.Error!@import("../../domain/specification_identity.zig").Assigned {
        return session.assemble(allocator, self.validator, context, current);
    }
};
