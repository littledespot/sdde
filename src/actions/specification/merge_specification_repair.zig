const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const repair = @import("../../domain/specification_repair.zig");
const session = @import("../../domain/specification_session.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "merge-specification-repair", .kind = .action, .requires = &.{ .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .specification_generation_session, .parsed_specification_unit, .specification_repair_authorization }, .produces = &.{}, .replaces = &.{.parsed_specification_unit}, .invalidates = &.{ .validated_specification_unit, .specification_repair_authorization }, .side_effect = .none };
    normalizer: @import("../../ports/unicode_normalizer.zig").Normalizer,
    pub fn execute(self: Action, allocator: std.mem.Allocator, current: session.Session, context: @import("../../domain/specification_provenance.zig").Context, candidate: repair.Candidate, authorization: repair.Authorization, replacement: ?repair.Replacement, origin: ?@import("../../domain/model_candidate_origin.zig").Origin) repair.Error!repair.Candidate {
        var canonical = try @import("../../domain/typed_text.zig").CanonicalText.fromInputs(allocator, self.normalizer, context.inputs);
        defer canonical.deinit(allocator);
        return repair.merge(allocator, canonical, current, context, candidate, authorization, replacement, origin);
    }
};
