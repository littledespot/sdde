//! Diagnostic workload attribution from closed native request identities.
//! These categories measure consumption; they create no workflow authority or
//! assertion about the semantic stage that first lost a source obligation.
const std = @import("std");
const identity = @import("../../../src/domain/model_request_identity.zig");
pub const OwnerKind = std.meta.Tag(identity.ImmutableUnitOwnerId);
pub const Purpose = identity.RequestPurposeKind;
pub const Stage = enum { extraction_grouping, generation, review, repair, clarification, other };

pub fn classify(purpose: Purpose, owner: OwnerKind) Stage {
    return switch (purpose) {
        .atomic_repair => .repair,
        .semantic_review => .review,
        .clarification_resolution => .clarification,
        .context_followup => .other,
        .initial_generation => switch (owner) {
            .reference_chunk, .reference_global => .extraction_grouping,
            .specification_unit => .generation,
            .semantic_review => .review,
            .workflow_step, .plan_unit, .task_cluster, .implementation_operation => .other,
        },
    };
}

test "baseline stage attribution uses native purpose and owner without operation names" {
    for (std.meta.tags(OwnerKind)) |owner| {
        try std.testing.expectEqual(Stage.repair, classify(.atomic_repair, owner));
        try std.testing.expectEqual(Stage.review, classify(.semantic_review, owner));
        try std.testing.expectEqual(Stage.clarification, classify(.clarification_resolution, owner));
        try std.testing.expectEqual(Stage.other, classify(.context_followup, owner));
        const expected: Stage = switch (owner) {
            .reference_chunk, .reference_global => .extraction_grouping,
            .specification_unit => .generation,
            .semantic_review => .review,
            .workflow_step, .plan_unit, .task_cluster, .implementation_operation => .other,
        };
        try std.testing.expectEqual(expected, classify(.initial_generation, owner));
    }
}
