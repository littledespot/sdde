const support = @import("../../domain/specification_support.zig");
const repair = @import("../../domain/specification_support_repair.zig");
const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");

const authority = @import("../../domain/required_authority.zig");
const p = @import("../../domain/specification_provenance.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "merge-specification-support-repair", .kind = .action, .requires = &.{ .required_authority_inputs, .specification_support_review, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .specification_support_repair }, .produces = &.{}, .replaces = &.{.specification_support_review}, .invalidates = &.{.specification_support_repair}, .side_effect = .none };
    pub fn execute(_: Action, comptime purpose: support.Purpose, allocator: std.mem.Allocator, inputs: authority.Inputs, context: p.Context, candidate: support.Contract(purpose).Candidate, state: repair.Contract(purpose).State) repair.Contract(purpose).Error!support.Contract(purpose).Collection {
        return repair.Contract(purpose).merge(allocator, inputs, context, candidate, state.authorization, if (state.response) |response| response.value else null, if (state.response) |response| response.origin else null);
    }
};
