const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
const clarification = @import("../../domain/clarification_inputs.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "apply-clarification-answers", .kind = .action, .requires = &.{ .reference_reconciliation_records, .citable_reference_inputs, .clarification_inputs }, .produces = &.{.answered_reference_reconciliation_records}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, sources: r.evidence.Inputs, answers: clarification.Inputs, records: r.Records) (r.Error || error{InvalidClarificationInput})!r.Records {
        return @import("../../domain/answered_reconciliation.zig").apply(allocator, sources, records, try @import("../../domain/clarification_resolution.zig").choices(allocator, answers.state));
    }
};
