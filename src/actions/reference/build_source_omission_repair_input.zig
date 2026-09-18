const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const loss = @import("../../domain/source_omission.zig");
const ex = @import("../../domain/reference_extraction_repair.zig").Omission;
const rec = @import("../../domain/reference_reconciliation_repair.zig").Omission;
const r = @import("../../domain/reference_reconciliation.zig");
const Context = @import("../../domain/reference_reconciliation_validation.zig").TextContext;
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-source-omission-repair-input", .kind = .action, .requires = &.{ .citable_reference_inputs, .structured_token_candidates, .text_validated_reference_extraction, .parsed_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .required_authority_inputs, .required_authority_observations, .required_authority_result, .specification_support_review, .source_omission_repair }, .produces = &.{.model_input_packet}, .replaces = &.{}, .invalidates = &.{}, .side_effect = .none };
    pub fn execute(_: Action, a: std.mem.Allocator, extraction: ex.Facts, parsed: r.Parsed, ctx: Context, repair: loss.Repair) (ex.Error || rec.Error)!*@import("../../domain/model_input_packet.zig").Packet {
        return switch (repair.authorization) {
            .extraction => |auth| ex.packet(a, extraction, ctx.registry, auth),
            .reconciliation => |auth| rec.packet(a, parsed, ctx, extraction.support, auth),
        };
    }
};
