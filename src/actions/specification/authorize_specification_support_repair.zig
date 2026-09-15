const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/specification_support_repair.zig");
const support = @import("../../domain/specification_support.zig");
const authority = @import("../../domain/required_authority.zig");
const p = @import("../../domain/specification_provenance.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "authorize-specification-support-repair", .kind = .action, .requires = &.{ .required_authority_inputs, .specification_support_review, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain }, .produces = &.{.specification_support_repair}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: authority.Inputs, context: p.Context, rejected: @FieldType(support.Collection, "rejected")) repair.Error!repair.Authorization {
        return repair.authorize(allocator, inputs, context, rejected);
    }
};
