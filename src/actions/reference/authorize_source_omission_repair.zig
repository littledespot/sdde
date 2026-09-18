const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const loss = @import("../../domain/source_omission.zig");
const ex = @import("../../domain/reference_extraction_repair.zig").Omission;
const rec = @import("../../domain/reference_reconciliation_repair.zig").Omission;
const r = @import("../../domain/reference_reconciliation.zig");
const Context = @import("../../domain/reference_reconciliation_validation.zig").TextContext;
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "authorize-source-omission-repair", .kind = .action, .requires = &.{ .citable_reference_inputs, .structured_token_candidates, .text_validated_reference_extraction, .parsed_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .required_authority_inputs, .required_authority_observations, .required_authority_result, .specification_support_review }, .produces = &.{.source_omission_repair}, .replaces = &.{}, .invalidates = &.{}, .side_effect = .none };
    pub fn execute(_: Action, a: std.mem.Allocator, extraction: ex.Facts, parsed: r.Parsed, ctx: Context) (ex.Error || rec.Error)!loss.Repair {
        const selected = try loss.select(a, ctx.inputs, extraction.support);
        return .{ .authorization = switch (selected.location) {
            .unlocalized => return error.InvalidAtomicRepair,
            .extraction_claim, .token_classification => .{ .extraction = try ex.authorize(a, extraction) },
            .reconciliation_signal, .reconciliation_disposition => .{ .reconciliation = try rec.authorize(a, parsed, ctx, extraction.support) },
        } };
    }
};
