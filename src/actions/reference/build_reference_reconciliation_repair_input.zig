const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/reference_reconciliation_repair.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-reference-reconciliation-repair-input", .kind = .action, .requires = &.{ .parsed_reference_reconciliation, .reference_reconciliation_repair, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain }, .produces = &.{.model_input_packet}, .side_effect = .none };
    pub fn execute(_: Action, a: std.mem.Allocator, parsed: @import("../../domain/reference_reconciliation.zig").Parsed, context: @import("../../domain/reference_reconciliation_validation.zig").TextContext, authorization: repair.Authorization) repair.Error!*@import("../../domain/model_input_packet.zig").Packet {
        return repair.packet(a, parsed, context, authorization);
    }
};
