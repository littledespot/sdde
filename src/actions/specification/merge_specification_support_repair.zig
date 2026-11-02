const support = @import("../../domain/specification_support.zig");
const repair = @import("../../domain/specification_support_repair.zig");
const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");

const authority = @import("../../domain/required_authority.zig");
const p = @import("../../domain/specification_provenance.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "merge-specification-support-repair", .kind = .action, .requires = &.{ .required_authority_inputs, .specification_support_review, .model_request_identity_ledger, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .specification_support_repair, .packet_guidance }, .produces = &.{}, .replaces = &.{.specification_support_review}, .invalidates = &.{.specification_support_repair}, .side_effect = .none };
    normalizer: @import("../../ports/unicode_normalizer.zig").Normalizer,
    pub fn execute(self: Action, allocator: std.mem.Allocator, inputs: authority.Inputs, context: p.Context, guidance: *const @import("../../domain/packet_guidance.zig").Guidance, candidate: support.Source.Candidate, state: repair.Source.State) repair.Source.Error!support.Source.Collection {
        var canonical = try @import("../../domain/typed_text.zig").CanonicalText.fromInputs(allocator, self.normalizer, context.inputs);
        defer canonical.deinit(allocator);
        return repair.Source.merge(allocator, canonical, inputs, context, guidance, candidate, state.authorization, if (state.response) |response| response.value else null, if (state.response) |response| response.origin else null);
    }
};
