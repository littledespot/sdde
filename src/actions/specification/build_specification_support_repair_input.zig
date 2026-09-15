const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/specification_support_repair.zig");
const support = @import("../../domain/specification_support.zig");
const authority = @import("../../domain/required_authority.zig");
const p = @import("../../domain/specification_provenance.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-specification-support-repair-input", .kind = .action, .requires = &.{ .required_authority_inputs, .specification_support_review, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .specification_support_repair }, .produces = &.{.model_input_packet}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: authority.Inputs, context: p.Context, candidate: support.Candidate, authorization: repair.Authorization) repair.Error!*@import("../../domain/model_input_packet.zig").Packet {
        return repair.packet(allocator, inputs, context, candidate, authorization);
    }
};
