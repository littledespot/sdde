const support = @import("../../domain/specification_support.zig");
const repair = @import("../../domain/specification_support_repair.zig");
const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");

const authority = @import("../../domain/required_authority.zig");
const p = @import("../../domain/specification_provenance.zig");
const retention = @import("../../domain/specification_review_retention.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "merge-specification-support-repair", .kind = .action, .requires = &.{ .required_authority_inputs, .specification_support_review, .specification_review_history, .model_request_identity_ledger, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .specification_support_repair }, .produces = &.{}, .replaces = &.{ .specification_support_review, .specification_review_history }, .invalidates = &.{.specification_support_repair}, .side_effect = .none };
    normalizer: @import("../../ports/unicode_normalizer.zig").Normalizer,
    pub fn execute(self: Action, comptime purpose: support.Purpose, allocator: std.mem.Allocator, inputs: authority.Inputs, context: p.Context, candidate: support.Contract(purpose).Candidate, state: repair.Contract(purpose).State, history: retention.History, ledger: *const @import("../../domain/model_request_identity.zig").ModelRequestIdentityLedger) (repair.Contract(purpose).Error || retention.Error)!struct { collection: support.Contract(purpose).Collection, history: retention.History } {
        var canonical = try @import("../../domain/typed_text.zig").CanonicalText.fromInputs(allocator, self.normalizer, context.inputs);
        defer canonical.deinit(allocator);
        const result = try repair.Contract(purpose).merge(allocator, canonical, inputs, context, candidate, state.authorization, if (state.response) |response| response.value else null, if (state.response) |response| response.origin else null);
        return .{ .collection = result, .history = if (purpose == .source) try retention.observe(allocator, history, inputs, context, result, ledger) else history };
    }
};
