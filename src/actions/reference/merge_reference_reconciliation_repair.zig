const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/reference_reconciliation_repair.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "merge-reference-reconciliation-repair", .kind = .action, .requires = &.{ .parsed_reference_reconciliation, .reference_reconciliation_repair, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain }, .produces = &.{}, .replaces = &.{.parsed_reference_reconciliation}, .invalidates = &.{.reference_reconciliation_repair}, .side_effect = .none };
    normalizer: @import("../../ports/unicode_normalizer.zig").Normalizer,
    pub fn execute(self: Action, a: std.mem.Allocator, parsed: r.Parsed, context: @import("../../domain/reference_reconciliation_validation.zig").TextContext, authorization: repair.Authorization, replacement: ?repair.Replacement, origin: ?@import("../../domain/model_candidate_origin.zig").Origin) repair.Error!r.Parsed {
        var canonical = try @import("../../domain/typed_text.zig").CanonicalText.fromInputs(a, self.normalizer, context.inputs);
        defer canonical.deinit(a);
        return repair.merge(a, canonical, parsed, context, authorization, replacement, origin);
    }
};
