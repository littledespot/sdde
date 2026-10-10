//! Source-review wire values. Native evidence is reconstructed from the bound
//! requirement; stored findings retain the full canonical review contract.
const std = @import("std");
const a = @import("required_authority.zig");
const r = @import("reference_reconciliation.zig");
const SourceId = @import("reference_identity.zig").SourceId;
const loss = @import("source_omission.zig").Location;
const evidence = @import("specification_support_evidence.zig");
const codec = @import("model_candidate_json.zig");
const json = @import("strict_json.zig");

pub const Decision = enum {
    supported,
    ambiguous,
    conflicting,
    unsupported,
    candidate_omission,
    inconclusive,
    not_applicable,

    pub fn finding(self: Decision) a.Finding {
        return switch (self) {
            .not_applicable => .supported,
            inline else => |value| @field(a.Finding, @tagName(value)),
        };
    }
    pub fn fromFinding(value: a.Finding) error{}!Decision {
        return switch (value) {
            inline else => |tag| @field(Decision, @tagName(tag)),
        };
    }
};
pub const Canonical = struct {
    loss: loss = .{ .unlocalized = .{} },
    loss_comparison: ?@import("source_omission.zig").Comparison = null,
    kind: Decision,
    provenance: @import("specification.zig").Selection,
    source_ids: []const SourceId,
    detail: []const u8,
    question: ?[]const u8 = null,
};

pub fn fixedClaims(required: evidence.Requirements) ?[]const r.ClaimId {
    return required.rule(.supported, .{ .unlocalized = .{} }).fixedClaims();
}

const Positive = struct { source_ids: []const SourceId, detail: []const u8 };
const Question = struct { source_ids: []const SourceId, detail: []const u8, question: []const u8 };
const Explanation = struct { source_ids: []const SourceId, detail: []const u8 };
const Omission = struct { source_ids: []const SourceId, detail: []const u8 };

pub const Value = union(enum) {
    supported: Positive,
    ambiguous: Question,
    conflicting: Question,
    unsupported: Question,
    candidate_omission: Omission,
    inconclusive: Explanation,
    not_applicable: Positive,
};

/// Resolve only subject-bound or diagnostic claims. An unlocalized negative
/// finding may use source-only evidence, never an arbitrary eligible subset.
fn claimsFor(required: evidence.Requirements, kind: Decision, location: loss) json.Error![]const r.ClaimId {
    if (required.rule(kind.finding(), location).fixedClaims()) |claims| return claims;
    if (kind == .candidate_omission) return &.{};
    if (required.supported_provenance) |provenance| return provenance.claim_ids;
    if (required.positive_claims == .exact_set) return required.eligible_claim_ids;
    if ((kind == .supported or kind == .not_applicable) and required.eligible_claim_ids.len != 0) return error.InvalidJsonDocument;
    if (required.eligible_claim_ids.len == 1) return required.eligible_claim_ids;
    if (kind != .supported and kind != .not_applicable) return &.{};
    return error.InvalidJsonDocument;
}

pub fn decode(a_alloc: std.mem.Allocator, bytes: []const u8, required: evidence.Requirements) json.Error!Canonical {
    const value = try codec.decode(Value, a_alloc, bytes);
    const kind: Decision = switch (value) {
        inline else => |_, tag| @field(Decision, @tagName(tag)),
    };
    const location: loss = .{ .unlocalized = .{} };
    const claims = try claimsFor(required, kind, location);
    const selected: @import("specification.zig").Selection = .{ .claim_ids = claims, .clarification_response_ids = &.{} };
    return switch (value) {
        .supported, .not_applicable => |positive| .{ .kind = kind, .provenance = selected, .source_ids = positive.source_ids, .detail = positive.detail },
        .ambiguous, .conflicting, .unsupported => |negative| .{ .kind = kind, .provenance = selected, .source_ids = negative.source_ids, .detail = negative.detail, .question = negative.question },
        .candidate_omission => |negative| .{ .kind = kind, .provenance = selected, .source_ids = negative.source_ids, .detail = negative.detail, .loss = location },
        .inconclusive => |negative| .{ .kind = kind, .provenance = selected, .source_ids = negative.source_ids, .detail = negative.detail },
    };
}

pub fn bindLoss(required: evidence.Requirements, value: Canonical, assessment: @import("source_omission.zig").Assessment) json.Error!Canonical {
    if (value.kind != .candidate_omission) return error.InvalidJsonDocument;
    var bound = value;
    switch (assessment) {
        .unlocalized => {
            bound.loss = .{ .unlocalized = .{} };
            bound.loss_comparison = null;
        },
        .candidate => {
            bound.loss = .{ .candidate = .{} };
            bound.loss_comparison = null;
        },
        .localized => |selected| {
            if (!@import("source_omission.zig").isUpstream(selected.location)) return error.InvalidJsonDocument;
            bound.loss = selected.location;
            bound.loss_comparison = selected.comparison;
        },
    }
    bound.provenance.claim_ids = try claimsFor(required, .candidate_omission, bound.loss);
    return bound;
}

/// Test fixtures project a canonical finding into the current model contract.
/// Production admission always decodes and validates the response again.
pub fn encode(a_alloc: std.mem.Allocator, value: Canonical, required: evidence.Requirements) json.Error![]const u8 {
    _ = required;
    const positive: Positive = .{ .source_ids = value.source_ids, .detail = value.detail };
    const selected: Value = switch (value.kind) {
        .supported => .{ .supported = positive },
        .not_applicable => .{ .not_applicable = positive },
        .ambiguous => .{ .ambiguous = .{ .source_ids = value.source_ids, .detail = value.detail, .question = value.question orelse "" } },
        .conflicting => .{ .conflicting = .{ .source_ids = value.source_ids, .detail = value.detail, .question = value.question orelse "" } },
        .unsupported => .{ .unsupported = .{ .source_ids = value.source_ids, .detail = value.detail, .question = value.question orelse "" } },
        .candidate_omission => .{ .candidate_omission = .{ .source_ids = value.source_ids, .detail = value.detail } },
        .inconclusive => .{ .inconclusive = .{ .source_ids = value.source_ids, .detail = value.detail } },
    };
    return codec.encode(Value, a_alloc, selected);
}

pub const Selection = struct { source_ids: []const SourceId };
pub fn decodeSelection(a_alloc: std.mem.Allocator, bytes: []const u8, claims: []const r.ClaimId) json.Error!struct { provenance: @import("specification.zig").Selection, source_ids: []const SourceId } {
    const selected = try codec.decode(Selection, a_alloc, bytes);
    return .{ .provenance = .{ .claim_ids = claims, .clarification_response_ids = &.{} }, .source_ids = selected.source_ids };
}
