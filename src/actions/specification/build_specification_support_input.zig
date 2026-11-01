const support = @import("../../domain/specification_support.zig");
const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-specification-support-input", .kind = .action, .requires = &.{ .required_authority_inputs, .specification_support_review, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .packet_guidance }, .produces = &.{.model_input_packet}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, inputs: @import("../../domain/required_authority.zig").Inputs, context: @import("../../domain/specification_provenance.zig").Context, guidance: *const @import("../../domain/packet_guidance.zig").Guidance, selected: @import("../../domain/required_authority.zig").Id) support.Source.Error!*@import("../../domain/model_input_packet.zig").Packet {
        return support.Source.packetFor(allocator, inputs, context, guidance, .{ .finding = selected });
    }
};
