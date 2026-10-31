const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const retention = @import("../../domain/specification_review_retention.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "reuse-specification-review", .kind = .action, .requires = &.{ .specification_review_history, .required_authority_inputs, .specification_support_review, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .model_request_identity_ledger, .packet_guidance }, .produces = &.{}, .replaces = &.{ .specification_support_review, .specification_review_history }, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, history: retention.History, inputs: @import("../../domain/required_authority.zig").Inputs, context: @import("../../domain/specification_provenance.zig").Context, guidance: *const @import("../../domain/packet_guidance.zig").Guidance, prior: ?@import("../../domain/specification_support.zig").Source.Collection, selection: @import("../../domain/model_request_handoff.zig").Selection, ledger: *const @import("../../domain/model_request_identity.zig").ModelRequestIdentityLedger) retention.Error!?struct { collection: @import("../../domain/specification_support.zig").Source.Collection, history: retention.History } {
        const result = try retention.reuse(allocator, history, inputs, context, guidance, prior, selection, ledger) orelse return null;
        return .{ .collection = result, .history = try retention.observe(allocator, history, inputs, context, result, ledger) };
    }
};
