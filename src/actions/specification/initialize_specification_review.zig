const pipeline = @import("../../domain/pipeline.zig");
const a = @import("../../domain/required_authority.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "initialize-specification-review", .kind = .action, .requires = &.{ .required_authority_inputs, .specification_review_history, .model_request_identity_ledger }, .produces = &.{.specification_support_review}, .side_effect = .none };
    pub fn execute(_: Action, allocator: @import("std").mem.Allocator, inputs: a.Inputs, history: @import("../../domain/specification_review_retention.zig").History, ledger: *const @import("../../domain/model_request_identity.zig").ModelRequestIdentityLedger) @import("../../domain/specification_review_retention.zig").Error!@import("../../domain/specification_review.zig").Progress {
        if (!@import("../../domain/specification_support.zig").Source.acceptsProjection(inputs.projection) or inputs.evidence.len != 0 or inputs.candidates.len != 0) return error.InvalidRequiredAuthority;
        return if (try @import("../../domain/specification_review_retention.zig").restart(allocator, history, inputs, ledger)) |result| .{ .source = result } else .initial;
    }
};
